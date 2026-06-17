import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import '../providers/transfer_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/photo_provider.dart';
import '../services/gallery_service.dart';

/// 전송 메인 화면 — 갤러리 사진 그리드 + 다중 선택 + 전송
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransferProvider>().initialize();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      context.read<TransferProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransferProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F8),
          body: SafeArea(
            child: Column(
              children: [
                // 상단 헤더
                _buildHeader(provider),

                // 권한 미허용 시
                if (!provider.hasPermission)
                  _buildPermissionRequest(provider)

                // 갤러리 그리드
                else
                  Expanded(
                    child: Stack(
                      children: [
                        _buildGalleryGrid(provider),

                        // 전송 진행 중일 때 하단 진행률
                        if (provider.isTransferring)
                          _buildTransferProgress(provider),

                        // 전송 완료 결과
                        if (!provider.isTransferring &&
                            provider.transferQueue.isNotEmpty)
                          _buildTransferResult(provider),
                      ],
                    ),
                  ),

                // 하단 전송 바
                if (provider.selectedCount > 0 && !provider.isTransferring)
                  _buildTransferBar(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 상단 헤더
  Widget _buildHeader(TransferProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀
          Row(
            children: [
              const Text(
                '갤러리',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),

              // 새로고침
              IconButton(
                onPressed: provider.isLoading ? null : () => provider.refresh(),
                icon: Icon(
                  Icons.refresh,
                  color: Colors.black.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 통계 바
          Row(
            children: [
              _statChip(
                icon: Icons.photo_library,
                label: '전체 ${provider.totalAssetCount}',
                color: Colors.black54,
              ),
              const SizedBox(width: 8),
              _statChip(
                icon: Icons.cloud_done,
                label: '전송됨 ${provider.transferredCount}',
                color: const Color(0xFF4ECDC4),
              ),
              const Spacer(),

              // 전송됨만 선택 버튼
              if (provider.assets.isNotEmpty && provider.showTransferredOnly) ...[
                GestureDetector(
                  onTap: () => provider.selectTransferredOnly(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ECDC4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF4ECDC4).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      '전체 선택',
                      style: TextStyle(
                        color: Color(0xFF4ECDC4),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // 선택 버튼
              if (provider.assets.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    if (provider.selectedCount > 0) {
                      provider.clearSelection();
                    } else {
                      provider.selectAll();
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
              ],
            ],
          ),

          const SizedBox(height: 8),

          // 필터 칩
          Row(
            children: [
              _filterChip(
                icon: Icons.cloud_done,
                label: '전송됨만',
                isActive: provider.showTransferredOnly,
                activeColor: const Color(0xFF4ECDC4),
                onTap: () => provider.toggleTransferredFilter(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Color activeColor = const Color(0xFF7C6AEF),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? activeColor : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? activeColor : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 권한 요청 화면
  Widget _buildPermissionRequest(TransferProvider provider) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 64, color: Colors.black.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            Text(
              '갤러리 접근 권한이 필요합니다',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '사진과 동영상을 서버로 전송하려면\n갤러리 접근을 허용해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => provider.initialize(),
              icon: const Icon(Icons.lock_open),
              label: const Text('권한 허용하기'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C6AEF),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 갤러리 사진 그리드 (날짜별 그룹)
  Widget _buildGalleryGrid(TransferProvider provider) {
    final displayAssets = provider.filteredAssets;

    if (displayAssets.isEmpty && provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C6AEF)),
      );
    }

    if (displayAssets.isEmpty) {
      return Center(
        child: Text(
          provider.showTransferredOnly ? '전송된 사진이 없습니다' : '사진이 없습니다',
          style: TextStyle(
            fontSize: 16,
            color: Colors.black.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    // 날짜별 그룹핑
    final grouped = <String, List<AssetEntity>>{};
    for (final asset in displayAssets) {
      final date = asset.createDateTime;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(asset);
    }
    final dateKeys = grouped.keys.toList(); // 이미 최신순

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        for (final dateKey in dateKeys) ...[
          // 날짜 헤더 (체크박스 포함)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Builder(
                builder: (context) {
                  final dateAssets = grouped[dateKey]!;
                  final dateAssetIds = dateAssets.map((a) => a.id).toList();
                  final allSelected = dateAssetIds.every(
                      (id) => provider.selectedIds.contains(id));
                  final someSelected = !allSelected &&
                      dateAssetIds.any(
                          (id) => provider.selectedIds.contains(id));

                  return GestureDetector(
                    onTap: () => provider.toggleDateSelection(dateAssetIds),
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
                          '${dateAssets.length}장',
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
                crossAxisCount: 4,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildAssetTile(provider, grouped[dateKey]![index]),
                childCount: grouped[dateKey]!.length,
              ),
            ),
          ),
        ],
        // 로딩 표시
        if (provider.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C6AEF)),
              ),
            ),
          ),
      ],
    );
  }

  /// 날짜 헤더 포맷: "2026-05-29 (금)"
  String _formatDateHeader(String dateKey) {
    try {
      final dt = DateTime.parse(dateKey);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final weekday = weekdays[dt.weekday - 1];
      return '$dateKey ($weekday)';
    } catch (_) {
      return dateKey;
    }
  }

  /// 개별 사진 타일
  Widget _buildAssetTile(TransferProvider provider, AssetEntity asset) {
    final isSelected = provider.selectedIds.contains(asset.id);
    final isVideo = asset.type == AssetType.video;
    final isTransferred = provider.isAssetTransferred(asset.id);

    return GestureDetector(
      onTap: () => provider.toggleSelection(asset.id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 썸네일
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize(200, 200),
              quality: 80,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              }
              return Container(color: const Color(0xFFE8E8F0));
            },
          ),

          // 전송 완료 반투명 오버레이
          if (isTransferred)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
            ),

          // 동영상 아이콘 + 길이
          if (isVideo)
            Positioned(
              bottom: 4,
              right: isTransferred ? 28 : 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(asset.videoDuration),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),

          // 전송 완료 초록색 체크
          if (isTransferred)
            Positioned(
              bottom: 3,
              right: 3,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF4ECDC4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(Icons.cloud_done, color: Colors.white, size: 13),
              ),
            ),

          // 선택 체크
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
                border:
                    Border.all(color: const Color(0xFF7C6AEF), width: 3),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 하단 전송 바 (전송 + 삭제)
  Widget _buildTransferBar(TransferProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C6AEF), Color(0xFF6A5ACD)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C6AEF).withValues(alpha: 0.4),
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
                    '📤 서버로 전송',
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
            // 삭제 버튼
            GestureDetector(
              onTap: () => _confirmDeleteSelected(provider),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D6D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline, color: Colors.white, size: 18),
                    SizedBox(width: 4),
                    Text(
                      '삭제',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 전송 버튼
            GestureDetector(
              onTap: () async {
                await provider.transferSelected();
                // 전송 완료 후 백업 갤러리 자동 동기화
                if (mounted) {
                  final syncProv = context.read<SyncProvider>();
                  final photoProv = context.read<PhotoProvider>();
                  await syncProv.sync(photoProv);
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '전송 시작',
                  style: TextStyle(
                    color: Color(0xFF7C6AEF),
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

  /// 전송 진행률 바텀 시트
  Widget _buildTransferProgress(TransferProvider provider) {
    final queue = provider.transferQueue;
    final currentIndex =
        queue.indexWhere((item) => item.status == TransferStatus.uploading);
    final current = currentIndex >= 0 ? queue[currentIndex] : null;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
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
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목 + 중지 버튼
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF7C6AEF),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          provider.isCancelRequested
                              ? '중지 중... 현재 파일 전송 완료 후 중지됩니다'
                              : '전송 중... (${provider.successCount + provider.duplicateCount}/${queue.length})',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: provider.isCancelRequested
                                ? const Color(0xFFFF4D6D)
                                : const Color(0xFF1A1A2E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 중지 버튼
                      if (!provider.isCancelRequested)
                        GestureDetector(
                          onTap: () => provider.cancelTransfer(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4D6D),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stop_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  '중지',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 전체 진행률 바
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: provider.overallProgress,
                      backgroundColor: Colors.black.withValues(alpha: 0.05),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF7C6AEF)),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 현재 전송 중인 파일
                  if (current != null)
                    Text(
                      '${current.asset.title ?? "파일"} (${(current.progress * 100).toInt()}%)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),

                  // 통계
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _miniStat('✅', '${provider.successCount}',
                          const Color(0xFF4ECDC4)),
                      const SizedBox(width: 12),
                      _miniStat('⏭️', '${provider.duplicateCount}',
                          Colors.orange),
                      const SizedBox(width: 12),
                      _miniStat('❌', '${provider.failCount}',
                          const Color(0xFFFF4D6D)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String emoji, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 3),
        Text(count, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  /// 전송 완료 결과
  Widget _buildTransferResult(TransferProvider provider) {
    final wasCancelled = provider.cancelledAtFile != null;
    final cancelledCount = provider.transferQueue
        .where((item) => item.status == TransferStatus.cancelled)
        .length;

    // 중복/실패 항목 수집
    final duplicateItems = provider.transferQueue
        .where((item) => item.status == TransferStatus.duplicate)
        .toList();
    final failedItems = provider.transferQueue
        .where((item) => item.status == TransferStatus.failed)
        .toList();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 완료/중지 아이콘
                Text(wasCancelled ? '⏹️' : '🎉',
                    style: const TextStyle(fontSize: 32)),
                const SizedBox(height: 10),
                Text(
                  wasCancelled ? '전송 중지됨' : '전송 완료!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: wasCancelled
                        ? const Color(0xFFFF4D6D)
                        : const Color(0xFF1A1A2E),
                  ),
                ),
                if (wasCancelled) ...[
                  const SizedBox(height: 6),
                  Text(
                    '"${provider.cancelledAtFile}" 까지 전송 완료',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),

                // 결과 요약
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _resultChip('성공', '${provider.successCount}',
                        const Color(0xFF4ECDC4)),
                    const SizedBox(width: 10),
                    if (provider.duplicateCount > 0)
                      _resultChip('중복', '${provider.duplicateCount}',
                          Colors.orange),
                    if (provider.failCount > 0) ...[
                      const SizedBox(width: 10),
                      _resultChip('실패', '${provider.failCount}',
                          const Color(0xFFFF4D6D)),
                    ],
                    if (cancelledCount > 0) ...[
                      const SizedBox(width: 10),
                      _resultChip('미전송', '$cancelledCount',
                          Colors.grey),
                    ],
                  ],
                ),

                // 중복 사유 목록
                if (duplicateItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildReasonSection(
                    icon: Icons.content_copy,
                    title: '중복 사유',
                    color: Colors.orange,
                    items: duplicateItems,
                  ),
                ],

                // 실패 사유 목록
                if (failedItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildReasonSection(
                    icon: Icons.error_outline,
                    title: '실패 사유',
                    color: const Color(0xFFFF4D6D),
                    items: failedItems,
                  ),
                ],

                const SizedBox(height: 20),

                // 버튼들
                Row(
                  children: [
                    // 닫기
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => provider.clearQueue(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('닫기',
                            style: TextStyle(color: Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 전송된 사진 삭제
                    if (provider.successCount > 0)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _confirmDelete(provider),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('폰에서 삭제'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4D6D),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 중복/실패 사유 섹션
  Widget _buildReasonSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<TransferItem> items,
  }) {
    // 같은 사유끼리 그룹핑
    final reasonGroups = <String, List<String>>{};
    for (final item in items) {
      final reason = item.errorMessage ?? '사유 없음';
      final filename = item.asset.title ?? item.file?.path.split('/').last ?? '파일';
      reasonGroups.putIfAbsent(reason, () => []).add(filename);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '$title (${items.length}건)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 사유별 목록
          ...reasonGroups.entries.map((entry) {
            final reason = entry.key;
            final files = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 사유
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('→ ', style: TextStyle(fontSize: 12, color: color)),
                      Expanded(
                        child: Text(
                          reason,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: color.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 파일명들 (최대 3개 + "외 N개")
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      files.length <= 3
                          ? files.join(', ')
                          : '${files.take(3).join(', ')} 외 ${files.length - 3}개',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _resultChip(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 선택한 사진 바로 삭제 확인 다이얼로그
  void _confirmDeleteSelected(TransferProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('선택한 사진 삭제',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600)),
        content: Text(
          '${provider.selectedCount}개의 사진/동영상을 폰에서 삭제합니다.\n\n'
          '⚠️ 서버에 전송되지 않은 파일은 복구할 수 없습니다.',
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
                    content: Text('🗑️ $deleted개 파일 삭제 완료'),
                    backgroundColor: const Color(0xFFFF4D6D),
                  ),
                );
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 전송 완료 후 삭제 확인 다이얼로그
  void _confirmDelete(TransferProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('전송된 사진 삭제',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600)),
        content: Text(
          '${provider.successCount}장의 사진/동영상을 폰에서 삭제합니다.\n\n'
          '• 서버에 이미 전송되어 안전합니다.\n'
          '• 외장하드 연결 시 자동 이관됩니다.',
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
              final deleted = await provider.deleteTransferred();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ $deleted개 파일 삭제 완료'),
                    backgroundColor: const Color(0xFF4ECDC4),
                  ),
                );
                provider.clearQueue();
                provider.refresh();
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
