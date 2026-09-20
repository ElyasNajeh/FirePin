import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/app/app_services.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/report/fire_report_repository.dart';
import 'package:firepin_ui/features/report/fire_reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppServices has no Stage-5 runtime report mock fallback', () {
    final services = AppServices(apiBaseUrl: 'https://api.example.com');
    expect(services.reports, isA<ApiFireReportRepository>());
    expect(services.reportRepository, same(services.reports));
    services.authController.dispose();
    (services.operations as ChangeNotifier).dispose();
    services.incidents.dispose();
  });

  test('one submission sends real GPS and PIN exactly once', () async {
    final fixture = ReportFixture();
    final repository = await fixture.repository();

    await repository.submit(
      location: const LocationFix(31.781234, 35.241234, 7),
      pin: '2468',
    );

    final requests = fixture.adapter.requests
        .where((request) => request.path == '/fire-reports')
        .toList();
    expect(requests, hasLength(1));
    final form = requests.single.data as FormData;
    expect(_field(form, 'latitude'), '31.781234');
    expect(_field(form, 'longitude'), '35.241234');
    expect(_field(form, 'pin'), '2468');
    expect(form.fields.any((field) => field.key == 'municipality_id'), isFalse);
    expect(form.files, isEmpty);
    expect(requests.single.headers['Authorization'], 'Bearer access');
  });

  test('multipart photo omits PIN and preserves camera bytes', () async {
    final fixture = ReportFixture();
    final repository = await fixture.repository();
    final photo = Uint8List.fromList([1, 2, 3, 4]);

    await repository.submit(
      location: const LocationFix(31.7, 35.2, 4),
      photo: photo,
    );

    final form = fixture.adapter.requests.single.data as FormData;
    expect(form.fields.any((field) => field.key == 'pin'), isFalse);
    expect(form.files, hasLength(1));
    expect(form.files.single.key, 'images');
    expect(form.files.single.value.length, photo.length);
    expect(form.files.single.value.filename, 'fire-report.jpg');
  });

  test('real report list/detail and protected image map from API', () async {
    final fixture = ReportFixture();
    final repository = await fixture.repository();

    final reports = await repository.getMyReports();
    final detail = await repository.getMyReport(91);
    final image = await repository.getImage(91, 7);

    expect(reports.single.id, 91);
    expect(reports.single.status, FireReportStatus.pending);
    expect(reports.single.municipality.id, 734);
    expect(detail.images.single.url, '/fire-reports/91/images/7');
    expect(image, Uint8List.fromList([10, 20, 30]));
    final imageRequest = fixture.adapter.requests.singleWhere(
      (request) => request.path == '/fire-reports/91/images/7',
    );
    expect(imageRequest.headers['Authorization'], 'Bearer access');
  });

  test('real route maps backend geometry and sends origin only', () async {
    final fixture = ReportFixture();
    final repository = await fixture.repository();

    final route = await repository.getVolunteerRoute(
      91,
      const LocationFix(31.77, 35.23, 5),
    );

    expect(route.geometry, hasLength(3));
    expect(route.geometry[1].latitude, 31.78);
    expect(route.distanceKm, 4.2);
    expect(route.durationSeconds, 540);
    final request = fixture.adapter.requests.singleWhere(
      (request) => request.path.endsWith('/91/route'),
    );
    expect(request.data, {'latitude': 31.77, 'longitude': 35.23});
    expect((request.data as Map).containsKey('destination'), isFalse);
  });

  testWidgets('map uses backend geometry and displays distance and duration', (
    tester,
  ) async {
    final repository = StaticReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: sampleReport,
          volunteer: true,
          repository: repository,
          location: FixedLocationService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final layer = tester.widget<PolylineLayer>(
      find.byKey(const ValueKey('backend-route-polyline')),
    );
    expect(layer.polylines.single.points, hasLength(3));
    expect(layer.polylines.single.points[1].latitude, 31.78);
    expect(find.text('4.2 كم'), findsOneWidget);
    expect(find.text('9 دقيقة'), findsOneWidget);
  });

  testWidgets('route failure shows error and never draws a fake line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FireReportDetailScreen(
          report: sampleReport,
          volunteer: true,
          repository: StaticReportRepository(failRoute: true),
          location: FixedLocationService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('تعذّر تحميل مسار الطريق الحقيقي.'), findsOneWidget);
    expect(find.byKey(const ValueKey('backend-route-polyline')), findsNothing);
  });

  test('production report failures surface without a mock fallback', () async {
    final fixture = ReportFixture()..failReports = true;
    await expectLater(
      (await fixture.repository()).getMyReports(),
      throwsA(isA<DioException>()),
    );
  });
}

