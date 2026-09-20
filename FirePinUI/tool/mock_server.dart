import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local FirePin demo infrastructure only.
///
/// This server is in-memory, disposable, and intentionally does not provide
/// production authentication, durable storage, or realtime delivery.
const defaultMockServerPort = 8787;

Future<void> main(List<String> arguments) async {
  final port = _parsePort(arguments);
  if (port == null) {
    stderr.writeln('Usage: dart run tool/mock_server.dart [--port PORT]');
    exitCode = 64;
    return;
  }

  final server = await FirePinMockServer.start(port: port);
  stdout
    ..writeln('FirePin local demo server running on port ${server.port}.')
    ..writeln('Host: http://localhost:${server.port}')
    ..writeln('Android emulator: http://10.0.2.2:${server.port}')
    ..writeln('State is memory-only and resets when the server stops.');

  await ProcessSignal.sigint.watch().first;
  await server.close();
}

int? _parsePort(List<String> arguments) {
  if (arguments.isEmpty) return defaultMockServerPort;
  String? value;
  if (arguments.length == 1 && arguments.single.startsWith('--port=')) {
    value = arguments.single.substring('--port='.length);
  } else if (arguments.length == 2 && arguments.first == '--port') {
    value = arguments.last;
  } else {
    return null;
  }
  final port = int.tryParse(value);
  return port != null && port > 0 && port <= 65535 ? port : null;
}

class FirePinMockServer {
  FirePinMockServer._(this._server, DateTime Function() now)
    : _state = _SharedDemoState(now);

  final HttpServer _server;
  final _SharedDemoState _state;

  int get port => _server.port;

  static Future<FirePinMockServer> start({
    int port = defaultMockServerPort,
    InternetAddress? address,
    DateTime Function()? now,
  }) async {
    final httpServer = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    final server = FirePinMockServer._(
      httpServer,
      now ?? () => DateTime.now().toUtc(),
    );
    httpServer.listen((request) {
      unawaited(server._handleSafely(request));
    });
    return server;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handleSafely(HttpRequest request) async {
    _applyCors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      await _route(request);
    } on _RequestError catch (error) {
      await _sendJson(
        request.response,
        error.statusCode,
        _errorJson(error.code, error.message),
      );
    } on Object {
      await _sendJson(
        request.response,
        HttpStatus.internalServerError,
        _errorJson(
          'internal_error',
          'The local demo server could not respond.',
        ),
      );
    }
  }

  Future<void> _route(HttpRequest request) async {
    final segments = request.uri.pathSegments;

    if (segments.length == 1 && segments.single == 'health') {
      _requireMethod(request, 'GET');
      await _sendJson(request.response, HttpStatus.ok, {
        'status': 'ok',
        'service': 'firepin-local-mock',
        'inMemory': true,
      });
      return;
    }

    if (segments.length == 1 && segments.single == 'reset') {
      _requireMethod(request, 'POST');
      _state.reset();
      await _sendJson(request.response, HttpStatus.ok, _state.toJson());
      return;
    }

    if (segments.length == 1 && segments.single == 'state') {
      _requireMethod(request, 'GET');
      await _sendJson(request.response, HttpStatus.ok, _state.toJson());
      return;
    }

    if (segments.length == 1 && segments.single == 'incidents') {
      _requireMethod(request, 'POST');
      final body = await _readJsonObject(request);
      final incident = _state.createIncident(body);
      await _sendJson(request.response, HttpStatus.created, {
        'incident': incident.toJson(),
      });
      return;
    }

    if (segments.length == 3 && segments.first == 'incidents') {
      _requireMethod(request, 'POST');
      final body = await _readJsonObject(request);
      final incidentId = segments[1];
      final incident = switch (segments[2]) {
        'respond' => _state.respond(incidentId, body),
        'decline' => _state.decline(incidentId, body),
        'withdraw' => _state.withdraw(incidentId, body),
        'resolve' => _state.resolve(incidentId, body),
        _ => throw const _RequestError(
          HttpStatus.notFound,
          'route_not_found',
          'The requested local demo route does not exist.',
        ),
      };
      await _sendJson(request.response, HttpStatus.ok, {
        'incident': incident.toJson(),
      });
      return;
    }

    throw const _RequestError(
      HttpStatus.notFound,
      'route_not_found',
      'The requested local demo route does not exist.',
    );
  }

  void _requireMethod(HttpRequest request, String expected) {
    if (request.method != expected) {
      request.response.headers.set(HttpHeaders.allowHeader, expected);
      throw _RequestError(
        HttpStatus.methodNotAllowed,
        'method_not_allowed',
        'Use $expected for this local demo route.',
      );
    }
  }
}

class _SharedDemoState {
  _SharedDemoState(this._now);

