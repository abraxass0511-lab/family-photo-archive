import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/photo_model.dart';
import '../services/api_service.dart';

/// 자동재생 모드 열거형
enum AutoPlayMode {
  /// 같은 영상 반복 재생
  loopSingle,

  /// 다음 영상으로 자동 이동
  playNext,
}

/// 동영상 자동재생 화면
/// - 백업 갤러리에서 동영상만 필터하여 자동재생
/// - 같은 영상 반복 / 다음 영상 이동 모드 선택
/// - 터치 잠금(Lock) 기능
class VideoAutoPlayScreen extends StatefulWidget {
  final List<PhotoModel> videos;
  final int initialIndex;

  const VideoAutoPlayScreen({
    super.key,
    required this.videos,
    this.initialIndex = 0,
  });

  @override
  State<VideoAutoPlayScreen> createState() => _VideoAutoPlayScreenState();
}

class _VideoAutoPlayScreenState extends State<VideoAutoPlayScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isError = false;
  String _errorMsg = '';

  int _currentIndex = 0;
  AutoPlayMode _autoPlayMode = AutoPlayMode.playNext;

  /// 터치 잠금 상태
  bool _isLocked = false;

  /// 컨트롤 UI 표시 여부
  bool _showControls = true;

  /// 잠금 해제 확인 중
  bool _showUnlockConfirm = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _fadeController.value = 1.0; // 시작시 컨트롤 표시

    // 전체화면 모드
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initVideo();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoEvent);
    _videoController?.dispose();
    _fadeController.dispose();
    // 시스템 UI 복원
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 현재 인덱스의 동영상 초기화
  Future<void> _initVideo() async {
    // 이전 컨트롤러 정리
    _videoController?.removeListener(_onVideoEvent);
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _isInitialized = false;
      _isError = false;
      _errorMsg = '';
    });

    final photo = widget.videos[_currentIndex];

    // 1) 로컬 미리보기(360p)가 있으면 로컬 우선
    if (photo.localPreviewPath != null) {
      final file = File(photo.localPreviewPath!);
      if (file.existsSync()) {
        try {
          _videoController = VideoPlayerController.file(file);
          _videoController!.addListener(_onVideoEvent);
          await _videoController!.initialize();
          if (mounted) {
            setState(() => _isInitialized = true);
            _videoController!.play(); // 자동재생
            // 루프 모드일 때 루프 설정
            if (_autoPlayMode == AutoPlayMode.loopSingle) {
              _videoController!.setLooping(true);
            }
          }
          return;
        } catch (_) {
          _videoController?.dispose();
          _videoController = null;
        }
      }
    }

    // 2) 로컬 없으면 서버 원본 시도
    final url = apiService.getOriginalFileUrl(photo.id);
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController!.addListener(_onVideoEvent);
      await _videoController!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _videoController!.play(); // 자동재생
        if (_autoPlayMode == AutoPlayMode.loopSingle) {
          _videoController!.setLooping(true);
        }
      }
      return;
    } catch (_) {
      _videoController?.dispose();
      _videoController = null;
    }

    // 3) 전부 실패
    if (mounted) {
      setState(() {
        _isError = true;
        _errorMsg = '동영상을 로드할 수 없습니다.\n서버 연결 또는 외장하드를 확인해주세요.';
      });
      // 에러 시 다음 영상으로 (playNext 모드일 때)
      if (_autoPlayMode == AutoPlayMode.playNext) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _playNext();
        });
      }
    }
  }

  void _onVideoEvent() {
    if (!mounted || _videoController == null) return;

    final value = _videoController!.value;

    // 영상 끝났을 때 → playNext 모드라면 다음으로
    if (value.position >= value.duration &&
        value.duration > Duration.zero &&
        !value.isPlaying &&
        _autoPlayMode == AutoPlayMode.playNext) {
      _playNext();
    }

    if (mounted) setState(() {});
  }

  void _playNext() {
    if (_currentIndex < widget.videos.length - 1) {
      _currentIndex++;
      _initVideo();
    } else {
      // 마지막 영상 → 처음으로 돌아가기
      _currentIndex = 0;
      _initVideo();
    }
  }

  void _playPrevious() {
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = widget.videos.length - 1;
    }
    _initVideo();
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isInitialized) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  void _toggleControls() {
    if (_isLocked) {
      // 잠금 상태에서는 unlock 확인만 표시
      setState(() => _showUnlockConfirm = !_showUnlockConfirm);
      if (_showUnlockConfirm) {
        // 3초 후 자동 숨김
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _showUnlockConfirm) {
            setState(() => _showUnlockConfirm = false);
          }
        });
      }
      return;
    }

    if (_showControls) {
      _fadeController.reverse();
    } else {
      _fadeController.forward();
    }
    setState(() => _showControls = !_showControls);

    // 컨트롤 표시 5초 후 자동 숨김
    if (_showControls) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _showControls && !_isLocked) {
          _fadeController.reverse();
          setState(() => _showControls = false);
        }
      });
    }
  }

  /// 잠금 토글
  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showUnlockConfirm = false;
      if (_isLocked) {
        // 잠금 시 컨트롤 숨김
        _showControls = false;
        _fadeController.reverse();
      } else {
        // 잠금 해제 시 컨트롤 표시
        _showControls = true;
        _fadeController.forward();
      }
    });
  }

  /// 모드 변경
  void _cycleAutoPlayMode() {
    setState(() {
      if (_autoPlayMode == AutoPlayMode.loopSingle) {
        _autoPlayMode = AutoPlayMode.playNext;
        _videoController?.setLooping(false);
      } else {
        _autoPlayMode = AutoPlayMode.loopSingle;
        _videoController?.setLooping(true);
      }
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // === 동영상 영역 ===
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              child: _buildVideoArea(),
            ),
          ),

          // === 잠금 오버레이 (터치 차단) ===
          if (_isLocked) _buildLockOverlay(),

          // === 컨트롤 UI (잠금 해제 상태에서만) ===
          if (!_isLocked)
            FadeTransition(
              opacity: _fadeAnimation,
              child: _showControls ? _buildControlsOverlay() : const SizedBox(),
            ),

          // === 잠금 상태 안내 + 해제 버튼 ===
          if (_isLocked) _buildLockIndicator(),
        ],
      ),
    );
  }

  /// 동영상 재생 영역
  Widget _buildVideoArea() {
    if (_isError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMsg,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF7C6AEF),
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.videos[_currentIndex].filename}\n로딩 중...',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }

  /// 잠금 오버레이 — 모든 터치를 흡수
  Widget _buildLockOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );
  }

  /// 잠금 상태 표시 + 해제 버튼
  Widget _buildLockIndicator() {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showUnlockConfirm ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: Center(
          child: GestureDetector(
            onTap: _toggleControls,
            onLongPress: _toggleLock, // 꾹 눌러서 잠금 해제
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.symmetric(
                horizontal: _showUnlockConfirm ? 28 : 16,
                vertical: _showUnlockConfirm ? 14 : 10,
              ),
              decoration: BoxDecoration(
                color: _showUnlockConfirm
                    ? const Color(0xFF7C6AEF).withValues(alpha: 0.85)
                    : Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: _showUnlockConfirm ? 20 : 16,
                  ),
                  if (_showUnlockConfirm) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '꾹 눌러서 잠금 해제',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 컨트롤 오버레이 (잠금 해제 상태)
  Widget _buildControlsOverlay() {
    return Stack(
      children: [
        // 상단 그라데이션 + 상태바
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
                child: Row(
                  children: [
                    // 뒤로가기
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 24),
                    ),
                    // 파일명
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.videos[_currentIndex].filename,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_currentIndex + 1} / ${widget.videos.length}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 자동재생 모드 토글
                    _buildModeButton(),
                    const SizedBox(width: 4),
                    // 잠금 버튼
                    _buildLockButton(),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 하단 그라데이션 + 컨트롤
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 프로그레스 바
                    if (_isInitialized) ...[
                      Row(
                        children: [
                          Text(
                            _formatDuration(
                                _videoController!.value.position),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                                activeTrackColor: const Color(0xFF7C6AEF),
                                inactiveTrackColor:
                                    Colors.white.withValues(alpha: 0.2),
                                thumbColor: const Color(0xFF7C6AEF),
                                overlayColor:
                                    const Color(0xFF7C6AEF).withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: _videoController!
                                        .value.position.inMilliseconds
                                        .toDouble()
                                        .clamp(
                                            0,
                                            _videoController!
                                                .value.duration.inMilliseconds
                                                .toDouble()),
                                max: _videoController!
                                    .value.duration.inMilliseconds
                                    .toDouble(),
                                onChanged: (v) {
                                  _videoController!.seekTo(
                                      Duration(milliseconds: v.toInt()));
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(
                                _videoController!.value.duration),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 재생 컨트롤
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 이전 영상
                        IconButton(
                          onPressed: _playPrevious,
                          icon: const Icon(Icons.skip_previous,
                              color: Colors.white70, size: 32),
                        ),
                        const SizedBox(width: 8),
                        // 10초 뒤로
                        IconButton(
                          onPressed: () {
                            if (_videoController == null) return;
                            final pos = _videoController!.value.position;
                            _videoController!.seekTo(
                                pos - const Duration(seconds: 10));
                          },
                          icon: const Icon(Icons.replay_10,
                              color: Colors.white70, size: 28),
                        ),
                        const SizedBox(width: 12),
                        // 재생/일시정지
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                const Color(0xFF7C6AEF).withValues(alpha: 0.9),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C6AEF)
                                    .withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _togglePlayPause,
                            icon: Icon(
                              (_isInitialized &&
                                      _videoController!.value.isPlaying)
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 10초 앞으로
                        IconButton(
                          onPressed: () {
                            if (_videoController == null) return;
                            final pos = _videoController!.value.position;
                            _videoController!.seekTo(
                                pos + const Duration(seconds: 10));
                          },
                          icon: const Icon(Icons.forward_10,
                              color: Colors.white70, size: 28),
                        ),
                        const SizedBox(width: 8),
                        // 다음 영상
                        IconButton(
                          onPressed: _playNext,
                          icon: const Icon(Icons.skip_next,
                              color: Colors.white70, size: 32),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 중앙 — 큰 재생 버튼 (일시정지 상태에서)
        if (_isInitialized && !_videoController!.value.isPlaying)
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 자동재생 모드 버튼
  Widget _buildModeButton() {
    final isLoop = _autoPlayMode == AutoPlayMode.loopSingle;
    return GestureDetector(
      onTap: _cycleAutoPlayMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isLoop
              ? const Color(0xFF4ECDC4).withValues(alpha: 0.25)
              : const Color(0xFF7C6AEF).withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLoop
                ? const Color(0xFF4ECDC4).withValues(alpha: 0.4)
                : const Color(0xFF7C6AEF).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLoop ? Icons.repeat_one : Icons.playlist_play,
              color: isLoop
                  ? const Color(0xFF4ECDC4)
                  : const Color(0xFF7C6AEF),
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              isLoop ? '반복' : '연속',
              style: TextStyle(
                color: isLoop
                    ? const Color(0xFF4ECDC4)
                    : const Color(0xFF7C6AEF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 잠금 버튼
  Widget _buildLockButton() {
    return GestureDetector(
      onTap: _toggleLock,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(
          _isLocked ? Icons.lock : Icons.lock_open,
          color: Colors.white.withValues(alpha: 0.8),
          size: 20,
        ),
      ),
    );
  }
}
