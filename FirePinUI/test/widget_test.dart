import 'package:firepin_ui/app/firepin_app.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/core/ui/live_camera.dart';
import 'package:firepin_ui/features/account/account_screen.dart';
import 'package:firepin_ui/features/alerts/alerts_screen.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/incidents/incident_screen.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/permission_screens.dart';
import 'package:firepin_ui/features/onboarding/phone_pin_screens.dart';
import 'package:firepin_ui/features/onboarding/role_screens.dart';
import 'package:firepin_ui/features/welcome/welcome_screen.dart';
import 'package:firepin_ui/features/report/fire_camera_screen.dart';
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

Future<void> toPhoneNumber(WidgetTester tester) async {
  await tester.pump();
  await tapLabel(tester, 'إنشاء حساب جديد');
  await tapLabel(tester, 'السماح باستخدام الكاميرا');
  await tester.pump(const Duration(milliseconds: 100));
  await tapLabel(tester, 'التقاط الصورة');
  expect(find.text('جارٍ فحص الهوية'), findsWidgets);
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(IdentitySuccessScreen), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 2400));
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(IdentityReviewScreen), findsOneWidget);
  expect(find.text('تاريخ الانتهاء'), findsNothing);
  await tapLabel(tester, 'التالي');
  expect(find.byType(PhoneNumberScreen), findsOneWidget);
}

