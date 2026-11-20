import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settle_async.dart';

/// Lends both clocks till the move of [session]'s playhead lands, and
/// pumps the frame it lands in: a canvas that stands goes to a frame with
/// its picture (`StandsWithItsPicture`, the-standing-canvas-composes-a-
/// frame-twice-before-its-picture-Q1 = B), made on the engine in real time
/// — which a pumped clock does not give it ([settleAsync]).
Future<void> theMoveLands(
  WidgetTester tester,
  EditorSessionManager session,
) async {
  expect(
    await settleAsync(
      tester,
      () => session.standsWithItsPicture.waitsFor.value == null,
    ),
    isTrue,
    reason: 'the move of the playhead lands once its picture is there',
  );
  await tester.pump();
}
