import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
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
