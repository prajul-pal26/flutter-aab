import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:geolocator/geolocator.dart';
import '../services/survey_service.dart';
import '../services/local_database_service.dart';

class SurveyFormScreen extends StatefulWidget {
  final String districtName;
  final Map<String, dynamic> acData;

  const SurveyFormScreen({
    super.key,
    required this.districtName,
    required this.acData,
  });

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen> {
  final _surveyService = SurveyService();
  final _audioRecorder = AudioRecorder();

  List<dynamic> _questions = [];
  bool _isLoadingQuestions = true;

  // Recording State
  bool _isRecording = false;
  String? _recordedFilePath;
  Timer? _timer;
  int _secondsRecorded = 0;

  // GPS Live State in Page 3
  bool _isGpsActive = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;

  // Form Answers State
  final Map<int, dynamic> _answers = {};
  final Map<int, TextEditingController> _textControllers = {};
  final Map<int, TextEditingController> _commentControllers = {};

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _startAudioRecording();
    _initLiveLocationTracking();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    if (_isRecording) {
      _audioRecorder.stop();
      _audioRecorder.dispose();
    }
    for (var c in _textControllers.values) {
      c.dispose();
    }
    for (var c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Real-time GPS Tracking in Page 3
  Future<void> _initLiveLocationTracking() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      if (pos != null && mounted) {
        setState(() {
          _isGpsActive = true;
          _currentPosition = pos;
        });
      }

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _isGpsActive = true;
            _currentPosition = position;
          });
        }
      }, onError: (_) {
        if (mounted) setState(() => _isGpsActive = false);
      });
    } catch (_) {
      if (mounted) setState(() => _isGpsActive = false);
    }
  }

  // Audio Recording Flow
  Future<void> _startAudioRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) return;

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordedFilePath = path;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() => _secondsRecorded++);
      });
    } catch (_) {}
  }

  Future<void> _loadQuestions() async {
    try {
      final jsonString = await rootBundle.loadString('assets/questions.json');
      setState(() {
        _questions = json.decode(jsonString);
        _isLoadingQuestions = false;
      });
    } catch (e) {
      setState(() => _isLoadingQuestions = false);
    }
  }

  bool _isQuestionVisible(Map<String, dynamic> q) {
    if (!q.containsKey('depends_on')) return true;

    final dep = q['depends_on'] as Map<String, dynamic>;
    final parentId = dep['question_id'] as int;
    final parentAns = _answers[parentId];

    if (parentAns == null) return false;

    if (dep.containsKey('equals')) {
      return parentAns == dep['equals'];
    }
    if (dep.containsKey('matches_any')) {
      final list = dep['matches_any'] as List;
      return list.contains(parentAns);
    }
    if (dep.containsKey('contains')) {
      return parentAns.toString().contains(dep['contains']);
    }
    return true;
  }

  List<String> _getCasteList(dynamic parentVal) {
    if (parentVal == 'सामान्य वर्ग') {
      return ['ब्राह्मण', 'राजपूत/ठाकुर', 'वैश्य/बनिया', 'कायस्थ', 'भूमिहार', 'त्यागी', 'अन्य'];
    } else if (parentVal == 'अन्य पिछड़ा वर्ग') {
      return ['यादव', 'कुर्मी', 'मौर्य/कुशवाहा/शाक्य/सैनी', 'लोध/लोधी', 'जाट', 'गुर्जर', 'निषाद/कश्यप/मल्लाह', 'राजभर', 'प्रजापति/कुम्हार', 'पाल/बघेल/गडरिया', 'विश्वकर्मा/लोहार/बढ़ई', 'अन्य'];
    } else if (parentVal == 'अनुसूचित जाति') {
      return ['जाटव/चमार', 'पासी', 'कोरी', 'धोबी', 'वाल्मीकि', 'खटीक', 'गोंड', 'अन्य'];
    } else if (parentVal == 'अनुसूचित जनजाति') {
      return ['थारू', 'बुक्सा', 'सहरिया', 'गोंड/धुरिया', 'खरवार', 'अन्य'];
    }
    return ['सामान्य', 'अन्य'];
  }

  Future<void> _handleSubmitSurvey() async {
    // Corner Case Check: Location MUST be active
    if (!_isGpsActive || _currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('जीपीएस सिग्नल सक्रिय होना अनिवार्य है। कृपया लोकेशन ऑन करें।'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Screening check Q1-Q3
    for (int id = 1; id <= 3; id++) {
      if (_answers[id] == 'नहीं (End survey)') {
        _handleScreenOut();
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      _timer?.cancel();
      String? audioPath = _recordedFilePath;
      if (_isRecording) {
        audioPath = await _audioRecorder.stop();
        setState(() => _isRecording = false);
      }

      final Map<String, dynamic> formattedAnswers = {};
      for (var entry in _answers.entries) {
        formattedAnswers['q_${entry.key}'] = entry.value;
      }
      for (var entry in _commentControllers.entries) {
        if (entry.value.text.isNotEmpty) {
          formattedAnswers['q_${entry.key}_comment'] = entry.value.text.trim();
        }
      }

      final locationData = {
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'altitude': _currentPosition!.altitude,
        'accuracy_meters': _currentPosition!.accuracy,
        'speed': _currentPosition!.speed,
        'captured_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Try uploading online
      try {
        String audioUrl = '';
        if (audioPath != null && File(audioPath).existsSync()) {
          audioUrl = await _surveyService.uploadAudio(File(audioPath), widget.acData['ac_no']);
        }

        await _surveyService.submitSurvey(
          districtName: widget.districtName,
          acId: widget.acData['ac_no'],
          respondentName: _textControllers[4]?.text.trim(),
          respondentPhone: _textControllers[7]?.text.trim(),
          respondentAge: int.tryParse(_textControllers[8]?.text.trim() ?? ''),
          respondentGender: _answers[6]?.toString(),
          surveyStatus: 'completed',
          answers: formattedAnswers,
          location: locationData,
          audioFileUrl: audioUrl,
          recordingDuration: _secondsRecorded,
        );

        if (!mounted) return;
        _showSuccessDialog(isOfflineDraft: false);
      } catch (networkError) {
        // CORNER CASE: Offline / No Internet at location
        // Save form response, local audio file path, and GPS to SQLite
        await LocalDatabaseService.instance.insertDraft(
          districtName: widget.districtName,
          acId: widget.acData['ac_no'],
          respondentName: _textControllers[4]?.text.trim(),
          respondentPhone: _textControllers[7]?.text.trim(),
          respondentAge: int.tryParse(_textControllers[8]?.text.trim() ?? ''),
          respondentGender: _answers[6]?.toString(),
          surveyStatus: 'completed',
          answers: formattedAnswers,
          location: locationData,
          localAudioPath: audioPath ?? '',
          recordingDuration: _secondsRecorded,
        );

        if (!mounted) return;
        _showSuccessDialog(isOfflineDraft: true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटि: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog({required bool isOfflineDraft}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOfflineDraft ? Icons.cloud_off_rounded : Icons.check_circle_rounded,
              color: isOfflineDraft ? Colors.amber.shade700 : Colors.green,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              isOfflineDraft ? 'ऑफलाइन ड्राफ्ट सुरक्षित हुआ!' : 'सर्वेक्षण सफलतापूर्वक दर्ज हुआ!',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isOfflineDraft
                  ? 'नेटवर्क न होने के कारण ऑडियो और फॉर्म डिवाइस में सुरक्षित कर लिया गया है। नेटवर्क आते ही यह स्वतः सिंक हो जाएगा।'
                  : 'ऑडियो, GPS लोकेशन और डेटा Supabase पर सुरक्षित रूप से सहेज लिया गया है।',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isOfflineDraft ? Colors.amber.shade800 : const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('वापस डैशबोर्ड पर जाएं'),
          )
        ],
      ),
    );
  }

  void _handleScreenOut() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('सर्वेक्षण समाप्त (Screened Out)'),
        content: const Text('रेस्पोंडेंट पात्रता मानदंडों को पूरा नहीं करते हैं। सर्वेक्षण समाप्त किया जा रहा है।'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('ठीक है (OK)'),
          )
        ],
      ),
    );
  }

  String _formatTimer(int totalSecs) {
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '[${widget.acData['ac_no']}] ${widget.acData['ac_name_hi']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(widget.districtName, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Column(
            children: [
              // Audio Recording Active Bar
              Container(
                color: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'ऑडियो रिकॉर्डिंग चालू है (Audio Active)',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Text(
                      _formatTimer(_secondsRecorded),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Live GPS Bar in 3rd Page
              Container(
                color: _isGpsActive ? const Color(0xFF047857) : const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(_isGpsActive ? Icons.location_on : Icons.location_off, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _isGpsActive ? 'GPS लाइव (Coordinates Locked)' : 'GPS बंद / अनुपलब्ध (Location Lost)',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      _isGpsActive ? '±${_currentPosition?.accuracy.toStringAsFixed(1) ?? '0'}m' : 'DISABLED',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoadingQuestions
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: _questions.length + 1,
              itemBuilder: (context, idx) {
                if (idx == _questions.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30.0),
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isGpsActive ? const Color(0xFF1E3A8A) : Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: _isGpsActive ? 4 : 0,
                        ),
                        // SUBMIT BUTTON DISABLED UNTIL GPS IS ACTIVE
                        onPressed: (_isSubmitting || !_isGpsActive) ? null : _handleSubmitSurvey,
                        child: _isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                !_isGpsActive
                                    ? 'लोकेशन चालू करें (Enable GPS to Submit)'
                                    : 'सबमिट करें (SUBMIT FORM)',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  );
                }

                final q = _questions[idx] as Map<String, dynamic>;
                if (!_isQuestionVisible(q)) return const SizedBox.shrink();

                return _buildQuestionCard(q);
              },
            ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> q) {
    final int id = q['id'];
    final String title = q['title'];
    final String type = q['type'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFF1E3A8A).withOpacity(0.1),
                  child: Text(
                    '$id',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (type == 'subjective') ...[
              _buildSubjectiveField(q),
            ] else if (type == 'single_choice') ...[
              _buildSingleChoiceField(q),
            ] else if (type == 'multiple_choice') ...[
              _buildMultipleChoiceField(q),
            ],

            if (q['has_other_comment'] == true &&
                (_answers[id]?.toString().contains('अन्य') == true ||
                    (_answers[id] is List && (_answers[id] as List).any((e) => e.toString().contains('अन्य'))))) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _commentControllers.putIfAbsent(id, () => TextEditingController()),
                decoration: InputDecoration(
                  labelText: 'कृपया विवरण लिखें (Specify comments)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectiveField(Map<String, dynamic> q) {
    final int id = q['id'];
    final controller = _textControllers.putIfAbsent(id, () => TextEditingController());
    final isPhone = q['keyboard'] == 'phone';
    final isNumber = q['keyboard'] == 'number' || isPhone;

    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: q['placeholder'] ?? 'उत्तर लिखें...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildSingleChoiceField(Map<String, dynamic> q) {
    final int id = q['id'];
    List<String> options = [];

    if (q['dynamic_caste'] == true) {
      final parentVal = _answers[q['parent_question_id']];
      options = _getCasteList(parentVal);
    } else {
      options = List<String>.from(q['options'] ?? []);
    }

    return Column(
      children: options.map((opt) {
        final isSelected = _answers[id] == opt;
        return InkWell(
          onTap: () {
            setState(() {
              _answers[id] = opt;
            });
            if (q['screen_out_on'] == opt) {
              _handleScreenOut();
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E3A8A).withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? const Color(0xFF1E3A8A) : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? const Color(0xFF1E3A8A) : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    opt,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? const Color(0xFF1E3A8A) : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultipleChoiceField(Map<String, dynamic> q) {
    final int id = q['id'];
    final int maxSelect = q['max_select'] ?? 3;
    final List<String> currentSelected = List<String>.from(_answers[id] ?? []);
    final options = List<String>.from(q['options'] ?? []);

    return Column(
      children: options.map((opt) {
        final isChecked = currentSelected.contains(opt);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(opt, style: const TextStyle(fontSize: 13.5)),
          value: isChecked,
          activeColor: const Color(0xFF1E3A8A),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                if (currentSelected.length < maxSelect) {
                  currentSelected.add(opt);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('अधिकतम केवल $maxSelect विकल्प चुने जा सकते हैं'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              } else {
                currentSelected.remove(opt);
              }
              _answers[id] = currentSelected;
            });
          },
        );
      }).toList(),
    );
  }
}
