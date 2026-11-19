import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// 🚨A PEN GOING DOWN ON A CANVAS ASKS ITS STORE FOR THE BYTES ITS CEL'S
/// EDIT WILL NEED (`BrushFrameStore.bringBytesAhead`) — as it goes down,
/// so they are read off the UI thread while the stroke is drawn, where the
/// stroke's landing would read the cel's file on it (card
/// `cel-originals-are-held-twice-in-ram-and-on-the-gpu` ②(3)).
///
/// What the store then does is the store's own pins'
/// (`test/services/a_use_of_a_cel_kept_in_the_file_takes_its_shell_test.dart`);
/// here the pen is real and the panel is the one every canvas is — the
/// main one, a sheet's — so the asking is every surface's.
void main() {
  testWidgets('🚨a pen going down asks for the bytes of the cel it draws '
      'on — once a stroke, and before the stroke lands', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final store = _StoreSayingWhatWasAsked();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: frameKeys.first,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: BrushCanvasFixture.canvasSize,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.asked, isEmpty, reason: '⛔premise: none asked at rest');

    final pen = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(60, 60)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();

    expect(store.asked, [coordinator.activeFrameKey]);

    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.up();
    await tester.pumpAndSettle();

    expect(
      store.bakedSurfaceOrNull(coordinator.activeFrameKey),
      isNotNull,
      reason: '⛔premise: the stroke landed',
    );
    expect(store.asked, [coordinator.activeFrameKey], reason: 'once a stroke');
  });
}

/// A store that says which cels' bytes were asked ahead.
class _StoreSayingWhatWasAsked extends BrushFrameStore {
  final List<BrushFrameKey> asked = [];

  @override
  Future<void> bringBytesAhead(BrushFrameKey key) {
    asked.add(key);
    return super.bringBytesAhead(key);
  }
}