  final DateTime Function() _now;
  final Map<String, _SharedIncident> _incidents = {};
  int _nextIncidentNumber = 1;

  Map<String, Object> toJson() => {
    'incidents': _incidents.values
        .map((incident) => incident.toJson())
        .toList(growable: false),
    'activeIncidentCount': _incidents.values
        .where((incident) => incident.isActive)
        .length,
  };

  void reset() {
    _incidents.clear();
    _nextIncidentNumber = 1;
  }

  _SharedIncident createIncident(Map<String, dynamic> body) {
    final reporter = _requiredObject(body, 'reporter');
    final fireLocation = _requiredObject(body, 'fireLocation');
    final reportedAt = _timestamp();
    final incident = _SharedIncident(
      id: 'demo-incident-${_nextIncidentNumber++}',
      reportedAt: reportedAt,
      reporterId: _requiredString(reporter, 'id'),
      reporterName: _requiredString(reporter, 'displayName'),
      reporterPhone: _requiredString(reporter, 'phone'),
      latitude: _requiredCoordinate(fireLocation, 'latitude', -90, 90),
      longitude: _requiredCoordinate(fireLocation, 'longitude', -180, 180),
      photoMetadata: _optionalObject(body, 'photoMetadata'),
      events: [
        _SharedEvent(stage: 'reported', at: reportedAt),
        _SharedEvent(stage: 'waitingForResponder', at: reportedAt),
      ],
    );
    _incidents[incident.id] = incident;
    return incident;
  }

  _SharedIncident respond(String incidentId, Map<String, dynamic> body) {
    final incident = _activeIncident(incidentId);
    final volunteerId = _requiredString(body, 'volunteerId');
    final displayName = _requiredString(body, 'displayName');
    final phone = _requiredString(body, 'phone');
    if (incident.hasActiveResponse(volunteerId)) return incident;

    final updatedAt = _timestamp();
    incident.responses.removeWhere(
      (response) => response.volunteerId == volunteerId,
    );
    incident.responses.add(
      _SharedVolunteerResponse(
        volunteerId: volunteerId,
        displayName: displayName,
        phone: phone,
        state: 'responding',
        updatedAt: updatedAt,
      ),
    );
    incident
      ..stage = 'responderEnRoute'
      ..events.addAll([
        _SharedEvent(
          stage: 'responderAccepted',
          at: updatedAt,
          volunteerId: volunteerId,
        ),
        _SharedEvent(
          stage: 'responderEnRoute',
          at: updatedAt,
          volunteerId: volunteerId,
        ),
      ]);
    return incident;
  }

  _SharedIncident decline(String incidentId, Map<String, dynamic> body) {
    final incident = _activeIncident(incidentId);
    final volunteerId = _requiredString(body, 'volunteerId');
    final displayName = _requiredString(body, 'displayName');
    final phone = _requiredString(body, 'phone');
    if (incident.responseFor(volunteerId) != null) return incident;

    incident.responses.add(
      _SharedVolunteerResponse(
        volunteerId: volunteerId,
        displayName: displayName,
        phone: phone,
        state: 'declined',
        updatedAt: _timestamp(),
      ),
    );
    return incident;
  }

  _SharedIncident withdraw(String incidentId, Map<String, dynamic> body) {
    final incident = _activeIncident(incidentId);
    final volunteerId = _requiredString(body, 'volunteerId');
    final hadActiveResponse = incident.hasActiveResponse(volunteerId);
    incident.responses.removeWhere(
      (response) =>
          response.volunteerId == volunteerId && response.isResponding,
    );
    if (hadActiveResponse && incident.activeResponses.isEmpty) {
      final updatedAt = _timestamp();
      incident
        ..stage = 'waitingForResponder'
        ..events.add(_SharedEvent(stage: 'waitingForResponder', at: updatedAt));
    }
    return incident;
  }

  _SharedIncident resolve(String incidentId, Map<String, dynamic> body) {
    final incident = _activeIncident(incidentId);
    final volunteerId = _requiredString(body, 'volunteerId');
    if (!incident.hasActiveResponse(volunteerId)) {
      throw const _RequestError(
        HttpStatus.forbidden,
        'not_active_responder',
        'Only an active responder may resolve this incident.',
      );
    }
    final resolvedAt = _timestamp();
    incident
      ..stage = 'resolved'
      ..events.add(
        _SharedEvent(
          stage: 'resolved',
          at: resolvedAt,
          volunteerId: volunteerId,
        ),
      );
    return incident;
  }

  _SharedIncident _activeIncident(String incidentId) {
    final incident = _incidents[incidentId];
    if (incident == null) {
      throw const _RequestError(
        HttpStatus.notFound,
        'unknown_incident',
        'The requested incident does not exist.',
      );
    }
    if (!incident.isActive) {
      throw const _RequestError(
        HttpStatus.conflict,
        'incident_resolved',
        'The resolved incident can no longer be changed.',
      );
    }
    return incident;
  }

