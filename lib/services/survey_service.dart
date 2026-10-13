import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

class SurveyService {
  final SupabaseClient client = Supabase.instance.client;

  // Sign In with email/username & password
  Future<AuthResponse> signIn(String email, String password) async {
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

  // Upload Audio Recording to Supabase Storage
  Future<String> uploadAudio(File audioFile, int acId) async {
    final fileName = '${acId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '$acId/$fileName';

    await client.storage.from(SupabaseConstants.audioBucket).upload(path, audioFile);
    return client.storage.from(SupabaseConstants.audioBucket).getPublicUrl(path);
  }

  // Submit Survey Response
  Future<void> submitSurvey({
    required int districtId,
    required int acId,
    required String? respondentName,
    required String? respondentPhone,
    required int? respondentAge,
    required String? respondentGender,
    required String surveyStatus,
    required Map<String, dynamic> answers,
    required String audioFileUrl,
    required int recordingDuration,
  }) async {
    final user = client.auth.currentUser;

    await client.from('survey_responses').insert({
      'surveyor_id': user?.id,
      'district_id': districtId,
      'ac_id': acId,
      'respondent_name': respondentName,
      'respondent_phone': respondentPhone,
      'respondent_age': respondentAge,
      'respondent_gender': respondentGender,
      'survey_status': surveyStatus,
      'answers': answers,
      'audio_file_url': audioFileUrl,
      'recording_duration_seconds': recordingDuration,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
