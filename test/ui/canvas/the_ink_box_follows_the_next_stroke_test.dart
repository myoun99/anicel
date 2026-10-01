import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart' show visibleCanvasPoint;

/// The transform box frames the layer's INK, and the scan behind it is
/// memoized on the cel's surface instance — so the memo has to let go the
/// moment the cel changes. A second stroke on the same cel is that change:
/// same layer, same frame, more ink. (Pinned when the read moved into the
/// render caches, the session-state audit's twentieth family, 2026-09-29 —
/// a memo that kept its first answer passed every test there was.)
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  testWidgets('a second stroke on the same cel grows the ink box', (
    tester,
  ) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final layerId = session.activeLayerId!;
    Layer layer() => session.activeCutOrNull!.layers.firstWhere(
      (candidate) => candidate.id == layerId,
    );

    Future<void> strokeFrom(Offset start) async {
      final press = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await press.moveBy(const Offset(30, 0));
      await tester.pump();
      await press.moveBy(const Offset(30, 0));
      await tester.pump();
      await press.up();
      await tester.pumpAndSettle();
    }

    await strokeFrom(visibleCanvasPoint(tester, offset: const Offset(-150, 0)));
    final first = session.renderCaches.layerContentBoundsAt(layer(), 0);
    expect(first, isNotNull, reason: '⛔premise: the first stroke landed');

    await strokeFrom(visibleCanvasPoint(tester, offset: const Offset(100, 0)));
    final second = session.renderCaches.layerContentBoundsAt(layer(), 0);

    expect(second, isNotNull);
    expect(
      second!.rightExclusive,
      greaterThan(first!.rightExclusive),
      reason: 'the box takes in the ink the second stroke laid down',
    );
    expect(second.left, first.left, reason: 'and keeps what was there');

    session.playbackRig.prerenderScheduler.cancel();
  });
}
