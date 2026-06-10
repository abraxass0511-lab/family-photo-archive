import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/api_service.dart';
import 'transfer_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';

/// 메인 홈 화면 (하단 3탭 네비게이션)
/// 전송 / 백업 갤러리 / 설정
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    TransferScreen(),
    GalleryScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // 저장된 서버 URL과 토큰 로드
    await apiService.loadServerUrl();
    await apiService.loadToken();

    if (!mounted) return;

    // TransferProvider 초기화 (전송 표시 복원)
    final transferProvider = context.read<TransferProvider>();
    await transferProvider.initialize();

    // 로컬 DB에서 기존 데이터 먼저 로드
    final photoProvider = context.read<PhotoProvider>();
    await photoProvider.loadFromLocal();

    // 서버 연결 시도
    final syncProvider = context.read<SyncProvider>();
    await syncProvider.checkServerStatus();

    if (syncProvider.isServerOnline) {
      await syncProvider.sync(photoProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.photo_library_outlined, Icons.photo_library, '갤러리'),
              _navItem(1, Icons.cloud_done_outlined, Icons.cloud_done, '백업'),
              _navItem(2, Icons.settings_outlined, Icons.settings, '설정'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF7C6AEF).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive
                  ? const Color(0xFF7C6AEF)
                  : const Color(0xFF9E9EB8),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? const Color(0xFF7C6AEF)
                    : const Color(0xFF5C5A6E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
