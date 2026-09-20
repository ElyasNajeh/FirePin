import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firepin_ui/app/app_services.dart';
import 'package:firepin_ui/app/firepin_app.dart';
import 'package:firepin_ui/core/config/api_config.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/features/auth/auth_controller.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API base URL supports Android and an explicit production URL', () {
    expect(
      resolveApiBaseUrl(platform: TargetPlatform.android),
      'http://10.0.2.2:8000',
    );
    expect(
      resolveApiBaseUrl(override: 'https://api.firepin.example'),
      'https://api.firepin.example',
    );
  });

  test(
    'real user login uses national ID, profile, and bearer access',
    () async {
      final fixture = AuthApiFixture();
      final repository = fixture.userRepository;

      final result = await repository.loginUser(
        nationalId: '123456789',
        pin: '1234',
      );

      expect(result.account.nationalId, '123456789');
      expect(result.account.address, 'غير متاح');
      expect(fixture.storage.refreshToken, 'user-refresh');
      expect(fixture.adapter.requests.first.data, {
        'national_id': '123456789',
        'pin': '1234',
      });
      expect(
        fixture.adapter.request('/auth/me').headers['Authorization'],
        'Bearer user-access',
      );
    },
  );

  test('real municipality login uses municipality profile endpoint', () async {
    final fixture = AuthApiFixture();

    final result = await fixture.municipalityRepository.login(
      email: 'MUNICIPALITY@FIREPIN.PS',
      password: 'password',
    );

    expect(result.account.name, 'بلدية القدس');
    expect(result.account.serviceArea, 'غير متاح');
    expect(fixture.storage.refreshToken, 'municipality-refresh');
    expect(
      fixture.adapter
          .request('/municipalities/auth/me')
          .headers['Authorization'],
      'Bearer municipality-access',
    );
  });

  test('registration is followed by national-ID login', () async {
    final fixture = AuthApiFixture();
    final session = OnboardingSession()
      ..identity = const IdentityData(
        fullName: 'مستخدم جديد',
        identityNumber: '123456789',
        birthDate: '14 / 05 / 1998',
        gender: '',
        address: 'عنوان محلي',
      )
      ..phone = '059 123 4567';
    expect(session.savePin('1234', '1234'), isTrue);

    await fixture.userRepository.registerUser(session);

    expect(fixture.adapter.paths.take(2), ['/users/register', '/auth/login']);
    expect(fixture.adapter.request('/users/register').data, {
      'full_name': 'مستخدم جديد',
      'phone': '0591234567',
      'national_id': '123456789',
      'birth_date': '1998-05-14',
      'pin': '1234',
    });
  });

  test('access expiry refreshes once and retries once', () async {
    final fixture = AuthApiFixture()..protectedRejectsOldAccess = true;
    await fixture.userApi.setSession(
      accessToken: 'old-access',
      refreshToken: 'user-refresh',
    );

    final response = await fixture.userApi.get<Map<String, dynamic>>(
      '/protected',
      requiresAuth: true,
    );

    expect(response.statusCode, 200);
    expect(fixture.adapter.count('/auth/refresh'), 1);
    expect(fixture.adapter.count('/protected'), 2);
  });

  test('a failed retry does not create a refresh loop', () async {
    final fixture = AuthApiFixture()..protectedAlwaysUnauthorized = true;
    await fixture.userApi.setSession(
      accessToken: 'old-access',
      refreshToken: 'user-refresh',
    );

    await expectLater(
      fixture.userApi.get<Map<String, dynamic>>(
        '/protected',
        requiresAuth: true,
      ),
      throwsA(isA<DioException>()),
    );
    expect(fixture.adapter.count('/auth/refresh'), 1);
    expect(fixture.adapter.count('/protected'), 2);
  });

  test('a request that starts with refresh never refreshes twice', () async {
    final fixture = AuthApiFixture()..protectedAlwaysUnauthorized = true;
    fixture.storage.refreshToken = 'user-refresh';

    await expectLater(
      fixture.userApi.get<Map<String, dynamic>>(
        '/protected',
        requiresAuth: true,
      ),
      throwsA(isA<AuthenticationException>()),
    );

    expect(fixture.adapter.count('/auth/refresh'), 1);
    expect(fixture.adapter.count('/protected'), 1);
    expect(fixture.storage.refreshToken, isNull);
  });

  test('user and municipality clients use their own refresh paths', () async {
    final userFixture = AuthApiFixture();
    userFixture.storage.refreshToken = 'user-refresh';
    await userFixture.userApi.refreshAccessToken();
    expect(userFixture.adapter.count('/auth/refresh'), 1);

    final municipalityFixture = AuthApiFixture();
    municipalityFixture.storage.refreshToken = 'municipality-refresh';
    await municipalityFixture.municipalityApi.refreshAccessToken();
    expect(
      municipalityFixture.adapter.count('/municipalities/auth/refresh'),
      1,
    );
  });

  test(
    'refresh token is secure-only metadata and access is memory-only',
    () async {
      final fixture = AuthApiFixture();
      final sessions = SecureSessionRepository(storage: fixture.storage);
      await fixture.userApi.setSession(
        accessToken: 'memory-access',
        refreshToken: 'user-refresh',
      );
      await sessions.save(const StoredSession(principal: AuthPrincipal.user));

      expect(fixture.storage.refreshToken, 'user-refresh');
      expect(fixture.storage.session, '{"principal":"user"}');
      expect(fixture.storage.session, isNot(contains('refresh')));
      expect(fixture.storage.session, isNot(contains('memory-access')));

      final restartedClient = ApiClient(
        baseUrl: 'https://api.example.com',
        tokenStorage: fixture.storage,
        dio: Dio()..httpClientAdapter = fixture.adapter,
      );
      await restartedClient.get<Map<String, dynamic>>(
        '/protected',
        requiresAuth: true,
      );
      expect(fixture.adapter.count('/auth/refresh'), 1);
    },
  );

  test('restoration clears an orphaned refresh token', () async {
    final fixture = AuthApiFixture();
    fixture.storage.refreshToken = 'orphan-refresh-token';
    final controller = AuthController(
      users: fixture.userRepository,
      municipalities: fixture.municipalityRepository,
      sessions: MemorySessionRepository(),
    );

    await controller.restore();

    expect(controller.status, AuthStatus.signedOut);
    expect(fixture.storage.refreshToken, isNull);
    controller.dispose();
  });

  test('cold start restores user and municipality principals', () async {
    final userFixture = AuthApiFixture();
    userFixture.storage.refreshToken = 'user-refresh';
    final userSessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.user);
    final userController = AuthController(
      users: userFixture.userRepository,
      municipalities: userFixture.municipalityRepository,
      sessions: userSessions,
    );
    await userController.restore();
    expect(userController.status, AuthStatus.user);
    expect(userController.user?.nationalId, '123456789');
    userController.dispose();

    final municipalityFixture = AuthApiFixture();
    municipalityFixture.storage.refreshToken = 'municipality-refresh';
    final municipalitySessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.municipality);
    final municipalityController = AuthController(
      users: municipalityFixture.userRepository,
      municipalities: municipalityFixture.municipalityRepository,
      sessions: municipalitySessions,
    );
    await municipalityController.restore();
    expect(municipalityController.status, AuthStatus.municipality);
    expect(
      municipalityController.municipality?.email,
      'municipality@firepin.ps',
    );
    municipalityController.dispose();
  });

  test('terminal refresh clears secure and principal sessions', () async {
    final fixture = AuthApiFixture()..terminalUserRefresh = true;
    fixture.storage.refreshToken = 'revoked-refresh';
    final sessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.user);
    final controller = AuthController(
      users: fixture.userRepository,
      municipalities: fixture.municipalityRepository,
      sessions: sessions,
    );

    await controller.restore();

    expect(controller.status, AuthStatus.signedOut);
    expect(sessions.value, isNull);
    expect(fixture.storage.refreshToken, isNull);
    controller.dispose();
  });

  test('account switching clears previous in-memory authentication', () async {
    final fixture = AuthApiFixture();
    final sessions = MemorySessionRepository();
    final controller = AuthController(
      users: fixture.userRepository,
      municipalities: fixture.municipalityRepository,
      sessions: sessions,
    );
    await controller.loginUser('123456789', '1234');
    await controller.loginMunicipality('municipality@firepin.ps', 'password');

    expect(controller.status, AuthStatus.municipality);
    expect(controller.user, isNull);
    expect(fixture.storage.refreshToken, 'municipality-refresh');
    fixture.terminalUserRefresh = true;
    await expectLater(
      fixture.userApi.get<Map<String, dynamic>>(
        '/protected',
        requiresAuth: true,
      ),
      throwsA(isA<AuthenticationException>()),
    );
    expect(fixture.adapter.count('/protected'), 0);
    expect(fixture.adapter.count('/auth/refresh'), 1);
    controller.dispose();
  });

  test(
    'logout revokes refresh token and clears all local session state',
    () async {
      final fixture = AuthApiFixture();
      final sessions = MemorySessionRepository();
      final controller = AuthController(
        users: fixture.userRepository,
        municipalities: fixture.municipalityRepository,
        sessions: sessions,
      );
      await controller.loginUser('123456789', '1234');

      await controller.logout();

      expect(controller.status, AuthStatus.signedOut);
      expect(sessions.value, isNull);
      expect(fixture.storage.refreshToken, isNull);
      expect(fixture.adapter.request('/auth/logout').data, {
        'refresh_token': 'user-refresh',
      });
      controller.dispose();
    },
  );

  testWidgets('API-backed cold restoration opens authenticated user shell', (
    tester,
  ) async {
    final fixture = AuthApiFixture();
    fixture.storage.refreshToken = 'user-refresh';
    final sessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.user);
    final incidents = IncidentController();
    final operations = LocalMunicipalityRepository(incidents: incidents);
    final services = AppServices(
      auth: fixture.userRepository,
      municipalityAuth: fixture.municipalityRepository,
      sessions: sessions,
      incidents: incidents,
      operations: operations,
    );

    await tester.pumpWidget(FirePinApp(services: services));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HomeScreen), findsOneWidget);
    services.authController.dispose();
    operations.dispose();
    incidents.dispose();
  });
}

