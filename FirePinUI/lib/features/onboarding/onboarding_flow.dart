import 'package:flutter/material.dart';
import '../../app/app_services.dart';
import '../../core/ui/motion.dart';
import '../home/home_screen.dart';
import '../incidents/incident_controller.dart';
import '../report/fire_camera_screen.dart';
import '../welcome/welcome_screen.dart';
import 'identity_screens.dart';
import 'onboarding_models.dart';
import 'permission_screens.dart';
import 'phone_pin_screens.dart';
import 'role_screens.dart';

enum OnboardingStep {
  welcome,
  cameraPermission,
  capture,
  identitySuccess,
  review,
  phone,
  otp,
  phoneSuccess,
  pin,
  location,
  role,
  volunteerWarning,
  pending,
  home,
  fireCamera,
}

/// Navigation owns session state; widgets depend only on narrow callbacks/services.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.services});
  final AppServices services;
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _navigator = GlobalKey<NavigatorState>();
  final _session = OnboardingSession();
  final _incidents = IncidentController();
  String _current = OnboardingStep.welcome.name;
  late final _observer = _FlowObserver((name) => _current = name);

  void _go(OnboardingStep step, {bool replace = false, bool clear = false}) {
    if (!mounted || _current == step.name) return;
    _current = step.name;
    final route = AppMotion.route<void>(context, _screen(step), step.name);
    if (clear) {
      _navigator.currentState!.pushAndRemoveUntil(route, (_) => false);
    } else if (replace) {
      _navigator.currentState!.pushReplacement(route);
    } else {
      _navigator.currentState!.push(route);
    }
  }

  void _back() => _navigator.currentState!.maybePop();
  Widget _screen(OnboardingStep step) => switch (step) {
    OnboardingStep.welcome => WelcomeScreen(
      onStart: () => _go(OnboardingStep.cameraPermission),
    ),
    OnboardingStep.cameraPermission => CameraPermissionScreen(
      permissions: widget.services.permissions,
      onGranted: () => _go(OnboardingStep.capture),
      onBack: _back,
    ),
    OnboardingStep.capture => IdentityCaptureScreen(
      services: widget.services,
      onVerified: (image, identity) {
        _session.identityImage = image;
        _session.identity = identity;
        _go(OnboardingStep.identitySuccess, replace: true);
      },
    ),
    OnboardingStep.identitySuccess => IdentitySuccessScreen(
      onContinue: () => _go(OnboardingStep.review, replace: true),
    ),
    OnboardingStep.review => IdentityReviewScreen(
      identity: _session.identity!,
      image: _session.identityImage!,
      onContinue: () => _go(OnboardingStep.phone),
    ),
    OnboardingStep.phone => PhoneNumberScreen(
      otp: widget.services.otp,
      onSent: (phone) {
        _session.phone = phone;
        _go(OnboardingStep.otp);
      },
    ),
    OnboardingStep.otp => OtpScreen(
      otp: widget.services.otp,
      phone: _session.phone,
      onVerified: () => _go(OnboardingStep.phoneSuccess, replace: true),
    ),
    OnboardingStep.phoneSuccess => PhoneSuccessScreen(
      onContinue: () => _go(OnboardingStep.pin, replace: true),
    ),
    OnboardingStep.pin => PinScreen(
      session: _session,
      onContinue: () => _go(OnboardingStep.location, replace: true),
    ),
    OnboardingStep.location => LocationPermissionScreen(
      service: widget.services.location,
      onContinue: (fix) {
        _session.location = fix;
        _go(OnboardingStep.role);
      },
    ),
    OnboardingStep.role => RoleSelectionScreen(
      initialRole: _session.role,
      onContinue: (role) {
        _session.role = role;
        switch (_session.destination) {
          case AccountDestination.home:
            _go(OnboardingStep.home, clear: true);
          case AccountDestination.volunteerWarning:
            _go(OnboardingStep.volunteerWarning);
          case AccountDestination.pendingApproval:
            _go(OnboardingStep.pending, clear: true);
        }
      },
    ),
    OnboardingStep.volunteerWarning => VolunteerWarningScreen(
      service: widget.services.volunteer,
      onBack: _back,
      onSubmitted: (status) {
        _session.applicationStatus = status;

        switch (_session.destination) {
          case AccountDestination.home:
            _go(OnboardingStep.home, clear: true);
          case AccountDestination.pendingApproval:
            _go(OnboardingStep.pending, clear: true);
          case AccountDestination.volunteerWarning:
            _go(OnboardingStep.volunteerWarning);
        }
      },
    ),
    OnboardingStep.pending => const VolunteerPendingScreen(),
    OnboardingStep.home => HomeScreen(
      hasLocation: _session.location != null,
      onReport: () => _go(OnboardingStep.fireCamera),
      session: _session,
      incidentController: _incidents,
    ),
    OnboardingStep.fireCamera => FireCameraScreen(
      services: widget.services,
      session: _session,
      onClose: _back,
      onSubmitted: (photo) {
        _incidents.report(
          location: _session.location!,
          reporterPhone: _session.phone,
          photo: photo,
        );
        _go(OnboardingStep.home, clear: true);
      },
    ),
  };
  @override
  void dispose() {
    _incidents.dispose();
    _session.clearSensitiveData();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => _back(),
    child: Navigator(
      key: _navigator,
      observers: [_observer],
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(
          settings: RouteSettings(name: OnboardingStep.welcome.name),
          builder: (_) => _screen(OnboardingStep.welcome),
        ),
      ],
    ),
  );
}

class _FlowObserver extends NavigatorObserver {
  _FlowObserver(this.onChanged);
  final ValueChanged<String> onChanged;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged(route.settings.name ?? '');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged(previousRoute?.settings.name ?? '');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onChanged(newRoute?.settings.name ?? '');
  }
}
