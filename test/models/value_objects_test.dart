import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/stroke_point.dart';

void main() {
  group('value objects', () {
    test('CanvasSize creates and round-trips through JSON', () {
      const size = CanvasSize(width: 1920, height: 1080);

      expect(size.width, 1920);
      expect(size.height, 1080);
      expect(CanvasSize.fromJson(size.toJson()), size);
    });

    test(
      'BrushSettings creates with defaults and round-trips through JSON',
      () {
        final brush = BrushSettings();

        expect(brush.color, 0xFF000000);
        expect(brush.size, 4.0);
        expect(brush.opacity, 1.0);
        expect(BrushSettings.fromJson(brush.toJson()), brush);
      },
    );

    test('BrushPresetId equality works', () {
      expect(const BrushPresetId('brush-a'), const BrushPresetId('brush-a'));
      expect(
        const BrushPresetId('brush-a'),
        isNot(const BrushPresetId('brush-b')),
      );
    });

    test('BrushPresetId toJson/fromJson round-trips', () {
      const id = BrushPresetId('brush-a');

      expect(BrushPresetId.fromJson(id.toJson()), id);
    });

    test('StrokePoint creates and round-trips through JSON', () {
      const point = StrokePoint(x: 12.5, y: 24.75);

      expect(point.x, 12.5);
      expect(point.y, 24.75);
      expect(StrokePoint.fromJson(point.toJson()), point);
    });

    test('Frame defaults to unnamed', () {
      final frame = Frame(
        id: const FrameId('frame'),
        duration: 1,
        strokes: const [],
      );

      expect(frame.name, isNull);
    });
  });
}
