// 🗣️F-525 (유저 2026-11-01): 「활성레이어 솔로한채로 픽셀붙여넣기하면 버그남 …
// 즉 솔로할때만 안보임. 다른 붙여넣기관련도 버그났을수도있으니 근본적으로확인」.
//
// Whatever lands on a cel but a stroke has no step in the picture shown: it
// goes in as one patch. Reaching past a picture, with no step to widen it,
// it cannot — and the frame's key must not be left with a picture short of
// it.
//
// 🚨The frame goes first here, as in the app: [settle] builds before the
// warmer gets a turn. Pumped by time alone, the warmer lays the new key first
// and no pin here is red without the fix.
// 🚨On Flutter GPU, as in the app (the `gpu` tag): with nothing to write with,
// every patch fails and a paste inside the page only ever proves a new lay.
@Tags(['gpu'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pixel_clipboard_verb.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/wait_window.dart' show windowBehind;

void main() {
  const red = [255, 0, 0, 255];
  const blue = [0, 0, 255, 255];

  /// Past the page's left edge, and past the picture of a stack that draws
  /// its page alone: tile (-2, 0) of 128.
  const pastTheX = -200.0;
  const pastTheY = 20.0;

  Project fixture() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    Layer named(String id) => row.copyWith(
      id: LayerId(id),
      name: id,
      frames: [
        Frame(id: FrameId('${id}0'), duration: 1, strokes: const []),
        Frame(id: FrameId('${id}1'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(FrameId('${id}0'), length: 1),
        1: TimelineExposure.drawing(FrameId('${id}1'), length: 1),
      },
    );
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id == row.id) ...[
                    named('b'),
                    named('a'),
                  ] else
                    layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  BrushFrameKey keyOf(EditorSessionManager s, String cel) {
    final row = cel.substring(0, 1);
    return s.brushFrameKeyForCut(
      s.requireActiveCut,
      LayerId(row),
      FrameId(cel),
    );
  }

  /// Paints tile [coord] of [cel] whole with [rgba].
  void paintTile(
    EditorSessionManager s,
    String cel,
    TileCoord coord,
    List<int> rgba,
  ) {
    final key = keyOf(s, cel);
    final coordinator = s.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    final pixels = Uint8List(size * size * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, rgba);
    }
    coordinator.restoreSurfaceSnapshot(
      key,
      base.putTiles([
        (
          coord: coord,
          tile: BitmapTile(size: size, pixels: pixels),
        ),
      ]),
    );
  }

  /// Builds, then lends both clocks until what was asked is in its pictures.
  ///
  /// ⚠️Not `runAsync` around the store's `settled`: its chain runs in the
  /// pumped zone and a write comes back from the GPU in real time — awaited
  /// there, the chain never moves on ([settleAsync]'s why).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await lendBothClocks(
      tester,
      rounds: 6,
      step: const Duration(milliseconds: 20),
    );
    final view = tester.widget<FramePictureView>(theFramesPicture());
    var landed = false;
    unawaited(view.run.pictures.store.settled().then((_) => landed = true));
    expect(await settleAsync(tester, () => landed), isTrue, reason: 'LIVENESS');
    await lendBothClocks(tester, rounds: 2);
  }

  /// What the picture under the frame's key — the one every screen takes,
  /// the view's own after any leaving and coming back — holds at ([x], [y]);
  /// null where it has no such place.
  Future<List<int>?> pictureAt(WidgetTester tester, double x, double y) async {
    final view = tester.widget<FramePictureView>(theFramesPicture());
    final pictures = view.run.pictures;
    final there = pictures.store.peek(
      pictures.keyOfStack(view.nodes, view.picture),
    );
    if (there == null) {
      return null;
    }
    final bytes = await tester.runAsync(() => there.image.toByteData());
    final extent = there.extent;
    final width = there.image.width;
    final height = there.image.height;
    final px = ((x - extent.left) * width / extent.width).floor();
    final py = ((y - extent.top) * height / extent.height).floor();
    if (px < 0 || py < 0 || px >= width || py >= height) {
      return null;
    }
    return [
      for (var c = 0; c < 4; c++) bytes!.getUint8((py * width + px) * 4 + c),
    ];
  }

  /// [project] with its row `b` turned 30° about the page's centre — a pose
  /// that leaves the axes, so a change of its cannot be told by where it
  /// lands.
  Project withRowBTurned(Project project) {
    final track = project.tracks.first;
    final cut = track.cuts.first;
    final pose = TransformPose(
      center: CanvasPoint(
        x: cut.canvasSize.width / 2,
        y: cut.canvasSize.height / 2,
      ),
      rotationDegrees: 30,
    );
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id.value == 'b')
                    layer.copyWith(
                      transformTrack: TransformTrack(keyframes: {0: pose}),
                    )
                  else
                    layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<EditorSessionManager> up(
    WidgetTester tester, {
    Project? project,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project ?? fixture())),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    s.selectLayer(const LayerId('a'));
    s.selectFrameIndex(0);
    await tester.pump();
    return s;
  }

  /// Copies a tile of [red] past the page from `a0`, and stands in solo on
  /// the blank `b0`.
  Future<EditorSessionManager> upWithACopyPastThePage(
    WidgetTester tester,
  ) async {
    final s = await up(tester);
    paintTile(s, 'a0', TileCoord(x: -2, y: 0), red);
    await settle(tester);
    s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.copy);
    s.selectLayer(const LayerId('b'));
    await settle(tester);
    s.visibilitySolo.toggleLayerVisibilitySolo();
    await settle(tester);
    return s;
  }

  /// Steps out of solo and back, and asks the paste at every step.
  Future<void> expectThroughSolo(
    WidgetTester tester,
    EditorSessionManager s,
    double x,
    double y, {
    List<int> rgba = red,
  }) async {
    expect(await pictureAt(tester, x, y), rgba, reason: 'landed, in solo');
    s.visibilitySolo.toggleLayerVisibilitySolo();
    await settle(tester);
    expect(await pictureAt(tester, x, y), rgba, reason: 'solo off');
    s.visibilitySolo.toggleLayerVisibilitySolo();
    await settle(tester);
    expect(
      await pictureAt(tester, x, y),
      rgba,
      reason: '↩️solo again took the picture that never held it (F-525)',
    );
  }

  CutPiece pieceAt(int left, int top) => CutPiece(
    image: BrushStampImage(
      id: 'piece-at-$left-$top',
      width: 20,
      height: 20,
      rgba: Uint8List.fromList([for (var i = 0; i < 400; i += 1) ...red]),
    ),
    originLeft: left,
    originTop: top,
  );

  group('a paste past the page, in solo', () {
    for (final verb in [
      PixelClipboardVerb.pasteAbove,
      PixelClipboardVerb.pasteBelow,
    ]) {
      testWidgets('${verb.name} is the frame\'s through solo and back', (
        tester,
      ) async {
        final s = await upWithACopyPastThePage(tester);

        s.pixelVerbs.runPixelClipboardVerb(verb);
        await settle(tester);

        await expectThroughSolo(tester, s, pastTheX, pastTheY);
      });
    }

    testWidgets('a picture landed by a verb of its own takes the same door', (
      tester,
    ) async {
      final s = await upWithACopyPastThePage(tester);

      s.pixelVerbs.landCanvasPicture(
        pieceAt(-210, 10),
        description: 'a picture',
      );
      await settle(tester);

      await expectThroughSolo(tester, s, pastTheX, pastTheY);
    });

    testWidgets('the cut tool\'s paste at its origin', (tester) async {
      final s = await upWithACopyPastThePage(tester);
      s.pixelVerbs.cutToolHand!(pieceAt(-210, 10));
      await settle(tester);

      final slot = tester
          .widget<BrushCanvasPanel>(
            find.byKey(const ValueKey<String>('main-canvas-brush-host')),
          )
          .cutPieceSlot!;
      await windowBehind(tester, () async => slot.pasteAtOriginHandler!());
      await settle(tester);

      await expectThroughSolo(tester, s, pastTheX, pastTheY);
    });

    testWidgets('undone and redone, it goes and it comes back', (tester) async {
      final s = await upWithACopyPastThePage(tester);
      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
      await settle(tester);

      s.undo();
      await settle(tester);
      expect(await pictureAt(tester, pastTheX, pastTheY), isNot(red));

      s.redo();
      await settle(tester);
      await expectThroughSolo(tester, s, pastTheX, pastTheY);
    });
  });

  testWidgets('it is no matter of solo: a paste past what the frame draws '
      'stays once you leave the frame and come back', (tester) async {
    final s = await up(tester);
    s.selectFrameIndex(1);
    await settle(tester);
    paintTile(s, 'a1', TileCoord(x: -2, y: 0), red);
    await settle(tester);
    s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.copy);
    s.selectFrameIndex(0);
    s.selectLayer(const LayerId('b'));
    await settle(tester);

    s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await settle(tester);
    expect(await pictureAt(tester, pastTheX, pastTheY), red, reason: 'landed');

    s.selectFrameIndex(1);
    await settle(tester);
    s.selectFrameIndex(0);
    await settle(tester);

    expect(
      await pictureAt(tester, pastTheX, pastTheY),
      red,
      reason: '↩️the frame\'s key held the picture that never had it',
    );
  });

  testWidgets('nor of the picture\'s edge: on a turned row, where a change '
      'cannot be told by where it lands, a paste inside the page stays once '
      'you leave the frame and come back', (tester) async {
    final s = await up(tester, project: withRowBTurned(fixture()));
    final page = s.requireActiveCut.canvasSize;
    final middleX = page.width / 2;
    final middleY = page.height / 2;
    s.selectFrameIndex(1);
    await settle(tester);
    paintTile(
      s,
      'a1',
      TileCoord(x: middleX ~/ 128, y: middleY ~/ 128),
      red,
    );
    await settle(tester);
    s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.copy);
    s.selectFrameIndex(0);
    s.selectLayer(const LayerId('b'));
    await settle(tester);

    s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await settle(tester);
    s.selectFrameIndex(1);
    await settle(tester);
    s.selectFrameIndex(0);
    await settle(tester);

    // The row turns about the page's middle, which stays where it is.
    expect(
      await pictureAt(tester, middleX, middleY),
      red,
      reason: '↩️the frame\'s key held the picture that never had it',
    );
  });

  group('a paste inside the page goes in by a patch, in solo or out', () {
    /// Tile (0, 0) of `a0` red; copied, and left to stand on `b`.
    Future<EditorSessionManager> upWithACopyOnThePage(
      WidgetTester tester,
    ) async {
      final s = await up(tester);
      paintTile(s, 'a0', TileCoord(x: 0, y: 0), red);
      await settle(tester);
      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.copy);
      return s;
    }

    Future<void> standInSoloOnB(
      WidgetTester tester,
      EditorSessionManager s,
    ) async {
      s.selectLayer(const LayerId('b'));
      await settle(tester);
      s.visibilitySolo.toggleLayerVisibilitySolo();
      await settle(tester);
    }

    testWidgets('onto a blank cel', (tester) async {
      final s = await upWithACopyOnThePage(tester);
      await standInSoloOnB(tester, s);

      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
      await settle(tester);

      await expectThroughSolo(tester, s, 20, 20);
    });

    testWidgets('the picture it goes into is the one shown, not one laid '
        'anew', (tester) async {
      final s = await upWithACopyOnThePage(tester);
      await standInSoloOnB(tester, s);
      FramePicture? shownNow() {
        final view = tester.widget<FramePictureView>(theFramesPicture());
        return view.run.pictures.store.peek(
          view.run.pictures.keyOfStack(view.nodes, view.picture),
        );
      }

      final before = shownNow();
      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
      await settle(tester);

      expect(before, isNotNull, reason: '⛔premise: a picture to go into');
      expect(shownNow(), same(before));
      expect(await pictureAt(tester, 20, 20), red);
    }, skip: noFlutterGpu != null);

    testWidgets('over a drawing and under one', (tester) async {
      final s = await upWithACopyOnThePage(tester);
      paintTile(s, 'b0', TileCoord(x: 0, y: 0), blue);
      await settle(tester);
      await standInSoloOnB(tester, s);

      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteBelow);
      await settle(tester);
      expect(
        await pictureAt(tester, 20, 20),
        blue,
        reason: 'under the drawing',
      );

      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
      await settle(tester);
      await expectThroughSolo(tester, s, 20, 20);
    });

    testWidgets('a range across both rows', (tester) async {
      final s = await upWithACopyOnThePage(tester);
      s.selectLayer(const LayerId('b'));
      await settle(tester);
      s.frameRangeSelection.value = const TimelineFrameRangeSelection(
        layerId: LayerId('b'),
        layerIds: [LayerId('a'), LayerId('b')],
        startIndex: 0,
        endIndexExclusive: 1,
      );
      await settle(tester);
      s.visibilitySolo.toggleLayerVisibilitySolo();
      await settle(tester);

      s.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
      await settle(tester);

      await expectThroughSolo(tester, s, 20, 20);
    });
  });
}
