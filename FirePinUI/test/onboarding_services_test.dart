import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:firepin_ui/features/onboarding/onboarding_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_fakes.dart';

void main() {
  group('mock OTP', () {
    test('accepts 123456 only after issuance and consumes it', () async {
      final service = MockOtpService(delay: Duration.zero);
      expect(await service.verify('0591234567', '123456'), isFalse);
      await service.send('0591234567');
      expect(await service.verify('0591234567', '123456'), isTrue);
      expect(await service.verify('0591234567', '123456'), isFalse);
    });
    test('rejects wrong, short, long and non-numeric codes', () async {
      final service = MockOtpService(delay: Duration.zero);
      await service.send('0591234567');
      for (final code in ['000000', '12345', '1234567', 'abcdef']) {
        expect(await service.verify('0591234567', code), isFalse);
      }
      expect(await service.verify('0597654321', '123456'), isFalse);
    });
    test(
      'resend issues a new mock challenge and accepts Arabic digits',
      () async {
        final service = MockOtpService(delay: Duration.zero);
        await service.send('0591234567');
        await service.verify('0591234567', '123456');
        await service.send('0591234567');
        expect(await service.verify('0591234567', '١٢٣٤٥٦'), isTrue);
      },
    );
  });
  test('PIN requires exactly four matching numeric digits', () {
    expect(confirmPin('123', '123'), PinConfirmation.incomplete);
    expect(confirmPin('12345', '12345'), PinConfirmation.incomplete);
    expect(confirmPin('abcd', 'abcd'), PinConfirmation.incomplete);
    expect(confirmPin('1234', '4321'), PinConfirmation.mismatch);
    expect(confirmPin('0123', '0123'), PinConfirmation.confirmed);
    final session = OnboardingSession();
    expect(session.savePin('1234', '4321'), isFalse);
    expect(session.hasPin, isFalse);
    expect(session.savePin('0123', '0123'), isTrue);
    expect(session.hasPin, isTrue);
    session.clearSensitiveData();
    expect(session.hasPin, isFalse);
  });
  test(
    'citizen routes home; volunteer requires confirmation and stays pending',
    () {
      final session = OnboardingSession();
      expect(session.destination, AccountDestination.home);
      session.role = UsageRole.volunteer;
      expect(session.destination, AccountDestination.volunteerWarning);
      session.applicationStatus = ApplicationStatus.pending;
      expect(session.destination, AccountDestination.pendingApproval);
      session.role = UsageRole.citizen;
      expect(session.destination, AccountDestination.pendingApproval);
    },
  );
  test('phone validation normalizes Arabic numerals and spacing', () {
    expect(isValidPhone('٠٥٩ ١٢٣ ٤٥٦٧'), isTrue);
    expect(isValidPhone('+970 59 123 4567'), isTrue);
    expect(isValidPhone('123'), isFalse);
    expect(isValidPhone('abcdef'), isFalse);
    expect(isValidPhone('++970591234567'), isFalse);
  });
  test(
    'identity mock supplies the Figma fixture, without performing OCR',
    () async {
      final service = MockIdentityVerificationService(delay: Duration.zero);
      final data = await service.verify(testPhoto);
      expect(data.fullName, 'أحمد محمد عبد الله');
      expect(data.address, 'القدس — الطور');
      expect(data.birthDate, '14 / 05 / 1998');
    },
  );
}
