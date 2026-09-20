import 'package:firepin_ui/app/firepin_app.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/auth/login_screens.dart';
import 'package:firepin_ui/features/home/home_screen.dart';
import 'package:firepin_ui/features/municipality/municipality_dashboard.dart';
import 'package:firepin_ui/features/welcome/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('startup gate restores a citizen session directly to Home', (
    tester,
  ) async {
    final sessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.user);
    await tester.pumpWidget(
      FirePinApp(services: fakeServices(sessions: sessions)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('🔥 إبلاغ عن حريق'), findsOneWidget);
  });

  testWidgets('national ID login succeeds and invalid login stays inline', (
    tester,
  ) async {
    await tester.pumpWidget(FirePinApp(services: fakeServices()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tapText(tester, 'تسجيل الدخول');
    expect(find.byType(UserLoginScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('login-national-id')),
      '123456789',
    );
    await tester.enterText(find.byKey(const ValueKey('login-pin')), '9999');
    await tapText(tester, 'تسجيل الدخول');
    expect(find.byKey(const ValueKey('user-login-error')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('login-pin')), '1234');
    await tapText(tester, 'تسجيل الدخول');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('user logout clears session and returns to entry', (
    tester,
  ) async {
    final sessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.user);
    await tester.pumpWidget(
      FirePinApp(services: fakeServices(sessions: sessions)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tapText(tester, 'الحساب');
    await tapText(tester, 'تسجيل الخروج');
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(sessions.value, isNull);
  });

  testWidgets('municipality login opens responsive operational dashboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final services = fakeServices();
    await tester.pumpWidget(FirePinApp(services: services));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tapText(tester, 'دخول الجهة المسؤولة');
    expect(find.byType(MunicipalityLoginScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('municipality-email')),
      DemoMunicipalityAuthRepository.demoEmail,
    );
    await tester.enterText(
      find.byKey(const ValueKey('municipality-password')),
      DemoMunicipalityAuthRepository.demoPassword,
    );
    await tapText(tester, 'تسجيل الدخول');
    expect(find.byType(MunicipalityDashboard), findsOneWidget);
    expect(find.text('الحرائق النشطة'), findsOneWidget);
    expect(find.text('FP-1042'), findsWidgets);

    await tapText(tester, 'طلبات التطوع');
    expect(find.text('سارة محمود خليل'), findsOneWidget);
    await tapText(tester, 'قبول');
    await tapText(tester, 'مقبول');
    expect(find.text('سارة محمود خليل'), findsOneWidget);

    await tapText(tester, 'المتطوعون');
    expect(find.text('ليان أحمد صالح'), findsOneWidget);
    expect(find.text('سارة محمود خليل'), findsOneWidget);

    await tapText(tester, 'السجل');
    expect(find.textContaining('FP-1037'), findsOneWidget);

    await tapText(tester, 'الحساب');
    await tapText(tester, 'تسجيل الخروج');
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('municipality dashboard uses compact navigation on mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final sessions = MemorySessionRepository()
      ..value = const StoredSession(principal: AuthPrincipal.municipality);
    await tester.pumpWidget(
      FirePinApp(services: fakeServices(sessions: sessions)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MunicipalityDashboard), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
