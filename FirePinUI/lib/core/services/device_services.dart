import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import '../../features/onboarding/onboarding_models.dart';

enum DevicePermission { granted, denied, permanentlyDenied, restricted }

enum LocationProblem { denied, permanentlyDenied, serviceDisabled, unavailable }

class LocationFailure implements Exception {
  const LocationFailure(this.problem);
  final LocationProblem problem;
}

abstract interface class DevicePermissions {
  Future<DevicePermission> requestCamera();
  Future<bool> openAppSettings();
}

class NativeDevicePermissions implements DevicePermissions {
  @override
  Future<DevicePermission> requestCamera() async {
    final status = await permissions.Permission.camera.request();
    if (status.isGranted) return DevicePermission.granted;
    if (status.isPermanentlyDenied) return DevicePermission.permanentlyDenied;
    if (status.isRestricted) return DevicePermission.restricted;
    return DevicePermission.denied;
  }

  @override
  Future<bool> openAppSettings() => permissions.openAppSettings();
}

abstract interface class LocationService {
  Future<LocationFix> requestCurrentPosition();
  Future<bool> openSettings({bool locationService = false});
}

class NativeLocationService implements LocationService {
  @override
  Future<LocationFix> requestCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationProblem.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(LocationProblem.permanentlyDenied);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationFailure(LocationProblem.denied);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationFix(
        position.latitude,
        position.longitude,
        position.accuracy,
      );
    } catch (_) {
      throw const LocationFailure(LocationProblem.unavailable);
    }
  }

  @override
  Future<bool> openSettings({bool locationService = false}) => locationService
      ? Geolocator.openLocationSettings()
      : Geolocator.openAppSettings();
}

String locationExplanation(LocationProblem problem) => switch (problem) {
  LocationProblem.denied =>
    'لم يتم السماح بالموقع. نحتاجه لتحديد موقع البلاغ والتنبيهات القريبة.',
  LocationProblem.permanentlyDenied =>
    'إذن الموقع مغلق. يمكنك تفعيله من إعدادات التطبيق ثم المحاولة مجددًا.',
  LocationProblem.serviceDisabled =>
    'خدمة الموقع متوقفة. فعّلها من إعدادات الجهاز ثم حاول مجددًا.',
  LocationProblem.unavailable =>
    'تعذّر تحديد موقعك الآن. انتقل إلى مكان مفتوح وحاول مرة أخرى.',
};
