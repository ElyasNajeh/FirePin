import 'dart:async';

import 'package:flutter/foundation.dart';

import '../onboarding/onboarding_models.dart';
import 'shared_mock_incident_client.dart';

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
    this.reporterId,
    this.reporterName,
    this.reporterNationalId,
    this.hasPhotoMetadata = false,
    this.nearbyCitizenAcknowledged = false,
  }) : volunteerResponses = volunteerResponses ?? [];

  final String id;
  IncidentStage stage;
  final DateTime reportedAt;
  final LocationFix fireLocation;
  final String reporterPhone;
  final String? reporterId;
  final String? reporterName;
  final String? reporterNationalId;
  final Uint8List? photo;
  final bool hasPhotoMetadata;
  final List<IncidentEvent> events;
  final List<VolunteerResponse> volunteerResponses;
  bool nearbyCitizenAcknowledged;

  bool get isResolved => stage == IncidentStage.resolved;
  bool get hasPhoto => photo != null || hasPhotoMetadata;
  Iterable<VolunteerResponse> get responders => isResolved
      ? const Iterable<VolunteerResponse>.empty()
      : volunteerResponses.where(
          (response) => response.state == VolunteerResponseState.responding,
        );
  int get responderCount => responders.length;
  bool get hasResponder => responderCount > 0;

  VolunteerResponse? responseFor(String volunteerId) => volunteerResponses
      .where((response) => response.volunteerId == volunteerId)
      .firstOrNull;

  bool hasResponded(String volunteerId) =>
      responders.any((response) => response.volunteerId == volunteerId);

  bool isDeclinedFor(String volunteerId) =>
      responseFor(volunteerId)?.state == VolunteerResponseState.declined;
}

/// Frontend incident boundary for the demo. A backend/realtime implementation
/// can replace this controller without changing the role-specific widgets.
class IncidentController extends ChangeNotifier {
  IncidentController({
    FireIncident? incident,
    SharedMockIncidentClient? sharedClient,
    Duration pollInterval = const Duration(seconds: 1),
  }) : _incidents = incident == null ? [] : [incident],
       _sharedClient = sharedClient,
       _pollInterval = pollInterval;

  final SharedMockIncidentClient? _sharedClient;
  final Duration _pollInterval;
  List<FireIncident> _incidents;
  final Map<String, Uint8List> _localPhotos = {};
  final Set<String> _acknowledgedIncidentIds = {};
  final Set<String> _dismissedResolvedIncidentIds = {};
  Timer? _pollTimer;
  Future<bool>? _refreshInFlight;
  bool _pollingEnabled = false;
  bool _hasSyncError = false;
  bool _disposed = false;

  List<FireIncident> get incidents => List.unmodifiable(_incidents);

  /// The existing single-incident user UI projects the newest active incident.
  /// Municipality consumers use [incidents] and retain the complete collection.
  FireIncident? get incident {
    final active = _incidents.where((item) => !item.isResolved);
    if (active.isNotEmpty) return _newest(active);
    final history = _incidents.where(
      (item) => !_dismissedResolvedIncidentIds.contains(item.id),
    );
    return history.isEmpty ? null : _newest(history);
  }

  bool get hasIncident => incident != null;
  bool get hasActiveIncident => _incidents.any((item) => !item.isResolved);
  bool get isShared => _sharedClient != null;
  bool get isPolling => _pollingEnabled;
  bool get hasSyncError => _hasSyncError;

