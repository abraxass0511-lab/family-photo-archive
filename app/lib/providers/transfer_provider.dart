import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/gallery_service.dart';
import '../services/api_service.dart';

/// 전송 상태 모델
class TransferItem {
  final AssetEntity asset;
  final String? hash;
  File? file;
  double progress;
  TransferStatus status;
  String? errorMessage;

  TransferItem({
    required this.asset,
    this.hash,
    this.file,
    this.progress = 0.0,
    this.status = TransferStatus.pending,
    this.errorMessage,
  });
}

enum TransferStatus { pending, preparing, uploading, done, failed, duplicate, cancelled }

/// 전송 상태 관리 Provider
class TransferProvider extends ChangeNotifier {
  List<AssetEntity> _assets = [];
  final Set<String> _selectedIds = {};
  final List<TransferItem> _transferQueue = [];
  bool _isLoading = false;
  bool _isTransferring = false;
  bool _hasPermission = false;
  int _totalAssetCount = 0;
  int _currentPage = 0;
  bool _hasMore = true;
  final Set<String> _transferredAssetIds = {};
  bool _selectAllCancelled = false;
  bool _cancelRequested = false;
  String? _cancelledAtFile;
  bool _showTransferredOnly = false;
  bool _foregroundServiceInitialized = false;

  // 전송 통계
  int _successCount = 0;
  int _failCount = 0;
  int _duplicateCount = 0;

  // Getters
  List<AssetEntity> get assets => _assets;
  Set<String> get selectedIds => _selectedIds;
  List<TransferItem> get transferQueue => _transferQueue;
  bool get isLoading => _isLoading;
  bool get isTransferring => _isTransferring;
  bool get hasPermission => _hasPermission;
  int get totalAssetCount => _totalAssetCount;
  bool get hasMore => _hasMore;
  int get selectedCount => _selectedIds.length;
  int get successCount => _successCount;
  int get failCount => _failCount;
  int get duplicateCount => _duplicateCount;
  int get transferredCount => _transferredAssetIds.length;
  bool get isCancelRequested => _cancelRequested;
  String? get cancelledAtFile => _cancelledAtFile;
  bool get showTransferredOnly => _showTransferredOnly;

  /// 전송된 것만 필터링된 에셋 목록
  List<AssetEntity> get filteredAssets {
    if (!_showTransferredOnly) return _assets;
    return _assets.where((a) => _transferredAssetIds.contains(a.id)).toList();
  }

  /// 전송됨만 필터 토글
  void toggleTransferredFilter() {
    _showTransferredOnly = !_showTransferredOnly;
    notifyListeners();
  }

  /// 전송된 에셋만 선택
  void selectTransferredOnly() {
    _selectedIds.clear();
    for (final asset in _assets) {
      if (_transferredAssetIds.contains(asset.id)) {
        _selectedIds.add(asset.id);
      }
    }
    notifyListeners();
  }

  /// 에셋이 전송되었는지 확인
  bool isAssetTransferred(String assetId) => _transferredAssetIds.contains(assetId);

  /// 전체 전송 진행률 (0.0 ~ 1.0)
  double get overallProgress {
    if (_transferQueue.isEmpty) return 0;
    final total = _transferQueue.fold<double>(
        0, (sum, item) => sum + item.progress);
    return total / _transferQueue.length;
  }

  // ===================================================================
  // 백그라운드 전송 서비스 (Foreground Service + Wakelock)
  // ===================================================================

