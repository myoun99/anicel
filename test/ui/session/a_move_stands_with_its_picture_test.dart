import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/presses_wait_for_the_frame.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/session/stands_with_its_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/an_effect_sampled.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/settle_async.dart';

/// the-standing-canvas-composes-a-frame-twice-before-its-picture-Q1 = B
/// (유저 2026-11-18, 「임시 그리기를 뺀다」): a canvas that stands goes to a
/// frame with its picture — the playhead stands on the frame shown until
/// the frame moved to has its picture, and goes with it
/// ([StandsWithItsPicture]); a press meanwhile is the frame moved to's,
/// from its first point (11-15 ① (나), [PressesWaitForTheFrame]).
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 16, height: 16);

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 3,
    canvasSize: canvasSize,
    layers: const [],
  );
  final otherCut = Cut(
    id: const CutId('o'),
    name: 'o',
    duration: 3,
    canvasSize: canvasSize,
    layers: const [],
  );

  BrushFrameKey keyOf(int frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut.id,
    layerId: const LayerId('l'),
    frameId: FrameId('f$frame'),
  );

  /// Three frames, each a cel of its own colour.
  FramePictures threeFrames() {
    final store = BrushFrameStore();
    for (final (frame, colour) in [
      (0, 0xFF0000FF),
      (1, 0xFFFF0000),
      (2, 0xFF00FF00),
    ]) {
      inkCelIn(
        store,
        keyOf(frame),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 8, y: 8),
        size: 14,
        tipShape: BrushTipShape.square,
        color: colour,
      );
    }
    final pictures = aStoreOfPictures();
    addTearDown(pictures.dispose);
    return FramePictures(
      store: pictures,
      layerImages: LayerFrameImageCache(frameStore: store),
      stackOf: (picture) => [
        // Blurred, so a frame laid holds a chain of its own: a canvas that
        // goes to it keeps it for the pen (`heldNodes`).
        CompositeGroup<CanvasStackRow>(
          effects: [
            fx(EffectKind.blur, {'blurriness': 1}),
          ],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          children: [
            CompositeLeaf<CanvasStackRow>(
              CanvasLayerImageRequest(
                frameKey: keyOf(picture.frameIndex),
                opacity: 1,
              ),
            ),
          ],
        ),
      ],
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.none,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
    );
  }

  DemandedPicture frameAt(int frame) => standingPicturesOf(
    cut,
    frame,
    OnionSkinPlacement.inPlace,
  ).frame;

  /// A session's frame, and the moves of its playhead.
  ({
    StandsWithItsPicture moves,
    FramePictures pictures,
    ValueNotifier<int> frame,
    ValueNotifier<Cut> cutStood,
  })
  aSession() {
    final pictures = threeFrames();
    final frame = ValueNotifier<int>(0);
    final cutStood = ValueNotifier<Cut>(cut);
    final moves = StandsWithItsPicture(
      pictures: () => pictures,
      cut: () => cutStood.value,
      frame: () => frame.value,
      placement: () => OnionSkinPlacement.inPlace,
    );
    addTearDown(moves.dispose);
    addTearDown(frame.dispose);
    addTearDown(cutStood.dispose);
    return (moves: moves, pictures: pictures, frame: frame, cutStood: cutStood);
  }

  /// What a point is, as a hand would say it.
  String kindOf(PointerEvent event) => switch (event) {
    PointerDownEvent() => 'down',
    PointerMoveEvent() => 'move',
    PointerUpEvent() => 'up',
    _ => 'cancel',
  };

  Future<void> make(WidgetTester tester, FramePictures pictures, int frame) =>
      tester.runAsync(
        () => pictures.make(frameAt(frame), shouldAbort: () => false),
      );

  testWidgets('a move to a frame with no picture stands on the frame shown '
      'till the picture is there, and goes with it', (tester) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    s.moves.shownBy(tester);

    expect(
      s.pictures.heldNodes.heldBytes,
      0,
      reason: '⛔premise: the frame shown was made ahead',
    );
    s.moves.moveTo(1, () => s.frame.value = 1);

    expect(s.frame.value, 0, reason: 'the playhead stands on the frame shown');
    expect(s.moves.waitsFor.value, 1);
    expect(s.pictures.has(frameAt(1)), isFalse);
    expect(
      await settleAsync(tester, () => s.frame.value == 1),
      isTrue,
      reason: 'it goes once the picture is there',
    );
    expect(s.pictures.has(frameAt(1)), isTrue);
    expect(
      s.pictures.heldNodes.heldBytes,
      greaterThan(0),
      reason: 'made as the canvas that goes to it makes it: its chains held '
          'for the pen',
    );
    expect(s.moves.waitsFor.value, isNull);
  });

  testWidgets('a move to a frame with its picture goes at once', (
    tester,
  ) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    await make(tester, s.pictures, 2);
    s.moves.shownBy(tester);

    s.moves.moveTo(2, () => s.frame.value = 2);

    expect(s.frame.value, 2);
    expect(s.moves.waitsFor.value, isNull);
  });

  testWidgets('a move goes at once where no canvas stands to show it', (
    tester,
  ) async {
    final s = aSession();
    await make(tester, s.pictures, 0);

    s.moves.moveTo(1, () => s.frame.value = 1);

    expect(s.frame.value, 1);
    expect(s.moves.waitsFor.value, isNull);
  });

  testWidgets('a move goes at once where the frame stood on shows no '
      'picture either — nothing to stand on', (tester) async {
    final s = aSession();
    s.moves.shownBy(tester);

    s.moves.moveTo(1, () => s.frame.value = 1);

    expect(s.frame.value, 1);
    expect(s.moves.waitsFor.value, isNull);
  });

  testWidgets('the move after replaces the one that waits', (tester) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    s.moves.shownBy(tester);
    final landed = <int>[];
    var withItsPicture = false;

    s.moves.moveTo(1, () => landed.add(1));
    s.moves.moveTo(2, () {
      landed.add(2);
      withItsPicture = s.pictures.has(frameAt(2));
      s.frame.value = 2;
    });

    expect(s.moves.waitsFor.value, 2);
    expect(await settleAsync(tester, () => s.frame.value == 2), isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(landed, [2], reason: 'a frame passed over is never stood on');
    expect(
      withItsPicture,
      isTrue,
      reason: 'and the one it goes to lands with its picture, not with the '
          'making of the one it passed over',
    );
  });

  testWidgets('a move asked again for the frame it waits for lands as it '
      'was last asked — a scrub let go of there commits it', (tester) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    s.moves.shownBy(tester);
    final landed = <String>[];

    s.moves.moveTo(1, () => landed.add('scrubbed'));
    s.moves.moveTo(1, () {
      landed.add('committed');
      s.frame.value = 1;
    });

    expect(await settleAsync(tester, () => s.frame.value == 1), isTrue);
    expect(landed, ['committed']);
  });

  testWidgets('no move goes under a press held for the frame moved to', (
    tester,
  ) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    s.moves.shownBy(tester);
    s.moves.moveTo(1, () => s.frame.value = 1);
    s.moves.holdsAPress(held: true);

    var other = false;
    s.moves.moveTo(2, () => other = true);

    expect(s.moves.waitsFor.value, 1);
    expect(await settleAsync(tester, () => s.frame.value == 1), isTrue);
    expect(other, isFalse);
  });

  testWidgets('a move whose cut is left meanwhile does not land', (
    tester,
  ) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    s.moves.shownBy(tester);
    var landed = false;
    s.moves.moveTo(1, () => landed = true);

    s.cutStood.value = otherCut;

    expect(
      await settleAsync(tester, () => s.moves.waitsFor.value == null),
      isTrue,
    );
    expect(landed, isFalse);
  });

  testWidgets('the last canvas that goes lands the move that waits', (
    tester,
  ) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    s.moves.shownBy(tester);
    s.moves.moveTo(1, () => s.frame.value = 1);

    s.moves.noLongerShownBy(tester);

    expect(s.frame.value, 1);
    expect(s.moves.waitsFor.value, isNull);
  });

  testWidgets('a press while a move waits goes to the canvas from its first '
      'point once the move lands, and none before', (tester) async {
    final s = aSession();
    await make(tester, s.pictures, 0);
    final points = <String>[];
    // Each point with the frame the session stood on as the canvas took it.
    void took(PointerEvent event) => points.add(
      '${kindOf(event)}@${event.localPosition.dx}/f${s.frame.value}',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: PressesWaitForTheFrame(
              moves: s.moves,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: took,
                onPointerMove: took,
                onPointerUp: took,
                onPointerCancel: took,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    s.moves.moveTo(1, () => s.frame.value = 1);
    await tester.pump();
    final corner = tester.getTopLeft(find.byType(PressesWaitForTheFrame));

    final pen = await tester.startGesture(corner + const Offset(10, 10));
    await pen.moveTo(corner + const Offset(20, 10));
    await tester.pump();

    expect(points, isEmpty, reason: 'held while the move waits');
    var passedUnder = false;
    s.moves.moveTo(2, () => passedUnder = true);
    expect(
      s.moves.waitsFor.value,
      1,
      reason: 'no other move goes under the press held for frame 1',
    );
    expect(await settleAsync(tester, () => s.frame.value == 1), isTrue);
    await tester.pump();
    expect(passedUnder, isFalse);
    expect(points, [
      'down@10.0/f1',
      'move@20.0/f1',
    ], reason: 'every point held, in order, on the frame the move landed on');

    await pen.moveTo(corner + const Offset(30, 10));
    await pen.up();
    expect(points.skip(2), [
      'move@30.0/f1',
      'up@30.0/f1',
    ], reason: 'and the points after it come the usual way');

    s.moves.moveTo(0, () => s.frame.value = 0);
    expect(s.frame.value, 0, reason: 'the press handed on holds no move');

    final next = await tester.startGesture(corner + const Offset(50, 10));
    await next.up();
    expect(points.skip(4), [
      'down@50.0/f0',
      'up@50.0/f0',
    ], reason: 'a press while no move waits goes straight to the canvas');
  });
}
