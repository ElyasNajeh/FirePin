import 'dart:convert';
import 'dart:typed_data';
import 'package:firepin_ui/app/app_services.dart';
import 'package:firepin_ui/core/services/camera_service.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/onboarding_services.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:flutter/material.dart';

final testPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAeSURBVDhPY5jxe8Z/SjADugCpeNSAUQNGDRgsBgAAS3MqLkKHgmcAAAAASUVORK5CYII=',
);

class FakePermissions implements DevicePermissions {
  FakePermissions({this.result = DevicePermission.granted});
  DevicePermission result;
  int requests = 0;
  int settingsOpened = 0;
  @override
  Future<DevicePermission> requestCamera() async {
    requests++;
    return result;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

class FakeLocation implements LocationService {
  LocationProblem? failure;
  int requests = 0;
  int settingsOpened = 0;
  @override
  Future<LocationFix> requestCurrentPosition() async {
    requests++;
    if (failure != null) throw LocationFailure(failure!);
    return const LocationFix(31.78, 35.24, 10);
  }

  @override
  Future<bool> openSettings({bool locationService = false}) async {
    settingsOpened++;
    return true;
  }
}

class FakeCamera implements CameraSource {
  bool opened = false;
  int captures = 0;
  @override
  Future<void> initialize() async {
    opened = true;
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF173431));
  @override
  Future<Uint8List> capture() async {
    captures++;
    return testPhoto;
  }

  @override
  Future<void> close() async {
    opened = false;
  }
}

class FakeReports implements FireReportService {
  int submissions = 0;
  bool hasPhoto = false;
  String? pin;
  @override
  Future<void> submit({
    Uint8List? photo,
    String? pin,
    required LocationFix location,
  }) async {
    submissions++;
    hasPhoto = photo != null;
    this.pin = pin;
  }
}

class TrackingOtpService implements OtpService {
  int sends = 0;
  int verifications = 0;

  @override
  Future<void> send(String phone) async {
    sends++;
  }

  @override
  Future<bool> verify(String phone, String code) async {
    verifications++;
    return true;
  }
}

class FakeVolunteerApplicationService implements VolunteerApplicationService {
  int? municipalityId;

