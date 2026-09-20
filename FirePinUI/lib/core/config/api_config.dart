import 'package:flutter/foundation.dart';

const _configuredApiBaseUrl = String.fromEnvironment('FIREPIN_API_BASE_URL');

String resolveApiBaseUrl({String? override, TargetPlatform? platform}) {
  final configured = override?.trim().isNotEmpty == true
      ? override!.trim()
      : _configuredApiBaseUrl.trim();
  if (configured.isNotEmpty) {
    return configured;
  }

  if (!kIsWeb &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}
