import 'dart:convert';
import 'dart:io';

import 'package:edtech/features/courses/data/models/upload_task.dart';
import 'package:edtech/global/core/services/logger_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class UploadQueueItem {
  final int? id;
  final String filePath;
  final String title;
  final int videoDuration;
  final int fileSize;
  final String? uploadUrl;
  final String? fileUrl;
  final String status;
  final int bytesUploaded;
  final String? errorMessage;
  final String createdAt;
  final String lastUpdated;
  final String uploadType;
  final String? metadata;

  UploadQueueItem({
    this.id,
    required this.filePath,
    required this.title,
    this.videoDuration = 0,
    this.fileSize = 0,
    this.uploadUrl,
    this.fileUrl,
    this.status = 'pending',
    this.bytesUploaded = 0,
    this.errorMessage,
    String? createdAt,
    String? lastUpdated,
    this.uploadType = 'video_post',
    this.metadata,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        lastUpdated = lastUpdated ?? DateTime.now().toIso8601String();

  UploadTaskType get taskType => UploadTaskType.fromDb(uploadType);

  T? parseMetadata<T>(T Function(Map<String, dynamic>) fromJson) {
    if (metadata == null || metadata!.isEmpty) return null;
    try {
      final map = jsonDecode(metadata!) as Map<String, dynamic>;
      return fromJson(map);
    } catch (_) {
      return null;
    }
  }

  UploadQueueItem copyWith({
    int? id,
    String? filePath,
    String? title,
    int? videoDuration,
    int? fileSize,
    String? uploadUrl,
    String? fileUrl,
    String? status,
    int? bytesUploaded,
    String? errorMessage,
    String? createdAt,
    String? lastUpdated,
    String? uploadType,
    String? metadata,
  }) {
    return UploadQueueItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      videoDuration: videoDuration ?? this.videoDuration,
      fileSize: fileSize ?? this.fileSize,
      uploadUrl: uploadUrl ?? this.uploadUrl,
      fileUrl: fileUrl ?? this.fileUrl,
      status: status ?? this.status,
      bytesUploaded: bytesUploaded ?? this.bytesUploaded,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      uploadType: uploadType ?? this.uploadType,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'filePath': filePath,
      'title': title,
      'videoDuration': videoDuration,
      'fileSize': fileSize,
      'uploadUrl': uploadUrl,
      'fileUrl': fileUrl,
      'status': status,
      'bytesUploaded': bytesUploaded,
      'errorMessage': errorMessage,
      'createdAt': createdAt,
      'lastUpdated': lastUpdated,
      'uploadType': uploadType,
      'metadata': metadata,
    };
  }

  factory UploadQueueItem.fromMap(Map<String, dynamic> map) {
    return UploadQueueItem(
      id: map['id'] as int?,
      filePath: map['filePath'] as String,
      title: map['title'] as String,
      videoDuration: map['videoDuration'] as int? ?? 0,
      fileSize: map['fileSize'] as int? ?? 0,
      uploadUrl: map['uploadUrl'] as String?,
      fileUrl: map['fileUrl'] as String?,
      status: map['status'] as String? ?? 'pending',
      bytesUploaded: map['bytesUploaded'] as int? ?? 0,
      errorMessage: map['errorMessage'] as String?,
      createdAt: map['createdAt'] as String?,
      lastUpdated: map['lastUpdated'] as String?,
      uploadType: map['uploadType'] as String? ?? 'video_post',
      metadata: map['metadata'] as String?,
    );
  }
}

