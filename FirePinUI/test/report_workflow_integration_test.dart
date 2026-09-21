import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/core/ui/components.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/municipality/municipality_dashboard.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/report/fire_report_repository.dart';
import 'package:firepin_ui/features/report/fire_reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'claim and resolve use the real authenticated workflow endpoints',
    () async {
      final fixture = WorkflowFixture();
      final repository = await fixture.repository();

      final pending = (await repository.getVolunteerReports()).single;
      final claimed = await repository.claimReport(pending.id);
      final resolved = await repository.resolveReport(pending.id);

      expect(pending.status, FireReportStatus.pending);
      expect(claimed.status, FireReportStatus.assigned);
      expect(claimed.assignedVolunteer?.userId, 13);
      expect(resolved.status, FireReportStatus.resolved);
      expect(
        fixture.adapter.requests.map((request) => request.path),
        containsAllInOrder([
          '/volunteers/me/fire-reports',
          '/volunteers/me/fire-reports/91/claim',
          '/volunteers/me/fire-reports/91/resolve',
        ]),
      );
      expect(
        fixture.adapter.requests.every(
          (request) => request.headers['Authorization'] == 'Bearer access',
        ),
        isTrue,
      );
    },
  );

  testWidgets('claim success reloads authoritative state and enables resolve', (
    tester,
  ) async {
    useTallTestView(tester);
    final repository = MutableWorkflowRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: repository.report,
          volunteer: true,
          repository: repository,
          location: const WorkflowLocation(),
          viewerUserId: '13',
        ),
      ),
    );

    final claim = find.byKey(const ValueKey('claim-fire-report'));
    tester.widget<AppButton>(claim).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.claims, 1);
    expect(repository.detailLoads, 1);
    expect(repository.routeLoads, 1);
    expect(find.byKey(const ValueKey('resolve-fire-report')), findsOneWidget);
  });

  testWidgets('claim conflict reports it and reloads the winning assignment', (
    tester,
  ) async {
    useTallTestView(tester);
    final repository = MutableWorkflowRepository(conflictOnClaim: true);
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: repository.report,
          volunteer: true,
          repository: repository,
          location: const WorkflowLocation(),
          viewerUserId: '13',
        ),
      ),
    );

    final claim = find.byKey(const ValueKey('claim-fire-report'));
    tester.widget<AppButton>(claim).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.claims, 1);
    expect(repository.detailLoads, 1);
    expect(repository.routeLoads, 0);
    expect(find.textContaining('متطوع آخر'), findsWidgets);
    expect(find.byKey(const ValueKey('resolve-fire-report')), findsNothing);
  });

  testWidgets('assigned volunteer resolve reloads the resolved state', (
    tester,
  ) async {
    useTallTestView(tester);
    final repository = MutableWorkflowRepository(
      initialReport: workflowReport(
        FireReportStatus.assigned,
        assignedUserId: 13,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: repository.report,
          volunteer: true,
          repository: repository,
          location: const WorkflowLocation(),
          viewerUserId: '13',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final resolve = find.byKey(const ValueKey('resolve-fire-report'));
    tester.widget<AppButton>(resolve).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.resolutions, 1);
    expect(repository.detailLoads, 1);
    expect(repository.report.status, FireReportStatus.resolved);
    expect(find.byKey(const ValueKey('resolve-fire-report')), findsNothing);
  });

  testWidgets('citizen report detail refreshes authoritative assignment', (
    tester,
  ) async {
    useTallTestView(tester);
    final repository = MutableWorkflowRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: repository.report,
          volunteer: false,
          createdSuccessfully: true,
          repository: repository,
          location: const WorkflowLocation(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('report-created-success')),
      findsOneWidget,
    );
    repository.report = workflowReport(
      FireReportStatus.assigned,
      assignedUserId: 13,
    );
    await tester.tap(find.byKey(const ValueKey('refresh-fire-report-detail')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.citizenDetailLoads, 1);
    expect(
      find.textContaining(repository.report.assignedVolunteer!.fullName),
      findsWidgets,
    );
    expect(find.text(repository.report.assignedVolunteer!.phone), findsWidgets);
  });

  testWidgets('volunteer GPS marker survives route API failure', (
    tester,
  ) async {
    useTallTestView(tester);
    final repository = MutableWorkflowRepository(
      initialReport: workflowReport(
        FireReportStatus.assigned,
        assignedUserId: 13,
      ),
      failRoute: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: repository.report,
          volunteer: true,
          repository: repository,
          location: const WorkflowLocation(),
          viewerUserId: '13',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.routeLoads, 1);
    final map = tester.widget<FireReportMap>(find.byType(FireReportMap));
    expect(map.origin?.latitude, 31.77);
    expect(map.origin?.longitude, 35.23);
    expect(find.byKey(const ValueKey('backend-route-polyline')), findsNothing);
  });

  test(
    'municipality loads assigned report data from its read-only endpoint',
    () async {
      final fixture = MunicipalityWorkflowFixture();
      final repository = await fixture.repository();

      await repository.loadVolunteerData();

      expect(repository.reports, hasLength(1));
      expect(repository.reports.single.id, 91);
      expect(repository.reports.single.status, FireReportStatus.assigned);
      expect(
        repository.reports.single.assignedVolunteer?.fullName,
        'Assigned Volunteer',
      );
      final reportRequests = fixture.adapter.requests.where(
        (request) => request.path == '/municipalities/auth/fire-reports',
      );
      expect(reportRequests, hasLength(1));
      expect(reportRequests.single.method, 'GET');
      expect(
        reportRequests.single.headers['Authorization'],
        'Bearer municipality-access',
      );
      repository.dispose();
    },
  );

  testWidgets('municipality report details are read-only', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = MunicipalityWorkflowFixture();
    final repository = await fixture.repository();

    await tester.pumpWidget(
      MaterialApp(
        home: MunicipalityDashboard(
          account: const MunicipalityAccount(
            id: '734',
            name: 'Municipality',
            email: 'municipality@example.com',
            serviceArea: '',
            isActive: true,
          ),
          repository: repository,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('#91').first);
    await tester.pumpAndSettle();

    expect(find.text('Assigned Volunteer'), findsWidgets);
    expect(find.byKey(const ValueKey('claim-fire-report')), findsNothing);
    expect(find.byKey(const ValueKey('resolve-fire-report')), findsNothing);
    repository.dispose();
  });

  testWidgets('municipality report detail reloads authoritative status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final report = MunicipalityFireReport(
      id: 91,
      status: FireReportStatus.assigned,
      reportedAt: DateTime.utc(2026, 9, 21),
      reporterName: 'Reporter',
      reporterPhone: '0591111111',
      reporterNationalId: '123456789',
      locationLabel: '31.77, 35.23',
      latitude: 31.77,
      longitude: 35.23,
      municipalityName: 'Municipality',
      assignedVolunteer: const AssignedVolunteer(
        id: 7,
        userId: 13,
        fullName: 'Assigned Volunteer',
        phone: '0590000000',
      ),
    );
    var reloads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MunicipalityReportDetailsDialog(
            incident: report,
            reload: (reportId) async {
              reloads++;
              expect(reportId, report.id);
              return MunicipalityFireReport(
                id: report.id,
                status: FireReportStatus.resolved,
                reportedAt: report.reportedAt,
                reporterName: report.reporterName,
                reporterPhone: report.reporterPhone,
                reporterNationalId: report.reporterNationalId,
                locationLabel: report.locationLabel,
                latitude: report.latitude,
                longitude: report.longitude,
                municipalityName: report.municipalityName,
                assignedVolunteer: report.assignedVolunteer,
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('refresh-municipality-report-detail')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(reloads, 1);
    expect(find.text('تمت معالجة الحالة'), findsOneWidget);
    expect(find.text('Assigned Volunteer'), findsWidgets);
    expect(find.byKey(const ValueKey('claim-fire-report')), findsNothing);
    expect(find.byKey(const ValueKey('resolve-fire-report')), findsNothing);
  });

  test('municipality API failure has no report mock fallback', () async {
    final fixture = MunicipalityWorkflowFixture()..fail = true;
    final repository = await fixture.repository();

    await expectLater(
      repository.loadVolunteerData(),
      throwsA(isA<DioException>()),
    );
    expect(repository.reports, isEmpty);
    repository.dispose();
  });

  testWidgets('volunteer home is backed by the real report repository', (
    tester,
  ) async {
    useTallTestView(tester);
    final reports = MutableWorkflowRepository();
    final session = OnboardingSession()
      ..accountId = '13'
      ..role = UsageRole.volunteer;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onReport: (_) {},
          session: session,
          onLogout: () async {},
          reportRepository: reports,
          location: const WorkflowLocation(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('volunteer-ready')), findsOneWidget);
    expect(find.byKey(const ValueKey('citizen-location-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-fire-report')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('volunteer-municipality-reports')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fire-report-91')), findsWidgets);
    expect(reports.report.status, FireReportStatus.pending);
    await tester.ensureVisible(
      find.byKey(const ValueKey('fire-report-91')).last,
    );
    await tester.tap(find.byKey(const ValueKey('fire-report-91')).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const ValueKey('claim-fire-report')), findsOneWidget);
  });
}

void useTallTestView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class WorkflowFixture {
  final storage = WorkflowTokenStorage();
  late final adapter = WorkflowAdapter();

  Future<ApiFireReportRepository> repository() async {
    final dio = Dio()..httpClientAdapter = adapter;
    final api = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      dio: dio,
    );
    await api.setSession(accessToken: 'access', refreshToken: 'refresh');
    return ApiFireReportRepository(api);
  }
}

class WorkflowAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  FireReportStatus status = FireReportStatus.pending;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path == '/volunteers/me/fire-reports') {
      return jsonResponse(200, {
        'items': [workflowReportJson(status)],
        'page': 1,
        'limit': 100,
        'total': 1,
      });
    }
    if (options.path == '/volunteers/me/fire-reports/91/claim') {
      status = FireReportStatus.assigned;
      return jsonResponse(200, workflowReportJson(status, assignedUserId: 13));
    }
    if (options.path == '/volunteers/me/fire-reports/91/resolve') {
      status = FireReportStatus.resolved;
      return jsonResponse(200, workflowReportJson(status, assignedUserId: 13));
    }
    return jsonResponse(404, {'detail': 'not found'});
  }

  @override
  void close({bool force = false}) {}
}

