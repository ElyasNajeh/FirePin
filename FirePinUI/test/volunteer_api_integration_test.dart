import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/core/ui/components.dart';
import 'package:firepin_ui/features/account/account_screen.dart';
import 'package:firepin_ui/features/auth/auth_controller.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/onboarding_services.dart';
import 'package:firepin_ui/features/onboarding/volunteer_application_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  test(
    'user submits the selected real municipality ID with bearer auth',
    () async {
      final fixture = Stage4Fixture();
      final api = fixture.userApi();
      await api.setSession(
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
      );
      final service = ApiVolunteerApplicationService(api);

      final status = await service.submit(municipalityId: 734);

      expect(status, ApplicationStatus.pending);
      final request = fixture.adapter.requests.singleWhere(
        (item) => item.path == '/volunteer-applications',
      );
      expect(request.data, {'municipality_id': 734});
      expect(request.headers['Authorization'], 'Bearer user-access');
    },
  );

  test(
    'application API failures surface without a Stage 4 mock fallback',
    () async {
      final fixture = Stage4Fixture()..userSubmissionFails = true;
      final api = fixture.userApi();
      await api.setSession(
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
      );

      await expectLater(
        ApiVolunteerApplicationService(api).submit(municipalityId: 734),
        throwsA(isA<DioException>()),
      );
    },
  );

  test(
    'duplicate pending application is surfaced as a backend conflict',
    () async {
      final fixture = Stage4Fixture()..duplicatePending = true;
      final api = fixture.userApi();
      await api.setSession(
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
      );

      await expectLater(
        ApiVolunteerApplicationService(api).submit(municipalityId: 734),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status code',
            409,
          ),
        ),
      );
    },
  );

  test(
    'registration is authenticated before submission and activates pending state',
    () async {
      final users = Stage4AuthRepository();
      final sessions = MemorySessionRepository();
      final controller = AuthController(
        users: users,
        municipalities: DemoMunicipalityAuthRepository(),
        sessions: sessions,
      );
      final session = registrationSession();

      await controller.prepareRegistration(session);
      expect(users.registered, isTrue);
      expect(controller.status, AuthStatus.signedOut);
      expect((await sessions.read())?.principal, AuthPrincipal.user);

      users.status = ApplicationStatus.pending;
      await controller.activatePreparedRegistration();
      expect(controller.status, AuthStatus.user);
      expect(controller.user?.applicationStatus, ApplicationStatus.pending);
      expect(controller.user?.hasVolunteerMembership, isFalse);
      controller.dispose();
    },
  );

  test(
    'cold API restoration identifies an accepted user as a real volunteer',
    () async {
      final fixture = Stage4Fixture()..restoreAsVolunteer = true;
      await fixture.storage.saveRefreshToken('user-refresh');
      final sessions = SecureSessionRepository(storage: fixture.storage);
      await sessions.save(const StoredSession(principal: AuthPrincipal.user));
      final users = ApiAuthRepository(
        api: fixture.userApi(),
        storage: fixture.storage,
      );
      final controller = AuthController(
        users: users,
        municipalities: DemoMunicipalityAuthRepository(),
        sessions: sessions,
      );

      await controller.restore();

      expect(controller.status, AuthStatus.user);
      expect(controller.user?.applicationStatus, ApplicationStatus.accepted);
      expect(controller.user?.role, UsageRole.volunteer);
      controller.dispose();
    },
  );

  test(
    'user profile restoration maps rejected backend state exactly',
    () async {
      final fixture = Stage4Fixture()
        ..restoredApplicationStatus = ApplicationStatus.rejected;
      await fixture.storage.saveRefreshToken('user-refresh');
      final account = await ApiAuthRepository(
        api: fixture.userApi(),
        storage: fixture.storage,
      ).restoreUser();

      expect(account.applicationStatus, ApplicationStatus.rejected);
      expect(account.hasVolunteerMembership, isFalse);
      expect(account.role, UsageRole.citizen);
    },
  );

  test(
    'municipality loads real applications, statuses, IDs, and volunteers',
    () async {
      final fixture = Stage4Fixture();
      final api = fixture.municipalityApi();
      await api.setSession(
        accessToken: 'municipality-access',
        refreshToken: 'municipality-refresh',
      );
      final repository = MunicipalityOperationsRepository(api: api);

      await repository.loadVolunteerData();

      expect(repository.applications.single.id, 71);
      expect(repository.applications.single.userId, 13);
      expect(repository.applications.single.status, ApplicationStatus.pending);
      expect(repository.volunteers.single.id, 31);
      expect(repository.volunteers.single.userId, 11);
      expect(repository.volunteerDataError, isNull);
      expect(
        fixture.adapter.requests
            .where(
              (item) =>
                  item.path == '/municipalities/auth/volunteer-applications',
            )
            .single
            .headers['Authorization'],
        'Bearer municipality-access',
      );

      repository.dispose();
    },
  );

  test(
    'accept and reject use real endpoints then refresh PostgreSQL state',
    () async {
      final fixture = Stage4Fixture();
      final api = fixture.municipalityApi();
      await api.setSession(
        accessToken: 'municipality-access',
        refreshToken: 'municipality-refresh',
      );
      final repository = MunicipalityOperationsRepository(api: api);
      await repository.loadVolunteerData();

      await repository.acceptApplication(71);
      expect(repository.applications.single.status, ApplicationStatus.accepted);
      expect(repository.volunteers.any((item) => item.userId == 13), isTrue);
      expect(
        fixture.adapter.requests.any(
          (item) =>
              item.path ==
              '/municipalities/auth/volunteer-applications/71/accept',
        ),
        isTrue,
      );

      fixture.resetForReject();
      await repository.loadVolunteerData();
      await repository.rejectApplication(71);
      expect(repository.applications.single.status, ApplicationStatus.rejected);
      expect(
        fixture.adapter.requests.any(
          (item) =>
              item.path ==
              '/municipalities/auth/volunteer-applications/71/reject',
        ),
        isTrue,
      );

      repository.dispose();
    },
  );

  test(
    'malformed municipality API data is not replaced with fake records',
    () async {
      final fixture = Stage4Fixture()..malformedMunicipalityData = true;
      final api = fixture.municipalityApi();
      await api.setSession(
        accessToken: 'municipality-access',
        refreshToken: 'municipality-refresh',
      );
      final repository = MunicipalityOperationsRepository(api: api);

      await expectLater(repository.loadVolunteerData(), throwsFormatException);
      expect(repository.applications, isEmpty);
      expect(repository.volunteers, isEmpty);
      expect(repository.volunteerDataError, isA<FormatException>());

      repository.dispose();
    },
  );

  testWidgets('Stage 3 selection flows its real ID into Stage 4 submission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = RecordingVolunteerApplicationService();
    ApplicationStatus? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: VolunteerApplicationFlow(
          directory: FakeMunicipalityDirectoryRepository(
            municipalities: const [
              MunicipalityDirectoryEntry(
                id: 734,
                name: 'Test municipality',
                latitude: 31.5,
                longitude: 35.1,
              ),
            ],
          ),
          applications: service,
          onCancel: () {},
          onSubmitted: (status) async => submitted = status,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<InkWell>(find.byKey(const ValueKey('municipality-734')))
        .onTap!();
    await tester.pump();
    tester
        .widget<AppButton>(
          find.byKey(const ValueKey('municipality-selection-continue')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<AppButton>(
          find.byKey(const ValueKey('volunteer-application-submit')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(service.municipalityId, 734);
    expect(submitted, ApplicationStatus.pending);
  });

  testWidgets('rejected user is offered a real reapplication flow', (
    tester,
  ) async {
    var started = false;
    final session = OnboardingSession()
      ..applicationStatus = ApplicationStatus.rejected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountScreen(
              session: session,
              onLogout: () {},
              onApplyVolunteer: () => started = true,
            ),
          ),
        ),
      ),
    );

    final applyButton = tester.widget<AppButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppButton && widget.label == 'إعادة التقديم كمتطوع',
      ),
    );
    applyButton.onPressed!();

    expect(started, isTrue);
  });
}

