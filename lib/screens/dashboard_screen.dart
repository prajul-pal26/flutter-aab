import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/survey_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadConstituencyData();
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

  void _showAudioBridgeDialog() {
    if (_selectedDistrict == null || _selectedAC == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.mic, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text('सर्वेक्षण प्रारंभ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'गुणवत्ता सत्यापन (Quality Verification) के लिए ऑडियो रिकॉर्डिंग स्वचालित रूप से शुरू हो रही है।',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Audio Recording starting now...',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                    )
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('रद्द करें', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
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
                });
              },
              child: const Text('फॉर्म शुरू करें (Proceed)'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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

                  // FORM BUTTON (Directly above metadata)
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedAC == null ? Colors.grey : const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                      onPressed: _selectedAC == null ? null : _showAudioBridgeDialog,
                      icon: const Icon(Icons.assignment_add),
                      label: const Text(
                        'FORM भरें (Start Survey)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
