import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import 'local_database_service.dart';

class SurveyService {
  final SupabaseClient client = Supabase.instance.client;

  // Sign In with username or email & password
  Future<AuthResponse> signIn(String userInput, String password) async {
    // If user enters pure username (e.g. 'agent'), map to internal email
    final email = userInput.contains('@')
        ? userInput.trim()
        : '${userInput.trim().toLowerCase()}@qualitysurvey.com';

    return await client.auth.signInWithPassword(email: email, password: password);
  }

  // Sign Out
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Current User Profile
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    final res = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    return res;
  }

  // Fetch Submissions Count for a Specific AC
  Future<Map<String, int>> getACStats(int acId) async {
    try {
      final user = client.auth.currentUser;
      final totalRes = await client
          .from('survey_responses')
          .select('id')
          .eq('ac_id', acId);

      int total = (totalRes as List).length;

      int myCount = 0;
      if (user != null) {
        final myRes = await client
            .from('survey_responses')
            .select('id')
            .eq('ac_id', acId)
            .eq('surveyor_id', user.id);
        myCount = (myRes as List).length;
      }

      return {'total': total, 'myCount': myCount};
    } catch (_) {
      return {'total': 0, 'myCount': 0};
    }
  }

  // Fetch coordinates of all submitted surveys for a specific AC
  Future<List<Map<String, double>>> getACSurveyLocations(int acId) async {
    try {
      final res = await client
          .from('survey_responses')
          .select('answers')
          .eq('ac_id', acId);

      final List<Map<String, double>> points = [];
      for (var row in res as List) {
        final answers = row['answers'];
        if (answers != null && answers is Map) {
          final loc = answers['location'];
          if (loc != null && loc['latitude'] != null && loc['longitude'] != null) {
            final lat = (loc['latitude'] as num).toDouble();
            final lng = (loc['longitude'] as num).toDouble();
            points.add({'lat': lat, 'lng': lng});
          }
        }
      }
      return points;
    } catch (_) {
      return [];
    }
  }

  // Upload Audio Recording to Supabase Storage
  Future<String> uploadAudio(File audioFile, int acId) async {
    final fileName = '${acId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '$acId/$fileName';

    await client.storage.from(SupabaseConstants.audioBucket).upload(path, audioFile);
    return client.storage.from(SupabaseConstants.audioBucket).getPublicUrl(path);
  }

  // Submit Survey Response
  Future<void> submitSurvey({
    required String districtName,
    required int acId,
    required String? respondentName,
    required String? respondentPhone,
    required int? respondentAge,
    required String? respondentGender,
    required String surveyStatus,
    required Map<String, dynamic> answers,
    required Map<String, dynamic>? location,
    required String audioFileUrl,
    required int recordingDuration,
  }) async {
    final user = client.auth.currentUser;

    // Store location and district_name inside answers JSONB so it never fails
    // regardless of whether extra top-level columns exist in schema
    final Map<String, dynamic> enrichedAnswers = Map<String, dynamic>.from(answers);
    if (districtName.isNotEmpty) {
      enrichedAnswers['district_name'] = districtName;
    }
    if (location != null) {
      enrichedAnswers['location'] = location;
    }

    final payload = {
      'surveyor_id': user?.id,
      'ac_id': acId,
      'respondent_name': respondentName,
      'respondent_phone': respondentPhone,
      'respondent_age': respondentAge,
      'respondent_gender': respondentGender,
      'survey_status': surveyStatus,
      'answers': enrichedAnswers,
      'audio_file_url': audioFileUrl,
      'recording_duration_seconds': recordingDuration,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
    };

    await client.from('survey_responses').insert(payload);
  }

  // Auto-sync all local drafts to Supabase
  Future<int> syncOfflineDrafts() async {
    final drafts = await LocalDatabaseService.instance.getDrafts();
    if (drafts.isEmpty) return 0;

    int syncedCount = 0;
    for (var draft in drafts) {
      try {
        final draftId = draft['id'] as int;
        final acId = draft['ac_id'] as int;
        final audioFile = File(draft['local_audio_path'] as String);

        String audioUrl = '';
        if (await audioFile.exists()) {
          audioUrl = await uploadAudio(audioFile, acId);
        }

        await submitSurvey(
          districtName: draft['district_name'] as String,
          acId: acId,
          respondentName: draft['respondent_name'] as String?,
          respondentPhone: draft['respondent_phone'] as String?,
          respondentAge: draft['respondent_age'] as int?,
          respondentGender: draft['respondent_gender'] as String?,
          surveyStatus: draft['survey_status'] as String? ?? 'completed',
          answers: json.decode(draft['answers'] as String),
          location: json.decode(draft['location'] as String),
          audioFileUrl: audioUrl,
          recordingDuration: draft['recording_duration'] as int? ?? 0,
        );

        await LocalDatabaseService.instance.deleteDraft(draftId);
        syncedCount++;
      } catch (_) {
        // If still offline, stop batch and try next time
        break;
      }
    }
    return syncedCount;
  }
}