class MutableWorkflowRepository implements FireReportRepository {
  MutableWorkflowRepository({
    FireReport? initialReport,
    this.conflictOnClaim = false,
    this.failRoute = false,
  }) : report = initialReport ?? workflowReport(FireReportStatus.pending);

  FireReport report;
  final bool conflictOnClaim;
  final bool failRoute;
  int claims = 0;
  int resolutions = 0;
  int detailLoads = 0;
  int citizenDetailLoads = 0;
  int routeLoads = 0;

  @override
  Future<FireReport> claimReport(int reportId) async {
    claims++;
    if (conflictOnClaim) {
      report = workflowReport(FireReportStatus.assigned, assignedUserId: 27);
      final request = RequestOptions(path: '/claim');
      throw DioException(
        requestOptions: request,
        response: Response<void>(requestOptions: request, statusCode: 409),
      );
    }
    report = workflowReport(FireReportStatus.assigned, assignedUserId: 13);
    return report;
  }

  @override
  Future<FireReport> resolveReport(int reportId) async {
    resolutions++;
    report = workflowReport(FireReportStatus.resolved, assignedUserId: 13);
    return report;
  }

  @override
  Future<FireReport> getVolunteerReport(int reportId) async {
    detailLoads++;
    return report;
  }

  @override
  Future<List<FireReport>> getVolunteerReports() async => [report];

