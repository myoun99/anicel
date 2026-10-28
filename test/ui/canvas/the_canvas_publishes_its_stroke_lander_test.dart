import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/stroke_in_flight.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';

/// 🚨★★★**THE CANVAS HANDS OUT THE ONE VERB A SAVE NEEDS, AND TAKES IT
/// BACK.** `ProjectFileDoor` lands the pen before it snapshots so that
/// pressing Ctrl+S mid-stroke puts that line in that file — but it can only
/// do that if a mounted canvas held up a lander, and only safely if a
/// gone canvas put it down.
///
/// ⚠️`a_manual_save_lands_the_pen_first_test` pins what the DOOR does with
/// the lander, and it sets one by hand. That is the half this file does
/// not cover and vice versa: without this one, the view could stop
/// publishing entirely and every save test would still be green.
void main() {
  const canvasSize = CanvasSize(width: 200, height: 200);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame'),
  );

  setUp(() {
    CanvasTouchContacts.reset();
    // Fingers must be allowed to draw at all, or the view bails earlier
    // and the test proves nothing.
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  late ViewHand<StrokeLander> landers;
  late ViewHand<ShapeShow> shapes;
  late List<BrushStrokeCommitData> commits;
  late List<bool> strokeActive;

  /// [wrapped] puts the view under a parent of another kind, so Flutter
  /// builds it anew in the same frame — as the main canvas panel's opacity
  /// wrap once did each time the row's opacity crossed 1 (F-419).
  Future<void> pumpInk(
    WidgetTester tester, {
    bool mounted = true,
    bool wrapped = false,
  }) async {
    final store = BrushFrameEditSessionStore(canvasSize: canvasSize);
    final view = InteractiveBrushEditCanvasView(
      key: const ValueKey<String>('ink'),
      celNow: () => store.getOrCreate(key).canvasState.currentSurface,
      layerId: const LayerId('layer'),
      frameId: const FrameId('frame'),
      inputSettings: BrushEditCanvasInputSettings.new,
      onSourceStrokeCommitted: commits.add,
      strokeLander: landers,
      shapeShow: shapes,
      onActiveStrokeChanged: (stroke) =>
          strokeActive.add(stroke != StrokeInFlight.none),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: switch ((mounted, wrapped)) {
                (false, _) => const SizedBox.shrink(),
                (true, false) => view,
                (true, true) => Opacity(opacity: 1, child: view),
              },
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    landers = ViewHand();
    shapes = ViewHand();
    commits = <BrushStrokeCommitData>[];
    strokeActive = <bool>[];
  });

  testWidgets('a mounted canvas holds up its lander, and a gone one '
      'puts it down', (tester) async {
    await pumpInk(tester);

    expect(
      landers.now,
      isNotNull,
      reason: 'a save with nothing published cannot land the pen at all',
    );

    await pumpInk(tester, mounted: false);

    expect(
      landers.now,
      isNull,
      reason: '⛔a lander left standing after the view goes would land a '
          'stroke into rasterizer tiles that have already gone back to the '
          'engine',
    );
  });

  // 🗣️F-419 (유저 2026-10-21: 「선 레이어 불투명도 100에서 80정도로
  // 내렷다가 100으로 올리니 안그려지기 시작했어」): a canvas built anew comes
  // up before the one it replaces goes down, and the old one's goodbye
  // must not take the new one's lander — or its shape — away.
  testWidgets('a canvas built anew in place of another leaves the new '
      'one\'s lander up', (tester) async {
    await pumpInk(tester);
    final first = landers.now;
    await pumpInk(tester, wrapped: true);

    expect(landers.now, isNotNull, reason: 'the old goodbye came last');
    expect(
      identical(landers.now, first),
      isFalse,
      reason: 'it is the new view\'s',
    );
  });

  // The shape tool's hand goes up and down beside the lander: the view
  // that came up last keeps it, and a gone view leaves none — a show
  // whose view is gone would lay a shape into tiles already given back.
  testWidgets('a canvas holds up its shape show the same way', (
    tester,
  ) async {
    await pumpInk(tester);
    final first = shapes.now;
    expect(first, isNotNull, reason: 'a mounted canvas shows the shape');

    await pumpInk(tester, wrapped: true);
    expect(shapes.now, isNotNull, reason: 'the old goodbye came last');
    expect(identical(shapes.now, first), isFalse);

    await pumpInk(tester, mounted: false);
    expect(shapes.now, isNull, reason: 'a gone canvas puts it down');
  });

  testWidgets('🚨★★★and the published lander really lands the stroke — the '
      'same landing a pen-up performs', (tester) async {
    await pumpInk(tester);
    final centre = tester.getCenter(find.byKey(const ValueKey<String>('ink')));

    // A pen that is still DOWN — the state pressing Ctrl+S catches.
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(centre);
    await tester.pump();
    await pen.moveBy(const Offset(20, 12));
    await tester.pump();

    expect(
      commits,
      isEmpty,
      reason: 'fixture premise: nothing has landed while the pen is down',
    );

    final landed = landers.now!();

    expect(landed, isTrue, reason: 'it had dabs to land');
    expect(
      commits,
      hasLength(1),
      reason: 'the stroke reached the cel through the ordinary commit — the '
          'save does not get a second path to the picture',
    );

    // And the pen-up that follows finds nothing left to do, rather than
    // committing the same dabs twice.
    await pen.up();
    await tester.pumpAndSettle();

    expect(
      commits,
      hasLength(1),
      reason: '⛔the landing cleared the input state, so the release is a '
          'no-op — two commits would be two undo entries for one line',
    );
  });

  testWidgets('⛔landing with no stroke in flight does NOTHING — not even '
      'the teardown', (tester) async {
    await pumpInk(tester);

    expect(landers.now!(), isFalse);
    expect(commits, isEmpty);
    expect(
      strokeActive,
      isEmpty,
      reason: '🚨THE GUARD IS WHAT THIS MEASURES. Without it the body runs '
          'anyway: no dabs, so it falls through to `endStrokeInput` and '
          '`resetOverlay` — announcing a stroke that ended when none began, '
          'and resetting an overlay the HOST may own. Every Ctrl+S with the '
          'pen up would do it, which is most of them',
    );
  });
}
