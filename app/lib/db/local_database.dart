import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/photo_model.dart';

/// 로컬 SQLite 데이터베이스 (서버 DB 미러링)
/// - 썸네일 + 메타데이터만 보관 (원본은 외장하드)
/// - 오프라인에서도 지도/갤러리/인물 검색 가능
class LocalDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'family_archive.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 사진 메타데이터
    await db.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY,
        filename TEXT NOT NULL,
        taken_at TEXT,
        latitude REAL,
        longitude REAL,
        place_name TEXT,
        is_backed_up INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0,
        thumbnail_path TEXT,
        file_size INTEGER,
        camera_model TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    // 인물
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        photo_count INTEGER DEFAULT 0,
        sample_thumbnail TEXT
      )
    ''');

    // 사진-인물 관계
    await db.execute('''
      CREATE TABLE photo_persons (
        photo_id TEXT,
        person_id INTEGER,
        PRIMARY KEY (photo_id, person_id)
      )
    ''');

    // 장소
    await db.execute('''
      CREATE TABLE places (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        latitude REAL,
        longitude REAL,
        category TEXT
      )
    ''');

    // 동기화 상태
    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // 오프라인 즐겨찾기 큐 (역동기화용)
    await db.execute('''
      CREATE TABLE offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        photo_id TEXT,
        data TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    // 인덱스
    await db.execute('CREATE INDEX idx_photos_taken ON photos(taken_at)');
    await db.execute('CREATE INDEX idx_photos_place ON photos(place_name)');
    await db.execute('CREATE INDEX idx_photos_backed ON photos(is_backed_up)');
    await db.execute('CREATE INDEX idx_photos_coords ON photos(latitude, longitude)');
  }

  // === CRUD 메서드 ===

  /// 사진 전체 조회 (최신순)
  static Future<List<PhotoModel>> getAllPhotos() async {
    final db = await database;
    final rows = await db.query('photos', orderBy: 'taken_at DESC');
    return rows.map((r) => PhotoModel.fromJson(r)).toList();
  }

  /// 사진 삽입/업데이트
  static Future<void> upsertPhoto(PhotoModel photo) async {
    final db = await database;
    await db.insert(
      'photos',
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 사진 일괄 삽입 (동기화)
  static Future<void> bulkUpsertPhotos(List<PhotoModel> photos) async {
    final db = await database;
    final batch = db.batch();
    for (final photo in photos) {
      batch.insert('photos', photo.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 즐겨찾기 토글
  static Future<void> toggleFavorite(String photoId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'photos',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [photoId],
    );

    // 오프라인 큐에 추가 (역동기화용)
    await db.insert('offline_queue', {
      'action': 'toggle_favorite',
      'photo_id': photoId,
      'data': isFavorite.toString(),
    });
  }

  /// 백업 완료 사진 조회
  static Future<List<PhotoModel>> getBackedUpPhotos() async {
    final db = await database;
    final rows = await db.query(
      'photos',
      where: 'is_backed_up = 1',
      orderBy: 'taken_at DESC',
    );
    return rows.map((r) => PhotoModel.fromJson(r)).toList();
  }

  /// 위치별 사진 조회 (지도용)
  static Future<List<PhotoModel>> getPhotosWithLocation() async {
    final db = await database;
    final rows = await db.query(
      'photos',
      where: 'latitude IS NOT NULL AND longitude IS NOT NULL',
      orderBy: 'taken_at DESC',
    );
    return rows.map((r) => PhotoModel.fromJson(r)).toList();
  }

  /// 인물별 사진 조회
  static Future<List<PhotoModel>> getPhotosByPerson(int personId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.* FROM photos p
      JOIN photo_persons pp ON p.id = pp.photo_id
      WHERE pp.person_id = ?
      ORDER BY p.taken_at DESC
    ''', [personId]);
    return rows.map((r) => PhotoModel.fromJson(r)).toList();
  }

  /// 마지막 동기화 시간
  static Future<String?> getLastSyncTime() async {
    final db = await database;
    final rows = await db.query('sync_state',
        where: 'key = ?', whereArgs: ['last_sync_at']);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// 동기화 시간 업데이트
  static Future<void> setLastSyncTime(String time) async {
    final db = await database;
    await db.insert('sync_state', {'key': 'last_sync_at', 'value': time},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 오프라인 큐 조회 (역동기화 대기)
  static Future<List<Map<String, dynamic>>> getOfflineQueue() async {
    final db = await database;
    return await db.query('offline_queue', orderBy: 'created_at ASC');
  }

  /// 오프라인 큐 비우기 (동기화 완료 후)
  static Future<void> clearOfflineQueue() async {
    final db = await database;
    await db.delete('offline_queue');
  }
}
