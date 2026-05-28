import 'package:flutter/material.dart';
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

      final lastSync = await LocalDatabase.getLastSyncTime();
      final data = await apiService.syncData(lastSyncAt: lastSync);

      if (data != null) {
        await photoProvider.applySyncData(data);

        // 동기화 시간 업데이트
        final serverTime = data['server_time'] as String?;
        if (serverTime != null) {
          await LocalDatabase.setLastSyncTime(serverTime);
          _lastSyncTime = serverTime;
        }

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
        .map((q) => {
              'photo_id': q['photo_id'],
              'is_favorite': q['data'] == 'true',
            })
        .toList();

    if (favoriteChanges.isNotEmpty) {
      final success = await apiService.syncFavorites(favoriteChanges);
      if (success) {
        await LocalDatabase.clearOfflineQueue();
      }
    }
  }
}
