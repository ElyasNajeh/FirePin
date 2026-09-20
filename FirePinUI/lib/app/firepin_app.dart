import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/onboarding/onboarding_flow.dart';
import '../features/auth/auth_models.dart';
import '../features/home/home_screen.dart';
import '../features/municipality/municipality_dashboard.dart';
import '../features/onboarding/onboarding_models.dart';
import '../features/report/fire_camera_screen.dart';
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
  bool _reporting = false;

  @override
  void initState() {
    super.initState();
    _services.authController.restore();
  }

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
      home: AnimatedBuilder(
        animation: _services.authController,
        builder: (context, _) => switch (_services.authController.status) {
          AuthStatus.restoring => const _StartupScreen(),
          AuthStatus.signedOut => OnboardingFlow(services: _services),
          AuthStatus.user => _buildUserExperience(),
          AuthStatus.municipality => MunicipalityDashboard(
            account: _services.authController.municipality!,
            repository: _services.operations,
            onLogout: _services.authController.logout,
          ),
        },
      ),
    );
  }

  Widget _buildUserExperience() {
    final account = _services.authController.user!;
    final session = OnboardingSession()
      ..accountId = account.id
      ..identity = IdentityData(
        fullName: account.fullName,
        identityNumber: account.nationalId,
        birthDate: account.birthDate,
        gender: '',
        address: account.address,
      )
      ..phone = account.phone
      ..location = const LocationFix(31.78, 35.24, 10)
      ..role = account.role
      ..applicationStatus = account.applicationStatus;
    if (_reporting) {
      return FireCameraScreen(
        services: _services,
        session: session,
        onClose: () => setState(() => _reporting = false),
        onSubmitted: (photo) {
          _services.incidents.report(
            location: session.location!,
            reporterPhone: session.phone,
            reporterName: account.fullName,
            reporterNationalId: account.nationalId,
            photo: photo,
          );
          setState(() => _reporting = false);
        },
      );
    }
    return HomeScreen(
      hasLocation: true,
      session: session,
      incidentController: _services.incidents,
      onReport: () => setState(() => _reporting = true),
      onLogout: () async {
        _reporting = false;
        await _services.authController.logout();
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Semantics(
        label: 'جارٍ استعادة الجلسة',
        child: CircularProgressIndicator(),
      ),
    ),
  );
}
