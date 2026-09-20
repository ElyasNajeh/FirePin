import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/municipality/municipality_dashboard.dart';
import 'package:firepin_ui/features/municipality/municipality_map_layout.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  test('mock responder map placement is stable and identity-specific', () {
    const layout = DeterministicMockResponderMapLayout();
    final first = layout.placementFor(
      incidentId: 'incident-1',
      volunteerId: 'volunteer-a',
    );
    final repeated = layout.placementFor(
      incidentId: 'incident-1',
      volunteerId: 'volunteer-a',
    );
    final second = layout.placementFor(
      incidentId: 'incident-1',
      volunteerId: 'volunteer-b',
    );

    expect(repeated.normalizedStart, first.normalizedStart);
    expect(repeated.normalizedControlBias, first.normalizedControlBias);
    expect(second.normalizedStart, isNot(first.normalizedStart));
    expect(second.normalizedControlBias, isNot(first.normalizedControlBias));
  });

  testWidgets(
    'municipality projects and maps every active responder independently',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final incidents = IncidentController()
        ..report(
          location: const LocationFix(31.78, 35.24, 10),
          reporterPhone: '0591234567',
          reporterName: 'المبلّغ',
        )
        ..acceptByVolunteer(
          volunteerId: 'volunteer-a',
          displayName: 'المتطوع أ',
          phone: '0591111111',
        )
        ..acceptByVolunteer(
          volunteerId: 'volunteer-b',
          displayName: 'المتطوع ب',
          phone: '0592222222',
        )
        ..declineForVolunteer(
          volunteerId: 'volunteer-c',
          displayName: 'المتطوع ج',
          phone: '0593333333',
        );
      final repository = FakeMunicipalityOperationsRepository(
        incidentController: incidents,
      );
      addTearDown(() {
        repository.dispose();
        incidents.dispose();
      });
      final incidentId = incidents.incident!.id;

      MunicipalityIncidentRecord localRecord() => repository.incidents.first;
      Finder marker(String volunteerId) => find.byKey(
        ValueKey('municipality-responder-marker-$incidentId-$volunteerId'),
      );
      Finder route(String volunteerId) => find.byKey(
        ValueKey('municipality-responder-route-$incidentId-$volunteerId'),
      );

      expect(localRecord().responderCount, 2);
      expect(localRecord().responders.map((response) => response.volunteerId), [
        'volunteer-a',
        'volunteer-b',
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MunicipalityDashboard(
              account: const MunicipalityAccount(
                id: 'municipality-test',
                name: 'بلدية الاختبار',
                email: 'test@municipality.ps',
                serviceArea: 'منطقة الاختبار',
                isActive: true,
              ),
              repository: repository,
              onLogout: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('2 متطوعين في الطريق'), findsOneWidget);
      expect(marker('volunteer-a'), findsOneWidget);
      expect(marker('volunteer-b'), findsOneWidget);
      expect(marker('volunteer-c'), findsNothing);
      expect(route('volunteer-a'), findsOneWidget);
      expect(route('volunteer-b'), findsOneWidget);
      expect(route('volunteer-c'), findsNothing);

      final routeA = tester.widget<CustomPaint>(route('volunteer-a'));
      final routeB = tester.widget<CustomPaint>(route('volunteer-b'));
      final painterA = routeA.painter! as MunicipalityResponderRoutePainter;
      final painterB = routeB.painter! as MunicipalityResponderRoutePainter;
      expect(painterA.start, isNot(painterB.start));
      expect(painterA.controlBias, isNot(painterB.controlBias));
      expect(painterA.end, painterB.end);
      final volunteerBStart = painterB.start;

      await tester.tap(find.text(incidentId));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('municipality-responder-detail-volunteer-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('municipality-responder-detail-volunteer-b')),
        findsOneWidget,
      );
      expect(find.text('المتطوع أ'), findsOneWidget);
      expect(find.text('المتطوع ب'), findsOneWidget);
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pump();

      incidents.withdrawVolunteerResponse('volunteer-a');
      await tester.pump();
      expect(localRecord().responderCount, 1);
      expect(marker('volunteer-a'), findsNothing);
      expect(route('volunteer-a'), findsNothing);
      expect(marker('volunteer-b'), findsOneWidget);
      expect(route('volunteer-b'), findsOneWidget);
      final remainingRoute = tester.widget<CustomPaint>(route('volunteer-b'));
      expect(
        (remainingRoute.painter! as MunicipalityResponderRoutePainter).start,
        volunteerBStart,
      );

      incidents.resolveByVolunteer('volunteer-b');
      await tester.pump();
      expect(localRecord().isResolved, isTrue);
      expect(localRecord().responderCount, 0);
      expect(marker('volunteer-b'), findsNothing);
      expect(route('volunteer-b'), findsNothing);
      expect(
        repository.incidents
            .where((incident) => !incident.isResolved)
            .any((incident) => incident.id == incidentId),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
