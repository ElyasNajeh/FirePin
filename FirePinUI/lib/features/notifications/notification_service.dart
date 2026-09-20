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

class FirePinNotificationService {
  FirePinNotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    NotificationDeviceTokenApi? deviceTokenApi,
  }) : _providedMessaging = messaging,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _deviceTokenApi = deviceTokenApi;

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
  final StreamController<String> _reportTapController =
      StreamController<String>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  NotificationAccountType? _accountType;
  String? _currentToken;
  String? _initialReportId;

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

      _currentToken = await _messaging.getToken();
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
        _initialReportId = _reportId(initialMessage.data['report_id']);
      }

      final localLaunch = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp ?? false) {
        _initialReportId = _reportIdFromPayload(
          localLaunch?.notificationResponse?.payload,
        );
      }
    } on Object catch (error) {
      debugPrint('Notification setup unavailable: ${error.runtimeType}');
    }
  }

  Future<void> attachAuthenticatedAccount(
    NotificationAccountType accountType,
  ) async {
    final api = _deviceTokenApi;
    if (api == null) {
      throw StateError('Notification device-token API is not configured');
    }

    _accountType = accountType;
    final token = _currentToken ?? await _messaging.getToken();
    _currentToken = token;
    if (token != null) {
      await api.registerToken(
        accountType: accountType,
        token: token,
        platform: _platformName,
      );
    }
  }

  Future<void> detachAuthenticatedAccount() async {
    final api = _deviceTokenApi;
    final accountType = _accountType;
    final token = _currentToken;
    try {
      if (api != null && accountType != null && token != null) {
        await api.removeToken(accountType: accountType, token: token);
      }
    } finally {
      _accountType = null;
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
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _handleTokenRefresh(String token) async {
    final previousToken = _currentToken;
    _currentToken = token;

    final api = _deviceTokenApi;
    final accountType = _accountType;
    if (api == null || accountType == null) {
      return;
    }

    try {
      await api.registerToken(
        accountType: accountType,
        token: token,
        platform: _platformName,
      );
      if (previousToken != null && previousToken != token) {
        await api.removeToken(accountType: accountType, token: previousToken);
      }
    } on Object catch (error) {
      debugPrint('Unable to update notification token: ${error.runtimeType}');
    }
  }

  void _handleRemoteMessageTap(RemoteMessage message) {
    final reportId = _reportId(message.data['report_id']);
    if (reportId != null) {
      _reportTapController.add(reportId);
    }
  }

  void _handleLocalNotificationTap(NotificationResponse response) {
    final reportId = _reportIdFromPayload(response.payload);
    if (reportId != null) {
      _reportTapController.add(reportId);
    }
  }

  String? _reportId(Object? value) {
    final reportId = value?.toString();
    if (reportId != null && reportId.isNotEmpty) {
      return reportId;
    }
    return null;
  }

  String? _reportIdFromPayload(String? payload) {
    if (payload == null) {
      return null;
    }
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return _reportId(data['report_id']);
    } on FormatException {
      return null;
    }
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
