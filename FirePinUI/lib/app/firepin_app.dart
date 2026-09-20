import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/onboarding/onboarding_flow.dart';
import '../features/auth/auth_models.dart';
import '../features/home/home_screen.dart';
import '../features/municipality/municipality_dashboard.dart';
import '../features/onboarding/onboarding_models.dart';
import '../features/onboarding/volunteer_application_flow.dart';
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
  bool _applyingVolunteer = false;

  @override
  void initState() {
    super.initState();
    _services.authController.addListener(_syncIncidentPolling);
    _syncIncidentPolling();
    unawaited(_services.authController.restore());
  }

  void _syncIncidentPolling() {
    switch (_services.authController.status) {
      case AuthStatus.user || AuthStatus.municipality:
        unawaited(_services.incidents.startPolling());
      case AuthStatus.restoring || AuthStatus.signedOut:
        _services.incidents.stopPolling();
    }
  }

  @override
  void dispose() {
    _services.authController.removeListener(_syncIncidentPolling);
    _services.incidents.stopPolling();
    super.dispose();
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
    if (_applyingVolunteer) {
      return VolunteerApplicationFlow(
        directory: _services.municipalityDirectory,
        applications: _services.volunteer,
        onCancel: () => setState(() => _applyingVolunteer = false),
        onSubmitted: (_) async {
          await _services.authController.refreshUser();
          if (mounted) setState(() => _applyingVolunteer = false);
        },
      );
    }
    if (_reporting) {
      return FireCameraScreen(
        services: _services,
        session: session,
        onClose: () => setState(() => _reporting = false),
        onSubmitted: (photo) async {
          final submitted = await _services.incidents.report(
            location: session.location!,
            reporterPhone: session.phone,
            reporterId: account.id,
            reporterName: account.fullName,
            reporterNationalId: account.nationalId,
            photo: photo,
          );
          if (!submitted) {
            throw StateError('Shared demo incident creation failed.');
          }
          if (!mounted) return;
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
        _applyingVolunteer = false;
        await _services.authController.logout();
      },
      onApplyVolunteer: () => setState(() => _applyingVolunteer = true),
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
