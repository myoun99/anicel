import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨ANOTHER CEL UNDER THE PEN IS NO CHANGE OF THE PICTURE (I-22 · 📏S5 cut
/// 352, 2026-11-01): a click on another row leaves the frame's key where it
/// was, and the picture shown holds that row's stored pixels as it holds
/// every row's. Measured from what it held of the row left, every tile of
/// the row come to 「moved」, and the frame was drawn as it stands — 5–9 ms a
/// paint in debug — until its key moved, the first stroke on the row clicked
/// composing the whole frame a step at a time.
///
/// ⛔A picture that holds what no cel stores, or short of what the row left
/// shows, is not told so: what stands between it and the frame has to go in.
///
/// The writes are counted, and land as they are let ([_WritesHeld]): a step
/// asked of the picture is the oracle, the GPU's own writes are pinned
/// elsewhere (`a_stroke_is_written_into_the_picture_shown_test`).
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const under = Color(0xFF203040);
  BrushFrameKey celOf(String row) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(row),
    frameId: const FrameId('f'),
  );
  final low = celOf('low');
  final high = celOf('high');
  final cut = Cut(
    id: low.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [],
  );
  final frame = (
    cut: cut,
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final view = CanvasViewport(panX: 8, panY: 4);
  final screen = GlobalKey();
  final at = TileCoord(x: 0, y: 0);
  final beside = TileCoord(x: 1, y: 0);

  BitmapTile tileOf(List<int> colour) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, colour);
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  final stroke = tileOf(const [0x40, 0x00, 0x00, 0x80]);

  /// The two rows, the pen on [pen] and the other drawn from its stored
  /// image.
  List<CompositeNode<CanvasStackRow>> stackUnder(BrushFrameKey? pen) => [
    for (final cel in [low, high])
      CompositeLeaf<CanvasStackRow>(
        cel == pen
            ? CanvasActiveLayerRow(opacity: 1, frameKey: cel)
            : CanvasLayerImageRequest(frameKey: cel, opacity: 1),
      ),
  ];

  /// A canvas on the two rows: their cels, the frame's picture, the view
  /// and the overlay of the pen.
  Future<
    ({
      Future<void> Function(
        BrushFrameKey? pen, {
        Map<TileCoord, BitmapTile> more,
      })
      penOn,
      void Function(TileCoord where) step,
      _WritesHeld gpu,
      FramePictureStore<FramePictureKey> store,
      FramePictureKey picture,
      Future<FramePictureKey> Function(BrushFrameKey cel) landOn,
    })
  >
  aCanvas(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      low: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {at: tileOf(const [0x00, 0x40, 0x00, 0x80])},
      ),
      high: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {beside: tileOf(const [0x00, 0x00, 0x40, 0x80])},
      ),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final gpu = _WritesHeld();
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    var nodes = stackUnder(low);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
    );
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);
    final picture = run.pictures.keyOfStack(nodes, frame);
    expect(
      run.pictures.keyOfStack(stackUnder(high), frame),
      picture,
      reason: '⛔premise: the pen\'s row is drawn what it stores either way',
    );

    BitmapSurface surfaceOf(BrushFrameKey cel) => BrushFrameDisplayCacheService(
      frameStore: cels,
      canvasSize: canvasSize,
    ).prepareFramePreview(cel).previewSurface;

    Future<void> penOn(
      BrushFrameKey? pen, {
      Map<TileCoord, BitmapTile> more = const {},
    }) {
      nodes = stackUnder(pen);
      return tester.pumpWidget(
        onAScreen(
          screen,
          size: viewSize,
          under: under,
          view: standingOn(
            run,
            key: const ValueKey(0),
            picture: frame,
            nodes: nodes,
            viewport: view,
            live: (
              activeSurfacePainter: pen == null
                  ? null
                  : BitmapSurfacePainter(
                      surface: BitmapSurface(
                        canvasSize: canvasSize,
                        tileSize: tileSize,
                        tiles: {...surfaceOf(pen).tiles, ...more},
                      ),
                      overlayModel: overlay,
                      showTransparentBackground: false,
                      lineage: 'another-cel-under-the-pen',
                    ),
              floatOverlay: null,
              liftedRows: const {},
            ),
          ),
        ),
      );
    }

    await penOn(low);
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return (
      penOn: penOn,
      step: (where) =>
          overlay.showResultTiles([PromotedStrokeTile(where, stroke, 1)]),
      gpu: gpu,
      store: store,
      picture: picture,
      landOn: (cel) async {
        cels.storeBakedSurface(
          cel,
          BitmapSurface(
            canvasSize: canvasSize,
            tileSize: tileSize,
            tiles: {...surfaceOf(cel).tiles, at: stroke},
          ),
        );
        cels.markCelEdited(cel);
        overlay.reset();
        final drawn = run.pictures.keyOfStack(nodes, frame);
        expect(drawn, isNot(picture), reason: '⛔premise: the key moved');
        await penOn(cel);
        return drawn;
      },
    );
  }

  bool drawnAsItStands(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(FramePictureView),
        matching: find.byType(CustomPaint),
      ),
    );
    // ignore: avoid_dynamic_calls
    return (paint.painter as dynamic).standing.whole as bool;
  }

  testWidgets('🚨the screen shows the picture it showed, and the frame is not '
      'drawn as it stands', (tester) async {
    final (:penOn, step: _, :gpu, store: _, picture: _, landOn: _) =
        await aCanvas(tester);
    final before = await shotOf(tester, screen);

    await penOn(high);
    await tester.pump();

    expect(drawnAsItStands(tester), isFalse);
    expect(gpu.written, 0, reason: 'nothing changed, so nothing goes in');
    expect(differences(before, await shotOf(tester, screen)), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨the first stroke on the row clicked is written into the '
      'picture — not the whole frame composed a step at a time', (
    tester,
  ) async {
    final (:penOn, :step, :gpu, :store, :picture, landOn: _) = await aCanvas(
      tester,
    );

    await penOn(high);
    gpu.holdsRenders = true;
    step(at);
    await tester.pump();

    expect(
      store.landingOf(keptByTheCanvas(tester, picture)),
      isNotNull,
      reason: 'the step is on its way into the picture',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨and that stroke, landed, moves the picture to the frame\'s '
      'next key: the cel the pen is on is the one it came to', (tester) async {
    final (:penOn, :step, :gpu, :store, picture: _, :landOn) = await aCanvas(
      tester,
    );

    await penOn(high);
    gpu.holdsRenders = true;
    step(at);
    await tester.pump();
    final drawn = await landOn(high);

    expect(
      store.landingOf(drawn),
      isNotNull,
      reason: 'moved where it stands, ⛔not laid again whole',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row the pen cannot draw on leaves it too, and back from it '
      'the next stroke is written in', (tester) async {
    final (:penOn, :step, :gpu, :store, :picture, landOn: _) = await aCanvas(
      tester,
    );

    await penOn(null);
    await tester.pump();
    expect(drawnAsItStands(tester), isFalse);

    await penOn(high);
    gpu.holdsRenders = true;
    step(at);
    await tester.pump();
    expect(store.landingOf(keptByTheCanvas(tester, picture)), isNotNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('⛔a picture that holds a step no cel stores is not told it '
      'holds the frame: what the row left drew goes on being answered for', (
    tester,
  ) async {
    final (:penOn, :step, :gpu, store: _, picture: _, landOn: _) =
        await aCanvas(tester);
    step(at);
    await tester.pump();
    expect(gpu.written, 1, reason: '⛔premise: the step is in the picture');
    gpu.letTheWritesLand();
    await lendBothClocks(tester, rounds: 2);

    await penOn(high);
    await tester.pump();

    expect(
      drawnAsItStands(tester) || gpu.written > 1,
      isTrue,
      reason: 'the picture is drawn over or written into, not left as it is',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('⛔nor is one short of a step the row left took: it stays to go '
      'in', (tester) async {
    final (:penOn, :step, :gpu, store: _, picture: _, landOn: _) =
        await aCanvas(tester);

    // The step shown and no paint since: the picture has not asked for it.
    step(at);
    await penOn(high);
    await tester.pump();

    expect(
      drawnAsItStands(tester) || gpu.written > 0,
      isTrue,
      reason: 'the picture is drawn over or written into, not left as it is',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the same cel handed by another painter is told by what moved, '
      'as ever: what its tiles changed goes in', (tester) async {
    final (:penOn, step: _, :gpu, store: _, picture: _, landOn: _) =
        await aCanvas(tester);

    await penOn(low, more: {beside: stroke});
    await tester.pump();

    expect(gpu.written, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(theLevelsPause);
  });
}

/// A GPU that counts the writes asked of it, each of them landing as it is
/// let ([letTheWritesLand]) — into nothing: the image is what it was.
class _WritesHeld extends WritesNeverLand {
  final List<Completer<bool>> _waiting = [];

  /// How many writes were asked.
  int written = 0;

  void letTheWritesLand() {
    for (final write in _waiting) {
      write.complete(true);
    }
    _waiting.clear();
  }

  @override
  Object? hold(ui.Image image) => image.clone();

  @override
  ui.Image imageOf(Object held) => (held as ui.Image).clone();

  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) {
    written += 1;
    final landing = Completer<bool>();
    _waiting.add(landing);
    return landing.future;
  }
}
