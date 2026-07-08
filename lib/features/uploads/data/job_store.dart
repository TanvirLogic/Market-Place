import 'dart:convert';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models/upload_enums.dart';
import 'models/upload_job.dart';

/// Persists [UploadJob] state transitions to SQLite so jobs survive app kill.
///
/// Table schema mirrors [UploadJob] fields. Only non-terminal jobs are kept
/// after a restart; terminal jobs are cleaned up lazily.
class JobStore {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      join(dir.path, 'upload_jobs.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE upload_jobs (
            id TEXT PRIMARY KEY,
            file_path TEXT NOT NULL,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            state TEXT NOT NULL,
            progress REAL NOT NULL,
            is_multipart INTEGER NOT NULL DEFAULT 0,
            key TEXT,
            s3_upload_id TEXT,
            direct_upload_url TEXT,
            file_url TEXT,
            parts TEXT,
            metadata TEXT,
            error TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Persist a job snapshot. Called on every state/progress change.
  Future<void> save(UploadJob job) async {
    final db = await _open();
    await db.insert(
      'upload_jobs',
      {
        'id': job.id,
        'file_path': job.filePath,
        'type': job.type.wire,
        'title': job.title,
        'file_size': job.fileSize,
        'state': job.state.wire,
        'progress': job.progress,
        'is_multipart': job.isMultipart ? 1 : 0,
        'key': job.key,
        's3_upload_id': job.s3UploadId,
        'direct_upload_url': job.directUploadUrl,
        'file_url': job.fileUrl,
        'parts': job.parts.isNotEmpty
            ? jsonEncode(job.parts.map((p) => p.toMap()).toList())
            : null,
        'metadata': job.metadata.isNotEmpty
            ? jsonEncode(job.metadata)
            : null,
        'error': job.error,
        'created_at': job.createdAt,
        'updated_at': job.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load all non-terminal jobs from the database.
  Future<List<UploadJob>> loadAll() async {
    final db = await _open();
    final rows = await db.query(
      'upload_jobs',
      where: 'state NOT IN (?, ?, ?)',
      whereArgs: [
        UploadJobState.completed.wire,
        UploadJobState.failed.wire,
        UploadJobState.cancelled.wire,
      ],
    );
    return rows.map(_rowToJob).toList();
  }

  /// Load ALL jobs including terminal ones (for cleanup/audit).
  Future<List<UploadJob>> loadAllIncludingTerminal() async {
    final db = await _open();
    final rows = await db.query('upload_jobs');
    return rows.map(_rowToJob).toList();
  }

  /// Remove a specific job from the database.
  Future<void> delete(String id) async {
    final db = await _open();
    await db.delete('upload_jobs', where: 'id = ?', whereArgs: [id]);
  }

  /// Purge all terminal (completed, failed, cancelled) jobs.
  Future<void> deleteAllTerminal() async {
    final db = await _open();
    await db.delete(
      'upload_jobs',
      where: 'state IN (?, ?, ?)',
      whereArgs: [
        UploadJobState.completed.wire,
        UploadJobState.failed.wire,
        UploadJobState.cancelled.wire,
      ],
    );
  }

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  UploadJob _rowToJob(Map<String, dynamic> row) {
    List<UploadPart> parts = [];
    if (row['parts'] is String) {
      final list = jsonDecode(row['parts'] as String) as List;
      parts = list
          .map((p) => UploadPart.fromMap(p as Map<dynamic, dynamic>))
          .toList();
    }

    Map<String, dynamic> metadata = {};
    if (row['metadata'] is String) {
      metadata =
          Map<String, dynamic>.from(jsonDecode(row['metadata'] as String) as Map);
    }

    return UploadJob(
      id: row['id'] as String,
      filePath: row['file_path'] as String,
      type: UploadAssetType.fromWire(row['type'] as String?),
      title: row['title'] as String? ?? '',
      fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
      state: UploadJobState.fromWire(row['state'] as String?),
      progress: (row['progress'] as num?)?.toDouble() ?? 0.0,
      isMultipart: (row['is_multipart'] as int?) == 1,
      key: row['key'] as String?,
      s3UploadId: row['s3_upload_id'] as String?,
      directUploadUrl: row['direct_upload_url'] as String?,
      fileUrl: row['file_url'] as String?,
      parts: parts,
      metadata: metadata,
      error: row['error'] as String?,
      createdAt: (row['created_at'] as num?)?.toInt(),
      updatedAt: (row['updated_at'] as num?)?.toInt(),
    );
  }
}
