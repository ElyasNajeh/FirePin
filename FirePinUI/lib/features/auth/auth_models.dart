import '../onboarding/onboarding_models.dart';

enum AuthPrincipal { user, municipality }

enum AuthStatus { restoring, signedOut, user, municipality }

class UserAccount {
  const UserAccount({
    required this.id,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.birthDate,
    required this.address,
    required this.applicationStatus,
    required this.hasVolunteerMembership,
  });

  final String id;
  final String fullName;
  final String nationalId;
  final String phone;
  final String birthDate;
  final String address;
  final ApplicationStatus applicationStatus;
  final bool hasVolunteerMembership;

  UsageRole get role =>
      hasVolunteerMembership ? UsageRole.volunteer : UsageRole.citizen;

  UserAccount copyWith({
    ApplicationStatus? applicationStatus,
    bool? hasVolunteerMembership,
  }) => UserAccount(
    id: id,
    fullName: fullName,
    nationalId: nationalId,
    phone: phone,
    birthDate: birthDate,
    address: address,
    applicationStatus: applicationStatus ?? this.applicationStatus,
    hasVolunteerMembership:
        hasVolunteerMembership ?? this.hasVolunteerMembership,
  );
}

class MunicipalityAccount {
  const MunicipalityAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.serviceArea,
    required this.isActive,
  });

  final String id;
  final String name;
  final String email;
  final String serviceArea;
  final bool isActive;
}

class UserLoginResult {
  const UserLoginResult({required this.account});
  final UserAccount account;
}

class MunicipalityLoginResult {
  const MunicipalityLoginResult({required this.account});
  final MunicipalityAccount account;
}

class StoredSession {
  const StoredSession({required this.principal});
  final AuthPrincipal principal;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

bool isValidNationalId(String input) =>
    RegExp(r'^[0-9]{9}$').hasMatch(normalizeDigits(input).trim());

bool isValidLoginPin(String input) =>
    RegExp(r'^[0-9]{4}$').hasMatch(normalizeDigits(input).trim());

bool isValidEmail(String input) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input.trim());
