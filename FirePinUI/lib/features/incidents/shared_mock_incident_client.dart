import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _configuredMockBaseUrl = String.fromEnvironment('FIREPIN_MOCK_BASE_URL');

String resolveSharedMockBaseUrl({
  String? override,
  bool? web,
  TargetPlatform? platform,
}) {
  final configured = override?.trim().isNotEmpty == true
      ? override!.trim()
      : _configuredMockBaseUrl.trim();
  if (configured.isNotEmpty) return _withoutTrailingSlash(configured);
  if (web ?? kIsWeb) return 'http://127.0.0.1:8787';
  return (platform ?? defaultTargetPlatform) == TargetPlatform.android
      ? 'http://10.0.2.2:8787'
      : 'http://127.0.0.1:8787';
}

abstract interface class SharedMockIncidentClient {
  Future<List<SharedIncidentSnapshot>> fetchState();

  Future<SharedIncidentSnapshot> createIncident({
    required String reporterId,
    required String reporterName,
    required String reporterPhone,
    required double latitude,
    required double longitude,
    String? reporterNationalId,
    bool hasPhoto = false,
  });

  Future<SharedIncidentSnapshot> respond({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  });

  Future<SharedIncidentSnapshot> decline({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  });

  Future<SharedIncidentSnapshot> withdraw({
    required String incidentId,
    required String volunteerId,
  });

  Future<SharedIncidentSnapshot> resolve({
    required String incidentId,
    required String volunteerId,
  });
}

class DioSharedMockIncidentClient implements SharedMockIncidentClient {
  DioSharedMockIncidentClient({String? baseUrl, Dio? dio})
    : baseUrl = resolveSharedMockBaseUrl(override: baseUrl),
      _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: this.baseUrl,
      connectTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      headers: const {'Content-Type': 'application/json'},
    );
  }

  final String baseUrl;
  final Dio _dio;

  @override
  Future<List<SharedIncidentSnapshot>> fetchState() async {
    final response = await _dio.get<Object>('/state');
    final body = _object(response.data, 'state response');
    final incidents = body['incidents'];
    if (incidents is! List<dynamic>) {
      throw const FormatException('Shared state has no incidents list.');
    }
    return incidents
        .map(
          (incident) =>
              SharedIncidentSnapshot.fromJson(_object(incident, 'incident')),
        )
        .toList(growable: false);
  }

  @override
  Future<SharedIncidentSnapshot> createIncident({
    required String reporterId,
    required String reporterName,
    required String reporterPhone,
    required double latitude,
    required double longitude,
    String? reporterNationalId,
    bool hasPhoto = false,
  }) => _postIncident('/incidents', {
    'reporter': {
      'id': reporterId,
      'displayName': reporterName,
      'phone': reporterPhone,
      'nationalId': reporterNationalId,
    },
    'fireLocation': {'latitude': latitude, 'longitude': longitude},
    'photoMetadata': {'present': hasPhoto},
  });

  @override
  Future<SharedIncidentSnapshot> respond({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  }) => _postIncident('/incidents/$incidentId/respond', {
    'volunteerId': volunteerId,
    'displayName': displayName,
    'phone': phone,
  });

  @override
  Future<SharedIncidentSnapshot> decline({
    required String incidentId,
    required String volunteerId,
    required String displayName,
    required String phone,
  }) => _postIncident('/incidents/$incidentId/decline', {
    'volunteerId': volunteerId,
    'displayName': displayName,
    'phone': phone,
  });

  @override
  Future<SharedIncidentSnapshot> withdraw({
    required String incidentId,
    required String volunteerId,
  }) => _postIncident('/incidents/$incidentId/withdraw', {
    'volunteerId': volunteerId,
  });

  @override
  Future<SharedIncidentSnapshot> resolve({
    required String incidentId,
    required String volunteerId,
  }) => _postIncident('/incidents/$incidentId/resolve', {
    'volunteerId': volunteerId,
  });

  Future<SharedIncidentSnapshot> _postIncident(
    String path,
    Map<String, Object> body,
  ) async {
    final response = await _dio.post<Object>(path, data: body);
    final responseBody = _object(response.data, 'incident response');
    return SharedIncidentSnapshot.fromJson(
      _object(responseBody['incident'], 'incident'),
    );
  }
}

