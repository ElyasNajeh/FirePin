import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/incidents/shared_mock_incident_client.dart';
import 'package:firepin_ui/features/municipality/municipality_dashboard.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shared projection isolates user routes and exposes all to municipality',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final shared = _SnapshotClient([_incident()]);
      final citizen = IncidentController(sharedClient: shared);
      final volunteerA = IncidentController(sharedClient: shared);
      final volunteerB = IncidentController(sharedClient: shared);
      final municipality = IncidentController(sharedClient: shared);
      addTearDown(citizen.dispose);
      addTearDown(volunteerA.dispose);
      addTearDown(volunteerB.dispose);
      addTearDown(municipality.dispose);
      await Future.wait([
        citizen.refresh(),
        volunteerA.refresh(),
        volunteerB.refresh(),
        municipality.refresh(),
      ]);

      Future<void> pumpHome(
        IncidentController controller,
        OnboardingSession session,
      ) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HomeScreen(
              hasLocation: true,
              onReport: () {},
              session: session,
              incidentController: controller,
            ),
          ),
        ),
      );

      await pumpHome(
        citizen,
        OnboardingSession()
          ..accountId = 'user-citizen'
          ..phone = '059 123 4567',
      );
      expect(find.textContaining('استجاب 2'), findsOneWidget);
      expect(_route('user-volunteer'), findsNothing);
      expect(_route('user-volunteer-2'), findsNothing);

      await pumpHome(
        volunteerA,
        OnboardingSession()
          ..accountId = 'user-volunteer'
          ..phone = '059 222 3344'
          ..role = UsageRole.volunteer,
      );
      expect(_route('user-volunteer'), findsOneWidget);
      expect(_route('user-volunteer-2'), findsNothing);

      await pumpHome(
        volunteerB,
        OnboardingSession()
          ..accountId = 'user-volunteer-2'
          ..phone = '059 333 4466'
          ..role = UsageRole.volunteer,
      );
      expect(_route('user-volunteer-2'), findsOneWidget);
      expect(_route('user-volunteer'), findsNothing);

      final operations = LocalMunicipalityRepository(incidents: municipality);
      addTearDown(operations.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MunicipalityDashboard(
              account: const MunicipalityAccount(
                id: 'municipality-jerusalem',
                name: 'بلدية القدس',
                email: 'municipality@firepin.ps',
                serviceArea: 'القدس',
                isActive: true,
              ),
              repository: operations,
              onLogout: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_municipalityMarker('user-volunteer'), findsOneWidget);
      expect(_municipalityMarker('user-volunteer-2'), findsOneWidget);
      expect(_municipalityRoute('user-volunteer'), findsOneWidget);
      expect(_municipalityRoute('user-volunteer-2'), findsOneWidget);

      shared.snapshots = [
        _incident(responders: const ['user-volunteer-2']),
      ];
      await municipality.refresh();
      await tester.pump();
      expect(_municipalityMarker('user-volunteer'), findsNothing);
      expect(_municipalityMarker('user-volunteer-2'), findsOneWidget);

      shared.snapshots = [_incident(active: false)];
      await municipality.refresh();
      await tester.pump();
      final sharedRecord = operations.incidents.singleWhere(
        (incident) => incident.id == 'demo-incident-1',
      );
      expect(sharedRecord.isResolved, isTrue);
      expect(sharedRecord.responders, isEmpty);
      expect(_municipalityMarker('user-volunteer-2'), findsNothing);
    },
  );
}

Finder _route(String volunteerId) =>
    find.byKey(ValueKey('volunteer-route-$volunteerId'));

Finder _municipalityMarker(String volunteerId) => find.byKey(
  ValueKey('municipality-responder-marker-demo-incident-1-$volunteerId'),
);

Finder _municipalityRoute(String volunteerId) => find.byKey(
  ValueKey('municipality-responder-route-demo-incident-1-$volunteerId'),
);

SharedIncidentSnapshot _incident({
  bool active = true,
  List<String> responders = const ['user-volunteer', 'user-volunteer-2'],
}) {
  final timestamp = DateTime.utc(2026, 9, 20, 12);
  final historicalResponders = active
      ? responders
      : const ['user-volunteer', 'user-volunteer-2'];
  return SharedIncidentSnapshot(
    id: 'demo-incident-1',
    stage: active ? 'responderEnRoute' : 'resolved',
    isActive: active,
    reportedAt: timestamp,
    reporterId: 'user-citizen',
    reporterName: 'أحمد محمد عبد الله',
    reporterPhone: '059 123 4567',
    reporterNationalId: '123456789',
    latitude: 31.78,
    longitude: 35.24,
    hasPhoto: false,
    events: [
      SharedIncidentEventSnapshot(
        stage: 'reported',
        at: timestamp,
        volunteerId: null,
      ),
      SharedIncidentEventSnapshot(
        stage: active ? 'responderEnRoute' : 'resolved',
        at: timestamp,
        volunteerId: 'user-volunteer-2',
      ),
    ],
    volunteerResponses: [
      for (final volunteerId in historicalResponders)
        SharedVolunteerResponseSnapshot(
          volunteerId: volunteerId,
          displayName: volunteerId == 'user-volunteer'
              ? 'ليان أحمد صالح'
              : 'عمر يوسف النجار',
          phone: volunteerId == 'user-volunteer'
              ? '059 222 3344'
              : '059 333 4466',
          state: 'responding',
          updatedAt: timestamp,
        ),
    ],
  );
}

class _SnapshotClient implements SharedMockIncidentClient {
  _SnapshotClient(this.snapshots);

  List<SharedIncidentSnapshot> snapshots;

  @override
  Future<List<SharedIncidentSnapshot>> fetchState() async => snapshots;

  @override
  Future<SharedIncidentSnapshot> createIncident({
    required String reporterId,
    required String reporterName,
    required String reporterPhone,
    required double latitude,
    required double longitude,
    String? reporterNationalId,
    bool hasPhoto = false,
  }) => throw UnsupportedError('Not used by this projection test.');

  @override
  Future<SharedIncidentSnapshot> decline({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  }) => throw UnsupportedError('Not used by this projection test.');

  @override
  Future<SharedIncidentSnapshot> resolve({
    required String incidentId,
    required String volunteerId,
  }) => throw UnsupportedError('Not used by this projection test.');

  @override
  Future<SharedIncidentSnapshot> respond({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  }) => throw UnsupportedError('Not used by this projection test.');

  @override
  Future<SharedIncidentSnapshot> withdraw({
    required String incidentId,
    required String volunteerId,
  }) => throw UnsupportedError('Not used by this projection test.');
}