class AuthApiFixture {
  AuthApiFixture() {
    final dio = Dio()..httpClientAdapter = adapter;
    userApi = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      dio: dio,
    );
    municipalityApi = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      refreshPath: '/municipalities/auth/refresh',
      dio: dio,
    );
    userRepository = ApiAuthRepository(api: userApi, storage: storage);
    municipalityRepository = ApiMunicipalityAuthRepository(
      api: municipalityApi,
      storage: storage,
    );
    adapter.fixture = this;
  }

  final MemoryTokenStorage storage = MemoryTokenStorage();
  final AuthAdapter adapter = AuthAdapter();
  late final ApiClient userApi;
  late final ApiClient municipalityApi;
  late final ApiAuthRepository userRepository;
  late final ApiMunicipalityAuthRepository municipalityRepository;
  bool protectedRejectsOldAccess = false;
  bool protectedAlwaysUnauthorized = false;
  bool terminalUserRefresh = false;
}

class MemoryTokenStorage extends TokenStorage {
  String? refreshToken;
  String? session;

  @override
  Future<void> saveSession(String value) async => session = value;

  @override
  Future<String?> readSession() async => session;

  @override
  Future<void> deleteSession() async => session = null;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> deleteRefreshToken() async => refreshToken = null;
}

class AuthAdapter implements HttpClientAdapter {
  late AuthApiFixture fixture;
  final List<RequestOptions> requests = [];

