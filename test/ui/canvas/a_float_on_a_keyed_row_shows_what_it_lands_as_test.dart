import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/transform_values.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_float.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cel_text_tool_harness.dart';
import '../../helpers/key_chords.dart';
import '../../helpers/panel_finders.dart';
import '../../helpers/placement_reading.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/wait_window.dart' show windowBehind;

/// Who the box carries: the row the canvas edits, alone; that row and
/// another across a frame range (F-329), the other floating in a slot of
/// its own; or a folder's two rows (I-37), each in a slot of its own.
enum _Rows { live, range, folder }

/// transform-float-skips-colour-key — WHAT THE TRANSFORM BOX CARRIES SHOWS
/// WHAT IT LANDS AS ON A ROW THAT KEYS A COLOUR AWAY, IN EVERY ROW IT
/// FLOATS IN.
///
/// F-240 (유저 2026-09-29: 「변형중에도 필터 통일적용하도록」) is the law: what
/// floats is what lands. A scanned sheet whose ground its row keys away is
/// the everyday case — that ground is not on the canvas, so it must not be
/// there while the sheet is carried either (measured before this: 3,712
/// pixels of it). The composite the canvas draws is read with the box
/// still open and again once its confirm has landed it, over the same
/// window, and the two must be the same bytes — for each kind of row a
/// float shows in, dragged and warped, by each of the three ways a float
/// is shown (`SelectionFloatPaint.shownOn`), at 1:1 and zoomed out.
void main() {
  // The engine and what a frame is laid with, open before the first test:
  // a frame is on its screen from the frame it is stood in.
  //
  // ↩️They opened of themselves, in the first test, in whatever real time
  // its waits lent, until 2026-11-11 (card
  // float-landing-test-red-once-under-load). 🔬The shot that test takes
  // before its box opens was of a screen with nothing on it in every run
  // — 11,532,672 pixels, all clear: its control compared a landing with
  // nothing — and on a loaded machine the shot with the box open was too:
  // 「what floats is what lands」 read 3,870,360 pixels apart, the whole
  // frame, once in a run of 118 files. The 33 tests after it met an engine
  // already open. ⇒ [composite] refuses a screen with nothing on it.
  opensTheEnginesScreens();
  const ground = 0xFF40C060;
  const rowB = LayerId('keyed-row-b');
  const celB = FrameId('keyed-row-b-cel');
  const folder = LayerId('keyed-folder');
  final keyB = BrushFrameKey(
    projectId: textToolKey.projectId,
    trackId: textToolKey.trackId,
    cutId: textToolKey.cutId,
    layerId: rowB,
    frameId: celB,
  );

  /// [ground] taken away.
  LayerEffect groundKey() => LayerEffect(
    id: const EffectId('sheet-ground-key'),
    kind: EffectKind.colorKey,
    colors: {
      'keyColor': PropertyTrack<int>.empty().withKey(0, ground),
    },
    parameters: {
      'tolerance': EffectParameter(value: 10),
      'amount': EffectParameter(value: 100),
    },
  );

  /// The text tool's project — its row A — and for [rows] a row B beside
  /// it, both in a folder for [_Rows.folder]; every row wearing [ground]'s
  /// key when [keyed] and the stand-in plugin when [plugin], and A posed
  /// by [pose].
  Project projectOf(
    _Rows rows, {
    required bool keyed,
    bool plugin = false,
    TransformPose? pose,
  }) {
    final base = textToolProject(
      effects: [
        if (keyed) groundKey(),
        if (plugin) shiftingFxPluginLayerEffect(),
      ],
    );
    final track = base.tracks.single;
    final cut = track.cuts.single;
    final a = cut.layers.single;
    final inFolder = rows == _Rows.folder;
    Layer member(Layer row) => inFolder ? row.copyWith(folderId: folder) : row;
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                member(
                  pose == null
                      ? a
                      : a.copyWith(
                          transformTrack: TransformTrack(keyframes: {0: pose}),
                        ),
                ),
                if (rows != _Rows.live)
                  member(
                    a.copyWith(
                      id: rowB,
                      name: 'B',
                      frames: [
                        Frame(
                          id: celB,
                          name: 'B',
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: const {
                        0: TimelineExposure.drawing(celB, length: 1),
                      },
                    ),
                  ),
                if (inFolder) createFolderLayer(id: folder, name: 'F'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// An opaque sheet of [ground] over [area], black squares on it.
  List<int>? sheet(Rect area, int x, int y) {
    if (!area.contains(Offset(x + 0.5, y + 0.5))) {
      return null;
    }
    final ink = (x - area.left) % 24 < 8 && (y - area.top) % 24 < 8;
    return ink
        ? const [0, 0, 0, 255]
        : [ground >> 16 & 0xFF, ground >> 8 & 0xFF, ground & 0xFF, 255];
  }

  /// Line art over [area]: clear, with lines of [ground] and of red, and a
  /// partly clear edge beside each.
  List<int>? lineArt(Rect area, int x, int y) {
    if (!area.contains(Offset(x + 0.5, y + 0.5))) {
      return null;
    }
    final across = (x - area.left.toInt()) % 16;
    if (across > 2) {
      return null;
    }
    final red = (x - area.left.toInt()) ~/ 16 % 2 == 1;
    final colour = red
        ? const [220, 30, 30]
        : [ground >> 16 & 0xFF, ground >> 8 & 0xFF, ground & 0xFF];
    return [...colour, if (across == 2) 128 else 255];
  }

  /// [key]'s cel laid with [paint]'s pixels over [area] — clear where it
  /// gives none — its texts kept.
  Future<void> lay(
    WidgetTester tester,
    BrushFrameKey key,
    Rect area,
    List<int>? Function(int x, int y) paint,
  ) async {
    final cel = celOf(tester, key);
    final size = cel.tileSize;
    final tiles = <TileCoord, BitmapTile>{};
    for (var ty = area.top ~/ size; ty * size < area.bottom; ty += 1) {
      for (var tx = area.left ~/ size; tx * size < area.right; tx += 1) {
        final px = Uint8List(size * size * 4);
        for (var y = 0; y < size; y += 1) {
          for (var x = 0; x < size; x += 1) {
            final rgba = paint(tx * size + x, ty * size + y);
            if (rgba != null) {
              px.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, rgba);
            }
          }
        }
        tiles[TileCoord(x: tx, y: ty)] = BitmapTile(size: size, pixels: px);
      }
    }
    coordinatorOf(tester).restoreSurfaceSnapshot(
      key,
      BitmapSurface(
        canvasSize: cel.canvasSize,
        tileSize: size,
        tiles: tiles,
        texts: cel.texts,
      ),
    );
  }

  FramePictureView canvasOf(WidgetTester tester) =>
      tester.widget<FramePictureView>(
        theFramesPicture(within: mainCanvasPanel()),
      );

  /// Device pixels a canvas pixel of the view lands on.
  double scaleOf(WidgetTester tester) => displayScaleOf(
    canvasOf(tester).viewport.zoom,
    tester.view.devicePixelRatio,
  );

  /// What the drawing canvas's stack draws — every row, each float in the
  /// slot of the row it lands on — as raw RGBA. Its own painter, so the
  /// box's ants and handles over it are not in it.
  ///
  /// 🚨AT DEVICE RESOLUTION — the view's ratio as the root scale, the way
  /// the compositor rasters it. ↩️It was rastered at logical size, a third
  /// of the device's pixels at the runner's ratio of 3 — a raster no screen
  /// makes: a stroke's patch is drawn straight onto the screen at a whole
  /// display scale (`_pictureDrawsTheSame`), and its tile edges, whole
  /// device pixels, fell on thirds of the raster's. 🔬Under Impeller
  /// (Vulkan, 10-24) the multisampled raster blended them — at 1:1 a
  /// landing read grey 64 on nine pixels the box had carried black.
  ///
  /// ⛔Of a frame that is on its screen: one the engine has not come to yet
  /// paints nothing at all, its paper neither, and two shots of nothing
  /// are the same bytes.
  ///
  /// 🗣️I-132-Q34 a: a frame whose chain runs a plugin shows the picture
  /// last made of it until the next is there — waited for, until nothing
  /// more of it is on its way (`FramePictureView.nothingOnItsWay`).
  Future<Uint8List> composite(WidgetTester tester) async {
    bool caughtUp() =>
        (tester.state(theFramesPicture(within: mainCanvasPanel())) as dynamic)
                .nothingOnItsWay
            as bool;
    expect(
      await settleAsync(tester, caughtUp),
      isTrue,
      reason: 'LIVENESS: what the frame waits for comes',
    );
    await pumpFrames(tester, 2);
    final shot = await shotOfBox(
      tester,
      tester.renderObject<RenderBox>(
        theFrameScreenIn(theFramesPicture(within: mainCanvasPanel())),
      ),
    );
    expect(
      shot.rgba.any((channel) => channel != 0),
      isTrue,
      reason: '⛔fixture: the frame is on its screen',
    );
    return shot.rgba;
  }

  /// Lets a step land: its frames, and the resample an open warp shows
  /// once a frame has ended, waited for until it is the one the box's
  /// values ask for now ([CanvasSelectionCommands.debugFloatsCaughtUp]).
  /// ↩️That resample was decoded by the engine on a real thread, until the
  /// canvas laid its tiles (a-float-premultiplies-in-the-c-each-step).
  ///
  /// ↩️It lent both clocks twelve rounds of 16 ms until 2026-10-25. 🔬On
  /// two pumped frames and no real time 17 of the 22 tests passed, their
  /// controls too; the five that failed were the warps, showing the float's
  /// surface where its resample was still decoding — and one let-go,
  /// waited for where it is checked.
  Future<void> settle(WidgetTester tester) async {
    await pumpFrames(tester, 2);
    // No selection layer up — before the Move tool is — floats nothing.
    bool caughtUp() => tester
        .widgetList<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer))
        .every(
          (layer) => layer.selectionCommands?.debugFloatsCaughtUp ?? true,
        );
    expect(
      await settleAsync(
        tester,
        caughtUp,
        step: const Duration(milliseconds: 16),
      ),
      isTrue,
      reason: 'the warp shows the resample its values ask for',
    );
    await pumpFrames(tester, 2);
  }

  /// The app on [project], stood on row A — at the 1:1 it opens at, or
  /// [zoomedOut] by the bar's own steps past a halving, where the screen
  /// samples the frame's picture from its chain (F-240) — with the text
  /// tool in hand, and the canvas pixel in the middle of what can be seen
  /// of it. ↩️Past a halving the rows were drawn as level tiles, until
  /// one-picture-per-frame ②-5b-2. [fxPlugins]: the device's installed
  /// plugins.
  Future<Offset> open(
    WidgetTester tester,
    Project project, {
    bool zoomedOut = false,
    InstalledFxPlugins? fxPlugins,
  }) async {
    await pumpTextToolApp(tester, project: project, fxPlugins: fxPlugins);
    sessionOf(tester).selectLayer(textToolLayerId);
    await settle(tester);
    final view = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .canvasViewCommands!;
    for (
      var step = 0;
      zoomedOut && scaleOf(tester) > 0.5 && step < 8;
      step++
    ) {
      view.zoomStep(zoomIn: false);
      await settle(tester);
    }
    expect(
      scaleOf(tester),
      zoomedOut ? lessThanOrEqualTo(0.5) : greaterThan(0.5),
      reason: '⛔fixture: 1:1, or a zoom past a halving',
    );
    await takeTextTool(tester);
    return canvasPixelInView(tester);
  }

  /// Where a hand takes hold of the box [region] frames, on the screen: a
  /// quarter of the way from its middle to its lower right corner — clear
  /// of the cross at its middle and of the handles round its edge, each of
  /// which takes a press of its own (`boxPressAt`).
  Offset holdIn(WidgetTester tester, Rect region) => onScreen(
    tester,
    region.center.dx + region.width / 4,
    region.center.dy + region.height / 4,
  );

  /// How far a hand goes on the screen to carry by ([dx], [dy]) pixels of
  /// the canvas.
  Offset handFor(WidgetTester tester, double dx, double dy) =>
      onScreen(tester, dx, dy) - onScreen(tester, 0, 0);

  /// The Move tool up, stood as [rows] says, [region] selected — and its
  /// commands, the box they open cancelled when a failed check leaves it
  /// open (the next test would otherwise confirm it).
  Future<CanvasSelectionCommands> select(
    WidgetTester tester,
    _Rows rows,
    Rect region,
  ) async {
    final session = sessionOf(tester);
    final brush = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
    brush.value = brush.value.copyWith(tool: CanvasTool.move);
    switch (rows) {
      case _Rows.live:
        break;
      case _Rows.range:
        session.frameRangeSelection.value = const TimelineFrameRangeSelection(
          layerId: textToolLayerId,
          layerIds: [textToolLayerId, rowB],
          startIndex: 0,
          endIndexExclusive: 1,
        );
      case _Rows.folder:
        session.selectLayer(folder);
    }
    await settle(tester);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    addTearDown(() {
      if (commands.transformActive) {
        commands.cancelTransform();
      }
    });
    commands.applyRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: region.left,
          top: region.top,
          right: region.right,
          bottom: region.bottom,
        ),
      ),
    );
    await settle(tester);
    return commands;
  }

  /// A box on [region], stood as [rows] says, carrying what it lifts: by a
  /// hand that takes hold inside it ([holdIn]) and drags it by (40, 30) —
  /// [twice], by as much again — which floats the lifted pixels
  /// themselves; or by [warps]' numbers in Ctrl+T's box, one after
  /// another, which floats the picture each resamples them to. The
  /// composite while it is carried — once [whileOpen] has done what it
  /// does with the box open — and once its confirm has landed it.
  ///
  /// The hand takes hold while no box is open, so its press opens one as
  /// the move; its second hold is in the box that opened — the box's own
  /// drag, a road of its own (`_handlePointerMove`), which floats the
  /// lifted pixels as the first does (a-drag-in-an-open-box-resamples-a-
  /// move). ↩️That road resampled a translation: the float became a
  /// picture of its own, and on a keyed row a landing made again at every
  /// move.
  ///
  /// Asked with the text tool in hand: its stage says where a canvas pixel
  /// is on the screen — where the row's own pixel of that number is, so on
  /// a row its pose turns the hand is told where to take hold ([holdAt],
  /// [sheetOnATurnedRow]).
  Future<({Uint8List carried, Uint8List landed})> carry(
    WidgetTester tester,
    _Rows rows, {
    required Rect region,
    Offset? holdAt,
    List<TransformValues Function(TransformValues now)> warps = const [],
    bool twice = false,
    Future<void> Function()? whileOpen,
  }) async {
    final hold = holdAt ?? holdIn(tester, region);
    final step = handFor(tester, 40, 30);
    final drop = hold + step;
    final commands = await select(tester, rows, region);
    // Each cel the box holds, as it stands before the confirm.
    List<BitmapSurface> cels() => [
      celOf(tester),
      if (rows != _Rows.live) celOf(tester, keyB),
    ];
    final before = cels();
    if (warps.isNotEmpty) {
      await pressCtrl(tester, LogicalKeyboardKey.keyT);
      commands.beginTransform();
      for (final warp in warps) {
        await settle(tester);
        commands.editTransformValues(warp);
      }
    } else {
      // [from] to [to] by one hand, the way a mouse drags.
      Future<void> drag(Offset from, Offset to) async {
        final hand = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await hand.moveTo(Offset.lerp(from, to, 0.5)!);
        await tester.pump();
        await hand.moveTo(to);
        await tester.pump();
        await hand.up();
      }

      await drag(hold, drop);
      if (twice) {
        await settle(tester);
        expect(commands.transformActive, isTrue, reason: '⛔fixture: a box');
        await drag(drop, drop + step);
      }
    }
    await settle(tester);
    expect(commands.transformActive, isTrue, reason: '⛔fixture: a box');
    expect(
      canvasOf(tester).live!.liftedRows.keys.toSet(),
      switch (rows) {
        _Rows.live => isEmpty,
        _Rows.range => {keyB},
        _Rows.folder => {textToolKey, keyB},
      },
      reason: '⛔fixture: the rows floating in slots of their own',
    );
    final stack = canvasOf(tester);
    final floats = [
      if (rows != _Rows.folder) stack.live!.floatOverlay?.value,
      for (final lifted in stack.live!.liftedRows.values) lifted.float?.value,
    ];
    expect(
      [
        for (final float in floats)
          switch (float) {
            null => 'nothing',
            _ when float.isEmpty => 'nothing',
            _ when float.resampled != null => 'its resample',
            _ => 'its surface',
          },
      ],
      [
        for (final _ in before)
          if (warps.isNotEmpty) 'its resample' else 'its surface',
      ],
      reason: 'every row floats — a warp as what it resamples to, a '
          'drag as its own surface, in a box it opened or one already open',
    );
    expect(
      [for (final (i, cel) in cels().indexed) identical(cel, before[i])],
      everyElement(isTrue),
      reason: 'a box writes nothing until it is confirmed (F-116)',
    );
    if (whileOpen != null) {
      await whileOpen();
      await settle(tester);
    }
    final carried = await composite(tester);
    await windowBehind(tester, () async => commands.applyTransform());
    await settle(tester);
    expect(
      [for (final (i, cel) in cels().indexed) identical(cel, before[i])],
      everyElement(isFalse),
      reason: '⛔CONTROL: the confirm landed what it carried on every cel',
    );
    return (carried: carried, landed: await composite(tester));
  }

  /// A's sheet left of [c] — and for two rows B's right of it — so a carry
  /// by (40, 30) lands each on nothing. The region a box carries them in:
  /// round them with room to spare, so that zoomed out too its box is
  /// large enough on the screen to take hold of ([holdIn]).
  Future<Rect> sheets(WidgetTester tester, Offset c, _Rows rows) async {
    var held = Rect.fromLTWH(c.dx - 160, c.dy - 64, 120, 120);
    final a = held;
    await lay(tester, textToolKey, a, (x, y) => sheet(a, x, y));
    if (rows != _Rows.live) {
      final b = Rect.fromLTWH(c.dx + 40, c.dy - 64, 120, 120);
      await lay(tester, keyB, b, (x, y) => sheet(b, x, y));
      held = held.expandToInclude(b);
    }
    await settle(tester);
    return held.inflate(60);
  }

  /// Line art above a sheet and clear of it, the pair round [c]: carried
  /// by (40, 30), the art's lower part — its partly clear edges too —
  /// lands on the sheet's upper left. The region a box carries the art in:
  /// the art, with room above it and left of it and none of the sheet.
  Future<Rect> artOverSheet(WidgetTester tester, Offset c) async {
    final art = Rect.fromLTWH(c.dx - 140, c.dy - 110, 96, 50);
    final under = Rect.fromLTWH(c.dx - 80, c.dy - 50, 160, 120);
    await lay(
      tester,
      textToolKey,
      under.expandToInclude(art),
      (x, y) => lineArt(art, x, y) ?? sheet(under, x, y),
    );
    await settle(tester);
    return Rect.fromPoints(
      art.topLeft - const Offset(160, 160),
      art.bottomRight,
    );
  }

  void expectLandsAsCarried(
    ({Uint8List carried, Uint8List landed}) seen,
    Uint8List drawn,
  ) {
    expect(
      _apart(drawn, seen.landed),
      greaterThan(0),
      reason: '⛔CONTROL: the landing moved what the canvas shows',
    );
    expect(
      _apart(seen.carried, seen.landed),
      0,
      reason: 'what floats is what lands (F-240)',
    );
  }

  TransformValues movedAndScaled(TransformValues now) =>
      now.copyWith(tx: 40, ty: 30, sx: 1.25, sy: 1.25);

  // ── Every kind of row, dragged and warped. ──

  for (final rows in _Rows.values) {
    for (final warped in [false, true]) {
      final how = warped ? 'warped' : 'dragged';
      testWidgets('${rows.name}: a keyed sheet $how by the box shows what it '
          'lands as', (tester) async {
        final c = await open(tester, projectOf(rows, keyed: true));
        final region = await sheets(tester, c, rows);
        final drawn = await composite(tester);

        expectLandsAsCarried(
          await carry(
            tester,
            rows,
            region: region,
            warps: [if (warped) movedAndScaled],
          ),
          drawn,
        );
      });
    }
  }

  // ── Dragged twice: the second time in the box the first one opened. ──

  for (final rows in _Rows.values) {
    testWidgets('${rows.name}: a keyed sheet dragged again in its open box '
        'floats its own pixels still', (tester) async {
      final c = await open(tester, projectOf(rows, keyed: true));
      final region = await sheets(tester, c, rows);
      final drawn = await composite(tester);

      expectLandsAsCarried(
        await carry(tester, rows, region: region, twice: true),
        drawn,
      );
    });
  }

  // ── The three ways a float is shown, at both kinds of zoom. ──

  for (final zoomedOut in [false, true]) {
    final zoom = zoomedOut ? 'zoomed out' : 'at 1:1';

    testWidgets('a keyed sheet lands on nothing $zoom — shown as its own '
        'pixels through the keys', (tester) async {
      final c = await open(
        tester,
        projectOf(_Rows.live, keyed: true),
        zoomedOut: zoomedOut,
      );
      final region = await sheets(tester, c, _Rows.live);
      final drawn = await composite(tester);

      expectLandsAsCarried(
        await carry(tester, _Rows.live, region: region),
        drawn,
      );
    });

    testWidgets('keyed line art with partly clear edges lands over the '
        'sheet beside it $zoom — shown as the landing itself', (tester) async {
      final c = await open(
        tester,
        projectOf(_Rows.live, keyed: true),
        zoomedOut: zoomedOut,
      );
      final region = await artOverSheet(tester, c);
      final drawn = await composite(tester);

      expectLandsAsCarried(
        await carry(tester, _Rows.live, region: region),
        drawn,
      );
    });
  }

  testWidgets('a keyed sheet lands on another one — its own pixels through '
      'the keys, in place of what the row shows there', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: true));
    // Clear of each other; carried by (40, 30), the first lands on the
    // second's upper left.
    final carried = Rect.fromLTWH(c.dx - 150, c.dy - 90, 96, 80);
    final under = Rect.fromLTWH(c.dx - 100, c.dy - 5, 120, 90);
    await lay(
      tester,
      textToolKey,
      carried.expandToInclude(under),
      (x, y) => sheet(carried, x, y) ?? sheet(under, x, y),
    );
    await settle(tester);
    final drawn = await composite(tester);

    expectLandsAsCarried(
      await carry(
        tester,
        _Rows.live,
        // With room above it and left of it, and none of the other.
        region: Rect.fromPoints(
          carried.topLeft - const Offset(60, 60),
          carried.bottomRight,
        ),
      ),
      drawn,
    );
  });

  testWidgets('keyed line art carried whole lands on nothing — its partly '
      'clear edges too', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: true));
    final art = Rect.fromLTWH(c.dx - 160, c.dy - 64, 120, 120);
    await lay(tester, textToolKey, art, (x, y) => lineArt(art, x, y));
    await settle(tester);
    final drawn = await composite(tester);

    expectLandsAsCarried(
      await carry(tester, _Rows.live, region: art.inflate(60)),
      drawn,
    );
  });

  testWidgets('a keyed sheet scaled where it stands, and scaled again, shows '
      'what it lands as — every picture the warp resamples to, at the same '
      'place', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: true));
    final region = await sheets(tester, c, _Rows.live);
    final drawn = await composite(tester);

    // Two scales about the one middle: one place, two pictures — the landing
    // shown for the first is no landing of the second.
    expectLandsAsCarried(
      await carry(
        tester,
        _Rows.live,
        region: region,
        warps: [
          (now) => now.copyWith(sx: 1.25, sy: 1.25),
          (now) => now.copyWith(sx: 1.5, sy: 1.5),
        ],
      ),
      drawn,
    );
  });

  // 🧭관제 2026-11-11 18:47 (a-float-premultiplies-in-the-c-each-step):
  // 「플로트를 엔진에 놓아(`EngineHeld` 길) Flutter 표시용 디코드 자체를
  // 없애는 쪽」 — the canvas lays an open warp's resample as its tiles, so
  // nothing pictures it: no premultiply, no upload, a step of the box.
  testWidgets('a sheet scaled in its box, and scaled again, is laid as its '
      'tiles — no picture is made of what the canvas shows', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: false));
    final region = await sheets(tester, c, _Rows.live);
    final commands = await select(tester, _Rows.live, region);
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    commands.beginTransform();

    final shown = <Object>{};
    for (final by in [1.25, 1.5]) {
      commands.editTransformValues((now) => now.copyWith(sx: by, sy: by));
      await settle(tester);
      final resampled = canvasOf(tester).live!.floatOverlay!.value!.resampled;
      expect(resampled, isNotNull, reason: '⛔fixture: its resample shown');
      shown.add(resampled!);
      expect(resampled.debugPictured, isFalse, reason: 'scaled by $by');
    }
    expect(shown, hasLength(2), reason: '⛔CONTROL: each scale a resample');
  });

  testWidgets('a keyed sheet on a posed row shows what it lands as', (
    tester,
  ) async {
    final c = await open(
      tester,
      projectOf(
        _Rows.live,
        keyed: true,
        // Moved by (13, 7): its anchor is the canvas's middle.
        pose: TransformPose(
          center: CanvasPoint(
            x: defaultCutCanvasSize.width / 2 + 13,
            y: defaultCutCanvasSize.height / 2 + 7,
          ),
        ),
      ),
    );
    final region = await sheets(tester, c, _Rows.live);
    final drawn = await composite(tester);

    expectLandsAsCarried(
      await carry(tester, _Rows.live, region: region),
      drawn,
    );
  });

  testWidgets('a keyed sheet on a posed row in a folder shows what it lands '
      'as — past the page too, where the pose put it', (tester) async {
    const page = defaultCutCanvasSize;
    final c = await open(
      tester,
      projectOf(
        _Rows.folder,
        keyed: true,
        // A moved right by 30: its anchor is the canvas's middle.
        pose: TransformPose(
          center: CanvasPoint(x: page.width / 2 + 30, y: page.height / 2),
        ),
      ),
    );
    // A shows 10 short of the page's right edge — its cel 40 short, and the
    // pose's 30 — so carried right by 40, its last 30 columns land PAST
    // THE PAGE, where the composite holds only what the rows ask room for.
    // B LEFT of A, so B's own room asks for none of that.
    final a = Rect.fromLTRB(
      page.width - 160.0,
      c.dy - 64,
      page.width - 40.0,
      c.dy + 56,
    );
    final aShown = a.shift(const Offset(30, 0));
    final b = aShown.shift(const Offset(-200, 0));
    await lay(tester, textToolKey, a, (x, y) => sheet(a, x, y));
    await lay(tester, keyB, b, (x, y) => sheet(b, x, y));
    await settle(tester);
    expect(
      tester
          .getRect(theFramesPicture(within: mainCanvasPanel()))
          .contains(onScreen(tester, page.width + 29.0, c.dy + 30)),
      isTrue,
      reason: '⛔fixture: what lands past the page is on the screen',
    );
    final drawn = await composite(tester);

    // ⚠️The box ENDS AT A's RIGHT EDGE on the canvas: with room right of
    // the sheet, the landing's own clear room took the cut of an extent
    // measured through the pose a second time — 30 short — and the
    // composite came out the same. 🔬2026-10-16, the mutant walked past
    // the two boxes this test carried first: the folder is no buffer of
    // its own (it passes through), so a short extent cuts only where the
    // page's own room does not reach.
    final room = aShown.expandToInclude(b).inflate(60);
    expectLandsAsCarried(
      await carry(
        tester,
        _Rows.folder,
        region: Rect.fromLTRB(room.left, room.top, aShown.right, room.bottom),
      ),
      drawn,
    );
  });

  for (final keyed in [false, true]) {
    testWidgets('a sheet carried under a text shows under it — keyed '
        '$keyed', (tester) async {
      final c = await open(tester, projectOf(_Rows.live, keyed: keyed));
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(celOf(tester).texts, hasLength(1), reason: '⛔fixture: a text');
      final under = Rect.fromLTWH(c.dx - 96, c.dy - 96, 192, 192);
      await lay(tester, textToolKey, under, (x, y) => sheet(under, x, y));
      await settle(tester);
      final drawn = await composite(tester);

      expectLandsAsCarried(
        await carry(tester, _Rows.live, region: under.inflate(60)),
        drawn,
      );
    });
  }

  // ── Rows whose chain runs a plugin, dragged and warped: the engine runs
  // it over what floats as over the cel. ↩️What floated was the landing
  // made on the whole cel (🗣️I-132-Q32 b), while a plugin at the chain's
  // head ran on the CPU over the cel alone — until it was a step of the
  // chain (float-warp-resamples-in-the-c-engine (2), 2026-11-11). ──

  for (final rows in _Rows.values) {
    for (final warped in [false, true]) {
      final how = warped ? 'warped' : 'dragged';
      testWidgets('${rows.name}: a sheet $how by the box on rows whose chain '
          'runs a PLUGIN shows what it lands as — the plugin over the cel and '
          'what floats on it', (tester) async {
        final c = await open(
          tester,
          projectOf(rows, keyed: false, plugin: true),
          // Past the stamp a float lands as — the box it was carried in,
          // 60 round the sheets, scaled up too — so that what the plugin
          // makes of the float shows where nothing of the float lies.
          fxPlugins: await installedShiftingFxPlugin(tester, by: 100),
        );
        expect(
          theCanvasRowRunsAPlugin(tester),
          isTrue,
          reason: '⛔fixture: the device\'s plugin runs on the canvas',
        );
        final region = await sheets(tester, c, rows);
        final drawn = await composite(tester);

        expectLandsAsCarried(
          await carry(
            tester,
            rows,
            region: region,
            warps: [if (warped) movedAndScaled],
          ),
          drawn,
        );
      });
    }
  }

  /// The app on row A wearing the stand-in plugin, A's sheet laid: the
  /// region it is carried in, and the frame as it stands before any box.
  Future<({Rect region, Uint8List drawn})> aPluginRowToCarry(
    WidgetTester tester,
  ) async {
    final c = await open(
      tester,
      projectOf(_Rows.live, keyed: false, plugin: true),
      fxPlugins: await installedShiftingFxPlugin(tester, by: 100),
    );
    final region = await sheets(tester, c, _Rows.live);
    return (region: region, drawn: await composite(tester));
  }

  testWidgets('live: a sheet dragged by the box on a row whose chain runs a '
      'PLUGIN and put back by a cancel shows the frame as it stood — what '
      'went through the plugin was the view\'s own, not the frame\'s', (
    tester,
  ) async {
    final (:region, :drawn) = await aPluginRowToCarry(tester);
    // Read with the text tool in hand, as [carry] reads them.
    final hold = holdIn(tester, region);
    final step = handFor(tester, 40, 30);
    final commands = await select(tester, _Rows.live, region);
    final hand = await tester.startGesture(
      hold,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await hand.moveTo(hold + step);
    await tester.pump();
    await hand.up();
    await settle(tester);
    expect(commands.transformActive, isTrue, reason: '⛔fixture: a box');
    expect(
      _apart(drawn, await composite(tester)),
      greaterThan(0),
      reason: '⛔CONTROL: what is carried shows',
    );
    final picture = theFramesPicture(within: mainCanvasPanel());
    final view = tester.widget<FramePictureView>(picture);
    final frame = view.run.pictures.keyOfStack(view.nodes, view.picture);
    expect(
      view.run.pictures.store.peek(
        keptByTheCanvas(tester, frame, view: picture),
      ),
      isNotNull,
      reason:
          'what went through the plugin with the float is kept under the '
          'canvas\'s own key — a picture under the frame\'s is the frame, '
          'for every screen that asks for it',
    );

    commands.cancelTransform();
    await settle(tester);

    expect(_apart(drawn, await composite(tester)), 0);
  });

  testWidgets('live: a sheet dragged by the box on a row whose chain runs a '
      'PLUGIN shows what it lands as once the row\'s opacity changes with '
      'the box open — the picture the frame is given goes through too', (
    tester,
  ) async {
    final (:region, :drawn) = await aPluginRowToCarry(tester);

    expectLandsAsCarried(
      await carry(
        tester,
        _Rows.live,
        region: region,
        whileOpen: () async {
          sessionOf(tester).opacityVerbs.setLayerOpacity(
            layerId: textToolLayerId,
            opacity: 0.5,
          );
          await settle(tester);
        },
      ),
      drawn,
    );
  });

  /// 🧭관제 2026-11-12 08:5x (float-warp-resamples-in-the-c-engine): 「변화가
  /// 몰리면 하나만 돈다(앞 것이 끝나야 다음, 마지막 변화는 반드시 돈다)」 — a
  /// device's run takes real time, on a worker (`GpuFxPlugin.render`), so a
  /// drag's moves come while a write is on its way through the plugin.
  testWidgets('live: a sheet dragged by the box on a row whose chain runs a '
      'PLUGIN goes through it one write at a time — what moves meanwhile '
      'waits, and the last of it goes through once the write on its way has '
      'ended', (tester) async {
    final gate = _HeldAtTheGate(ShiftingFxPlugin(by: 100));
    final c = await open(
      tester,
      projectOf(_Rows.live, keyed: false, plugin: true),
      fxPlugins: await installedShiftingFxPlugin(tester, runner: gate),
    );
    final region = await sheets(tester, c, _Rows.live);
    final drawn = await composite(tester);
    // Read with the text tool in hand, as [carry] reads them.
    final hold = holdIn(tester, region);
    final step = handFor(tester, 20, 15);
    final commands = await select(tester, _Rows.live, region);
    bool nothingOnItsWay() =>
        (tester.state(theFramesPicture(within: mainCanvasPanel())) as dynamic)
                .nothingOnItsWay
            as bool;

    final before = gate.asked;
    gate.hold();
    final hand = await tester.startGesture(
      hold,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await hand.moveTo(hold + step);
    // 🔬Read before a frame: the next already owes the box's step behind
    // the write, and owed alone would answer.
    expect(
      nothingOnItsWay(),
      isFalse,
      reason: 'the write the move began is on its way, nothing behind it yet',
    );
    await pumpFrames(tester, 2);
    expect(gate.asked, before + 1, reason: '⛔CONTROL: a write on its way');
    for (final times in [2.0, 3.0]) {
      await hand.moveTo(hold + step * times);
      await pumpFrames(tester, 2);
    }
    await hand.up();
    await settle(tester);
    expect(commands.transformActive, isTrue, reason: '⛔fixture: a box');
    expect(
      nothingOnItsWay(),
      isFalse,
      reason: 'the frame shows late what is on its way',
    );
    expect(
      gate.asked,
      before + 1,
      reason: 'what moved meanwhile starts no write of its own',
    );

    // ⚠️Not how many runs follow: the write on its way records the live
    // rows as they are at each of its rounds, and one whose step's picture
    // grew with the move meets that step anew (`FxPluginStages`).
    gate.letThrough();
    final carried = await composite(tester);
    await windowBehind(tester, () async => commands.applyTransform());
    await settle(tester);
    expectLandsAsCarried(
      (carried: carried, landed: await composite(tester)),
      drawn,
    );
  });

  for (final rows in [_Rows.live, _Rows.range]) {
    for (final warped in [false, true]) {
      final how = warped ? 'warped' : 'dragged';
      testWidgets('${rows.name}: a sheet $how on keyed rows whose chain runs '
          'a PLUGIN shows what it lands as once the device lets the plugin go '
          'with the box open — the landing and the hole asked again', (
        tester,
      ) async {
        final plugins = await installedShiftingFxPlugin(tester, by: 40);
        final c = await open(
          tester,
          projectOf(rows, keyed: true, plugin: true),
          fxPlugins: plugins,
        );
        final region = await sheets(tester, c, rows);
        if (rows == _Rows.range) {
          // Ink on B the box does not hold: B's hole shows it, through
          // its chain.
          final b = Rect.fromLTWH(c.dx + 40, c.dy - 64, 120, 120);
          final apart = Rect.fromLTWH(c.dx + 40, c.dy + 130, 40, 40);
          await lay(
            tester,
            keyB,
            b.expandToInclude(apart),
            (x, y) => sheet(b, x, y) ?? sheet(apart, x, y),
          );
          await settle(tester);
        }
        final drawn = await composite(tester);

        expectLandsAsCarried(
          await carry(
            tester,
            rows,
            region: region,
            warps: [if (warped) movedAndScaled],
            whileOpen: () async {
              await tester.runAsync(
                () => plugins.uninstall(shiftingFxPluginDescription.id),
              );
              await settle(tester);
              expect(
                theCanvasRowRunsAPlugin(tester),
                isFalse,
                reason: '⛔fixture: the plugin is gone from the canvas',
              );
            },
          ),
          drawn,
        );
      });
    }
  }

  testWidgets('⛔CONTROL: on a row that keys nothing a sheet floats as its '
      'own pixels, and lands as them', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: false));
    final region = await sheets(tester, c, _Rows.live);
    final drawn = await composite(tester);

    expectLandsAsCarried(
      await carry(tester, _Rows.live, region: region),
      drawn,
    );
  });

  /// The landing the live row shows the float as, asked through the row's
  /// own keys — the one its paint was handed.
  CelTextLanding shownLanding(WidgetTester tester) {
    final stack = canvasOf(tester);
    CanvasActiveLayerRow? row;
    void walk(List<CompositeNode<CanvasStackRow>> nodes) {
      for (final node in nodes) {
        switch (node) {
          case CompositeLeaf(payload: final CanvasActiveLayerRow live):
            row = live;
          case CompositeGroup(:final children):
            walk(children);
          case CompositeAdjustment(:final children):
            walk(children);
          case CompositeBackdropBlend(:final children):
            walk(children);
          case CompositeClip(:final children):
            walk(children);
          case CompositeReadsRows(:final children):
            walk(children);
          case CompositeLeaf():
          case CompositeOpaque():
          case CompositeCelNumber():
            break;
        }
      }
    }

    walk(stack.nodes);
    final shown = stack.live!.floatOverlay!.value!
        .shownOn(row!.sourceEffects)
        .preview;
    expect(shown, isA<CelTextLanding>(), reason: '⛔fixture: a landing');
    return shown as CelTextLanding;
  }

  // ── A posed row's float is its landing, and the landing is the engine's. ──

  /// A's sheet left of [c] on a row [pose] turns about the page's middle,
  /// and the box a hand carries it in: THE CANVAS'S, round where the row
  /// shows the sheet — and where on the screen a hand takes hold in it, on
  /// the sheet, clear of the cross at the box's middle.
  ///
  /// ⚠️The stage reads the row's own pixels ([onScreen]), which such a row
  /// shows somewhere other than their numbers say: a box of the sheet's own
  /// numbers is not round it, and a hold a quarter across that box
  /// ([holdIn]) was the box's turn, not its move (🔬2026-11-11).
  Future<({Rect region, Offset hold})> sheetOnATurnedRow(
    WidgetTester tester,
    Offset c,
    TransformPose pose,
  ) async {
    final a = Rect.fromLTWH(c.dx - 160, c.dy - 64, 120, 120);
    await lay(tester, textToolKey, a, (x, y) => sheet(a, x, y));
    await settle(tester);
    final placement = placedBy(pose, defaultCutCanvasSize);
    final shown = [
      for (final corner in [a.topLeft, a.topRight, a.bottomRight, a.bottomLeft])
        placement.apply(CanvasPoint(x: corner.dx, y: corner.dy)),
    ];
    final xs = [for (final point in shown) point.x];
    final ys = [for (final point in shown) point.y];
    return (
      region: Rect.fromLTRB(
        xs.reduce(math.min).floorToDouble(),
        ys.reduce(math.min).floorToDouble(),
        xs.reduce(math.max).ceilToDouble(),
        ys.reduce(math.max).ceilToDouble(),
      ).inflate(60),
      hold: onScreen(tester, a.center.dx + 30, a.center.dy + 30),
    );
  }

  // 🗣️유저 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」 — a pose
  // resamples what lands into the cel, so off the canvas's grid the float is
  // its landing whatever its row keys (flip lane ⓐ-2).
  testWidgets('a sheet on a row turned off the quarter shows what it lands '
      'as', (tester) async {
    const page = defaultCutCanvasSize;
    final pose = TransformPose(
      center: CanvasPoint(x: page.width / 2, y: page.height / 2),
      scaleX: 1.1,
      scaleY: 1.1,
      rotationDegrees: 8,
    );
    final c = await open(
      tester,
      projectOf(_Rows.live, keyed: false, pose: pose),
    );
    final (:region, :hold) = await sheetOnATurnedRow(tester, c, pose);
    final drawn = await composite(tester);

    expectLandsAsCarried(
      await carry(tester, _Rows.live, region: region, holdAt: hold),
      drawn,
    );
  });

  // 🔬A float on a posed row is its landing, made at each place a hand
  // carries it to, and that landing is the engine's: read back to be shown
  // it was a GPU wait a tile, about 187 a frame on S5_BA's paper (Surface
  // Pro 11, 검증/서피스 11-10) — and its crossing into the row made here, a
  // 26.7 MB float was 55–68 ms of resample and 32–44 ms of handing the
  // bytes up again, a step (main PC, 11-11, gpu-canonical-store ⑪).
  testWidgets('carried on a posed row, a step is the engine\'s: no tile '
      'comes off it, the float is neither resampled here nor handed up '
      'again nor read back', (tester) async {
    const page = defaultCutCanvasSize;
    final pose = TransformPose(
      center: CanvasPoint(x: page.width / 2, y: page.height / 2),
      rotationDegrees: 8,
    );
    final c = await open(
      tester,
      projectOf(_Rows.live, keyed: false, pose: pose),
    );
    final (:region, :hold) = await sheetOnATurnedRow(tester, c, pose);
    final first = hold + handFor(tester, 40, 30);
    final second = hold + handFor(tester, 46, 34);
    final commands = await select(tester, _Rows.live, region);

    // From the press on: the lift crosses the sheet out onto the canvas on
    // the engine too, and nothing asks for its bytes back.
    final readBack = EngineStampPictures.debugReadBack;
    final hand = await tester.startGesture(hold, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await hand.moveTo(first);
    await settle(tester);
    expect(commands.movePending, isTrue, reason: '⛔fixture: in hand');
    expect(
      canvasOf(tester).live!.floatOverlay!.value!.resampled,
      isNull,
      reason: '⛔fixture: carried, the float its own pixels — no warp of the '
          'box\'s',
    );
    final there = shownLanding(tester);

    final reads = EngineTileLedger.instance.debugTileReads;
    final handedUp = EngineStampPictures.debugHandedUp;
    await hand.moveTo(second);
    await settle(tester);

    expect(
      identical(shownLanding(tester), there),
      isFalse,
      reason: '⛔CONTROL: the step made a landing of its own',
    );
    expect(EngineTileLedger.instance.debugTileReads, reads);
    expect(EngineStampPictures.debugHandedUp, handedUp);
    await hand.up();
    await settle(tester);
    expect(EngineStampPictures.debugReadBack, readBack);
  });

  // ── What a landing holds is let go. ──

  testWidgets('a landing made for one place is let go once the hand carries '
      'the float on, and the last once the box lands', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: true));
    final region = await artOverSheet(tester, c);
    final step = holdIn(tester, region);
    final first = step + handFor(tester, 40, 30);
    final second = step + handFor(tester, 46, 34);
    final commands = await select(tester, _Rows.live, region);

    final hand = await tester.startGesture(step, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await hand.moveTo(first);
    await settle(tester);
    final there = shownLanding(tester);
    // Made as a canvas that paints the landing makes it: what is let go.
    final pictureThere = there.picture;
    await hand.moveTo(second);
    await settle(tester);
    final further = shownLanding(tester);
    final pictureFurther = further.picture;
    await hand.up();
    await settle(tester);

    expect(identical(there, further), isFalse, reason: '⛔fixture: carried on');
    expect(pictureThere.debugDisposed, isTrue);
    expect(pictureFurther.debugDisposed, isFalse, reason: 'still shown');

    await windowBehind(tester, () async => commands.applyTransform());
    expect(
      await settleAsync(
        tester,
        () => pictureFurther.debugDisposed,
        step: const Duration(milliseconds: 16),
      ),
      isTrue,
      reason: 'the last landing is let go once the box lands',
    );
  });
}

/// How many pixels of [a] and [b] are apart at all.
int _apart(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n += 1;
    }
  }
  return n;
}

/// [_shifting] whose runs wait, while it is held ([hold]), for the test to
/// let them through ([letThrough]): a device's run takes real time, a
/// stand-in's none.
final class _HeldAtTheGate implements FxPluginRunner {
  _HeldAtTheGate(this._shifting);

  final ShiftingFxPlugin _shifting;
  Completer<void>? _gate;

  /// How many runs it was asked for.
  int asked = 0;

  void hold() => _gate ??= Completer<void>();

  void letThrough() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      _shifting.reach(values, moment);

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) async {
    asked += 1;
    if (_gate case final gate?) {
      await gate.future;
    }
    return _shifting.render(
      input: input,
      values: values,
      layers: layers,
      moment: moment,
    );
  }

  @override
  void close() => _shifting.close();

  @override
  bool get closed => _shifting.closed;
}
