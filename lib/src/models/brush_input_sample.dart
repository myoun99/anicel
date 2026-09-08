/// One reading from the pen: where it is, how hard it presses, and how it
/// leans.
///
/// 🚨TILT IS TWO NUMBERS, AND THEY ARE THE SIDECAR'S TWO. The tablet bridge
/// already speaks `tiltAzimuthDegrees` + a normalized `altitude`
/// (`qa_tablet_bridge.dart`), so the sample carries that pair rather than
/// Flutter's `tilt`/`orientation` radians — converting once, at the door
/// where the pointer is read, beats converting at every reader. A pen held
/// upright reports altitude 1.0, which is why that is the default: a device
/// with no tilt to report is an upright pen, not a flat one.
class BrushInputSample {
  BrushInputSample({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    this.tiltAzimuthDegrees = 0.0,
    this.tiltAltitude = 1.0,
    this.sequence = 0,
  }) {
    _validateFiniteCoordinate(x, 'x');
    _validateFiniteCoordinate(y, 'y');
    _validatePressure(pressure);
    _validateFiniteCoordinate(tiltAzimuthDegrees, 'tiltAzimuthDegrees');
    _validateAltitude(tiltAltitude);
    _validateSequence(sequence);
  }

  final double x;
  final double y;
  final double pressure;

  /// Which way the pen leans, in degrees (0 = along +x, driver convention).
  /// Meaningless while [tiltAltitude] is 1.0 — an upright pen leans nowhere.
  final double tiltAzimuthDegrees;

  /// How upright the pen is: 1.0 vertical, 0.0 flat on the surface.
  final double tiltAltitude;

  final int sequence;

  BrushInputSample copyWith({
    double? x,
    double? y,
    double? pressure,
    double? tiltAzimuthDegrees,
    double? tiltAltitude,
    int? sequence,
  }) {
    return BrushInputSample(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
      tiltAzimuthDegrees: tiltAzimuthDegrees ?? this.tiltAzimuthDegrees,
      tiltAltitude: tiltAltitude ?? this.tiltAltitude,
      sequence: sequence ?? this.sequence,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'pressure': pressure,
    // ⚠️Omitted at the resting value so a stored stroke from before tilt
    // existed reads back byte-identical to one recorded now with an
    // upright pen.
    if (tiltAltitude != 1.0) 'tiltAltitude': tiltAltitude,
    if (tiltAzimuthDegrees != 0.0) 'tiltAzimuthDegrees': tiltAzimuthDegrees,
    'sequence': sequence,
  };

  factory BrushInputSample.fromJson(Map<String, dynamic> json) {
    return BrushInputSample(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 1.0,
      tiltAzimuthDegrees:
          (json['tiltAzimuthDegrees'] as num?)?.toDouble() ?? 0.0,
      tiltAltitude: (json['tiltAltitude'] as num?)?.toDouble() ?? 1.0,
      sequence: json['sequence'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushInputSample &&
          other.x == x &&
          other.y == y &&
          other.pressure == pressure &&
          other.tiltAzimuthDegrees == tiltAzimuthDegrees &&
          other.tiltAltitude == tiltAltitude &&
          other.sequence == sequence;

  @override
  int get hashCode =>
      Object.hash(x, y, pressure, tiltAzimuthDegrees, tiltAltitude, sequence);

  @override
  String toString() =>
      'BrushInputSample(x: $x, y: $y, pressure: $pressure, '
      'tiltAzimuthDegrees: $tiltAzimuthDegrees, '
      'tiltAltitude: $tiltAltitude, sequence: $sequence)';
}

void _validateFiniteCoordinate(double value, String fieldName) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushInputSample.$fieldName must be finite.',
    );
  }
}

void _validatePressure(double value) {
  if (value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      'pressure',
      'BrushInputSample.pressure must be between 0.0 and 1.0 inclusive.',
    );
  }
}

void _validateAltitude(double value) {
  if (!value.isFinite || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      'tiltAltitude',
      'BrushInputSample.tiltAltitude must be between 0.0 and 1.0 inclusive.',
    );
  }
}

void _validateSequence(int value) {
  if (value < 0) {
    throw ArgumentError.value(
      value,
      'sequence',
      'BrushInputSample.sequence must be greater than or equal to 0.',
    );
  }
}
