import 'package:flutter/foundation.dart';

import '../incidents/incident_controller.dart';
import '../onboarding/onboarding_models.dart';

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

  final String id;
  final String userId;
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
    required this.userId,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.birthDate,
    required this.approvedAt,
  });

  final String userId;
  final String fullName;
  final String nationalId;
  final String phone;
  final String birthDate;
  final DateTime approvedAt;
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
  void acceptApplication(String id);
  void rejectApplication(String id);
  ApplicationStatus applicationStatusFor(String nationalId);
  bool hasVolunteerMembership(String nationalId);
  void submitApplication(VolunteerApplicationRecord application);
}

class LocalMunicipalityRepository extends ChangeNotifier
    implements MunicipalityRepository {
  LocalMunicipalityRepository({required IncidentController incidents})
    : _incidentController = incidents {
    _incidentController.addListener(_onIncidentChanged);
  }

  final IncidentController _incidentController;
  final List<VolunteerApplicationRecord> _applications = [
    VolunteerApplicationRecord(
      id: 'application-pending',
      userId: 'user-pending',
      fullName: 'سارة محمود خليل',
      nationalId: '111222333',
      phone: '059 765 4321',
      birthDate: '09 / 08 / 1999',
      requestedAt: DateTime(2026, 9, 18, 10, 30),
      status: ApplicationStatus.pending,
    ),
  ];
  final List<VolunteerRecord> _volunteers = [
    VolunteerRecord(
      userId: 'user-volunteer',
      fullName: 'ليان أحمد صالح',
      nationalId: '987654321',
      phone: '059 222 3344',
      birthDate: '22 / 03 / 1996',
      approvedAt: DateTime(2026, 8, 12),
    ),
    VolunteerRecord(
      userId: 'user-volunteer-2',
      fullName: 'عمر يوسف النجار',
      nationalId: '864209753',
      phone: '059 333 4466',
      birthDate: '06 / 07 / 1995',
      approvedAt: DateTime(2026, 8, 20),
    ),
  ];

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
  List<MunicipalityIncidentRecord> get incidents {
    final local = _incidentController.incident;
    return [
      if (local != null)
        MunicipalityIncidentRecord(
          id: local.id,
          stage: local.stage,
          reportedAt: local.reportedAt,
          reporterName: local.reporterName ?? 'مستخدم FirePin',
          reporterPhone: local.reporterPhone,
          reporterNationalId: local.reporterNationalId ?? 'غير متاح',
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
  void acceptApplication(String id) {
    final index = _applications.indexWhere((item) => item.id == id);
    if (index < 0 || _applications[index].status != ApplicationStatus.pending) {
      return;
    }
    final application = _applications[index];
    _applications[index] = application.copyWith(
      status: ApplicationStatus.approved,
    );
    if (!_volunteers.any((item) => item.userId == application.userId)) {
      _volunteers.add(
        VolunteerRecord(
          userId: application.userId,
          fullName: application.fullName,
          nationalId: application.nationalId,
          phone: application.phone,
          birthDate: application.birthDate,
          approvedAt: DateTime.now(),
        ),
      );
    }
    notifyListeners();
  }

  @override
  void rejectApplication(String id) {
    final index = _applications.indexWhere((item) => item.id == id);
    if (index < 0 || _applications[index].status != ApplicationStatus.pending) {
      return;
    }
    _applications[index] = _applications[index].copyWith(
      status: ApplicationStatus.rejected,
    );
    notifyListeners();
  }

  @override
  ApplicationStatus applicationStatusFor(String nationalId) =>
      _applications
          .where((item) => item.nationalId == nationalId)
          .map((item) => item.status)
          .firstOrNull ??
      (hasVolunteerMembership(nationalId)
          ? ApplicationStatus.approved
          : ApplicationStatus.none);

  @override
  bool hasVolunteerMembership(String nationalId) =>
      _volunteers.any((item) => item.nationalId == nationalId);

  @override
  void submitApplication(VolunteerApplicationRecord application) {
    _applications.removeWhere(
      (item) => item.nationalId == application.nationalId,
    );
    _applications.add(application);
    notifyListeners();
  }

  void _onIncidentChanged() => notifyListeners();

  @override
  void dispose() {
    _incidentController.removeListener(_onIncidentChanged);
    super.dispose();
  }
}
