import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import 'app_repository.dart';

class SqliteAppRepository implements AppRepository {
  Future<Database>? _dbFuture;

  Future<Database> get _db {
    _dbFuture ??= () async {
      final directory = await getDatabasesPath();
      return openDatabase(
        path.join(directory, 'aperture_grafik.db'),
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS app_state_quarantine (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, saved_at TEXT NOT NULL, error TEXT)',
          );
        },
      );
    }();
    return _dbFuture!;
  }

  @override
  Future<AppState> load() async {
    final db = await _db;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS app_state_quarantine (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, saved_at TEXT NOT NULL, error TEXT)',
    );
    final rows = await db.query('app_state', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) return AppState.initial();
    final raw = rows.single['payload']! as String;
    try {
      return AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      // Quarantine corrupted payload to prevent silent permanent destruction
      try {
        await db.insert('app_state_quarantine', {
          'payload': raw,
          'saved_at': DateTime.now().toIso8601String(),
          'error': error.toString(),
        });
      } catch (_) {}
      // Keep the original row in place and fail startup so it cannot be
      // overwritten by an initial state before the user recovers their data.
      throw FormatException('Saved app data is corrupted: $error');
    }
  }

  @override
  Future<void> save(AppState state) async {
    final db = await _db;
    final payload = jsonEncode(state.toJson());
    await db.transaction((txn) async {
      await txn.insert('app_state', {
        'id': 1,
        'payload': payload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> replace(AppState state) => save(state);
}
