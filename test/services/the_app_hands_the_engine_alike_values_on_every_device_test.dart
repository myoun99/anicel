import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/color_matrix.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/shaded_passes.dart';

import '../helpers/pinned_fingerprints.dart';

/// 🧭관제 (connection-round-checklist I Ⓒ①, 2026-11-07): what the app works
/// out with a cos, a sin, an exp or a pow and hands the engine — a
/// directional blur's steps, a radial blur's turns, scales and maps, a
/// hue's colour matrix — is the platform's libm's, which may differ by
/// device in a last bit (gpu-int-spec-canvas 대조 필요 ①). Past the
/// engine's own rounding such a bit can move a pixel, and under a pow's
/// ceiling the number of taps. So each is pinned bit for bit in the one
/// ledger: a device whose libm differs fails here, by which of the three,
/// before a picture shows it.
///
/// Every value as its IEEE double, little-endian, in the order written —
/// each effect's own path (`shadedPassesOf`, `hueSaturationMatrix`) over a
/// grid of its parameters, with lengths where a pow's ceiling turns: 36 =
/// 6², and at four times 144 = 12², 1331 = 11³, 1728 = 12³.
void main() {
  const paper = ui.Rect.fromLTWH(0, 0, 1920, 1080);

  List<LineBoxPass> passesOf(ResolvedLayerEffect effect) =>
      shadedPassesOf(effect, paper: paper).cast();

  test('a directional blur hands the pinned steps', () {
    final values = <double>[];
    // ↩️Four times as long was a raster drawn at four times
    // (`DrawSpace.preScaled(4)`) till the Flutter chain went
    // (the-flutter-fx-chain-is-a-second-chain): the same doubles, so the
    // same pin.
    for (final times in const [1.0, 4.0]) {
      for (final length in _lengths) {
        for (var quarter = -720; quarter <= 720; quarter += 1) {
          final effect = _effect(EffectKind.directionalBlur, {
            'direction': quarter / 4,
            'blurLength': length * times,
          });
          for (final pass in passesOf(effect)) {
            values.addAll(_handed(pass));
          }
        }
      }
    }
    expect(
      fingerprintHex(_bytesOf(values)),
      pinnedFingerprint('values/directional-blur-passes'),
    );
  });

  test('a cube of taps is laid as its root, not one more', () {
    // The ceiling a pow's last bit can turn: 1331 raster pixels are three
    // passes of 11 taps (11³), 1728 of 12.
    for (final (length, taps) in [(332.75, 11), (432.0, 12)]) {
      final effect = _effect(EffectKind.directionalBlur, {
        'blurLength': length * 4,
      });
      expect(
        passesOf(effect).map((p) => p.taps),
        [taps, taps, taps],
        reason: '${length * 4} pixels',
      );
    }
  });

  test('a radial blur hands the pinned turns, scales and maps', () {
    final values = <double>[];
    for (final center in [null, CanvasPoint(x: 100, y: 50)]) {
      for (final type in [0.0, 1.0]) {
        for (final antialiasing in [0.0, 1.0]) {
          for (var half = 1; half <= 200; half += 1) {
            final effect = _effect(
              EffectKind.radialBlur,
              {'amount': half / 2, 'type': type, 'antialiasing': antialiasing},
              points: {'center': center},
            );
            for (final pass in passesOf(effect)) {
              values.addAll(_handed(pass));
            }
          }
        }
      }
    }
    expect(
      fingerprintHex(_bytesOf(values)),
      pinnedFingerprint('values/radial-blur-passes'),
    );
  });

  test('a hue hands the pinned colour matrix', () {
    final values = <double>[];
    for (final (saturation, lightness) in [
      (0.0, 0.0),
      (-60.0, 0.0),
      (35.0, -20.0),
      (100.0, 100.0),
    ]) {
      for (var eighth = -1440; eighth <= 1440; eighth += 1) {
        values.addAll(
          hueSaturationMatrix(
            hueDegrees: eighth / 8,
            saturation: saturation,
            lightness: lightness,
          ),
        );
      }
    }
    expect(
      fingerprintHex(_bytesOf(values)),
      pinnedFingerprint('values/hue-saturation-matrix'),
    );
  });
}

/// Blur lengths, canvas pixels: under, at and past one pass of 32 taps, a
/// square, and past four times them the cubes 1331 and 1728 and the most.
const _lengths = [
  0.5, 1.0, 7.25, 32.0, 33.0, 36.0, 100.0, 332.75, 432.0, 499.75, 500.0, //
];

/// [kind] with [lanes] by parameter id, its defaults for the rest.
ResolvedLayerEffect _effect(
  EffectKind kind,
  Map<String, double> lanes, {
  Map<String, CanvasPoint?> points = const {},
}) {
  final ids = {for (final spec in kind.parameters) spec.id};
  if (!ids.containsAll(lanes.keys)) {
    throw ArgumentError('${kind.name} has no ${lanes.keys}');
  }
  return ResolvedLayerEffect(
    kind: kind,
    values: [
      for (final spec in kind.parameters) lanes[spec.id] ?? spec.defaultValue,
    ],
    points: points,
  );
}

/// What a pass hands its shader and the engine, in order.
List<double> _handed(LineBoxPass pass) => [
  pass.stepX,
  pass.stepY,
  pass.turn,
  pass.grow,
  pass.centerX,
  pass.centerY,
  pass.taps.toDouble(),
  ...pass.firstMap,
  ...pass.eachMap,
];

Uint8List _bytesOf(List<double> values) {
  final bytes = ByteData(values.length * 8);
  for (final (index, value) in values.indexed) {
    bytes.setFloat64(index * 8, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
