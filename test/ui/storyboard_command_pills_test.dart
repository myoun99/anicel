import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/timeline_shift_buttons.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 유저 확정 (2026-08-10): 스토리보드 레이어의 프레임을 조절해야 하고,
/// 레이어도 만들고 지워야 한다 — so the storyboard mounts the SAME four
/// pills the timeline does, from the same widget rather than a parallel copy.
///
/// `Edit Instance` is included: its kind-dispatch used to be private to the
/// timeline's host, so the entry shipped greyed out for exactly one commit.
/// It is [instance_editor_commands.dart] now and both panels call it — the
/// last test here opens the editor for real, because "the entry is enabled"
/// and "the entry does something" fail apart.
void main() {
  Future<EditorSessionManager> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.frameSeekCommitted]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  testWidgets('the storyboard mounts the timeline\'s own action toolbar', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    expect(find.byType(TimelineActionToolbar), findsOneWidget);

    // The four name cells — 컷 · 레이어 · 프레임 · FX.
    for (final keyValue in [
      'cut-menu-button',
      'timeline-layer-menu-button',
      'timeline-frame-menu-button',
      'timeline-effects-button',
    ]) {
      expect(
        find.byKey(ValueKey<String>(keyValue)),
        findsOneWidget,
        reason: '$keyValue must be on the storyboard bar too',
      );
    }
  });

  testWidgets('the frame verbs are here — this is what 프레임 조절 means', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    for (final keyValue in [
      'new-frame-button',
      'blank-exposure-button',
      'toggle-mark-button',
      'set-comma-1-button',
      'set-comma-n-button',
    ]) {
      expect(find.byKey(ValueKey<String>(keyValue)), findsOneWidget);
    }
  });

  testWidgets('layer make is here, and the delete is the SHARED one', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
      findsOneWidget,
    );
    // ⑰/F: this panel mounts the same pills, so it inherited the same fold —
    // the layer's own delete button is gone and the one that asks what is
    // selected stands in the shared pill.
    expect(
      find.byKey(const ValueKey<String>('timeline-delete-layer-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('shared-delete-button')),
      findsOneWidget,
    );
  });

  testWidgets('Edit Instance is LIVE here — the dispatch is a free function', (
    tester,
  ) async {
    // It shipped greyed out for one commit, because the kind-dispatch lived
    // in the timeline's host and there was no way to reach it from here.
    // Now it is [instance_editor_commands.dart] and both panels call it.
    final manager = await pumpStoryboard(tester);
    // A drawing row at a named cell is the plainest thing the dispatch can
    // open — the frame-rename branch.
    manager.selectFrameIndex(0);
    manager.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-frame-menu-button')),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey<String>('rename-frame-button'));
    expect(entry, findsOneWidget);
    expect(
      tester.widget<PopupMenuItem<PanelFlyoutItem>>(entry).enabled,
      isTrue,
      reason: 'the storyboard can serve Edit Instance now',
    );

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      find.byType(TextField),
      findsWidgets,
      reason: 'and it actually opens the editor rather than doing nothing',
    );
  });

  testWidgets('push/pull is on the bar ONCE, inside the frame pill, and still '
      'asks as this rail', (tester) async {
    final manager = await pumpStoryboard(tester);

    // It used to be mounted a SECOND time as a loose pair beside the bar,
    // because the frame pill did not exist here yet and a frame-axis shove
    // had no noun to sit under. The pill arrived; two of them is one too many.
    final pair = find.byType(TimelineShiftButtons);
    expect(pair, findsOneWidget);
    expect(
      tester.getTopLeft(pair).dx,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('timeline-frame-menu-button')),
            )
            .dx,
      ),
      reason: 'inside the FRAME pill, after its name cell',
    );

    // 🚨And the surviving pair kept what the loose one was carrying: with
    // nothing selected the shove aims at the row THIS rail stands on, which on
    // the storyboard is separate state from the drawing target. A pair falling
    // back to the session's active layer would shove the wrong row.
    final transition = manager.activeTrack.transitionLayer.id;
    manager.selectRow(LayerRowAddress(transition));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TimelineShiftButtons>(pair).currentRow,
      LayerRowAddress(transition),
    );
  });
}