  String _timestamp() => _now().toUtc().toIso8601String();
}

class _SharedIncident {
  _SharedIncident({
    required this.id,
    required this.reportedAt,
    required this.reporterId,
    required this.reporterName,
    required this.reporterPhone,
    required this.latitude,
    required this.longitude,
    required this.photoMetadata,
    required this.events,
  });

  final String id;
  final String reportedAt;
  final String reporterId;
  final String reporterName;
  final String reporterPhone;
  final double latitude;
  final double longitude;
  final Map<String, dynamic>? photoMetadata;
  final List<_SharedEvent> events;
  final List<_SharedVolunteerResponse> responses = [];
  String stage = 'waitingForResponder';

  bool get isActive => stage != 'resolved';
  Iterable<_SharedVolunteerResponse> get activeResponses => isActive
      ? responses.where((response) => response.isResponding)
      : const [];

  bool hasActiveResponse(String volunteerId) =>
      activeResponses.any((response) => response.volunteerId == volunteerId);

  _SharedVolunteerResponse? responseFor(String volunteerId) {
    for (final response in responses) {
      if (response.volunteerId == volunteerId) return response;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'stage': stage,
    'isActive': isActive,
    'reportedAt': reportedAt,
    'reporter': {
      'id': reporterId,
      'displayName': reporterName,
      'phone': reporterPhone,
    },
    'fireLocation': {'latitude': latitude, 'longitude': longitude},
    'photoMetadata': photoMetadata,
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'volunteerResponses': responses
        .map((response) => response.toJson())
        .toList(growable: false),
    'responderCount': activeResponses.length,
  };
}

class _SharedEvent {
  const _SharedEvent({required this.stage, required this.at, this.volunteerId});

  final String stage;
  final String at;
  final String? volunteerId;

  Map<String, Object?> toJson() => {
    'stage': stage,
    'at': at,
    'volunteerId': volunteerId,
  };
}

class _SharedVolunteerResponse {
  const _SharedVolunteerResponse({
    required this.volunteerId,
    required this.displayName,
    required this.phone,
    required this.state,
    required this.updatedAt,
  });

  final String volunteerId;
  final String displayName;
  final String phone;
  final String state;
  final String updatedAt;

  bool get isResponding => state == 'responding';

  Map<String, Object> toJson() => {
    'volunteerId': volunteerId,
    'displayName': displayName,
    'phone': phone,
    'state': state,
    'updatedAt': updatedAt,
  };
}

Future<Map<String, dynamic>> _readJsonObject(HttpRequest request) async {
  try {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const _RequestError(
        HttpStatus.badRequest,
        'invalid_request',
        'The request body must be a JSON object.',
      );
    }
    return decoded;
  } on _RequestError {
    rethrow;
  } on FormatException {
    throw const _RequestError(
      HttpStatus.badRequest,
      'malformed_json',
      'The request body is not valid JSON.',
    );
  }
}

Map<String, dynamic> _requiredObject(
  Map<String, dynamic> source,
  String field,
) {
  final value = source[field];
  if (value is Map<String, dynamic>) return value;
  throw _invalidField(field);
}

Map<String, dynamic>? _optionalObject(
  Map<String, dynamic> source,
  String field,
) {
  final value = source[field];
  if (value == null) return null;
  if (value is Map<String, dynamic>) return Map.unmodifiable(value);
  throw _invalidField(field);
}

String _requiredString(Map<String, dynamic> source, String field) {
  final value = source[field];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw _invalidField(field);
}

double _requiredCoordinate(
  Map<String, dynamic> source,
  String field,
  double minimum,
  double maximum,
) {
  final value = source[field];
  if (value is num && value.isFinite) {
    final coordinate = value.toDouble();
    if (coordinate >= minimum && coordinate <= maximum) return coordinate;
  }
  throw _invalidField(field);
}

_RequestError _invalidField(String field) => _RequestError(
  HttpStatus.badRequest,
  'invalid_request',
  'Missing or invalid required field: $field.',
);

void _applyCors(HttpResponse response) {
  response.headers
    ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
    ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS')
    ..set(HttpHeaders.accessControlAllowHeadersHeader, 'Content-Type')
    ..set(HttpHeaders.accessControlMaxAgeHeader, '600')
    ..contentType = ContentType.json;
}

Future<void> _sendJson(
  HttpResponse response,
  int statusCode,
  Object body,
) async {
  response.statusCode = statusCode;
  response.write(jsonEncode(body));
  await response.close();
}

Map<String, Object> _errorJson(String code, String message) => {
  'error': {'code': code, 'message': message},
};

class _RequestError implements Exception {
  const _RequestError(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;
}
