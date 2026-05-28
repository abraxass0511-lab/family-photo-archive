import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/photo_provider.dart';
import '../models/photo_model.dart';

/// 인물 화면 (얼굴 기반 앨범)
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          appBar: AppBar(
            title: const Text('인물',
                style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFF0A0A0F),
          ),
          body: provider.persons.isEmpty
              ? _buildEmptyState()
              : _buildPersonGrid(provider),
        );
      },
    );
  }

  Widget _buildPersonGrid(PhotoProvider provider) {
    final colors = [
      const Color(0xFF7C6AEF), const Color(0xFF4ECDC4),
      const Color(0xFFF7A072), const Color(0xFFFF6B9D),
      const Color(0xFF45B7D1), const Color(0xFF96CEB4),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: provider.persons.length,
      itemBuilder: (context, index) {
        final person = provider.persons[index];
        final color = colors[index % colors.length];

        return GestureDetector(
          onTap: () => _showPersonPhotos(context, person, provider),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 아바타
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.7)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      person.name.isNotEmpty ? person.name[0] : '?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 이름
                Text(
                  person.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),

                // 사진 수
                Text(
                  '${person.photoCount}장',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPersonPhotos(
      BuildContext context, PersonModel person, PhotoProvider provider) {
    final photos = provider.photosByPerson(person.name);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        appBar: AppBar(
          title: Text('${person.name}의 사진'),
          backgroundColor: const Color(0xFF0A0A0F),
        ),
        body: photos.isEmpty
            ? Center(
                child: Text(
                  '사진이 없습니다',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: photos.length,
                itemBuilder: (_, index) {
                  final photo = photos[index];
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF2A2A3D),
                      border: photo.isBackedUp
                          ? Border.all(
                              color: const Color(0xFF4ECDC4), width: 2)
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Text(
                          photo.placeName?.substring(0, 1) ?? '📸',
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('👨‍👩‍👧‍👦',
              style: TextStyle(
                  fontSize: 48, color: Colors.white.withValues(alpha: 0.3))),
          const SizedBox(height: 16),
          Text(
            '등록된 인물이 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '서버에서 얼굴 인식을 수행하면 자동으로 추가됩니다',
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
