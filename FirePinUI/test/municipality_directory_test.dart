import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/app/app_services.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/features/municipality/municipality_repository.dart';
import 'package:firepin_ui/features/onboarding/municipality_selection_screen.dart';
import 'package:firepin_ui/features/onboarding/onboarding_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'active municipalities load from API and preserve backend IDs',
    () async {
      final adapter = MunicipalityAdapter(
        response: {
          'items': [
            municipalityJson(id: 42, name: 'بلدية الخليل'),
            municipalityJson(id: 99, name: 'بلدية غير نشطة', isActive: false),
          ],
          'page': 1,
          'limit': 100,
          'total': 2,
        },
      );
      final repository = apiRepository(adapter);

      final municipalities = await repository.getActiveMunicipalities();

      expect(municipalities, hasLength(1));
      expect(municipalities.single.id, 42);
      expect(municipalities.single.name, 'بلدية الخليل');
      expect(municipalities.single.latitude, 31.5326);
      expect(municipalities.single.longitude, 35.0998);
      expect(adapter.requests.single.path, '/municipalities');
      expect(adapter.requests.single.queryParameters, {
        'is_active': true,
        'page': 1,
        'limit': 100,
      });
      expect(adapter.requests.single.headers['Authorization'], isNull);
    },
  );

  test('empty API response returns an empty directory', () async {
    final repository = apiRepository(
      MunicipalityAdapter(
        response: {'items': [], 'page': 1, 'limit': 100, 'total': 0},
      ),
    );

    expect(await repository.getActiveMunicipalities(), isEmpty);
  });

  test('API failure is surfaced without a mock fallback', () async {
    final repository = apiRepository(
      MunicipalityAdapter(statusCode: 503, response: {'detail': 'offline'}),
    );

    await expectLater(
      repository.getActiveMunicipalities(),
      throwsA(isA<DioException>()),
    );
  });

  test('AppServices uses the API directory repository by default', () {
    final services = AppServices(apiBaseUrl: 'https://api.example.com');

    expect(
      services.municipalityDirectory,
      isA<ApiMunicipalityDirectoryRepository>(),
    );

    services.authController.dispose();
    (services.operations as MunicipalityOperationsRepository).dispose();
    services.incidents.dispose();
  });

  test('onboarding session preserves the selected backend municipality ID', () {
    final session = OnboardingSession()
      ..selectMunicipality(id: 734, name: 'بلدية نابلس');

    expect(session.municipalityId, 734);
    expect(session.municipalityName, 'بلدية نابلس');
  });

  testWidgets('selection returns the real backend municipality', (
    tester,
  ) async {
    MunicipalityDirectoryEntry? selected;
    final repository = StaticMunicipalityDirectory([
      const MunicipalityDirectoryEntry(
        id: 734,
        name: 'بلدية نابلس',
        latitude: 32.2211,
        longitude: 35.2544,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MunicipalitySelectionScreen(
          repository: repository,
          onContinue: (value) => selected = value,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('municipality-734')));
    await tester.pump();
    final continueButton = find.text('متابعة');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);

    expect(selected?.id, 734);
    expect(selected?.name, 'بلدية نابلس');
  });

  testWidgets('directory shows loading and empty states', (tester) async {
    final completer = Completer<List<MunicipalityDirectoryEntry>>();
    final repository = DeferredMunicipalityDirectory(completer.future);

    await tester.pumpWidget(
      MaterialApp(
        home: MunicipalitySelectionScreen(
          repository: repository,
          onContinue: (_) {},
          onBack: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('municipality-directory-loading')),
      findsOneWidget,
    );

    completer.complete([]);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('municipality-directory-empty')),
      findsOneWidget,
    );
  });

  testWidgets('directory error can retry successfully', (tester) async {
    final repository = RetryingMunicipalityDirectory();

    await tester.pumpWidget(
      MaterialApp(
        home: MunicipalitySelectionScreen(
          repository: repository,
          onContinue: (_) {},
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('municipality-directory-error')),
      findsOneWidget,
    );

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();

    expect(find.text('بلدية رام الله'), findsOneWidget);
    expect(repository.calls, 2);
  });
}

ApiMunicipalityDirectoryRepository apiRepository(MunicipalityAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'https://api.example.com',
    tokenStorage: MemoryTokenStorage(),
    dio: Dio()..httpClientAdapter = adapter,
  );
  return ApiMunicipalityDirectoryRepository(client);
}

Map<String, dynamic> municipalityJson({
  required int id,
  required String name,
  bool isActive = true,
}) => {
  'id': id,
  'name': name,
  'latitude': '31.532600',
  'longitude': '35.099800',
  'is_active': isActive,
  'created_at': '2026-09-20T10:00:00Z',
  'updated_at': '2026-09-20T10:00:00Z',
};

class MunicipalityAdapter implements HttpClientAdapter {
  MunicipalityAdapter({required this.response, this.statusCode = 200});

  final Map<String, dynamic> response;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MemoryTokenStorage extends TokenStorage {}

class StaticMunicipalityDirectory implements MunicipalityDirectoryRepository {
  StaticMunicipalityDirectory(this.municipalities);

  final List<MunicipalityDirectoryEntry> municipalities;

  @override
  Future<List<MunicipalityDirectoryEntry>> getActiveMunicipalities() async =>
      municipalities;
}

class DeferredMunicipalityDirectory implements MunicipalityDirectoryRepository {
  DeferredMunicipalityDirectory(this.result);

  final Future<List<MunicipalityDirectoryEntry>> result;

  @override
  Future<List<MunicipalityDirectoryEntry>> getActiveMunicipalities() => result;
}

class RetryingMunicipalityDirectory implements MunicipalityDirectoryRepository {
  int calls = 0;

  @override
  Future<List<MunicipalityDirectoryEntry>> getActiveMunicipalities() async {
    calls++;
    if (calls == 1) throw StateError('offline');
    return const [
      MunicipalityDirectoryEntry(
        id: 81,
        name: 'بلدية رام الله',
        latitude: 31.9038,
        longitude: 35.2034,
      ),
    ];
  }
}