String? _field(FormData data, String key) =>
    data.fields.where((field) => field.key == key).firstOrNull?.value;

class ReportFixture {
  final storage = ReportTokenStorage();
  late final adapter = ReportAdapter(this);
  bool failReports = false;

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

class ReportTokenStorage extends TokenStorage {
  String? token;
  @override
  Future<void> saveRefreshToken(String value) async => token = value;
  @override
  Future<String?> readRefreshToken() async => token;
  @override
  Future<void> deleteRefreshToken() async => token = null;
}

class ReportAdapter implements HttpClientAdapter {
  ReportAdapter(this.fixture);
  final ReportFixture fixture;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fixture.failReports) return _json(503, {'detail': 'offline'});
    if (options.path == '/fire-reports') return _json(201, reportJson);
    if (options.path == '/fire-reports/me') {
      return _json(200, {
        'items': [reportJson],
        'page': 1,
        'limit': 100,
        'total': 1,
      });
    }
    if (options.path == '/fire-reports/me/91') return _json(200, reportJson);
    if (options.path == '/fire-reports/91/images/7') {
      return ResponseBody.fromBytes(
        [10, 20, 30],
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }
    if (options.path == '/volunteers/me/fire-reports/91/route') {
      return _json(200, routeJson);
    }
    return _json(404, {'detail': 'not found'});
  }

  @override
  void close({bool force = false}) {}
}

class StaticReportRepository implements FireReportRepository {
  StaticReportRepository({this.failRoute = false});
  final bool failRoute;

  @override
  Future<FireReportRoute> getVolunteerRoute(
    int reportId,
    LocationFix origin,
  ) async {
    if (failRoute) throw StateError('Valhalla unavailable');
    return const FireReportRoute(
      geometry: [
        RoutePoint(latitude: 31.77, longitude: 35.23),
        RoutePoint(latitude: 31.78, longitude: 35.24),
        RoutePoint(latitude: 31.79, longitude: 35.25),
      ],
      distanceKm: 4.2,
      durationSeconds: 540,
    );
  }

  @override
  Future<Uint8List> getImage(int reportId, int imageId) async => Uint8List(0);
  @override
  Future<FireReport> getMyReport(int reportId) async => sampleReport;
  @override
  Future<List<FireReport>> getMyReports() async => [sampleReport];
  @override
  Future<FireReport> getVolunteerReport(int reportId) async => sampleReport;
  @override
  Future<List<FireReport>> getVolunteerReports() async => [sampleReport];
  @override
  Future<void> submit({
    Uint8List? photo,
    String? pin,
    required LocationFix location,
  }) async {}
}

class FixedLocationService implements LocationService {
  @override
  Future<LocationFix> requestCurrentPosition() async =>
      const LocationFix(31.77, 35.23, 5);
  @override
  Future<bool> openSettings({bool locationService = false}) async => true;
}

final sampleReport = FireReport(
  id: 91,
  latitude: 31.79,
  longitude: 35.25,
  status: FireReportStatus.pending,
  reportedAt: DateTime.parse('2026-09-20T10:00:00Z'),
  updatedAt: DateTime.parse('2026-09-20T10:00:00Z'),
  municipality: const FireReportMunicipality(id: 734, name: 'Municipality'),
  images: const [],
);

final reportJson = {
  'id': 91,
  'latitude': '31.790000',
  'longitude': '35.250000',
  'status': 'pending',
  'reported_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-20T10:00:00Z',
  'municipality': {'id': 734, 'name': 'Municipality'},
  'assigned_volunteer': null,
  'images': [
    {'id': 7, 'url': '/fire-reports/91/images/7'},
  ],
};

const routeJson = {
  'geometry': [
    {'latitude': 31.77, 'longitude': 35.23},
    {'latitude': 31.78, 'longitude': 35.24},
    {'latitude': 31.79, 'longitude': 35.25},
  ],
  'distance_km': 4.2,
  'duration_seconds': 540,
};

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
