import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/photo_model.dart';

/// 서버 API 통신 서비스
/// - JWT 인증 기반
/// - 사진 업로드, 동기화, 장소 검색
class ApiService {
  late Dio _dio;
  String? _token;
  String _baseUrl = 'http://192.168.0.1:8000'; // 로컬 네트워크 서버

  ApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
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

  /// 서버 연결 확인
  Future<bool> isServerReachable() async {
    try {
      final resp = await _dio.get('$_baseUrl/api/status');
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

  /// 사진 파일 업로드 (폰 → 서버)
  Future<Map<String, dynamic>?> uploadPhoto(String filePath) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      final resp = await _dio.post('$_baseUrl/api/photos/upload',
          data: formData);
      if (resp.statusCode == 200) {
        return resp.data;
      }
    } catch (e) {
      print('업로드 실패: $e');
    }
    return null;
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

  // === 썸네일 다운로드 ===

  /// 썸네일 URL 생성
  String getThumbnailUrl(String photoId) {
    return '$_baseUrl/api/thumbnails/$photoId';
  }
}

/// 싱글톤
final apiService = ApiService();
