import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '/db/dbmethods.dart';

class LocationService {
  static Future<Position> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

   Future<bool> verifyLocation() async {
    try {
      final currentPosition = await getCurrentPosition();
      final attendanceDb = AttendancedbMethods.instance;
      final storedLocation = await attendanceDb.getLocationData();
      
      if (storedLocation == null) {
        throw Exception('No location data stored');
      }

      final distance = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        storedLocation.latitude,
        storedLocation.longitude,
      );
      
      return distance <= storedLocation.threshold;
    } catch (e) {
       debugPrint('Location verification error: $e');
      return false;
    }
  }
}