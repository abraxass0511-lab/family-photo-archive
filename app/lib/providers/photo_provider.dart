import 'package:flutter/material.dart';
import '../models/photo_model.dart';
import '../db/local_database.dart';
import '../services/api_service.dart';

/// 사진 데이터 상태 관리
class PhotoProvider extends ChangeNotifier {
  List<PhotoModel> _photos = [];
  List<PersonModel> _persons = [];
  List<PlaceModel> _places = [];
  bool _isLoading = false;
  bool _selectMode = false;
  Set<String> _selectedIds = {};

  // Getters
  List<PhotoModel> get photos => _photos;
  List<PersonModel> get persons => _persons;
  List<PlaceModel> get places => _places;
  bool get isLoading => _isLoading;
  bool get selectMode => _selectMode;
  Set<String> get selectedIds => _selectedIds;

  /// 로컬 DB에서 데이터 로드
  Future<void> loadFromLocal() async {
    _isLoading = true;
    notifyListeners();

    _photos = await LocalDatabase.getAllPhotos();
    _isLoading = false;
    notifyListeners();
  }

  /// 위치 있는 사진만 (지도용)
  List<PhotoModel> get photosWithLocation =>
      _photos.where((p) => p.latitude != null && p.longitude != null).toList();

  /// 백업 완료된 사진만
  List<PhotoModel> get backedUpPhotos =>
      _photos.where((p) => p.isBackedUp).toList();

  /// 즐겨찾기 사진만
  List<PhotoModel> get favoritePhotos =>
      _photos.where((p) => p.isFavorite).toList();

  /// 인물별 사진
  List<PhotoModel> photosByPerson(String personName) =>
      _photos.where((p) => p.persons.contains(personName)).toList();

  /// 즐겨찾기 토글 (오프라인 지원)
  Future<void> toggleFavorite(String photoId) async {
    final index = _photos.indexWhere((p) => p.id == photoId);
    if (index < 0) return;

    final newFav = !_photos[index].isFavorite;
    _photos[index] = _photos[index].copyWith(isFavorite: newFav);

    await LocalDatabase.toggleFavorite(photoId, newFav);
    notifyListeners();
  }

  /// 동기화 데이터 적용
  Future<void> applySyncData(Map<String, dynamic> data) async {
    final photoList = (data['photos'] as List<dynamic>?)
            ?.map((j) => PhotoModel.fromJson(j))
            .toList() ??
        [];

    _persons = (data['persons'] as List<dynamic>?)
            ?.map((j) => PersonModel.fromJson(j))
            .toList() ??
        [];

    _places = (data['places'] as List<dynamic>?)
            ?.map((j) => PlaceModel.fromJson(j))
            .toList() ??
        [];

    // 기존 로컬 경로 백업 (동기화 시 보존)
    final db = await LocalDatabase.database;
    final existingRows = await db.query('photos',
        columns: ['id', 'local_thumbnail_path', 'local_preview_path']);
    final localPaths = <String, Map<String, String?>>{};
    for (final row in existingRows) {
      localPaths[row['id'] as String] = {
        'local_thumbnail_path': row['local_thumbnail_path'] as String?,
        'local_preview_path': row['local_preview_path'] as String?,
      };
    }

    // 로컬 DB 전체 교체 (삭제된 항목 반영)
    await LocalDatabase.clearPhotos();

    // 로컬 경로 복원하여 삽입
    final photosWithLocalPaths = photoList.map((p) {
      final saved = localPaths[p.id];
      if (saved != null) {
        return p.copyWith(
          localThumbnailPath: saved['local_thumbnail_path'],
          localPreviewPath: saved['local_preview_path'],
        );
      }
      return p;
    }).toList();

    await LocalDatabase.bulkUpsertPhotos(photosWithLocalPaths);
    _photos = await LocalDatabase.getAllPhotos();

    notifyListeners();
  }

  // === 선택 모드 (다중 선택 + 삭제) ===

  void toggleSelectMode() {
    _selectMode = !_selectMode;
    if (!_selectMode) _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelection(String photoId) {
    if (_selectedIds.contains(photoId)) {
      _selectedIds.remove(photoId);
    } else {
      _selectedIds.add(photoId);
    }
    // 선택이 없으면 선택 모드 자동 해제
    if (_selectedIds.isEmpty) _selectMode = false;
    notifyListeners();
  }

  /// 날짜별 전체 선택/해제 (날짜 헤더 클릭 시)
  void toggleDateSelection(List<String> photoIds) {
    final allSelected = photoIds.every((id) => _selectedIds.contains(id));
    if (allSelected) {
      // 전부 선택됨 → 전부 해제
      _selectedIds.removeAll(photoIds);
    } else {
      // 하나라도 미선택 → 전부 선택
      _selectedIds.addAll(photoIds);
    }
    _selectMode = _selectedIds.isNotEmpty;
    notifyListeners();
  }

  /// 전체 사진 선택
  void selectAll() {
    _selectedIds = _photos.map((p) => p.id).toSet();
    _selectMode = _selectedIds.isNotEmpty;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _selectMode = false;
    notifyListeners();
  }

  int get selectedCount => _selectedIds.length;

  /// 선택한 사진 서버에서 삭제
  Future<int> deleteSelected() async {
    if (_selectedIds.isEmpty) return 0;

    final idsToDelete = _selectedIds.toList();
    final deleted = await apiService.deletePhotos(idsToDelete);

    if (deleted > 0) {
      // 로컬 리스트에서 제거
      _photos.removeWhere((p) => idsToDelete.contains(p.id));
      _selectedIds.clear();
      _selectMode = false;

      // 로컬 DB도 갱신
      await LocalDatabase.clearPhotos();
      await LocalDatabase.bulkUpsertPhotos(_photos);

      notifyListeners();
    }

    return deleted;
  }

  /// 검색
  List<PhotoModel> search(String query) {
    final q = query.toLowerCase();
    return _photos.where((p) {
      return (p.placeName?.toLowerCase().contains(q) ?? false) ||
          p.filename.toLowerCase().contains(q) ||
          p.persons.any((name) => name.toLowerCase().contains(q));
    }).toList();
  }
}
