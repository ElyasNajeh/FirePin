import 'dart:typed_data';

enum UsageRole { citizen, volunteer }

enum AccountDestination { home, volunteerWarning, pendingApproval }

enum ApplicationStatus { none, pending, approved, rejected }

class IdentityData {
  const IdentityData({
    required this.fullName,
    required this.identityNumber,
    required this.birthDate,
    required this.gender,
    required this.address,
  });
  final String fullName;
  final String identityNumber;
  final String birthDate;
  final String gender;
  final String address;
}

class LocationFix {
  const LocationFix(this.latitude, this.longitude, this.accuracy);
  final double latitude;
  final double longitude;
  final double accuracy;
}

enum PinConfirmation { incomplete, mismatch, confirmed }

PinConfirmation confirmPin(String pin, String confirmation) {
  final fourDigits = RegExp(r'^[0-9]{4}$');
  if (!fourDigits.hasMatch(pin) || !fourDigits.hasMatch(confirmation)) {
    return PinConfirmation.incomplete;
  }
  return pin == confirmation
      ? PinConfirmation.confirmed
      : PinConfirmation.mismatch;
}

String normalizeDigits(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return input.split('').map((char) {
    final index = arabic.indexOf(char);
    if (index >= 0) return '$index';
    final other = persian.indexOf(char);
    return other >= 0 ? '$other' : char;
  }).join();
}

String normalizePhone(String input) =>
    normalizeDigits(input).replaceAll(RegExp(r'[\s()-]'), '');

bool isValidPhone(String input) {
  final phone = normalizePhone(input);
  return RegExp(r'^05[0-9]{8}$').hasMatch(phone) ||
      RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone);
}

/// Ephemeral demo session. No storage, logging, or network serialization.
class OnboardingSession {
  Uint8List? identityImage;
  IdentityData? identity;
  String phone = '';
  LocationFix? location;
  UsageRole role = UsageRole.citizen;
  ApplicationStatus applicationStatus = ApplicationStatus.none;
  String? _pin;
  bool get hasPin => _pin != null;
  String? get pinForRegistration => _pin;

  bool savePin(String pin, String confirmation) {
    if (confirmPin(pin, confirmation) != PinConfirmation.confirmed) {
      return false;
    }
    _pin = pin;
    return true;
  }

  AccountDestination get destination {
    if (role == UsageRole.citizen) {
      return AccountDestination.home;
    }

    if (applicationStatus == ApplicationStatus.approved) {
      return AccountDestination.home;
    }

    if (applicationStatus == ApplicationStatus.pending) {
      return AccountDestination.pendingApproval;
    }

    return AccountDestination.volunteerWarning;
  }

  void clearSensitiveData() {
    identityImage = null;
    identity = null;
    phone = '';
    _pin = null;
    location = null;
  }
}
