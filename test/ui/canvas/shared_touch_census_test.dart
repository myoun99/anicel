import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// R26 #5: the finger census is APP-WIDE. The timesheet mounts one ink
/// view per sheet window, so a two-finger pinch lands one contact on each
/// of two SIBLING views — counting per view let both of them draw a line
/// while the user was only navigating.
void main() {
  const canvasSize = CanvasSize(width: 200, height: 200);

  setUp(() {
    CanvasTouchContacts.reset();
    // Fingers must be allowed to draw at all, or the views bail earlier
    // and the test proves nothing: the one-finger slot IS the draw slot.
    AppInput.settings.value = const AppInputSettings(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  testWidgets('a finger on each of two sibling ink views draws NOTHING', (
    tester,
  ) async {
    final store = BrushFrameEditSessionStore(canvasSize: canvasSize);
    final commits = <BrushStrokeCommitData>[];

    Widget view(String id) => SizedBox(
      width: 200,
      height: 200,
      child: InteractiveBrushEditCanvasView(
        key: ValueKey<String>('ink-$id'),
        sessionState: store.getOrCreate(
          BrushFrameKey(
            projectId: const ProjectId('p'),
            trackId: const TrackId('t'),
            cutId: const CutId('c'),
            layerId: LayerId('layer-$id'),
            frameId: FrameId('frame-$id'),
          ),
        ),
        layerId: LayerId('layer-$id'),
        frameId: FrameId('frame-$id'),
        inputSettings: BrushEditCanvasInputSettings(),
        onSourceStrokeCommitted: commits.add,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Row(children: [view('a'), view('b')]),
          ),
        ),
      ),
    );

    final left = tester.getCenter(find.byKey(const ValueKey<String>('ink-a')));
    final right = tester.getCenter(find.byKey(const ValueKey<String>('ink-b')));

    final finger1 = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger1.down(left);
    final finger2 = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger2.down(right);
    await tester.pump();
    await finger1.moveBy(const Offset(40, 0));
    await finger2.moveBy(const Offset(40, 0));
    await tester.pump();
    await finger1.up();
    await finger2.up();
    await tester.pumpAndSettle();

    expect(
      commits,
      isEmpty,
      reason: 'two fingers = navigation, even across sibling views',
    );
    expect(
      CanvasTouchContacts.count,
      0,
      reason: 'every contact leaves the census on release',
    );
  });
}
