/// One reading from the pen: where it is, how hard it presses, how it leans
/// and how fast it was travelling when it got here.
///
/// 🚨TILT IS TWO NUMBERS, AND THEY ARE THE SIDECAR'S TWO. The tablet bridge
/// already speaks `tiltAzimuthDegrees` + a normalized `altitude`
/// (`qa_tablet_bridge.dart`), so the sample carries that pair rather than
/// Flutter's `tilt`/`orientation` radians — converting once, at the door
/// where the pointer is read, beats converting at every reader.
///
/// ⛔A pen held upright reports altitude 1.0, and that USED TO BE THE DEFAULT
/// on the reasoning that "a device with no tilt to report is an upright pen,
/// not a flat one". Half right: it is not a flat pen, but it is not an
/// upright one either — a mouse never made that reading. The default is
/// absent now (유저 2026-09-09, `brush-tilt-no-device-Q1` 답 1).
class BrushInputSample {
  BrushInputSample({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    this.tiltAzimuthDegrees = 0.0,
    this.tiltAltitude,
    this.speed = 0.0,
    this.sequence = 0,
  }) {
    _validateFiniteCoordinate(x, 'x');
    _validateFiniteCoordinate(y, 'y');
    // ⚠️Pressure had its OWN validator until speed arrived and made three
    // copies of "0..1 or throw" in one file. Folding it in also plugged the
    // hole it had: it never asked `isFinite`, and NaN loses every comparison,
    // so a NaN pressure walked straight through the range check.
    _validateUnitInterval(pressure, 'pressure');
    _validateFiniteCoordinate(tiltAzimuthDegrees, 'tiltAzimuthDegrees');
    _validateTilt(tiltAltitude, tiltAzimuthDegrees);
    _validateUnitInterval(speed, 'speed');
    _validateSequence(sequence);
  }

  final double x;
  final double y;
  final double pressure;

  /// Which way the pen leans, in degrees (0 = along +x, driver convention).
  /// Meaningless while [tiltAltitude] is 1.0 — an upright pen leans nowhere —
  /// and required to be 0 when it is null.
  final double tiltAzimuthDegrees;

  /// How upright the pen is: 1.0 vertical, 0.0 flat on the surface — or NULL
  /// when the device reported no tilt. See `BrushDab.tiltAltitude`: a mouse
  /// and an upright pen used to be the same number.
  final double? tiltAltitude;

  /// How fast the pen was travelling on its way here, already normalized to
  /// 0..1 against `AppInputSettings.speedReferencePixelsPerSecond`.
  ///
  /// 🚨**NORMALIZED AT THE DOOR, like pressure and tilt.** The raw px/s never
  /// reaches a sample, because the ratio's ceiling is a user setting and a
  /// reader holding raw pixels would have to fetch that setting to mean
  /// anything — sixteen readers, sixteen chances to fetch a different one.
  /// The pen door divides once (`AppInput.normalizedSpeed`) and everything
  /// downstream reads a plain 0..1, exactly as it does for the other two.
  ///
  /// ⚠️Speed is a property of the MOVE, not of the point: every dab placed
  /// along one segment carries that segment's speed. 0.0 is a pen that has
  /// just landed and has no move behind it yet.
  final double speed;

  final int sequence;

  BrushInputSample copyWith({
    double? x,
    double? y,
    double? pressure,
    double? tiltAzimuthDegrees,
    double? tiltAltitude,
    double? speed,
    int? sequence,
  }) {
    return BrushInputSample(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
      tiltAzimuthDegrees: tiltAzimuthDegrees ?? this.tiltAzimuthDegrees,
      tiltAltitude: tiltAltitude ?? this.tiltAltitude,
      speed: speed ?? this.speed,
      sequence: sequence ?? this.sequence,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'pressure': pressure,
    // ⚠️Omitted when absent, so a stored stroke from before tilt existed
    // reads back byte-identical to one recorded now on a device that
    // reports none. A MEASURED upright pen still writes its 1.0.
    if (tiltAltitude != null) 'tiltAltitude': tiltAltitude,
    if (tiltAzimuthDegrees != 0.0) 'tiltAzimuthDegrees': tiltAzimuthDegrees,
    if (speed != 0.0) 'speed': speed,
    'sequence': sequence,
  };

  factory BrushInputSample.fromJson(Map<String, dynamic> json) {
    return BrushInputSample(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 1.0,
      tiltAzimuthDegrees:
          (json['tiltAzimuthDegrees'] as num?)?.toDouble() ?? 0.0,
      tiltAltitude: (json['tiltAltitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
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
          other.speed == speed &&
          other.sequence == sequence;

  @override
  int get hashCode => Object.hash(
    x,
    y,
    pressure,
    tiltAzimuthDegrees,
    tiltAltitude,
    speed,
    sequence,
  );

  @override
  String toString() =>
      'BrushInputSample(x: $x, y: $y, pressure: $pressure, '
      'tiltAzimuthDegrees: $tiltAzimuthDegrees, '
      'tiltAltitude: $tiltAltitude, speed: $speed, sequence: $sequence)';
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

/// Tilt is ONE reading of two numbers, so it has ONE way to be absent — the
/// same law `BrushDab` enforces, because a sample and a dab that disagreed
/// about what "no tilt" looks like would be two spellings of one fact.
void _validateTilt(double? altitude, double azimuthDegrees) {
  if (altitude == null) {
    if (azimuthDegrees != 0.0) {
      throw ArgumentError.value(
        azimuthDegrees,
        'tiltAzimuthDegrees',
        'BrushInputSample.tiltAzimuthDegrees must be 0 when no tilt was '
        'reported.',
      );
    }
    return;
  }
  _validateUnitInterval(altitude, 'tiltAltitude');
}

void _validateUnitInterval(double value, String fieldName) {
  if (!value.isFinite || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'BrushInputSample.$fieldName must be between 0.0 and 1.0 inclusive.',
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
