import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/onboarding/onboarding_flow.dart';
import '../features/auth/auth_models.dart';
import '../features/home/home_screen.dart';
import '../features/municipality/municipality_dashboard.dart';
import '../features/onboarding/onboarding_models.dart';
import '../features/onboarding/volunteer_application_flow.dart';
import '../features/report/fire_reports_screen.dart';
import '../features/report/fire_camera_screen.dart';
import '../core/network/api_client.dart';
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
  LocationFix? _currentUserLocation;
  String? _locationUserId;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final List<String> _pendingReportIds = [];
  final Set<String> _queuedReportIds = {};
  StreamSubscription<String>? _notificationTapSubscription;
  String? _processingReportId;
  String? _openReportId;

  @override
  void initState() {
    super.initState();
    _services.authController.addListener(_scheduleNotificationNavigation);
    _notificationTapSubscription = _services.notifications.reportTaps.listen(
      _queueNotificationReport,
    );
    unawaited(_services.authController.restore());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialReportId = _services.notifications.takeInitialReportId();
      if (initialReportId != null) {
        _queueNotificationReport(initialReportId);
      } else {
        _scheduleNotificationNavigation();
      }
    });
  }

  void _queueNotificationReport(String reportId) {
    if (_processingReportId == reportId ||
        _openReportId == reportId ||
        !_queuedReportIds.add(reportId)) {
      return;
    }
    _pendingReportIds.add(reportId);
    _scheduleNotificationNavigation();
  }

  void _scheduleNotificationNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openNextNotificationReport());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openNextNotificationReport() async {
    if (!mounted ||
        _processingReportId != null ||
        _openReportId != null ||
        _pendingReportIds.isEmpty ||
        _navigatorKey.currentState == null) {
      return;
    }
    final status = _services.authController.status;
    if (status != AuthStatus.user && status != AuthStatus.municipality) {
      return;
    }

    final reportIdText = _pendingReportIds.removeAt(0);
    _queuedReportIds.remove(reportIdText);
    _processingReportId = reportIdText;
    final reportId = int.parse(reportIdText);
    try {
      final navigator = _navigatorKey.currentState!;
      if (status == AuthStatus.user) {
        final account = _services.authController.user!;
        final volunteer = account.role == UsageRole.volunteer;
        final repository = _services.reportRepository;
        final report = volunteer
            ? await repository.getVolunteerReport(reportId)
            : await repository.getMyReport(reportId);
        if (!mounted || _services.authController.status != AuthStatus.user) {
          return;
        }
        _openReportId = reportIdText;
        await navigator.push<void>(
          MaterialPageRoute(
            settings: RouteSettings(
              name: '/notifications/fire-reports/$reportIdText',
            ),
            builder: (_) => FireReportDetailScreen(
              report: report,
              volunteer: volunteer,
              repository: repository,
              location: _services.location,
              viewerUserId: account.id,
            ),
          ),
        );
      } else {
        final report = await _services.operations.getReport(reportId);
        if (!mounted ||
            _services.authController.status != AuthStatus.municipality) {
          return;
        }
        _openReportId = reportIdText;
        await navigator.push<void>(
          DialogRoute(
            context: navigator.context,
            settings: RouteSettings(
              name: '/notifications/municipality/fire-reports/$reportIdText',
            ),
            builder: (_) => MunicipalityReportDetailsDialog(incident: report),
          ),
        );
      }
    } on AuthenticationException {
      await _services.authController.handleExpiredSession();
      _showNotificationError('انتهت الجلسة. سجّل الدخول لفتح البلاغ.');
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      _showNotificationError(
        statusCode == 403 || statusCode == 404
            ? 'هذا البلاغ غير متاح للحساب الحالي.'
            : 'تعذّر فتح البلاغ. تحقق من الاتصال وحاول مجددًا.',
      );
    } on Object {
      _showNotificationError('تعذّر فتح البلاغ من الإشعار.');
    } finally {
      _processingReportId = null;
      _openReportId = null;
      _scheduleNotificationNavigation();
    }
  }

  void _showNotificationError(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _services.authController.removeListener(_scheduleNotificationNavigation);
    unawaited(_notificationTapSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
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
    if (_locationUserId != account.id) {
      _locationUserId = account.id;
      _currentUserLocation = null;
    }
    final session = OnboardingSession()
      ..accountId = account.id
      ..identity = IdentityData(
        fullName: account.fullName,
        identityNumber: account.nationalId,
        birthDate: account.birthDate,
        address: account.address,
      )
      ..phone = account.phone
      ..role = account.role
      ..applicationStatus = account.applicationStatus
      ..location = _currentUserLocation;
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
        onSubmitted: (report) async {
          if (!mounted) return;
          setState(() => _reporting = false);
          await _navigatorKey.currentState?.push<void>(
            MaterialPageRoute(
              settings: RouteSettings(
                name: '/fire-reports/${report.id}/created',
              ),
              builder: (_) => FireReportDetailScreen(
                report: report,
                volunteer: false,
                repository: _services.reportRepository,
                location: _services.location,
                viewerUserId: account.id,
              ),
            ),
          );
        },
      );
    }
    return HomeScreen(
      session: session,
      reportRepository: _services.reportRepository,
      location: _services.location,
      onReport: (location) {
        setState(() {
          _currentUserLocation = location;
          _reporting = true;
        });
      },
      onLogout: () async {
        _reporting = false;
        _applyingVolunteer = false;
        _currentUserLocation = null;
        _locationUserId = null;
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
