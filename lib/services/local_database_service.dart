import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabaseService {
  static final LocalDatabaseService instance = LocalDatabaseService._init();
  static Database? _database;

  LocalDatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('quality_survey_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE offline_drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        district_name TEXT NOT NULL,
        ac_id INTEGER NOT NULL,
        respondent_name TEXT,
        respondent_phone TEXT,
        respondent_age INTEGER,
        respondent_gender TEXT,
        survey_status TEXT,
        answers TEXT NOT NULL,
        location TEXT NOT NULL,
        local_audio_path TEXT NOT NULL,
        recording_duration INTEGER,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertDraft({
    required String districtName,
    required int acId,
    required String? respondentName,
    required String? respondentPhone,
    required int? respondentAge,
    required String? respondentGender,
    required String surveyStatus,
    required Map<String, dynamic> answers,
    required Map<String, dynamic> location,
    required String localAudioPath,
    required int recordingDuration,
  }) async {
    final db = await instance.database;
    return await db.insert('offline_drafts', {
      'district_name': districtName,
      'ac_id': acId,
      'respondent_name': respondentName,
      'respondent_phone': respondentPhone,
      'respondent_age': respondentAge,
      'respondent_gender': respondentGender,
      'survey_status': surveyStatus,
      'answers': json.encode(answers),
      'location': json.encode(location),
      'local_audio_path': localAudioPath,
      'recording_duration': recordingDuration,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getDrafts({int? acId}) async {
    final db = await instance.database;
    if (acId != null) {
      return await db.query('offline_drafts', where: 'ac_id = ?', whereArgs: [acId], orderBy: 'id DESC');
    }
    return await db.query('offline_drafts', orderBy: 'id DESC');
  }

  Future<int> deleteDraft(int id) async {
    final db = await instance.database;
    return await db.delete('offline_drafts', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getDraftCount({int? acId}) async {
    final db = await instance.database;
    final res = acId != null
        ? await db.rawQuery('SELECT COUNT(*) as count FROM offline_drafts WHERE ac_id = ?', [acId])
        : await db.rawQuery('SELECT COUNT(*) as count FROM offline_drafts');
    return Sqflite.firstIntValue(res) ?? 0;
  }
}
