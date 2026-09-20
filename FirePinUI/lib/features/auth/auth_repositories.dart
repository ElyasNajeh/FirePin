import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../municipality/municipality_repository.dart';
import '../onboarding/onboarding_models.dart';
import 'auth_models.dart';

abstract interface class SessionRepository {
  Future<StoredSession?> read();
  Future<void> save(StoredSession session);
  Future<void> clear();
}

class SecureSessionRepository implements SessionRepository {
  SecureSessionRepository({TokenStorage? storage})
    : _storage = storage ?? TokenStorage();

  final TokenStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.readSession();
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return StoredSession(
        principal: AuthPrincipal.values.byName(json['principal'] as String),
      );
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(StoredSession session) =>
      _storage.saveSession(jsonEncode({'principal': session.principal.name}));

  @override
  Future<void> clear() => _storage.deleteSession();
}

class MemorySessionRepository implements SessionRepository {
  StoredSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredSession?> read() async => value;

  @override
  Future<void> save(StoredSession session) async => value = session;
}

abstract interface class AuthRepository {
  Future<UserLoginResult> loginUser({
    required String nationalId,
    required String pin,
  });
  Future<UserAccount> restoreUser();
  Future<UserLoginResult> registerUser(OnboardingSession session);
  Future<bool> verifyUserPin({required String userId, required String pin});
  Future<void> logoutUser();
  Future<void> clearLocalSession();
}

abstract interface class MunicipalityAuthRepository {
  Future<MunicipalityLoginResult> login({
    required String email,
    required String password,
  });
  Future<MunicipalityAccount> restore();
  Future<void> logout();
  Future<void> clearLocalSession();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({required ApiClient api, required TokenStorage storage})
    : _api = api,
      _storage = storage;

  final ApiClient _api;
  final TokenStorage _storage;
  String? _currentPin;

  @override
  Future<UserLoginResult> loginUser({
    required String nationalId,
    required String pin,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'national_id': normalizeDigits(nationalId).trim(),
          'pin': normalizeDigits(pin).trim(),
        },
      );
      final tokens = _tokens(response.data);
      await _api.setSession(accessToken: tokens.$1, refreshToken: tokens.$2);
      _currentPin = normalizeDigits(pin).trim();
      return UserLoginResult(account: await _loadAccount());
    } on Object catch (error) {
      await clearLocalSession();
      throw _authFailure(error);
    }
  }

  @override
  Future<UserAccount> restoreUser() async {
    try {
      final accessToken = await _api.refreshAccessToken();
      if (accessToken == null) {
        throw const AuthenticationException('Session has expired');
      }
      return await _loadAccount();
    } on Object catch (error) {
      await clearLocalSession();
      throw _authFailure(error);
    }
  }

  @override
  Future<UserLoginResult> registerUser(OnboardingSession session) async {
    final identity = session.identity;
    final pin = session.pinForRegistration;
    if (identity == null || pin == null) {
      throw const AuthFailure('تعذّر إكمال إنشاء الحساب.');
    }

    try {
      await _api.post<Map<String, dynamic>>(
        '/users/register',
        data: {
          'full_name': identity.fullName,
          'phone': normalizePhone(session.phone),
          'national_id': normalizeDigits(identity.identityNumber).trim(),
          'birth_date': _apiDate(identity.birthDate),
          'pin': normalizeDigits(pin).trim(),
        },
      );
    } on Object catch (error) {
      throw _authFailure(error);
    }

    return loginUser(nationalId: identity.identityNumber, pin: pin);
  }

  Future<UserAccount> _loadAccount() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/auth/me',
      requiresAuth: true,
    );
    final profile = _map(response.data, 'user profile');
    var applicationStatus = ApplicationStatus.none;
    var hasVolunteerMembership = false;

    try {
      await _api.get<Map<String, dynamic>>(
        '/volunteers/me',
        requiresAuth: true,
      );
      hasVolunteerMembership = true;
      applicationStatus = ApplicationStatus.accepted;
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final applications = await _api.get<Map<String, dynamic>>(
        '/volunteer-applications/me',
        queryParameters: {'page': 1, 'limit': 1},
        requiresAuth: true,
      );
      final items = _map(applications.data, 'volunteer applications')['items'];
      if (items is List && items.isNotEmpty) {
        final latest = _map(items.first, 'volunteer application');
        applicationStatus = _applicationStatus(latest['status']);
      }
    }

    return UserAccount(
      id: profile['id'].toString(),
      fullName: profile['full_name'] as String,
      nationalId: profile['national_id'] as String,
      phone: profile['phone'] as String,
      birthDate: _displayDate(profile['birth_date'] as String),
      address: 'غير متاح',
      applicationStatus: applicationStatus,
      hasVolunteerMembership: hasVolunteerMembership,
    );
  }

  @override
  Future<bool> verifyUserPin({
    required String userId,
    required String pin,
  }) async => _currentPin != null && _currentPin == normalizeDigits(pin).trim();

  @override
  Future<void> logoutUser() async {
    final refreshToken = await _storage.readRefreshToken();
    try {
      if (refreshToken != null) {
        await _api.post<Map<String, dynamic>>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } finally {
      await clearLocalSession();
    }
  }

  @override
  Future<void> clearLocalSession() async {
    _currentPin = null;
    await _api.clearSession();
  }
}

