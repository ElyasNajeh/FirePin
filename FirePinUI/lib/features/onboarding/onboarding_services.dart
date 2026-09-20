import 'dart:typed_data';

import '../../core/network/api_client.dart';
import 'onboarding_models.dart';

abstract interface class IdentityVerificationService {
  Future<IdentityData> verify(Uint8List cameraImage);
}

/// MOCK ONLY: accepts a camera image but does NOT authenticate a document,
/// perform OCR, determine age/eligibility, or extract a real portrait.
/// Replace this boundary with backend verification before release.
class MockIdentityVerificationService implements IdentityVerificationService {
  const MockIdentityVerificationService({
    this.delay = const Duration(milliseconds: 1500),
  });
  final Duration delay;
  @override
  Future<IdentityData> verify(Uint8List cameraImage) async {
    if (cameraImage.isEmpty) {
      throw ArgumentError('A camera capture is required.');
    }
    await Future<void>.delayed(delay);
    return const IdentityData(
      fullName: 'أحمد محمد عبد الله',
      identityNumber: '123456789',
      birthDate: '14 / 05 / 1998',
      gender: 'ذكر',
      address: 'القدس — الطور',
    );
  }
}

abstract interface class OtpService {
  Future<void> send(String phone);
  Future<bool> verify(String phone, String code);
}

/// Development-only OTP. No SMS is sent. A successful code is consumed.
class MockOtpService implements OtpService {
  MockOtpService({this.delay = const Duration(milliseconds: 450)});
  final Duration delay;
  String? _issuedPhone;
  @override
  Future<void> send(String phone) async {
    if (!isValidPhone(phone)) throw ArgumentError('Invalid phone number.');
    await Future<void>.delayed(delay);
    _issuedPhone = normalizePhone(phone);
  }

  @override
  Future<bool> verify(String phone, String code) async {
    await Future<void>.delayed(delay);
    final accepted =
        _issuedPhone == normalizePhone(phone) &&
        normalizeDigits(code) == '123456';
    if (accepted) _issuedPhone = null;
    return accepted;
  }
}

abstract interface class VolunteerApplicationService {
  Future<ApplicationStatus> submit({required int municipalityId});
}

class ApiVolunteerApplicationService implements VolunteerApplicationService {
  const ApiVolunteerApplicationService(this._api);

  final ApiClient _api;

  @override
  Future<ApplicationStatus> submit({required int municipalityId}) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/volunteer-applications',
      data: {'municipality_id': municipalityId},
      requiresAuth: true,
    );
    final status = response.data?['status'];
    return switch (status) {
      'pending' => ApplicationStatus.pending,
      'accepted' => ApplicationStatus.accepted,
      'rejected' => ApplicationStatus.rejected,
      _ => throw const FormatException(
        'Invalid volunteer application response',
      ),
    };
  }
}

abstract interface class FireReportService {
  Future<void> submit({
    Uint8List? photo,
    String? pin,
    required LocationFix location,
  });
}
