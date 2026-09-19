import 'package:flutter/foundation.dart';

import '../onboarding/onboarding_models.dart';

enum IncidentStage {
  reported,
  waitingForResponder,
  responderAccepted,
  responderEnRoute,
  resolved,
}

class IncidentEvent {
  const IncidentEvent({required this.stage, required this.at});

  final IncidentStage stage;
  final DateTime at;
}

class FireIncident {
  FireIncident({
    required this.id,
    required this.stage,
    required this.reportedAt,
    required this.fireLocation,
    required this.reporterPhone,
    required this.photo,
    required this.events,
    this.reporterName,
    this.reporterNationalId,
    this.responderPhone,
    this.nearbyCitizenAcknowledged = false,
    this.volunteerDeclined = false,
  });

  final String id;
  IncidentStage stage;
  final DateTime reportedAt;
  final LocationFix fireLocation;
  final String reporterPhone;
  final String? reporterName;
  final String? reporterNationalId;
  final Uint8List? photo;
  final List<IncidentEvent> events;
  String? responderPhone;
  bool nearbyCitizenAcknowledged;
  bool volunteerDeclined;

  bool get isResolved => stage == IncidentStage.resolved;
  bool get hasResponder =>
      stage == IncidentStage.responderAccepted ||
      stage == IncidentStage.responderEnRoute;
}

/// Frontend incident boundary for the demo. A backend/realtime implementation
/// can replace this controller without changing the role-specific widgets.
class IncidentController extends ChangeNotifier {
  IncidentController({FireIncident? incident}) : _incident = incident;

  FireIncident? _incident;
  FireIncident? get incident => _incident;
  bool get hasIncident => _incident != null;
  bool get hasActiveIncident => _incident != null && !_incident!.isResolved;

  void report({
    required LocationFix location,
    required String reporterPhone,
    String? reporterName,
    String? reporterNationalId,
    Uint8List? photo,
  }) {
    final now = DateTime.now();
    _incident = FireIncident(
      id: 'local-${now.microsecondsSinceEpoch}',
      stage: IncidentStage.reported,
      reportedAt: now,
      fireLocation: location,
      reporterPhone: reporterPhone,
      reporterName: reporterName,
      reporterNationalId: reporterNationalId,
      photo: photo,
      events: [IncidentEvent(stage: IncidentStage.reported, at: now)],
    );
    _moveTo(IncidentStage.waitingForResponder);
  }

  void acceptByVolunteer({String phone = '059 123 4567'}) {
    final current = _incident;
    if (current == null || current.stage != IncidentStage.waitingForResponder) {
      return;
    }
    current.responderPhone = phone;
    current.volunteerDeclined = false;
    _moveTo(IncidentStage.responderAccepted);
    _moveTo(IncidentStage.responderEnRoute);
  }

  void acknowledgeNearbyAlert() {
    final current = _incident;
    if (current == null || current.nearbyCitizenAcknowledged) return;
    current.nearbyCitizenAcknowledged = true;
    notifyListeners();
  }

  void withdrawVolunteerResponse() {
    final current = _incident;
    if (current == null || !current.hasResponder) return;
    current.responderPhone = null;
    current.volunteerDeclined = true;
    _moveTo(IncidentStage.waitingForResponder);
  }

  void declineVolunteerRequest() {
    final current = _incident;
    if (current == null || current.stage != IncidentStage.waitingForResponder) {
      return;
    }
    current.volunteerDeclined = true;
    notifyListeners();
  }

  void resolve() {
    final current = _incident;
    if (current == null || current.isResolved) return;
    _moveTo(IncidentStage.resolved);
  }

  void dismissResolved() {
    if (_incident?.isResolved != true) return;
    _incident = null;
    notifyListeners();
  }

  void _moveTo(IncidentStage stage) {
    final current = _incident;
    if (current == null) return;
    current.stage = stage;
    current.events.add(IncidentEvent(stage: stage, at: DateTime.now()));
    notifyListeners();
  }
}