  Iterable<String> get paths => requests.map((request) => request.path);

  int count(String path) =>
      requests.where((request) => request.path == path).length;

  RequestOptions request(String path) =>
      requests.firstWhere((request) => request.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path == '/auth/login') {
      return jsonResponse(200, {
        'access_token': 'user-access',
        'refresh_token': 'user-refresh',
        'token_type': 'bearer',
      });
    }
    if (path == '/users/register') {
      return jsonResponse(201, userProfile);
    }
    if (path == '/auth/me') {
      return jsonResponse(200, userProfile);
    }
    if (path == '/volunteers/me') {
      return jsonResponse(404, {'detail': 'Not found'});
    }
    if (path == '/volunteer-applications/me') {
      return jsonResponse(200, {
        'items': [],
        'page': 1,
        'limit': 1,
        'total': 0,
      });
    }
    if (path == '/auth/refresh') {
      if (fixture.terminalUserRefresh) {
        return jsonResponse(401, {'detail': 'Invalid refresh token'});
      }
      return jsonResponse(200, {
        'access_token': 'refreshed-user-access',
        'token_type': 'bearer',
      });
    }
    if (path == '/auth/logout') return jsonResponse(200, {'message': 'ok'});
    if (path == '/municipalities/auth/login') {
      return jsonResponse(200, {
        'access_token': 'municipality-access',
        'refresh_token': 'municipality-refresh',
        'token_type': 'bearer',
      });
    }
    if (path == '/municipalities/auth/me') {
      return jsonResponse(200, municipalityProfile);
    }
    if (path == '/municipalities/auth/refresh') {
      return jsonResponse(200, {
        'access_token': 'refreshed-municipality-access',
        'token_type': 'bearer',
      });
    }
    if (path == '/municipalities/auth/logout') {
      return jsonResponse(200, {'message': 'ok'});
    }
    if (path == '/protected') {
      final authorization = options.headers['Authorization'];
      if (fixture.protectedAlwaysUnauthorized ||
          (fixture.protectedRejectsOldAccess &&
              authorization == 'Bearer old-access')) {
        return jsonResponse(401, {'detail': 'Expired'});
      }
      return jsonResponse(200, {'ok': true});
    }
    return jsonResponse(404, {'detail': 'Not found'});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(int status, Map<String, dynamic> data) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const userProfile = <String, dynamic>{
  'id': 7,
  'full_name': 'أحمد محمد',
  'phone': '0591234567',
  'national_id': '123456789',
  'birth_date': '1998-05-14',
  'is_active': true,
  'created_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-20T10:00:00Z',
};

const municipalityProfile = <String, dynamic>{
  'id': 3,
  'name': 'بلدية القدس',
  'email': 'municipality@firepin.ps',
  'latitude': '31.780000',
  'longitude': '35.240000',
  'is_active': true,
  'created_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-20T10:00:00Z',
};
