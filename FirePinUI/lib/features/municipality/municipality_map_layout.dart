import 'dart:ui';

/// Presentation-only map geometry for the local demo. A realtime location
/// source can replace this boundary without changing municipality widgets.
abstract interface class MunicipalityResponderMapLayout {
  ResponderMapPlacement placementFor({
    required String incidentId,
    required String volunteerId,
  });
}

class ResponderMapPlacement {
  const ResponderMapPlacement({
    required this.normalizedStart,
    required this.normalizedControlBias,
  });

  final Offset normalizedStart;
  final Offset normalizedControlBias;
}

class DeterministicMockResponderMapLayout
    implements MunicipalityResponderMapLayout {
  const DeterministicMockResponderMapLayout();

  @override
  ResponderMapPlacement placementFor({
    required String incidentId,
    required String volunteerId,
  }) {
    final primary = _stableHash('$incidentId:$volunteerId');
    final secondary = _stableHash('$volunteerId:$incidentId:route');
    return ResponderMapPlacement(
      normalizedStart: Offset(
        0.08 + (primary % 260) / 1000,
        0.49 + (secondary % 360) / 1000,
      ),
      normalizedControlBias: Offset(
        ((secondary ~/ 17) % 140 - 70) / 1000,
        -0.08 - ((primary ~/ 19) % 120) / 1000,
      ),
    );
  }

  int _stableHash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }
}
