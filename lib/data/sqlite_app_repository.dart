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
        onCreate: (db, _) => db.execute(
          'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
        ),
      );
    }();
    return _dbFuture!;
  }

  @override
  Future<AppState> load() async {
    final rows = await (await _db).query(
      'app_state',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) return AppState.initial();
    try {
      return AppState.fromJson(
        jsonDecode(rows.single['payload']! as String) as Map<String, dynamic>,
      );
    } catch (error) {
      // Return initial state only if payload is missing or unparseable, but do not clear DB automatically
      return AppState.initial();
    }
  }

  @override
  Future<void> save(AppState state) async {
    await (await _db).insert('app_state', {
      'id': 1,
      'payload': jsonEncode(state.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> replace(AppState state) => save(state);
}
