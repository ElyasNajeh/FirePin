import 'package:flutter/material.dart';
import '../../app/app_services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../auth/login_screens.dart';
import '../welcome/welcome_screen.dart';
import 'identity_screens.dart';
import 'municipality_selection_screen.dart';
import 'onboarding_models.dart';
import 'phone_pin_screens.dart';
import 'role_screens.dart';

enum OnboardingStep {
  welcome,
  userLogin,
  municipalityLogin,
  identity,
  phone,
  pin,
  role,
  municipalitySelection,
  volunteerWarning,
  pending,
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
  String _current = OnboardingStep.welcome.name;
  late final _observer = _FlowObserver((name) => _current = name);
  bool _preparingRegistration = false;

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
      onStart: () => _go(OnboardingStep.identity),
      onLogin: () => _go(OnboardingStep.userLogin),
      onMunicipalityLogin: () => _go(OnboardingStep.municipalityLogin),
    ),
    OnboardingStep.userLogin => UserLoginScreen(
      auth: widget.services.authController,
      onBack: _back,
      onCreateAccount: () => _go(OnboardingStep.identity),
    ),
    OnboardingStep.municipalityLogin => MunicipalityLoginScreen(
      auth: widget.services.authController,
      onBack: _back,
    ),
    OnboardingStep.identity => IdentityDetailsScreen(
      onBack: _back,
      onContinue: (identity) {
        _session.identity = identity;
        _go(OnboardingStep.phone);
      },
    ),
    OnboardingStep.phone => PhoneNumberScreen(
      onBack: _back,
      onContinue: (phone) {
        _session.phone = phone;
        _go(OnboardingStep.pin);
      },
    ),
    OnboardingStep.pin => PinScreen(
      session: _session,
      onBack: _back,
      onContinue: () => _go(OnboardingStep.role),
    ),
    OnboardingStep.role => RoleSelectionScreen(
      initialRole: _session.role,
      onBack: _back,
      onContinue: (role) {
        _session.role = role;
        switch (_session.destination) {
          case AccountDestination.home:
            _completeRegistration();
          case AccountDestination.volunteerWarning:
            _prepareVolunteerRegistration();
          case AccountDestination.pendingApproval:
            _go(OnboardingStep.pending, clear: true);
        }
      },
    ),
    OnboardingStep.municipalitySelection => MunicipalitySelectionScreen(
      repository: widget.services.municipalityDirectory,
      initialMunicipalityId: _session.municipalityId,
      onBack: _back,
      onContinue: (municipality) {
        _session.selectMunicipality(
          id: municipality.id,
          name: municipality.name,
        );
        _go(OnboardingStep.volunteerWarning);
      },
    ),
    OnboardingStep.volunteerWarning => VolunteerWarningScreen(
      service: widget.services.volunteer,
      municipalityId: _session.municipalityId!,
      onBack: _back,
      onSubmitted: (status) async {
        _session.applicationStatus = status;
        await widget.services.authController.activatePreparedRegistration();
      },
    ),
    OnboardingStep.pending => const VolunteerPendingScreen(),
  };

  Future<void> _completeRegistration() async {
    try {
      await widget.services.authController.completeRegistration(_session);
    } on Object {
      if (mounted) {
        showFeedback(context, 'تعذّر حفظ الجلسة. حاول مجددًا.');
      }
    }
  }

  Future<void> _prepareVolunteerRegistration() async {
    if (_preparingRegistration) return;
    _preparingRegistration = true;
    try {
      await widget.services.authController.prepareRegistration(_session);
      if (mounted) _go(OnboardingStep.municipalitySelection);
    } on Object {
      if (mounted) {
        showFeedback(context, 'تعذّر إنشاء الحساب. حاول مجددًا.');
      }
    } finally {
      _preparingRegistration = false;
    }
  }

  @override
  void dispose() {
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
