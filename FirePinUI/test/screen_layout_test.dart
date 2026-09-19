import 'dart:io';
import 'dart:ui' as ui;
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/permission_screens.dart';
import 'package:firepin_ui/features/onboarding/phone_pin_screens.dart';
import 'package:firepin_ui/features/onboarding/role_screens.dart';
import 'package:firepin_ui/features/report/fire_camera_screen.dart';
import 'package:firepin_ui/features/welcome/welcome_screen.dart';
import 'package:firepin_ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_fakes.dart';

// Set FIREPIN_VISUAL_QA=true to export real-font renders into .dart_tool.
// No screenshot fixtures or test hooks are shipped in the application.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await loader.load();
  });
  final services = fakeServices();
  final session = OnboardingSession()
    ..location = const LocationFix(31.78, 35.24, 10);
  const identity = IdentityData(
    fullName: 'أحمد محمد عبد الله',
    identityNumber: '123456789',
    birthDate: '14 / 05 / 1998',
    gender: 'ذكر',
    address: 'القدس — الطور',
  );
  IncidentController demoIncident({bool accepted = false}) {
    final controller = IncidentController()
      ..report(
        location: const LocationFix(31.78, 35.24, 10),
        reporterPhone: '0591111111',
        photo: testPhoto,
      );
    if (accepted) controller.acceptByVolunteer();
    return controller;
  }

  final pages = <String, Widget Function()>{
    '01_welcome': () => WelcomeScreen(onStart: () {}),
    '02_camera_permission': () => CameraPermissionScreen(
      permissions: services.permissions,
      onGranted: () {},
      onBack: () {},
    ),
    '03_identity_camera': () => IdentityCaptureScreen(
      services: services,
      onVerified: (_, _) {},
      onBack: () {},
    ),
    '04_identity_success': () => IdentitySuccessScreen(onContinue: () {}),
    '05_identity_review': () => IdentityReviewScreen(
      identity: identity,
      image: testPhoto,
      onContinue: () {},
      onBack: () {},
    ),
    '06_phone': () => PhoneNumberScreen(onContinue: (_) {}, onBack: () {}),
    '07_otp': () =>
        OtpScreen(otp: services.otp, phone: '059 123 4567', onVerified: () {}),
    '08_phone_success': () => PhoneSuccessScreen(onContinue: () {}),
    '09_pin': () =>
        PinScreen(session: session, onContinue: () {}, onBack: () {}),
    '10_location': () => LocationPermissionScreen(
      service: services.location,
      onContinue: (_) {},
      onBack: () {},
    ),
    '11_citizen': () => RoleSelectionScreen(onContinue: (_) {}, onBack: () {}),
    '12_volunteer': () => RoleSelectionScreen(
      initialRole: UsageRole.volunteer,
      onContinue: (_) {},
      onBack: () {},
    ),
    '13_warning': () => VolunteerWarningScreen(
      service: services.volunteer,
      onSubmitted: (_) {},
      onBack: () {},
    ),
    '14_pending': () => const VolunteerPendingScreen(),
    '15_home': () => HomeScreen(hasLocation: true, onReport: () {}),
    '17_nearby_alert': () => HomeScreen(
      hasLocation: true,
      onReport: () {},
      incidentController: demoIncident(),
    ),
    '18_reporter_en_route': () => HomeScreen(
      hasLocation: true,
      onReport: () {},
      session: OnboardingSession()..phone = '0591111111',
      incidentController: demoIncident(accepted: true),
    ),
    '19_volunteer_route': () => HomeScreen(
      hasLocation: true,
      onReport: () {},
      session: OnboardingSession()..role = UsageRole.volunteer,
      incidentController: demoIncident(),
    ),
    '16_fire_camera': () => FireCameraScreen(
      services: services,
      session: session,
      onSubmitted: (_) {},
      onClose: () {},
    ),
  };

  for (final small in [false, true]) {
    testWidgets(
      'all frames: ${small ? '320px / large text / reduced motion' : '390px Figma size'}',
      (tester) async {
        final previousShadowSetting = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadowSetting);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = small
            ? const Size(320, 568)
            : const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final entry in pages.entries) {
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(entry.key),
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: AppTheme.light,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(small ? 1.5 : 1),
                  disableAnimations: small,
                  accessibleNavigation: small,
                ),
                child: RepaintBoundary(key: boundaryKey, child: child!),
              ),
              home: entry.value(),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
          await tester.runAsync(() async {
            final context = boundaryKey.currentContext!;
            await precacheImage(
              const AssetImage('assets/figma/shutter.png'),
              context,
            );
            if (!context.mounted) return;
            await precacheImage(
              const AssetImage('assets/figma/location_marker.png'),
              context,
            );
            if (!context.mounted) return;
            await precacheImage(MemoryImage(testPhoto), context);
          });
          await tester.pump();
          expect(tester.takeException(), isNull, reason: entry.key);
          if (!small && const bool.fromEnvironment('FIREPIN_VISUAL_QA')) {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('.dart_tool/visual_qa').create(recursive: true);
              await File(
                '.dart_tool/visual_qa/${entry.key}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        // Flutter checks paint flags before package:test tearDown callbacks.
        debugDisableShadows = previousShadowSetting;
      },
    );
  }
}