class RecordingVolunteerApplicationService
    implements VolunteerApplicationService {
  int? municipalityId;

  @override
  Future<ApplicationStatus> submit({required int municipalityId}) async {
    this.municipalityId = municipalityId;
    return ApplicationStatus.pending;
  }
}

class Stage4Fixture {
  final storage = MemoryTokenStorage();
  late final adapter = Stage4Adapter(this);
  bool userSubmissionFails = false;
  bool duplicatePending = false;
  bool malformedMunicipalityData = false;
  bool restoreAsVolunteer = false;
  ApplicationStatus restoredApplicationStatus = ApplicationStatus.none;
  ApplicationStatus applicationStatus = ApplicationStatus.pending;
  bool acceptedVolunteerCreated = false;

  ApiClient userApi() => _api('/auth/refresh');
  ApiClient municipalityApi() => _api('/municipalities/auth/refresh');

  ApiClient _api(String refreshPath) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      refreshPath: refreshPath,
      dio: dio,
    );
  }

  void resetForReject() {
    applicationStatus = ApplicationStatus.pending;
    acceptedVolunteerCreated = false;
  }
}

class Stage4Adapter implements HttpClientAdapter {
  Stage4Adapter(this.fixture);
  final Stage4Fixture fixture;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;
    if (path == '/volunteer-applications') {
      if (fixture.userSubmissionFails) {
        return response(503, {'detail': 'offline'});
      }
      if (fixture.duplicatePending) {
        return response(409, {
          'detail': 'User already has a pending volunteer application',
        });
      }
      return response(201, {
        'id': 71,
        'status': 'pending',
        'municipality': {'id': options.data['municipality_id']},
      });
    }
    if (path == '/auth/refresh') {
      return response(200, {
        'access_token': 'restored-user-access',
        'token_type': 'bearer',
      });
    }
    if (path == '/auth/me') {
      return response(200, {
        'id': 13,
        'full_name': 'Applicant',
        'national_id': '123456789',
        'phone': '0591111111',
        'birth_date': '1998-05-14',
        'is_active': true,
      });
    }
    if (path == '/volunteers/me') {
      if (!fixture.restoreAsVolunteer) {
        return response(404, {'detail': 'Volunteer not found'});
      }
      return response(200, {
        'id': 31,
        'user_id': 13,
        'municipality': {'id': 734, 'name': 'Test municipality'},
        'created_at': '2026-09-20T10:00:00Z',
      });
    }
    if (path == '/volunteer-applications/me') {
      final status = fixture.restoredApplicationStatus;
      return response(200, {
        'items': status == ApplicationStatus.none
            ? []
            : [
                {
                  'id': 71,
                  'status': status.name,
                  'created_at': '2026-09-20T10:00:00Z',
                },
              ],
        'page': 1,
        'limit': 1,
        'total': status == ApplicationStatus.none ? 0 : 1,
      });
    }
    if (path.endsWith('/71/accept')) {
      fixture.applicationStatus = ApplicationStatus.accepted;
      fixture.acceptedVolunteerCreated = true;
      return response(200, {'application': {}, 'volunteer': {}});
    }
    if (path.endsWith('/71/reject')) {
      fixture.applicationStatus = ApplicationStatus.rejected;
      return response(200, {'id': 71, 'status': 'rejected'});
    }
    if (path == '/municipalities/auth/volunteer-applications') {
      if (fixture.malformedMunicipalityData) {
        return response(200, {'items': 'invalid', 'total': 1});
      }
      return response(200, {
        'items': [
          {
            'id': 71,
            'status': fixture.applicationStatus.name,
            'user': {
              'id': 13,
              'full_name': 'Applicant',
              'phone': '0591111111',
              'national_id': '123456789',
              'birth_date': '1998-05-14',
            },
            'created_at': '2026-09-20T10:00:00Z',
          },
        ],
        'page': 1,
        'limit': 100,
        'total': 1,
      });
    }
    if (path == '/municipalities/auth/volunteers') {
      final items = [
        {
          'id': 31,
          'user_id': 11,
          'full_name': 'Existing volunteer',
          'phone': '0592222222',
          'national_id': '987654321',
          'birth_date': '1997-03-12',
          'created_at': '2026-09-10T10:00:00Z',
        },
        if (fixture.acceptedVolunteerCreated)
          {
            'id': 32,
            'user_id': 13,
            'full_name': 'Applicant',
            'phone': '0591111111',
            'national_id': '123456789',
            'birth_date': '1998-05-14',
            'created_at': '2026-09-20T10:05:00Z',
          },
      ];
      return response(200, {
        'items': items,
        'page': 1,
        'limit': 100,
        'total': items.length,
      });
    }
    if (path == '/municipalities/auth/fire-reports') {
      return response(200, {'items': [], 'page': 1, 'limit': 100, 'total': 0});
    }
    return response(404, {'detail': 'not found'});
  }

  @override
  void close({bool force = false}) {}
}

