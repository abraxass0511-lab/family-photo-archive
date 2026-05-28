import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import '../providers/sync_provider.dart';
import '../services/api_service.dart';

/// 설정 화면 (서버 연결, 동기화, 앱 정보)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = 'http://192.168.0.1:8000';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PhotoProvider, SyncProvider>(
      builder: (context, photoProvider, syncProvider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          appBar: AppBar(
            title: const Text('설정',
                style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFF0A0A0F),
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
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _serverUrlController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: '서버 주소',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      hintText: 'http://192.168.0.1:8000',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: FilledButton(
                    onPressed: () async {
                      await apiService.setServerUrl(_serverUrlController.text);
                      await syncProvider.checkServerStatus();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              syncProvider.isServerOnline
                                  ? '✅ 서버 연결 성공!'
                                  : '❌ 서버에 연결할 수 없습니다',
                            ),
                          ),
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C6AEF),
                    ),
                    child: const Text('연결 테스트'),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              // === 동기화 ===
              _sectionTitle('동기화'),
              _buildCard(children: [
                _buildStatusRow(
                  '상태',
                  syncProvider.syncStatus,
                  Colors.white54,
                ),
                if (syncProvider.lastSyncTime != null) ...[
                  const Divider(color: Color(0xFF2A2A3D), height: 1),
                  _buildStatusRow(
                    '마지막 동기화',
                    syncProvider.lastSyncTime!,
                    Colors.white38,
                  ),
                ],
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: FilledButton.icon(
                    onPressed: syncProvider.isSyncing
                        ? null
                        : () => syncProvider.sync(photoProvider),
                    icon: syncProvider.isSyncing
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(syncProvider.isSyncing ? '동기화 중...' : '지금 동기화'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4ECDC4),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              // === 저장 현황 ===
              _sectionTitle('저장 현황'),
              _buildCard(children: [
                _buildStatusRow('총 사진', '${photoProvider.photos.length}장', Colors.white70),
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                _buildStatusRow('백업 완료', '${photoProvider.backedUpPhotos.length}장',
                    const Color(0xFF4ECDC4)),
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                _buildStatusRow('즐겨찾기', '${photoProvider.favoritePhotos.length}장',
                    const Color(0xFFFF4D6D)),
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                _buildStatusRow('등록 인물', '${photoProvider.persons.length}명',
                    const Color(0xFF7C6AEF)),
              ]),

              const SizedBox(height: 20),

              // === 앱 정보 ===
              _sectionTitle('앱 정보'),
              _buildCard(children: [
                _buildStatusRow('버전', '1.0.0', Colors.white38),
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                _buildStatusRow('아키텍처', '클라우드 제로 (Self-Hosted)', Colors.white38),
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                _buildStatusRow('지도', 'OpenStreetMap (무료)', Colors.white38),
                const Divider(color: Color(0xFF2A2A3D), height: 1),
                _buildStatusRow('장소 검색', '카카오 로컬 + Nominatim (무료)', Colors.white38),
              ]),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.4),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
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
}
