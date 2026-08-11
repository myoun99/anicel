import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart'
    show InstructionEventDialog;
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart'
    show TimelineActionToolbar;
import 'package:anicel/src/ui/widgets/panel_flyout.dart' show PanelFlyoutItem;

/// The GLOBAL surface authors transitions. The transition row is track-owned
/// and its spans address the track's frame axis, so this panel — not the cut
/// timeline, which shows the same spans read-only — is where an O.L is made,
/// sized and named.
Future<StoryboardPanel> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
  return tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
}

StoryboardPanel _panel(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));

Track _track(WidgetTester tester) => _panel(tester).project.tracks.single;

/// Stand on the transition row at [frame].
///
/// 🚨It has to be THIS row and not the track row: the verb dispatches off the
/// rail's `selectedRow`, because the storyboard rail's standing row is separate
/// state from the cut's drawing target (user 2026-07-27) and the transition row
/// is invisible to anything reading `activeLayer`.
Future<void> _standOnTransitionRow(WidgetTester tester, int frame) async {
  _panel(tester).onRowFramePress!(
    LayerRowAddress(_track(tester).transitionLayer.id),
    frame,
  );
  await tester.pumpAndSettle();
}

/// Open the frame pill and press Edit Instance — the real path, not the
/// callback. Which button the rail grows is exactly what this round changed,
/// so the test drives the button.
Future<void> _tapEditInstance(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-frame-menu-button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('rename-frame-button')));
  await tester.pumpAndSettle();
}

/// Whether the pill offers the verb here, read from the open flyout.
Future<bool> _editInstanceEnabled(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-frame-menu-button')),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<PopupMenuItem<PanelFlyoutItem>>(
        find.byKey(const ValueKey<String>('rename-frame-button')),
      )
      .enabled;
}

