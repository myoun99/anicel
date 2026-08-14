import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';

/// 🚨UI 피드백 08-14 #11 — 「타임라인 **접은상태로 재생버튼누르면 타임라인이
/// 한번 펼쳐졌다가 다시 접힘**」.
///
/// The fold was the visible end of something much larger: the first frame of
/// playback DESTROYED EVERY [State] in the editor. The actuation gate
/// (T28-c) returned its bare child when idle and wrapped it in two widgets
/// when playing, so the subtree changed position in the element tree and
/// Flutter threw it away and inflated a new one. `_bottomDockCollapsed` went
/// back to its field initialiser with it — hence "펼쳐졌다", and the saved
/// layout restoring a moment later is "다시 접힘".
///
/// 🔬The control matters here: folded and left alone the panel stays folded
/// for seconds, so the fold is not drifting on its own. Pressing play is
/// what moves it.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Finder region() =>
      find.byKey(const ValueKey<String>('floating-bottom-region'));

  Future<void> fold(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressPlay(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Playback runs on a clock, so the teardown has to say stop — and the
  /// gate's own law is that the first actuation IS the stop (T28-c).
  Future<void> stopPlayback(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(region()));
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('the editor keeps its State when playback starts', (
    tester,
  ) async {
    await pumpApp(tester);
    final before = tester.state(find.byType(EditorWorkspace));

    await pressPlay(tester);

    expect(
      tester.state(find.byType(EditorWorkspace)),
      same(before),
      reason: 'the gate may change what it absorbs, never where the editor '
          'sits in the tree',
    );
    await stopPlayback(tester);
  });

  testWidgets('a folded timeline stays folded through play', (tester) async {
    await pumpApp(tester);
    await fold(tester);
    final folded = tester.getRect(region()).height;
    expect(find.byType(CollapsedRowOverlay), findsOneWidget);

    await pressPlay(tester);

    expect(
      tester.getRect(region()).height,
      closeTo(folded, 0.5),
      reason: 'pressing play is not a request to unfold the panel',
    );
    expect(
      find.byType(CollapsedRowOverlay),
      findsOneWidget,
      reason: 'and the folded row is still the thing on screen',
    );
    await stopPlayback(tester);
  });

  testWidgets('CONTROL: a fold left alone does not drift open', (
    tester,
  ) async {
    await pumpApp(tester);
    await fold(tester);
    final folded = tester.getRect(region()).height;

    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(tester.getRect(region()).height, closeTo(folded, 0.5));
  });
}