class SharedIncidentSnapshot {
  const SharedIncidentSnapshot({
    required this.id,
    required this.stage,
    required this.isActive,
    required this.reportedAt,
    required this.reporterId,
    required this.reporterName,
    required this.reporterPhone,
    required this.reporterNationalId,
    required this.latitude,
    required this.longitude,
    required this.hasPhoto,
    required this.events,
    required this.volunteerResponses,
  });

  factory SharedIncidentSnapshot.fromJson(Map<String, dynamic> json) {
    final reporter = _object(json['reporter'], 'reporter');
    final fireLocation = _object(json['fireLocation'], 'fireLocation');
    final photoMetadata = json['photoMetadata'];
    final events = json['events'];
    final responses = json['volunteerResponses'];
    if (events is! List<dynamic> || responses is! List<dynamic>) {
      throw const FormatException('Shared incident collections are invalid.');
    }
    return SharedIncidentSnapshot(
      id: _string(json['id'], 'id'),
      stage: _string(json['stage'], 'stage'),
      isActive: _boolean(json['isActive'], 'isActive'),
      reportedAt: _dateTime(json['reportedAt'], 'reportedAt'),
      reporterId: _string(reporter['id'], 'reporter.id'),
      reporterName: _string(reporter['displayName'], 'reporter.displayName'),
      reporterPhone: _string(reporter['phone'], 'reporter.phone'),
      reporterNationalId: _optionalString(reporter['nationalId']),
      latitude: _double(fireLocation['latitude'], 'fireLocation.latitude'),
      longitude: _double(fireLocation['longitude'], 'fireLocation.longitude'),
      hasPhoto:
          photoMetadata is Map<String, dynamic> &&
          photoMetadata['present'] == true,
      events: events
          .map(
            (event) =>
                SharedIncidentEventSnapshot.fromJson(_object(event, 'event')),
          )
          .toList(growable: false),
      volunteerResponses: responses
          .map(
            (response) => SharedVolunteerResponseSnapshot.fromJson(
              _object(response, 'volunteer response'),
            ),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String stage;
  final bool isActive;
  final DateTime reportedAt;
  final String reporterId;
  final String reporterName;
  final String reporterPhone;
  final String? reporterNationalId;
  final double latitude;
  final double longitude;
  final bool hasPhoto;
  final List<SharedIncidentEventSnapshot> events;
  final List<SharedVolunteerResponseSnapshot> volunteerResponses;
}

class SharedIncidentEventSnapshot {
  const SharedIncidentEventSnapshot({
    required this.stage,
    required this.at,
    required this.volunteerId,
  });

  factory SharedIncidentEventSnapshot.fromJson(Map<String, dynamic> json) =>
      SharedIncidentEventSnapshot(
        stage: _string(json['stage'], 'event.stage'),
        at: _dateTime(json['at'], 'event.at'),
        volunteerId: _optionalString(json['volunteerId']),
      );

  final String stage;
  final DateTime at;
  final String? volunteerId;
}

class SharedVolunteerResponseSnapshot {
  const SharedVolunteerResponseSnapshot({
    required this.volunteerId,
    required this.displayName,
    required this.phone,
    required this.state,
    required this.updatedAt,
  });

  factory SharedVolunteerResponseSnapshot.fromJson(Map<String, dynamic> json) =>
      SharedVolunteerResponseSnapshot(
        volunteerId: _string(json['volunteerId'], 'volunteerId'),
        displayName: _string(json['displayName'], 'displayName'),
        phone: _string(json['phone'], 'phone'),
        state: _string(json['state'], 'state'),
        updatedAt: _dateTime(json['updatedAt'], 'updatedAt'),
      );

  final String volunteerId;
  final String displayName;
  final String phone;
  final String state;
  final DateTime updatedAt;
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map<dynamic, dynamic>) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('$label is not a JSON object.');
}

String _string(Object? value, String label) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$label is not a non-empty string.');
}

String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

bool _boolean(Object? value, String label) {
  if (value is bool) return value;
  throw FormatException('$label is not a boolean.');
}

double _double(Object? value, String label) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('$label is not a finite number.');
}

DateTime _dateTime(Object? value, String label) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$label is not an ISO-8601 timestamp.');
}

String _withoutTrailingSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;
