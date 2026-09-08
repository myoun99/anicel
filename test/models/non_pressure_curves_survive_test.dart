// 🚨A TILT CURVE MUST SURVIVE EVERY HOP IT TAKES.
//
// The round that introduced (target, source) curves shipped three holes at
// once, all found by adversarial review on 2026-09-09 and all of the same
// shape: a path that REBUILT the curve map out of the four legacy pressure
// names, which cannot spell "tilt", and so deleted it in silence.
//
// * `BrushSettings.toJson` wrote only the four pressure keys, so an imported
//   tilt curve died on the very next save — the library persists immediately
//   after an import, which is the exact defect the round set out to end.
// * `BrushSettings.copyWith` rebuilt through the flat constructor.
// * `BrushEditCanvasInputSettings.copyWith` did the same, and a mapped-erase
//   press goes through it — so the pen tail would have drawn without the
//   brush's tilt response while the nib drew with it.
//
// ⚠️Every case here starts from a curve the four names CANNOT express. A test
// that starts from a pressure curve passes against all three bugs.
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';

void main() {
  final tilt = BrushPressureCurve.linearFrom(0.3, maximum: 3.0);
  final speed = BrushPressureCurve.linearFrom(0.1);
  final curves = <BrushDynamicsKey, BrushPressureCurve>{
    (BrushPressureTarget.size, BrushInputSource.tilt): tilt,
    (BrushPressureTarget.opacity, BrushInputSource.speed): speed,
  };

  BrushSettings settings() => BrushSettings(
    curves: curves,
    sizePressureCurve: BrushPressureCurve.identity(),
  );

  test('the preset JSON carries them, and reads them back', () {
    final loaded = BrushSettings.fromJson(settings().toJson());

    expect(
      loaded.shape.curveFor(BrushPressureTarget.size, BrushInputSource.tilt),
      tilt,
      reason: 'the tilt curve, maximum and all',
    );
    expect(
      loaded.shape.curveFor(BrushPressureTarget.opacity, BrushInputSource.speed),
      speed,
    );
    expect(loaded.sizePressureCurve, BrushPressureCurve.identity());
  });

  test('a pressure-only brush still writes the bytes it always did', () {
    // The four legacy keys stay the only home for pressure, so nothing that
    // predates sources changes on disk.
    final json = BrushSettings(
      sizePressureCurve: BrushPressureCurve.identity(),
    ).toJson();
    expect(json.containsKey('curves'), isFalse);
    expect(json.containsKey('sizePressureCurve'), isTrue);
  });

  test('BrushSettings.copyWith keeps them', () {
    for (final copy in [
      settings().copyWith(),
      settings().copyWith(size: 9),
      settings().copyWith(sizePressureCurve: BrushPressureCurve.linearFrom(0.5)),
    ]) {
      expect(
        copy.shape.curveFor(BrushPressureTarget.size, BrushInputSource.tilt),
        tilt,
      );
    }
  });

  test('BrushEditCanvasInputSettings.copyWith keeps them — the mapped-erase '
      'stroke draws with the same brush the nib does', () {
    final input = BrushEditCanvasInputSettings.fromShape(
      BrushShape(curves: curves),
    );
    expect(
      input.copyWith(erase: true).shape.curveFor(
        BrushPressureTarget.size,
        BrushInputSource.tilt,
      ),
      tilt,
    );
    expect(
      input.copyWith(color: 0xFF00FF00).shape.curveFor(
        BrushPressureTarget.size,
        BrushInputSource.tilt,
      ),
      tilt,
    );
  });

test('🚨a TILT-only brush is not "no dynamics" — the pen must draw what '      'the preview shows', () {
    // `hasPressureDynamics` gates the interactive stroke path. Naming the
    // four pressure curves one by one made it answer false for a tilt brush,
    // so the pen skipped its dynamics while the offline commit and the
    // swatch applied them — one brush drawing two ways.
    final tiltOnly = BrushEditCanvasInputSettings.fromShape(
      BrushShape(curves: {
        (BrushPressureTarget.size, BrushInputSource.tilt): tilt,
      }),
    );
    expect(tiltOnly.hasPressureDynamics, isTrue);
    expect(
      BrushEditCanvasInputSettings.fromShape(const BrushShape())
          .hasPressureDynamics,
      isFalse,
    );
  });

  test('an unknown target or source in the JSON is skipped, not fatal', () {
    // A preset written by a later build has to stay loadable, minus what it
    // says that we cannot yet hear.
    final loaded = BrushSettings.fromJson({
      'color': 0xFF000000,
      'size': 4.0,
      'opacity': 1.0,
      'rotationMode': 'fixed',
      'curves': {
        'size.tilt': tilt.toJson(),
        'wobble.tilt': speed.toJson(),
        'size.barometer': speed.toJson(),
        'malformed': speed.toJson(),
      },
    });
    expect(loaded.shape.curves.length, 1);
    expect(
      loaded.shape.curveFor(BrushPressureTarget.size, BrushInputSource.tilt),
      tilt,
    );
  });
}
