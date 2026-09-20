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
    const limit = 100;
    var page = 1;
    var fetched = 0;
    final municipalities = <MunicipalityDirectoryEntry>[];

    while (true) {
      final response = await _api.get<Map<String, dynamic>>(
        '/municipalities',
        queryParameters: {'is_active': true, 'page': page, 'limit': limit},
      );
      final data = response.data;
      final items = data?['items'];
      final total = data?['total'];
      if (data == null || items is! List || total is! int) {
        throw const FormatException('Invalid municipality directory response');
      }

      for (final item in items) {
        final municipality = _municipalityMap(item);
        if (municipality != null) {
          municipalities.add(municipality);
        }
      }
      fetched += items.length;

      if (items.isEmpty || fetched >= total) {
        return List.unmodifiable(municipalities);
      }
      page++;
    }
  }

  MunicipalityDirectoryEntry? _municipalityMap(Object? value) {
    if (value is! Map<String, dynamic> || value['is_active'] != true) {
      return null;
    }
    final id = value['id'];
    final name = value['name'];
    final latitude = _coordinate(value['latitude']);
    final longitude = _coordinate(value['longitude']);
    if (id is! int ||
        name is! String ||
        latitude == null ||
        longitude == null) {
      throw const FormatException('Invalid municipality directory item');
    }
    return MunicipalityDirectoryEntry(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
    );
  }

  double? _coordinate(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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
    this.responders = const [],
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
  final List<VolunteerResponse> responders;
  final Uint8List? photo;

  bool get isResolved => stage == IncidentStage.resolved;
  int get responderCount => responders.length;
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
  MunicipalityOperationsRepository({
    required IncidentController incidents,
    required ApiClient api,
  }) : _incidentController = incidents,
       _api = api {
    _incidentController.addListener(_onIncidentChanged);
  }

  final IncidentController _incidentController;
  final ApiClient _api;
  List<VolunteerApplicationRecord> _applications = const [];
  List<VolunteerRecord> _volunteers = const [];
  bool _isVolunteerDataLoading = false;
  Object? _volunteerDataError;

  late final List<MunicipalityIncidentRecord> _seedIncidents = [
    MunicipalityIncidentRecord(
      id: 'FP-1042',
      stage: IncidentStage.waitingForResponder,
      reportedAt: DateTime(2026, 9, 19, 11, 42),
      reporterName: 'أحمد محمد عبد الله',
      reporterPhone: '059 123 4567',
      reporterNationalId: '123456789',
      locationLabel: 'الطور، قرب الشارع الرئيسي',
      latitude: 31.78,
      longitude: 35.24,
      municipalityName: 'بلدية القدس',
      events: [
        IncidentEvent(
          stage: IncidentStage.reported,
          at: DateTime(2026, 9, 19, 11, 42),
        ),
        IncidentEvent(
          stage: IncidentStage.waitingForResponder,
          at: DateTime(2026, 9, 19, 11, 43),
        ),
      ],
    ),
    MunicipalityIncidentRecord(
      id: 'FP-1037',
      stage: IncidentStage.resolved,
      reportedAt: DateTime(2026, 9, 18, 18, 5),
      reporterName: 'نور سمير',
      reporterPhone: '059 400 1188',
      reporterNationalId: '444555666',
      locationLabel: 'وادي الجوز، المنطقة الصناعية',
      latitude: 31.79,
      longitude: 35.23,
      municipalityName: 'بلدية القدس',
      events: [
        IncidentEvent(
          stage: IncidentStage.reported,
          at: DateTime(2026, 9, 18, 18, 5),
        ),
        IncidentEvent(
          stage: IncidentStage.responderEnRoute,
          at: DateTime(2026, 9, 18, 18, 11),
        ),
        IncidentEvent(
          stage: IncidentStage.resolved,
          at: DateTime(2026, 9, 18, 18, 34),
        ),
      ],
    ),
  ];

  @override
  List<VolunteerApplicationRecord> get applications =>
      List.unmodifiable(_applications);

  @override
  List<VolunteerRecord> get volunteers => List.unmodifiable(_volunteers);

  @override
  bool get hasSyncError =>
      _incidentController.hasSyncError || _volunteerDataError != null;

  @override
  bool get isVolunteerDataLoading => _isVolunteerDataLoading;

  @override
  Object? get volunteerDataError => _volunteerDataError;

  @override
  List<MunicipalityIncidentRecord> get incidents {
    return [
      for (final local in _incidentController.incidents)
        MunicipalityIncidentRecord(
          id: local.id,
          stage: local.stage,
          reportedAt: local.reportedAt,
          reporterName: local.reporterName ?? 'مستخدم FirePin',
          reporterPhone: local.reporterPhone,
          reporterNationalId:
              local.reporterNationalId ?? local.reporterId ?? 'غير متاح',
          locationLabel: 'موقع البلاغ المحدد على الخريطة',
          latitude: local.fireLocation.latitude,
          longitude: local.fireLocation.longitude,
          municipalityName: 'بلدية القدس',
          responders: local.isResolved
              ? const []
              : List.unmodifiable(local.responders),
          photo: local.photo,
          events: List.unmodifiable(local.events),
        ),
      ..._seedIncidents,
    ];
  }

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
    notifyListeners();
    try {
      final results = await Future.wait([
        _loadApplications(),
        _loadVolunteers(),
      ]);
      _applications = results[0] as List<VolunteerApplicationRecord>;
      _volunteers = results[1] as List<VolunteerRecord>;
    } on Object catch (error) {
      _volunteerDataError = error;
      rethrow;
    } finally {
      _isVolunteerDataLoading = false;
      notifyListeners();
    }
  }

  Future<List<VolunteerApplicationRecord>> _loadApplications() async {
    final items = await _loadAll('/municipalities/auth/volunteer-applications');
    return List.unmodifiable(items.map(_applicationFromJson));
  }

  Future<List<VolunteerRecord>> _loadVolunteers() async {
    final items = await _loadAll('/municipalities/auth/volunteers');
    return List.unmodifiable(items.map(_volunteerFromJson));
  }

  Future<List<Map<String, dynamic>>> _loadAll(String path) async {
    const limit = 100;
    var page = 1;
    var fetched = 0;
    final result = <Map<String, dynamic>>[];
    while (true) {
      final response = await _api.get<Map<String, dynamic>>(
        path,
        queryParameters: {'page': page, 'limit': limit},
        requiresAuth: true,
      );
      final data = response.data;
      final items = data?['items'];
      final total = data?['total'];
      if (items is! List || total is! int) {
        throw const FormatException('Invalid municipality volunteer response');
      }
      for (final item in items) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid municipality volunteer item');
        }
        result.add(item);
      }
      fetched += items.length;
      if (items.isEmpty || fetched >= total) return result;
      page++;
    }
  }

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
      status: _applicationStatus(json['status']),
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

  int _int(Object? value) {
    if (value is int) return value;
    throw const FormatException('Invalid backend identifier');
  }

  ApplicationStatus _applicationStatus(Object? value) => switch (value) {
    'pending' => ApplicationStatus.pending,
    'accepted' => ApplicationStatus.accepted,
    'rejected' => ApplicationStatus.rejected,
    _ => throw const FormatException('Invalid volunteer application status'),
  };

  String _displayDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return value;
    return '${parts[2]} / ${parts[1]} / ${parts[0]}';
  }

  void _onIncidentChanged() => notifyListeners();

  @override
  void dispose() {
    _incidentController.removeListener(_onIncidentChanged);
    super.dispose();
  }
}
