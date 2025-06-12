
import 'dart:async';

import 'package:smartattendance/services/face_service.dart';

import '/db/dbmethods.dart';
import '/providers/sync_provider.dart';
import '/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/attendance_screen.dart';
import 'screens/face_registration.dart';
import '/screens/login.dart';
//import 'screens/siteEntry.dart';

// Import ItemDatabase
// Import DatabaseHelper

void main() async {
    final apiService = ApiService();
     final database = AttendancedbMethods.instance;
  WidgetsFlutterBinding.ensureInitialized();
  await FaceService.init();
    await database.printAllNozzles();

  // After successful login
  // In your main.dart or wherever you initialize your database

  runApp( MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        Provider(create: (_) => database),
        Provider(create: (_) => apiService),
      ],
      child: AttendanceApp (apiService: apiService),
    ),

  );
    Timer.periodic(const Duration(seconds: 15), (timer) async {
    final db = await AttendancedbMethods.instance.dbHelper.database;
  });
}

class AttendanceApp  extends StatefulWidget {
  final ApiService apiService;

  const AttendanceApp ({super.key, required this.apiService});

  @override
  _AttendanceAppState createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp >
    with WidgetsBindingObserver {
  final AttendancedbMethods db = AttendancedbMethods.instance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartAttendance',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginScreen(apiService: widget.apiService),
        '/attendance': (context) => const AttendanceScreen(),
        '/register-face': (context) => FaceRegistrationScreen(
              databaseHelper: AttendancedbMethods.instance.dbHelper,
              username: '',
            ),
      },
    );
  }

}