class UploadQueueRepository {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}upload_queue.db';
    AppLogger.i('UploadQueueRepository: opening database at $path');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE upload_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT NOT NULL,
            title TEXT NOT NULL,
            videoDuration INTEGER NOT NULL DEFAULT 0,
            fileSize INTEGER NOT NULL DEFAULT 0,
            uploadUrl TEXT,
            fileUrl TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            bytesUploaded INTEGER NOT NULL DEFAULT 0,
            errorMessage TEXT,
            createdAt TEXT NOT NULL,
            lastUpdated TEXT NOT NULL,
            uploadType TEXT NOT NULL DEFAULT 'video_post',
            metadata TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_upload_queue_status ON upload_queue(status)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: Added uploadType and metadata columns (preserve data)
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE upload_queue ADD COLUMN uploadType TEXT NOT NULL DEFAULT 'video_post'",
          );
          await db.execute(
            "ALTER TABLE upload_queue ADD COLUMN metadata TEXT",
          );
          AppLogger.i(
            'UploadQueueRepository: migrated to v2 — added uploadType and metadata',
          );
        }
        // v3: Added lastUpdated column
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE upload_queue ADD COLUMN lastUpdated TEXT NOT NULL DEFAULT ''",
          );
          // Backfill lastUpdated with createdAt for existing rows
          await db.rawUpdate(
            "UPDATE upload_queue SET lastUpdated = createdAt WHERE lastUpdated = ''",
          );
          AppLogger.i(
            'UploadQueueRepository: migrated to v3 — added lastUpdated column',
          );
        }
        // v4: Ensure index exists
        if (oldVersion < 4) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_upload_queue_status ON upload_queue(status)',
          );
          AppLogger.i(
            'UploadQueueRepository: migrated to v4 — ensured index',
          );
        }
      },
    );
  }

  static Future<int> insert(UploadQueueItem item) async {
    final db = await database;
    final id = await db.insert('upload_queue', item.toMap());
    AppLogger.i(
      'UploadQueueRepository: inserted item id=$id, type=${item.uploadType}, title=${item.title}',
    );
    return id;
  }

  static Future<UploadQueueItem?> getNextPending() async {
    final db = await database;
    final maps = await db.query(
      'upload_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return UploadQueueItem.fromMap(maps.first);
  }

  static Future<List<UploadQueueItem>> getAll() async {
    final db = await database;
    final maps = await db.query(
      'upload_queue',
      orderBy: 'id ASC',
    );
    return maps.map((m) => UploadQueueItem.fromMap(m)).toList();
  }

  static Future<List<UploadQueueItem>> getActive() async {
    final db = await database;
    final maps = await db.query(
      'upload_queue',
      where: 'status != ? AND status != ?',
      whereArgs: ['completed', 'failed'],
      orderBy: 'id ASC',
    );
    return maps.map((m) => UploadQueueItem.fromMap(m)).toList();
  }

  static Future<List<UploadQueueItem>> getByStatus(String status) async {
    final db = await database;
    final maps = await db.query(
      'upload_queue',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'id ASC',
    );
    return maps.map((m) => UploadQueueItem.fromMap(m)).toList();
  }

  static Future<void> updateUrls({
    required int id,
    required String uploadUrl,
    required String fileUrl,
  }) async {
    final db = await database;
    await db.update(
      'upload_queue',
      {
        'uploadUrl': uploadUrl,
        'fileUrl': fileUrl,
        'status': 'uploading',
        'lastUpdated': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateProgress({
    required int id,
    required int bytesUploaded,
  }) async {
    final db = await database;
    await db.update(
      'upload_queue',
      {
        'bytesUploaded': bytesUploaded,
        'lastUpdated': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateMetadata({
    required int id,
    required String metadata,
  }) async {
    final db = await database;
    await db.update(
      'upload_queue',
      {'metadata': metadata},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markCompleted(int id) async {
    final db = await database;
    await db.update(
      'upload_queue',
      {
        'status': 'completed',
        'bytesUploaded': 0,
        'lastUpdated': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markFailed(int id, String error) async {
    final db = await database;
    await db.update(
      'upload_queue',
      {
        'status': 'failed',
        'errorMessage': error,
        'lastUpdated': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateStatus({
    required int id,
    required String status,
    int? bytesUploaded,
    String? errorMessage,
  }) async {
    final db = await database;
    final values = <String, dynamic>{
      'status': status,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    if (bytesUploaded != null) values['bytesUploaded'] = bytesUploaded;
    if (errorMessage != null) values['errorMessage'] = errorMessage;
    await db.update('upload_queue', values, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteItem(int id) async {
    final db = await database;
    await db.delete('upload_queue', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearCompleted() async {
    final db = await database;
    await db.delete('upload_queue',
        where: 'status = ?', whereArgs: ['completed']);
  }

  static Future<int> countPending() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM upload_queue WHERE status = ?',
      ['pending'],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<int> countActive() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM upload_queue WHERE status NOT IN ('completed', 'failed')",
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<void> resetStaleUploading(
      {Duration olderThan = const Duration(minutes: 30)}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(olderThan).toIso8601String();
    await db.update(
      'upload_queue',
      {'status': 'pending', 'uploadUrl': null, 'fileUrl': null},
      where: "status = 'uploading' AND lastUpdated < ?",
      whereArgs: [cutoff],
    );
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
