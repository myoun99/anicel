import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_surface_edit.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_surface_edit_builder.dart';

void main() {
  group('CanvasSurfaceState', () {
    const layerId = LayerId('layer-a');
    const frameId = FrameId('frame-a');

    BitmapSurface surface({int width = 4, int height = 4, int tileSize = 2}) {
      return BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: tileSize,
      );
    }

    BrushDab dab() {
      return BrushDab(
        center: CanvasPoint(x: 0.5, y: 0.5),
        color: 0xFFFF0000,
        size: 1,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      );
    }

    BrushSurfaceEdit editFor(BitmapSurface source) {
      return brushSurfaceEditForBrushDabSequenceOnBitmapSurface(
        surface: source,
        sequence: BrushDabSequence([dab()]),
        layerId: layerId,
        frameId: frameId,
      );
    }

    test('stores currentSurface and nullable lastEdit', () {
      final current = surface();
      final edit = editFor(current);
      final state = CanvasSurfaceState(currentSurface: current, lastEdit: edit);

      expect(state.currentSurface, current);
      expect(state.lastEdit, edit);
    });

    test('initial state can have no lastEdit', () {
      final state = CanvasSurfaceState(currentSurface: surface());

      expect(state.lastEdit, isNull);
    });

    test('hasLastEdit is false when lastEdit is null', () {
      final state = CanvasSurfaceState(currentSurface: surface());

      expect(state.hasLastEdit, isFalse);
    });

    test('hasLastEdit is true when lastEdit is non-null', () {
      final current = surface();
      final state = CanvasSurfaceState(
        currentSurface: current,
        lastEdit: editFor(current),
      );

      expect(state.hasLastEdit, isTrue);
    });

    test('copyWith preserves omitted values', () {
      final current = surface();
      final edit = editFor(current);
      final state = CanvasSurfaceState(currentSurface: current, lastEdit: edit);

      final copied = state.copyWith();

      expect(copied.currentSurface, current);
      expect(copied.lastEdit, edit);
    });

    test('copyWith updates currentSurface', () {
      final current = surface();
      final next = surface(width: 6, height: 6);
      final state = CanvasSurfaceState(currentSurface: current);

      final copied = state.copyWith(currentSurface: next);

      expect(copied.currentSurface, next);
    });

    test('copyWith can set lastEdit', () {
      final current = surface();
      final edit = editFor(current);
      final state = CanvasSurfaceState(currentSurface: current);

      final copied = state.copyWith(lastEdit: edit);

      expect(copied.lastEdit, edit);
    });

    test('copyWith can explicitly clear lastEdit with null', () {
      final current = surface();
      final state = CanvasSurfaceState(
        currentSurface: current,
        lastEdit: editFor(current),
      );

      final copied = state.copyWith(lastEdit: null);

      expect(copied.lastEdit, isNull);
    });

    test('clearLastEdit clears lastEdit', () {
      final current = surface();
      final state = CanvasSurfaceState(
        currentSurface: current,
        lastEdit: editFor(current),
      );

      final cleared = state.clearLastEdit();

      expect(cleared.lastEdit, isNull);
      expect(cleared.currentSurface, current);
    });

    test('equality compares currentSurface and lastEdit', () {
      final current = surface();
      final edit = editFor(current);

      expect(
        CanvasSurfaceState(currentSurface: current, lastEdit: edit),
        CanvasSurfaceState(currentSurface: current.copyWith(), lastEdit: edit),
      );
      expect(
        CanvasSurfaceState(currentSurface: current),
        isNot(CanvasSurfaceState(currentSurface: current, lastEdit: edit)),
      );
    });

    test('hashCode matches equality', () {
      final current = surface();
      final edit = editFor(current);
      final first = CanvasSurfaceState(currentSurface: current, lastEdit: edit);
      final second = CanvasSurfaceState(
        currentSurface: current.copyWith(),
        lastEdit: edit,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });


  });
}
