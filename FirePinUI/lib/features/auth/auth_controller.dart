import 'package:flutter/foundation.dart';

import '../onboarding/onboarding_models.dart';
import 'auth_models.dart';
import 'auth_repositories.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository users,
    required MunicipalityAuthRepository municipalities,
    required SessionRepository sessions,
  }) : _users = users,
       _municipalities = municipalities,
       _sessions = sessions;

  final AuthRepository _users;
  final MunicipalityAuthRepository _municipalities;
  final SessionRepository _sessions;

  AuthStatus _status = AuthStatus.restoring;
  UserAccount? _user;
  MunicipalityAccount? _municipality;
  String? _refreshToken;

  AuthStatus get status => _status;
  UserAccount? get user => _user;
  MunicipalityAccount? get municipality => _municipality;

  Future<void> restore() async {
    _status = AuthStatus.restoring;
    notifyListeners();
    final stored = await _sessions.read();
    if (stored == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      _refreshToken = stored.refreshToken;
      if (stored.principal == AuthPrincipal.user) {
        _user = await _users.restoreUser(stored.subjectId, stored.refreshToken);
        _status = AuthStatus.user;
      } else {
        _municipality = await _municipalities.restore(
          stored.subjectId,
          stored.refreshToken,
        );
        _status = AuthStatus.municipality;
      }
    } on Object {
      await _sessions.clear();
      _clearMemory();
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> loginUser(String nationalId, String pin) async {
    final result = await _users.loginUser(nationalId: nationalId, pin: pin);
    await _setUser(result);
  }

  Future<void> completeRegistration(OnboardingSession session) async {
    final result = await _users.registerUser(session);
    await _setUser(result);
  }

  Future<void> loginMunicipality(String email, String password) async {
    final result = await _municipalities.login(
      email: email,
      password: password,
    );
    _clearMemory();
    _municipality = result.account;
    _refreshToken = result.tokens.refreshToken;
    await _sessions.save(
      StoredSession(
        principal: AuthPrincipal.municipality,
        subjectId: result.account.id,
        refreshToken: result.tokens.refreshToken,
      ),
    );
    _status = AuthStatus.municipality;
    notifyListeners();
  }

  Future<void> _setUser(UserLoginResult result) async {
    _clearMemory();
    _user = result.account;
    _refreshToken = result.tokens.refreshToken;
    await _sessions.save(
      StoredSession(
        principal: AuthPrincipal.user,
        subjectId: result.account.id,
        refreshToken: result.tokens.refreshToken,
      ),
    );
    _status = AuthStatus.user;
    notifyListeners();
  }

  Future<void> logout() async {
    final token = _refreshToken;
    try {
      if (token != null && _status == AuthStatus.user) {
        await _users.logoutUser(token);
      } else if (token != null && _status == AuthStatus.municipality) {
        await _municipalities.logout(token);
      }
    } finally {
      await _sessions.clear();
      _clearMemory();
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  void _clearMemory() {
    _user = null;
    _municipality = null;
    _refreshToken = null;
  }
}
