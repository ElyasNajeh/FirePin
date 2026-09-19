import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/onboarding/onboarding_flow.dart';
import '../theme/app_theme.dart';
import 'app_services.dart';

class FirePinApp extends StatefulWidget {
  const FirePinApp({super.key, this.services});
  final AppServices? services;

  @override
  State<FirePinApp> createState() => _FirePinAppState();
}

class _FirePinAppState extends State<FirePinApp> {
  late final _services = widget.services ?? AppServices();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'شباب البلد',
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemUi,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: OnboardingFlow(services: _services),
    );
  }
}
