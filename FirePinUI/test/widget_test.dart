import 'package:firepin_ui/app/firepin_app.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/core/ui/live_camera.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/permission_screens.dart';
import 'package:firepin_ui/features/onboarding/phone_pin_screens.dart';
import 'package:firepin_ui/features/onboarding/role_screens.dart';
import 'package:firepin_ui/features/report/fire_camera_screen.dart';
import 'package:firepin_ui/features/welcome/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

Future<void> tapLabel(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void mobileSize(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> enterIdentity(WidgetTester tester) async {
  await tester.pump();
  await tapLabel(tester, 'إنشاء حساب جديد');
  expect(find.byType(CameraPermissionScreen), findsOneWidget);
  await tapLabel(tester, 'السماح باستخدام الكاميرا');
  await tester.pump();
  expect(find.byType(IdentityCaptureScreen), findsOneWidget);
  await tapLabel(tester, 'التقاط الهوية');
  expect(find.byType(IdentityDetailsScreen), findsOneWidget);
  await tapLabel(tester, 'متابعة');
  expect(find.byType(PhoneNumberScreen), findsOneWidget);
}

Future<void> reachRoleSelection(WidgetTester tester) async {
  await enterIdentity(tester);
  await tester.enterText(
    find.byKey(const ValueKey('phone-number')),
    '0591234567',
  );
  await tapLabel(tester, 'متابعة');
  await tester.enterText(find.byKey(const ValueKey('رمز الدخول')), '0123');
  await tester.enterText(
    find.byKey(const ValueKey('تأكيد رمز الدخول')),
    '0123',
  );
  await tapLabel(tester, 'حفظ رمز الدخول');
  await tapLabel(tester, 'السماح بالوصول إلى الموقع');
  expect(find.byType(RoleSelectionScreen), findsOneWidget);
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await loader.load();
  });

  testWidgets('Arabic welcome is RTL and opens municipality login', (
    tester,
  ) async {
    mobileSize(tester);
    await tester.pumpWidget(FirePinApp(services: fakeServices()));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      Directionality.of(tester.element(find.byType(WelcomeScreen))),
      TextDirection.rtl,
    );
    await tapLabel(tester, 'دخول الجهة المسؤولة');
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual identity rejects invalid data and accepts real fields', (
    tester,
  ) async {
    mobileSize(tester);
    IdentityData? result;
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityDetailsScreen(onContinue: (value) => result = value),
      ),
    );
    await tapLabel(tester, 'متابعة');
    expect(result, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('identity-full-name')),
      'أحمد محمد',
    );
    await tester.enterText(
      find.byKey(const ValueKey('identity-national-id')),
      '١٢٣٤٥٦٧٨٩',
    );
    await tester.enterText(
      find.byKey(const ValueKey('identity-birth-date')),
      '14/05/1998',
    );
    await tapLabel(tester, 'متابعة');
    expect(result?.identityNumber, '123456789');
    expect(result?.fullName, 'أحمد محمد');
  });

  testWidgets('citizen completes onboarding and submits a photo report', (
    tester,
  ) async {
    mobileSize(tester);
    final reports = FakeReports();
    final camera = FakeCamera();
    final location = FakeLocation();
    await tester.pumpWidget(
      FirePinApp(
        services: fakeServices(
          camera: camera,
          reports: reports,
          location: location,
        ),
      ),
    );
    await reachRoleSelection(tester);
    await tapLabel(tester, 'متابعة');
    expect(find.byType(HomeScreen), findsOneWidget);
    await tapLabel(tester, '🔥 إبلاغ عن حريق');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fire-shutter')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(reports.submissions, 1);
    expect(reports.hasPhoto, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(camera.opened, isFalse);
  });

  testWidgets('PIN mismatch clears confirmation and allows retry', (
    tester,
  ) async {
    final session = OnboardingSession();
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PinScreen(session: session, onContinue: () => continued = true),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('رمز الدخول')), '0123');
    await tester.enterText(
      find.byKey(const ValueKey('تأكيد رمز الدخول')),
      '4567',
    );
    await tapLabel(tester, 'حفظ رمز الدخول');
    expect(continued, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('تأكيد رمز الدخول')),
      '0123',
    );
    await tapLabel(tester, 'حفظ رمز الدخول');
    expect(continued, isTrue);
  });

  testWidgets('location denial can open settings or continue without a fix', (
    tester,
  ) async {
    final location = FakeLocation()
      ..failure = LocationProblem.permanentlyDenied;
    LocationFix? result;
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LocationPermissionScreen(
          service: location,
          onContinue: (fix) {
            result = fix;
            continued = true;
          },
        ),
      ),
    );
    await tapLabel(tester, 'السماح بالوصول إلى الموقع');
    await tapLabel(tester, 'فتح الإعدادات');
    await tapLabel(tester, 'ليس الآن');
    expect(location.settingsOpened, 1);
    expect(continued, isTrue);
    expect(result, isNull);
  });

  testWidgets('camera closes on background and reopens on resume', (
    tester,
  ) async {
    final camera = FakeCamera();
    await tester.pumpWidget(
      MaterialApp(home: LiveCamera(factory: () => camera)),
    );
    await tester.pump();
    expect(camera.opened, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(camera.opened, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.opened, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(camera.opened, isFalse);
  });

  testWidgets('no-photo report verifies PIN and forwards a real location', (
    tester,
  ) async {
    mobileSize(tester);
    final location = FakeLocation();
    final reports = FakeReports();
    final services = fakeServices(location: location, reports: reports);
    await services.authController.loginUser(
      DemoAuthRepository.citizenNationalId,
      DemoAuthRepository.citizenPin,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FireCameraScreen(
          services: services,
          session: OnboardingSession(),
          onSubmitted: (_) {},
          onClose: () {},
        ),
      ),
    );
    await tester.pump();
    await tapLabel(tester, 'إرسال البلاغ بدون صورة');
    await tester.enterText(
      find.byKey(const ValueKey('رمز تأكيد البلاغ')),
      DemoAuthRepository.citizenPin,
    );
    await tapLabel(tester, 'تأكيد الإرسال');
    expect(reports.submissions, 1);
    expect(reports.hasPhoto, isFalse);
    expect(reports.pin, DemoAuthRepository.citizenPin);
    expect(location.requests, 1);
  });
}
