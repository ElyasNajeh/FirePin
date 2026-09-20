import '../core/services/camera_service.dart';
import '../core/services/device_services.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_repositories.dart';
import '../features/incidents/incident_controller.dart';
import '../features/incidents/shared_mock_incident_client.dart';
import '../features/municipality/municipality_repository.dart';
import '../features/onboarding/onboarding_services.dart';

/// Replace the mock implementations here when the API is ready.
class AppServices {
  AppServices({
    IdentityVerificationService? identity,
    OtpService? otp,
    VolunteerApplicationService? volunteer,
    FireReportService? reports,
    DevicePermissions? permissions,
    LocationService? location,
    CameraSourceFactory? camera,
    IncidentController? incidents,
    SharedMockIncidentClient? sharedIncidents,
    Duration incidentPollInterval = const Duration(seconds: 1),
    MunicipalityRepository? operations,
    AuthRepository? auth,
    MunicipalityAuthRepository? municipalityAuth,
    SessionRepository? sessions,
  }) {
    this.identity = identity ?? const MockIdentityVerificationService();
    this.otp = otp ?? MockOtpService();
    this.volunteer = volunteer ?? const MockVolunteerApplicationService();
    this.reports = reports ?? const MockFireReportService();
    this.permissions = permissions ?? NativeDevicePermissions();
    this.location = location ?? NativeLocationService();
    this.camera = camera ?? NativeCameraSource.new;
    this.incidents =
        incidents ??
        IncidentController(
          sharedClient: sharedIncidents ?? DioSharedMockIncidentClient(),
          pollInterval: incidentPollInterval,
        );
    this.operations =
        operations ?? LocalMunicipalityRepository(incidents: this.incidents);
    final userAuth = auth ?? DemoAuthRepository(this.operations);
    final authorityAuth = municipalityAuth ?? DemoMunicipalityAuthRepository();
    this.sessions = sessions ?? SecureSessionRepository();
    authController = AuthController(
      users: userAuth,
      municipalities: authorityAuth,
      sessions: this.sessions,
    );
  }

  late final IdentityVerificationService identity;
  late final OtpService otp;
  late final VolunteerApplicationService volunteer;
  late final FireReportService reports;
  late final DevicePermissions permissions;
  late final LocationService location;
  late final CameraSourceFactory camera;
  late final IncidentController incidents;
  late final MunicipalityRepository operations;
  late final SessionRepository sessions;
  late final AuthController authController;
}
