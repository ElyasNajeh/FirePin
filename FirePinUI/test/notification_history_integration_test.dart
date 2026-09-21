import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firepin_ui/core/network/api_client.dart';
import 'package:firepin_ui/core/storage/token_storage.dart';
import 'package:firepin_ui/features/notifications/notification_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'user and municipality inboxes use their own authenticated API paths',
    () async {
      final userAdapter = HistoryAdapter();
      final municipalityAdapter = HistoryAdapter();
      final storage = HistoryTokenStorage();
      final userApi = ApiClient(
        baseUrl: 'https://api.example.com',
        tokenStorage: storage,
        dio: Dio()..httpClientAdapter = userAdapter,
      );
      final municipalityApi = ApiClient(
        baseUrl: 'https://api.example.com',
        tokenStorage: storage,
        refreshPath: '/municipalities/auth/refresh',
        dio: Dio()..httpClientAdapter = municipalityAdapter,
      );
      await userApi.setSession(
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
      );
      await municipalityApi.setSession(
        accessToken: 'municipality-access',
        refreshToken: 'municipality-refresh',
      );
      final history = ApiNotificationHistoryRepository(
        userApi,
        municipalityApi,
      );

      final userItems = await history.getUserNotifications();
      final municipalityItems = await history.getMunicipalityNotifications();
      expect(userItems.single.fireReportId, 186);
      expect(municipalityItems.single.eventType, 'report_created');
      expect(userAdapter.requests.single.path, '/notifications/me');
      expect(
        municipalityAdapter.requests.single.path,
        '/municipalities/auth/notifications',
      );
      expect(
        userAdapter.requests.single.headers['Authorization'],
        'Bearer user-access',
      );
      expect(
        municipalityAdapter.requests.single.headers['Authorization'],
        'Bearer municipality-access',
      );
    },
  );

  testWidgets('inbox displays persisted event and opens its real report ID', (
    tester,
  ) async {
    final opened = <int>[];
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationHistoryView(
            load: () async {
              loads++;
              return [historyEntry()];
            },
            onOpenReport: (id) async => opened.add(id),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('notification-7')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notification-7')));
    await tester.pump();
    expect(opened, [186]);
    expect(loads, 2);
  });

  testWidgets('inbox failure has retry and no fake events', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationHistoryView(
            load: () async {
              if (fail) throw StateError('network');
              return [historyEntry()];
            },
            onOpenReport: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('notification-7')), findsNothing);
    expect(find.textContaining('تعذّر تحميل التنبيهات'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const ValueKey('refresh-notifications')));
    await tester.pump();
    expect(find.byKey(const ValueKey('notification-7')), findsOneWidget);
  });
}

NotificationEntry historyEntry() => NotificationEntry(
  id: 7,
  fireReportId: 186,
  eventType: 'new_report',
  title: 'بلاغ حريق جديد',
  body: 'تم تسجيل بلاغ حريق جديد بالقرب منك',
  createdAt: DateTime.utc(2026, 9, 21),
);

class HistoryTokenStorage extends TokenStorage {
  String? token;

  @override
  Future<void> saveRefreshToken(String value) async => token = value;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> deleteRefreshToken() async => token = null;
}

class HistoryAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode([
        {
          'id': 7,
          'fire_report_id': 186,
          'event_type': 'report_created',
          'title': 'بلاغ حريق جديد',
          'body': 'تم تسجيل بلاغ حريق جديد بالقرب منك',
          'created_at': '2026-09-21T12:00:00Z',
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
