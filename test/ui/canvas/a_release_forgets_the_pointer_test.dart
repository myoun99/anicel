import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

/// "This pointer is gone" is ONE piece of bookkeeping, and both endings of
/// a press owe it: a lift and a cancel each drop the contact buttons, the
/// touch census, the mapped hold and the alt-pick claim.
///
/// The census is the half a test can see, and it is the half that leaks
/// worst — a contact left standing there tells every other view that a
/// finger is still down, so nobody draws again for the life of the app.
/// Pinned before the two handlers were folded onto one release step.
void main() {
  const canvasSize = CanvasSize(width: 200, height: 200);

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

  Future<void> pumpInk(WidgetTester tester) async {
    final store = BrushFrameEditSessionStore(canvasSize: canvasSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: InteractiveBrushEditCanvasView(
                key: const ValueKey<String>('ink'),
                sessionState: store.getOrCreate(
                  const BrushFrameKey(
                    projectId: ProjectId('p'),
                    trackId: TrackId('t'),
                    cutId: CutId('c'),
                    layerId: LayerId('layer'),
                    frameId: FrameId('frame'),
                  ),
                ),
                layerId: const LayerId('layer'),
                frameId: const FrameId('frame'),
                inputSettings: BrushEditCanvasInputSettings.new,
                onSourceStrokeCommitted: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a LIFT forgets the pointer', (tester) async {
    await pumpInk(tester);
    final center = tester.getCenter(find.byKey(const ValueKey<String>('ink')));

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(center);
    await tester.pump();
    expect(CanvasTouchContacts.count, 1);

    await finger.up();
    await tester.pumpAndSettle();
    expect(CanvasTouchContacts.count, 0);
  });

  testWidgets('a CANCEL forgets it too — the same four steps, not a '
      'shorter list', (tester) async {
    await pumpInk(tester);
    final center = tester.getCenter(find.byKey(const ValueKey<String>('ink')));

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(center);
    await tester.pump();
    expect(CanvasTouchContacts.count, 1);

    await finger.cancel();
    await tester.pumpAndSettle();
    expect(
      CanvasTouchContacts.count,
      0,
      reason: 'a cancelled contact left in the census is a dead app',
    );
  });

  testWidgets('two fingers leave one at a time, whichever way each ends', (
    tester,
  ) async {
    await pumpInk(tester);
    final center = tester.getCenter(find.byKey(const ValueKey<String>('ink')));

    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(center);
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await second.down(center + const Offset(20, 0));
    await tester.pump();
    expect(CanvasTouchContacts.count, 2);

    await first.cancel();
    await tester.pump();
    expect(CanvasTouchContacts.count, 1, reason: 'only the one that ended');

    await second.up();
    await tester.pumpAndSettle();
    expect(CanvasTouchContacts.count, 0);
  });
}
