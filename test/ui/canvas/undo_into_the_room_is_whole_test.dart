import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
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
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
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
///
/// Stage 2 (2026-09-15) lets the pictures of entries deeper than the next
/// step go, so the cases below also pin what must NOT go on screen: a
/// fork's picture. The two a tile not ready yet borrows are pinned at the
/// cache's door (`a_lent_tile_picture_is_not_let_go_test`) — ⚠️a widget
/// walk cannot reach them: without real time no decode lands and nothing
/// schedules the paint that would borrow, so the frame it would look at is
/// the same with the release on and off (measured).
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

  testWidgets('🚨stage 2: an entry DEEPER than the next step keeps its tiles '
      'but not their pictures — the next step and the screen keep theirs', (
    tester,
  ) async {
    // 유저 2026-09-11 「전부 확인했으니 진행해도되」: hold what is on screen
    // and the next step each way, let the rest go (undo-held-tile-pictures,
    // stage 2). Eight cels of budget park nothing, so every entry is RAM and
    // only the release can take a picture away.
    final walk = await _Walk.draw(tester, cels: 8);
    for (final k in [0, 1, 2, 3]) {
      // ⛔Mutation: no release → the deep ones keep all 64.
      expect(
        _pictured(walk.surfaces[k]),
        0,
        reason: 'stroke ${k + 1}, which entry ${k + 2} puts back, is deep',
      );
    }
    expect(_pictured(walk.surfaces[4]), 64, reason: 'the next undo');
    expect(_pictured(walk.surfaces[5]), 64, reason: 'the screen');
    walk.press();
    expect(walk.history.undoCount, 5, reason: 'the next step lands at once');
    await tester.pump();
    await walk.expectWhole(showing: 4, why: 'the first frame of undo 6');
  });

  testWidgets('🚨stage 2: the same on the REDO side — past the next redo, an '
      'entry keeps its tiles but not their pictures', (tester) async {
    final walk = await _Walk.draw(tester, cels: 8);
    for (var undo = 0; undo < 3; undo += 1) {
      if (undo > 0) {
        await walk.settle();
      }
      walk.press();
      await tester.pump();
    }
    // ⚠️Read on the frame the third undo lands, before real time passes: the
    // warm-up re-makes the next step's pictures right after the pass, so a
    // pass that wrongly let them go is healed once decodes land. Read after
    // a settle, three mutants survived here (measured 2026-09-15).
    // Redo puts strokes 4, 5 and 6 back in that order, so 4 is next.
    // ⛔Mutation: the redo stack read as if applied → stroke 4 loses its
    // pictures.
    expect(
      _pictured(walk.surfaces[3]),
      64,
      reason: 'the next redo lands on stroke 4',
    );
    expect(
      _pictured(walk.surfaces[4]),
      0,
      reason: 'stroke 5 is past the next redo',
    );
  });

  testWidgets('🚨stage 2: an undo and its redo leave the next undo holding its '
      'pictures — and the entry behind it none', (tester) async {
    final walk = await _Walk.draw(tester, cels: 8);
    walk.press();
    await tester.pump();
    await walk.settle();
    walk.pictures.step(undo: false, apply: walk.history.redo);
    expect(walk.history.undoCount, 6, reason: 'the redo landed at the press');
    // Read on the frame the redo lands, for the reason the case above gives.
    await tester.pump();
    // ⛔Mutation: the undo stack read on the wrong half, or its top counted
    // deep → stroke 5, which the next undo puts back, loses its pictures.
    expect(
      _pictured(walk.surfaces[4]),
      64,
      reason: 'the next undo lands on stroke 5',
    );
    expect(_pictured(walk.surfaces[3]), 0, reason: 'stroke 4 is deep again');
  });

  testWidgets('🚨stage 2: a stand-in on a deep entry goes too — the picture a '
      'confirm composes for a tile whose truth never lands', (tester) async {
    final walk = await _Walk.draw(tester, cels: 8);
    final cache = BitmapTileImageCache.instance;
    // Stroke 1's tiles sit under entry 2, deep, and their truth has gone.
    // Give one the stand-in a confirm composes for a tile off screen.
    final tile = walk.surfaces[0].tiles.values.first;
    expect(cache.imageFor(tile), isNull, reason: 'premise: its truth went');
    cache.putProvisional(
      tile,
      _uploadUniformTile(Uint8List(4), tile.size, tile.size),
    );
    walk.press();
    await tester.pump();
    // ⛔Mutation: the pass asks after truth only → a tile holding nothing
    // but a stand-in is passed over, and keeps it as long as the history.
    expect(cache.hasProvisional(tile), isFalse);
  });

  testWidgets('control: with no store to ask, every entry keeps its pictures', (
    tester,
  ) async {
    final walk = await _Walk.draw(tester, cels: 8, releases: false);
    expect(
      _pictured(walk.surfaces[0]),
      64,
      reason: 'the release took them, not a budget or a collection',
    );
  });

  testWidgets('🚨stage 2: a picture a FORK still shows stays — a duplicate '
      'holds the very tiles an entry holds alone', (tester) async {
    // A paste, a duplicate and an unlink store the SAME surface under a
    // second key (`carryBakedPictures`, `UnlinkLayerCommand`), so stroke 1's
    // tiles are a deep entry's AND the second cel's picture.
    final walk = await _Walk.draw(tester, cels: 8, forkFirstStroke: true);
    final fork = walk.keys[1];
    expect(
      walk.coordinator.frameStore.hotBakedSurfaceOrNull(fork),
      same(walk.surfaces[0]),
      reason: 'still hot — a cold fork holds no tile objects to measure',
    );
    walk.coordinator.selectFrame(fork);
    await tester.pumpWidget(walk.tree());
    // ⛔Mutation: `holdsTile` answers false → the fork's first frame is
    // magenta.
    await walk.expectWhole(showing: 0, why: 'the first frame on the fork');
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

/// Undoes 5 (the next step, ready), then straight on into 4 (in RAM, its
/// pictures let go while it was deeper) and 3, 2 and 1 (parked), faster
/// than any warm-up could go — and looks at every frame on the way.
Future<void> _outrun(WidgetTester tester, _Walk walk) async {
  walk.press();
  expect(walk.history.undoCount, 5);
  await tester.pump();
  await walk.expectWhole(showing: 4, why: 'the first frame of undo 5');
  // ↩️Undo 4 used to land at this press too: resident, so its pictures
  // lived as long as its tiles. Stage 2 holds only the next step each way
  // (the 2026-09-11 plan), so it waits for them like the parked ones.
  for (final k in [4, 3, 2, 1]) {
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
  _Walk._(
    this.tester,
    this.coordinator,
    this.history, {
    required this.keys,
    required this.tree,
    required bool releases,
  }) : pictures = HistoryPictures(
         history: history,
         store: releases ? coordinator.frameStore : null,
       );

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
  final List<BrushFrameKey> keys;

  /// The panel as pumped. It reads the active cel when it builds, so a case
  /// that switches cels pumps this again.
  final Widget Function() tree;
  final List<BrushStrokeHistoryCommand> strokes = [];

  /// The cel after each stroke: `surfaces[k]` is the picture entry k + 2
  /// puts back, and the last one is the screen.
  final List<BitmapSurface> surfaces = [];
  final HistoryPictures pictures;

  /// [drawingCanvas]: the panel in the drawing editor's shape — it hands
  /// the active row's painter to the layer stack (here, the underlay paints
  /// it) and draws the row through a colour key. Otherwise the ink view
  /// paints the cel's own tiles.
  ///
  /// [cels]: the undo budget, in cels — at two the deep four park.
  /// [releases]: whether pictures of the deeper entries are let go.
  /// [forkFirstStroke]: the second cel is given stroke 1's surface itself,
  /// the way a paste, a duplicate or an unlink shares one.
  static Future<_Walk> draw(
    WidgetTester tester, {
    bool drawingCanvas = false,
    int cels = 2,
    bool releases = true,
    bool forkFirstStroke = false,
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
    // [cels] of RAM. The setter narrows the room along with it, and the
    // room is not what this is about — so it is opened again.
    final history = HistoryManager()..byteBudget = cels * _cel;
    VolatileScratchFiles.ceilingBytes = 0;
    addTearDown(() => VolatileScratchFiles.ceilingBytes = 0);
    addTearDown(history.dispose);
    final sink = BrushEditCacheInvalidationSink();
    final transformOptions = ValueNotifier(TransformToolOptions.defaults);
    addTearDown(transformOptions.dispose);
    final selectionCommands = CanvasSelectionCommands();
    final view = CanvasViewport();
    final overlay = drawingCanvas ? ActiveStrokeOverlayModel() : null;
    final effects = drawingCanvas
        ? [_deleteWhite]
        : const <ResolvedLayerEffect>[];
    Widget tree() => MaterialApp(
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
            selectionCommands: selectionCommands,
            viewport: view,
            shapeFillDabFor: (shape, color) => buildShapeFillDab(
              shape: shape,
              color: color,
              options: const FloodFillOptions(expandPx: 0, antiAlias: false),
            ),
            transformOptions: transformOptions,
            activeStrokeOverlayModel: overlay,
            activeSourceEffects: effects,
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
    );
    await tester.pumpWidget(tree());
    final walk = _Walk._(
      tester,
      coordinator,
      history,
      keys: keys,
      tree: tree,
      releases: releases,
    );
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
      walk.surfaces.add(coordinator.currentSurfaceOf(coordinator.activeFrameKey));
      if (forkFirstStroke && walk.surfaces.length == 1) {
        coordinator.frameStore.storeBakedSurface(keys[1], walk.surfaces.first);
      }
    }
    await tester.runAsync(history.drainSpilling);
    // Past the top [cels] the deep ones parked (the first stroke's
    // before-picture is empty, so it weighs nothing either way).
    expect(
      [for (final s in walk.strokes) s.estimatedRetainedBytes(undone: false)],
      [
        0,
        for (var k = 1; k < _colours.length; k += 1)
          if (k < _colours.length - cels) 0 else _cel,
      ],
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

/// How many of [surface]'s tiles have their own picture.
int _pictured(BitmapSurface surface) => surface.tiles.values
    .where((tile) => BitmapTileImageCache.instance.imageFor(tile) != null)
    .length;

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
