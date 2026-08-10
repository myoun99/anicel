import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 유저 확정 (2026-08-10): 스토리보드 레이어의 프레임을 조절해야 하고,
/// 레이어도 만들고 지워야 한다 — so the storyboard mounts the SAME four
/// pills the timeline does, from the same widget rather than a parallel copy.
///
/// The one thing it cannot serve is `Edit Instance`, whose kind-dispatch
/// still lives in the timeline's host. That is passed as null and the entry
/// greys out; this file pins BOTH halves, because "the pills are there" and
/// "the one it cannot do says so" are the two ways this can regress.
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

  testWidgets('layer make/delete are here — and delete is OUTSIDE the menu', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-delete-layer-button')),
      findsOneWidget,
    );
  });

  testWidgets('Edit Instance greys out, because this host cannot serve it', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-frame-menu-button')),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey<String>('rename-frame-button'));
    expect(entry, findsOneWidget, reason: 'the entry is present…');
    expect(
      tester.widget<PopupMenuItem<PanelFlyoutItem>>(entry).enabled,
      isFalse,
      reason: '…and disabled rather than offering a dead command',
    );
  });
}
