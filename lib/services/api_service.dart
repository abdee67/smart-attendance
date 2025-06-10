import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:smartattendance/services/AttendanceException.dart';
import 'package:sqflite/sqflite.dart';

import '/db/dbmethods.dart';
import '/models/location.dart';
import '/models/attendance.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '/screens/location_service.dart';


class ApiService {
  static const String baseUrl = 'https://2491-196-188-160-151.ngrok-free.app/savvy/api';
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
    
    final locationValid = await LocationService().verifyLocation();
    if (!locationValid) {
      throw Exception('Location verification failed');
    }

    final record = AttendanceRecord(
      userId: userId,
      timestamp: DateTime.now(),
      status: AttendanceStatus.absent,
    );

    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
         try {
        // Try to sync immediately
        await syncAttendance(record);
        record.status = AttendanceStatus.present;
        await db.saveAttendance(record);
      } catch (e) {
        // Fallback to local storage if sync fails
        record.status = AttendanceStatus.absent;
        await db.saveAttendance(record);
        throw AttendanceException('Online sync failed. Saved locally for later sync.');
      }
    } else {
      // Save to local storage for later sync
      await db.saveAttendance(record);
      throw AttendanceException('No internet connection. Saved locally for later sync.');
    }
  }
    Future<void> syncAttendance(AttendanceRecord record) async {
    try {
      await postAttendanceStatus(record);
    } catch (e) {
      throw AttendanceException('Failed to sync attendance: ${e.toString()}');
    }
  }

  Future<void> processPendingSyncs() async {
    try {
      // Check connectivity first
      final connectivityResult = await _connectivity.checkConnectivity();
      // ignore: unrelated_type_equality_checks
      if (connectivityResult == ConnectivityResult.none) return;

      // Get all pending syncs ordered by timestamp 
      final pendingSyncs = await db.getPendingAttendances();

       for (final record in pendingSyncs) {
        try {
          await syncAttendance(record);
          await db.markAsSynced(record.id!);
        } catch (e) {
          debugPrint('Failed to sync record ${record.id}: $e');
          // Update retry count and last attempt time
        }
      }
        } catch (e) {
          debugPrint('Failed to process pending sync: $e');
        }
  }


  Future<http.Response> postAttendanceStatus(
    AttendanceRecord data, {
    int maxRetries = 3,
  }) async {
    final url = Uri.parse('$baseUrl/attendance/faceCompare');
    http.Response? lastResponse;
    Exception? lastException;

    for (int i = 0; i < maxRetries; i++) {
      try {
        final response = await http.post(
          url,
          headers: _headers,
          body: jsonEncode(data.tojson()),
        ).timeout(const Duration(seconds: 50));

        lastResponse = response;
        
        if (response.statusCode == 200) {
          debugPrint('✅ Satus submitted successfully!');
          return response;
        } else {
          debugPrint('❌ Failed to submit Satus');
          debugPrint('Status: ${response.statusCode}');
          debugPrint('Body: ${response.body}');
          lastException = ApiException('API returned ${response.statusCode}', response.statusCode);
        }

        // Exponential backoff
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: _calculateDelay(i)));
        }
      } on TimeoutException catch (e) {
        lastException = e;
        debugPrint('⏱️ Timeout occurred: ${e.message}');
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: _calculateDelay(i)));
        }
      } on http.ClientException catch (e) {
        lastException = e;
        debugPrint('🌐 Network error occurred: ${e.message}');
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: _calculateDelay(i)));
        }
      } catch (e) {
        lastException = Exception('Unknown error: $e');
        debugPrint('❌ Unexpected error: $e');
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: _calculateDelay(i)));
        }
      }
    }

    if (lastResponse != null) return lastResponse;
    throw lastException ?? ApiException('API request failed after $maxRetries attempts');
  }
  // Helper method to calculate exponential backoff delay
  static int _calculateDelay(int attempt) => 2 * (attempt + 1);
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => statusCode != null
      ? 'ApiException: $message (Status: $statusCode)'
      : 'ApiException: $message';
}