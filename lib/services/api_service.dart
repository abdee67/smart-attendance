import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:smartattendance/services/AttendanceException.dart';

import '/db/dbmethods.dart';
import '/models/location.dart';
import '/models/attendance.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '/screens/location_service.dart';


class ApiService {
  static const String baseUrl = 'https://bf0e-196-188-160-151.ngrok-free.app/savvy/api';
  final AttendancedbMethods db = AttendancedbMethods.instance;
  final Connectivity _connectivity = Connectivity();
    final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();


  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  // Authentication Method (returns userId and addresses)
Future<Map<String, dynamic>> authenticateUser(String username, String password) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    ).timeout(const Duration(seconds: 120));

    debugPrint('Login Response Code: ${response.statusCode}');
    debugPrint('Login Response: ${response.body}');

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      final message = jsonData['message'] as String? ?? 'Login successful';
      final userId = jsonData['userId'] as String?;
      final longitude = double.tryParse(jsonData['longitude']?.toString() ?? '0') ?? 0;
      final latitude = double.tryParse(jsonData['latitude']?.toString() ?? '0') ?? 0;
      final threshold = double.tryParse(jsonData['attendance_range']?.toString() ?? '100') ?? 100;
      
      if (userId == null || userId.isEmpty) {
        return {
          'success': false,
          'error': 'Authentication succeeded but no user ID was provided',
          'userMessage': 'System error: Please contact support'
        };
      }
    // Save location data to local DB
      final location = LocationData(
        id: 1, // Using fixed ID for primary location
        threshold: threshold,
        latitude: latitude,
        longitude: longitude,
      );
      await db.saveLocationData(location);
      // Store credentials securely for future logins
      await _storeCredentials(username, password, userId);
      
      return {
        'success': true,
        'userId': userId,
        'addresses': location,
        'userMessage': message,
      };
    }
    
    // Handle specific status codes with user-friendly messages
    String userMessage;
    switch (response.statusCode) {
      case 400:
        userMessage = 'Invalid request format';
        break;
      case 401:
        userMessage = 'Incorrect username or password';
        break;
      case 403:
        userMessage = 'Account disabled or access denied';
        break;
      case 404:
        userMessage = 'Account not found';
        break;
      case 500:
        userMessage = 'Server error - please try again later';
        break;
      default:
        userMessage = 'Login failed (Error ${response.statusCode})';
    }
    
    return {
      'success': false,
      'error': userMessage,
      'userMessage': userMessage,
    };
  } on TimeoutException {
    return {
      'success': false,
      'error': 'Connection timeout',
      'userMessage': 'Server took too long to respond. Please check your connection and try again.',
    };
  } on SocketException {
    return {
      'success': false,
      'error': 'Network error',
      'userMessage': 'No internet connection. Please check your network settings.',
    };
  } on FormatException {
    return {
      'success': false,
      'error': 'Invalid server response',
      'userMessage': 'System error: Please contact support',
    };
  } catch (e) {
    debugPrint('API authentication failed: $e');
    return {
      'success': false,
      'error': e.toString(),
      'userMessage': 'An unexpected error occurred. Please try again.',
    };
  }
}
    // Store credentials securely
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<void> _storeCredentials(String username, String password, String? userId) async {
    await _secureStorage.write(key: 'api_username', value: username);
    await _secureStorage.write(key: 'api_password', value: password);
     if (userId != null) {
    await _secureStorage.write(key: 'api_user_id', value: userId);
  }
  }

    // Retrieve stored credentials
Future<Map<String, String>?> getStoredCredentials() async {
  final username = await _secureStorage.read(key: 'api_username');
  final password = await _secureStorage.read(key: 'api_password');
  final userId = await _secureStorage.read(key: 'api_user_id');
  
  if (username != null && password != null) {
    return {
      'username': username, 
      'password': password,
      'userId': userId ?? 'offline_user' // Return empty string if userId is null
    };
  }
  return null;
}
   Future<String?> getUserId() async {
    return await _secureStorage.read(key: 'api_user_id');
  }

Future<void> markAttendance() async {
  final userId = await getUserId();
  if (userId == null) throw Exception('User not logged in');

  // 1) verify location…
  if (!await LocationService().verifyLocation()) {
    throw Exception('Location verification failed');
  }

  // 2) build the record and attempt immediate online sync
  final record = AttendanceRecord(
    userId: userId,
    timestamp: DateTime.now(),
    status: AttendanceStatus.absent,
  );

  // ignore: unrelated_type_equality_checks
  final isOnline = await _connectivity.checkConnectivity() != ConnectivityResult.none;
  if (isOnline) {
    // wrap in a list ⇒ batch API
    final response = await postAttendanceBatch([record]);
    if (response.statusCode == 200) {
      // success ⇒ mark present
      record.status = AttendanceStatus.present;
      await db.saveAttendance(record);
    } else {
      // non‐200 ⇒ queue locally
      await db.saveAttendance(record);
      throw AttendanceException('Server rejected attendance: ${response.statusCode}');
    }
  } else {
    // offline ⇒ queue locally
    await db.saveAttendance(record);
    throw AttendanceException('No internet. Saved locally for later sync.');
  }
}

  /// Sends one or more attendance records in a single batch.
  /// Returns the raw http.Response so callers can decide what to do.
Future<http.Response> postAttendanceBatch(
  List<AttendanceRecord> records, {
  int maxRetries = 3,
}) async {
  // 1) Build your payload exactly as the API expects (an array of objects)
  final List<Map<String, dynamic>> payload = records.map((r) {
    return {
      "userId": r.userId, // Wrap userId in a nested object
      "attendanceDate": DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(r.timestamp),
      "attendanceStatus": "pending",
    };
  }).toList();

  final url = Uri.parse('$baseUrl/attendance/faceCompare');
  final body = jsonEncode(payload);
  http.Response? lastResponse;
  Exception? lastError;

    // 2) Retry loop with exponential backoff
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _client
            .post(url, headers: _headers, body: body)
            .timeout(const Duration(seconds: 30));
        lastResponse = response;
        // 3) Immediately return on success
        if (response.statusCode == 200) {
          debugPrint('✅ Attendance batch submitted: ${response.body}');
          return response;
        }

        // 4) Log & prepare to retry
        debugPrint('❌ Attendance batch failed (${response.statusCode}) → ${response.body}');
        lastError = ApiException('Status ${response.statusCode}', response.statusCode);
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint('⏱️ Timeout on attendance post: $e');
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint('🌐 Network error on attendance post: $e');
      } catch (e) {
        lastError = Exception('Unknown error: $e');
        debugPrint('❌ Unexpected error on attendance post: $e');
      }

      // 5) Delay before next attempt (unless it was last)
      if (attempt < maxRetries - 1) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }

    // if we have a non‐200 response, return it to caller
    if (lastResponse != null) return lastResponse;

    // else throw the last exception
    throw lastError ?? ApiException('Attendance batch failed after $maxRetries tries');
  }
}

Future<void> processPendingSyncs(apiService) async {
  final Connectivity connectivity = Connectivity();
  if (await connectivity.checkConnectivity() == ConnectivityResult.none) return;
  final pending = await apiService.db.getPendingAttendances();
  for (final record in pending) {
    final response = await apiService.postAttendanceBatch([record]);
    if (response.statusCode == 200) {
      await apiService.db.markAsSynced(record.id!);
    }
  }
}

  // Helper method to calculate exponential backoff delay
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => statusCode != null
      ? 'ApiException: $message (Status: $statusCode)'
      : 'ApiException: $message';
}