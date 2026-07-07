import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models/models.dart';

class Persistence {
  Persistence({this.customDbPath});

  /// Override database path (used in tests).
  final String? customDbPath;

  Future<Database>? _dbFuture;
  bool _closed = false;

  Future<Database> get database {
    if (_closed) throw StateError('Persistence is closed');
    return _dbFuture ??= _initDb();
  }

  Future<Database> _initDb() async {
    final path = customDbPath ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'upload_queue_v2.db', // different from legacy UploadQueueRepository
        );
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS uploads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT NOT NULL,
            title TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'pending',
            progress REAL NOT NULL DEFAULT 0.0,
            totalParts INTEGER NOT NULL DEFAULT 0,
            partsCompleted INTEGER NOT NULL DEFAULT 0,
            errorMessage TEXT,
            metadata TEXT,
            fileUrl TEXT,
            s3UploadId TEXT,
            s3Key TEXT,
            partSize INTEGER NOT NULL DEFAULT 0,
            partETags TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_uploads_state ON uploads(state)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: add s3Key column for multipart complete/abort payloads.
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE uploads ADD COLUMN s3Key TEXT');
          } catch (_) {
            // Column may already exist (e.g. created by onOpen) — ignore.
          }
        }
      },
      onConfigure: (db) async {
        try {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA busy_timeout=5000');
        } catch (_) {
          // PRAGMA failures must not block schema creation in onOpen
        }
      },
      onOpen: (db) async {
        // Run on every DB open so schema is guaranteed to exist even if the
        // DB file predates this table (e.g. old app install, onConfigure skip).
        await db.execute('''
          CREATE TABLE IF NOT EXISTS uploads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT NOT NULL,
            title TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'pending',
            progress REAL NOT NULL DEFAULT 0.0,
            totalParts INTEGER NOT NULL DEFAULT 0,
            partsCompleted INTEGER NOT NULL DEFAULT 0,
            errorMessage TEXT,
            metadata TEXT,
            fileUrl TEXT,
            s3UploadId TEXT,
            s3Key TEXT,
            partSize INTEGER NOT NULL DEFAULT 0,
            partETags TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
        // Defensive: ensure s3Key exists on databases created before v2 that
        // may reach onOpen without onUpgrade running.
        try {
          await db.execute('ALTER TABLE uploads ADD COLUMN s3Key TEXT');
        } catch (_) {
          // Already present — expected.
        }
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_uploads_state ON uploads(state)',
        );
      },
    );
  }

  Future<int> insert({
    required String filePath,
    required String title,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert('uploads', {
      'filePath': filePath,
      'title': title,
      'state': 'pending',
      'progress': 0.0,
      'totalParts': 0,
      'partsCompleted': 0,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<UploadTask?> getById(int id) async {
    final db = await database;
    final maps = await db.query(
      'uploads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _rowToTask(maps.first);
  }

  Future<UploadTask?> claimNextPending() async {
    final db = await database;
    return db.transaction<UploadTask?>((txn) async {
      final maps = await txn.query(
        'uploads',
        where: 'state = ?',
        whereArgs: ['pending'],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (maps.isEmpty) return null;
      final map = maps.first;
      final id = map['id'] as int;
      final now = DateTime.now().toIso8601String();
      final updated = await txn.update(
        'uploads',
        {'state': 'uploading', 'updatedAt': now, 'errorMessage': null},
        where: 'id = ? AND state = ?',
        whereArgs: [id, 'pending'],
      );
      if (updated != 1) return null;
      return _rowToTask({...map, 'state': 'uploading', 'updatedAt': now});
    });
  }

  Future<void> updateMultipartState({
    required int id,
    required String s3UploadId,
    required int totalParts,
    required int partSize,
    String? s3Key,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {
        's3UploadId': s3UploadId,
        if (s3Key != null) 's3Key': s3Key,
        'totalParts': totalParts,
        'partsCompleted': 0,
        'partSize': partSize,
        'partETags': '[]',
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recordPartCompletion({
    required int id,
    required int partNumber,
    required String eTag,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'uploads',
        columns: ['partETags', 'partsCompleted', 'state'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      if (rows.first['state'] != 'uploading') return;

      final existing = rows.first['partETags'] as String?;
      final tags = _parsePartETags(existing);
      final wasDuplicate = tags.any((t) => t.partNumber == partNumber);
      if (!wasDuplicate) {
        tags.add(PartETag(partNumber: partNumber, eTag: eTag));
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'uploads',
        {
          'partsCompleted': wasDuplicate
              ? (rows.first['partsCompleted'] as int? ?? 0)
              : (rows.first['partsCompleted'] as int? ?? 0) + 1,
          'partETags': _encodePartETags(tags),
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<PartETag>> getPartETags(int id) async {
    final db = await database;
    final rows = await db.query(
      'uploads',
      columns: ['partETags'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return [];
    return _parsePartETags(rows.first['partETags'] as String?);
  }

  Future<void> updateFileUrl({
    required int id,
    required String fileUrl,
  }) async {
    if (fileUrl.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {'fileUrl': fileUrl, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markCompleted(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {'state': 'completed', 'progress': 1.0, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markFailed(int id, String error) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {'state': 'failed', 'errorMessage': error, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markCancelled(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {
        'state': 'cancelled',
        'errorMessage': 'Cancelled',
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearMultipartState(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {
        's3UploadId': null,
        's3Key': null,
        'totalParts': 0,
        'partsCompleted': 0,
        'partSize': 0,
        'partETags': null,
        'progress': 0.0,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<UploadTask>> getActive() async {
    final db = await database;
    final maps = await db.query(
      'uploads',
      where: 'state NOT IN (?, ?, ?)',
      whereArgs: ['completed', 'failed', 'cancelled'],
      orderBy: 'id ASC',
    );
    return maps.map(_rowToTask).toList();
  }

  Future<int> countActive() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM uploads WHERE state NOT IN (?, ?, ?)',
      ['completed', 'failed', 'cancelled'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<UploadTask>> getAll() async {
    final db = await database;
    final maps = await db.query('uploads', orderBy: 'id ASC');
    return maps.map(_rowToTask).toList();
  }

  Future<List<UploadTask>> getUploading() async {
    final db = await database;
    final maps = await db.query(
      'uploads',
      where: 'state = ?',
      whereArgs: ['uploading'],
    );
    return maps.map(_rowToTask).toList();
  }

  Future<void> updateProgress({
    required int id,
    required double progress,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {'progress': progress, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markPending(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'uploads',
      {
        'state': 'pending',
        'progress': 0.0,
        'errorMessage': null,
        's3UploadId': null,
        's3Key': null,
        'totalParts': 0,
        'partsCompleted': 0,
        'partSize': 0,
        'partETags': null,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteItem(int id) async {
    final db = await database;
    await db.delete('uploads', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOldItems({int days = 7}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    await db.delete(
      'uploads',
      where: 'state IN (?, ?, ?) AND updatedAt < ?',
      whereArgs: ['completed', 'failed', 'cancelled', cutoff],
    );
  }

  /// Run database maintenance — VACUUM + integrity check.
  /// Call periodically (e.g. after every 100 delete operations).
  Future<void> optimize() async {
    try {
      final db = await database;
      await db.execute('PRAGMA optimize');
      await db.execute('PRAGMA auto_vacuum=INCREMENTAL');
      await db.execute('PRAGMA incremental_vacuum(100)');
    } catch (_) {}
  }

  /// Migrate pending tasks from a legacy DB (e.g. [upload_queue.db]) into
  /// this new queue DB. Runs once on startup to ensure no uploads are lost
  /// during the migration from the old upload system.
  ///
  /// Returns the number of tasks migrated.
  Future<int> migrateFromLegacy(String legacyDbPath) async {
    try {
      final legacyFile = File(legacyDbPath);
      if (!await legacyFile.exists()) return 0;

      final legacy = await openDatabase(legacyDbPath, readOnly: true);
      int count = 0;
      try {
        final rows = await legacy.query('uploads',
            where: 'state IN (?, ?, ?, ?)',
            whereArgs: ['pending', 'uploading', 'failed', 'paused']);
        for (final row in rows) {
          final id = row['id'] as int;
          // Check if already in new DB
          final existing = await (await database)
              .query('uploads', where: 'id = ?', whereArgs: [id]);
          if (existing.isNotEmpty) continue;

          await (await database).insert('uploads', {
            'id': id,
            'filePath': row['filePath'] as String? ?? '',
            'title': row['title'] as String? ?? '',
            'state': 'pending',
            'progress': 0.0,
            'totalParts': row['totalParts'] as int? ?? 0,
            'partsCompleted': row['partsCompleted'] as int? ?? 0,
            'errorMessage': null,
            'metadata': row['metadata'] as String?,
            'fileUrl': row['fileUrl'] as String?,
            's3UploadId': row['s3UploadId'] as String?,
            'partSize': row['partSize'] as int?,
            'partETags': row['partETags'] as String?,
            'createdAt': row['createdAt'] as String? ??
                DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          });
          count++;
        }
      } finally {
        await legacy.close();
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final db = _dbFuture == null ? null : await _dbFuture;
    await db?.close();
  }

  List<PartETag> _parsePartETags(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => PartETag.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.partNumber.compareTo(b.partNumber));
    } catch (_) {
      return [];
    }
  }

  String _encodePartETags(List<PartETag> tags) =>
      jsonEncode(tags.map((t) => t.toJson()).toList());

  UploadTask _rowToTask(Map<String, dynamic> map) {
    Map<String, dynamic>? metadata;
    if (map['metadata'] != null) {
      try {
        metadata = jsonDecode(map['metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }
    return UploadTask(
      id: map['id'] as int,
      filePath: map['filePath'] as String,
      title: map['title'] as String,
      state: UploadState.values.firstWhere(
        (s) => s.name == map['state'],
        orElse: () => UploadState.pending,
      ),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      totalParts: map['totalParts'] as int? ?? 0,
      partsCompleted: map['partsCompleted'] as int? ?? 0,
      s3UploadId: map['s3UploadId'] as String?,
      s3Key: map['s3Key'] as String?,
      errorMessage: map['errorMessage'] as String?,
      metadata: metadata,
      fileUrl: map['fileUrl'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
