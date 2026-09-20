import 'dart:io';
import 'dart:ui' as ui;
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/municipality_selection_screen.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
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
    address: 'القدس — الطور',
  );
  final citizenSession = OnboardingSession()
    ..accountId = 'user-citizen'
    ..identity = identity
    ..phone = '0591234567';
  final volunteerSession = OnboardingSession()
    ..accountId = 'user-volunteer'
    ..identity = identity
    ..phone = '0592223344'
    ..role = UsageRole.volunteer;

  final pages = <String, Widget Function()>{
    '01_welcome': () => WelcomeScreen(onStart: () {}),
    '02_identity_details': () =>
        IdentityDetailsScreen(onContinue: (_) {}, onBack: () {}),
    '03_phone': () => PhoneNumberScreen(onContinue: (_) {}, onBack: () {}),
    '04_pin': () =>
        PinScreen(session: session, onContinue: () {}, onBack: () {}),
    '05_citizen': () => RoleSelectionScreen(onContinue: (_) {}, onBack: () {}),
    '06_volunteer': () => RoleSelectionScreen(
      initialRole: UsageRole.volunteer,
      onContinue: (_) {},
      onBack: () {},
    ),
    '07_municipality_selection': () => MunicipalitySelectionScreen(
      repository: FakeMunicipalityDirectoryRepository(),
      onContinue: (_) {},
      onBack: () {},
    ),
    '08_warning': () => VolunteerWarningScreen(
      service: services.volunteer,
      municipalityId: 101,
      onSubmitted: (_) async {},
      onBack: () {},
    ),
    '09_pending': () => const VolunteerPendingScreen(),
    '10_citizen_home': () => HomeScreen(
      onReport: (_) {},
      session: citizenSession,
      onLogout: () async {},
      reportRepository: services.reportRepository,
      location: services.location,
    ),
    '11_volunteer_home': () => HomeScreen(
      onReport: (_) {},
      session: volunteerSession,
      onLogout: () async {},
      reportRepository: services.reportRepository,
      location: services.location,
    ),
    '12_fire_camera': () => FireCameraScreen(
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
