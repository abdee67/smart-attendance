// Location CRUD

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:smartattendance/services/face_service.dart';
import 'package:sqflite/sqflite.dart';
import '../models/attendance.dart';
import '/models/location.dart';
import '/db/dbHelper.dart';

class AttendancedbMethods {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  static final AttendancedbMethods _instance = AttendancedbMethods._internal();
  AttendancedbMethods._internal();
  static AttendancedbMethods get instance => _instance;

  Future<void> saveLocationData(LocationData location) async {
    final db = await dbHelper.database;
    await db.insert(
      'location',
      location.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LocationData?> getLocationData() async {
    final db = await dbHelper.database;
    final maps = await db.query('location', limit: 1);
    if (maps.isEmpty) return null;
    return LocationData.fromJson(maps.first);
  }

  // Attendance CRUD
  Future<void> saveAttendance(AttendanceRecord record) async {
    final db = await dbHelper.database;
    await db.insert('attendance', record.tojson());
  }

  Future<List<AttendanceRecord>> getPendingAttendances() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'attendance',
     where: 'status = ?',
      whereArgs: [AttendanceStatus.absent.index],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => AttendanceRecord.fromJson(map)).toList();
  }

  Future<void> markAsSynced(int id) async {
    final db = await dbHelper.database;
    await db.update(
      'attendance',
      {'is_synced': 1,
      'status': AttendanceStatus.present.index,},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Face Data

Future<void> saveFaceEmbedding(Float32List embedding) async {
  final db = await dbHelper.database;

  if (embedding.length != 128) {
    throw Exception('Invalid embedding length before save: ${embedding.length}');
  }

  final normalized = FaceService.normalizeEmbedding(embedding);

  // Convert Float32List to Uint8List safely
  final bytes = normalized.buffer.asUint8List();

  // Encode as Base64 string
  final base64Str = base64Encode(bytes);

  await db.insert(
    'face_data',
    {'embedding': base64Str},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
Future<Float32List?> getFaceEmbedding() async {
  final db = await dbHelper.database;

  final maps = await db.query('face_data', limit: 1);
  if (maps.isEmpty) return null;

  final base64Str = maps.first['embedding'] as String;

  final bytes = base64Decode(base64Str);
  if (bytes.length != 512) {
    await db.delete('face_data');
    throw Exception('Invalid stored embedding byte length: ${bytes.length}');
  }

  final embedding = Float32List.view(bytes.buffer, 0, 128);
  debugPrint('📤 Loaded embedding sample: ${embedding.sublist(0, 5)}');
  return embedding;
}


  Future<bool> faceDataExists() async {
    final db = await dbHelper.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM face_data'),
    );
    return count != null && count > 0;
  }

  // Add these methods to Sitedetaildatabase class
  Future<bool> checkUserExists(String username) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    return result.isNotEmpty;
  }

  Future<bool> validateUser(String username, String password) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    return result.isNotEmpty;
  }

  Future<int> insertUser(
    String username,
    String password, {
    String? userId,
  }) async {
    final db = await dbHelper.database;
    return db.insert('users', {
      'username': username,
      'password': password,
      'userId': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getUser(String username) async {
    final db = await dbHelper.database;
    final results = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllLocaion() async {
    final db = await dbHelper.database;
    return await db.query('attendance');
  }

  Future<void> printAllNozzles() async {
    final nozzles = await getAllLocaion();

    debugPrint('\n🔧 ALL attendance IN DATABASE (${nozzles.length} total)');
    for (final nozzle in nozzles) {
      debugPrint('├─  id : ${nozzle['id']}');
     
      // debugPrint('│   longitude : ${nozzle['longitude']}');
      //debugPrint('│   threshold : ${nozzle['threshold']}');
      debugPrint('│ full data : ${nozzle.toString()}');
    }
    debugPrint('└──────────────────────────────────');
  }
}
