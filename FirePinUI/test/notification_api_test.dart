import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/features/notifications/notification_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'user token registration and removal use authenticated endpoint',
    () async {
      final adapter = RecordingAdapter();
      final client = ApiClient(
        baseUrl: 'https://api.example.com',
        tokenStorage: MemoryTokenStorage(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      await client.setSession(
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
      );
      final api = NotificationDeviceTokenApi(client);

      await api.registerToken(
        accountType: NotificationAccountType.user,
        token: 'fcm-user',
        platform: 'android',
      );
      await api.removeToken(
        accountType: NotificationAccountType.user,
        token: 'fcm-user',
      );

      expect(adapter.requests.map((request) => request.path), [
        '/device-tokens',
        '/device-tokens',
      ]);
      expect(adapter.requests[0].method, 'POST');
      expect(adapter.requests[0].data, {
        'token': 'fcm-user',
        'platform': 'android',
      });
      expect(adapter.requests[1].method, 'DELETE');
      expect(adapter.requests[1].data, {'token': 'fcm-user'});
      expect(
        adapter.requests.every(
          (request) => request.headers['Authorization'] == 'Bearer user-access',
        ),
        isTrue,
      );
    },
  );

  test('municipality token uses municipality endpoint', () async {
    final adapter = RecordingAdapter();
    final client = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: MemoryTokenStorage(),
      refreshPath: '/municipalities/auth/refresh',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await client.setSession(
      accessToken: 'municipality-access',
      refreshToken: 'municipality-refresh',
    );
    final api = NotificationDeviceTokenApi(client);

    await api.registerToken(
      accountType: NotificationAccountType.municipality,
      token: 'fcm-municipality',
      platform: 'android',
    );

    expect(adapter.requests.single.path, '/municipalities/auth/device-tokens');
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer municipality-access',
    );
  });
}

class MemoryTokenStorage extends TokenStorage {
  String? refreshToken;

  @override
  Future<void> saveRefreshToken(String token) async {
    refreshToken = token;
  }

  @override
  Future<String?> readRefreshToken() async {
    return refreshToken;
  }

  @override
  Future<void> deleteRefreshToken() async {
    refreshToken = null;
  }
}

class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'id': 1, 'platform': 'android'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
