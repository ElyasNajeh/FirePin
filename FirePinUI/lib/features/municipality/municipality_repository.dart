import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../incidents/incident_controller.dart';
import '../onboarding/onboarding_models.dart';

class MunicipalityDirectoryEntry {
  const MunicipalityDirectoryEntry({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
  final int id;
  final String name;
  final double latitude;
  final double longitude;
}

abstract interface class MunicipalityDirectoryRepository {
  Future<List<MunicipalityDirectoryEntry>> getActiveMunicipalities();
}

class ApiMunicipalityDirectoryRepository
    implements MunicipalityDirectoryRepository {
  ApiMunicipalityDirectoryRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<MunicipalityDirectoryEntry>> getActiveMunicipalities() async {
    final items = await _loadAllPages(
      _api,
      '/municipalities',
      query: {'is_active': true},
      requiresAuth: false,
    );
    return List.unmodifiable(
      items.where((item) => item['is_active'] == true).map((item) {
        return MunicipalityDirectoryEntry(
          id: _int(item['id']),
          name: item['name'] as String,
          latitude: _double(item['latitude']),
          longitude: _double(item['longitude']),
        );
      }),
    );
  }
}

class VolunteerApplicationRecord {
  const VolunteerApplicationRecord({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.birthDate,
    required this.requestedAt,
    required this.status,
  });
  final int id;
  final int userId;
  final String fullName;
  final String nationalId;
  final String phone;
  final String birthDate;
  final DateTime requestedAt;
  final ApplicationStatus status;

  VolunteerApplicationRecord copyWith({ApplicationStatus? status}) =>
      VolunteerApplicationRecord(
        id: id,
        userId: userId,
        fullName: fullName,
        nationalId: nationalId,
        phone: phone,
        birthDate: birthDate,
        requestedAt: requestedAt,
        status: status ?? this.status,
      );
}

class VolunteerRecord {
  const VolunteerRecord({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.birthDate,
    required this.joinedAt,
  });
  final int id;
  final int userId;
  final String fullName;
  final String nationalId;
  final String phone;
  final String birthDate;
  final DateTime joinedAt;
}

class MunicipalityIncidentRecord {
  const MunicipalityIncidentRecord({
    required this.id,
    required this.stage,
    required this.reportedAt,
    required this.reporterName,
    required this.reporterPhone,
    required this.reporterNationalId,
    required this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.municipalityName,
    required this.events,
    this.assignedVolunteer,
    this.photo,
  });
  final String id;
  final IncidentStage stage;
  final DateTime reportedAt;
  final String reporterName;
  final String reporterPhone;
  final String reporterNationalId;
  final String locationLabel;
  final double latitude;
  final double longitude;
  final String municipalityName;
  final List<IncidentEvent> events;
  final VolunteerResponse? assignedVolunteer;
  final Uint8List? photo;
  bool get isResolved => stage == IncidentStage.resolved;
}

abstract interface class MunicipalityRepository implements Listenable {
  List<VolunteerApplicationRecord> get applications;
  List<VolunteerRecord> get volunteers;
  List<MunicipalityIncidentRecord> get incidents;
  bool get hasSyncError;
  bool get isVolunteerDataLoading;
  Object? get volunteerDataError;
  Future<void> loadVolunteerData();
  Future<void> acceptApplication(int id);
  Future<void> rejectApplication(int id);
}

class MunicipalityOperationsRepository extends ChangeNotifier
    implements MunicipalityRepository {
  MunicipalityOperationsRepository({required ApiClient api}) : _api = api;
  final ApiClient _api;
  List<VolunteerApplicationRecord> _applications = const [];
  List<VolunteerRecord> _volunteers = const [];
  List<MunicipalityIncidentRecord> _incidents = const [];
  bool _isVolunteerDataLoading = false;
  Object? _volunteerDataError;

  @override
  List<VolunteerApplicationRecord> get applications =>
      List.unmodifiable(_applications);
  @override
  List<VolunteerRecord> get volunteers => List.unmodifiable(_volunteers);
  @override
  List<MunicipalityIncidentRecord> get incidents =>
      List.unmodifiable(_incidents);
  @override
  bool get hasSyncError => _volunteerDataError != null;
  @override
  bool get isVolunteerDataLoading => _isVolunteerDataLoading;
  @override
  Object? get volunteerDataError => _volunteerDataError;

  @override
  Future<void> acceptApplication(int id) async {
    await _api.post<Map<String, dynamic>>(
      '/municipalities/auth/volunteer-applications/$id/accept',
      requiresAuth: true,
    );
    await loadVolunteerData();
  }

  @override
  Future<void> rejectApplication(int id) async {
    await _api.post<Map<String, dynamic>>(
      '/municipalities/auth/volunteer-applications/$id/reject',
      requiresAuth: true,
    );
    await loadVolunteerData();
  }

  @override
  Future<void> loadVolunteerData() async {
    if (_isVolunteerDataLoading) return;
    _isVolunteerDataLoading = true;
    _volunteerDataError = null;
    _applications = const [];
    _volunteers = const [];
    _incidents = const [];
    notifyListeners();
    try {
      final results = await Future.wait([
        _loadApplications(),
        _loadVolunteers(),
        _loadReports(),
      ]);
      _applications = results[0] as List<VolunteerApplicationRecord>;
      _volunteers = results[1] as List<VolunteerRecord>;
      _incidents = results[2] as List<MunicipalityIncidentRecord>;
    } on Object catch (error) {
      _volunteerDataError = error;
      rethrow;
    } finally {
      _isVolunteerDataLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> _loadAll(String path) =>
      _loadAllPages(_api, path, requiresAuth: true);
  Future<List<VolunteerApplicationRecord>> _loadApplications() async =>
      List.unmodifiable(
        (await _loadAll(
          '/municipalities/auth/volunteer-applications',
        )).map(_applicationFromJson),
      );
  Future<List<VolunteerRecord>> _loadVolunteers() async => List.unmodifiable(
    (await _loadAll('/municipalities/auth/volunteers')).map(_volunteerFromJson),
  );
  Future<List<MunicipalityIncidentRecord>> _loadReports() async =>
      List.unmodifiable(
        (await _loadAll(
          '/municipalities/auth/fire-reports',
        )).map(_reportFromJson),
      );

  VolunteerApplicationRecord _applicationFromJson(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is! Map<String, dynamic>) {
      throw const FormatException('Invalid volunteer applicant');
    }
    return VolunteerApplicationRecord(
      id: _int(json['id']),
      userId: _int(user['id']),
      fullName: user['full_name'] as String,
      nationalId: user['national_id'] as String,
      phone: user['phone'] as String,
      birthDate: _displayDate(user['birth_date'] as String),
      requestedAt: DateTime.parse(json['created_at'] as String),
      status: switch (json['status']) {
        'pending' => ApplicationStatus.pending,
        'accepted' => ApplicationStatus.accepted,
        'rejected' => ApplicationStatus.rejected,
        _ => throw const FormatException(
          'Invalid volunteer application status',
        ),
      },
    );
  }

  VolunteerRecord _volunteerFromJson(Map<String, dynamic> json) =>
      VolunteerRecord(
        id: _int(json['id']),
        userId: _int(json['user_id']),
        fullName: json['full_name'] as String,
        nationalId: json['national_id'] as String,
        phone: json['phone'] as String,
        birthDate: _displayDate(json['birth_date'] as String),
        joinedAt: DateTime.parse(json['created_at'] as String),
      );

  MunicipalityIncidentRecord _reportFromJson(Map<String, dynamic> json) {
    final reporter = json['reporter'];
    final municipality = json['municipality'];
    if (reporter is! Map<String, dynamic> ||
        municipality is! Map<String, dynamic>) {
      throw const FormatException('Invalid municipality fire report');
    }
    final reportedAt = DateTime.parse(json['reported_at'] as String);
    final updatedAt = DateTime.parse(json['updated_at'] as String);
    final stage = switch (json['status']) {
      'pending' => IncidentStage.waitingForResponder,
      'assigned' => IncidentStage.responderAccepted,
      'resolved' => IncidentStage.resolved,
      _ => throw const FormatException('Invalid fire report status'),
    };
    VolunteerResponse? assignedVolunteer;
    final assigned = json['assigned_volunteer'];
    if (assigned is Map<String, dynamic>) {
      final user = assigned['user'];
      if (user is! Map<String, dynamic>) {
        throw const FormatException('Invalid assigned volunteer');
      }
      assignedVolunteer = VolunteerResponse(
        volunteerId: _int(assigned['id']).toString(),
        state: VolunteerResponseState.responding,
        updatedAt: updatedAt,
        displayName: user['full_name'] as String,
        phone: user['phone'] as String,
      );
    }
    return MunicipalityIncidentRecord(
      id: '#${_int(json['id'])}',
      stage: stage,
      reportedAt: reportedAt,
      reporterName: reporter['full_name'] as String,
      reporterPhone: reporter['phone'] as String,
      reporterNationalId: reporter['national_id'] as String,
      locationLabel: '${json['latitude']}, ${json['longitude']}',
      latitude: _double(json['latitude']),
      longitude: _double(json['longitude']),
      municipalityName: municipality['name'] as String,
      assignedVolunteer: assignedVolunteer,
      events: [
        IncidentEvent(stage: IncidentStage.reported, at: reportedAt),
        if (stage != IncidentStage.waitingForResponder)
          IncidentEvent(stage: IncidentStage.responderAccepted, at: updatedAt),
        if (stage == IncidentStage.resolved)
          IncidentEvent(stage: IncidentStage.resolved, at: updatedAt),
      ],
    );
  }
}

Future<List<Map<String, dynamic>>> _loadAllPages(
  ApiClient api,
  String path, {
  Map<String, dynamic> query = const {},
  required bool requiresAuth,
}) async {
  const limit = 100;
  var page = 1;
  var fetched = 0;
  final result = <Map<String, dynamic>>[];
  while (true) {
    final response = await api.get<Map<String, dynamic>>(
      path,
      queryParameters: {...query, 'page': page, 'limit': limit},
      requiresAuth: requiresAuth,
    );
    final items = response.data?['items'];
    final total = response.data?['total'];
    if (items is! List || total is! int) {
      throw const FormatException('Invalid paginated response');
    }
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid paginated item');
      }
      result.add(item);
    }
    fetched += items.length;
    if (items.isEmpty || fetched >= total) return result;
    page++;
  }
}

int _int(Object? value) {
  if (value is int) return value;
  throw const FormatException('Invalid backend identifier');
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const FormatException('Invalid backend coordinate');
}

String _displayDate(String value) {
  final parts = value.split('-');
  return parts.length == 3 ? '${parts[2]} / ${parts[1]} / ${parts[0]}' : value;
}