  @override
  Future<ApplicationStatus> submit({required int municipalityId}) async {
    this.municipalityId = municipalityId;
    return ApplicationStatus.pending;
  }
}

class FakeMunicipalityDirectoryRepository
    implements MunicipalityDirectoryRepository {
  FakeMunicipalityDirectoryRepository({
    this.municipalities = const [
      MunicipalityDirectoryEntry(
        id: 101,
        name: 'بلدية القدس',
        latitude: 31.78,
        longitude: 35.24,
      ),
    ],
  });

  final List<MunicipalityDirectoryEntry> municipalities;

  @override
  Future<List<MunicipalityDirectoryEntry>> getActiveMunicipalities() async =>
      municipalities;
}

class FakeMunicipalityOperationsRepository extends ChangeNotifier
    implements MunicipalityRepository {
  FakeMunicipalityOperationsRepository({required this.incidentController}) {
    incidentController.addListener(notifyListeners);
  }

  final IncidentController incidentController;
  @override
  final List<VolunteerApplicationRecord> applications = [
    VolunteerApplicationRecord(
      id: 1,
      userId: 3,
      fullName: 'سارة محمود خليل',
      nationalId: DemoAuthRepository.pendingNationalId,
      phone: '059 765 4321',
      birthDate: '09 / 08 / 1999',
      requestedAt: DateTime(2026, 9, 18, 10, 30),
      status: ApplicationStatus.pending,
    ),
  ];
  @override
  final List<VolunteerRecord> volunteers = [
    VolunteerRecord(
      id: 1,
      userId: 1,
      fullName: 'ليان أحمد صالح',
      nationalId: DemoAuthRepository.volunteerNationalId,
      phone: '059 222 3344',
      birthDate: '22 / 03 / 1996',
      joinedAt: DateTime(2026, 8, 12),
    ),
    VolunteerRecord(
      id: 2,
      userId: 2,
      fullName: 'عمر يوسف النجار',
      nationalId: DemoAuthRepository.secondVolunteerNationalId,
      phone: '059 333 4466',
      birthDate: '06 / 07 / 1995',
      joinedAt: DateTime(2026, 8, 20),
    ),
  ];

  @override
  bool get hasSyncError => incidentController.hasSyncError;
  @override
  bool get isVolunteerDataLoading => false;
  @override
  Object? get volunteerDataError => null;
  @override
  List<MunicipalityIncidentRecord> get incidents => [
    for (final incident in incidentController.incidents)
      MunicipalityIncidentRecord(
        id: incident.id,
        stage: incident.stage,
        reportedAt: incident.reportedAt,
        reporterName: incident.reporterName ?? 'Test user',
        reporterPhone: incident.reporterPhone,
        reporterNationalId:
            incident.reporterNationalId ?? incident.reporterId ?? 'unknown',
        locationLabel: 'Test location',
        latitude: incident.fireLocation.latitude,
        longitude: incident.fireLocation.longitude,
        municipalityName: 'Test municipality',
        events: List.unmodifiable(incident.events),
        responders: List.unmodifiable(incident.responders),
        photo: incident.photo,
      ),
    MunicipalityIncidentRecord(
      id: 'FP-1042',
      stage: IncidentStage.waitingForResponder,
      reportedAt: DateTime(2026, 9, 18),
      reporterName: 'Reporter',
      reporterPhone: '0590000000',
      reporterNationalId: '100000000',
      locationLabel: 'Location',
      latitude: 31.78,
      longitude: 35.24,
      municipalityName: 'Municipality',
      events: const [],
    ),
    MunicipalityIncidentRecord(
      id: 'FP-1037',
      stage: IncidentStage.resolved,
      reportedAt: DateTime(2026, 9, 17),
      reporterName: 'Reporter',
      reporterPhone: '0590000000',
      reporterNationalId: '100000000',
      locationLabel: 'Location',
      latitude: 31.78,
      longitude: 35.24,
      municipalityName: 'Municipality',
      events: const [],
    ),
  ];

  @override
  Future<void> loadVolunteerData() async {}

  @override
  Future<void> acceptApplication(int id) async {
    final index = applications.indexWhere((item) => item.id == id);
    if (index < 0 || applications[index].status != ApplicationStatus.pending) {
      return;
    }
    final application = applications[index];
    applications[index] = application.copyWith(
      status: ApplicationStatus.accepted,
    );
    volunteers.add(
      VolunteerRecord(
        id: volunteers.length + 1,
        userId: application.userId,
        fullName: application.fullName,
        nationalId: application.nationalId,
        phone: application.phone,
        birthDate: application.birthDate,
        joinedAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> rejectApplication(int id) async {
    final index = applications.indexWhere((item) => item.id == id);
    if (index >= 0 && applications[index].status == ApplicationStatus.pending) {
      applications[index] = applications[index].copyWith(
        status: ApplicationStatus.rejected,
      );
      notifyListeners();
    }
  }

  void submitApplication(VolunteerApplicationRecord application) {
    applications.add(application);
    notifyListeners();
  }

  ApplicationStatus applicationStatusFor(String nationalId) =>
      applications
          .where((item) => item.nationalId == nationalId)
          .map((item) => item.status)
          .firstOrNull ??
      (hasVolunteerMembership(nationalId)
          ? ApplicationStatus.accepted
          : ApplicationStatus.none);

  bool hasVolunteerMembership(String nationalId) =>
      volunteers.any((item) => item.nationalId == nationalId);

  @override
  void dispose() {
    incidentController.removeListener(notifyListeners);
    super.dispose();
  }
}

AppServices fakeServices({
  FakePermissions? permissions,
  FakeLocation? location,
  FakeCamera? camera,
  FakeReports? reports,
  OtpService? otp,
  SessionRepository? sessions,
}) {
  final incidents = IncidentController();
  final operations = FakeMunicipalityOperationsRepository(
    incidentController: incidents,
  );
  return AppServices(
    permissions: permissions ?? FakePermissions(),
    location: location ?? FakeLocation(),
    camera: () => camera ?? FakeCamera(),
    reports: reports ?? FakeReports(),
    volunteer: FakeVolunteerApplicationService(),
    sessions: sessions ?? MemorySessionRepository(),
    identity: const MockIdentityVerificationService(
      delay: Duration(milliseconds: 1500),
    ),
    otp: otp ?? MockOtpService(delay: Duration.zero),
    incidents: incidents,
    operations: operations,
    municipalityDirectory: FakeMunicipalityDirectoryRepository(),
    auth: DemoAuthRepository(operations),
    municipalityAuth: DemoMunicipalityAuthRepository(),
  );
}
