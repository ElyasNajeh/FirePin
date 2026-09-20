import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';

enum NotificationAccountType { user, municipality }

class NotificationDeviceTokenApi {
  NotificationDeviceTokenApi(this._apiClient);

  final ApiClient _apiClient;

  Future<void> registerToken({
    required NotificationAccountType accountType,
    required String token,
    required String platform,
  }) async {
    await _apiClient.post<Map<String, dynamic>>(
      _endpoint(accountType),
      data: {'token': token, 'platform': platform},
      requiresAuth: true,
    );
  }

  Future<void> removeToken({
    required NotificationAccountType accountType,
    required String token,
  }) async {
    try {
      await _apiClient.delete<Map<String, dynamic>>(
        _endpoint(accountType),
        data: {'token': token},
        requiresAuth: true,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) {
        rethrow;
      }
    }
  }

  String _endpoint(NotificationAccountType accountType) {
    return switch (accountType) {
      NotificationAccountType.user => '/device-tokens',
      NotificationAccountType.municipality =>
        '/municipalities/auth/device-tokens',
    };
  }
}
