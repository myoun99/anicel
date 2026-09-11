import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/persistence/volatile_scratch_files.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/shown_cels.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/session/history_pictures.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/native_engine_path.dart';

/// 🚨★★★UNDO INTO AN ENTRY THE BUDGET PARKED SHOWS NO BLANK FRAME
/// (undo-held-tile-pictures, stage 1, 2026-09-11).
///
/// A parked payload comes back as NEW tile objects, and a tile's picture is
/// keyed on the object — so the step used to land on tiles with no picture
/// at all. Measured on a 225-tile cel: 204 of them blank on the first frame
/// (Settings ▸ Show Unpainted Tiles paints each one magenta), filling in
/// over several. The control at the bottom keeps that measurement honest:
/// if it ever reads zero, the cases above it prove nothing.
///
/// ⚠️TWO CANVASES, because they register differently. The ink view paints
/// the cel's own tiles; the DRAWING canvas hands its painter to the layer
/// stack and paints the active row THROUGH its colour keys, so the tiles on
/// screen are other objects than the cel's. A walk on the first alone left
/// the second's registration untested — a mutant deleting it survived.
///
/// The cel is 64 tiles because the composed stand-in covers sixteen a paint
/// — on a smaller cel it hides the defect this exists to catch.
void main() {
  testWidgets('🚨OUTRUN, where the engine cannot upload on the spot (Skia): '
      'an undo into a parked entry WAITS for its pictures, and no frame on '
      'the way is blank', (tester) async {
    await _outrun(tester, await _Walk.draw(tester));
  });

  testWidgets('🚨the same on the DRAWING canvas, painting the row through a '
      'colour key', (tester) async {
    await _outrun(tester, await _Walk.draw(tester, drawingCanvas: true));
  });

  testWidgets('at a human pace the next undo is ready BEFORE the press: it '
      'lands at once, and whole', (tester) async {
    final walk = await _Walk.draw(tester);

    for (final k in [5, 4, 3, 2, 1]) {
      walk.press();
      // ⛔Mutation: no warm after a landing → the parked ones wait.
      expect(walk.history.undoCount, k, reason: 'undo $k landed at the press');
      await tester.pump();
      await walk.expectWhole(showing: k - 1, why: 'the first frame of undo $k');
      await walk.settle(); // The user looks at it for a moment.
    }
  });

  testWidgets('where the engine uploads on the spot (Impeller), an undo into '
      'a parked entry lands AT ONCE, and whole', (tester) async {
    debugSyncImageUploadOverride = _uploadUniformTile;
    addTearDown(() => debugSyncImageUploadOverride = null);
    final walk = await _Walk.draw(tester);

    for (final k in [5, 4, 3, 2, 1]) {
      walk.press();
      // ⛔Mutation: pictures started a ration at a time → the parked ones
      // wait a frame, and the press has not landed here.
      expect(walk.history.undoCount, k, reason: 'undo $k landed at the press');
    }
    await tester.pump();
    await walk.expectWhole(showing: 0, why: 'the first frame of undo 1');
  });

  testWidgets('control: straight to the history, an undo into a parked entry '
      'DOES land blank — the measurement can see it', (tester) async {
    final walk = await _Walk.draw(tester);
    walk.history.undo(); // 5
    walk.history.undo(); // 4
    await walk.settle();

    walk.history.undo(); // 3: parked, read back inside the step
    await tester.pump();

    final seen = await walk.look(showing: 2);
    expect(seen.magenta, greaterThan(20000));
  });
}

/// Undoes 5 and 4 (in RAM), then straight on into 3, 2 and 1 (parked),
/// faster than any warm-up could go — and looks at every frame on the way.
Future<void> _outrun(WidgetTester tester, _Walk walk) async {
  walk.press();
  expect(walk.history.undoCount, 5);
  await tester.pump();
  await walk.expectWhole(showing: 4, why: 'the first frame of undo 5');
  walk.press();
  expect(walk.history.undoCount, 4, reason: 'resident: lands at the press');
  for (final k in [3, 2, 1]) {
    walk.press();
    // ⛔Mutation: land at once → the next frame is mostly magenta.
    expect(walk.history.undoCount, k + 1, reason: 'undo $k waits');
    var frames = 0;
    while (walk.history.undoCount == k + 1) {
      expect(frames, lessThan(80), reason: 'undo $k never landed');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      frames += 1;
      if (walk.history.undoCount == k + 1) {
        // Still the picture from before the press — whole.
        await walk.expectWhole(
          showing: k,
          why: 'waiting on undo $k, frame $frames',
        );
      }
    }
  }
  await tester.pump();
  await walk.expectWhole(showing: 0, why: 'the first frame of undo 1');
}

/// Six whole-cel strokes in six colours on a 1024² cel (64 tiles), under an
/// undo budget of two cels — so the four deep entries park, exactly the
/// way a long session or a memory warning leaves them.
class _Walk {
  _Walk._(this.tester, this.coordinator, this.history);

  static const _size = CanvasSize(width: 1024, height: 1024);
  static const _cel = 64 * 128 * 128 * 4;
  static const _capture = ValueKey<String>('undo-into-the-room');

  /// Stroke k paints colour k — and none of them reads as magenta.
  static const _colours = [
    0xFFFF0000,
    0xFF00FF00,
    0xFF0000FF,
    0xFFFFFF00,
    0xFF00FFFF,
    0xFFFF8000,
  ];

  /// What the drawing canvas's row is painted through: the white specks
  /// every stroke leaves go, so every tile it paints is a keyed copy.
  static final _deleteWhite = ResolvedLayerEffect(
    kind: EffectKind.deleteColor,
    values: const [255, 255, 255, 0, 100],
  );