class ApiMunicipalityAuthRepository implements MunicipalityAuthRepository {
  ApiMunicipalityAuthRepository({
    required ApiClient api,
    required TokenStorage storage,
  }) : _api = api,
       _storage = storage;

  final ApiClient _api;
  final TokenStorage _storage;

  @override
  Future<MunicipalityLoginResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '/municipalities/auth/login',
        data: {'email': email.trim().toLowerCase(), 'password': password},
      );
      final tokens = _tokens(response.data);
      await _api.setSession(accessToken: tokens.$1, refreshToken: tokens.$2);
      return MunicipalityLoginResult(account: await _loadAccount());
    } on Object catch (error) {
      await clearLocalSession();
      throw _authFailure(error);
    }
  }

  @override
  Future<MunicipalityAccount> restore() async {
    try {
      final accessToken = await _api.refreshAccessToken();
      if (accessToken == null) {
        throw const AuthenticationException('Session has expired');
      }
      return await _loadAccount();
    } on Object catch (error) {
      await clearLocalSession();
      throw _authFailure(error);
    }
  }

  Future<MunicipalityAccount> _loadAccount() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/municipalities/auth/me',
      requiresAuth: true,
    );
    final profile = _map(response.data, 'municipality profile');
    return MunicipalityAccount(
      id: profile['id'].toString(),
      name: profile['name'] as String,
      email: profile['email'] as String,
      serviceArea: 'غير متاح',
      isActive: profile['is_active'] as bool,
    );
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    try {
      if (refreshToken != null) {
        await _api.post<Map<String, dynamic>>(
          '/municipalities/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      }
    } finally {
      await clearLocalSession();
    }
  }

  @override
  Future<void> clearLocalSession() => _api.clearSession();
}

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository([MunicipalityRepository? _]);
  String? _activeNationalId;
  OnboardingSession? _activeRegistrationSession;

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
    final normalizedId = normalizeDigits(nationalId).trim();
    final normalizedPin = normalizeDigits(pin).trim();
    if (_pins[normalizedId] != normalizedPin) {
      throw const AuthFailure(
        'تعذّر تسجيل الدخول. تحقق من البيانات وحاول مجددًا.',
      );
    }
    _activeNationalId = normalizedId;
    return UserLoginResult(account: _accounts[normalizedId]!);
  }

  @override
  Future<UserAccount> restoreUser() async {
    final account = _accounts[_activeNationalId ?? citizenNationalId];
    if (account == null) throw const AuthFailure('انتهت الجلسة.');
    final registration = _activeRegistrationSession;
    if (registration == null) return account;
    return account.copyWith(
      applicationStatus: registration.applicationStatus,
      hasVolunteerMembership:
          registration.applicationStatus == ApplicationStatus.accepted,
    );
  }

  @override
  Future<UserLoginResult> registerUser(OnboardingSession session) async {
    final identity = session.identity;
    if (identity == null || session.pinForRegistration == null) {
      throw const AuthFailure('تعذّر إكمال إنشاء الحساب.');
    }
    final account = UserAccount(
      id: 'local-${identity.identityNumber}',
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
    _pins[account.nationalId] = session.pinForRegistration!;
    _activeNationalId = account.nationalId;
    _activeRegistrationSession = session;
    return UserLoginResult(account: account);
  }

  @override
  Future<bool> verifyUserPin({
    required String userId,
    required String pin,
  }) async {
    if (!isValidLoginPin(pin)) return false;
    final account = _accounts.values
        .where((item) => item.id == userId)
        .firstOrNull;
    return account != null &&
        _pins[account.nationalId] == normalizeDigits(pin).trim();
  }

  @override
  Future<void> logoutUser() async {
    _activeNationalId = null;
    _activeRegistrationSession = null;
  }

  @override
  Future<void> clearLocalSession() async {
    _activeNationalId = null;
    _activeRegistrationSession = null;
  }
}

