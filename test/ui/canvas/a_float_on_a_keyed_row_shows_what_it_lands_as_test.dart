import 'dart:ui' as ui;

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
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
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
import '../../helpers/settle_async.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';

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
  Future<Uint8List> composite(WidgetTester tester) async {
    final paint = find
        .descendant(
          of: theFramesPicture(within: mainCanvasPanel()),
          matching: find.byType(CustomPaint),
        )
        .evaluate()
        .firstWhere((e) => (e.widget as CustomPaint).painter != null);
    final size = (paint.renderObject! as RenderBox).size;
    final dpr = tester.view.devicePixelRatio;
    final recorder = ui.PictureRecorder();
    (paint.widget as CustomPaint).painter!.paint(
      Canvas(recorder, Offset.zero & size * dpr)..scale(dpr),
      size,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (size.width * dpr).round(),
      (size.height * dpr).round(),
    );
    picture.dispose();
    final bytes = await tester.runAsync(image.toByteData);
    image.dispose();
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  }

  /// Lets a step land: its frames, and the one thing here drawn off the
  /// frame's clock — the picture an open warp resamples to, decoded by the
  /// engine on a real thread — waited for until it is the one the box's
  /// values ask for now ([CanvasSelectionCommands.debugFloatsCaughtUp]).
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
  /// is on the screen.
  Future<({Uint8List carried, Uint8List landed})> carry(
    WidgetTester tester,
    _Rows rows, {
    required Rect region,
    List<TransformValues Function(TransformValues now)> warps = const [],
    bool twice = false,
    Future<void> Function()? whileOpen,
  }) async {
    final hold = holdIn(tester, region);
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
      for (final lifted in stack.live!.liftedRows.values) lifted.float.value,
    ];
    expect(
      [
        for (final float in floats)
          switch (float) {
            null => 'nothing',
            _ when float.isEmpty => 'nothing',
            _ when float.image != null => 'an image',
            _ => 'its surface',
          },
      ],
      [
        for (final _ in before)
          if (warps.isNotEmpty) 'an image' else 'its surface',
      ],
      reason: 'every row floats — a warp as the image it resamples to, a '
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
    commands.applyTransform();
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

  // ── 🗣️I-132-Q32 b: rows whose chain runs a plugin, dragged and warped. ──

  for (final rows in _Rows.values) {
    for (final warped in [false, true]) {
      final how = warped ? 'warped' : 'dragged';
      testWidgets('${rows.name}: a sheet $how by the box on rows whose chain '
          'runs a PLUGIN shows what it lands as — the whole cel the plugin '
          'makes', (tester) async {
        final c = await open(
          tester,
          projectOf(rows, keyed: false, plugin: true),
          // Far past where the float lands: the landing is the cel.
          fxPlugins: await installedShiftingFxPlugin(tester, by: 40),
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

  // ── What a landing holds is let go. ──

  testWidgets('a landing made for one place is let go once the hand carries '
      'the float on, and the last once the box lands', (tester) async {
    final c = await open(tester, projectOf(_Rows.live, keyed: true));
    final region = await artOverSheet(tester, c);
    final step = holdIn(tester, region);
    final first = step + handFor(tester, 40, 30);
    final second = step + handFor(tester, 46, 34);
    final commands = await select(tester, _Rows.live, region);

    /// The landing the live row shows the float as, asked through the
    /// row's own keys — the one its paint was handed.
    CelTextLanding shownLanding() {
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

    final hand = await tester.startGesture(step, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await hand.moveTo(first);
    await settle(tester);
    final there = shownLanding();
    await hand.moveTo(second);
    await settle(tester);
    final further = shownLanding();
    await hand.up();
    await settle(tester);

    expect(identical(there, further), isFalse, reason: '⛔fixture: carried on');
    expect(there.picture.debugDisposed, isTrue);
    expect(further.picture.debugDisposed, isFalse, reason: 'still shown');

    commands.applyTransform();
    expect(
      await settleAsync(
        tester,
        () => further.picture.debugDisposed,
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
