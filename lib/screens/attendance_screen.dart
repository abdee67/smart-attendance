import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartattendance/models/attendance.dart';
import '../../services/api_service.dart';
import '../../services/face_service.dart';
import '/screens/location_service.dart';
import '../../db/dbmethods.dart';
import 'package:intl/intl.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int _attempts = 0;
  bool _isVerifying = false;
  String _statusMessage = '';
  final AttendancedbMethods db = AttendancedbMethods.instance;
  final locationService = LocationService();
  final apiservice = ApiService();
  DateTime? _lastAttendanceTime;
   bool _showPendingSyncs = false;
  List<AttendanceRecord> _pendingRecords = [];

  @override
  void initState() {
    super.initState();
      _loadPendingRecords();
      Timer.periodic(const Duration(minutes: 5), (_) => _syncPendingRecords());
  }
    Future<void> _loadPendingRecords() async {
    final records = await db.getPendingAttendances();
    setState(() => _pendingRecords = records);
  }

  Future<void> _syncPendingRecords() async {
    await apiservice.processPendingSyncs();
    await _loadPendingRecords();
  }

  Future<void> _verifyAndMarkAttendance() async {
    setState(() {
      _isVerifying = true;
      _statusMessage = 'Verifying face...';
    });

    try {
      // Step 1: Face Verification
      final image = await ImagePicker().pickImage(source: ImageSource.camera);
      if (image == null) return;

      setState(() => _statusMessage = 'Processing face...');
      final currentEmbedding = await FaceService.getFaceEmbedding(image.path);
      final storedEmbedding = await db.getFaceEmbedding();

      if (storedEmbedding == null) {
        throw Exception('No face registered. Please register first.');
      }

      if (currentEmbedding.length != 128 || storedEmbedding.length != 128) {
        throw Exception(
          'Invalid face data. Please try again.',
        );
      }

      final isMatch = FaceService.verifyFace(storedEmbedding, currentEmbedding);
      if (!isMatch) {
        throw Exception('Face verification failed. Please try again.');
      }

      // Step 2: Location Verification
      setState(() => _statusMessage = 'Verifying location...');
      final locationValid = await locationService.verifyLocation();
      
      if (!locationValid) {
        final currentPosition = await LocationService.getCurrentPosition();
        final allowedLocation = await db.getLocationData();
        final distance = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          allowedLocation!.latitude,
          allowedLocation.longitude,
        );
        
        throw Exception('You are ${distance.toStringAsFixed(2)}m away from the required location');
      }

      // Step 3: Mark Attendance
      setState(() => _statusMessage = 'Marking attendance...');
      await apiservice.markAttendance();

      setState(() {
        _statusMessage = 'Attendance marked successfully!';
        _attempts = 0;
        _lastAttendanceTime = DateTime.now();
      });

      // Refresh history
      await _loadPendingRecords();

      // Reset status after success
      await Future.delayed(const Duration(seconds: 2));
      setState(() => _statusMessage = '');
    } catch (e) {
      setState(() => _statusMessage = 'Error: ${e.toString()}');

      if (_attempts < 3) {
        _attempts++;
        await Future.delayed(const Duration(seconds: 2));
        setState(() => _statusMessage = 'Retrying ($_attempts/3)...');
        await _verifyAndMarkAttendance();
      } else {      
        setState(() {
          _statusMessage = 'Maximum attempts reached. Please try again later.';
          _attempts = 0;
        });
      }
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        actions: [
          IconButton(
            icon: Icon(_showPendingSyncs ? Icons.close : Icons.history),
            onPressed: () {
              setState(() {
                _showPendingSyncs = !_showPendingSyncs;
              });
            },
          ),
        ],
      ),
      body: _showPendingSyncs ? _buildPendingSyncsView() : _buildMainView(),
      floatingActionButton: _lastAttendanceTime != null
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _showPendingSyncs = !_showPendingSyncs;
                });
              },
              icon: const Icon(Icons.history),
              label: const Text('History'),
              backgroundColor: Colors.blueAccent,
            )
          : null,
    );
  }

  Widget _buildMainView() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.fingerprint,
                size: 100,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 20),
              Text(
                'Smart Attendance',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
              ),
              const SizedBox(height: 30),
              
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _statusMessage.contains('success') 
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _statusMessage.contains('success')
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusMessage.contains('success')
                            ? Icons.check_circle
                            : Icons.error,
                        color: _statusMessage.contains('success')
                            ? Colors.green
                            : Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 16,
                            color: _statusMessage.contains('success')
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isVerifying ? null : _verifyAndMarkAttendance,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _isVerifying
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(
                    _isVerifying ? 'Processing...' : 'Mark Attendance',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              if (_attempts > 0)
                Text(
                  'Attempts: $_attempts/3',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),

              if (_lastAttendanceTime != null) ...[
                const SizedBox(height: 30),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Last Attendance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  DateFormat('MMM dd, yyyy - hh:mm a').format(_lastAttendanceTime!),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

 Widget _buildPendingSyncsView() {
    return ListView.builder(
      itemCount: _pendingRecords.length,
      itemBuilder: (context, index) {
        final record = _pendingRecords[index];
        return ListTile(
          leading: const Icon(Icons.pending_actions),
          title: Text(DateFormat('MMM dd, yyyy hh:mm a').format(record.timestamp)),
          trailing: IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              try {
                await apiservice.syncAttendance(record);
                await _loadPendingRecords();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sync successful')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sync failed: ${e.toString()}')),
                );
              }
            },
          ),
        );
      },
    );
  }
}