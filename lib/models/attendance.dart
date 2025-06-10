enum AttendanceStatus {
  absent('absent'),
  present('present'),
  failed('failed');
  
  final String value;
  const AttendanceStatus(this.value);
  @override
  String toString() => value;
}
class AttendanceRecord {
  int? id;
  final String userId;
  final DateTime timestamp;
   AttendanceStatus status;
  bool isSynced;

  AttendanceRecord({
    this.id,
    required this.userId,
    required this.timestamp,
    this.status = AttendanceStatus.absent,
    this.isSynced = false,
  });

  Map<String, dynamic> tojson() {
    return {
      'user_id': userId,
      'timestamp': timestamp.toIso8601String(),
      'status': status.value,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'],
      userId: json['user_id'],
      timestamp: DateTime.parse(json['timestamp']),  status: AttendanceStatus.values.firstWhere(
        (e) => e.value == json['status'],
        orElse: () => AttendanceStatus.absent,
      ),
      isSynced: json['is_synced'] == 1,
    );
  }
}