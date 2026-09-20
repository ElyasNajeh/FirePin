import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IncidentController reportedIncident() => IncidentController()
    ..report(
      location: const LocationFix(31.78, 35.24, 10),
      reporterPhone: '0591234567',
    );

  test('multiple volunteers respond independently without duplicates', () {
    final controller = reportedIncident();
    final incident = controller.incident!;

    controller.acceptByVolunteer(
      volunteerId: 'volunteer-a',
      displayName: 'المتطوع أ',
      phone: '0591111111',
    );
    expect(incident.hasResponded('volunteer-a'), isTrue);
    expect(incident.responderCount, 1);
    expect(incident.stage, IncidentStage.responderEnRoute);

    controller.acceptByVolunteer(
      volunteerId: 'volunteer-b',
      displayName: 'المتطوع ب',
      phone: '0592222222',
    );
    expect(incident.hasResponded('volunteer-b'), isTrue);
    expect(incident.responderCount, 2);

    controller.acceptByVolunteer(
      volunteerId: 'volunteer-a',
      displayName: 'اسم مكرر',
      phone: '0599999999',
    );
    expect(incident.responderCount, 2);
    expect(incident.responseFor('volunteer-a')!.phone, '0591111111');
    expect(
      incident.events
          .where(
            (event) =>
                event.stage == IncidentStage.responderEnRoute &&
                event.volunteerId != null,
          )
          .map((event) => event.volunteerId),
      ['volunteer-a', 'volunteer-b'],
    );
  });

  test('decline and withdrawal affect only the selected volunteer', () {
    final controller = reportedIncident()
      ..acceptByVolunteer(volunteerId: 'volunteer-a')
      ..acceptByVolunteer(volunteerId: 'volunteer-b')
      ..declineForVolunteer(volunteerId: 'volunteer-c');
    final incident = controller.incident!;

    expect(incident.isDeclinedFor('volunteer-c'), isTrue);
    expect(incident.hasResponded('volunteer-a'), isTrue);
    expect(incident.hasResponded('volunteer-b'), isTrue);
    expect(incident.responderCount, 2);

    controller.withdrawVolunteerResponse('volunteer-a');
    expect(incident.responseFor('volunteer-a'), isNull);
    expect(incident.hasResponded('volunteer-b'), isTrue);
    expect(incident.responderCount, 1);
    expect(incident.stage, IncidentStage.responderEnRoute);

    controller.withdrawVolunteerResponse('volunteer-b');
    expect(incident.responderCount, 0);
    expect(incident.stage, IncidentStage.waitingForResponder);
    expect(controller.hasActiveIncident, isTrue);
  });

  test('only an active responder can resolve the incident', () {
    final controller = reportedIncident()
      ..acceptByVolunteer(volunteerId: 'volunteer-a');

    controller.resolveByVolunteer('volunteer-b');
    expect(controller.incident!.isResolved, isFalse);

    controller.resolveByVolunteer('volunteer-a');
    expect(controller.incident!.stage, IncidentStage.resolved);
    expect(controller.hasActiveIncident, isFalse);
    controller.dismissResolved();
    expect(controller.incident, isNull);
  });
}
