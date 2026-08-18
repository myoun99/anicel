import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
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

  testWidgets('D28: with a storyboard layer on the cut, the comma press '
      'retimes the PANEL under the cursor — the ripple moves the later '
      'panels, never crushes the cut', (tester) async {
    final manager = await pumpStoryboard(tester);
    // Give the active cut a storyboard layer (born covering the cut) and
    // divide it: panels [0,3) and [3,duration).
    manager.addLayerOfKind(LayerKind.storyboard);
    final cutBefore = manager.activeCutOrNull!;
    manager.selectRow(TrackRowAddress(manager.activeTrack.id));
    manager.selectGlobalFrame(3);
    await tester.pumpAndSettle();
    manager.createStoryboardPanelAtCursor();
    await tester.pumpAndSettle();

    // Comma 4 on the FIRST panel: the panel takes length 4 and the later
    // panel RIPPLES (+1) — the old law (「컷블록 위 4 = 컷길이 4」) would
    // have crushed the whole cut to 4 instead.
    manager.selectGlobalFrame(1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('set-comma-4-button')));
    await tester.pumpAndSettle();

    final rowAfter = manager.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.kind == LayerKind.storyboard,
    );
    expect(rowAfter.timeline.keys.toList(), [0, 4]);
    expect(rowAfter.timeline[0]!.length, 4);
    expect(
      manager.activeCutOrNull!.duration,
      cutBefore.duration + 1,
      reason: 'the ripple pushes the cut end with the last panel '
          '(feedback #9) — the cut was NOT retimed to 4',
    );

    // One undo restores the whole ride.
    manager.undo();
    await tester.pumpAndSettle();
    expect(manager.activeCutOrNull!.duration, cutBefore.duration);
  });

  testWidgets('D28: the frame ＋ DIVIDES the panel under the cursor, and '
      'refuses at an existing division start', (tester) async {
    final manager = await pumpStoryboard(tester);
    manager.addLayerOfKind(LayerKind.storyboard);
    manager.selectRow(TrackRowAddress(manager.activeTrack.id));
    manager.selectGlobalFrame(0);
    await tester.pumpAndSettle();

    final panel = StoryboardToolbarPanelContext(manager);
    expect(
      panel.canCreateInstance,
      isFalse,
      reason: 'the cursor sits ON the panel\'s division start — nothing '
          'to divide (T25: a lit ＋ must have a working press)',
    );

    manager.selectGlobalFrame(3);
    await tester.pumpAndSettle();
    expect(panel.canCreateInstance, isTrue);
    manager.createStoryboardPanelAtCursor();
    await tester.pumpAndSettle();

    final row = manager.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.kind == LayerKind.storyboard,
    );
    expect(
      row.timeline.keys.toList(),
      [0, 3],
      reason: 'the covering panel divided at the cursor',
    );
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

  Future<void> pressSelectRowSpan(WidgetTester tester) async {
    final menu = find.byKey(
      const ValueKey<String>('timeline-frame-menu-button'),
    );
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('select-row-span-button')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('D40: whole-row select on the V row selects the row\'s whole '
      'cut span — 「컷블록도 동일 작동」', (tester) async {
    final manager = await pumpStoryboard(tester);
    manager.selectRow(TrackRowAddress(manager.activeTrack.id));
    await tester.pumpAndSettle();

    await pressSelectRowSpan(tester);

    final selection = manager.trackFrameRangeSelection.value!;
    expect(selection.trackId, manager.activeTrack.id);
    expect(selection.startFrame, 0);
    expect(selection.endFrameExclusive, manager.activeCutOrNull!.duration);
    expect(
      manager.storyboardSelectedCutIds,
      [manager.activeCutOrNull!.id],
      reason: 'the whole cut span reads back as every cut selected',
    );
  });

  testWidgets('D40: whole-row select on an S row takes its first authored '
      'frame through its last', (tester) async {
    final manager = await pumpStoryboard(tester);
    final se = manager.activeTrack.seLayers.first;
    final drawingTarget = manager.activeLayerId;

    // An EMPTY row has no span: the gate must refuse rather than light a
    // dead press (T25's defect).
    manager.selectRow(LayerRowAddress(se.id));
    expect(StoryboardToolbarPanelContext(manager).canSelectRowSpan, isFalse);

    manager.selectLayer(se.id);
    manager.selectFrameIndex(2);
    manager.createSeEntryAtCurrentFrame(name: 'boom', lengthFrames: 3);
    if (drawingTarget != null) {
      manager.selectLayer(drawingTarget);
    }
    manager.selectRow(LayerRowAddress(se.id));
    await tester.pumpAndSettle();

    await pressSelectRowSpan(tester);

    final selection = manager.trackFrameRangeSelection.value!;
    expect(selection.startFrame, 2);
    expect(selection.endFrameExclusive, 5);
    expect(selection.anchorRow, LayerRowAddress(se.id));
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

    // D40 under the TIMELINE context: the press selects the active row's
    // first authored cell through its last, in the cut-local selection.
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final frameMenu = find.byKey(
      const ValueKey<String>('timeline-frame-menu-button'),
    );
    await tester.ensureVisible(frameMenu);
    await tester.pumpAndSettle();
    await tester.tap(frameMenu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('select-row-span-button')),
    );
    await tester.pumpAndSettle();
    final selection = s.frameRangeSelection.value!;
    expect(selection.layerId, s.activeLayerId);
    expect(selection.startIndex, 0);
    expect(selection.endIndexExclusive, 4);
    expect(s.trackFrameRangeSelection.value, isNull);

    // D40 on an INSTRUCTION row: the chips live in layer.instructions, not
    // the timeline — the resolver reads the SAME lanes the range snap does,
    // so a row a drag can select on, the button can select too (T25).
    if (!s.activeCutOrNull!.layers.any(
      (layer) => layer.kind == LayerKind.instruction,
    )) {
      s.addLayerOfKind(LayerKind.instruction);
    }
    final instruction = s.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.kind == LayerKind.instruction,
    );
    s.updateLayerInstructions(instruction.id, const {
      6: InstructionEvent(instructionId: 'pan', length: 3),
    });
    s.selectLayer(instruction.id);
    await tester.pumpAndSettle();
    await tester.tap(frameMenu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('select-row-span-button')),
    );
    await tester.pumpAndSettle();
    final chipSpan = s.frameRangeSelection.value!;
    expect(chipSpan.layerId, instruction.id);
    expect(chipSpan.startIndex, 6);
    expect(chipSpan.endIndexExclusive, 9);
  });
}
