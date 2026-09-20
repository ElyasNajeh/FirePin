import 'dart:typed_data';

import '../../core/network/api_client.dart';
import 'onboarding_models.dart';

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
