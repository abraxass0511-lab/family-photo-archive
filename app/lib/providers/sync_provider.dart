import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';
import '../db/local_database.dart';
import 'photo_provider.dart';

/// 동기화 상태 관리
class SyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  bool _isServerOnline = false;
  String? _lastSyncTime;
  String _syncStatus = '동기화 대기';

  bool get isSyncing => _isSyncing;
  bool get isServerOnline => _isServerOnline;
  String? get lastSyncTime => _lastSyncTime;
  String get syncStatus => _syncStatus;

  /// 서버 연결 상태 확인
  Future<void> checkServerStatus() async {
    _isServerOnline = await apiService.isServerReachable();
    notifyListeners();
  }

  /// 전체 동기화 실행
  Future<bool> sync(PhotoProvider photoProvider) async {
    if (_isSyncing) return false;

    _isSyncing = true;
    _syncStatus = '서버 연결 중...';
    notifyListeners();

    try {
      // 1. 서버 상태 확인
      final isOnline = await apiService.isServerReachable();
      if (!isOnline) {
        _syncStatus = '서버에 연결할 수 없습니다';
        _isServerOnline = false;
        return false;
      }
      _isServerOnline = true;

      // 2. 오프라인 큐 먼저 전송 (역동기화)
      _syncStatus = '오프라인 변경사항 전송 중...';
      notifyListeners();
      await _syncOfflineQueue();

      // 3. 서버에서 최신 데이터 가져오기
      _syncStatus = '데이터 다운로드 중...';
      notifyListeners();

      // 항상 전체 동기화 (삭제된 항목도 반영)
      final data = await apiService.syncData(lastSyncAt: null);

      if (data != null) {
        await photoProvider.applySyncData(data);

        // 동기화 시간 업데이트
        final serverTime = data['server_time'] as String?;
        if (serverTime != null) {
          await LocalDatabase.setLastSyncTime(serverTime);
          _lastSyncTime = serverTime;
        }

        // 4. 썸네일/미리보기 로컬 저장 (동기화 완료 전에 실행)
        _syncStatus = '썸네일 저장 중...';
        notifyListeners();
        await _downloadMediaLocally(photoProvider);

        _syncStatus = '동기화 완료 ✅';
      } else {
        _syncStatus = '데이터를 가져올 수 없습니다';
        return false;
      }
    } catch (e) {
      _syncStatus = '동기화 실패: $e';
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }

    return true;
  }

  /// 오프라인 큐 전송 (역동기화: 즐겨찾기 등)
  Future<void> _syncOfflineQueue() async {
    final queue = await LocalDatabase.getOfflineQueue();
    if (queue.isEmpty) return;

    final favoriteChanges = queue
        .where((q) => q['action'] == 'toggle_favorite')
        .map((q) => <String, dynamic>{
              'photo_id': q['photo_id'],
              'is_favorite': q['data'] == 'true',
            })
        .toList();

    if (favoriteChanges.isNotEmpty) {
      final success = await apiService.syncFavorites(favoriteChanges);
      if (!success) return; // 실패 시 큐 유지
    }

    // 오프라인 삭제 큐 처리
    final deleteIds = queue
        .where((q) => q['action'] == 'delete_photo')
        .map((q) => q['photo_id'] as String)
        .toList();

    if (deleteIds.isNotEmpty) {
      try {
        await apiService.deletePhotos(deleteIds);
      } catch (_) {
        return; // 실패 시 큐 유지
      }
    }

    await LocalDatabase.clearOfflineQueue();
  }

  /// 썸네일/미리보기를 앱 로컬 저장소에 다운로드 (병렬, 점진적 UI 갱신)
  Future<void> _downloadMediaLocally(PhotoProvider photoProvider) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory(p.join(dir.path, 'thumbnails'));
      final previewDir = Directory(p.join(dir.path, 'previews'));
      if (!thumbDir.existsSync()) thumbDir.createSync(recursive: true);
      if (!previewDir.existsSync()) previewDir.createSync(recursive: true);

      final db = await LocalDatabase.database;
      final photos = photoProvider.photos;

      // 썸네일 다운로드가 필요한 사진만 필터링
      final needsThumb = photos.where((p) => p.localThumbnailPath == null).toList();

      if (needsThumb.isEmpty) return;

      _syncStatus = '썸네일 저장 중... (0/${needsThumb.length})';
      notifyListeners();

      int completed = 0;

      // 10개씩 병렬 다운로드
      for (int i = 0; i < needsThumb.length; i += 10) {
        final batch = needsThumb.skip(i).take(10).toList();

        await Future.wait(batch.map((photo) async {
          try {
            // 썸네일
            final thumbFile = File(p.join(thumbDir.path, '${photo.id}_thumb.jpg'));
            if (!thumbFile.existsSync()) {
              final bytes = await apiService.downloadThumbnailBytes(photo.id);
              if (bytes != null && bytes.isNotEmpty) {
                await thumbFile.writeAsBytes(bytes);
              }
            }
            if (thumbFile.existsSync()) {
              await db.update(
                'photos',
                {'local_thumbnail_path': thumbFile.path},
                where: 'id = ?',
                whereArgs: [photo.id],
              );
            }

            // 동영상 미리보기
            final fn = photo.filename.toLowerCase();
            final isVideo = fn.endsWith('.mp4') || fn.endsWith('.mov') || fn.endsWith('.3gp');
            if (isVideo && photo.localPreviewPath == null) {
              final previewFile = File(p.join(previewDir.path, '${photo.id}_preview.mp4'));
              if (!previewFile.existsSync()) {
                final bytes = await apiService.downloadPreviewBytes(photo.id);
                if (bytes != null && bytes.isNotEmpty) {
                  await previewFile.writeAsBytes(bytes);
                }
              }
              if (previewFile.existsSync()) {
                await db.update(
                  'photos',
                  {'local_preview_path': previewFile.path},
                  where: 'id = ?',
                  whereArgs: [photo.id],
                );
              }
            }
          } catch (_) {}
        }));

        completed += batch.length;
        _syncStatus = '썸네일 저장 중... ($completed/${needsThumb.length})';
        notifyListeners();
      }

      // 로컬 경로 반영을 위해 데이터 리로드
      await photoProvider.loadFromLocal();
    } catch (e) {
      print('로컬 미디어 다운로드 오류: $e');
    }
  }
}
