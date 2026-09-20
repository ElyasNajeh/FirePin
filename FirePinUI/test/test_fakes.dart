import 'dart:convert';
import 'dart:typed_data';
import 'package:firepin_ui/app/app_services.dart';
import 'package:firepin_ui/core/services/camera_service.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/identity_document_processor.dart';
import 'package:firepin_ui/features/onboarding/identity_image_processor.dart';
import 'package:firepin_ui/features/onboarding/onboarding_services.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/report/fire_report_repository.dart';
import 'package:flutter/material.dart';

final testPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAeSURBVDhPY5jxe8Z/SjADugCpeNSAUQNGDRgsBgAAS3MqLkKHgmcAAAAASUVORK5CYII=',
);

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository([MunicipalityRepository? _]);

  static const citizenNationalId = '123456789';
  static const citizenPin = '1234';
  static const secondCitizenNationalId = '246813579';
  static const secondCitizenPin = '2468';
  static const volunteerNationalId = '987654321';
  static const volunteerPin = '4321';
  static const secondVolunteerNationalId = '864209753';
  static const secondVolunteerPin = '5678';
  static const pendingNationalId = '111222333';
  static const pendingPin = '1234';

  String? _activeNationalId;
  OnboardingSession? _activeRegistration;
  final Map<String, String> _pins = {
    citizenNationalId: citizenPin,
    secondCitizenNationalId: secondCitizenPin,
    volunteerNationalId: volunteerPin,
    secondVolunteerNationalId: secondVolunteerPin,
    pendingNationalId: pendingPin,
  };
  final Map<String, UserAccount> _accounts = {
    citizenNationalId: const UserAccount(
      id: 'user-citizen',
      fullName: 'أحمد محمد عبد الله',
      nationalId: citizenNationalId,
      phone: '059 123 4567',
      birthDate: '14 / 05 / 1998',
      address: 'القدس — الطور',
      applicationStatus: ApplicationStatus.none,
      hasVolunteerMembership: false,
    ),
    secondCitizenNationalId: const UserAccount(
      id: 'user-citizen-2',
      fullName: 'ريم سامر حمدان',
      nationalId: secondCitizenNationalId,
      phone: '059 333 4455',
      birthDate: '17 / 11 / 2001',
      address: 'القدس — بيت حنينا',
      applicationStatus: ApplicationStatus.none,
      hasVolunteerMembership: false,
    ),
    volunteerNationalId: const UserAccount(
      id: 'user-volunteer',
      fullName: 'ليان أحمد صالح',
      nationalId: volunteerNationalId,
      phone: '059 222 3344',
      birthDate: '22 / 03 / 1996',
      address: 'القدس — وادي الجوز',
      applicationStatus: ApplicationStatus.accepted,
      hasVolunteerMembership: true,
    ),
    secondVolunteerNationalId: const UserAccount(
      id: 'user-volunteer-2',
      fullName: 'عمر يوسف النجار',
      nationalId: secondVolunteerNationalId,
      phone: '059 333 4466',
      birthDate: '06 / 07 / 1995',
      address: 'القدس — شعفاط',
      applicationStatus: ApplicationStatus.accepted,
      hasVolunteerMembership: true,
    ),
    pendingNationalId: const UserAccount(
      id: 'user-pending',
      fullName: 'سارة محمود خليل',
      nationalId: pendingNationalId,
      phone: '059 765 4321',
      birthDate: '09 / 08 / 1999',
      address: 'القدس — الصوانة',
      applicationStatus: ApplicationStatus.pending,
      hasVolunteerMembership: false,
    ),
  };

  @override
  Future<UserLoginResult> loginUser({
    required String nationalId,
    required String pin,
  }) async {
    final id = normalizeDigits(nationalId).trim();
    if (_pins[id] != normalizeDigits(pin).trim()) {
      throw const AuthFailure('بيانات الدخول غير صحيحة.');
    }
    _activeNationalId = id;
    return UserLoginResult(account: _accounts[id]!);
  }

  @override
  Future<UserAccount> restoreUser() async {
    final account = _accounts[_activeNationalId ?? citizenNationalId];
    if (account == null) throw const AuthFailure('انتهت الجلسة.');
    final registration = _activeRegistration;
    return registration == null
        ? account
        : account.copyWith(
            applicationStatus: registration.applicationStatus,
            hasVolunteerMembership:
                registration.applicationStatus == ApplicationStatus.accepted,
          );
  }

  @override
  Future<UserLoginResult> registerUser(OnboardingSession session) async {
    final identity = session.identity;
    final pin = session.pinForRegistration;
    if (identity == null || pin == null) {
      throw const AuthFailure('بيانات التسجيل غير مكتملة.');
    }
    final account = UserAccount(
      id: 'test-${identity.identityNumber}',
      fullName: identity.fullName,
      nationalId: identity.identityNumber,
      phone: session.phone,
      birthDate: identity.birthDate,
      address: identity.address,
      applicationStatus: session.applicationStatus,
      hasVolunteerMembership:
          session.applicationStatus == ApplicationStatus.accepted,
    );
    _accounts[account.nationalId] = account;
    _pins[account.nationalId] = pin;
    _activeNationalId = account.nationalId;
    _activeRegistration = session;
    return UserLoginResult(account: account);
  }

  @override
  Future<bool> verifyUserPin({
    required String userId,
    required String pin,
  }) async {
    final account = _accounts.values
        .where((item) => item.id == userId)
        .firstOrNull;
    return account != null &&
        _pins[account.nationalId] == normalizeDigits(pin).trim();
  }

  @override
  Future<void> clearLocalSession() async {
    _activeNationalId = null;
    _activeRegistration = null;
  }

  @override
  Future<void> logoutUser() => clearLocalSession();
}

