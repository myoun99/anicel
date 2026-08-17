import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/dialogs/se_instance_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'flyout_test_helpers.dart' show readCommandEnabled;

/// B8 (2026-08-17): 상단 버튼의 패널 스코프 — the toolbar's layer/frame/
/// shared/fx verbs dispatch AGAINST THE PANEL THEY ARE PRESSED IN, through
/// [ToolbarPanelContext]. Pressed in the storyboard, they act on the
/// standing row × the track-global playhead (「블록 종류 불문 같은 규칙」);
/// pressed in a timeline context, they keep the cut-local dispatch they
/// always had. Every press here is REAL INPUT on the mounted button.
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

  testWidgets('B8: EDIT on an SE-block cursor opens the SE dialog — the '
      'standing row dispatches, not the invisible active layer', (
    tester,
  ) async {
    final manager = await pumpStoryboard(tester);
    final se = manager.activeTrack.seLayers.first;
    final drawingTarget = manager.activeLayerId;

    // Author an entry on the S row (session setup), then put the DRAWING
    // target back on the cel row: if the button still opened anything, it
    // could only be through the standing row.
    manager.selectLayer(se.id);
    manager.selectFrameIndex(2);
    manager.createSeEntryAtCurrentFrame(name: 'boom', lengthFrames: 3);
    if (drawingTarget != null) {
      manager.selectLayer(drawingTarget);
    }

    // Stand on the S row (active track S1) with the cursor ON the block.
    manager.selectRow(LayerRowAddress(se.id));
    manager.selectGlobalFrame(3);
    await tester.pumpAndSettle();
    expect(manager.activeLayer?.kind, isNot(LayerKind.se),
        reason: 'the drawing target must NOT be the row being edited — '
            'that separation is what this test exists to cross');

    const key = ValueKey<String>('shared-edit-button');
    expect(await readCommandEnabled(tester, key), isTrue);
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();

    expect(
      find.byType(SeInstanceDialog),
      findsOneWidget,
      reason: 'the SE block under the cursor owns the press (B8)',
    );
    Navigator.of(tester.element(find.byType(SeInstanceDialog))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('B8: the layer ＋ adds an S row here — never the cut\'s '
      'animation stack', (tester) async {
    final manager = await pumpStoryboard(tester);
    final seBefore = manager.activeTrack.seLayers.length;
    final cutLayersBefore = manager.activeCutOrNull!.layers.length;

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
    );
    await tester.pumpAndSettle();

    expect(
      manager.activeTrack.seLayers.length,
      seBefore + 1,
      reason: 'S트랙 추가 — the rail\'s one addable kind',
    );
    expect(
      manager.activeCutOrNull!.layers.length,
      cutLayersBefore,
      reason: 'no animation layer slipped into the cut',
    );

    // The band menu says the same thing: only the S row lights up. V tracks
    // and the transition row cannot be added at all, and the cut-scoped
    // kinds are the other panel's stack ("disable" is the honest state).
    final panel = StoryboardToolbarPanelContext(manager);
    expect(panel.canAddLayerOfKind(LayerKind.se), isTrue);
    for (final kind in const [
      LayerKind.animation,
      LayerKind.storyboard,
      LayerKind.image,
      LayerKind.text,
      LayerKind.instruction,
      LayerKind.adjustment,
      LayerKind.folder,
      LayerKind.camera,
      LayerKind.transition,
    ]) {
      expect(
        panel.canAddLayerOfKind(kind),
        isFalse,
        reason: '$kind is not this rail\'s to add',
      );
    }
    expect(panel.canAddAttachedLayer, isFalse);
  });

  testWidgets('B8: comma 4 on a CUT block sets the cut length to 4 — '
      '「컷블록 위 4 = 컷길이 4」', (tester) async {
    final manager = await pumpStoryboard(tester);
    final cut = manager.activeCutOrNull!;
    expect(cut.duration, isNot(4), reason: 'the press must be what moves it');

    // Standing on the V row with the cursor inside the cut block.
    manager.selectRow(TrackRowAddress(manager.activeTrack.id));
    manager.selectGlobalFrame(0);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('set-comma-4-button')));
    await tester.pumpAndSettle();

    expect(manager.activeCutOrNull!.duration, 4);

    // One undo step, like the trailing-edge drag it rides.
    manager.undo();
    await tester.pumpAndSettle();
    expect(manager.activeCutOrNull!.duration, cut.duration);
  });

  testWidgets('B8: the SAME comma press, said of an SE block and of a '
      'transition span — no divergent rules per kind', (tester) async {
    final manager = await pumpStoryboard(tester);
    final se = manager.activeTrack.seLayers.first;
    final drawingTarget = manager.activeLayerId;

    manager.selectLayer(se.id);
    manager.selectFrameIndex(2);
    manager.createSeEntryAtCurrentFrame(name: 'boom', lengthFrames: 3);
    if (drawingTarget != null) {
      manager.selectLayer(drawingTarget);
    }

    // SE block: standing S row, cursor on the block → its exposure.
    manager.selectRow(LayerRowAddress(se.id));
    manager.selectGlobalFrame(3);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('set-comma-2-button')));
    await tester.pumpAndSettle();
    expect(
      manager.activeTrack.seLayers.first.timeline[2]!.length,
      2,
      reason: 'the SE block under the cursor took the pressed exposure',
    );

    // Transition span: standing the 🔀 row, cursor on the span → its length.
    manager.selectGlobalFrame(5);
    manager.createTransitionSpanAtPlayhead();
    final transition = manager.activeTrack.transitionLayer;
    manager.selectRow(LayerRowAddress(transition.id));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('set-comma-3-button')));
    await tester.pumpAndSettle();
    expect(
      manager.transitionSpanAt(5)!.value.length,
      3,
      reason: 'the span under the cursor took the pressed length',
    );
  });

  testWidgets('B8: the verbs with no storyboard subject grey out honestly '
      'even while the TIMELINE context would light them', (tester) async {
    final manager = await pumpStoryboard(tester);
    // Make the cut-local context rich: the playhead INSIDE a held cel
    // lights blank/mark/copy over on the timeline panel.
    manager.selectFrameIndex(0);
    manager.createDrawingAtCurrentFrame();
    manager.setCommaForSelectionOrCurrent(4);
    manager.selectFrameIndex(1);
    await tester.pumpAndSettle();
    expect(manager.canBlankExposureAtCurrentFrame, isTrue,
        reason: 'the SESSION would say yes — the refusal is the panel\'s');
    expect(manager.canCopyFrameAtCurrentFrame, isTrue);

    for (final keyValue in const [
      'blank-exposure-button',
      'toggle-mark-button',
      'shared-cut-button',
      'shared-copy-button',
      'shared-paste-independent-button',
      'shared-paste-linked-button',
    ]) {
      expect(
        await readCommandEnabled(tester, ValueKey<String>(keyValue)),
        isFalse,
        reason: '$keyValue addresses the cut-local playhead — the other '
            'panel\'s subject, so this panel must not light it',
      );
    }
  });

  testWidgets('regression pin: the SAME buttons under the TIMELINE context '
      'keep the cut-local dispatch, byte for byte', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ListenableBuilder(
            listenable: Listenable.merge([s, s.frameSeekCommitted]),
            builder: (context, _) => Row(
              children: [
                TimelineActionToolbar(
                  session: s,
                  panelContext: TimelineToolbarPanelContext(s),
                  onAddLayer: () {},
                  onRenameLayer: () {},
                  onDeleteLayer: () {},
                  onEditInstance: () {},
                  onCreateInstance: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ＋ makes an ANIMATION layer in the cut (⑥'s law, untouched by B8).
    final seBefore = s.activeTrack.seLayers.length;
    final cutLayersBefore = s.activeCutOrNull!.layers.length;
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
    );
    await tester.pumpAndSettle();
    expect(s.activeLayer!.kind, LayerKind.animation);
    expect(s.activeCutOrNull!.layers.length, cutLayersBefore + 1);
    expect(s.activeTrack.seLayers.length, seBefore, reason: 'no S row here');

    // Comma 3 retimes the ACTIVE block at the playhead — never the cut.
    final durationBefore = s.activeCutOrNull!.duration;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('set-comma-3-button')));
    await tester.pumpAndSettle();
    expect(s.activeLayer!.timeline[0]!.length, 3);
    expect(
      s.activeCutOrNull!.duration,
      durationBefore,
      reason: 'a timeline comma press must NOT become a cut trim',
    );
  });
}
