import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 핸드폰 갤러리 접근 서비스
/// - photo_manager로 사진/동영상 스캔
/// - 전송 완료 여부 추적 (SHA-256 해시)
/// - 전송 완료 후 삭제
class GalleryService {
  static final GalleryService _instance = GalleryService._();
  factory GalleryService() => _instance;
  GalleryService._();

  /// 전송 완료된 파일 해시 목록 (로컬 캐시)
  final Set<String> _transferredHashes = {};

  /// 갤러리 접근 권한 요청
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  /// 갤러리에서 사진/동영상 목록 로드
  /// [page] 0-indexed 페이지, [pageSize] 한 페이지당 개수
  Future<List<AssetEntity>> loadAssets({
    int page = 0,
    int pageSize = 80,
  }) async {
    // 최신순 정렬 옵션
    final filterOption = FilterOptionGroup(
      orders: [
        const OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );

    // 사진 + 동영상 모두 포함
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common, // image + video
      hasAll: true,
      filterOption: filterOption,
    );

    if (albums.isEmpty) return [];

    // "전체" 앨범 (모든 사진/동영상)
    final allAlbum = albums.first;
    final assets = await allAlbum.getAssetListPaged(
      page: page,
      size: pageSize,
    );

    return assets;
  }

  /// 전체 사진/동영상 수
  Future<int> getTotalCount() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
    );
    if (albums.isEmpty) return 0;
    return albums.first.assetCountAsync;
  }

  /// 에셋의 썸네일 바이트 로드
  Future<Uint8List?> getThumbnail(AssetEntity asset, {int size = 200}) async {
    return await asset.thumbnailDataWithSize(
      ThumbnailSize(size, size),
      quality: 80,
    );
  }

  /// 에셋의 원본 파일 경로 획득
  /// originFile을 우선 사용하여 EXIF(GPS 등) 메타데이터를 보존
  /// asset.file은 EXIF를 제거한 복사본을 반환할 수 있음
  Future<File?> getFile(AssetEntity asset) async {
    // 원본 파일 우선 (EXIF GPS 보존)
    final originFile = await asset.originFile;
    if (originFile != null) return originFile;
    // 원본 파일 실패 시 일반 파일로 폴백
    return await asset.file;
  }

  /// 파일의 SHA-256 해시 계산
  Future<String> computeHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 전송 완료 목록 로드 (SharedPreferences)
  Future<void> loadTransferredHashes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('transferred_hashes') ?? [];
    _transferredHashes.addAll(list);
  }

  /// 전송 완료 기록
  Future<void> markAsTransferred(String hash) async {
    _transferredHashes.add(hash);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'transferred_hashes', _transferredHashes.toList());
  }

  /// 여러 건 전송 완료 기록
  Future<void> markMultipleAsTransferred(List<String> hashes) async {
    _transferredHashes.addAll(hashes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'transferred_hashes', _transferredHashes.toList());
  }

  /// 전송 완료 여부 확인
  bool isTransferred(String hash) => _transferredHashes.contains(hash);

  /// 에셋 삭제 (폰에서 삭제)
  /// Android에서는 사용자에게 시스템 삭제 확인 팝업이 표시됨
  Future<List<String>> deleteAssets(List<AssetEntity> assets) async {
    final ids = assets.map((a) => a.id).toList();
    final result = await PhotoManager.editor.deleteWithIds(ids);
    return result;
  }

  /// 전송 완료된 에셋 수
  int get transferredCount => _transferredHashes.length;
}

/// 싱글톤
final galleryService = GalleryService();
