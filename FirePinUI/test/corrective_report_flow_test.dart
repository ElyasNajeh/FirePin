import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/app/firepin_app.dart';
import 'package:firepin_ui/core/services/device_services.dart';
import 'package:firepin_ui/core/ui/components.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/onboarding/identity_screens.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/report/fire_camera_screen.dart';
import 'package:firepin_ui/features/report/fire_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void _mobileSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

OnboardingSession _citizenSession() => OnboardingSession()
  ..accountId = 'citizen-1'
  ..identity = const IdentityData(
    fullName: 'أحمد محمد عبد الله',
    identityNumber: '123456789',
    birthDate: '14 / 05 / 1998',
    address: '',
  )
  ..phone = '0591234567';

void main() {
  testWidgets(
    'registration starts with manual identity and never opens camera',
    (tester) async {
      _mobileSize(tester);
      final permissions = FakePermissions();
      final camera = FakeCamera();
      await tester.pumpWidget(
        FirePinApp(
          services: fakeServices(permissions: permissions, camera: camera),
        ),
      );
      await tester.pump();
      await _tapText(tester, 'إنشاء حساب جديد');

      expect(find.byType(IdentityDetailsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('identity-full-name')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('identity-national-id')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('identity-birth-date')), findsOneWidget);
      expect(permissions.requests, 0);
      expect(camera.captures, 0);
    },
  );

  testWidgets('citizen sees real GPS marker before report is enabled', (
    tester,
  ) async {
    _mobileSize(tester);
    final location = DeferredLocation();
    LocationFix? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          session: _citizenSession(),
          reportRepository: FakeReports(),
          location: location,
          onReport: (value) => selected = value,
          onLogout: () async {},
        ),
      ),
    );

    expect(find.text('جارٍ تحديد موقعك الحقيقي...'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('create-fire-report')))
          .onPressed,
      isNull,
    );

    const fix = LocationFix(31.901234, 35.201234, 6);
    location.complete(fix);
    await tester.pump();
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.byKey(const ValueKey('citizen-current-location-marker')),
      findsOneWidget,
    );
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, fix.latitude);
    expect(map.options.initialCenter.longitude, fix.longitude);

    await _tapText(tester, '🔥 إبلاغ عن حريق');
    expect(selected, same(fix));
  });

  testWidgets(
    'location failure has retry and never uses fallback coordinates',
    (tester) async {
      _mobileSize(tester);
      final location = FakeLocation()..failure = LocationProblem.denied;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            session: _citizenSession(),
            reportRepository: FakeReports(),
            location: location,
            onReport: (_) => fail('Report must remain unavailable'),
            onLogout: () async {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('citizen-location-error')),
        findsOneWidget,
      );
      expect(find.byType(FlutterMap), findsNothing);
      location.failure = null;
      await _tapText(tester, 'إعادة المحاولة');
      await tester.pump();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(location.requests, 2);
    },
  );

  testWidgets('camera captures at most five images then submits without PIN', (
    tester,
  ) async {
    _mobileSize(tester);
    final camera = FakeCamera();
    final reports = FakeReports();
    final location = FakeLocation();
    FireReport? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: FireCameraScreen(
          services: fakeServices(
            camera: camera,
            reports: reports,
            location: location,
          ),
          session: _citizenSession()
            ..location = const LocationFix(31.78, 35.24, 8),
          onSubmitted: (report) => submitted = report,
          onClose: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('المعرض'), findsNothing);
    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byKey(const ValueKey('fire-shutter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(camera.captures, 5);
    expect(find.text('الصور 5/5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fire-shutter')));
    await tester.pump();
    expect(camera.captures, 5);
    expect(reports.submissions, 0);

    await _tapText(tester, 'إرسال البلاغ بالصور');
    expect(reports.submissions, 1);
    expect(reports.imageCount, 5);
    expect(reports.pin, isNull);
    expect(reports.submittedLocation?.latitude, 31.78);
    expect(submitted?.id, FakeReports.report.id);
  });

  testWidgets('no-image PIN is verified by backend-facing repository', (
    tester,
  ) async {
    _mobileSize(tester);
    final reports = PinCheckingReports();
    FireReport? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: FireCameraScreen(
          services: fakeServices(reports: reports, location: FakeLocation()),
          session: _citizenSession()
            ..location = const LocationFix(31.78, 35.24, 8),
          onSubmitted: (report) => submitted = report,
          onClose: () {},
        ),
      ),
    );
    await tester.pump();

    await _tapText(tester, 'إرسال البلاغ بدون صورة');
    await tester.enterText(
      find.byKey(const ValueKey('رمز تأكيد البلاغ')),
      '9999',
    );
    await _tapText(tester, 'تأكيد الإرسال');
    expect(reports.receivedPins, ['9999']);
    expect(reports.submissions, 0);
    expect(
      find.text('رمز الدخول غير صحيح. لم يتم إرسال البلاغ.'),
      findsOneWidget,
    );

    await _tapText(tester, 'إرسال البلاغ بدون صورة');
    await tester.enterText(
      find.byKey(const ValueKey('رمز تأكيد البلاغ')),
      '1234',
    );
    await _tapText(tester, 'تأكيد الإرسال');
    expect(reports.receivedPins, ['9999', '1234']);
    expect(reports.submissions, 1);
    expect(reports.imageCount, 0);
    expect(submitted?.id, FakeReports.report.id);
  });
}

class DeferredLocation extends FakeLocation {
  final _completer = Completer<LocationFix>();

  void complete(LocationFix location) => _completer.complete(location);

  @override
  Future<LocationFix> requestCurrentPosition() {
    requests++;
    return _completer.future;
  }
}

class PinCheckingReports extends FakeReports {
  final List<String?> receivedPins = [];

  @override
  Future<FireReport> submit({
    required List<Uint8List> images,
    String? pin,
    required LocationFix location,
  }) async {
    receivedPins.add(pin);
    if (images.isEmpty && pin != DemoAuthRepository.citizenPin) {
      final options = RequestOptions(path: '/fire-reports');
      throw DioException(
        requestOptions: options,
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 422,
          data: {'detail': 'PIN verification failed'},
        ),
      );
    }
    return super.submit(images: images, pin: pin, location: location);
  }
}
