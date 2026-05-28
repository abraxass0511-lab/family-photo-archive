import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import '../models/photo_model.dart';

/// 갤러리 화면 (사진 그리드 + 다중선택 + 붉은색 삭제 바)
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _searchController = TextEditingController();
  bool _showFavoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        List<PhotoModel> photos = _showFavoritesOnly
            ? provider.favoritePhotos
            : provider.photos;

        // 검색 필터
        if (_searchController.text.isNotEmpty) {
          photos = provider.search(_searchController.text);
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: SafeArea(
            child: Column(
              children: [
                // 툴바
                _buildToolbar(provider),

                // 사진 그리드
                Expanded(
                  child: photos.isEmpty
                      ? _buildEmptyState()
                      : _buildPhotoGrid(photos, provider),
                ),

                // 하단 삭제 바 (선택 모드)
                if (provider.selectMode && provider.selectedCount > 0)
                  _buildDeleteBar(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 상단 툴바
  Widget _buildToolbar(PhotoProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          // 검색 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.white.withValues(alpha: 0.3), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '사진, 장소, 인물 검색...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 필터 버튼
          Row(
            children: [
              // 즐겨찾기 필터
              _filterChip(
                icon: Icons.favorite,
                label: '즐겨찾기',
                isActive: _showFavoritesOnly,
                onTap: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
              ),

              const SizedBox(width: 8),

              // 사진 수 표시
              Text(
                '${provider.photos.length}장',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),

              const Spacer(),

              // 선택 모드 버튼
              GestureDetector(
                onTap: () => provider.toggleSelectMode(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: provider.selectMode
                        ? const Color(0xFF7C6AEF).withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: provider.selectMode
                          ? const Color(0xFF7C6AEF).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Text(
                    provider.selectMode ? '취소' : '선택',
                    style: TextStyle(
                      color: provider.selectMode
                          ? const Color(0xFF7C6AEF)
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFF4D6D).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFF4D6D).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? const Color(0xFFFF4D6D) : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? const Color(0xFFFF4D6D) : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사진 그리드
  Widget _buildPhotoGrid(List<PhotoModel> photos, PhotoProvider provider) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        final isSelected = provider.selectedIds.contains(photo.id);

        return GestureDetector(
          onTap: () {
            if (provider.selectMode) {
              provider.toggleSelection(photo.id);
            } else {
              _showPhotoDetail(photo, provider);
            }
          },
          onLongPress: () {
            if (!provider.selectMode) {
              provider.toggleSelectMode();
              provider.toggleSelection(photo.id);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 사진 카드
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF2A2A3D),
                  // 백업 완료: 초록 테두리
                  border: photo.isBackedUp
                      ? Border.all(color: const Color(0xFF4ECDC4), width: 2)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    photo.isBackedUp ? 8 : 10,
                  ),
                  child: photo.thumbnailPath != null
                      ? Image.asset(photo.thumbnailPath!, fit: BoxFit.cover)
                      : _buildPlaceholder(photo),
                ),
              ),

              // 선택 체크박스
              if (provider.selectMode)
                Positioned(
                  top: 6,
                  left: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF7C6AEF)
                          : Colors.black.withValues(alpha: 0.4),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7C6AEF)
                            : Colors.white.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : null,
                  ),
                ),

              // 선택 오버레이
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF7C6AEF), width: 3),
                  ),
                ),

              // 즐겨찾기 하트
              if (photo.isFavorite && !provider.selectMode)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Text('❤️', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 플레이스홀더
  Widget _buildPlaceholder(PhotoModel photo) {
    final colors = [
      const Color(0xFF7C6AEF),
      const Color(0xFF4ECDC4),
      const Color(0xFFF7A072),
      const Color(0xFFFF6B9D),
    ];
    final color = colors[photo.id.hashCode.abs() % colors.length];

    return Container(
      color: color,
      child: Center(
        child: Text(
          photo.placeName?.substring(0, 1) ?? '📸',
          style: const TextStyle(fontSize: 32, color: Colors.white),
        ),
      ),
    );
  }

  /// 하단 붉은색 삭제 바
  Widget _buildDeleteBar(PhotoProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF4D6D), Color(0xFFE63946)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x4DFF4D6D),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 선택 정보
            Expanded(
              child: Row(
                children: [
                  const Text(
                    '📱 폰에서 삭제',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${provider.selectedCount}장',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 삭제 버튼
            GestureDetector(
              onTap: () => _confirmDelete(provider),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '🗑️ 삭제',
                  style: TextStyle(
                    color: Color(0xFFE63946),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 삭제 확인 다이얼로그
  void _confirmDelete(PhotoProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('선택 사진 삭제'),
        content: Text(
          '${provider.selectedCount}장의 사진을 폰에서 삭제합니다.\n\n'
          '• 외장하드 원본은 유지됩니다.\n'
          '• 웹 미리보기도 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE63946),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: API 호출로 삭제 실행
              provider.clearSelection();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ 삭제 요청이 전송되었습니다')),
              );
            },
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 사진 상세 모달
  void _showPhotoDetail(PhotoModel photo, PhotoProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 핸들
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 파일명
              Text(
                photo.filename,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // 메타데이터
              _metaRow(Icons.calendar_today, photo.takenAt ?? '날짜 없음'),
              _metaRow(Icons.place, photo.placeName ?? '위치 미상'),
              _metaRow(Icons.people, photo.persons.isEmpty
                  ? '인물 없음'
                  : photo.persons.join(', ')),
              _metaRow(Icons.cloud_done,
                  photo.isBackedUp ? '✅ 백업 완료' : '⏳ 백업 대기'),

              const SizedBox(height: 20),

              // 즐겨찾기 토글
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    provider.toggleFavorite(photo.id);
                    Navigator.pop(ctx);
                  },
                  icon: Icon(
                    photo.isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  label: Text(photo.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가'),
                  style: FilledButton.styleFrom(
                    backgroundColor: photo.isFavorite
                        ? const Color(0xFFFF4D6D)
                        : const Color(0xFF2A2A3D),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('📷', style: TextStyle(fontSize: 48, color: Colors.white.withValues(alpha: 0.3))),
          const SizedBox(height: 16),
          Text(
            _showFavoritesOnly ? '즐겨찾기한 사진이 없습니다' : '사진이 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '서버와 동기화하면 사진이 표시됩니다',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