  Future<void> startPolling() async {
    if (_sharedClient == null || _pollingEnabled || _disposed) return;
    _pollingEnabled = true;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(refresh());
    });
    await refresh();
  }

  void stopPolling() {
    _pollingEnabled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<bool> refresh() {
    if (_sharedClient == null || _disposed) return Future.value(false);
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final operation = _performRefresh();
    _refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<bool> _performRefresh() async {
    final sharedClient = _sharedClient;
    if (sharedClient == null) return false;
    try {
      final snapshots = await sharedClient.fetchState();
      if (_disposed) return false;
      _replaceFromSnapshots(snapshots);
      _hasSyncError = false;
      notifyListeners();
      return true;
    } on Object {
      _markSyncFailure();
      return false;
    }
  }

  Future<bool> report({
    required LocationFix location,
    required String reporterPhone,
    String? reporterId,
    String? reporterName,
    String? reporterNationalId,
    Uint8List? photo,
  }) async {
    final sharedClient = _sharedClient;
    if (sharedClient != null) {
      try {
        final snapshot = await sharedClient.createIncident(
          reporterId:
              reporterId ??
              reporterNationalId ??
              'phone-${normalizePhone(reporterPhone)}',
          reporterName: reporterName ?? 'FirePin user',
          reporterPhone: reporterPhone,
          reporterNationalId: reporterNationalId,
          latitude: location.latitude,
          longitude: location.longitude,
          hasPhoto: photo != null,
        );
        if (photo != null) _localPhotos[snapshot.id] = photo;
        _upsertSnapshot(snapshot);
        await _refreshAfterMutation();
        return true;
      } on Object {
        _markSyncFailure();
        return false;
      }
    }

    final now = DateTime.now();
    _incidents = [
      FireIncident(
        id: 'local-${now.microsecondsSinceEpoch}',
        stage: IncidentStage.reported,
        reportedAt: now,
        fireLocation: location,
        reporterPhone: reporterPhone,
        reporterId: reporterId,
        reporterName: reporterName,
        reporterNationalId: reporterNationalId,
        photo: photo,
        events: [IncidentEvent(stage: IncidentStage.reported, at: now)],
      ),
    ];
    _moveTo(IncidentStage.waitingForResponder);
    return true;
  }

  Future<bool> acceptByVolunteer({
    required String volunteerId,
    String? displayName,
    String? phone,
  }) async {
    final current = _incident;
    if (current == null || current.isResolved) {
      return false;
    }
    final sharedClient = _sharedClient;
    if (sharedClient != null) {
      try {
        final snapshot = await sharedClient.respond(
          incidentId: current.id,
          volunteerId: volunteerId,
          displayName: _requiredDemoValue(displayName, volunteerId),
          phone: _requiredDemoValue(phone, 'unavailable'),
        );
        _upsertSnapshot(snapshot);
        await _refreshAfterMutation();
        return true;
      } on Object {
        _markSyncFailure();
        return false;
      }
    }
    if (current.hasResponded(volunteerId)) return true;
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
    return true;
  }

  void acknowledgeNearbyAlert() {
    final current = _incident;
    if (current == null || current.nearbyCitizenAcknowledged) return;
    _acknowledgedIncidentIds.add(current.id);
    current.nearbyCitizenAcknowledged = true;
    notifyListeners();
  }

  Future<bool> withdrawVolunteerResponse(String volunteerId) async {
    final current = _incident;
    if (current == null ||
        current.isResolved ||
        !current.hasResponded(volunteerId)) {
      return false;
    }
    final sharedClient = _sharedClient;
    if (sharedClient != null) {
      try {
        final snapshot = await sharedClient.withdraw(
          incidentId: current.id,
          volunteerId: volunteerId,
        );
        _upsertSnapshot(snapshot);
        await _refreshAfterMutation();
        return true;
      } on Object {
        _markSyncFailure();
        return false;
      }
    }
    current.volunteerResponses.removeWhere(
      (response) => response.volunteerId == volunteerId,
    );
    if (current.responderCount == 0) {
      _moveTo(IncidentStage.waitingForResponder);
    } else {
      notifyListeners();
    }
    return true;
  }

  Future<bool> declineForVolunteer({
    required String volunteerId,
    String? displayName,
    String? phone,
  }) async {
    final current = _incident;
    if (current == null ||
        current.isResolved ||
        current.hasResponded(volunteerId) ||
        current.isDeclinedFor(volunteerId)) {
      return false;
    }
    final sharedClient = _sharedClient;
    if (sharedClient != null) {
      try {
        final snapshot = await sharedClient.decline(
          incidentId: current.id,
          volunteerId: volunteerId,
          displayName: _requiredDemoValue(displayName, volunteerId),
          phone: _requiredDemoValue(phone, 'unavailable'),
        );
        _upsertSnapshot(snapshot);
        await _refreshAfterMutation();
        return true;
      } on Object {
        _markSyncFailure();
        return false;
      }
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
    return true;
  }

  Future<bool> resolveByVolunteer(String volunteerId) async {
    final current = _incident;
    if (current == null ||
        current.isResolved ||
        !current.hasResponded(volunteerId)) {
      return false;
    }
    final sharedClient = _sharedClient;
    if (sharedClient != null) {
      try {
        final snapshot = await sharedClient.resolve(
          incidentId: current.id,
          volunteerId: volunteerId,
        );
        _upsertSnapshot(snapshot);
        await _refreshAfterMutation();
        return true;
      } on Object {
        _markSyncFailure();
        return false;
      }
    }
    _moveTo(IncidentStage.resolved, volunteerId: volunteerId);
    return true;
  }

  void dismissResolved() {
    final current = _incident;
    if (current?.isResolved != true) return;
    if (_sharedClient == null) {
      _incidents.removeWhere((item) => item.id == current!.id);
    } else {
      _dismissedResolvedIncidentIds.add(current!.id);
    }
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

  FireIncident? get _incident => incident;

  Future<void> _refreshAfterMutation() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) await inFlight;
    await refresh();
  }

  void _replaceFromSnapshots(List<SharedIncidentSnapshot> snapshots) {
    final ids = snapshots.map((snapshot) => snapshot.id).toSet();
    _localPhotos.removeWhere((id, _) => !ids.contains(id));
    _incidents = snapshots.map(_fromSnapshot).toList(growable: true);
  }

  void _upsertSnapshot(SharedIncidentSnapshot snapshot) {
    final incident = _fromSnapshot(snapshot);
    final index = _incidents.indexWhere((item) => item.id == snapshot.id);
    if (index < 0) {
      _incidents.add(incident);
    } else {
      _incidents[index] = incident;
    }
    _hasSyncError = false;
    if (!_disposed) notifyListeners();
  }

  FireIncident _fromSnapshot(SharedIncidentSnapshot snapshot) => FireIncident(
    id: snapshot.id,
    stage: snapshot.isActive
        ? _incidentStage(snapshot.stage)
        : IncidentStage.resolved,
    reportedAt: snapshot.reportedAt,
    fireLocation: LocationFix(snapshot.latitude, snapshot.longitude, 0),
    reporterPhone: snapshot.reporterPhone,
    reporterId: snapshot.reporterId,
    reporterName: snapshot.reporterName,
    reporterNationalId: snapshot.reporterNationalId,
    photo: _localPhotos[snapshot.id],
    hasPhotoMetadata: snapshot.hasPhoto,
    events: snapshot.events
        .map(
          (event) => IncidentEvent(
            stage: _incidentStage(event.stage),
            at: event.at,
            volunteerId: event.volunteerId,
          ),
        )
        .toList(growable: true),
    volunteerResponses: snapshot.volunteerResponses
        .map(
          (response) => VolunteerResponse(
            volunteerId: response.volunteerId,
            displayName: response.displayName,
            phone: response.phone,
            state: _volunteerResponseState(response.state),
            updatedAt: response.updatedAt,
          ),
        )
        .toList(growable: true),
    nearbyCitizenAcknowledged: _acknowledgedIncidentIds.contains(snapshot.id),
  );

  void _markSyncFailure() {
    if (_disposed || _hasSyncError) return;
    _hasSyncError = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}

FireIncident _newest(Iterable<FireIncident> incidents) => incidents.reduce(
  (current, candidate) =>
      candidate.reportedAt.isAfter(current.reportedAt) ? candidate : current,
);

IncidentStage _incidentStage(String value) => IncidentStage.values.firstWhere(
  (stage) => stage.name == value,
  orElse: () => throw FormatException('Unknown incident stage: $value'),
);

VolunteerResponseState _volunteerResponseState(String value) =>
    VolunteerResponseState.values.firstWhere(
      (state) => state.name == value,
      orElse: () =>
          throw FormatException('Unknown volunteer response state: $value'),
    );

String _requiredDemoValue(String? value, String fallback) =>
    value?.trim().isNotEmpty == true ? value!.trim() : fallback;
