import 'package:flutter/foundation.dart';

import '../onboarding/onboarding_models.dart';
import '../notifications/notification_api.dart';
import '../notifications/notification_service.dart';
import 'auth_models.dart';
import 'auth_repositories.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository users,
    required MunicipalityAuthRepository municipalities,
    required SessionRepository sessions,
    AuthenticatedNotificationLifecycle? notifications,
  }) : _users = users,
       _municipalities = municipalities,
       _sessions = sessions,
       _notifications = notifications;

  final AuthRepository _users;
  final MunicipalityAuthRepository _municipalities;
  final SessionRepository _sessions;
  final AuthenticatedNotificationLifecycle? _notifications;

  AuthStatus _status = AuthStatus.restoring;
  UserAccount? _user;
  MunicipalityAccount? _municipality;

  AuthStatus get status => _status;
  UserAccount? get user => _user;
  MunicipalityAccount? get municipality => _municipality;

  Future<void> restore() async {
    _status = AuthStatus.restoring;
    notifyListeners();
    final stored = await _sessions.read();
    if (stored == null) {
      await _detachNotifications();
      await _clearPersistedAuthentication();
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      if (stored.principal == AuthPrincipal.user) {
        _user = await _users.restoreUser();
        _status = AuthStatus.user;
        notifyListeners();
        await _attachNotifications(NotificationAccountType.user);
      } else {
        _municipality = await _municipalities.restore();
        _status = AuthStatus.municipality;
        notifyListeners();
        await _attachNotifications(NotificationAccountType.municipality);
      }
    } on Object {
      await _detachNotifications();
      await _clearPersistedAuthentication();
      _clearMemory();
      _status = AuthStatus.signedOut;
    }
    if (_status == AuthStatus.signedOut) {
      notifyListeners();
    }
  }

  Future<void> loginUser(String nationalId, String pin) async {
    await _prepareForLogin();
    try {
      final result = await _users.loginUser(nationalId: nationalId, pin: pin);
      await _setUser(result);
    } on Object {
      _status = AuthStatus.signedOut;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> completeRegistration(OnboardingSession session) async {
    await _prepareForLogin();
    try {
      final result = await _users.registerUser(session);
      await _setUser(result);
    } on Object {
      _status = AuthStatus.signedOut;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> verifyCurrentUserPin(String pin) async {
    final currentUser = _user;
    if (_status != AuthStatus.user ||
        currentUser == null ||
        !isValidLoginPin(pin)) {
      return false;
    }
    return _users.verifyUserPin(userId: currentUser.id, pin: pin);
  }

  Future<void> loginMunicipality(String email, String password) async {
    await _prepareForLogin();
    try {
      final result = await _municipalities.login(
        email: email,
        password: password,
      );
      _clearMemory();
      _municipality = result.account;
      await _sessions.save(
        const StoredSession(principal: AuthPrincipal.municipality),
      );
      _status = AuthStatus.municipality;
      notifyListeners();
      await _attachNotifications(NotificationAccountType.municipality);
    } on Object {
      _status = AuthStatus.signedOut;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _setUser(UserLoginResult result) async {
    _clearMemory();
    _user = result.account;
    await _sessions.save(const StoredSession(principal: AuthPrincipal.user));
    _status = AuthStatus.user;
    notifyListeners();
    await _attachNotifications(NotificationAccountType.user);
  }

  Future<void> logout() async {
    await _detachNotifications();
    try {
      if (_status == AuthStatus.user) {
        await _users.logoutUser();
      } else if (_status == AuthStatus.municipality) {
        await _municipalities.logout();
      }
    } finally {
      await _clearPersistedAuthentication();
      _clearMemory();
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> _prepareForLogin() async {
    await _detachNotifications();
    await _clearPersistedAuthentication();
    _clearMemory();
    _status = AuthStatus.signedOut;
  }

  Future<void> _clearPersistedAuthentication() async {
    await Future.wait([
      _users.clearLocalSession(),
      _municipalities.clearLocalSession(),
      _sessions.clear(),
    ]);
  }

  Future<void> _attachNotifications(NotificationAccountType accountType) async {
    try {
      await _notifications?.attachAuthenticatedAccount(accountType);
    } on Object catch (error) {
      debugPrint(
        'Notification account attachment unavailable: ${error.runtimeType}',
      );
    }
  }

  Future<void> _detachNotifications() async {
    try {
      await _notifications?.detachAuthenticatedAccount();
    } on Object catch (error) {
      debugPrint(
        'Notification account cleanup unavailable: ${error.runtimeType}',
      );
    }
  }

  void _clearMemory() {
    _user = null;
    _municipality = null;
  }
}
