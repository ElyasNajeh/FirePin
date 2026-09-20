import 'package:firepin_ui/features/auth/auth_controller.dart';
import 'package:firepin_ui/features/auth/auth_models.dart';
import 'package:firepin_ui/features/auth/auth_repositories.dart';
import 'package:firepin_ui/features/incidents/incident_controller.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late IncidentController incidents;
  late LocalMunicipalityRepository operations;
  late DemoAuthRepository users;
  late DemoMunicipalityAuthRepository municipalities;
  late MemorySessionRepository sessions;
  late AuthController auth;

  setUp(() {
    incidents = IncidentController();
    operations = LocalMunicipalityRepository(incidents: incidents);
    users = DemoAuthRepository(operations);
    municipalities = DemoMunicipalityAuthRepository();
    sessions = MemorySessionRepository();
    auth = AuthController(
      users: users,
      municipalities: municipalities,
      sessions: sessions,
    );
  });

  tearDown(() {
    operations.dispose();
    incidents.dispose();
    auth.dispose();
  });

  test('national ID and product PIN validation is exact', () {
    expect(isValidNationalId('123456789'), isTrue);
    expect(isValidNationalId('١٢٣٤٥٦٧٨٩'), isTrue);
    expect(isValidNationalId('12345678'), isFalse);
    expect(isValidNationalId('1234567890'), isFalse);
    expect(isValidLoginPin('0123'), isTrue);
    expect(isValidLoginPin('123'), isFalse);
    expect(isValidLoginPin('12345'), isFalse);
    expect(isValidLoginPin('12a4'), isFalse);
  });

  test('user login succeeds and persists a restorable session', () async {
    await auth.loginUser(
      DemoAuthRepository.citizenNationalId,
      DemoAuthRepository.citizenPin,
    );
    expect(auth.status, AuthStatus.user);
    expect(auth.user!.role, UsageRole.citizen);
    expect((await sessions.read())!.principal, AuthPrincipal.user);

    final restored = AuthController(
      users: users,
      municipalities: municipalities,
      sessions: sessions,
    );
    await restored.restore();
    expect(restored.status, AuthStatus.user);
    expect(restored.user!.nationalId, DemoAuthRepository.citizenNationalId);
    restored.dispose();
  });

  test('invalid user login returns an Arabic product error', () async {
    await expectLater(
      auth.loginUser(DemoAuthRepository.citizenNationalId, '9999'),
      throwsA(isA<AuthFailure>()),
    );
    expect(auth.status, AuthStatus.signedOut);
    expect(await sessions.read(), isNull);
  });

  test('current user PIN verification uses the active account', () async {
    expect(await auth.verifyCurrentUserPin('1234'), isFalse);
    await auth.loginUser(
      DemoAuthRepository.citizenNationalId,
      DemoAuthRepository.citizenPin,
    );
    expect(
      await auth.verifyCurrentUserPin(DemoAuthRepository.citizenPin),
      isTrue,
    );
    expect(await auth.verifyCurrentUserPin('9999'), isFalse);
    expect(await auth.verifyCurrentUserPin('123'), isFalse);
  });

  test(
    'demo citizens authenticate independently without volunteer access',
    () async {
      final first = await users.loginUser(
        nationalId: DemoAuthRepository.citizenNationalId,
        pin: DemoAuthRepository.citizenPin,
      );
      final second = await users.loginUser(
        nationalId: DemoAuthRepository.secondCitizenNationalId,
        pin: DemoAuthRepository.secondCitizenPin,
      );

      expect(first.account.id, isNot(second.account.id));
      for (final account in [first.account, second.account]) {
        expect(account.role, UsageRole.citizen);
        expect(account.hasVolunteerMembership, isFalse);
        expect(account.applicationStatus, ApplicationStatus.none);
      }
    },
  );

  test(
    'demo volunteers authenticate independently with matching membership',
    () async {
      final first = await users.loginUser(
        nationalId: DemoAuthRepository.volunteerNationalId,
        pin: DemoAuthRepository.volunteerPin,
      );
      final second = await users.loginUser(
        nationalId: DemoAuthRepository.secondVolunteerNationalId,
        pin: DemoAuthRepository.secondVolunteerPin,
      );

      expect(first.account.id, isNot(second.account.id));
      for (final account in [first.account, second.account]) {
        expect(account.role, UsageRole.volunteer);
        expect(account.hasVolunteerMembership, isTrue);
        expect(account.applicationStatus, ApplicationStatus.approved);
        final municipalityRecord = operations.volunteers.singleWhere(
          (volunteer) => volunteer.nationalId == account.nationalId,
        );
        expect(municipalityRecord.userId, account.id);
        expect(municipalityRecord.fullName, account.fullName);
        expect(municipalityRecord.phone, account.phone);
      }
    },
  );

  test('pending demo volunteer remains pending without membership', () async {
    await auth.loginUser(
      DemoAuthRepository.pendingNationalId,
      DemoAuthRepository.pendingPin,
    );

    expect(auth.user!.role, UsageRole.citizen);
    expect(auth.user!.hasVolunteerMembership, isFalse);
    expect(auth.user!.applicationStatus, ApplicationStatus.pending);
  });

  test('wrong PIN fails for an additional demo account', () async {
    await expectLater(
      users.loginUser(
        nationalId: DemoAuthRepository.secondVolunteerNationalId,
        pin: '0000',
      ),
      throwsA(isA<AuthFailure>()),
    );
  });

  test('logout clears persisted and in-memory session state', () async {
    await auth.loginUser('123456789', '1234');
    await auth.logout();
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.user, isNull);
    expect(await sessions.read(), isNull);
  });

  test('municipality login persists and restores separately', () async {
    await auth.loginMunicipality(
      DemoMunicipalityAuthRepository.demoEmail,
      DemoMunicipalityAuthRepository.demoPassword,
    );
    expect(auth.status, AuthStatus.municipality);
    expect((await sessions.read())!.principal, AuthPrincipal.municipality);

    final restored = AuthController(
      users: users,
      municipalities: municipalities,
      sessions: sessions,
    );
    await restored.restore();
    expect(restored.status, AuthStatus.municipality);
    expect(restored.municipality!.name, 'بلدية القدس');
    await restored.logout();
    expect(await sessions.read(), isNull);
    restored.dispose();
  });

  test(
    'applications accept/reject coherently update volunteer membership',
    () async {
      final pending = operations.applications.single;
      operations.acceptApplication(pending.id);
      expect(
        operations.applicationStatusFor(pending.nationalId),
        ApplicationStatus.approved,
      );
      expect(operations.hasVolunteerMembership(pending.nationalId), isTrue);
      await auth.loginUser(
        DemoAuthRepository.pendingNationalId,
        DemoAuthRepository.pendingPin,
      );
      expect(auth.user!.role, UsageRole.volunteer);
      await auth.logout();

      final second = VolunteerApplicationRecord(
        id: 'second',
        userId: 'user-second',
        fullName: 'محمد سمير',
        nationalId: '222333444',
        phone: '0590001112',
        birthDate: '01 / 01 / 2000',
        requestedAt: DateTime(2026, 9, 19),
        status: ApplicationStatus.pending,
      );
      operations.submitApplication(second);
      operations.rejectApplication(second.id);
      expect(
        operations.applicationStatusFor(second.nationalId),
        ApplicationStatus.rejected,
      );
      expect(operations.hasVolunteerMembership(second.nationalId), isFalse);
    },
  );

  test('active and resolved incidents remain separated', () {
    expect(operations.incidents.where((item) => !item.isResolved), isNotEmpty);
    expect(operations.incidents.where((item) => item.isResolved), isNotEmpty);
  });
}
