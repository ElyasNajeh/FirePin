import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/features/notifications/notification_api.dart';
import 'package:firepin_ui/features/notifications/notification_service.dart';
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
      final api = NotificationDeviceTokenApi(
        client,
        municipalityApiClient: client,
      );

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
    final userAdapter = RecordingAdapter();
    final municipalityAdapter = RecordingAdapter();
    final storage = MemoryTokenStorage();
    final userClient = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      dio: Dio()..httpClientAdapter = userAdapter,
    );
    final municipalityClient = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      refreshPath: '/municipalities/auth/refresh',
      dio: Dio()..httpClientAdapter = municipalityAdapter,
    );
    await municipalityClient.setSession(
      accessToken: 'municipality-access',
      refreshToken: 'municipality-refresh',
    );
    final api = NotificationDeviceTokenApi(
      userClient,
      municipalityApiClient: municipalityClient,
    );

    await api.registerToken(
      accountType: NotificationAccountType.municipality,
      token: 'fcm-municipality',
      platform: 'android',
    );

    expect(userAdapter.requests, isEmpty);
    expect(
      municipalityAdapter.requests.single.path,
      '/municipalities/auth/device-tokens',
    );
    expect(
      municipalityAdapter.requests.single.headers['Authorization'],
      'Bearer municipality-access',
    );
  });

  test('repeated attachment registers an unchanged token only once', () async {
    final fixture = NotificationFixture();
    await fixture.ready;

    await fixture.service.attachAuthenticatedAccount(
      NotificationAccountType.user,
    );
    await fixture.service.attachAuthenticatedAccount(
      NotificationAccountType.user,
    );

    expect(fixture.userAdapter.methodsAndPaths, ['POST /device-tokens']);
  });

  test(
    'token refresh registers new ownership before removing the old token',
    () async {
      final fixture = NotificationFixture();
      await fixture.ready;
      await fixture.service.attachAuthenticatedAccount(
        NotificationAccountType.user,
      );
      fixture.userAdapter.failRegistrationToken = 'new-token';

      await fixture.service.handleTokenRefreshForTest('new-token');

      expect(fixture.userAdapter.methodsAndPaths, [
        'POST /device-tokens',
        'POST /device-tokens',
      ]);

      fixture.userAdapter.failRegistrationToken = null;
      await fixture.service.handleTokenRefreshForTest('new-token');

      expect(fixture.userAdapter.methodsAndPaths, [
        'POST /device-tokens',
        'POST /device-tokens',
        'POST /device-tokens',
        'DELETE /device-tokens',
      ]);
      expect(fixture.userAdapter.requests.last.data, {'token': 'old-token'});
    },
  );

  test('token refresh uses the current municipality ownership', () async {
    final fixture = NotificationFixture();
    await fixture.ready;
    await fixture.service.attachAuthenticatedAccount(
      NotificationAccountType.municipality,
    );

    await fixture.service.handleTokenRefreshForTest('new-token');

    expect(fixture.userAdapter.requests, isEmpty);
    expect(fixture.municipalityAdapter.methodsAndPaths, [
      'POST /municipalities/auth/device-tokens',
      'POST /municipalities/auth/device-tokens',
      'DELETE /municipalities/auth/device-tokens',
    ]);
  });

  test(
    'token refresh without an authenticated principal does nothing',
    () async {
      final fixture = NotificationFixture();
      await fixture.ready;

      await fixture.service.handleTokenRefreshForTest('new-token');

      expect(fixture.userAdapter.requests, isEmpty);
      expect(fixture.municipalityAdapter.requests, isEmpty);
    },
  );
}

class NotificationFixture {
  NotificationFixture() {
    userApi = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      dio: Dio()..httpClientAdapter = userAdapter,
    );
    municipalityApi = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      refreshPath: '/municipalities/auth/refresh',
      dio: Dio()..httpClientAdapter = municipalityAdapter,
    );
    ready = Future.wait([
      userApi.setSession(
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
      ),
      municipalityApi.setSession(
        accessToken: 'municipality-access',
        refreshToken: 'municipality-refresh',
      ),
    ]);
    api = NotificationDeviceTokenApi(
      userApi,
      municipalityApiClient: municipalityApi,
    );
    service = FirePinNotificationService(
      deviceTokenApi: api,
      tokenProvider: () async => 'old-token',
      platformOverride: 'android',
    );
  }

  final storage = MemoryTokenStorage();
  final userAdapter = RecordingAdapter();
  final municipalityAdapter = RecordingAdapter();
  late final ApiClient userApi;
  late final ApiClient municipalityApi;
  late final Future<void> ready;
  late final NotificationDeviceTokenApi api;
  late final FirePinNotificationService service;
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
  String? failRegistrationToken;

  Iterable<String> get methodsAndPaths =>
      requests.map((request) => '${request.method} ${request.path}');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'POST' &&
        options.data is Map &&
        (options.data as Map)['token'] == failRegistrationToken) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'temporary failure'}),
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
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
