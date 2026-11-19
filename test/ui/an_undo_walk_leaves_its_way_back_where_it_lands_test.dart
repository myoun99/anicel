import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../helpers/a_move_lands.dart';
import '../helpers/draw_on_current_frame.dart';
import '../helpers/key_chords.dart';
import 'flyout_test_helpers.dart' show tapCommandButton;

/// Card F-624 ② (검증 11-20 02:37 · 03:08): 「크기 변경 뒤 Ctrl+Z → 눈금자
/// 클릭」을 되풀이하면 몇 번을 눌러도 안 돌아오고 다시하기 버튼만 켜진다.
///
/// An undo standing elsewhere walks to the edit first (I-41), and the walk
/// waits for its frame's picture — a canvas resize remakes every frame's.
/// The way back is the redo's once the walk LANDS: a walk the ruler took
/// over before then left one from where the user never went, the redo lit
/// with nothing moved. Driven as the hand drives it — the size window, the
/// ruler pressed, Ctrl+Z and Ctrl+Y. The same before F-624 landed (its
/// parent, 243311c25): it was never the many cuts' resize.
void main() {
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects
        .active;
  }

  Future<void> pumpPastTheWait(WidgetTester tester) async {
    for (var step = 0; step < 30; step += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The ruler pressed over the cut's first frame.
  Future<void> pressTheRuler(WidgetTester tester) async {
    final area = tester.getRect(
      find
          .byKey(const ValueKey<String>('timeline-frame-ruler-scrub-area'))
          .first,
    );
    await tester.tapAt(
      Offset(area.left + 3, area.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  }

  /// The cut drawn on its sixth frame and widened there through the size
  /// window, the ruler then pressed back to its first frame.
  Future<(EditorSessionManager, CanvasSize, CanvasSize)> resizedThenLeft(
    WidgetTester tester,
  ) async {
    final s = await pumpApp(tester);
    final before = s.requireActiveCut.canvasSize;
    s.selectFrameIndex(5);
    await tester.pump();
    drawOnCurrentFrame(s);
    await tester.pump();
    final wider = CanvasSize(width: before.width + 300, height: before.height);
    await tapCommandButton(
      tester,
      const ValueKey<String>('resize-cut-canvas-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '${wider.width}',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-confirm-button')),
    );
    await pumpPastTheWait(tester);
    expect(s.requireActiveCut.canvasSize, wider, reason: '⛔전제: resized');
    await pressTheRuler(tester);
    await theMoveLands(tester, s);
    expect(s.currentFrameIndex, 0, reason: '⛔전제: stood off the edit');
    return (s, before, wider);
  }

  testWidgets('🚨a walk the ruler took over before it landed leaves no way '
      'back, and the undo after it walks again', (tester) async {
    final (s, before, wider) = await resizedThenLeft(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(
      s.standsWithItsPicture.waitsFor.value,
      5,
      reason: '⛔전제: the walk waits for the edit\'s frame',
    );
    await pressTheRuler(tester);
    expect(s.standsWithItsPicture.waitsFor.value, isNull);
    expect(s.currentFrameIndex, 0, reason: 'the walk never landed');
    expect(
      s.historyManager.canRedo,
      isFalse,
      reason: 'nothing walked, so there is no way back to redo',
    );

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await theMoveLands(tester, s);
    expect(s.currentFrameIndex, 5, reason: 'this one walked there');
    expect(s.historyManager.redoCount, 1);
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await theMoveLands(tester, s);
    expect(s.requireActiveCut.canvasSize, before, reason: 'and then back');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a second walk to the same edit leaves one way back, which '
      'the redo after the edit\'s takes', (tester) async {
    final (s, before, wider) = await resizedThenLeft(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await theMoveLands(tester, s);
    expect(s.currentFrameIndex, 5, reason: '⛔전제: walked');
    await pressTheRuler(tester);
    await theMoveLands(tester, s);
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await theMoveLands(tester, s);
    expect(s.currentFrameIndex, 5, reason: '⛔전제: walked again (I-41)');
    expect(s.historyManager.redoCount, 1, reason: 'one way back, not two');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await theMoveLands(tester, s);
    expect(s.requireActiveCut.canvasSize, before);
    await pressCtrl(tester, LogicalKeyboardKey.keyY);
    await theMoveLands(tester, s);
    expect(s.requireActiveCut.canvasSize, wider);
    await pressCtrl(tester, LogicalKeyboardKey.keyY);
    await theMoveLands(tester, s);
    expect(s.currentFrameIndex, 0, reason: 'back where the last walk began');
    expect(s.historyManager.canRedo, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });
}