  @override
  Future<FireReportRoute> getVolunteerRoute(
    int reportId,
    LocationFix origin,
  ) async {
    routeLoads++;
    if (failRoute) throw StateError('Valhalla unavailable');
    return const FireReportRoute(
      geometry: [
        RoutePoint(latitude: 31.77, longitude: 35.23),
        RoutePoint(latitude: 31.79, longitude: 35.25),
      ],
      distanceKm: 2,
      durationSeconds: 240,
    );
  }

  @override
  Future<Uint8List> getImage(int reportId, int imageId) async => Uint8List(0);

  @override
  Future<FireReport> getMyReport(int reportId) async {
    citizenDetailLoads++;
    return report;
  }

  @override
  Future<List<FireReport>> getMyReports() async => [report];

  @override
  Future<FireReport> submit({
    required List<Uint8List> images,
    String? pin,
    required LocationFix location,
  }) async => report;
}

class MunicipalityWorkflowFixture {
  final storage = WorkflowTokenStorage();
  late final adapter = MunicipalityWorkflowAdapter(this);
  bool fail = false;

  Future<MunicipalityOperationsRepository> repository() async {
    final dio = Dio()..httpClientAdapter = adapter;
    final api = ApiClient(
      baseUrl: 'https://api.example.com',
      tokenStorage: storage,
      dio: dio,
    );
    await api.setSession(
      accessToken: 'municipality-access',
      refreshToken: 'municipality-refresh',
    );
    return MunicipalityOperationsRepository(api: api);
  }
}

