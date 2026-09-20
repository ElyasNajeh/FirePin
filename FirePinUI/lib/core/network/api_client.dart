import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

class AuthenticationException implements Exception {
  const AuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
    String refreshPath = '/auth/refresh',
    Dio? dio,
  }) : _tokenStorage = tokenStorage,
       _refreshPath = refreshPath,
       _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    );
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final String _refreshPath;

  String? _accessToken;
  Future<String?>? _refreshFuture;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) {
    return request<T>(
      path,
      method: 'GET',
      queryParameters: queryParameters,
      requiresAuth: requiresAuth,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) {
    return request<T>(
      path,
      method: 'POST',
      data: data,
      queryParameters: queryParameters,
      requiresAuth: requiresAuth,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) {
    return request<T>(
      path,
      method: 'PUT',
      data: data,
      queryParameters: queryParameters,
      requiresAuth: requiresAuth,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) {
    return request<T>(
      path,
      method: 'DELETE',
      data: data,
      queryParameters: queryParameters,
      requiresAuth: requiresAuth,
    );
  }

  Future<Response<T>> request<T>(
    String path, {
    required String method,
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) async {
    if (!requiresAuth) {
      return _send<T>(
        path,
        method: method,
        data: data,
        queryParameters: queryParameters,
      );
    }

    var token = _accessToken ?? await refreshAccessToken();
    if (token == null) {
      throw const AuthenticationException('Login is required');
    }

    try {
      return await _send<T>(
        path,
        method: method,
        data: data,
        queryParameters: queryParameters,
        accessToken: token,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        rethrow;
      }

      token = await refreshAccessToken();
      if (token == null) {
        throw const AuthenticationException('Session has expired');
      }

      return _send<T>(
        path,
        method: method,
        data: data,
        queryParameters: queryParameters,
        accessToken: token,
      );
    }
  }

  Future<Response<T>> _send<T>(
    String path, {
    required String method,
    Object? data,
    Map<String, dynamic>? queryParameters,
    String? accessToken,
  }) {
    return _dio.request<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        method: method,
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<void> setSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _tokenStorage.saveRefreshToken(refreshToken);
    _accessToken = accessToken;
  }

  Future<String?> refreshAccessToken() {
    final currentRefresh = _refreshFuture;
    if (currentRefresh != null) {
      return currentRefresh;
    }

    final refresh = _performRefresh();
    _refreshFuture = refresh;

    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
      }
    });
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      return null;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _refreshPath,
        data: {'refresh_token': refreshToken},
      );
      final accessToken = response.data?['access_token'];

      if (accessToken is! String || accessToken.isEmpty) {
        await clearSession();
        throw const FormatException('Refresh response has no access token');
      }

      _accessToken = accessToken;
      return accessToken;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401) {
        await clearSession();
        return null;
      }
      rethrow;
    }
  }

  Future<void> clearSession() async {
    _accessToken = null;
    await _tokenStorage.deleteRefreshToken();
  }
}
