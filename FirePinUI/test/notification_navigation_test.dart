import 'dart:async';

import 'package:firepin_ui/app/app_services.dart';
import 'package:firepin_ui/app/firepin_app.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/municipality/municipality_dashboard.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/notifications/notification_service.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/report/fire_report_repository.dart';
import 'package:firepin_ui/features/report/fire_reports_screen.dart';
import 'package:firepin_ui/features/welcome/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  test('notification service emits one canonical tap event', () async {
    final service = FirePinNotificationService();
    final event = service.reportTaps.first;
    service.handleReportTapForTest(
      reportId: '091',
      type: 'fire_report_created',
      messageId: 'canonical-91',
    );
    expect(await event, '91');
    await service.dispose();
  });

  testWidgets('foreground citizen notification opens its real report', (
    tester,
  ) async {
    final fixture = NotificationNavigationFixture();
    await fixture.pumpUser(tester);

    fixture.notifications.handleReportTapForTest(
      reportId: 91,
      type: 'fire_report_claimed',
      messageId: 'citizen-91',
    );
    await fixture.pumpNavigation(tester);

    expect(fixture.reports.myDetailLoads, 1);
    expect(fixture.reports.volunteerDetailLoads, 0);
    expect(find.byType(FireReportDetailScreen), findsOneWidget);
  });

  testWidgets('foreground volunteer notification uses volunteer endpoint', (
    tester,
  ) async {
    final fixture = NotificationNavigationFixture();
    await fixture.users.loginUser(
      nationalId: DemoAuthRepository.volunteerNationalId,
      pin: DemoAuthRepository.volunteerPin,
    );
    await fixture.pumpUser(tester);

    fixture.notifications.handleReportTapForTest(
      reportId: 91,
      type: 'fire_report_created',
      messageId: 'volunteer-91',
    );
    await fixture.pumpNavigation(tester);

    expect(fixture.reports.myDetailLoads, 0);
    expect(fixture.reports.volunteerDetailLoads, 1);
    expect(find.byType(FireReportDetailScreen), findsOneWidget);
  });

  testWidgets('municipality notification opens a read-only real report', (
    tester,
  ) async {
    final fixture = NotificationNavigationFixture();
    await fixture.pumpMunicipality(tester);

    fixture.notifications.handleReportTapForTest(
      reportId: 1042,
      type: 'fire_report_created',
      messageId: 'municipality-1042',
    );
    await fixture.pumpNavigation(tester);

    expect(fixture.operations.detailLoads, 1);
    expect(find.byType(MunicipalityReportDetailsDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-fire-report')), findsNothing);
    expect(find.byKey(const ValueKey('resolve-fire-report')), findsNothing);
  });

  testWidgets('terminated-state tap waits for authentication restoration', (
    tester,
  ) async {
    final fixture = NotificationNavigationFixture();
    final restoreGate = Completer<void>();
    final users = DelayedAuthRepository(fixture.users, restoreGate.future);
    fixture.notifications.setInitialReportTapForTest(
      reportId: 91,
      type: 'fire_report_resolved',
      messageId: 'initial-91',
    );
    await fixture.pumpUser(tester, users: users, settle: false);

    expect(fixture.reports.myDetailLoads, 0);
    restoreGate.complete();
    await fixture.pumpNavigation(tester);

    expect(fixture.reports.myDetailLoads, 1);
    expect(find.byType(FireReportDetailScreen), findsOneWidget);
  });

  testWidgets('malformed and duplicate notification taps are safe', (
    tester,
  ) async {
    final fixture = NotificationNavigationFixture();
    await fixture.pumpUser(tester);

    fixture.notifications.handleReportTapForTest(
      reportId: 'not-an-id',
      messageId: 'malformed',
    );
    fixture.notifications.handleReportTapForTest(
      reportId: 91,
      type: 'fire_report_claimed',
      messageId: 'same-message',
    );
    fixture.notifications.handleReportTapForTest(
      reportId: 91,
      type: 'fire_report_claimed',
      messageId: 'same-message',
    );
    await fixture.pumpNavigation(tester);

    expect(fixture.reports.myDetailLoads, 1);
    expect(find.byType(FireReportDetailScreen), findsOneWidget);
  });

  testWidgets('expired session while opening a notification signs out', (
    tester,
  ) async {
    final fixture = NotificationNavigationFixture()..reports.expire = true;
    await fixture.pumpUser(tester);

    fixture.notifications.handleReportTapForTest(
      reportId: 91,
      messageId: 'expired-91',
    );
    await fixture.pumpNavigation(tester);

    expect(fixture.sessions.value, isNull);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}

class NotificationNavigationFixture {
  final notifications = FirePinNotificationService();
  final users = DemoAuthRepository();
  final municipalities = DemoMunicipalityAuthRepository();
  final sessions = MemorySessionRepository();
  final reports = RecordingReportRepository();
  final operations = RecordingMunicipalityRepository();

  Future<void> pumpUser(
    WidgetTester tester, {
    AuthRepository? users,
    bool settle = true,
  }) async {
    sessions.value = const StoredSession(principal: AuthPrincipal.user);
    await _pump(tester, users: users ?? this.users, settle: settle);
  }

  Future<void> pumpMunicipality(WidgetTester tester) async {
    sessions.value = const StoredSession(principal: AuthPrincipal.municipality);
    await _pump(tester, users: users);
  }

  Future<void> _pump(
    WidgetTester tester, {
    required AuthRepository users,
    bool settle = true,
  }) async {
    final services = AppServices(
      permissions: FakePermissions(),
      location: FakeLocation(),
      camera: FakeCamera.new,
      reports: reports,
      reportRepository: reports,
      volunteer: FakeVolunteerApplicationService(),
      municipalityDirectory: FakeMunicipalityDirectoryRepository(),
      operations: operations,
      auth: users,
      municipalityAuth: municipalities,
      sessions: sessions,
      notifications: notifications,
    );
    await tester.pumpWidget(FirePinApp(services: services));
    await tester.pump();
    if (settle) await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpNavigation(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }
}

class RecordingReportRepository extends FakeReports {
  int myDetailLoads = 0;
  int volunteerDetailLoads = 0;
  bool expire = false;

  @override
  Future<FireReport> getMyReport(int reportId) async {
    myDetailLoads++;
    if (expire) throw const AuthenticationException('expired');
    return FakeReports.report;
  }

  @override
  Future<FireReport> getVolunteerReport(int reportId) async {
    volunteerDetailLoads++;
    if (expire) throw const AuthenticationException('expired');
    return FakeReports.report;
  }
}

class RecordingMunicipalityRepository
    extends FakeMunicipalityOperationsRepository {
  int detailLoads = 0;

  @override
  Future<MunicipalityFireReport> getReport(int reportId) async {
    detailLoads++;
    return super.getReport(reportId);
  }
}

class DelayedAuthRepository implements AuthRepository {
  DelayedAuthRepository(this.delegate, this.gate);
  final AuthRepository delegate;
  final Future<void> gate;

  @override
  Future<UserAccount> restoreUser() async {
    await gate;
    return delegate.restoreUser();
  }

  @override
  Future<void> clearLocalSession() => delegate.clearLocalSession();
  @override
  Future<UserLoginResult> loginUser({
    required String nationalId,
    required String pin,
  }) => delegate.loginUser(nationalId: nationalId, pin: pin);
  @override
  Future<void> logoutUser() => delegate.logoutUser();
  @override
  Future<UserLoginResult> registerUser(OnboardingSession session) =>
      delegate.registerUser(session);
  @override
  Future<bool> verifyUserPin({required String userId, required String pin}) =>
      delegate.verifyUserPin(userId: userId, pin: pin);
}