Future<void> toRoleSelection(WidgetTester tester) async {
  await toPhoneNumber(tester);
  await tester.enterText(
    find.byKey(const ValueKey('phone-number')),
    '0591234567',
  );
  await tapLabel(tester, 'متابعة');
  expect(find.byType(PinScreen), findsOneWidget);
  expect(find.byType(OtpScreen), findsNothing);
  expect(find.byType(PhoneSuccessScreen), findsNothing);
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
  testWidgets('Arabic welcome uses RTL and opens municipality login', (
    tester,
  ) async {
    mobileSize(tester);
    await tester.pumpWidget(FirePinApp(services: fakeServices()));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      Directionality.of(tester.element(find.byType(WelcomeScreen))),
      TextDirection.rtl,
    );
    expect(
      Localizations.localeOf(
        tester.element(find.byType(WelcomeScreen)),
      ).languageCode,
      'ar',
    );
    expect(find.text('إنشاء حساب موثّق'), findsOneWidget);
    await tapLabel(tester, 'دخول الجهة المسؤولة');
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera denial stays put and permanent denial opens settings', (
    tester,
  ) async {
    mobileSize(tester);
    final permissions = FakePermissions(result: DevicePermission.denied);
    await tester.pumpWidget(
      FirePinApp(services: fakeServices(permissions: permissions)),
    );
    await tester.pump();
    await tapLabel(tester, 'إنشاء حساب جديد');
    await tapLabel(tester, 'السماح باستخدام الكاميرا');
    expect(find.byType(CameraPermissionScreen), findsOneWidget);
    expect(find.byType(IdentityCaptureScreen), findsNothing);
    permissions.result = DevicePermission.permanentlyDenied;
    await tapLabel(tester, 'السماح باستخدام الكاميرا');
    await tapLabel(tester, 'فتح إعدادات التطبيق');
    expect(permissions.settingsOpened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid phone bypasses OTP and Back returns from PIN to phone', (
    tester,
  ) async {
    mobileSize(tester);
    final otp = TrackingOtpService();
    await tester.pumpWidget(FirePinApp(services: fakeServices(otp: otp)));
    await toPhoneNumber(tester);
    await tester.enterText(
      find.byKey(const ValueKey('phone-number')),
      '٠٥٩١٢٣٤٥٦٧',
    );
    await tapLabel(tester, 'متابعة');
    expect(find.byType(PinScreen), findsOneWidget);
    expect(find.byType(OtpScreen), findsNothing);
    expect(find.byType(PhoneSuccessScreen), findsNothing);
    expect(otp.sends, 0);
    expect(otp.verifications, 0);

    await tester.tap(find.byKey(const ValueKey('onboarding-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(PhoneNumberScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('phone-number')))
          .controller!
          .text,
      '0591234567',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'citizen completes onboarding and submits a camera-only local report',
    (tester) async {
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
      await toRoleSelection(tester);
      await tapLabel(tester, 'متابعة');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      await tapLabel(tester, '🔥 إبلاغ عن حريق');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.light,
      );
      final shutter = find.byKey(const ValueKey('fire-shutter'));
      expect(tester.widget<InkWell>(shutter).onTap, isNotNull);
      await tester.tap(shutter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(reports.submissions, 1);
      expect(reports.hasPhoto, isTrue);
      expect(find.text('تأكيد رمز الدخول'), findsNothing);
      expect(location.requests, 2);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(camera.opened, isFalse);
    },
  );

  testWidgets(
    'volunteer can return to selection and pending retains citizen access',
    (tester) async {
      mobileSize(tester);
      await tester.pumpWidget(FirePinApp(services: fakeServices()));
      await toRoleSelection(tester);
      await tapLabel(tester, 'تقديم طلب للانضمام كمتطوع');
      await tapLabel(tester, 'متابعة');
      expect(find.byType(VolunteerWarningScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(RoleSelectionScreen), findsOneWidget);
      await tapLabel(tester, 'متابعة');
      await tapLabel(tester, 'تأكيد وإرسال طلب التطوع');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(HomeScreen), findsOneWidget);
      await tapLabel(tester, 'الحساب');
      expect(find.textContaining('طلب تطوع قيد المراجعة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIN mismatch keeps original PIN, clears confirmation and allows retry',
    (tester) async {
      mobileSize(tester);
      final session = OnboardingSession();
      var continued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PinScreen(
              session: session,
              onContinue: () => continued = true,
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('رمز الدخول')), '0123');
      await tester.enterText(
        find.byKey(const ValueKey('تأكيد رمز الدخول')),
        '4567',
      );
      await tapLabel(tester, 'حفظ رمز الدخول');
      expect(continued, isFalse);
      expect(session.hasPin, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('تأكيد رمز الدخول')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('تأكيد رمز الدخول')),
        '0123',
      );
      await tapLabel(tester, 'حفظ رمز الدخول');
      expect(continued, isTrue);
      expect(session.hasPin, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small phone and large text remain scrollable and actionable', (
    tester,
  ) async {
    mobileSize(tester, size: const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(FirePinApp(services: fakeServices()));
    await tester.pump();
    await tapLabel(tester, 'إنشاء حساب جديد');
    expect(find.byType(CameraPermissionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone submit remains reachable with a keyboard on a small phone',
    (tester) async {
      mobileSize(tester, size: const Size(320, 568));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      String? sentPhone;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PhoneNumberScreen(onContinue: (phone) => sentPhone = phone),
          ),
        ),
      );
      final input = find.byKey(const ValueKey('phone-number'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '٠٥٩١٢٣٤٥٦٧');
      await tapLabel(tester, 'متابعة');
      expect(sentPhone, '0591234567');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('OTP error can be corrected after a resend resets the cells', (
    tester,
  ) async {
    mobileSize(tester);
    final otp = fakeServices().otp;
    await tester.runAsync(() => otp.send('0591234567'));
    var verified = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: OtpScreen(
            otp: otp,
            phone: '0591234567',
            onVerified: () => verified = true,
          ),
        ),
      ),
    );
    final input = find.byKey(const ValueKey('رمز التحقق'));
    await tester.enterText(input, '000000');
    await tapLabel(tester, 'تحقق');
    expect(verified, isFalse);
    expect(find.text('الرمز غير صحيح. تحقق منه وحاول مجددًا.'), findsOneWidget);
    await tapLabel(tester, 'إعادة إرسال الرمز');
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await tester.enterText(input, '123456');
    await tapLabel(tester, 'تحقق');
    expect(verified, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location denial can open settings or continue without a fix', (
    tester,
  ) async {
    mobileSize(tester);
    final location = FakeLocation()
      ..failure = LocationProblem.permanentlyDenied;
    var continued = false;
    LocationFix? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LocationPermissionScreen(
            service: location,
            onContinue: (fix) {
              continued = true;
              result = fix;
            },
          ),
        ),
      ),
    );
    await tapLabel(tester, 'السماح بالوصول إلى الموقع');
    expect(continued, isFalse);
    await tapLabel(tester, 'فتح الإعدادات');
    expect(location.settingsOpened, 1);
    await tapLabel(tester, 'ليس الآن');
    expect(continued, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no-photo report requires the correct PIN before location and submission',
    (tester) async {
      mobileSize(tester);
      final location = FakeLocation()..failure = LocationProblem.denied;
      final reports = FakeReports();
      var submitted = false;
      final services = fakeServices(
        permissions: FakePermissions(result: DevicePermission.denied),
        location: location,
        reports: reports,
      );
      await services.authController.loginUser(
        DemoAuthRepository.citizenNationalId,
        DemoAuthRepository.citizenPin,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: FireCameraScreen(
              services: services,
              session: OnboardingSession(),
              onSubmitted: (_) => submitted = true,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tapLabel(tester, 'إرسال البلاغ بدون صورة');
      expect(find.text('تأكيد رمز الدخول'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('رمز تأكيد البلاغ')))
            .obscureText,
        isTrue,
      );
      expect(reports.submissions, 0);
      expect(location.requests, 0);
      expect(submitted, isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('رمز تأكيد البلاغ')),
        '9999',
      );
      await tapLabel(tester, 'تأكيد الإرسال');
      expect(find.text('رمز الدخول غير صحيح. حاول مجددًا.'), findsOneWidget);
      expect(reports.submissions, 0);
      expect(location.requests, 0);

      await tester.enterText(
        find.byKey(const ValueKey('رمز تأكيد البلاغ')),
        DemoAuthRepository.citizenPin,
      );
      await tapLabel(tester, 'تأكيد الإرسال');
      expect(reports.submissions, 0);
      expect(submitted, isFalse);
      expect(location.requests, 1);

      location.failure = null;
      await tapLabel(tester, 'إرسال البلاغ بدون صورة');
      await tester.enterText(
        find.byKey(const ValueKey('رمز تأكيد البلاغ')),
        DemoAuthRepository.citizenPin,
      );
      await tapLabel(tester, 'تأكيد الإرسال');
      expect(reports.submissions, 1);
      expect(reports.hasPhoto, isFalse);
      expect(submitted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'citizen alerts, acknowledgement and account are distinct views',
    (tester) async {
      mobileSize(tester);
      final session = OnboardingSession()
        ..role = UsageRole.citizen
        ..phone = '0591234567';
      final incidents = IncidentController()
        ..report(
          location: const LocationFix(31.78, 35.24, 10),
          reporterPhone: '0590000000',
          photo: testPhoto,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HomeScreen(
              hasLocation: true,
              onReport: () {},
              session: session,
              incidentController: incidents,
            ),
          ),
        ),
      );
      await tapLabel(tester, 'التنبيهات');
      expect(find.byType(AlertsScreen), findsOneWidget);
      expect(find.textContaining('حادث نشط الآن'), findsOneWidget);
      await tapLabel(tester, 'عرض على الخريطة');
      expect(find.byType(IncidentScreen), findsOneWidget);
      expect(find.text('تنبيه حريق قريب'), findsOneWidget);
      await tapLabel(tester, 'تم الاطلاع');
      expect(find.text('تم إيقاف التنبيه'), findsOneWidget);
      await tapLabel(tester, 'الحساب');
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('استخدام التطبيق كمواطن'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('volunteer call advances to active response', (tester) async {
    mobileSize(tester);
    final session = OnboardingSession()..role = UsageRole.volunteer;
    final incidents = IncidentController()
      ..report(
        location: const LocationFix(31.78, 35.24, 10),
        reporterPhone: '0591234567',
        photo: testPhoto,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            hasLocation: true,
            onReport: () {},
            session: session,
            incidentController: incidents,
          ),
        ),
      ),
    );
    await tapLabel(tester, 'التنبيهات');
    expect(find.text('نداء حريق جديد'), findsWidgets);
    await tapLabel(tester, 'عرض الحادث');
    expect(find.text('نداء حريق جديد'), findsOneWidget);
    await tapLabel(tester, 'تلبية النداء');
    expect(find.text('أنت تستجيب لهذا البلاغ'), findsOneWidget);
    expect(find.text('استجابة نشطة'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tapLabel(tester, 'الحساب');
    expect(find.text('✓ متطوع معتمد'), findsOneWidget);
    expect(find.text('استجابة نشطة · أنت في الطريق'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reporter status progresses to volunteer incoming', (
    tester,
  ) async {
    mobileSize(tester);
    final session = OnboardingSession()..phone = '0591234567';
    final incidents = IncidentController()
      ..report(
        location: const LocationFix(31.78, 35.24, 10),
        reporterPhone: session.phone,
        photo: testPhoto,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            hasLocation: true,
            onReport: () {},
            session: session,
            incidentController: incidents,
          ),
        ),
      ),
    );
    expect(find.text('تم استلام البلاغ'), findsOneWidget);
    expect(find.text('جارٍ البحث'), findsOneWidget);
    incidents.acceptByVolunteer();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('متطوع في الطريق إليك'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tapLabel(tester, 'رؤية الصورة المرسلة');
    expect(find.text('الصورة المرسلة'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