class MunicipalityWorkflowAdapter implements HttpClientAdapter {
  MunicipalityWorkflowAdapter(this.fixture);
  final MunicipalityWorkflowFixture fixture;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fixture.fail) return jsonResponse(503, {'detail': 'offline'});
    if (options.path == '/municipalities/auth/fire-reports') {
      return jsonResponse(200, {
        'items': [municipalityReportJson],
        'page': 1,
        'limit': 100,
        'total': 1,
      });
    }
    if (options.path == '/municipalities/auth/volunteer-applications' ||
        options.path == '/municipalities/auth/volunteers') {
      return jsonResponse(200, {
        'items': <Object>[],
        'page': 1,
        'limit': 100,
        'total': 0,
      });
    }
    return jsonResponse(404, {'detail': 'not found'});
  }

  @override
  void close({bool force = false}) {}
}

class WorkflowTokenStorage extends TokenStorage {
  String? token;

  @override
  Future<void> saveRefreshToken(String value) async => token = value;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> deleteRefreshToken() async => token = null;
}

class WorkflowLocation implements LocationService {
  const WorkflowLocation();

  @override
  Future<LocationFix> requestCurrentPosition() async =>
      const LocationFix(31.77, 35.23, 5);

  @override
  Future<bool> openSettings({bool locationService = false}) async => true;
}

FireReport workflowReport(FireReportStatus status, {int? assignedUserId}) =>
    FireReport(
      id: 91,
      latitude: 31.79,
      longitude: 35.25,
      status: status,
      reportedAt: DateTime.parse('2026-09-20T10:00:00Z'),
      updatedAt: DateTime.parse('2026-09-20T10:05:00Z'),
      municipality: const FireReportMunicipality(id: 734, name: 'Municipality'),
      images: const [],
      assignedVolunteer: assignedUserId == null
          ? null
          : AssignedVolunteer(
              id: assignedUserId == 13 ? 7 : 8,
              userId: assignedUserId,
              fullName: assignedUserId == 13
                  ? 'Assigned Volunteer'
                  : 'Winning Volunteer',
              phone: '0590000000',
            ),
    );

Map<String, Object?> workflowReportJson(
  FireReportStatus status, {
  int? assignedUserId,
}) => {
  'id': 91,
  'latitude': '31.790000',
  'longitude': '35.250000',
  'status': status.name,
  'reported_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-20T10:05:00Z',
  'municipality': {'id': 734, 'name': 'Municipality'},
  'assigned_volunteer': assignedUserId == null
      ? null
      : {
          'id': 7,
          'user': {
            'id': assignedUserId,
            'full_name': 'Assigned Volunteer',
            'phone': '0590000000',
          },
        },
  'images': <Object>[],
};

final municipalityReportJson = {
  ...workflowReportJson(FireReportStatus.assigned, assignedUserId: 13),
  'reporter': {
    'id': 41,
    'full_name': 'Reporter',
    'national_id': '123456789',
    'phone': '0591111111',
  },
};

ResponseBody jsonResponse(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
