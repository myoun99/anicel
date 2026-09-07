import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
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
/// 🚨HOW THE ROW-LEVEL SCOPE IS PINNED, because two obvious ways do not work
/// and the next reader would try them:
///
/// * 🧪`find.descendant` from the row also finds the scope each swipe column
///   mounts, so deleting the row's left it green (measured, twice);
/// * 🧪pressing an eye or an fx proves nothing either — those ARE columns.
///
/// ⇒ The case below asks about a button that is in the row and is NOT a
/// column: the lane group's twirl, a bare [ControlPressClaim] standing beside
/// them. Deleting the row's scope turns it red, which is what makes it a
/// test rather than a hope.
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
    final before = session.onionSkin.isLayerOnionSkinEnabled(layerId);
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(ValueKey<String>('xsheet-layer-onion-$layerId')),
      ),
    );
    await tester.pump();

    expect(
      session.onionSkin.isLayerOnionSkinEnabled(layerId),
      !before,
      reason:
          '「레이어 쪽 버튼은 탭다운」 — a drag from here paints the whole '
          'column to match this row, so the row has to be holding its new '
          'value before the sweep starts reading it',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      session.onionSkin.isLayerOnionSkinEnabled(layerId),
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

  testWidgets('🚨a rail ROW puts its non-column buttons on the press too', (
    tester,
  ) async {
    // ⛔THE CASE THE SWIPE COLUMNS CANNOT ANSWER. A column mounts a scope of
    // its own, so pressing an eye or an fx proves nothing about the row —
    // 🧪measured twice: deleting the row's scope left every other case green.
    // What the row uniquely covers is the buttons that are NOT columns, and
    // the lane group's twirl is one: a bare [ControlPressClaim] sitting in
    // the row beside the columns.
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layerId = session.activeLayerId!;
    final laneToggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-$layerId'),
    );
    await tester.ensureVisible(laneToggle);
    await tester.pumpAndSettle();
    await tester.tap(laneToggle);
    await tester.pumpAndSettle();

    final twirl = find.byKey(
      ValueKey<String>('timeline-lane-group-toggle-$layerId-transform-group'),
    );
    expect(
      twirl,
      findsOneWidget,
      reason: 'the transform group lost its twirl — this measures nothing',
    );
    expect(
      find.ancestor(
        of: twirl,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is PressFireScope && widget.fireOn == PressFire.down,
        ),
      ),
      findsWidgets,
      reason:
          '유저: 「레이어 쪽 버튼은 탭다운」 — this one is not a swipe column, '
          'so only the ROW can put it on the press',
    );
  });
}
