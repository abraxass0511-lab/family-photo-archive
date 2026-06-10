import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/photo_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/api_service.dart';

/// 설정 화면 (서버 연결, 로그인, 동기화, 앱 정보)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggingIn = false;
  bool _obscurePassword = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = apiService.baseUrl;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = 'v${info.buildNumber}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PhotoProvider, SyncProvider>(
      builder: (context, photoProvider, syncProvider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F8),
          appBar: AppBar(
            title: const Text('설정',
                style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFFF5F5F8),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // === 서버 연결 ===
              _sectionTitle('서버 연결'),
              _buildCard(children: [
                _buildStatusRow(
                  '서버 상태',
                  syncProvider.isServerOnline ? '✅ 연결됨' : '❌ 오프라인',
                  syncProvider.isServerOnline ? Colors.green : Colors.red,
                ),
                const Divider(color: Color(0xFFE8E8F0), height: 1),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _serverUrlController,
                    style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: '서버 주소',
                      labelStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.4)),
                      hintText: 'http://192.168.0.X:8000',
                      hintStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.2)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                      prefixIcon: const Icon(Icons.dns, size: 18),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: FilledButton.icon(
                    onPressed: () async {
                      await apiService
                          .setServerUrl(_serverUrlController.text);
                      await syncProvider.checkServerStatus();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              syncProvider.isServerOnline
                                  ? '✅ 서버 연결 성공!'
                                  : '❌ 서버에 연결할 수 없습니다',
                            ),
                            backgroundColor: syncProvider.isServerOnline
                                ? const Color(0xFF4ECDC4)
                                : const Color(0xFFFF4D6D),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.wifi_find, size: 18),
                    label: const Text('연결 테스트'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C6AEF),
                    ),
                  ),
                ),
              ]),


              const SizedBox(height: 20),


              // === 앱 정보 ===
              _sectionTitle('앱 정보'),
              _buildCard(children: [
                _buildStatusRow('앱 이름', '포토 백업', Colors.black87),
                const Divider(color: Color(0xFFE8E8F0), height: 1),
                _buildStatusRow('버전', _appVersion.isEmpty ? '...' : _appVersion, Colors.black54),
                const Divider(color: Color(0xFFE8E8F0), height: 1),
                _buildStatusRow(
                    '아키텍처', 'Self-Hosted (100% 무료)', Colors.black54),
                const Divider(color: Color(0xFFE8E8F0), height: 1),
                _buildStatusRow(
                    '보안', 'JWT + bcrypt (로컬 네트워크)', Colors.black54),
              ]),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  /// 로그인 실행
  Future<void> _login(
      SyncProvider syncProvider, PhotoProvider photoProvider) async {
    if (_usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('아이디와 비밀번호를 입력해주세요'),
          backgroundColor: Color(0xFFFF4D6D),
        ),
      );
      return;
    }

    setState(() => _isLoggingIn = true);

    final success = await apiService.login(
      _usernameController.text,
      _passwordController.text,
    );

    setState(() => _isLoggingIn = false);

    if (mounted) {
      if (success) {
        _passwordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 로그인 성공!'),
            backgroundColor: Color(0xFF4ECDC4),
          ),
        );
        // 로그인 성공 → 자동 동기화
        await syncProvider.sync(photoProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 로그인 실패. 아이디/비밀번호를 확인하세요.'),
            backgroundColor: Color(0xFFFF4D6D),
          ),
        );
      }
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black.withValues(alpha: 0.4),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.6),
                  fontSize: 14)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: valueColor, fontSize: 14),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 비밀번호 변경 다이얼로그
  void _showPasswordChangeDialog() {
    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('비밀번호 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPwController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '현재 비밀번호',
                prefixIcon: Icon(Icons.lock_outline, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newPwController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '새 비밀번호 (8자 이상, 영문+숫자)',
                prefixIcon: Icon(Icons.key, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmPwController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '새 비밀번호 확인',
                prefixIcon: Icon(Icons.key, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              if (newPwController.text != confirmPwController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ 새 비밀번호가 일치하지 않습니다'),
                    backgroundColor: Color(0xFFFF4D6D),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              final success = await apiService.changePassword(
                currentPwController.text,
                newPwController.text,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? '✅ 비밀번호가 변경되었습니다'
                        : '❌ 비밀번호 변경 실패'),
                    backgroundColor:
                        success ? const Color(0xFF4ECDC4) : const Color(0xFFFF4D6D),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C6AEF),
            ),
            child: const Text('변경', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
