import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/mock_server.dart';

void main() {
  late FirePinMockServer server;
  late HttpClient client;
  late Uri baseUri;

  setUp(() async {
    server = await FirePinMockServer.start(
      port: 0,
      address: InternetAddress.loopbackIPv4,
      now: () => DateTime.utc(2026, 9, 20, 12),
    );
    client = HttpClient();
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  Future<_HttpResult> request(
    String method,
    String path, {
    Object? body,
    String? rawBody,
  }) async {
    final httpRequest = await client.openUrl(method, baseUri.resolve(path));
    httpRequest.headers.set('Origin', 'http://localhost:5000');
    if (body != null || rawBody != null) {
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(rawBody ?? jsonEncode(body));
    }
    final response = await httpRequest.close();
    final rawResponse = await utf8.decoder.bind(response).join();
    return _HttpResult(
      statusCode: response.statusCode,
      headers: response.headers,
      body: rawResponse.isEmpty
          ? null
          : jsonDecode(rawResponse) as Map<String, dynamic>,
    );
  }

  Map<String, Object> incidentRequest() => {
    'reporter': {
      'id': 'user-citizen',
      'displayName': 'أحمد محمد عبد الله',
      'phone': '059 123 4567',
    },
    'fireLocation': {'latitude': 31.78, 'longitude': 35.24},
    'photoMetadata': {'present': false},
  };

  Map<String, Object> volunteer(String id, String name, String phone) => {
    'volunteerId': id,
    'displayName': name,
    'phone': phone,
  };

  test('health works and reset returns empty shared state', () async {
    final health = await request('GET', '/health');
    expect(health.statusCode, HttpStatus.ok);
    expect(health.body, {
      'status': 'ok',
      'service': 'firepin-local-mock',
      'inMemory': true,
    });

    await request('POST', '/incidents', body: incidentRequest());
    final reset = await request('POST', '/reset');
    expect(reset.statusCode, HttpStatus.ok);
    expect(reset.body!['incidents'], isEmpty);
    expect(reset.body!['activeIncidentCount'], 0);

    final state = await request('GET', '/state');
    expect(state.body, reset.body);
  });

  test('HTTP lifecycle preserves independent multi-responder state', () async {
    final created = await request(
      'POST',
      '/incidents',
      body: incidentRequest(),
    );
    expect(created.statusCode, HttpStatus.created);
    final incident = created.body!['incident'] as Map<String, dynamic>;
    final incidentId = incident['id'] as String;
    expect(incidentId, 'demo-incident-1');
    expect(incident['stage'], 'waitingForResponder');
    expect(incident['isActive'], isTrue);
    expect(incident['responderCount'], 0);

    final initialState = await request('GET', '/state');
    expect(initialState.body!['activeIncidentCount'], 1);
    expect(initialState.body!['incidents'], hasLength(1));

    final volunteerA = volunteer(
      'user-volunteer',
      'ليان أحمد صالح',
      '059 222 3344',
    );
    final volunteerB = volunteer(
      'user-volunteer-2',
      'عمر يوسف النجار',
      '059 333 4466',
    );
    final volunteerC = volunteer(
      'user-volunteer-3',
      'متطوع ثالث',
      '059 999 9999',
    );

    await request('POST', '/incidents/$incidentId/respond', body: volunteerA);
    final responseB = await request(
      'POST',
      '/incidents/$incidentId/respond',
      body: volunteerB,
    );
    expect(responseB.body!['incident']['responderCount'], 2);

    final duplicateA = await request(
      'POST',
      '/incidents/$incidentId/respond',
      body: volunteerA,
    );
    final afterDuplicate = duplicateA.body!['incident'] as Map<String, dynamic>;
    expect(afterDuplicate['responderCount'], 2);
    expect(afterDuplicate['volunteerResponses'], hasLength(2));

    final declinedC = await request(
      'POST',
      '/incidents/$incidentId/decline',
      body: volunteerC,
    );
    final afterDecline = declinedC.body!['incident'] as Map<String, dynamic>;
    expect(afterDecline['responderCount'], 2);
    expect(afterDecline['volunteerResponses'], hasLength(3));
    expect(
      (afterDecline['volunteerResponses'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (response) => response['volunteerId'] == 'user-volunteer-3',
          )['state'],
      'declined',
    );

    final withdrawnA = await request(
      'POST',
      '/incidents/$incidentId/withdraw',
      body: {'volunteerId': 'user-volunteer'},
    );
    final afterWithdrawal =
        withdrawnA.body!['incident'] as Map<String, dynamic>;
    expect(afterWithdrawal['responderCount'], 1);
    expect(
      (afterWithdrawal['volunteerResponses'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((response) => response['state'] == 'responding')
          .single['volunteerId'],
      'user-volunteer-2',
    );

    final forbidden = await request(
      'POST',
      '/incidents/$incidentId/resolve',
      body: {'volunteerId': 'user-volunteer-3'},
    );
    expect(forbidden.statusCode, HttpStatus.forbidden);
    expect(forbidden.body!['error']['code'], 'not_active_responder');

    final resolved = await request(
      'POST',
      '/incidents/$incidentId/resolve',
      body: {'volunteerId': 'user-volunteer-2'},
    );
    final resolvedIncident = resolved.body!['incident'] as Map<String, dynamic>;
    expect(resolvedIncident['stage'], 'resolved');
    expect(resolvedIncident['isActive'], isFalse);
    expect(resolvedIncident['responderCount'], 0);

    final finalState = await request('GET', '/state');
    expect(finalState.body!['activeIncidentCount'], 0);
    expect(finalState.body!['incidents'], hasLength(1));

    final reset = await request('POST', '/reset');
    expect(reset.body!['incidents'], isEmpty);
  });

  test('malformed and unsupported requests return JSON errors', () async {
    final malformed = await request('POST', '/incidents', rawBody: '{not-json');
    expect(malformed.statusCode, HttpStatus.badRequest);
    expect(malformed.body!['error']['code'], 'malformed_json');

    final missingFields = await request('POST', '/incidents', body: {});
    expect(missingFields.statusCode, HttpStatus.badRequest);
    expect(missingFields.body!['error']['code'], 'invalid_request');

    final unknownIncident = await request(
      'POST',
      '/incidents/missing/respond',
      body: volunteer('user-volunteer', 'Volunteer', '0590000000'),
    );
    expect(unknownIncident.statusCode, HttpStatus.notFound);
    expect(unknownIncident.body!['error']['code'], 'unknown_incident');

    final wrongMethod = await request('GET', '/reset');
    expect(wrongMethod.statusCode, HttpStatus.methodNotAllowed);
    expect(wrongMethod.body!['error']['code'], 'method_not_allowed');

    final unknownRoute = await request('GET', '/missing');
    expect(unknownRoute.statusCode, HttpStatus.notFound);
    expect(unknownRoute.body!['error']['code'], 'route_not_found');
  });

  test('CORS preflight permits local browser requests', () async {
    final response = await request('OPTIONS', '/incidents');
    expect(response.statusCode, HttpStatus.noContent);
    expect(
      response.headers.value(HttpHeaders.accessControlAllowOriginHeader),
      '*',
    );
    expect(
      response.headers.value(HttpHeaders.accessControlAllowMethodsHeader),
      contains('POST'),
    );
    expect(
      response.headers.value(HttpHeaders.accessControlAllowHeadersHeader),
      contains('Content-Type'),
    );
  });
}

class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final Map<String, dynamic>? body;
}
