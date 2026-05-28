import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import '../models/photo_model.dart';

/// 지도 화면 (OpenStreetMap + flutter_map, 100% 무료)
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<PhotoModel> _selectedPlacePhotos = [];
  String? _selectedPlaceName;

  // 대한민국 중심 좌표
  static const _defaultCenter = LatLng(36.5, 127.5);
  static const _defaultZoom = 7.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        final photosWithLoc = provider.photosWithLocation;

        return Stack(
          children: [
            // 지도
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: _defaultZoom,
                maxZoom: 18,
                minZoom: 3,
                onTap: (_, __) => _closeBottomSheet(),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                // OpenStreetMap 다크 타일 (CartoDB, 100% 무료)
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.family.photoarchive',
                  retinaMode: true,
                ),

                // 마커 클러스터
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 60,
                    size: const Size(44, 44),
                    markers: _buildMarkers(photosWithLoc),
                    builder: (context, markers) => _clusterWidget(markers.length),
                    spiderfyCircleRadius: 60,
                    animationsOptions: const AnimationsOptions(
                      zoom: Duration(milliseconds: 300),
                    ),
                  ),
                ),
              ],
            ),

            // 상단 검색 바
            _buildSearchBar(),

            // 하단 사진 갤러리 (마커 터치 시)
            if (_selectedPlacePhotos.isNotEmpty) _buildBottomGallery(),

            // 동기화 상태 표시
            _buildSyncIndicator(),
          ],
        );
      },
    );
  }

  /// 마커 생성
  List<Marker> _buildMarkers(List<PhotoModel> photos) {
    // 장소별 그룹핑
    final placeGroups = <String, List<PhotoModel>>{};
    for (final photo in photos) {
      final key = '${photo.latitude!.toStringAsFixed(3)}_${photo.longitude!.toStringAsFixed(3)}';
      placeGroups.putIfAbsent(key, () => []).add(photo);
    }

    return placeGroups.entries.map((entry) {
      final photos = entry.value;
      final first = photos.first;

      return Marker(
        point: LatLng(first.latitude!, first.longitude!),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _onMarkerTap(photos),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C6AEF), Color(0xFF9B59B6)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C6AEF).withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '${photos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  /// 클러스터 위젯
  Widget _clusterWidget(int count) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C6AEF).withValues(alpha: 0.8),
            const Color(0xFF9B59B6).withValues(alpha: 0.8),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  /// 마커 터치 → 하단 갤러리 표시 (1초 이내 렌더링)
  void _onMarkerTap(List<PhotoModel> photos) {
    setState(() {
      _selectedPlacePhotos = photos;
      _selectedPlaceName = photos.first.placeName ?? '알 수 없는 장소';
    });
  }

  void _closeBottomSheet() {
    setState(() {
      _selectedPlacePhotos = [];
      _selectedPlaceName = null;
    });
  }

  /// 상단 검색 바
  Widget _buildSearchBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A28).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '장소 검색...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 하단 사진 갤러리 (핀 터치 시 슬라이드업)
  Widget _buildBottomGallery() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A28).withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 장소명 + 사진 수
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedPlaceName ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C6AEF).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_selectedPlacePhotos.length}장',
                      style: const TextStyle(
                        color: Color(0xFF7C6AEF),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 가로 스크롤 썸네일
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: _selectedPlacePhotos.length,
                itemBuilder: (context, index) {
                  final photo = _selectedPlacePhotos[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A3D),
                          border: photo.isBackedUp
                              ? Border.all(color: const Color(0xFF4ECDC4), width: 2)
                              : null,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 썸네일 또는 플레이스홀더
                            if (photo.thumbnailPath != null)
                              Image.asset(photo.thumbnailPath!, fit: BoxFit.cover)
                            else
                              Center(
                                child: Text(
                                  photo.placeName?.substring(0, 1) ?? '📸',
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),

                            // 즐겨찾기 하트
                            if (photo.isFavorite)
                              const Positioned(
                                top: 6,
                                right: 6,
                                child: Text('❤️', style: TextStyle(fontSize: 14)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 동기화 인디케이터
  Widget _buildSyncIndicator() {
    return Positioned(
      bottom: _selectedPlacePhotos.isNotEmpty ? 200 : 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A28).withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(
          Icons.my_location,
          color: Colors.white.withValues(alpha: 0.6),
          size: 20,
        ),
      ),
    );
  }
}