class DemoMunicipalityAuthRepository implements MunicipalityAuthRepository {
  static const demoEmail = 'municipality@firepin.ps';
  static const demoPassword = 'firepin-demo';
  static const _account = MunicipalityAccount(
    id: 'municipality-jerusalem',
    name: 'بلدية القدس',
    email: demoEmail,
    serviceArea: 'القدس والمناطق المحيطة',
    isActive: true,
  );

  @override
  Future<MunicipalityLoginResult> login({
    required String email,
    required String password,
  }) async {
    if (email.trim().toLowerCase() != demoEmail || password != demoPassword) {
      throw const AuthFailure(
        'تعذّر تسجيل الدخول. تحقق من البريد وكلمة المرور.',
      );
    }
    return const MunicipalityLoginResult(account: _account);
  }

  @override
  Future<MunicipalityAccount> restore() async => _account;

  @override
  Future<void> logout() async {}

  @override
  Future<void> clearLocalSession() async {}
}

(String, String) _tokens(Map<String, dynamic>? data) {
  final json = _map(data, 'login response');
  final accessToken = json['access_token'];
  final refreshToken = json['refresh_token'];
  if (accessToken is! String ||
      accessToken.isEmpty ||
      refreshToken is! String ||
      refreshToken.isEmpty) {
    throw const FormatException('Login response has invalid tokens');
  }
  return (accessToken, refreshToken);
}

Map<String, dynamic> _map(Object? value, String name) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Invalid $name');
}

ApplicationStatus _applicationStatus(Object? value) => switch (value) {
  'pending' => ApplicationStatus.pending,
  'accepted' => ApplicationStatus.accepted,
  'rejected' => ApplicationStatus.rejected,
  _ => ApplicationStatus.none,
};

String _apiDate(String value) {
  final normalized = normalizeDigits(value).trim();
  final parts = normalized.split(RegExp(r'\s*/\s*'));
  if (parts.length == 3) {
    return '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
  }
  return normalized;
}

String _displayDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return value;
  return '${parts[2]} / ${parts[1]} / ${parts[0]}';
}

AuthFailure _authFailure(Object error) {
  if (error is AuthFailure) return error;
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] is String) {
      return AuthFailure(data['detail'] as String);
    }
  }
  if (error is AuthenticationException) {
    return const AuthFailure('انتهت الجلسة. سجّل الدخول مجددًا.');
  }
  return const AuthFailure('تعذّر الاتصال بالخادم. حاول مجددًا.');
}
