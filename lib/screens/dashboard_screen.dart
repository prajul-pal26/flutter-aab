import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/survey_service.dart';
import '../services/local_database_service.dart';
import 'survey_form_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _surveyService = SurveyService();

  List<String> _districts = [];
  List<Map<String, dynamic>> _allConstituencies = [];
  List<Map<String, dynamic>> _filteredConstituencies = [];

  String? _selectedDistrict;
  Map<String, dynamic>? _selectedAC;

  bool _isLoadingData = true;
  bool _isLoadingStats = false;
  int _totalACSubmissions = 0;
  int _mySubmissions = 0;

  // GPS Live State
  bool _isGpsLive = false;
  Position? _currentPosition;
  String _gpsStatusText = 'जीपीएस सिग्नल खोजा जा रहा है... (Acquiring GPS)';
  StreamSubscription<Position>? _positionStreamSubscription;

  // Drafts State
  int _draftCount = 0;
  bool _isSyncingDrafts = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _loadConstituencyData();
    _initGpsTracking();
    _loadDraftCount();
    _initConnectivityListener();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _autoSyncDrafts();
      }
    });
  }

  Future<void> _loadDraftCount() async {
    final count = await LocalDatabaseService.instance.getDraftCount();
    if (mounted) setState(() => _draftCount = count);
  }

  Future<void> _autoSyncDrafts() async {
    if (_draftCount == 0 || _isSyncingDrafts) return;
    setState(() => _isSyncingDrafts = true);

    final synced = await _surveyService.syncOfflineDrafts();
    await _loadDraftCount();

    if (synced > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$synced ऑफलाइन ड्राफ्ट सफलतापूर्वक सिंक हुए!'),
          backgroundColor: Colors.green,
        ),
      );
      if (_selectedAC != null) _onACChanged(_selectedAC);
    }

    if (mounted) setState(() => _isSyncingDrafts = false);
  }

  Future<void> _initGpsTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isGpsLive = false;
            _gpsStatusText = 'डिवाइस का लोकेशन (GPS) बंद है। कृपया चालू करें।';
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isGpsLive = false;
              _gpsStatusText = 'लोकेशन की अनुमति अस्वीकार की गई है।';
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isGpsLive = false;
            _gpsStatusText = 'कृपया सेटिंग्स में जाकर लोकेशन अनुमति प्रदान करें।';
          });
        }
        return;
      }

      // Initial quick position
      try {
        final initialPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        if (mounted) {
          setState(() {
            _isGpsLive = true;
            _currentPosition = initialPos;
            _gpsStatusText =
                'GPS लाइव: ${initialPos.latitude.toStringAsFixed(5)}, ${initialPos.longitude.toStringAsFixed(5)} (शुद्धता: ${initialPos.accuracy.toStringAsFixed(1)}m)';
          });
        }
      } catch (_) {}

      // Live position stream
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _isGpsLive = true;
            _currentPosition = position;
            _gpsStatusText =
                'GPS लाइव: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} (±${position.accuracy.toStringAsFixed(1)}m)';
          });
        }
      }, onError: (_) {
        if (mounted) {
          setState(() {
            _isGpsLive = false;
            _gpsStatusText = 'GPS सिग्नल अनुपलब्ध है।';
          });
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isGpsLive = false;
          _gpsStatusText = 'GPS स्थिति प्राप्त करने में त्रुटि।';
        });
      }
    }
  }

  Future<void> _loadConstituencyData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/up_75_districts_403_acs.json');
      final data = json.decode(jsonString);

      setState(() {
        _districts = List<String>.from(data['districts']);
        _allConstituencies = List<Map<String, dynamic>>.from(data['constituencies']);
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  void _onDistrictChanged(String? district) {
    setState(() {
      _selectedDistrict = district;
      _selectedAC = null;
      _totalACSubmissions = 0;
      _mySubmissions = 0;
      if (district != null) {
        _filteredConstituencies =
            _allConstituencies.where((ac) => ac['district'] == district).toList();
      } else {
        _filteredConstituencies = [];
      }
    });
  }

  Future<void> _onACChanged(Map<String, dynamic>? ac) async {
    setState(() {
      _selectedAC = ac;
    });

    if (ac != null) {
      setState(() => _isLoadingStats = true);
      final stats = await _surveyService.getACStats(ac['ac_no']);
      setState(() {
        _totalACSubmissions = stats['total'] ?? 0;
        _mySubmissions = stats['myCount'] ?? 0;
        _isLoadingStats = false;
      });
    }
  }

  void _navigateToFormDirectly() {
    if (_selectedDistrict == null || _selectedAC == null || !_isGpsLive) return;

    // Directly navigate without any bridge dialog popup
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurveyFormScreen(
          districtName: _selectedDistrict!,
          acData: _selectedAC!,
        ),
      ),
    ).then((_) {
      if (_selectedAC != null) _onACChanged(_selectedAC);
      _loadDraftCount();
      _autoSyncDrafts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool canStartForm = _selectedDistrict != null && _selectedAC != null && _isGpsLive;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Quality Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _surveyService.signOut();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
        // GPS Live Status Bar (Matching audio bar style)
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Container(
            color: _isGpsLive ? const Color(0xFF047857) : const Color(0xFFB91C1C),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _isGpsLive ? Icons.location_on : Icons.location_off,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isGpsLive ? 'जीपीएस लाइव (GPS Active)' : 'जीपीएस बंद / प्रतीक्षारत',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  _isGpsLive
                      ? '±${_currentPosition?.accuracy.toStringAsFixed(1) ?? '0'}m'
                      : 'OFFLINE',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // GPS Status Banner Text
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isGpsLive ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isGpsLive ? Colors.green.shade200 : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isGpsLive ? Icons.check_circle : Icons.warning_amber_rounded,
                          color: _isGpsLive ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _gpsStatusText,
                            style: TextStyle(
                              color: _isGpsLive ? Colors.green.shade800 : Colors.red.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'विधानसभा क्षेत्र चयन',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 14),

                  // District Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedDistrict,
                        hint: const Text('जिला चुनें (Select District)'),
                        items: _districts.map((d) {
                          return DropdownMenuItem<String>(value: d, child: Text(d));
                        }).toList(),
                        onChanged: _onDistrictChanged,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // AC Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        isExpanded: true,
                        value: _selectedAC,
                        hint: Text(
                          _selectedDistrict == null
                              ? 'पहले जिला चुनें'
                              : 'विधानसभा चुनें (${_filteredConstituencies.length} ACs)',
                        ),
                        items: _filteredConstituencies.map((ac) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: ac,
                            child: Text(
                              '[${ac['ac_no']}] ${ac['ac_name_hi']} (${ac['ac_name_en']})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _selectedDistrict == null ? null : _onACChanged,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // FORM BUTTON (Disabled until GPS is LIVE and District/AC selected)
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canStartForm ? const Color(0xFF1E3A8A) : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: canStartForm ? 3 : 0,
                      ),
                      onPressed: canStartForm ? _navigateToFormDirectly : null,
                      icon: const Icon(Icons.assignment_add),
                      label: Text(
                        !_isGpsLive
                            ? 'GPS सिग्नल की प्रतीक्षा है... (GPS Disabled)'
                            : 'FORM भरें (Start Survey)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Live Metadata & Stats Card
                  if (_selectedAC != null) ...[
                    const Text(
                      'AC लाइव डेटा एवं सांख्यिकी',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: _isLoadingStats
                            ? const Center(child: CircularProgressIndicator())
                            : Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatItem(
                                          title: 'कुल फॉर्म (Total)',
                                          value: '$_totalACSubmissions',
                                          color: Colors.blue.shade700,
                                          icon: Icons.description_outlined,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatItem(
                                          title: 'आपके फॉर्म (My)',
                                          value: '$_mySubmissions',
                                          color: Colors.green.shade700,
                                          icon: Icons.person_pin_circle_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'लोकसभा: ${_selectedAC!['lok_sabha'] ?? '-'}',
                                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                      Text(
                                        'श्रेणी: ${_selectedAC!['seat_category'] ?? '-'}',
                                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],

                  // OFFLINE DRAFT SECTION (Directly at the bottom of metadata)
                  const SizedBox(height: 20),
                  Card(
                    color: _draftCount > 0 ? Colors.amber.shade50 : Colors.grey.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _draftCount > 0 ? Colors.amber.shade400 : Colors.grey.shade300,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.offline_pin_rounded,
                                    color: _draftCount > 0 ? Colors.amber.shade800 : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'ऑफलाइन ड्राफ्ट्स (Offline Queue)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _draftCount > 0 ? Colors.amber.shade700 : Colors.grey,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$_draftCount लंबित',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _draftCount > 0
                                ? 'नेटवर्क उपलब्ध होते ही यह डेटा ऑडियो सहित Supabase पर स्वतः अपलोड हो जाएगा।'
                                : 'सभी फॉर्म सिंक हो चुके हैं। कोई भी स्थानीय ड्राफ्ट लंबित नहीं है।',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          if (_draftCount > 0) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber.shade800,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _isSyncingDrafts ? null : _autoSyncDrafts,
                                icon: _isSyncingDrafts
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.sync, size: 18),
                                label: Text(
                                  _isSyncingDrafts ? 'सिंक हो रहा है...' : 'अभी सिंक करें (Sync Now)',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
