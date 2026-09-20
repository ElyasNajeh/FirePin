import 'dart:convert';

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
        subjectId: json['subjectId'] as String,
        refreshToken: json['refreshToken'] as String,
      );
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(StoredSession session) => _storage.saveSession(
    jsonEncode({
      'principal': session.principal.name,
      'subjectId': session.subjectId,
      'refreshToken': session.refreshToken,
    }),
  );

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.deleteSession(),
      _storage.deleteRefreshToken(),
    ]);
  }
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
  Future<UserAccount> restoreUser(String userId, String refreshToken);
  Future<UserLoginResult> registerUser(OnboardingSession session);
  Future<bool> verifyUserPin({required String userId, required String pin});
  Future<void> logoutUser(String refreshToken);
}

abstract interface class MunicipalityAuthRepository {
  Future<MunicipalityLoginResult> login({
    required String email,
    required String password,
  });
  Future<MunicipalityAccount> restore(
    String municipalityId,
    String refreshToken,
  );
  Future<void> logout(String refreshToken);
}

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(this._operations);
  final MunicipalityRepository _operations;

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
      applicationStatus: ApplicationStatus.approved,
      hasVolunteerMembership: true,
    ),
    secondVolunteerNationalId: const UserAccount(
      id: 'user-volunteer-2',
      fullName: 'عمر يوسف النجار',
      nationalId: secondVolunteerNationalId,
      phone: '059 333 4466',
      birthDate: '06 / 07 / 1995',
      address: 'القدس — شعفاط',
      applicationStatus: ApplicationStatus.approved,
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
    final account = _resolve(_accounts[normalizedId]!);
    return UserLoginResult(
      account: account,
      tokens: AuthTokens(
        accessToken: 'demo-access-${account.id}',
        refreshToken: 'demo-refresh-${account.id}',
      ),
    );
  }

  @override
  Future<UserAccount> restoreUser(String userId, String refreshToken) async {
    final account = _accounts.values
        .where((item) => item.id == userId)
        .firstOrNull;
    if (account == null || refreshToken != 'demo-refresh-$userId') {
      throw const AuthFailure('انتهت الجلسة.');
    }
    return _resolve(account);
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
          session.applicationStatus == ApplicationStatus.approved,
    );
    _accounts[account.nationalId] = account;
    _pins[account.nationalId] = session.pinForRegistration!;
    return UserLoginResult(
      account: account,
      tokens: AuthTokens(
        accessToken: 'demo-access-${account.id}',
        refreshToken: 'demo-refresh-${account.id}',
      ),
    );
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

  UserAccount _resolve(UserAccount account) => account.copyWith(
    applicationStatus: _operations.applicationStatusFor(account.nationalId),
    hasVolunteerMembership: _operations.hasVolunteerMembership(
      account.nationalId,
    ),
  );

  @override
  Future<void> logoutUser(String refreshToken) async {}
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
    return const MunicipalityLoginResult(
      account: _account,
      tokens: AuthTokens(
        accessToken: 'demo-municipality-access',
        refreshToken: 'demo-municipality-refresh',
      ),
    );
  }

  @override
  Future<MunicipalityAccount> restore(
    String municipalityId,
    String refreshToken,
  ) async {
    if (municipalityId != _account.id ||
        refreshToken != 'demo-municipality-refresh') {
      throw const AuthFailure('انتهت الجلسة.');
    }
    return _account;
  }

  @override
  Future<void> logout(String refreshToken) async {}
}
