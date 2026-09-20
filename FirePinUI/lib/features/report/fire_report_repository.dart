import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/onboarding_services.dart';

enum FireReportStatus { pending, assigned, resolved }

class FireReportImage {
  const FireReportImage({required this.id, required this.url});

  final int id;
  final String url;
}

class FireReportMunicipality {
  const FireReportMunicipality({required this.id, required this.name});

  final int id;
  final String name;
}

class AssignedVolunteer {
  const AssignedVolunteer({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.phone,
  });

  final int id;
  final int userId;
  final String fullName;
  final String phone;
}

class FireReport {
  const FireReport({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.reportedAt,
    required this.updatedAt,
    required this.municipality,
    required this.images,
    this.assignedVolunteer,
  });

  final int id;
  final double latitude;
  final double longitude;
  final FireReportStatus status;
  final DateTime reportedAt;
  final DateTime updatedAt;
  final FireReportMunicipality municipality;
  final List<FireReportImage> images;
  final AssignedVolunteer? assignedVolunteer;
}

class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class FireReportRoute {
  const FireReportRoute({
    required this.geometry,
    required this.distanceKm,
    required this.durationSeconds,
  });

  final List<RoutePoint> geometry;
  final double distanceKm;
  final int durationSeconds;
}

abstract interface class FireReportRepository implements FireReportService {
  @override
  Future<FireReport> submit({
    required List<Uint8List> images,
    String? pin,
    required LocationFix location,
  });
  Future<List<FireReport>> getMyReports();
  Future<FireReport> getMyReport(int reportId);
  Future<List<FireReport>> getVolunteerReports();
  Future<FireReport> getVolunteerReport(int reportId);
  Future<FireReport> claimReport(int reportId);
  Future<FireReport> resolveReport(int reportId);
  Future<FireReportRoute> getVolunteerRoute(int reportId, LocationFix origin);
  Future<Uint8List> getImage(int reportId, int imageId);
}

class ApiFireReportRepository implements FireReportRepository {
  ApiFireReportRepository(this._api);

  final ApiClient _api;

  @override
  Future<FireReport> submit({
    required List<Uint8List> images,
    String? pin,
    required LocationFix location,
  }) async {
    if (images.length > 5) {
      throw ArgumentError.value(images.length, 'images', 'Maximum is 5');
    }
    final files = [
      for (final (index, image) in images.indexed)
        MultipartFile.fromBytes(
          image,
          filename: 'fire-report-${index + 1}.jpg',
        ),
    ];
    final response = await _api.post<Map<String, dynamic>>(
      '/fire-reports',
      data: FormData.fromMap({
        'latitude': location.latitude.toStringAsFixed(6),
        'longitude': location.longitude.toStringAsFixed(6),
        if (files.isNotEmpty) 'images': files,
        if (files.isEmpty && pin != null) 'pin': pin,
      }),
      requiresAuth: true,
    );
    return _report(response.data);
  }

  @override
  Future<List<FireReport>> getMyReports() => _loadAll('/fire-reports/me');

  @override
  Future<FireReport> getMyReport(int reportId) =>
      _loadOne('/fire-reports/me/$reportId');

  @override
  Future<List<FireReport>> getVolunteerReports() =>
      _loadAll('/volunteers/me/fire-reports');

  @override
  Future<FireReport> getVolunteerReport(int reportId) =>
      _loadOne('/volunteers/me/fire-reports/$reportId');

  @override
  Future<FireReport> claimReport(int reportId) =>
      _postReport('/volunteers/me/fire-reports/$reportId/claim');

  @override
  Future<FireReport> resolveReport(int reportId) =>
      _postReport('/volunteers/me/fire-reports/$reportId/resolve');

  @override
  Future<FireReportRoute> getVolunteerRoute(
    int reportId,
    LocationFix origin,
  ) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/volunteers/me/fire-reports/$reportId/route',
      data: {'latitude': origin.latitude, 'longitude': origin.longitude},
      requiresAuth: true,
    );
    final data = response.data;
    final geometry = data?['geometry'];
    if (data == null || geometry is! List) {
      throw const FormatException('Invalid fire report route response');
    }
    return FireReportRoute(
      geometry: List.unmodifiable(geometry.map(_routePoint)),
      distanceKm: _double(data['distance_km']),
      durationSeconds: _int(data['duration_seconds']),
    );
  }

  @override
  Future<Uint8List> getImage(int reportId, int imageId) => _api.getBytes(
    '/fire-reports/$reportId/images/$imageId',
    requiresAuth: true,
  );

  Future<List<FireReport>> _loadAll(String path) async {
    const limit = 100;
    var page = 1;
    var fetched = 0;
    final reports = <FireReport>[];
    while (true) {
      final response = await _api.get<Map<String, dynamic>>(
        path,
        queryParameters: {'page': page, 'limit': limit},
        requiresAuth: true,
      );
      final data = response.data;
      final items = data?['items'];
      final total = data?['total'];
      if (data == null || items is! List || total is! int) {
        throw const FormatException('Invalid fire report list response');
      }
      reports.addAll(items.map(_report));
      fetched += items.length;
      if (items.isEmpty || fetched >= total) return List.unmodifiable(reports);
      page++;
    }
  }

  Future<FireReport> _loadOne(String path) async {
    final response = await _api.get<Map<String, dynamic>>(
      path,
      requiresAuth: true,
    );
    return _report(response.data);
  }

  Future<FireReport> _postReport(String path) async {
    final response = await _api.post<Map<String, dynamic>>(
      path,
      requiresAuth: true,
    );
    return _report(response.data);
  }

  static FireReport _report(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid fire report response');
    }
    final municipality = value['municipality'];
    final images = value['images'];
    final assigned = value['assigned_volunteer'];
    if (municipality is! Map<String, dynamic> || images is! List) {
      throw const FormatException('Invalid fire report response');
    }
    return FireReport(
      id: _int(value['id']),
      latitude: _double(value['latitude']),
      longitude: _double(value['longitude']),
      status: switch (value['status']) {
        'pending' => FireReportStatus.pending,
        'assigned' => FireReportStatus.assigned,
        'resolved' => FireReportStatus.resolved,
        _ => throw const FormatException('Invalid fire report status'),
      },
      reportedAt: DateTime.parse(value['reported_at'] as String),
      updatedAt: DateTime.parse(value['updated_at'] as String),
      municipality: FireReportMunicipality(
        id: _int(municipality['id']),
        name: municipality['name'] as String,
      ),
      images: List.unmodifiable(
        images.map((image) {
          if (image is! Map<String, dynamic>) {
            throw const FormatException('Invalid report image');
          }
          return FireReportImage(
            id: _int(image['id']),
            url: image['url'] as String,
          );
        }),
      ),
      assignedVolunteer: assigned == null ? null : _assignedVolunteer(assigned),
    );
  }

  static AssignedVolunteer _assignedVolunteer(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid assigned volunteer');
    }
    final user = value['user'];
    if (user is! Map<String, dynamic>) {
      throw const FormatException('Invalid assigned volunteer user');
    }
    return AssignedVolunteer(
      id: _int(value['id']),
      userId: _int(user['id']),
      fullName: user['full_name'] as String,
      phone: user['phone'] as String,
    );
  }

  static RoutePoint _routePoint(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid route point');
    }
    return RoutePoint(
      latitude: _double(value['latitude']),
      longitude: _double(value['longitude']),
    );
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw const FormatException('Invalid backend integer');
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException('Invalid backend coordinate');
  }
}
