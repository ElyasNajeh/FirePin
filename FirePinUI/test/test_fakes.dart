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
  @override
  Future<void> submit({Uint8List? photo, required LocationFix location}) async {
    submissions++;
    hasPhoto = photo != null;
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

AppServices fakeServices({
  FakePermissions? permissions,
  FakeLocation? location,
  FakeCamera? camera,
  FakeReports? reports,
  OtpService? otp,
  SessionRepository? sessions,
}) {
  final incidents = IncidentController();
  final operations = LocalMunicipalityRepository(incidents: incidents);
  return AppServices(
    permissions: permissions ?? FakePermissions(),
    location: location ?? FakeLocation(),
    camera: () => camera ?? FakeCamera(),
    reports: reports ?? FakeReports(),
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
