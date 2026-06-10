import 'package:flutter/material.dart';
import '../models/photo_model.dart';
import '../db/local_database.dart';

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

    // 로컬 DB 전체 교체 (삭제된 항목 반영)
    await LocalDatabase.clearPhotos();
    await LocalDatabase.bulkUpsertPhotos(photoList);
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
    // 백업 완료된 사진만 선택 가능
    final photo = _photos.firstWhere((p) => p.id == photoId,
        orElse: () => PhotoModel(id: '', filename: ''));
    if (!photo.isBackedUp) return;

    if (_selectedIds.contains(photoId)) {
      _selectedIds.remove(photoId);
    } else {
      _selectedIds.add(photoId);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _selectMode = false;
    notifyListeners();
  }

  int get selectedCount => _selectedIds.length;

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
