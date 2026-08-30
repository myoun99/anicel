import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨★★★THE RULE, PINNED ON REAL WIDGETS (유저 확정 2026-08-30):
///
/// > 「**레이어 쪽 버튼은 탭다운, 헤더쪽은 손떼면**으로 충분할거같은데
/// > 맞지? 규칙 단순명쾌하게 정리했으면 하는데」
///
/// ⛔A SCOPE IS EASY TO MOUNT IN THE WRONG PLACE, and nothing else would say
/// so: `PressFireScope` changes only WHEN a callback runs, so a rail that
/// lost it still works, still claims, still refuses to scroll — it just acts
/// late. That is exactly the bug 유저 reported about this very strip on
/// 2026-08-24 (F-26): 「레이어 탭다운이 아니라 손을 떼야 액티브레이어 …
/// 통일화 미스가 또 여기서 발견됐네?」.
///
/// So this asks the only question that catches it: **had it already happened
/// before the finger came up?**
///
/// ⚠️WHAT THIS DOES NOT COVER, so nobody reads it as more than it is: the
/// ROW-level `PressFireScope` mounts (`TimelineLayerControlsRow`, the lane
/// rows, the x-sheet's layer strip) are not isolated by any test here. They
/// exist for the buttons in a row that are NOT swipe columns — the fold
/// twirls, the lane navigators — and every attempt to pin them measured the
/// COLUMN's own scope instead:
///
/// * 🧪`find.descendant` from the row also finds the scope each swipe column
///   mounts, so deleting the row's left it green (measured, twice);
/// * `find.ancestor` from a column would isolate it, but no
///   `RailSwipeColumnPointer` descends from the row widget in this fixture —
///   the rail builds the columns and hands them in.
///
/// ⇒ The mechanism is proven (`a_button_still_fires_when_the_hand_shakes`),
/// and a rail button acting on the press is proven below. That a row's
/// NON-column buttons join it is construction, not coverage. 🔜The honest
/// way to close it is a fixture with a folded group in it.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  Widget host(EditorSessionManager session) => MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => TimelineTabHost(
          session: session,
          orientation: TimelineOrientation.vertical,
          onOrientationChanged: (_) {},
          pixelsPerFrame: 24,
          onPixelsPerFrameChanged: (_) {},
          showSeconds: false,
          onShowSecondsChanged: (_) {},
        ),
      ),
    ),
  );

  testWidgets('a LAYER-side button has already acted by the time it is '
      'released', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(host(session));
    await tester.pumpAndSettle();

    final layerId = session.activeLayerId!;
    final before = session.isLayerOnionSkinEnabled(layerId);
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(ValueKey<String>('xsheet-layer-onion-$layerId')),
      ),
    );
    await tester.pump();

    expect(
      session.isLayerOnionSkinEnabled(layerId),
      !before,
      reason:
          '「레이어 쪽 버튼은 탭다운」 — a drag from here paints the whole '
          'column to match this row, so the row has to be holding its new '
          'value before the sweep starts reading it',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      session.isLayerOnionSkinEnabled(layerId),
      !before,
      reason: '⛔and exactly once — the release must not toggle it back',
    );
  });

  testWidgets('a HEADER button waits for the release', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(host(session));
    await tester.pumpAndSettle();

    // The legend's own flyout: pressing it opens a menu, which is a thing
    // the tree can be asked about without reaching into the session.
    final trigger = find.byKey(const ValueKey<String>('legend-sections'));
    expect(trigger, findsOneWidget, reason: 'the legend lost its flyout');
    final entry = find.byKey(const ValueKey<String>('legend-section-se'));
    expect(entry, findsNothing, reason: 'nothing is open yet');

    final gesture = await tester.startGesture(tester.getCenter(trigger));
    await tester.pumpAndSettle();
    expect(
      entry,
      findsNothing,
      reason:
          '「헤더쪽은 손떼면」 — a header button that fired on the way down '
          'would leave no way to change your mind',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(entry, findsOneWidget, reason: 'and the release opens it');
  });
}
