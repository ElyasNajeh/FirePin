import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../core/services/camera_service.dart';
import '../core/services/device_services.dart';
import '../core/storage/token_storage.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_repositories.dart';
import '../features/municipality/municipality_repository.dart';
import '../features/notifications/notification_service.dart';
import '../features/notifications/notification_history.dart';
import '../features/notifications/notification_api.dart';
import '../features/onboarding/onboarding_services.dart';
import '../features/report/fire_report_repository.dart';

/// Application composition root for API-backed production services.
class AppServices {
  AppServices({
    VolunteerApplicationService? volunteer,
    FireReportService? reports,
    FireReportRepository? reportRepository,
    DevicePermissions? permissions,
    LocationService? location,
    CameraSourceFactory? camera,
    MunicipalityRepository? operations,
    MunicipalityDirectoryRepository? municipalityDirectory,
    AuthRepository? auth,
    MunicipalityAuthRepository? municipalityAuth,
    SessionRepository? sessions,
    FirePinNotificationService? notifications,
    NotificationHistoryRepository? notificationHistory,
    String? apiBaseUrl,
    TokenStorage? tokenStorage,
    ApiClient? userApiClient,
    ApiClient? municipalityApiClient,
  }) {
    this.permissions = permissions ?? NativeDevicePermissions();
    this.location = location ?? NativeLocationService();
    this.camera = camera ?? NativeCameraSource.new;
    final storage = tokenStorage ?? TokenStorage();
    final baseUrl = resolveApiBaseUrl(override: apiBaseUrl);
    final userApi =
        userApiClient ?? ApiClient(baseUrl: baseUrl, tokenStorage: storage);
    final apiReports = ApiFireReportRepository(userApi);
    this.reportRepository = reportRepository ?? apiReports;
    this.reports = reports ?? this.reportRepository;
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
        operations ?? MunicipalityOperationsRepository(api: municipalityApi);
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
    this.notificationHistory =
        notificationHistory ??
        ApiNotificationHistoryRepository(userApi, municipalityApi);
    authController = AuthController(
      users: userAuth,
      municipalities: authorityAuth,
      sessions: this.sessions,
      notifications: this.notifications,
    );
  }

  late final VolunteerApplicationService volunteer;
  late final FireReportService reports;
  late final FireReportRepository reportRepository;
  late final DevicePermissions permissions;
  late final LocationService location;
  late final CameraSourceFactory camera;
  late final MunicipalityRepository operations;
  late final MunicipalityDirectoryRepository municipalityDirectory;
  late final SessionRepository sessions;
  late final FirePinNotificationService notifications;
  late final NotificationHistoryRepository notificationHistory;
  late final AuthController authController;
}
