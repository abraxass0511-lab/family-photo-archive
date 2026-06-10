import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../providers/photo_provider.dart';
import '../providers/sync_provider.dart';
import '../models/photo_model.dart';
import '../services/api_service.dart';

/// 백업 갤러리 화면 — 서버에 전송된 사진 목록
/// 서버 썸네일을 CachedNetworkImage로 표시
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
    return Consumer2<PhotoProvider, SyncProvider>(
      builder: (context, provider, syncProvider, _) {
        List<PhotoModel> photos = _showFavoritesOnly
            ? provider.favoritePhotos
            : provider.photos;

        // 검색 필터 (즐겨찾기 내에서도 검색)
        if (_searchController.text.isNotEmpty) {
          final q = _searchController.text.toLowerCase();
          photos = photos.where((p) =>
            p.filename.toLowerCase().contains(q) ||
            (p.placeName?.toLowerCase().contains(q) ?? false) ||
            (p.takenAt?.toLowerCase().contains(q) ?? false) ||
            p.persons.any((name) => name.toLowerCase().contains(q))
          ).toList();
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F8),
          body: SafeArea(
            child: Column(
              children: [
                // 툴바
                _buildToolbar(provider, syncProvider),

                // 사진 그리드
                Expanded(
                  child: photos.isEmpty
                      ? _buildEmptyState(syncProvider)
                      : _buildPhotoGrid(photos, provider),
                ),

                // 하단 삭제 바 (선택 모드)
                if (provider.selectedCount > 0)
                  _buildDeleteBar(provider, syncProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 상단 툴바
  Widget _buildToolbar(PhotoProvider provider, SyncProvider syncProvider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          // 제목 + 동기화
          Row(
            children: [
              const Text(
                '백업 갤러리',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),

              // 전체 선택 / 해제 버튼
              if (provider.photos.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    if (provider.selectedCount > 0) {
                      provider.clearSelection();
                    } else {
                      provider.selectAll();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: provider.selectedCount > 0
                          ? const Color(0xFF7C6AEF).withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: provider.selectedCount > 0
                            ? const Color(0xFF7C6AEF).withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      provider.selectedCount > 0
                          ? '해제 (${provider.selectedCount})'
                          : '전체 선택',
                      style: TextStyle(
                        color: provider.selectedCount > 0
                            ? const Color(0xFF7C6AEF)
                            : Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // 동기화 버튼
              GestureDetector(
                onTap: syncProvider.isSyncing
                    ? null
                    : () => syncProvider.sync(provider),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: syncProvider.isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4ECDC4),
                          ),
                        )
                      : Icon(
                          Icons.sync,
                          size: 18,
                          color: syncProvider.isServerOnline
                              ? const Color(0xFF4ECDC4)
                              : Colors.black26,
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 검색 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Icon(Icons.search,
                    color: Colors.black.withValues(alpha: 0.3), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '파일명, 장소 검색...',
                      hintStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.3)),
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
              _filterChip(
                icon: Icons.favorite,
                label: '즐겨찾기',
                isActive: _showFavoritesOnly,
                onTap: () =>
                    setState(() => _showFavoritesOnly = !_showFavoritesOnly),
              ),
              const SizedBox(width: 8),
              Text(
                '${provider.photos.length}장 백업됨',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.4),
                  fontSize: 12,
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
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFF4D6D).withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? const Color(0xFFFF4D6D) : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? const Color(0xFFFF4D6D) : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사진 그리드 — 날짜별 그룹
  Widget _buildPhotoGrid(List<PhotoModel> photos, PhotoProvider provider) {
    // 날짜별 그룹핑
    final grouped = <String, List<PhotoModel>>{};
    for (final photo in photos) {
      String key;
      if (photo.takenAt != null && photo.takenAt!.isNotEmpty) {
        try {
          final dt = DateTime.parse(photo.takenAt!);
          key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {
          key = '날짜 미상';
        }
      } else {
        key = '날짜 미상';
      }
      grouped.putIfAbsent(key, () => []).add(photo);
    }
    final dateKeys = grouped.keys.toList();

    return CustomScrollView(
      slivers: [
        for (final dateKey in dateKeys) ...[
          // 날짜 헤더 (체크박스 포함)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Builder(
                builder: (context) {
                  final datePhotos = grouped[dateKey]!;
                  final datePhotoIds = datePhotos.map((p) => p.id).toList();
                  final allSelected = datePhotoIds.every(
                      (id) => provider.selectedIds.contains(id));
                  final someSelected = !allSelected &&
                      datePhotoIds.any(
                          (id) => provider.selectedIds.contains(id));

                  return GestureDetector(
                    onTap: () => provider.toggleDateSelection(datePhotoIds),
                    child: Row(
                      children: [
                        // 날짜 체크박스
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: allSelected
                                ? const Color(0xFF7C6AEF)
                                : someSelected
                                    ? const Color(0xFF7C6AEF)
                                        .withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.12),
                            border: Border.all(
                              color: allSelected || someSelected
                                  ? const Color(0xFF7C6AEF)
                                  : Colors.black.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: allSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 14)
                              : someSelected
                                  ? const Icon(Icons.remove,
                                      color: Colors.white, size: 14)
                                  : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDateHeader(dateKey),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${datePhotos.length}장',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // 해당 날짜 사진 그리드
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final photo = grouped[dateKey]![index];
                  final isVideoItem = photo.filename.toLowerCase().endsWith('.mp4') ||
                      photo.filename.toLowerCase().endsWith('.mov') ||
                      photo.filename.toLowerCase().endsWith('.3gp');
                  final isSelected = provider.selectedIds.contains(photo.id);

                  return GestureDetector(
                    onTap: () {
                      // 선택 모드이면 선택/해제, 아니면 상세보기
                      if (provider.selectMode) {
                        provider.toggleSelection(photo.id);
                      } else {
                        _showPhotoDetail(photo, provider);
                      }
                    },
                    onLongPress: () {
                      // 롱프레스로 선택 모드 진입
                      if (!provider.selectMode) {
                        provider.toggleSelectMode();
                      }
                      provider.toggleSelection(photo.id);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0xFFE8E8F0),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _buildThumbnail(photo),
                          ),
                        ),
                        // 동영상 재생 아이콘
                        if (isVideoItem)
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_arrow, color: Colors.white, size: 14),
                                  SizedBox(width: 2),
                                  Text('동영상', style: TextStyle(color: Colors.white, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        if (photo.isFavorite)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Text('❤️', style: TextStyle(fontSize: 14)),
                          ),
                        // 선택 체크 마크
                        Positioned(
                          top: 4,
                          left: 4,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? const Color(0xFF7C6AEF)
                                  : Colors.black.withValues(alpha: 0.3),
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
                              border: Border.all(
                                  color: const Color(0xFF7C6AEF), width: 3),
                            ),
                          ),
                      ],
                    ),
                  );
                },
                childCount: grouped[dateKey]!.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 날짜 헤더 포맷
  String _formatDateHeader(String dateKey) {
    if (dateKey == '날짜 미상') return dateKey;
    try {
      final dt = DateTime.parse(dateKey);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final weekday = weekdays[dt.weekday - 1];
      return '$dateKey ($weekday)';
    } catch (_) {
      return dateKey;
    }
  }

  /// 썸네일 표시 (서버에서 로드)
  Widget _buildThumbnail(PhotoModel photo) {
    // 서버 썸네일 URL
    final thumbUrl = apiService.getThumbnailUrl(photo.id);

    return CachedNetworkImage(
      imageUrl: thumbUrl,
      fit: BoxFit.cover,
      httpHeaders: const {},
      placeholder: (context, url) => _buildPlaceholder(photo),
      errorWidget: (context, url, error) => _buildPlaceholder(photo),
    );
  }

  /// 플레이스홀더 (썸네일 로드 실패 시)
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              photo.filename.endsWith('.mp4') ||
                      photo.filename.endsWith('.mov')
                  ? '🎬'
                  : '📸',
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                photo.filename,
                style: const TextStyle(
                    fontSize: 8, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사진 상세 — 전체화면 뷰어
  void _showPhotoDetail(PhotoModel photo, PhotoProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerPage(photo: photo, provider: provider),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.7), fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(SyncProvider syncProvider) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('📷',
              style: TextStyle(
                  fontSize: 48,
                  color: Colors.black.withValues(alpha: 0.3))),
          const SizedBox(height: 16),
          Text(
            _showFavoritesOnly ? '즐겨찾기한 사진이 없습니다' : '백업된 사진이 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            syncProvider.isServerOnline
                ? '전송 탭에서 사진을 전송하면 여기에 표시됩니다'
                : '설정에서 서버를 연결해주세요',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 삭제 바
  Widget _buildDeleteBar(PhotoProvider provider, SyncProvider syncProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF4D6D), Color(0xFFFF2D55)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4D6D).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Text(
                    '🗑️ 서버에서 삭제',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${provider.selectedCount}개',
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
            // 해제 버튼
            GestureDetector(
              onTap: () => provider.clearSelection(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '해제',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 삭제 버튼
            GestureDetector(
              onTap: () => _confirmDeleteSelected(provider, syncProvider),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '삭제',
                  style: TextStyle(
                    color: Color(0xFFFF4D6D),
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
  void _confirmDeleteSelected(PhotoProvider provider, SyncProvider syncProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('백업 사진 삭제',
            style: TextStyle(
                color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600)),
        content: Text(
          '${provider.selectedCount}개의 사진/동영상을 서버에서 삭제합니다.\n\n'
          '⚠️ DB 레코드, 썸네일, 버퍼 파일이 모두 삭제됩니다.\n'
          '• 외장하드에 이미 이관된 파일은 유지됩니다.',
          style: const TextStyle(color: Color(0xFF444444), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4D6D),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final deleted = await provider.deleteSelected();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ $deleted개 사진 삭제 완료'),
                    backgroundColor: const Color(0xFFFF4D6D),
                  ),
                );
                // 삭제 후 자동 동기화
                await syncProvider.sync(provider);
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// 전체화면 사진/동영상 뷰어
class _PhotoViewerPage extends StatefulWidget {
  final PhotoModel photo;
  final PhotoProvider provider;

  const _PhotoViewerPage({required this.photo, required this.provider});

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoError = false;
  bool _isPlaying = false;
  String _videoErrorMsg = '';

  bool get _isVideo {
    final fn = widget.photo.filename.toLowerCase();
    return fn.endsWith('.mp4') || fn.endsWith('.mov') || fn.endsWith('.3gp');
  }

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final url = apiService.getOriginalFileUrl(widget.photo.id);
    _videoErrorMsg = url;
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController!.addListener(() {
        if (mounted) {
          final playing = _videoController!.value.isPlaying;
          if (playing != _isPlaying) {
            setState(() => _isPlaying = playing);
          }
        }
      });
      await _videoController!.initialize();
      if (mounted) {
        setState(() => _isVideoInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVideoError = true;
          _videoErrorMsg = '$url\n에러: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = apiService.getOriginalFileUrl(widget.photo.id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.photo.filename,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              widget.photo.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.photo.isFavorite
                  ? const Color(0xFFFF4D6D)
                  : Colors.white54,
            ),
            onPressed: () {
              widget.provider.toggleFavorite(widget.photo.id);
              Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white54),
            onPressed: () => _showInfoSheet(context),
          ),
        ],
      ),
      body: _isVideo ? _buildVideoPlayer() : _buildImageViewer(imageUrl),
    );
  }

  Widget _buildImageViewer(String imageUrl) {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                color: Colors.white38,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (_, error, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, color: Colors.white38, size: 48),
                const SizedBox(height: 8),
                Text('$error',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isVideoError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              const Text('동영상을 재생할 수 없습니다',
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 8),
              Text(_videoErrorMsg,
                  style: const TextStyle(color: Colors.white24, fontSize: 9),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (!_isVideoInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white38),
            SizedBox(height: 12),
            Text('동영상 로딩 중...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          // 동영상 영역 + 재생 버튼 오버레이
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoController!),
                      // 큰 재생/일시정지 버튼 (영상 위 오버레이)
                      AnimatedOpacity(
                        opacity: _isPlaying ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 하단 컨트롤
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 프로그레스 바
                VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF7C6AEF),
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 8),
                // 컨트롤 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white70, size: 28),
                      onPressed: () {
                        final pos = _videoController!.value.position;
                        _videoController!.seekTo(pos - const Duration(seconds: 10));
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white70, size: 28),
                      onPressed: () {
                        final pos = _videoController!.value.position;
                        _videoController!.seekTo(pos + const Duration(seconds: 10));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _infoRow(Icons.insert_drive_file, widget.photo.filename),
              _infoRow(
                  Icons.calendar_today, widget.photo.takenAt ?? '날짜 없음'),
              _infoRow(Icons.place, widget.photo.placeName ?? '위치 미상'),
              _infoRow(
                  Icons.camera_alt, widget.photo.cameraModel ?? '카메라 미상'),
              _infoRow(Icons.cloud_done,
                  widget.photo.isBackedUp ? '백업 완료' : '백업 대기'),
              if (widget.photo.fileSize != null)
                _infoRow(Icons.storage,
                    '${(widget.photo.fileSize! / 1024 / 1024).toStringAsFixed(1)}MB'),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
