import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_model.dart';

/// 서버 API 통신 서비스
/// - JWT 인증 기반
/// - 사진 업로드 (진행률 콜백 지원)
/// - 동기화, 장소 검색, 즐겨찾기
class ApiService {
  late Dio _dio;
  String? _token;
  String _baseUrl = 'http://192.168.45.164:8000'; // 로컬 네트워크 서버

  ApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 300), // 대용량 동영상 다운로드 대비
      sendTimeout: const Duration(seconds: 300), // 대용량 동영상 업로드 대비
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          _token = null;
          // 토큰 만료 → 재로그인 필요
        }
        return handler.next(error);
      },
    ));
  }

  /// 서버 주소 설정 (설정 화면에서)
  Future<void> setServerUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    _dio.options.baseUrl = _baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _baseUrl);
  }

  /// 저장된 서버 주소 불러오기
  Future<void> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('server_url') ?? _baseUrl;
    _dio.options.baseUrl = _baseUrl;
  }

  /// 현재 서버 주소
  String get baseUrl => _baseUrl;

  /// 서버 연결 확인
  Future<bool> isServerReachable() async {
    try {
      final resp = await _dio.get('$_baseUrl/health');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // === 인증 ===

  /// 로그인
  Future<bool> login(String username, String password) async {
    try {
      final resp = await _dio.post('$_baseUrl/api/auth/login', data: {
        'username': username,
        'password': password,
      });
      if (resp.statusCode == 200) {
        _token = resp.data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        return true;
      }
    } catch (e) {
      print('로그인 실패: $e');
    }
    return false;
  }

  /// 로그아웃
  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  /// 저장된 토큰 불러오기
  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
  }

  bool get isAuthenticated => _token != null;

  // === 동기화 ===

  /// 서버와 데이터 동기화
  Future<Map<String, dynamic>?> syncData({String? lastSyncAt}) async {
    try {
      String url = '$_baseUrl/api/sync';
      if (lastSyncAt != null) {
        url += '?last_sync_at=$lastSyncAt';
      }
      final resp = await _dio.get(url);
      if (resp.statusCode == 200) {
        return resp.data;
      }
    } catch (e) {
      print('동기화 실패: $e');
    }
    return null;
  }

  // === 사진 업로드 ===

  /// 사진 파일 업로드 (진행률 콜백 지원)
  /// latitude/longitude: 앱에서 가져온 위치 데이터 (EXIF에 없을 경우 서버가 사용)
  Future<Map<String, dynamic>?> uploadPhotoWithProgress(
    String filePath, {
    void Function(int sent, int total)? onProgress,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final map = <String, dynamic>{
        'file': await MultipartFile.fromFile(filePath),
      };
      if (latitude != null && longitude != null) {
        map['latitude'] = latitude.toString();
        map['longitude'] = longitude.toString();
      }
      final formData = FormData.fromMap(map);
      final resp = await _dio.post(
        '$_baseUrl/api/photos/upload',
        data: formData,
        onSendProgress: onProgress,
      );
      if (resp.statusCode == 200) {
        return resp.data;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // 이미 전송된 파일 → 에러를 throw해서 duplicate 처리
        throw Exception('409: 이미 전송된 파일입니다');
      }
      print('업로드 실패: $e');
      rethrow;
    }
    return null;
  }

  /// 사진 파일 업로드 (기본)
  Future<Map<String, dynamic>?> uploadPhoto(String filePath, {double? latitude, double? longitude}) async {
    return uploadPhotoWithProgress(filePath, latitude: latitude, longitude: longitude);
  }

  // === 장소 검색 ===

  /// 장소 검색 (카카오 + Nominatim 융합)
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      final resp = await _dio.get('$_baseUrl/api/places/search',
          queryParameters: {'q': query, 'limit': 10});
      if (resp.statusCode == 200) {
        return List<Map<String, dynamic>>.from(resp.data);
      }
    } catch (e) {
      print('장소 검색 실패: $e');
    }
    return [];
  }

  // === 즐겨찾기 ===

  /// 즐겨찾기 변경 동기화 (역동기화)
  Future<bool> syncFavorites(List<Map<String, dynamic>> changes) async {
    try {
      final resp = await _dio.post('$_baseUrl/api/photos/favorites',
          data: {'changes': changes});
      return resp.statusCode == 200;
    } catch (e) {
      print('즐겨찾기 동기화 실패: $e');
      return false;
    }
  }

  // === 사진 삭제 (폰에서) ===

  /// 삭제 요청 전송 (서버에 기록)
  Future<bool> notifyDeletion(List<String> photoIds) async {
    try {
      final resp = await _dio.post('$_baseUrl/api/photos/phone-deleted',
          data: {'photo_ids': photoIds});
      return resp.statusCode == 200;
    } catch (e) {
      print('삭제 알림 실패: $e');
      return false;
    }
  }

  /// 서버에서 사진 완전 삭제 (DB + 파일)
  Future<int> deletePhotos(List<String> photoIds) async {
    try {
      final resp = await _dio.delete('$_baseUrl/api/photos/delete',
          data: {'photo_ids': photoIds});
      if (resp.statusCode == 200) {
        return resp.data['deleted'] ?? 0;
      }
    } catch (e) {
      print('사진 삭제 실패: $e');
    }
    return 0;
  }

  // === 서버 상태 ===

  /// 서버 상세 상태 조회
  Future<Map<String, dynamic>?> getServerStatus() async {
    try {
      final resp = await _dio.get('$_baseUrl/api/status');
      if (resp.statusCode == 200) {
        return resp.data;
      }
    } catch (e) {
      print('상태 조회 실패: $e');
    }
    return null;
  }

  // === 썸네일 다운로드 ===

  /// 썸네일 URL 생성
  String getThumbnailUrl(String photoId) {
    return '$_baseUrl/api/photos/thumbnail/$photoId';
  }

  /// 원본 파일 URL (사진/동영상)
  String getOriginalFileUrl(String photoId) {
    return '$_baseUrl/api/photos/file/$photoId';
  }

  /// 동영상 미리보기(360p) URL
  String getPreviewUrl(String photoId) {
    return '$_baseUrl/api/photos/preview/$photoId';
  }

  /// 썸네일 바이트 다운로드 (로컬 저장용)
  Future<List<int>?> downloadThumbnailBytes(String photoId) async {
    try {
      final resp = await _dio.get(
        '$_baseUrl/api/photos/thumbnail/$photoId',
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.statusCode == 200) {
        return resp.data as List<int>;
      }
    } catch (_) {}
    return null;
  }

  /// 미리보기 바이트 다운로드 (로컬 저장용)
  Future<List<int>?> downloadPreviewBytes(String photoId) async {
    try {
      final resp = await _dio.get(
        '$_baseUrl/api/photos/preview/$photoId',
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.statusCode == 200) {
        return resp.data as List<int>;
      }
    } catch (_) {}
    return null;
  }

  // === 비밀번호 변경 ===

  /// 비밀번호 변경
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      final resp = await _dio.put(
        '$_baseUrl/api/auth/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      return resp.statusCode == 200;
    } catch (e) {
      print('비밀번호 변경 실패: $e');
      return false;
    }
  }
}

/// 싱글톤
final apiService = ApiService();
