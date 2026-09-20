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
  const IncidentEvent({
    required this.stage,
    required this.at,
    this.volunteerId,
  });

  final IncidentStage stage;
  final DateTime at;
  final String? volunteerId;
}

enum VolunteerResponseState { responding, declined }

class VolunteerResponse {
  const VolunteerResponse({
    required this.volunteerId,
    required this.state,
    required this.updatedAt,
    this.displayName,
    this.phone,
  });

  final String volunteerId;
  final VolunteerResponseState state;
  final DateTime updatedAt;
  final String? displayName;
  final String? phone;
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
    List<VolunteerResponse>? volunteerResponses,
    this.reporterName,
    this.reporterNationalId,
    this.nearbyCitizenAcknowledged = false,
  }) : volunteerResponses = volunteerResponses ?? [];

  final String id;
  IncidentStage stage;
  final DateTime reportedAt;
  final LocationFix fireLocation;
  final String reporterPhone;
  final String? reporterName;
  final String? reporterNationalId;
  final Uint8List? photo;
  final List<IncidentEvent> events;
  final List<VolunteerResponse> volunteerResponses;
  bool nearbyCitizenAcknowledged;

  bool get isResolved => stage == IncidentStage.resolved;
  Iterable<VolunteerResponse> get responders => volunteerResponses.where(
    (response) => response.state == VolunteerResponseState.responding,
  );
  int get responderCount => responders.length;
  bool get hasResponder => responderCount > 0;

  VolunteerResponse? responseFor(String volunteerId) => volunteerResponses
      .where((response) => response.volunteerId == volunteerId)
      .firstOrNull;

  bool hasResponded(String volunteerId) =>
      responseFor(volunteerId)?.state == VolunteerResponseState.responding;

  bool isDeclinedFor(String volunteerId) =>
      responseFor(volunteerId)?.state == VolunteerResponseState.declined;
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

  void acceptByVolunteer({
    required String volunteerId,
    String? displayName,
    String? phone,
  }) {
    final current = _incident;
    if (current == null || current.isResolved) {
      return;
    }
    if (current.hasResponded(volunteerId)) return;
    current.volunteerResponses.removeWhere(
      (response) => response.volunteerId == volunteerId,
    );
    current.volunteerResponses.add(
      VolunteerResponse(
        volunteerId: volunteerId,
        displayName: displayName,
        phone: phone,
        state: VolunteerResponseState.responding,
        updatedAt: DateTime.now(),
      ),
    );
    _moveTo(IncidentStage.responderAccepted, volunteerId: volunteerId);
    _moveTo(IncidentStage.responderEnRoute, volunteerId: volunteerId);
  }

  void acknowledgeNearbyAlert() {
    final current = _incident;
    if (current == null || current.nearbyCitizenAcknowledged) return;
    current.nearbyCitizenAcknowledged = true;
    notifyListeners();
  }

  void withdrawVolunteerResponse(String volunteerId) {
    final current = _incident;
    if (current == null ||
        current.isResolved ||
        !current.hasResponded(volunteerId)) {
      return;
    }
    current.volunteerResponses.removeWhere(
      (response) => response.volunteerId == volunteerId,
    );
    if (current.responderCount == 0) {
      _moveTo(IncidentStage.waitingForResponder);
    } else {
      notifyListeners();
    }
  }

  void declineForVolunteer({
    required String volunteerId,
    String? displayName,
    String? phone,
  }) {
    final current = _incident;
    if (current == null ||
        current.isResolved ||
        current.hasResponded(volunteerId) ||
        current.isDeclinedFor(volunteerId)) {
      return;
    }
    current.volunteerResponses.removeWhere(
      (response) => response.volunteerId == volunteerId,
    );
    current.volunteerResponses.add(
      VolunteerResponse(
        volunteerId: volunteerId,
        displayName: displayName,
        phone: phone,
        state: VolunteerResponseState.declined,
        updatedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void resolveByVolunteer(String volunteerId) {
    final current = _incident;
    if (current == null ||
        current.isResolved ||
        !current.hasResponded(volunteerId)) {
      return;
    }
    _moveTo(IncidentStage.resolved, volunteerId: volunteerId);
  }

  void dismissResolved() {
    if (_incident?.isResolved != true) return;
    _incident = null;
    notifyListeners();
  }

  void _moveTo(IncidentStage stage, {String? volunteerId}) {
    final current = _incident;
    if (current == null) return;
    current.stage = stage;
    current.events.add(
      IncidentEvent(stage: stage, at: DateTime.now(), volunteerId: volunteerId),
    );
    notifyListeners();
  }
}
