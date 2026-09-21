import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'app/app_services.dart';
import 'app/firepin_app.dart';
import 'features/notifications/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final services = AppServices();
  await services.notifications.initialize();

  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUi);

  runApp(FirePinApp(services: services));
}
