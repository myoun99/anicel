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

/// 🚨★★★**THE CANVAS HANDS OUT THE ONE VERB A SAVE NEEDS, AND TAKES IT
/// BACK.** `ProjectFileDoor` lands the pen before it snapshots so that
/// pressing Ctrl+S mid-stroke puts that line in that file — but it can only
/// do that if a mounted canvas published a lander, and only safely if a
/// gone canvas published null.
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

  late StrokeLander? published;
  late List<BrushStrokeCommitData> commits;
  late List<bool> strokeActive;

  Future<void> pumpInk(WidgetTester tester, {bool mounted = true}) async {
    final store = BrushFrameEditSessionStore(canvasSize: canvasSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: mounted
                  ? InteractiveBrushEditCanvasView(
                      key: const ValueKey<String>('ink'),
                      sessionState: store.getOrCreate(key),
                      layerId: const LayerId('layer'),
                      frameId: const FrameId('frame'),
                      inputSettings: BrushEditCanvasInputSettings(),
                      onSourceStrokeCommitted: commits.add,
                      onStrokeLanderChanged: (lander) => published = lander,
                      onActiveStrokeChanged: strokeActive.add,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    published = null;
    commits = <BrushStrokeCommitData>[];
    strokeActive = <bool>[];
  });

  testWidgets('a mounted canvas publishes its lander, and a gone one '
      'publishes null', (tester) async {
    await pumpInk(tester);

    expect(
      published,
      isNotNull,
      reason: 'a save with nothing published cannot land the pen at all',
    );

    await pumpInk(tester, mounted: false);

    expect(
      published,
      isNull,
      reason: '⛔a lander left standing after the view goes would land a '
          'stroke into rasterizer tiles that have already gone back to the '
          'engine',
    );
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

    final landed = published!();

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

    expect(published!(), isFalse);
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
