import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/municipality/municipality_dashboard.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  testWidgets(
    'municipality shows every active responder without drawing a fake route',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final incidents = IncidentController()
        ..report(
          location: const LocationFix(31.78, 35.24, 10),
          reporterPhone: '0591234567',
          reporterName: 'Reporter',
        )
        ..acceptByVolunteer(
          volunteerId: 'volunteer-a',
          displayName: 'Volunteer A',
          phone: '0591111111',
        )
        ..acceptByVolunteer(
          volunteerId: 'volunteer-b',
          displayName: 'Volunteer B',
          phone: '0592222222',
        );
      final repository = FakeMunicipalityOperationsRepository(
        incidentController: incidents,
      );
      addTearDown(() {
        repository.dispose();
        incidents.dispose();
      });
      final incidentId = incidents.incident!.id;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MunicipalityDashboard(
              account: const MunicipalityAccount(
                id: 'municipality-test',
                name: 'Test municipality',
                email: 'test@municipality.ps',
                serviceArea: '',
                isActive: true,
              ),
              repository: repository,
              onLogout: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(
          ValueKey('municipality-responder-route-$incidentId-volunteer-a'),
        ),
        findsNothing,
      );
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
      expect(tester.takeException(), isNull);
    },
  );
}