class DemoMunicipalityAuthRepository implements MunicipalityAuthRepository {
  static const demoEmail = 'municipality@firepin.ps';
  static const demoPassword = 'firepin-test';
  static const account = MunicipalityAccount(
    id: 'municipality-101',
    name: 'بلدية القدس',
    email: demoEmail,
    serviceArea: '',
    isActive: true,
  );

  @override
  Future<MunicipalityLoginResult> login({
    required String email,
    required String password,
  }) async {
    if (email.trim().toLowerCase() != demoEmail || password != demoPassword) {
      throw const AuthFailure('بيانات الدخول غير صحيحة.');
    }
    return const MunicipalityLoginResult(account: account);
  }

  @override
  Future<MunicipalityAccount> restore() async => account;
  @override
  Future<void> clearLocalSession() async {}
  @override
  Future<void> logout() async {}
}

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

class FakeIdentityDocumentProcessor implements IdentityDocumentProcessor {
  FakeIdentityDocumentProcessor({
    this.result = const IdentityData(
      fullName: 'أحمد محمد عبد الله',
      identityNumber: '123456789',
      birthDate: '14 / 05 / 1998',
      address: '',
    ),
    this.failure,
    this.failuresRemaining,
  });

  final IdentityData result;
  final IdentityScanFailure? failure;
  int? failuresRemaining;
  int calls = 0;
  Uint8List? receivedImage;
  IdentityCaptureRegion? receivedRegion;

  @override
  Future<IdentityData> extract(
    Uint8List imageBytes, {
    IdentityCaptureRegion? region,
  }) async {
    calls++;
    receivedImage = Uint8List.fromList(imageBytes);
    receivedRegion = region;
    if (failure != null &&
        (failuresRemaining == null || failuresRemaining! > 0)) {
      if (failuresRemaining != null) failuresRemaining = failuresRemaining! - 1;
      throw failure!;
    }
    return result;
  }
}

class FakeReports implements FireReportRepository {
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

  static final report = FireReport(
    id: 91,
    latitude: 31.78,
    longitude: 35.24,
    status: FireReportStatus.pending,
    reportedAt: DateTime(2026, 9, 18),
    updatedAt: DateTime(2026, 9, 18),
    municipality: const FireReportMunicipality(id: 101, name: 'بلدية القدس'),
    images: const [],
  );

  @override
  Future<FireReport> claimReport(int reportId) async => report;
  @override
  Future<FireReport> getMyReport(int reportId) async => report;
  @override
  Future<List<FireReport>> getMyReports() async => [report];
  @override
  Future<FireReport> getVolunteerReport(int reportId) async => report;
  @override
  Future<List<FireReport>> getVolunteerReports() async => [report];
  @override
  Future<FireReportRoute> getVolunteerRoute(
    int reportId,
    LocationFix origin,
  ) async => FireReportRoute(
    geometry: [
      RoutePoint(latitude: origin.latitude, longitude: origin.longitude),
      const RoutePoint(latitude: 31.78, longitude: 35.24),
    ],
    distanceKm: 1,
    durationSeconds: 60,
  );
  @override
  Future<Uint8List> getImage(int reportId, int imageId) async => testPhoto;
  @override
  Future<FireReport> resolveReport(int reportId) async => report;
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
  FakeMunicipalityOperationsRepository();
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
  bool get hasSyncError => false;
  @override
  bool get isVolunteerDataLoading => false;
  @override
  Object? get volunteerDataError => null;
  @override
  List<MunicipalityFireReport> get reports => [
    MunicipalityFireReport(
      id: 1042,
      status: FireReportStatus.pending,
      reportedAt: DateTime(2026, 9, 18),
      reporterName: 'Reporter',
      reporterPhone: '0590000000',
      reporterNationalId: '100000000',
      locationLabel: 'Location',
      latitude: 31.78,
      longitude: 35.24,
      municipalityName: 'Municipality',
    ),
    MunicipalityFireReport(
      id: 1037,
      status: FireReportStatus.resolved,
      reportedAt: DateTime(2026, 9, 17),
      reporterName: 'Reporter',
      reporterPhone: '0590000000',
      reporterNationalId: '100000000',
      locationLabel: 'Location',
      latitude: 31.78,
      longitude: 35.24,
      municipalityName: 'Municipality',
    ),
  ];

  @override
  Future<void> loadVolunteerData() async {}

  @override
  Future<MunicipalityFireReport> getReport(int reportId) async =>
      reports.where((report) => report.id == reportId).first;

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
}

AppServices fakeServices({
  FakePermissions? permissions,
  FakeLocation? location,
  FakeCamera? camera,
  FakeReports? reports,
  FakeIdentityDocumentProcessor? identityProcessor,
  SessionRepository? sessions,
}) {
  final operations = FakeMunicipalityOperationsRepository();
  final fakeReports = reports ?? FakeReports();
  return AppServices(
    permissions: permissions ?? FakePermissions(),
    location: location ?? FakeLocation(),
    camera: () => camera ?? FakeCamera(),
    identityProcessor: identityProcessor ?? FakeIdentityDocumentProcessor(),
    reports: fakeReports,
    reportRepository: fakeReports,
    volunteer: FakeVolunteerApplicationService(),
    sessions: sessions ?? MemorySessionRepository(),
    operations: operations,
    municipalityDirectory: FakeMunicipalityDirectoryRepository(),
    auth: DemoAuthRepository(operations),
    municipalityAuth: DemoMunicipalityAuthRepository(),
  );
}
