import '../core/services/camera_service.dart';
import '../core/services/device_services.dart';
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
  }) : identity = identity ?? const MockIdentityVerificationService(),
       otp = otp ?? MockOtpService(),
       volunteer = volunteer ?? const MockVolunteerApplicationService(),
       reports = reports ?? const MockFireReportService(),
       permissions = permissions ?? NativeDevicePermissions(),
       location = location ?? NativeLocationService(),
       camera = camera ?? NativeCameraSource.new;

  final IdentityVerificationService identity;
  final OtpService otp;
  final VolunteerApplicationService volunteer;
  final FireReportService reports;
  final DevicePermissions permissions;
  final LocationService location;
  final CameraSourceFactory camera;
}
