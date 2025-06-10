// lib/db/database_helper.dart
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = "smart_attendance.db";
  static const _databaseVersion = 1;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  Future<Database> initDB() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute("PRAGMA foreign_keys = ON");
      },
      onCreate: (db, version) async {
        print("📦 Creating tables...");

        await db.execute('''
        CREATE TABLE users (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
  userId TEXT NOT NULL,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL

        )
      ''');

        await db.execute('''
      CREATE TABLE location (
        id INTEGER PRIMARY KEY,
        threshold REAL NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL
      )
    ''');

        await db.execute('''
      CREATE TABLE face_data (
        id INTEGER PRIMARY KEY,
        embedding BLOB NOT NULL
      )
    ''');

        await db.execute('''
        CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
         created_at TEXT DEFAULT CURRENT_TIMESTAMP
)
 ''');
     await db.execute('''
      CREATE INDEX idx_attendance_status ON attendance(status)
    ''');

        print("✅ All tables created.");
      },
      // ✅ This is important for upgrading existing apps
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 1) {
          print("⚙️ Upgrading DB from version $oldVersion to $newVersion...");

          print("✅ pending_syncs table added.");
        }
      },
      onOpen: (db) async {
        await db.execute("PRAGMA foreign_keys = ON");
        final tables = await db.rawQuery(
          'SELECT name FROM sqlite_master WHERE type="table"',
        );
        print('📋 Tables in database: $tables');
      },
    );
  }
}