  final WidgetTester tester;
  final BrushFrameEditingCoordinator coordinator;
  final HistoryManager history;
  final List<BrushStrokeHistoryCommand> strokes = [];
  late final HistoryPictures pictures = HistoryPictures(history: history);

  /// [drawingCanvas]: the panel in the drawing editor's shape — it hands
  /// the active row's painter to the layer stack (here, the underlay paints
  /// it) and draws the row through a colour key. Otherwise the ink view
  /// paints the cel's own tiles.
  static Future<_Walk> draw(
    WidgetTester tester, {
    bool drawingCanvas = false,
  }) async {
    debugQaEngineLibraryPathOverride = nativeEngineLibraryPathOrNull();
    addTearDown(() => debugQaEngineLibraryPathOverride = null);
    MeasurementMode.showUnpaintedTiles.value = true;
    addTearDown(() => MeasurementMode.showUnpaintedTiles.value = false);

    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: keys,
      canvasSize: _size,
    );
    // Two cels of RAM. The setter narrows the room along with it, and the
    // room is not what this is about — so it is opened again.
    final history = HistoryManager()..byteBudget = 2 * _cel;
    VolatileScratchFiles.ceilingBytes = 0;
    addTearDown(() => VolatileScratchFiles.ceilingBytes = 0);
    addTearDown(history.dispose);
    final sink = BrushEditCacheInvalidationSink();
    final transformOptions = ValueNotifier(TransformToolOptions.defaults);
    addTearDown(transformOptions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: _capture,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              canvasSize: _size,
              availableFrameKeys: keys,
              cacheInvalidationSink: sink,
              historyManager: history,
              brushToolState: BrushToolState.defaults.copyWith(
                tool: CanvasTool.move,
              ),
              selectionCommands: CanvasSelectionCommands(),
              viewport: CanvasViewport(),
              shapeFillDabFor: (shape, color) => buildShapeFillDab(
                shape: shape,
                color: color,
                options: const FloodFillOptions(expandPx: 0, antiAlias: false),
              ),
              transformOptions: transformOptions,
              activeStrokeOverlayModel: drawingCanvas
                  ? ActiveStrokeOverlayModel()
                  : null,
              activeSourceEffects: drawingCanvas ? [_deleteWhite] : const [],
              viewportUnderlayBuilder: drawingCanvas
                  ? (context, viewport, painter, float) => painter == null
                        ? const SizedBox.shrink()
                        : CustomPaint(
                            painter: painter,
                            size: Size(
                              _size.width.toDouble(),
                              _size.height.toDouble(),
                            ),
                          )
                  : null,
            ),
          ),
        ),
      ),
    );
    final walk = _Walk._(tester, coordinator, history);
    addTearDown(walk.pictures.dispose);
    expect(
      ShownCels.instance.isShown(coordinator.activeFrameKey),
      isTrue,
      reason: 'the canvas says which cel it paints',
    );
    await walk.settle();
    for (final colour in _colours) {
      final stroke = BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: BrushStrokeCommitData(sourceDabs: _strokeOf(colour)),
        cacheInvalidationSink: sink,
      );
      history.execute(stroke);
      walk.strokes.add(stroke);
      await walk.settle();
    }
    await tester.runAsync(history.drainSpilling);
    // The deep four parked (the first stroke's before-picture is empty, so
    // it weighs nothing either way), the top two still in RAM.
    expect(
      [for (final s in walk.strokes) s.estimatedRetainedBytes(undone: false)],
      [0, 0, 0, 0, _cel, _cel],
    );
    return walk;
  }

  /// Colour k over the whole cel, and a white speck in every tile.
  static List<BrushDab> _strokeOf(int colour) => [
    _dab(512, 512, colour, 1020, 0),
    for (var i = 0; i < 64; i += 1)
      _dab(64.0 + 128 * (i % 8), 64.0 + 128 * (i ~/ 8), 0xFFFFFFFF, 8, i + 1),
  ];

  static BrushDab _dab(
    double x,
    double y,
    int colour,
    double size,
    int sequence,
  ) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: colour,
    size: size,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
  );

  void press() => pictures.step(undo: true, apply: history.undo);

  /// Real time for the decodes, and a frame after each landing.
  Future<void> settle() async {
    for (var i = 0; i < 12; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

  /// The frame on screen: magenta pixels — a tile the painter had nothing
  /// for — and pixels of stroke [showing]'s colour.
  Future<({int magenta, int ink})> look({required int showing}) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = boundary.toImageSync();
    final colour = _colours[showing];
    final r0 = (colour >> 16) & 0xFF;
    final g0 = (colour >> 8) & 0xFF;
    final b0 = colour & 0xFF;
    var magenta = 0;
    var ink = 0;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      for (var i = 0; i < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        if (r > 140 && b > 140 && g + 60 < r && (r - b).abs() < 40) {
          magenta += 1;
        }
        if ((r - r0).abs() < 8 && (g - g0).abs() < 8 && (b - b0).abs() < 8) {
          ink += 1;
        }
      }
    });
    image.dispose();
    return (magenta: magenta, ink: ink);
  }

  /// No blank pixel on screen, and stroke [showing]'s picture on it — the
  /// second half is what says the first measured anything.
  Future<void> expectWhole({required int showing, required String why}) async {
    final seen = await look(showing: showing);
    expect(seen.magenta, 0, reason: why);
    expect(seen.ink, greaterThan(20000), reason: '$why: the canvas is seen');
  }
}

/// Impeller's synchronous upload, for tiles of one colour: the picture of
/// the colour the bytes hold. Enough for a measurement that only asks
/// whether each tile has the right picture or none.
ui.Image _uploadUniformTile(Uint8List pixels, int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()
      ..color = Color.fromARGB(pixels[3], pixels[0], pixels[1], pixels[2]),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}