OnboardingSession registrationSession() {
  final session = OnboardingSession()
    ..identity = const IdentityData(
      fullName: 'Applicant',
      identityNumber: '123456789',
      birthDate: '14 / 05 / 1998',
      address: '',
    )
    ..phone = '0591111111';
  session.savePin('2468', '2468');
  return session;
}

class Stage4AuthRepository implements AuthRepository {
  bool registered = false;
  ApplicationStatus status = ApplicationStatus.none;
  bool hasMembership = false;

  UserAccount get account => UserAccount(
    id: '13',
    fullName: 'Applicant',
    nationalId: '123456789',
    phone: '0591111111',
    birthDate: '14 / 05 / 1998',
    address: '',
    applicationStatus: status,
    hasVolunteerMembership: hasMembership,
  );

  @override
  Future<UserLoginResult> registerUser(OnboardingSession session) async {
    registered = true;
    return UserLoginResult(account: account);
  }

  @override
  Future<UserAccount> restoreUser() async => account;
  @override
  Future<void> clearLocalSession() async {}
  @override
  Future<void> logoutUser() async {}
  @override
  Future<UserLoginResult> loginUser({
    required String nationalId,
    required String pin,
  }) async => UserLoginResult(account: account);
}

class MemoryTokenStorage extends TokenStorage {
  String? refreshToken;
  String? session;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;
  @override
  Future<String?> readRefreshToken() async => refreshToken;
  @override
  Future<void> deleteRefreshToken() async => refreshToken = null;
  @override
  Future<void> saveSession(String value) async => session = value;
  @override
  Future<String?> readSession() async => session;
  @override
  Future<void> deleteSession() async => session = null;
}

ResponseBody response(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
