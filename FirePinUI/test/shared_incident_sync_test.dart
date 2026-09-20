import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/incidents/shared_mock_incident_client.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/mock_server.dart';

void main() {
  late FirePinMockServer server;
  late String baseUrl;
  final controllers = <IncidentController>[];

  IncidentController clientController({
    Duration pollInterval = const Duration(seconds: 1),
    SharedMockIncidentClient? client,
  }) {
    final controller = IncidentController(
      sharedClient: client ?? DioSharedMockIncidentClient(baseUrl: baseUrl),
      pollInterval: pollInterval,
    );
    controllers.add(controller);
    return controller;
  }

  setUp(() async {
    server = await FirePinMockServer.start(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    baseUrl = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
    await server.close();
  });

  test(
    'platform defaults and explicit base URL override are deterministic',
    () {
      expect(
        resolveSharedMockBaseUrl(web: true, platform: TargetPlatform.android),
        'http://127.0.0.1:8787',
      );
      expect(
        resolveSharedMockBaseUrl(web: false, platform: TargetPlatform.android),
        'http://10.0.2.2:8787',
      );
      expect(
        resolveSharedMockBaseUrl(web: false, platform: TargetPlatform.windows),
        'http://127.0.0.1:8787',
      );
      expect(
        resolveSharedMockBaseUrl(
          override: 'http://192.168.1.20:9000/',
          web: false,
          platform: TargetPlatform.android,
        ),
        'http://192.168.1.20:9000',
      );
    },
  );

  test('three clients share multi-responder lifecycle through HTTP', () async {
    final citizen = clientController();
    final volunteerA = clientController();
    final volunteerB = clientController();

    expect(
      await citizen.report(
        location: const LocationFix(31.78, 35.24, 10),
        reporterId: 'user-citizen',
        reporterName: 'أحمد محمد عبد الله',
        reporterNationalId: '123456789',
        reporterPhone: '059 123 4567',
      ),
      isTrue,
    );
    final incidentId = citizen.incident!.id;
    await Future.wait([volunteerA.refresh(), volunteerB.refresh()]);
    expect(volunteerA.incident!.id, incidentId);
    expect(volunteerB.incident!.id, incidentId);

    expect(
      await volunteerA.acceptByVolunteer(
        volunteerId: 'user-volunteer',
        displayName: 'ليان أحمد صالح',
        phone: '059 222 3344',
      ),
      isTrue,
    );
    expect(
      await volunteerB.acceptByVolunteer(
        volunteerId: 'user-volunteer-2',
        displayName: 'عمر يوسف النجار',
        phone: '059 333 4466',
      ),
      isTrue,
    );
    await Future.wait([
      citizen.refresh(),
      volunteerA.refresh(),
      volunteerB.refresh(),
    ]);
    for (final controller in [citizen, volunteerA, volunteerB]) {
      expect(controller.incident!.id, incidentId);
      expect(controller.incident!.responderCount, 2);
    }

    final directClient = DioSharedMockIncidentClient(baseUrl: baseUrl);
    await directClient.decline(
      incidentId: incidentId,
      volunteerId: 'user-volunteer-declined',
      displayName: 'متطوع معتذر',
      phone: '059 000 0000',
    );
    await citizen.refresh();
    expect(citizen.incident!.isDeclinedFor('user-volunteer-declined'), isTrue);
    expect(citizen.incident!.responderCount, 2);

    expect(
      await volunteerA.withdrawVolunteerResponse('user-volunteer'),
      isTrue,
    );
    await Future.wait([citizen.refresh(), volunteerB.refresh()]);
    expect(citizen.incident!.responderCount, 1);
    expect(citizen.incident!.hasResponded('user-volunteer'), isFalse);
    expect(citizen.incident!.hasResponded('user-volunteer-2'), isTrue);

    await expectLater(
      directClient.resolve(
        incidentId: incidentId,
        volunteerId: 'user-volunteer-declined',
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          HttpStatus.forbidden,
        ),
      ),
    );
    expect(await volunteerB.resolveByVolunteer('user-volunteer-2'), isTrue);
    await Future.wait([
      citizen.refresh(),
      volunteerA.refresh(),
      volunteerB.refresh(),
    ]);

    for (final controller in [citizen, volunteerA, volunteerB]) {
      expect(controller.incident!.isResolved, isTrue);
      expect(controller.incident!.responderCount, 0);
      expect(controller.incident!.responders, isEmpty);
      expect(
        controller.incident!.volunteerResponses.any(
          (response) => response.volunteerId == 'user-volunteer-2',
        ),
        isTrue,
      );
    }
  });

  test(
    'single-incident UI projection selects the newest active incident',
    () async {
      final directClient = DioSharedMockIncidentClient(baseUrl: baseUrl);
      final first = await directClient.createIncident(
        reporterId: 'user-citizen',
        reporterName: 'Citizen A',
        reporterPhone: '059 123 4567',
        latitude: 31.78,
        longitude: 35.24,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await directClient.createIncident(
        reporterId: 'user-citizen-2',
        reporterName: 'Citizen B',
        reporterPhone: '059 333 4455',
        latitude: 31.79,
        longitude: 35.25,
      );
      final observer = clientController();
      await observer.refresh();
      expect(observer.incident!.id, second.id);

      await directClient.respond(
        incidentId: second.id,
        volunteerId: 'user-volunteer',
        displayName: 'Volunteer A',
        phone: '059 222 3344',
      );
      await directClient.resolve(
        incidentId: second.id,
        volunteerId: 'user-volunteer',
      );
      await observer.refresh();
      expect(observer.incident!.id, first.id);
      expect(observer.incident!.isResolved, isFalse);

      await directClient.respond(
        incidentId: first.id,
        volunteerId: 'user-volunteer-2',
        displayName: 'Volunteer B',
        phone: '059 333 4466',
      );
      await directClient.resolve(
        incidentId: first.id,
        volunteerId: 'user-volunteer-2',
      );
      await observer.refresh();
      expect(observer.hasActiveIncident, isFalse);
      expect(observer.incident!.id, second.id);
      expect(observer.incident!.isResolved, isTrue);
      expect(observer.incidents, hasLength(2));
    },
  );

  test(
    'polling sees remote state, preserves valid data on failure, and stops',
    () async {
      final writer = clientController();
      final countingClient = _CountingClient(
        DioSharedMockIncidentClient(baseUrl: baseUrl),
      );
      final observer = clientController(
        client: countingClient,
        pollInterval: const Duration(milliseconds: 30),
      );
      await observer.startPolling();
      await writer.report(
        location: const LocationFix(31.78, 35.24, 10),
        reporterId: 'user-citizen',
        reporterName: 'أحمد محمد عبد الله',
        reporterPhone: '059 123 4567',
      );

      await _waitUntil(() => observer.incident != null);
      final incidentId = observer.incident!.id;
      expect(incidentId, writer.incident!.id);

      observer.stopPolling();
      final stoppedFetches = countingClient.fetchCount;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(countingClient.fetchCount, stoppedFetches);
      expect(observer.isPolling, isFalse);

      await server.close();
      expect(await observer.refresh(), isFalse);
      expect(observer.incident!.id, incidentId);
      expect(observer.hasSyncError, isTrue);

      await observer.startPolling();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      observer.dispose();
      controllers.remove(observer);
      expect(observer.isPolling, isFalse);
      final disposedFetches = countingClient.fetchCount;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(countingClient.fetchCount, disposedFetches);
    },
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for shared incident polling.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _CountingClient implements SharedMockIncidentClient {
  _CountingClient(this.delegate);

  final SharedMockIncidentClient delegate;
  int fetchCount = 0;

  @override
  Future<List<SharedIncidentSnapshot>> fetchState() {
    fetchCount++;
    return delegate.fetchState();
  }

  @override
  Future<SharedIncidentSnapshot> createIncident({
    required String reporterId,
    required String reporterName,
    required String reporterPhone,
    required double latitude,
    required double longitude,
    String? reporterNationalId,
    bool hasPhoto = false,
  }) => delegate.createIncident(
    reporterId: reporterId,
    reporterName: reporterName,
    reporterPhone: reporterPhone,
    latitude: latitude,
    longitude: longitude,
    reporterNationalId: reporterNationalId,
    hasPhoto: hasPhoto,
  );

  @override
  Future<SharedIncidentSnapshot> decline({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  }) => delegate.decline(
    incidentId: incidentId,
    volunteerId: volunteerId,
    displayName: displayName,
    phone: phone,
  );

  @override
  Future<SharedIncidentSnapshot> resolve({
    required String incidentId,
    required String volunteerId,
  }) => delegate.resolve(incidentId: incidentId, volunteerId: volunteerId);

  @override
  Future<SharedIncidentSnapshot> respond({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  }) => delegate.respond(
    incidentId: incidentId,
    volunteerId: volunteerId,
    displayName: displayName,
    phone: phone,
  );

  @override
  Future<SharedIncidentSnapshot> withdraw({
    required String incidentId,
    required String volunteerId,
  }) => delegate.withdraw(incidentId: incidentId, volunteerId: volunteerId);
}