Future<void> _closeFlyout(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

void main() {
  group('the transition row on the global rail', () {
    testWidgets('is there for every track, ABOVE the SE rows', (tester) async {
      await _openStoryboard(tester);
      final trackId = _track(tester).id.value;

      final label = find.byKey(
        ValueKey<String>('storyboard-transition-label-$trackId'),
      );
      final strip = find.byKey(
        ValueKey<String>('storyboard-transition-row-$trackId'),
      );
      expect(label, findsOneWidget);
      expect(strip, findsOneWidget);

      // Above the S rows on both columns — the rail and the strip mirror one
      // geometry, so a row that led one and trailed the other would drift the
      // selection bands off their rows.
      final seLabel = find.byKey(
        ValueKey<String>('storyboard-se-label-$trackId-1'),
      );
      expect(
        tester.getTopLeft(label).dy,
        lessThan(tester.getTopLeft(seLabel).dy),
      );
      expect(
        tester.getTopLeft(strip).dy,
        lessThan(tester.getTopLeft(find.byKey(
          const ValueKey<String>('storyboard-se-row-0-1'),
        )).dy),
      );
      // The two columns agree on the row's top, which is what keeps the rail
      // and the strips in lockstep.
      expect(tester.getTopLeft(label).dy, tester.getTopLeft(strip).dy);
    });

    testWidgets('is a layer row that SELECTS, like every other row', (
      tester,
    ) async {
      await _openStoryboard(tester);
      final layer = _track(tester).transitionLayer;
      expect(layer.kind, LayerKind.transition);

      _panel(tester).onRowFramePress!(LayerRowAddress(layer.id), 4);
      await tester.pumpAndSettle();

      expect(_panel(tester).selectedRow, LayerRowAddress(layer.id));
      // Owning no cuts, it lands the playhead and takes no cut active — the
      // SE rows' rule, and for the same reason.
      expect(_panel(tester).playheadFrame?.value, 4);
    });

    testWidgets('the row grows NO button of its own — Edit Instance is the '
        'whole verb', (tester) async {
      await _openStoryboard(tester);
      final trackId = _track(tester).id.value;

      // 유저 2026-08-11: 「프레임생성하는거 행에 버튼만들어서 넣은거같은데,
      // 그게아니라 인스턴스편집버튼으로 작동하도록. 삭제나 그런거 다 똑같이」.
      // The rail's `＋` was the predecessor and it is gone; a second entrance
      // is how "delete works from the dialog but not from the pill" starts.
      expect(
        find.byKey(ValueKey<String>('storyboard-transition-add-$trackId')),
        findsNothing,
      );
    });

    testWidgets('Edit Instance on an EMPTY frame makes a one-frame span at the '
        'playhead, and the strip draws it', (tester) async {
      await _openStoryboard(tester);
      await _standOnTransitionRow(tester, 6);
      await _tapEditInstance(tester);

      final spans = _track(tester).transitionLayer.instructions;
      expect(spans.keys, [6]);
      expect(spans[6]!.length, 1);
      // The paper the strip lays under the span — proof the row renders what
      // the track stores, on the global axis.
      expect(
        find.byKey(
          ValueKey<String>(
            'storyboard-transition-paper-'
            '${_track(tester).transitionLayer.id}-6',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the same verb EDITS where a span already covers the frame — '
        'it does not stand down and it does not silently make a second one', (
      tester,
    ) async {
      await _openStoryboard(tester);
      await _standOnTransitionRow(tester, 2);
      await _tapEditInstance(tester);
      expect(_track(tester).transitionLayer.instructions.keys, [2]);

      // Same frame again. The old `＋` went dark here because it could only
      // create; one verb opens the span instead, which is where its term is
      // repicked and where it is deleted.
      await _standOnTransitionRow(tester, 2);
      await _tapEditInstance(tester);
      expect(find.byType(InstructionEventDialog), findsOneWidget);
      expect(
        _track(tester).transitionLayer.instructions.keys,
        [2],
        reason: 'opening the editor must not add a span beside the one it edits',
      );
    });

    testWidgets('the verb stays LIVE right across the row — covered or empty, '
        'it has something to do', (tester) async {
      await _openStoryboard(tester);
      await _standOnTransitionRow(tester, 8);
      await _tapEditInstance(tester);
      expect(_track(tester).transitionLayer.instructions.keys, [8]);

      // ON the span it edits, one frame off it it creates. The entry that
      // went dark on a covered frame belonged to a create-only button.
      await _standOnTransitionRow(tester, 8);
      expect(await _editInstanceEnabled(tester), isTrue);
      await _closeFlyout(tester);

      await _standOnTransitionRow(tester, 9);
      expect(await _editInstanceEnabled(tester), isTrue);
      await _closeFlyout(tester);
    });
  });

  group('the playhead a transition is created at', () {
    /// Two cuts with a 4-frame gap before the second — the shape that tells
    /// "cut start + local index" apart from the track-global playhead.
    (EditorSessionManager, CutId, int) gappedSession() {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.createCut();
      final track = session.repository.requireProject().tracks.first;
      final second = track.cuts[1].id;
      session.repository.updateCutLeadingGap(
        cutId: second,
        leadingGapFrames: 4,
      );
      return (session, second, track.cuts[0].duration);
    }

    test('a GAP parking creates the span at the gap frame — a gap is a '
        'legitimate partner (the fade to black, and the のりしろ an animator '
        'gets by opening a gap in front of their only cut)', () {
      final (session, _, aEnd) = gappedSession();

      seekStoryboardGlobalFrame(session, aEnd + 2);
      expect(session.activeCutId, isNull, reason: 'a gap holds no cut');

      expect(session.canCreateTransitionSpanAtPlayhead, isTrue);
      session.createTransitionSpanAtPlayhead();

      expect(
        session.activeTrack.transitionLayer.instructions.keys,
        [aEnd + 2],
        reason: 'the span lands where the playhead is, not at cut-start + 0',
      );
    });

    test('a span on the SECOND cut lands at its GLOBAL frame, not its local '
        'one', () {
      final (session, second, aEnd) = gappedSession();
      session.selectCut(second);
      session.selectFrameIndex(1);

      session.createTransitionSpanAtPlayhead();

      expect(session.activeTrack.transitionLayer.instructions.keys, [
        aEnd + 4 + 1,
      ]);
    });
  });

  group('sizing a transition span', () {
    test('the END grip lengthens it; ONE undo restores the length', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.selectGlobalFrame(3);
      session.createTransitionSpanAtPlayhead();
      expect(session.activeTrack.transitionLayer.instructions[3]!.length, 1);

      expect(
        session.beginTransitionEdgeDrag(
          spanStartIndex: 3,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      session.updateTransitionEdgeDrag(11);
      // The in-flight form is on the preview channel, so the strip can follow
      // the hand while the repository still holds the committed span.
      expect(
        session.transitionEdgeDragPreview.value!.instructions[3]!.length,
        12,
      );
      expect(
        session.activeTrack.transitionLayer.instructions[3]!.length,
        1,
        reason: 'nothing is committed until release',
      );

      session.endTransitionEdgeDrag();
      expect(session.transitionEdgeDragPreview.value, isNull);
      expect(session.activeTrack.transitionLayer.instructions[3]!.length, 12);

      session.undo();
      expect(
        session.activeTrack.transitionLayer.instructions[3]!.length,
        1,
        reason: 'one release, one undo step',
      );
    });

    test('the START grip moves the start and holds the end', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.selectGlobalFrame(10);
      session.createTransitionSpanAtPlayhead();
      session.beginTransitionEdgeDrag(
        spanStartIndex: 10,
        edge: TimelineBlockEdge.end,
      );
      session.updateTransitionEdgeDrag(5);
      session.endTransitionEdgeDrag();
      expect(session.activeTrack.transitionLayer.instructions[10]!.length, 6);

      session.beginTransitionEdgeDrag(
        spanStartIndex: 10,
        edge: TimelineBlockEdge.start,
      );
      session.updateTransitionEdgeDrag(-4);
      session.endTransitionEdgeDrag();

      final spans = session.activeTrack.transitionLayer.instructions;
      expect(spans.keys, [6]);
      expect(
        spans[6]!.length,
        10,
        reason: 'the end stayed at 16 — the start is what moved',
      );
    });

    test('a cancelled drag commits nothing and drops the preview', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.selectGlobalFrame(1);
      session.createTransitionSpanAtPlayhead();

      session.beginTransitionEdgeDrag(
        spanStartIndex: 1,
        edge: TimelineBlockEdge.end,
      );
      session.updateTransitionEdgeDrag(20);
      session.cancelTransitionEdgeDrag();

      expect(session.transitionEdgeDragPreview.value, isNull);
      expect(session.activeTrack.transitionLayer.instructions[1]!.length, 1);
    });

    test('a grip on a frame no span starts at is refused', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      expect(
        session.beginTransitionEdgeDrag(
          spanStartIndex: 4,
          edge: TimelineBlockEdge.end,
        ),
        isFalse,
      );
    });
  });

  group('naming and removing a span', () {
    test('the term is replaced without moving or resizing the span', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.selectGlobalFrame(2);
      session.createTransitionSpanAtPlayhead();
      session.beginTransitionEdgeDrag(
        spanStartIndex: 2,
        edge: TimelineBlockEdge.end,
      );
      session.updateTransitionEdgeDrag(9);
      session.endTransitionEdgeDrag();

      final terms = session.transitionInstructionDefs;
      expect(terms.length, greaterThan(1));
      final other = terms.last;
      session.replaceTransitionEventAt(
        6,
        session.activeTrack.transitionLayer.instructions[2]!.copyWith(
          instructionId: other.id,
        ),
      );

      final spans = session.activeTrack.transitionLayer.instructions;
      expect(spans.keys, [2], reason: 'the start never moves');
      expect(spans[2]!.length, 10, reason: 'the grips own the length');
      expect(spans[2]!.instructionId, other.id);
    });

    test('the vocabulary offered is the 場面転換 terms only, and the editable '
        'set is untouched by that filter', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final filtered = session.transitionInstructionSet.defs;
      expect(filtered, isNotEmpty);
      expect(filtered.length, lessThan(session.cameraInstructionSet.defs.length));
      expect(
        session.transitionInstructionDefs.map((def) => def.id),
        filtered.map((def) => def.id),
      );
    });

    test('removing the covering span empties the row', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.selectGlobalFrame(5);
      session.createTransitionSpanAtPlayhead();
      expect(session.transitionSpanAt(5), isNotNull);

      session.removeTransitionSpanAt(5);
      expect(session.activeTrack.transitionLayer.instructions, isEmpty);

      session.undo();
      expect(session.activeTrack.transitionLayer.instructions.keys, [5]);
    });
  });

  /// ③ Create, edit and delete are ONE verb, reached from this panel.
  ///
  /// 🚨The dispatch had to be the RAIL's standing row, not `activeLayer`: the
  /// storyboard rail's row selection is separate state from the cut's drawing
  /// target (user 2026-07-27, and `selectRow` says so out loud), so the shared
  /// `editActiveInstance` cannot see this row at all. My first attempt routed
  /// through it with a flag and reached nothing — `activeLayer` was still the
  /// cut's animation layer.
  ///
  /// The cut view's half (it must still refuse) is in
  /// `transition_row_in_cut_test.dart`; between them the fork is pinned from
  /// both sides.
  group('the instance-edit verb on the global axis', () {
    /// The panel's own dispatch, read off the toolbar it mounts — so the test
    /// cannot pass while the host wires the callback to something else.
    void editInstance(WidgetTester tester) {
      final toolbar = tester.widget<TimelineActionToolbar>(
        find.byType(TimelineActionToolbar),
      );
      expect(
        toolbar.resolveCanEditInstance?.call(),
        isTrue,
        reason: 'the pill has to be ENABLED, or the wiring is unreachable',
      );
      toolbar.onEditInstance!();
    }

    testWidgets('opens the span dialog when a span covers the playhead', (
      tester,
    ) async {
      await _openStoryboard(tester);
      final session = tester
          .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
          .session;
      session.selectGlobalFrame(5);
      session.createTransitionSpanAtPlayhead();
      await tester.pumpAndSettle();
      session.selectRow(LayerRowAddress(session.activeTrack.transitionLayer.id));
      await tester.pumpAndSettle();

      editInstance(tester);
      await tester.pumpAndSettle();

      expect(find.byType(InstructionEventDialog), findsOneWidget);
      // The picker is the FILTERED vocabulary, and it offers no set editor —
      // committing a filtered copy would drop every camera-work term.
      final dialog = tester.widget<InstructionEventDialog>(
        find.byType(InstructionEventDialog),
      );
      expect(dialog.instructionSet.defs, session.transitionInstructionDefs);
      expect(dialog.onEditInstructionSet, isNull);
      // Dismiss through the route so the test leaves no dialog standing.
      Navigator.of(
        tester.element(find.byType(InstructionEventDialog)),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        session.activeTrack.transitionLayer.instructions.keys,
        [5],
        reason: 'cancelling changed nothing',
      );
    });

    testWidgets('CREATES on an empty frame instead of opening anything — one '
        'verb for both, so the rail needs no creation button of its own', (
      tester,
    ) async {
      await _openStoryboard(tester);
      final session = tester
          .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
          .session;
      session.selectGlobalFrame(7);
      session.selectRow(LayerRowAddress(session.activeTrack.transitionLayer.id));
      await tester.pumpAndSettle();
      expect(session.activeTrack.transitionLayer.instructions, isEmpty);
      // ⚠️The rail is standing here while `activeLayer` is NOT this row — the
      // separation that made the shared dispatch unusable.
      expect(session.selectedRow, isA<LayerRowAddress>());
      expect(session.activeLayer?.kind, isNot(LayerKind.transition));
      expect(session.editingGlobalFrame, 7);

      editInstance(tester);
      await tester.pumpAndSettle();

      expect(find.byType(InstructionEventDialog), findsNothing);
      expect(session.transitionSpanAt(7), isNotNull);
    });
  });
}
