import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show SelectionMaskOptions;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/piece_landing.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';
import '../../helpers/placement_reading.dart';

/// 🗣️brush-fidelity-Q9 (유저 2026-10-18): 「통일하면 좋음」 — the cut tool's
/// stamp ghost is what a click there lands, in every blend, normal too: the
/// click's own dab through the piece door, blended on the CPU and shown as
/// the overlay's result tiles. Q10: the shape tool's law — the last whole
/// ghost stays up until the next one is whole.
///
/// What a click lands is made of more than where the hand rests — the cel
/// under it, the marquee and its softness, the cel stood on and where its
/// rows stand — so each of them, changed under a resting pointer, lays the
/// ghost again.
///
/// The overlay is the host's here (the panel's merged mode), so what the
/// screen is given to draw can be read without capturing pixels. The oracle
/// is the click itself — the cel after a press where the pointer rests,
/// pictured by the door's own premultiply — never a blend spelled out again
/// here.
void main() {
  /// Where the pointer rests. At this harness's render 1.0 a point on the
  /// panel is the canvas point under it, and the piece centres on it.
  const aim = Offset(300, 300);

  /// Two tiles over from [aim]: a ghost there shares no tile with one at
  /// [aim].
  const elsewhere = Offset(556, 300);

  /// The held piece's side, and its top-left on both axes when it centres
  /// on [aim].
  const pieceSide = 32;
  const corner = 284;

  /// The paint under the piece — its channels add up to 290 …
  const paintArgb = 0xFF8C5A3C;
  const paintRgba = 0x8C5A3CFF;

  /// … under a light half the paint is darker than (630) and a dark half
  /// darker than the paint (180): darker colour keeps the paint under the
  /// one and takes the other, where normal and multiply change both.
  const light = [230, 220, 180];
  const dark = [30, 40, 110];

  /// A marquee whose right edge runs down the piece's dark half: at canvas
  /// x 310 where the piece's row 16 crosses it.
  CanvasSelectionRegion edgeInTheDarkHalf() => CanvasSelectionRegion.shape(
    CanvasSelectionShape.ellipse(left: 150, top: 150, right: 310, bottom: 450),
  );

  /// The held picture: [light] on its left half, [dark] on its right, and
  /// its top eight rows see-through, so the stamp's own alpha rides along
  /// with its opacity.
  CutPiece twoTonePiece() {
    final rgba = Uint8List(pieceSide * pieceSide * 4);
    for (var y = 0; y < pieceSide; y += 1) {
      for (var x = 0; x < pieceSide; x += 1) {
        final at = (y * pieceSide + x) * 4;
        rgba.setAll(at, x < pieceSide ~/ 2 ? light : dark);
        rgba[at + 3] = y < 8 ? 160 : 255;
      }
    }
    return CutPiece(
      image: BrushStampImage(
        id: 'two-tone',
        width: pieceSide,
        height: pieceSide,
        rgba: rgba,
      ),
      originLeft: 0,
      originTop: 0,
    );
  }

  /// The stamp tool in hand on the cel the panel stands on, the slot empty
  /// — the cut tool's harness (`cut_tool_drag_test`) in the merged mode the
  /// dragged shape is read in (`a_dragged_shape_shows_what_it_will_lay_test`).
  Future<_Stage> pumpPanel(
    WidgetTester tester, {
    BrushBlendMode blend = BrushBlendMode.color,
    double opacity = 1,
    SelectionMaskOptions softness = SelectionMaskOptions.none,
    bool paintUnder = false,
    PieceGround Function()? pieceGround,
  }) async {
    final keys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(frameKeys: keys);
    if (paintUnder) {
      // A square of paint the piece sits well inside.
      coordinator.commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: aim.dx, y: aim.dy),
            color: paintArgb,
            size: 128,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );
    }
    final history = HistoryManager();
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.cutStamp,
        cutStampBlendMode: blend,
        cutStampOpacity: opacity,
      ),
    );
    addTearDown(brush.dispose);
    // The selection's softness, as the tool settings would set it.
    final mask = ValueNotifier(softness);
    addTearDown(mask.dispose);
    final commands = CanvasSelectionCommands();
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    // ONE sink, held: a panel built again hears a cel change through the
    // sink it was built with (`brush_canvas_selection_test`).
    final sink = BrushEditCacheInvalidationSink();
    // ⚠️An EXPLICIT render 1.0: a point on the panel is the canvas point
    // under it, one for one.
    final atRenderOne = seedFromRender(tester, CanvasViewport());
    // The host's build. A cel stood on, or a row moved, reaches the panel
    // as the host building it again.
    Future<void> build() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: keys,
              cacheInvalidationSink: sink,
              historyManager: history,
              brushToolState: brush,
              selectionCommands: commands,
              selectionMaskOptions: mask,
              cutPieceSlot: slot,
              pieceGround: pieceGround,
              viewport: atRenderOne,
              activeStrokeOverlayModel: overlay,
              viewportUnderlayBuilder: (context, viewport, painter, floats) =>
                  painter == null
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: painter,
                      size: Size(
                        BrushCanvasFixture.canvasSize.width.toDouble(),
                        BrushCanvasFixture.canvasSize.height.toDouble(),
                      ),
                    ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await build();
    return (
      coordinator: coordinator,
      keys: keys,
      history: history,
      overlay: overlay,
      brush: brush,
      mask: mask,
      commands: commands,
      slot: slot,
      rebuild: build,
    );
  }

  Offset onPanel(WidgetTester tester, Offset at) =>
      tester.getTopLeft(find.byType(BrushCanvasPanel)) + at;

  /// A mouse come to rest at [at] — the aim, written by a hover as the
  /// hand writes it.
  Future<TestGesture> restAt(WidgetTester tester, Offset at) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: onPanel(tester, at));
    await tester.pump();
    await gesture.moveTo(onPanel(tester, at));
    return gesture;
  }

  /// A click by the resting mouse, where it rests: the stamp lands on the
  /// press, and the aim stays where it was.
  Future<void> clickAt(
    WidgetTester tester,
    TestGesture gesture,
    Offset at,
  ) async {
    await gesture.down(onPanel(tester, at));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var frame = 0; frame < 40 && !ready(); frame += 1) {
      await tester.pump();
    }
  }

  /// The aim the stamp's cursor layer publishes — null with nothing held.
  CutStampPreview? aimOf(WidgetTester tester) => tester
      .widget<CutStampPreviewPublisher>(find.byType(CutStampPreviewPublisher))
      .preview;

  /// Whether [overlay] shows exactly [pictures] — the same images on the
  /// same tiles, and nothing else.
  bool stillShows(
    ActiveStrokeOverlayModel overlay,
    Map<TileCoord, ui.Image> pictures,
  ) {
    final shown = overlay.tileImages;
    return shown.length == pictures.length &&
        pictures.entries.every(
          (entry) => identical(shown[entry.key], entry.value),
        );
  }

  /// Every picture the overlay shows — what the screen is given to draw —
  /// read back as the door made it, premultiplied.
  Future<Map<TileCoord, Uint8List>> shownBytes(
    WidgetTester tester,
    ActiveStrokeOverlayModel overlay,
  ) async {
    final pictures = Map.of(overlay.tileImages);
    final bytes = await tester.runAsync(() async {
      final read = <TileCoord, Uint8List>{};
      for (final MapEntry(key: coord, value: image) in pictures.entries) {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        read[coord] = data!.buffer.asUint8List();
      }
      return read;
    });
    return bytes!;
  }

  /// [tile] as the door pictures it — premultiplied as every upload rounds
  /// — or a clear tile where the cel holds none.
  Uint8List pictured(BitmapTile? tile, int tileSide) {
    if (tile == null) {
      return Uint8List(tileSide * tileSide * 4);
    }
    final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
    try {
      return Uint8List.fromList(upload.view);
    } finally {
      upload.free();
    }
  }

  /// Where two pictures of a tile part — the first pixel that does — or
  /// null where they are the same bytes.
  String? firstPixelApart(List<int> a, List<int> b, int tileSide) {
    if (a.length != b.length) {
      return '${a.length} bytes against ${b.length}';
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        final pixel = i ~/ 4;
        final at = pixel * 4;
        return '(${pixel % tileSide}, ${pixel ~/ tileSide}): '
            '${a.sublist(at, at + 4)} against ${b.sublist(at, at + 4)}';
      }
    }
    return null;
  }

  /// The tiles whose bytes [after] changed from [before].
  Set<TileCoord> tilesChanged(BitmapSurface before, BitmapSurface after) {
    final tileSide = before.tileSize;
    Uint8List straight(BitmapTile? tile) =>
        tile?.pixels ?? Uint8List(tileSide * tileSide * 4);
    final changed = <TileCoord>{};
    for (final coord in {...before.tiles.keys, ...after.tiles.keys}) {
      final was = straight(before.tileAt(coord));
      final now = straight(after.tileAt(coord));
      if (firstPixelApart(was, now, tileSide) != null) {
        changed.add(coord);
      }
    }
    return changed;
  }

  /// Whether any picture in [shown] is other than [cel]'s own tile there —
  /// a ghost that shows the cel as it was shows nothing at all.
  bool showsAChange(Map<TileCoord, Uint8List> shown, BitmapSurface cel) {
    final tileSide = cel.tileSize;
    for (final MapEntry(key: coord, value: picture) in shown.entries) {
      final own = pictured(cel.tileAt(coord), tileSide);
      if (firstPixelApart(picture, own, tileSide) != null) {
        return true;
      }
    }
    return false;
  }

  /// Whether two readings of the overlay part anywhere.
  bool partsFrom(
    Map<TileCoord, Uint8List> a,
    Map<TileCoord, Uint8List> b,
    int tileSide,
  ) {
    if (a.length != b.length) {
      return true;
    }
    for (final MapEntry(key: coord, value: picture) in a.entries) {
      final other = b[coord];
      if (other == null || firstPixelApart(picture, other, tileSide) != null) {
        return true;
      }
    }
    return false;
  }

  /// 🚨The pin itself: every tile [shown] showed is the picture of the tile
  /// the click landed there, byte for byte — and every tile the click
  /// changed is one it showed.
  void expectShownIsLanded(
    Map<TileCoord, Uint8List> shown,
    BitmapSurface before,
    BitmapSurface landed,
  ) {
    final tileSide = landed.tileSize;
    final changed = tilesChanged(before, landed);
    expect(changed, isNotEmpty, reason: '⛔premise: the click landed');
    expect(
      shown.keys,
      containsAll(changed),
      reason: 'every tile the click changed, the ghost showed',
    );
    for (final MapEntry(key: coord, value: picture) in shown.entries) {
      expect(
        firstPixelApart(
          picture,
          pictured(landed.tileAt(coord), tileSide),
          tileSide,
        ),
        isNull,
        reason: '$coord: the ghost showed what the click landed there',
      );
    }
  }

  // 🚨THE PIN OF Q9: a ghost per mode — darker colour among them, the one
  // the GPU has no blend for — at half strength, through a feathered and
  // anti-aliased selection, over paint the blends act on.
  for (final (blend, called) in [
    (BrushBlendMode.color, 'normal'),
    (BrushBlendMode.multiply, 'multiply'),
    (BrushBlendMode.darkerColor, 'darker colour'),
  ]) {
    testWidgets('🚨in $called, at half strength, through a feathered and '
        'anti-aliased selection, over paint: the ghost shows the very bytes '
        'a click there lands', (tester) async {
      final env = await pumpPanel(
        tester,
        blend: blend,
        opacity: 0.5,
        softness: const SelectionMaskOptions(featherPx: 4, antiAlias: true),
        paintUnder: true,
      );
      // Four pixels of feather inside its edge, nothing past it.
      env.commands.setRegion(edgeInTheDarkHalf());
      env.slot.hold(twoTonePiece());
      await tester.pump();
      final key = env.coordinator.activeFrameKey;
      final before = env.coordinator.currentSurfaceOf(key);
      expect(
        surfacePixelRgba(before, corner + 4, corner + 16),
        paintRgba,
        reason: '⛔premise: paint under the piece',
      );

      final gesture = await restAt(tester, aim);
      await pumpUntil(tester, () => env.overlay.hasStrokeContent);
      expect(env.overlay.hasStrokeContent, isTrue, reason: 'the ghost is up');
      // ⛔Premise: the aim is the piece centred on the pointer, at the
      // stamp's opacity and in its blend.
      final aimed = aimOf(tester)!;
      expect(aimed.canvasRect.left, closeTo(corner, 0.01));
      expect(aimed.canvasRect.top, closeTo(corner, 0.01));
      expect(aimed.opacity, 0.5);
      expect(aimed.blendMode, blend);
      final shown = await shownBytes(tester, env.overlay);
      expect(shown, isNotEmpty, reason: '⛔premise: tiles to compare');
      expect(
        showsAChange(shown, before),
        isTrue,
        reason: 'the ghost is not the cel as it was — an empty one would be',
      );
      expect(
        tilesChanged(before, env.coordinator.currentSurfaceOf(key)),
        isEmpty,
        reason: 'a ghost lands nothing',
      );
      expect(env.history.undoCount, 0);

      await clickAt(tester, gesture, aim);
      final landed = env.coordinator.currentSurfaceOf(key);
      expect(env.history.undoCount, 1, reason: 'the click lands, one step');

      // ⛔Premises — the scene tells the modes apart, and the selection's
      // softness is in it. The piece's row 16, by column:
      int? inRow(BitmapSurface cel, int column) =>
          surfacePixelRgba(cel, corner + column, corner + 16);
      expect(
        inRow(landed, 4) == inRow(before, 4),
        blend == BrushBlendMode.darkerColor,
        reason: 'the light half: darker colour keeps the darker paint, which '
            'normal and multiply change',
      );
      expect(
        inRow(landed, 18),
        isNot(inRow(before, 18)),
        reason: 'the dark half lands',
      );
      expect(
        inRow(landed, 24),
        allOf(isNot(inRow(before, 24)), isNot(inRow(landed, 18))),
        reason: 'in the feather it lands, in part',
      );
      expect(
        inRow(landed, 29),
        inRow(before, 29),
        reason: 'past the edge nothing lands',
      );

      expectShownIsLanded(shown, before, landed);
    });
  }

  testWidgets('a blend picked while the pointer rests lays the ghost again, '
      'in that blend — the bytes a click there lands now', (tester) async {
    final env = await pumpPanel(tester, opacity: 0.5, paintUnder: true);
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final key = env.coordinator.activeFrameKey;
    final before = env.coordinator.currentSurfaceOf(key);
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final inNormal = Map.of(env.overlay.tileImages);
    expect(inNormal, isNotEmpty, reason: '⛔premise: the ghost, in normal');
    final normalBytes = await shownBytes(tester, env.overlay);
    final rested = aimOf(tester)!;

    env.brush.value = env.brush.value.copyWith(
      cutStampBlendMode: BrushBlendMode.multiply,
    );
    await pumpUntil(tester, () => !stillShows(env.overlay, inNormal));
    expect(
      stillShows(env.overlay, inNormal),
      isFalse,
      reason: 'the ghost is laid again',
    );
    expect(env.overlay.hasStrokeContent, isTrue, reason: 'never nothing');
    // ⛔Premise: the hand did not move — only the blend did, and the aim's
    // blend is what told the ghost.
    final repicked = aimOf(tester)!;
    expect(repicked.canvasRect, rested.canvasRect);
    expect(repicked.blendMode, BrushBlendMode.multiply);
    final multiplyBytes = await shownBytes(tester, env.overlay);
    expect(
      partsFrom(multiplyBytes, normalBytes, before.tileSize),
      isTrue,
      reason: 'it shows the new blend, not the old one',
    );

    await clickAt(tester, gesture, aim);
    expectShownIsLanded(
      multiplyBytes,
      before,
      env.coordinator.currentSurfaceOf(key),
    );
  });

  testWidgets('the ghost on screen stays up until the next one is whole: '
      'laid a piece a frame, the ghost the pointer left is what shows until '
      'the new one is done', (tester) async {
    final share = shapeShowFrameShare;
    addTearDown(() => shapeShowFrameShare = share);
    shapeShowFrameShare = Duration.zero;
    final env = await pumpPanel(tester);
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final first = Map.of(env.overlay.tileImages);
    expect(
      first.keys.toSet(),
      {TileCoord(x: 2, y: 2)},
      reason: '⛔premise: the first ghost, on one tile',
    );

    await gesture.moveTo(onPanel(tester, elsewhere));
    await tester.pump();
    expect(
      stillShows(env.overlay, first),
      isTrue,
      reason: 'a frame after the move the old ghost is up — never nothing',
    );
    var framesItStood = 1;
    for (var frame = 0; frame < 40; frame += 1) {
      await tester.pump();
      if (!stillShows(env.overlay, first)) {
        break;
      }
      framesItStood += 1;
    }
    expect(
      framesItStood,
      greaterThan(1),
      reason: '⛔premise: a frame laid the new ghost while the old one stood',
    );
    expect(
      env.overlay.tileImages.keys.toSet(),
      {TileCoord(x: 4, y: 2)},
      reason: 'then the new one, whole, in the old one\'s place',
    );
  });

  testWidgets('a piece put in the empty hand under a resting pointer comes '
      'up as its ghost there, the pointer never moving', (tester) async {
    final env = await pumpPanel(tester);
    final gesture = await restAt(tester, aim);
    await tester.pump();
    expect(aimOf(tester), isNull, reason: '⛔premise: nothing held yet');
    expect(env.overlay.hasStrokeContent, isFalse, reason: '⛔premise');

    // A held piece swaps the cursor layer's branch: the publisher coming in
    // runs its initState before the one going out is disposed — and that
    // one published nothing, so it has nothing to take back.
    env.slot.hold(twoTonePiece());
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    expect(
      env.overlay.hasStrokeContent,
      isTrue,
      reason: 'the ghost comes up — the publisher that went took nothing',
    );
    expect(
      env.overlay.tileImages.keys.toSet(),
      {TileCoord(x: 2, y: 2)},
      reason: 'where the pointer rests',
    );
    final up = Map.of(env.overlay.tileImages);
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump();
    }
    expect(stillShows(env.overlay, up), isTrue, reason: 'and it stays up');

    final key = env.coordinator.activeFrameKey;
    final before = env.coordinator.currentSurfaceOf(key);
    final shown = await shownBytes(tester, env.overlay);
    await clickAt(tester, gesture, aim);
    expectShownIsLanded(shown, before, env.coordinator.currentSurfaceOf(key));
  });

  testWidgets('a landing, then an undo, under a resting pointer: each lays '
      'the ghost again over the cel it leaves — the bytes a click there '
      'lands now', (tester) async {
    final env = await pumpPanel(tester, opacity: 0.5, paintUnder: true);
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final key = env.coordinator.activeFrameKey;
    final before = env.coordinator.currentSurfaceOf(key);
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final overThePaint = Map.of(env.overlay.tileImages);
    expect(overThePaint, isNotEmpty, reason: '⛔premise: the ghost is up');

    await clickAt(tester, gesture, aim);
    expect(env.history.undoCount, 1, reason: '⛔premise: the click landed');
    await pumpUntil(tester, () => !stillShows(env.overlay, overThePaint));
    expect(
      stillShows(env.overlay, overThePaint),
      isFalse,
      reason: 'the cel under it changed, so the ghost is laid again',
    );
    final overTheStamp = Map.of(env.overlay.tileImages);
    final overTheStampBytes = await shownBytes(tester, env.overlay);

    env.history.undo();
    await tester.pump();
    expect(
      tilesChanged(before, env.coordinator.currentSurfaceOf(key)),
      isEmpty,
      reason: '⛔premise: the undo took the stamp back',
    );
    await pumpUntil(tester, () => !stillShows(env.overlay, overTheStamp));
    expect(
      stillShows(env.overlay, overTheStamp),
      isFalse,
      reason: 'the pointer never moved: the undo laid the ghost again',
    );
    final shown = await shownBytes(tester, env.overlay);
    expect(
      partsFrom(shown, overTheStampBytes, before.tileSize),
      isTrue,
      reason: 'over the cel the undo left, not the stamp it took back',
    );

    await clickAt(tester, gesture, aim);
    expectShownIsLanded(
      shown,
      before,
      env.coordinator.currentSurfaceOf(key),
    );
  });

  testWidgets('a softness picked for the marquee under a resting pointer '
      'lays the ghost again at it — the bytes a click there lands '
      'now', (tester) async {
    final env = await pumpPanel(
      tester,
      softness: const SelectionMaskOptions(featherPx: 4, antiAlias: true),
      paintUnder: true,
    );
    env.commands.setRegion(edgeInTheDarkHalf());
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final key = env.coordinator.activeFrameKey;
    final before = env.coordinator.currentSurfaceOf(key);
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final atFour = Map.of(env.overlay.tileImages);
    expect(atFour, isNotEmpty, reason: '⛔premise: the ghost, feathered 4');
    final atFourBytes = await shownBytes(tester, env.overlay);

    // The same marquee, softer — set where the tool settings set it, which
    // rebuilds nothing.
    env.mask.value = const SelectionMaskOptions(
      featherPx: 12,
      antiAlias: true,
    );
    await pumpUntil(tester, () => !stillShows(env.overlay, atFour));
    expect(
      stillShows(env.overlay, atFour),
      isFalse,
      reason: 'the ghost is laid again, the pointer and the marquee still',
    );
    final shown = await shownBytes(tester, env.overlay);
    expect(
      partsFrom(shown, atFourBytes, before.tileSize),
      isTrue,
      reason: 'at the new feather, not the old one',
    );

    await clickAt(tester, gesture, aim);
    expectShownIsLanded(
      shown,
      before,
      env.coordinator.currentSurfaceOf(key),
    );
  });

  testWidgets('a marquee drawn under a resting pointer lays the ghost again '
      'through it — the bytes a click there lands now', (tester) async {
    final env = await pumpPanel(tester, paintUnder: true);
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final key = env.coordinator.activeFrameKey;
    final before = env.coordinator.currentSurfaceOf(key);
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final whole = Map.of(env.overlay.tileImages);
    expect(whole, isNotEmpty, reason: '⛔premise: the ghost, uncut');
    final wholeBytes = await shownBytes(tester, env.overlay);

    // Drawn by a command — select all, invert — while the stamp is in hand.
    env.commands.setRegion(edgeInTheDarkHalf());
    await pumpUntil(tester, () => !stillShows(env.overlay, whole));
    expect(
      stillShows(env.overlay, whole),
      isFalse,
      reason: 'the ghost is laid again, the pointer still',
    );
    final shown = await shownBytes(tester, env.overlay);
    expect(
      partsFrom(shown, wholeBytes, before.tileSize),
      isTrue,
      reason: 'cut by the marquee, as it was not before',
    );

    await clickAt(tester, gesture, aim);
    expectShownIsLanded(
      shown,
      before,
      env.coordinator.currentSurfaceOf(key),
    );
  });

  testWidgets('a rebuild that moves nothing the ghost is made of lays '
      'nothing: the pictures on screen stay the very '
      'same', (tester) async {
    final env = await pumpPanel(
      tester,
      softness: const SelectionMaskOptions(featherPx: 4, antiAlias: true),
      paintUnder: true,
    );
    env.commands.setRegion(edgeInTheDarkHalf());
    env.slot.hold(twoTonePiece());
    await tester.pump();
    await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final up = Map.of(env.overlay.tileImages);
    expect(up, isNotEmpty, reason: '⛔premise: the ghost is up');

    // The host builds the panel again, for a reason of its own.
    await env.rebuild();
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump();
    }
    expect(
      stillShows(env.overlay, up),
      isTrue,
      reason: 'asked again, the same ghost asks for nothing — what it is '
          'made of compares by value',
    );
  });

  testWidgets('a row moved under a resting pointer lays the ghost again '
      'where the row shows the press now — the bytes a click there '
      'lands', (tester) async {
    final standing = BrushCanvasFixture.createFrameKeys().first;
    // The row stands a hundred to the right of the canvas's own place.
    var rowAt = 100.0;
    final env = await pumpPanel(
      tester,
      pieceGround: () => PieceGround(
        cels: [standing],
        placementOf: (_) => placementOfSample(
          (
            pose: TransformPose(center: CanvasPoint(x: rowAt, y: 0)),
            anchorPoint: CanvasPoint(x: 0, y: 0),
          ),
          BrushCanvasFixture.canvasSize,
        ),
      ),
    );
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final before = env.coordinator.currentSurfaceOf(standing);
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final first = Map.of(env.overlay.tileImages);
    expect(
      first.keys.toSet(),
      {TileCoord(x: 1, y: 2)},
      reason: '⛔premise: the press, a hundred to the left on the row',
    );

    // The host puts the row back, and builds the panel again.
    rowAt = 0;
    await env.rebuild();
    await pumpUntil(tester, () => !stillShows(env.overlay, first));
    expect(
      env.overlay.tileImages.keys.toSet(),
      {TileCoord(x: 2, y: 2)},
      reason: 'the ghost goes where the row shows the press now',
    );
    final shown = await shownBytes(tester, env.overlay);

    await clickAt(tester, gesture, aim);
    expectShownIsLanded(
      shown,
      before,
      env.coordinator.currentSurfaceOf(standing),
    );
  });

  testWidgets('the panel stood on another cel under a resting pointer brings '
      'the ghost up there — the bytes a click lands on that '
      'cel', (tester) async {
    final env = await pumpPanel(tester, opacity: 0.5, paintUnder: true);
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final overThePaint = await shownBytes(tester, env.overlay);
    expect(overThePaint, isNotEmpty, reason: '⛔premise: the ghost is up');

    // The next cel holds nothing; the host stands the panel on it.
    final next = env.keys[1];
    env.coordinator.selectFrame(next);
    await env.rebuild();
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    expect(
      env.overlay.hasStrokeContent,
      isTrue,
      reason: 'the ghost comes up on the new cel, the pointer never moving',
    );
    final before = env.coordinator.currentSurfaceOf(next);
    final shown = await shownBytes(tester, env.overlay);
    expect(
      partsFrom(shown, overThePaint, before.tileSize),
      isTrue,
      reason: 'over the cel stood on now, not the painted one it left',
    );

    await clickAt(tester, gesture, aim);
    expect(env.coordinator.activeFrameKey, next, reason: '⛔premise');
    expectShownIsLanded(
      shown,
      before,
      env.coordinator.currentSurfaceOf(next),
    );
  });

  testWidgets('🚨on a row that is a window onto the cel stood on, named first '
      'and standing elsewhere, the ghost is where the click lands: the '
      'door\'s answer for the cel', (tester) async {
    final standing = BrushCanvasFixture.createFrameKeys().first;
    final window = BrushFrameKey(
      projectId: standing.projectId,
      trackId: standing.trackId,
      cutId: standing.cutId,
      layerId: const LayerId('a-window-onto-the-standing-row'),
      frameId: standing.frameId,
    );
    final env = await pumpPanel(
      tester,
      // Named first, the window answers for the cel, and it stands a
      // hundred to the right: the one press means another place of the cel
      // through it (`cut_tool_drag_test`'s stack-order pin).
      pieceGround: () => PieceGround(
        cels: [window, standing],
        placementOf: (key) => placementOfSample(
          key == window
              ? (
                  pose: TransformPose(center: CanvasPoint(x: 100, y: 0)),
                  anchorPoint: CanvasPoint(x: 0, y: 0),
                )
              : null,
          BrushCanvasFixture.canvasSize,
        ),
      ),
    );
    env.coordinator.frameStore.setLinkResolver(
      (key) => key == window ? standing : key,
    );
    env.slot.hold(twoTonePiece());
    await tester.pump();
    final before = env.coordinator.currentSurfaceOf(standing);
    final gesture = await restAt(tester, aim);
    await pumpUntil(tester, () => env.overlay.hasStrokeContent);
    final shown = await shownBytes(tester, env.overlay);

    await clickAt(tester, gesture, aim);
    final landed = env.coordinator.currentSurfaceOf(standing);
    expect(
      tilesChanged(before, landed),
      {TileCoord(x: 1, y: 2)},
      reason: '⛔premise: the window answered — a hundred to the left of the '
          'press, not under it',
    );
    expectShownIsLanded(shown, before, landed);
  });
}

/// The panel under test, and what a test drives it by.
typedef _Stage = ({
  BrushFrameEditingCoordinator coordinator,
  List<BrushFrameKey> keys,
  HistoryManager history,
  ActiveStrokeOverlayModel overlay,
  ValueNotifier<BrushToolState> brush,
  ValueNotifier<SelectionMaskOptions> mask,
  CanvasSelectionCommands commands,
  CutPieceSlot slot,
  Future<void> Function() rebuild,
});
