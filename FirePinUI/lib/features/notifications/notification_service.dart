import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_api.dart';

const fireEmergencyChannelId = 'fire_emergency';
const fireEmergencySoundName = 'fire_alarm';
// Change to true only after a project-owned fire_alarm.wav/ogg is in res/raw.
const useBundledFireEmergencySound = false;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

abstract interface class AuthenticatedNotificationLifecycle {
  Future<void> attachAuthenticatedAccount(NotificationAccountType accountType);
  Future<void> detachAuthenticatedAccount();
}

class FirePinNotificationService implements AuthenticatedNotificationLifecycle {
  FirePinNotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    NotificationDeviceTokenApi? deviceTokenApi,
    Future<String?> Function()? tokenProvider,
    String? platformOverride,
  }) : _providedMessaging = messaging,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _deviceTokenApi = deviceTokenApi,
       _tokenProvider = tokenProvider,
       _platformOverride = platformOverride;

  static const _emergencyChannel = AndroidNotificationChannel(
    fireEmergencyChannelId,
    'Fire emergency alerts',
    description: 'Urgent alerts for newly reported fires',
    importance: Importance.max,
    playSound: true,
    sound: useBundledFireEmergencySound
        ? RawResourceAndroidNotificationSound(fireEmergencySoundName)
        : null,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  final FirebaseMessaging? _providedMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final NotificationDeviceTokenApi? _deviceTokenApi;
  final Future<String?> Function()? _tokenProvider;
  final String? _platformOverride;
  final StreamController<String> _reportTapController =
      StreamController<String>.broadcast(sync: true);

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  NotificationAccountType? _accountType;
  NotificationAccountType? _registeredAccountType;
  String? _currentToken;
  String? _registeredToken;
  String? _initialReportId;
  final Set<String> _handledTapKeys = <String>{};
  Future<void> _ownershipOperations = Future<void>.value();

  Stream<String> get reportTaps => _reportTapController.stream;

  String? takeInitialReportId() {
    final reportId = _initialReportId;
    _initialReportId = null;
    return reportId;
  }

  FirebaseMessaging get _messaging =>
      _providedMessaging ?? FirebaseMessaging.instance;

  Future<void> initialize() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
      await _initializeLocalNotifications();

      _currentToken = await _getToken();
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
        (token) => unawaited(_handleTokenRefresh(token)),
      );
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_showForegroundNotification(message)),
      );
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleRemoteMessageTap,
      );

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _storeInitialTap(initialMessage.data, initialMessage.messageId);
      }

      final localLaunch = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp ?? false) {
        _storeInitialPayload(localLaunch?.notificationResponse?.payload);
      }
    } on Object catch (error) {
      debugPrint('Notification setup unavailable: ${error.runtimeType}');
    }
  }

  @override
  Future<void> attachAuthenticatedAccount(NotificationAccountType accountType) {
    return _enqueueOwnershipOperation(() => _attachAccount(accountType));
  }

  Future<void> _attachAccount(NotificationAccountType accountType) async {
    final api = _deviceTokenApi;
    if (api == null) {
      throw StateError('Notification device-token API is not configured');
    }

    _accountType = accountType;
    final token = _currentToken ?? await _getToken();
    _currentToken = token;
    if (token == null) {
      return;
    }

    if (_registeredAccountType == accountType) {
      await _replaceRegisteredToken(token);
      return;
    }

    await api.registerToken(
      accountType: accountType,
      token: token,
      platform: _platformName,
    );
    _registeredAccountType = accountType;
    _registeredToken = token;
  }

  @override
  Future<void> detachAuthenticatedAccount() {
    return _enqueueOwnershipOperation(_detachAccount);
  }

  Future<void> _detachAccount() async {
    final api = _deviceTokenApi;
    final accountType = _accountType;
    final token = _registeredToken;
    try {
      if (api != null && accountType != null && token != null) {
        await api.removeToken(accountType: accountType, token: token);
      }
    } finally {
      _accountType = null;
      _registeredAccountType = null;
      _registeredToken = null;
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_emergencyChannel);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final type = message.data['type'] ?? message.data['event_type'];
    final isEmergency = type == 'fire_report_created';
    final title = notification?.title ?? _fallbackTitle(type);
    final body = notification?.body ?? '';

    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isEmergency ? fireEmergencyChannelId : 'firepin_updates',
          isEmergency ? 'Fire emergency alerts' : 'FirePin updates',
          channelDescription: isEmergency
              ? 'Urgent alerts for newly reported fires'
              : 'Fire report status updates',
          importance: isEmergency ? Importance.max : Importance.high,
          priority: isEmergency ? Priority.max : Priority.high,
          playSound: true,
          sound: isEmergency && useBundledFireEmergencySound
              ? const RawResourceAndroidNotificationSound(
                  fireEmergencySoundName,
                )
              : null,
          enableVibration: true,
          audioAttributesUsage: isEmergency
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode({
        ...message.data,
        if (message.messageId != null) '_firepin_message_id': message.messageId,
      }),
    );
  }

  Future<void> _handleTokenRefresh(String token) async {
    _currentToken = token;

    try {
      await _enqueueOwnershipOperation(() => _replaceRegisteredToken(token));
    } on Object catch (error) {
      debugPrint('Unable to update notification token: ${error.runtimeType}');
    }
  }

  Future<void> _replaceRegisteredToken(String token) async {
    final api = _deviceTokenApi;
    final accountType = _accountType;
    final previousToken = _registeredToken;
    if (api == null || accountType == null || previousToken == token) {
      return;
    }

    await api.registerToken(
      accountType: accountType,
      token: token,
      platform: _platformName,
    );
    _registeredAccountType = accountType;
    _registeredToken = token;
    if (previousToken != null) {
      await api.removeToken(accountType: accountType, token: previousToken);
    }
  }

  Future<void> _enqueueOwnershipOperation(Future<void> Function() operation) {
    final result = _ownershipOperations.then((_) => operation());
    _ownershipOperations = _ignoreOwnershipFailure(result);
    return result;
  }

  Future<void> _ignoreOwnershipFailure(Future<void> operation) async {
    try {
      await operation;
    } on Object {
      // The caller receives the error; keep later ownership operations usable.
    }
  }

  Future<String?> _getToken() {
    return _tokenProvider?.call() ?? _messaging.getToken();
  }

  @visibleForTesting
  Future<void> handleTokenRefreshForTest(String token) {
    return _handleTokenRefresh(token);
  }

  void _handleRemoteMessageTap(RemoteMessage message) {
    _emitTap(message.data, message.messageId);
  }

  void _handleLocalNotificationTap(NotificationResponse response) {
    final data = _dataFromPayload(response.payload);
    if (data != null) {
      _emitTap(data, data['_firepin_message_id']?.toString());
    }
  }

  String? _reportId(Object? value) {
    final reportId = int.tryParse(value?.toString() ?? '');
    return reportId != null && reportId > 0 ? reportId.toString() : null;
  }

  Map<String, dynamic>? _dataFromPayload(String? payload) {
    if (payload == null) {
      return null;
    }
    try {
      final data = jsonDecode(payload);
      return data is Map<String, dynamic> ? data : null;
    } on FormatException {
      return null;
    }
  }

  void _storeInitialPayload(String? payload) {
    final data = _dataFromPayload(payload);
    if (data != null) {
      _storeInitialTap(data, data['_firepin_message_id']?.toString());
    }
  }

  void _storeInitialTap(Map<String, dynamic> data, String? messageId) {
    final reportId = _reportId(data['report_id']);
    if (reportId == null) return;
    final key = _tapKey(data, reportId, messageId);
    if (_handledTapKeys.add(key)) {
      _initialReportId = reportId;
    }
  }

  void _emitTap(Map<String, dynamic> data, String? messageId) {
    final reportId = _reportId(data['report_id']);
    if (reportId == null) return;
    final key = _tapKey(data, reportId, messageId);
    if (_handledTapKeys.add(key)) {
      _reportTapController.add(reportId);
    }
  }

  String _tapKey(
    Map<String, dynamic> data,
    String reportId,
    String? messageId,
  ) => messageId?.trim().isNotEmpty == true
      ? 'message:${messageId!.trim()}'
      : '${data['type'] ?? data['event_type'] ?? 'report'}:$reportId';

  @visibleForTesting
  void handleReportTapForTest({
    required Object? reportId,
    String? type,
    String? messageId,
  }) {
    _emitTap({'report_id': reportId, 'type': ?type}, messageId);
  }

  @visibleForTesting
  void setInitialReportTapForTest({
    required Object? reportId,
    String? type,
    String? messageId,
  }) {
    _storeInitialTap({'report_id': reportId, 'type': ?type}, messageId);
  }

  String _fallbackTitle(String? type) {
    return switch (type) {
      'fire_report_created' => 'بلاغ حريق جديد',
      'fire_report_claimed' => 'تمت تلبية النداء',
      'fire_report_resolved' => 'تم إنهاء البلاغ',
      _ => 'FirePin',
    };
  }

  String get _platformName {
    final override = _platformOverride;
    if (override != null) {
      return override;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => throw UnsupportedError(
        'Device-token registration supports Android and iOS only',
      ),
    };
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _reportTapController.close();
  }
}
