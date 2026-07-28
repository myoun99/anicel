import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_input_sample.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';

void main() {
  group('Stroke BrushSettings compatibility', () {
    test('Stroke serializes BrushSettings with new fields', () {
      final stroke = Stroke(
        id: const StrokeId('stroke-1'),
        points: const [StrokePoint(x: 1, y: 2)],
        brushSettings: BrushSettings(
          color: 0xFF123456,
          size: 8,
          opacity: 0.7,
          flow: 0.6,
          hardness: 0.5,
          spacing: 0.25,
          tipShape: BrushTipShape.square,
          sizePressureCurve: BrushPressureCurve.linearFrom(0.2),
          opacityPressureCurve: BrushPressureCurve.identity(),
        ),
      );

      final brushJson =
          stroke.toJson()['brushSettings'] as Map<String, dynamic>;

      expect(brushJson['flow'], 0.6);
      expect(brushJson['hardness'], 0.5);
      expect(brushJson['spacing'], 0.25);
      expect(brushJson['tipShape'], 'square');
      expect(brushJson['sizePressureCurve'], [0.0, 0.2, 1.0, 1.0]);
      expect(brushJson['opacityPressureCurve'], [0.0, 0.0, 1.0, 1.0]);
    });

    test(
      'Stroke deserializes legacy BrushSettings nested in old stroke JSON',
      () {
        final stroke = Stroke.fromJson({
          'id': const StrokeId('stroke-legacy').toJson(),
          'points': const [
            {'x': 1, 'y': 2},
          ],
          'brushSettings': const {
            'color': 0xFFFFFFFF,
            'size': 6,
            'opacity': 0.5,
          },
        });

        expect(
          stroke.brushSettings,
          BrushSettings(color: 0xFFFFFFFF, size: 6, opacity: 0.5),
        );
        expect(stroke.brushSettings.flow, 1.0);
        expect(stroke.brushSettings.tipShape, BrushTipShape.round);
      },
    );

    test('Stroke stores StrokePoint data and BrushSettings directly', () {
      final brushSettings = BrushSettings(size: 5);
      final stroke = Stroke(
        id: const StrokeId('stroke-direct-storage'),
        points: const [StrokePoint(x: 1, y: 2)],
        brushSettings: brushSettings,
      );
      final preset = BrushPreset(
        id: const BrushPresetId('preset-1'),
        name: 'Preset 1',
        settings: brushSettings.copyWith(size: 9),
      );
      final inputSample = BrushInputSample(x: 1, y: 2);

      expect(stroke.points, isA<List<StrokePoint>>());
      expect(stroke.points.single, isA<StrokePoint>());
      expect(stroke.brushSettings, same(brushSettings));
      expect(stroke.brushSettings, isNot(preset));
      expect(stroke.points.single, isNot(inputSample));
    });

    test('Stroke keeps BrushSettings as a value snapshot', () {
      final presetSettings = BrushSettings(size: 4, flow: 0.5);
      final stroke = Stroke(
        id: const StrokeId('stroke-snapshot'),
        points: const [StrokePoint(x: 1, y: 2)],
        brushSettings: presetSettings,
      );
      final changedSettings = presetSettings.copyWith(size: 10);

      expect(stroke.brushSettings, presetSettings);
      expect(stroke.brushSettings, isNot(changedSettings));
      expect(stroke.brushSettings.size, 4);
    });
  });
}