  /// Foreground Service 초기화 (한 번만)
  void _initForegroundTask() {
    if (_foregroundServiceInitialized) return;
    _foregroundServiceInitialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'photo_transfer',
        channelName: '사진 전송',
        channelDescription: '사진/동영상을 서버로 전송 중입니다',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// 전송 시작 시 Foreground Service 시작 + Wakelock 켜기
  Future<void> _startForegroundService(int totalCount) async {
    _initForegroundTask();

    try {
      // Wakelock 켜기 (화면 꺼짐 방지)
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('⚠️ Wakelock 활성화 실패: $e');
    }

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: '📤 포토 백업',
        notificationText: '전송 준비 중... (0/$totalCount)',
        callback: _foregroundTaskCallback,
      );
    } catch (e) {
      debugPrint('⚠️ Foreground Service 시작 실패: $e');
    }
  }

  /// 알림바 진행률 업데이트
  Future<void> _updateNotification(int current, int total, String filename) async {
    try {
      final percent = total > 0 ? (current * 100 ~/ total) : 0;
      await FlutterForegroundTask.updateService(
        notificationTitle: '📤 포토 백업 — 전송 중',
        notificationText: '$current/$total ($percent%) • $filename',
      );
    } catch (_) {}
  }

  /// 전송 완료 시 Foreground Service 종료 + Wakelock 끄기
  Future<void> _stopForegroundService({String? resultText}) async {
    try {
      if (resultText != null) {
        await FlutterForegroundTask.updateService(
          notificationTitle: '✅ 포토 백업 완료',
          notificationText: resultText,
        );
        // 2초 후 서비스 종료 (사용자가 알림 볼 시간)
        await Future.delayed(const Duration(seconds: 2));
      }
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('⚠️ Foreground Service 종료 실패: $e');
    }

    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('⚠️ Wakelock 비활성화 실패: $e');
    }
  }

  // ===================================================================
  // 기존 기능
  // ===================================================================

  /// 갤러리 권한 요청 + 초기 로드
  Future<void> initialize() async {
    _hasPermission = await galleryService.requestPermission();
    if (!_hasPermission) return;

    // 알림 권한 요청 (Android 13+, 백그라운드 전송 알림용)
    try {
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}

    await galleryService.loadTransferredHashes();
    await _loadTransferredAssetIds();
    _totalAssetCount = await galleryService.getTotalCount();
    await loadMore();
  }

  /// 저장된 전송 ID 로드
  Future<void> _loadTransferredAssetIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('transferred_asset_ids') ?? [];
    _transferredAssetIds.addAll(ids);
  }

  /// 전송 ID 저장
  Future<void> _saveTransferredAssetIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('transferred_asset_ids', _transferredAssetIds.toList());
  }

  /// 다음 페이지 로드 (무한 스크롤)
  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    notifyListeners();

    final newAssets = await galleryService.loadAssets(
      page: _currentPage,
      pageSize: 80,
    );

    if (newAssets.isEmpty) {
      _hasMore = false;
    } else {
      _assets.addAll(newAssets);
      _currentPage++;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 새로고침 (갤러리 다시 스캔)
  Future<void> refresh() async {
    _assets.clear();
    _selectedIds.clear();
    _currentPage = 0;
    _hasMore = true;
    _totalAssetCount = await galleryService.getTotalCount();
    await loadMore();
  }

  /// 사진 선택/해제
  void toggleSelection(String assetId) {
    if (_selectedIds.contains(assetId)) {
      _selectedIds.remove(assetId);
    } else {
      _selectedIds.add(assetId);
    }
    notifyListeners();
  }

  /// 전체 선택 (모든 에셋 로드)
  Future<void> selectAll() async {
    _selectAllCancelled = false;

    // 이미 로드된 것들 선택
    _selectedIds.addAll(_assets.map((a) => a.id));
    notifyListeners();

    // 나머지 모두 로드
    while (_hasMore && !_selectAllCancelled) {
      await loadMore();
      if (_selectAllCancelled) break;
      _selectedIds.addAll(_assets.map((a) => a.id));
      notifyListeners();
    }
  }

  /// 미전송 사진만 전체 선택
  void selectUntransferred() {
    // 전송 완료 아닌 것만 선택
    for (final asset in _assets) {
      // 해시를 아직 모르면 일단 선택 (전송 시 체크)
      _selectedIds.add(asset.id);
    }
    notifyListeners();
  }

  /// 날짜별 일괄 선택/해제
  void toggleDateSelection(List<String> assetIds) {
    final allSelected = assetIds.every((id) => _selectedIds.contains(id));
    if (allSelected) {
      // 전부 선택되어 있으면 해제
      _selectedIds.removeAll(assetIds);
    } else {
      // 하나라도 미선택이면 전부 선택
      _selectedIds.addAll(assetIds);
    }
    notifyListeners();
  }

  /// 전체 해제
  void clearSelection() {
    _selectAllCancelled = true;
    _selectedIds.clear();
    notifyListeners();
  }

  /// 전송 중지 요청
  void cancelTransfer() {
    if (!_isTransferring) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// 선택한 사진들 서버로 전송
  Future<void> transferSelected() async {
    if (_isTransferring || _selectedIds.isEmpty) return;

    _isTransferring = true;
    _cancelRequested = false;
    _cancelledAtFile = null;
    _successCount = 0;
    _failCount = 0;
    _duplicateCount = 0;
    _transferQueue.clear();
    notifyListeners();

    // 1. 선택된 에셋 찾기
    final selectedAssets =
        _assets.where((a) => _selectedIds.contains(a.id)).toList();

    // 2. 전송 큐 생성
    for (final asset in selectedAssets) {
      _transferQueue.add(TransferItem(asset: asset));
    }
    notifyListeners();

    // 3. 백그라운드 서비스 시작 + Wakelock 켜기
    await _startForegroundService(_transferQueue.length);

    // 4. 순차 전송
    for (int i = 0; i < _transferQueue.length; i++) {
      // 중지 요청 확인 — 현재 파일 전송 전에 체크
      if (_cancelRequested) {
        // 나머지 파일들을 cancelled 상태로 변경
        for (int j = i; j < _transferQueue.length; j++) {
          _transferQueue[j].status = TransferStatus.cancelled;
        }
        notifyListeners();
        break;
      }

      final item = _transferQueue[i];
      final filename = item.asset.title ?? '파일';

      try {
        // 파일 준비
        item.status = TransferStatus.preparing;
        item.progress = 0.05;
        notifyListeners();

        final file = await galleryService.getFile(item.asset);
        if (file == null) {
          item.status = TransferStatus.failed;
          item.errorMessage = '파일을 읽을 수 없습니다';
          _failCount++;
          notifyListeners();
          continue;
        }
        item.file = file;

        // 업로드 (위치 데이터 포함)
        item.status = TransferStatus.uploading;
        item.progress = 0.1;
        notifyListeners();

        // 알림바 업데이트
        await _updateNotification(i + 1, _transferQueue.length, filename);

        // 앱에서 위치 데이터 가져오기 (삼성 갤러리 보정 포함)
        double? lat;
        double? lng;
        try {
          final latLng = await item.asset.latlngAsync();
          if (latLng != null &&
              latLng.latitude != 0 && latLng.longitude != 0) {
            lat = latLng.latitude;
            lng = latLng.longitude;
          }
        } catch (_) {}

        final result = await apiService.uploadPhotoWithProgress(
          file.path,
          onProgress: (sent, total) {
            item.progress = 0.1 + (sent / total) * 0.9;
            notifyListeners();
          },
          latitude: lat,
          longitude: lng,
        );

        if (result != null) {
          item.status = TransferStatus.done;
          item.progress = 1.0;
          _successCount++;
          _transferredAssetIds.add(item.asset.id);
          await _saveTransferredAssetIds();

          // 전송 완료 기록
          final hash = result['photo_id'] as String? ?? '';
          if (hash.isNotEmpty) {
            await galleryService.markAsTransferred(hash);
          }
        } else {
          item.status = TransferStatus.failed;
          item.errorMessage = '서버 응답 오류';
          _failCount++;
        }
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('duplicate:')) {
          item.status = TransferStatus.duplicate;
          item.progress = 1.0;
          // "Exception: duplicate:2026-05-29 이미 전송완료" → "2026-05-29 이미 전송완료"
          final reasonStart = msg.indexOf('duplicate:');
          item.errorMessage = reasonStart >= 0
              ? msg.substring(reasonStart + 'duplicate:'.length)
              : '이미 전송된 파일';
          _duplicateCount++;
        } else if (msg.contains('fail:')) {
          item.status = TransferStatus.failed;
          final reasonStart = msg.indexOf('fail:');
          item.errorMessage = reasonStart >= 0
              ? msg.substring(reasonStart + 'fail:'.length)
              : '전송 실패';
          _failCount++;
        } else {
          item.status = TransferStatus.failed;
          item.errorMessage = '알 수 없는 오류';
          _failCount++;
        }
      }
      notifyListeners();

      // 현재 파일 전송 완료 후 중지 요청 확인
      if (_cancelRequested) {
        _cancelledAtFile = item.asset.title ?? '파일';
        // 나머지 파일들을 cancelled 상태로 변경
        for (int j = i + 1; j < _transferQueue.length; j++) {
          _transferQueue[j].status = TransferStatus.cancelled;
        }
        notifyListeners();
        break;
      }
    }

    // 5. 전송 완료 — 서비스 종료 + Wakelock 끄기
    final resultParts = <String>[];
    if (_successCount > 0) resultParts.add('성공 $_successCount');
    if (_duplicateCount > 0) resultParts.add('중복 $_duplicateCount');
    if (_failCount > 0) resultParts.add('실패 $_failCount');
    final resultText = resultParts.isNotEmpty ? resultParts.join(' · ') : '완료';

    await _stopForegroundService(
      resultText: _cancelRequested
          ? '중지됨 — $resultText'
          : resultText,
    );

    _isTransferring = false;
    _selectedIds.clear();
    notifyListeners();
  }

  /// 전송 완료된 사진들을 폰에서 삭제
  Future<int> deleteTransferred() async {
    final toDelete = _transferQueue
        .where((item) => item.status == TransferStatus.done)
        .map((item) => item.asset)
        .toList();

    if (toDelete.isEmpty) return 0;

    final deletedIds = await galleryService.deleteAssets(toDelete);

    // 삭제된 에셋을 목록에서 제거
    _assets.removeWhere((a) => deletedIds.contains(a.id));
    notifyListeners();

    return deletedIds.length;
  }

  /// 선택한 사진들을 폰에서 바로 삭제 (전송 없이)
  Future<int> deleteSelected() async {
    final toDelete = _assets
        .where((a) => _selectedIds.contains(a.id))
        .toList();

    if (toDelete.isEmpty) return 0;

    final deletedIds = await galleryService.deleteAssets(toDelete);

    // 삭제된 에셋을 목록에서 제거
    _assets.removeWhere((a) => deletedIds.contains(a.id));
    _selectedIds.removeWhere((id) => deletedIds.contains(id));
    _totalAssetCount -= deletedIds.length;
    notifyListeners();

    return deletedIds.length;
  }

  /// 전송 큐 초기화
  void clearQueue() {
    _transferQueue.clear();
    _successCount = 0;
    _failCount = 0;
    _duplicateCount = 0;
    notifyListeners();
  }
}

/// Foreground Task 콜백 (서비스 유지용, 실제 작업은 메인 isolate에서 수행)
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_TransferTaskHandler());
}

/// 더미 태스크 핸들러 (서비스 유지 목적)
class _TransferTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
