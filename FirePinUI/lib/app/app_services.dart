import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../core/services/camera_service.dart';
import '../core/services/device_services.dart';
import '../core/storage/token_storage.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_repositories.dart';
import '../features/incidents/incident_controller.dart';
import '../features/incidents/shared_mock_incident_client.dart';
import '../features/municipality/municipality_repository.dart';
import '../features/notifications/notification_service.dart';
import '../features/notifications/notification_api.dart';
import '../features/onboarding/onboarding_services.dart';
import '../features/report/fire_report_repository.dart';

/// Application composition root. Features outside completed integration stages
/// remain mocked until their integration stages are implemented.
class AppServices {
  AppServices({
    IdentityVerificationService? identity,
    OtpService? otp,
    VolunteerApplicationService? volunteer,
    FireReportService? reports,
    FireReportRepository? reportRepository,
    DevicePermissions? permissions,
    LocationService? location,
    CameraSourceFactory? camera,
    IncidentController? incidents,
    SharedMockIncidentClient? sharedIncidents,
    Duration incidentPollInterval = const Duration(seconds: 1),
    MunicipalityRepository? operations,
    MunicipalityDirectoryRepository? municipalityDirectory,
    AuthRepository? auth,
    MunicipalityAuthRepository? municipalityAuth,
    SessionRepository? sessions,
    FirePinNotificationService? notifications,
    String? apiBaseUrl,
    TokenStorage? tokenStorage,
    ApiClient? userApiClient,
    ApiClient? municipalityApiClient,
  }) {
    this.identity = identity ?? const MockIdentityVerificationService();
    this.otp = otp ?? MockOtpService();
    this.permissions = permissions ?? NativeDevicePermissions();
    this.location = location ?? NativeLocationService();
    this.camera = camera ?? NativeCameraSource.new;
    this.incidents =
        incidents ??
        IncidentController(
          sharedClient: sharedIncidents,
          pollInterval: incidentPollInterval,
        );
    final storage = tokenStorage ?? TokenStorage();
    final baseUrl = resolveApiBaseUrl(override: apiBaseUrl);
    final userApi =
        userApiClient ?? ApiClient(baseUrl: baseUrl, tokenStorage: storage);
    final apiReports = ApiFireReportRepository(userApi);
    this.reports = reports ?? apiReports;
    this.reportRepository =
        reportRepository ??
        (this.reports is FireReportRepository
            ? this.reports as FireReportRepository
            : null);
    this.volunteer = volunteer ?? ApiVolunteerApplicationService(userApi);
    this.municipalityDirectory =
        municipalityDirectory ?? ApiMunicipalityDirectoryRepository(userApi);
    final municipalityApi =
        municipalityApiClient ??
        ApiClient(
          baseUrl: baseUrl,
          tokenStorage: storage,
          refreshPath: '/municipalities/auth/refresh',
        );
    this.operations =
        operations ??
        MunicipalityOperationsRepository(
          incidents: this.incidents,
          api: municipalityApi,
        );
    final userAuth = auth ?? ApiAuthRepository(api: userApi, storage: storage);
    final authorityAuth =
        municipalityAuth ??
        ApiMunicipalityAuthRepository(api: municipalityApi, storage: storage);
    this.sessions = sessions ?? SecureSessionRepository(storage: storage);
    this.notifications =
        notifications ??
        FirePinNotificationService(
          deviceTokenApi: NotificationDeviceTokenApi(
            userApi,
            municipalityApiClient: municipalityApi,
          ),
        );
    authController = AuthController(
      users: userAuth,
      municipalities: authorityAuth,
      sessions: this.sessions,
      notifications: this.notifications,
    );
  }

  late final IdentityVerificationService identity;
  late final OtpService otp;
  late final VolunteerApplicationService volunteer;
  late final FireReportService reports;
  late final FireReportRepository? reportRepository;
  late final DevicePermissions permissions;
  late final LocationService location;
  late final CameraSourceFactory camera;
  late final IncidentController incidents;
  late final MunicipalityRepository operations;
  late final MunicipalityDirectoryRepository municipalityDirectory;
  late final SessionRepository sessions;
  late final FirePinNotificationService notifications;
  late final AuthController authController;
}
