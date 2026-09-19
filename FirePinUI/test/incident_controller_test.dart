import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one incident lifecycle drives every role perspective', () {
    final controller = IncidentController();
    controller.report(
      location: const LocationFix(31.78, 35.24, 10),
      reporterPhone: '0591234567',
    );

    expect(controller.incident!.stage, IncidentStage.waitingForResponder);
    expect(controller.incident!.events.map((event) => event.stage), [
      IncidentStage.reported,
      IncidentStage.waitingForResponder,
    ]);

    controller.acknowledgeNearbyAlert();
    expect(controller.incident!.nearbyCitizenAcknowledged, isTrue);
    expect(controller.incident!.stage, IncidentStage.waitingForResponder);

    controller.acceptByVolunteer(phone: '0597654321');
    expect(controller.incident!.stage, IncidentStage.responderEnRoute);
    expect(controller.incident!.responderPhone, '0597654321');
    expect(
      controller.incident!.events.map((event) => event.stage),
      containsAllInOrder([
        IncidentStage.reported,
        IncidentStage.waitingForResponder,
        IncidentStage.responderAccepted,
        IncidentStage.responderEnRoute,
      ]),
    );

    controller.resolve();
    expect(controller.incident!.stage, IncidentStage.resolved);
    expect(controller.hasActiveIncident, isFalse);
    controller.dismissResolved();
    expect(controller.incident, isNull);
  });

  test('volunteer can leave a response without deleting the incident', () {
    final controller = IncidentController()
      ..report(
        location: const LocationFix(31.78, 35.24, 10),
        reporterPhone: '0591234567',
      )
      ..acceptByVolunteer();

    controller.withdrawVolunteerResponse();

    expect(controller.incident, isNotNull);
    expect(controller.incident!.stage, IncidentStage.waitingForResponder);
    expect(controller.incident!.volunteerDeclined, isTrue);
    expect(controller.incident!.responderPhone, isNull);
  });
}
