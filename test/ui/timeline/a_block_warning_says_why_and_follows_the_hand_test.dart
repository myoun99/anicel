import 'dart:collection';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart' show StoryboardTabHost;
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show extentAcross, extentAlong, offsetAlong;
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart'
    show TimelineBlockEdgeGrip;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show BlockMoveDragPreview;
import 'package:anicel/src/ui/timeline_tab_host.dart' show TimelineTabHost;

import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// F-495 (유저 2026-10-28): 「FI같은거 컷에 걸쳐있어서 위에 빨간줄
/// 생기는거 … 이유가 뭔지 모르겠으니 블록에 호버하면 툴팁 띄우도록. 그리고
/// 제대로 엣지 조작해서 컷 안에 넣으면 빨간줄 사라지는데, 컷 안에 넣고 나서
/// 손 떼야 빨간줄 사라짐. 우리 원칙은 뭐든 최대한 라이브로 보여주는거니까」.
///
/// ① The block says why under a hover anywhere on it — its red line only
/// shows it. ② The line follows the hand: a drag that brings the fade inside
/// its cut takes it off while the hand is still down, and the same drag
/// taken back out puts it back — on the cut's row and the conte's.
void main() {
  /// The span's whole cut view and the conte at this size: every frame of
  /// cut 1 on screen, where a hover can find it.
  const wide = Size(2400, 700);
  const tall = Size(1400, 2400);

  /// Cut 1 of two, open, its transition row holding an F.O inside it at 2
  /// and one at [crossingOf] that runs four frames past its end — refused
  /// and marked (D26).
  Future<void> fadesOnCutOne(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    session.transitions.updateTransitionInstructions(
      SplayTreeMap<int, InstructionEvent>.from({
        2: const InstructionEvent(instructionId: 'fo', length: 4),
        first.duration - 4: const InstructionEvent(
          instructionId: 'fo',
          length: 8,
        ),
      }),
    );
    session.selectCut(first.id);
    await tester.pumpAndSettle();
  }

  /// Where the crossing fade starts — on the track and, cut 1 standing at
  /// its frame 0, in the cut.
  int crossingOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.first.cuts.first.duration -
      4;

  String rowId(EditorSessionManager session) =>
      session.activeTrack.transitionLayer.id.value;

  String warning() => AppText.strings.tlTransitionCrossingWarning;

  Future<EditorSessionManager> theCutView(
    WidgetTester tester, {
    required bool xsheet,
  }) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      surface: xsheet ? tall : wide,
      orientation: xsheet
          ? TimelineOrientation.vertical
          : TimelineOrientation.horizontal,
    );
    await fadesOnCutOne(tester, session);
    return session;
  }

  Future<EditorSessionManager> theConte(WidgetTester tester) async {
    final session = await pumpStoryboardHost(
      tester,
      createDefaultProject(),
      surface: wide,
    );
    await fadesOnCutOne(tester, session);
    return session;
  }

  /// The test's one mouse, resting at [at] as long as a tooltip waits.
  TestGesture? mouse;
  Future<void> hoverAt(WidgetTester tester, Offset at) async {
    if (mouse == null) {
      final added = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await added.addPointer(location: Offset.zero);
      addTearDown(() async {
        await added.removePointer();
        mouse = null;
      });
      mouse = added;
    }
    await mouse!.moveTo(at);
    await tester.pump(const Duration(seconds: 2));
  }

  /// A point on [block] off the lines it meets: a quarter along it — the
  /// crossing fade straddles its cut's end line, the end's own grip — and
  /// halfway across, off its near edge, where its red line lies.
  Offset onTheBlock(
    WidgetTester tester,
    Finder block,
    Type host, {
    Axis axis = Axis.horizontal,
  }) {
    final rect = tester.getRect(block);
    final at =
        rect.topLeft +
        offsetAlong(
          axis,
          along: extentAlong(axis, rect.size) / 4,
          across: extentAcross(axis, rect.size) / 2,
        );
    expect(
      tester.getRect(find.byType(host)).contains(at),
      isTrue,
      reason: '⛔전제: the block is on screen',
    );
    return at;
  }

  /// The cut view's key namespace: the timeline's, or the X-sheet's.
  String surfaceOf({required bool xsheet}) => xsheet ? 'xsheet' : 'timeline';

  group('① the block says why under a hover anywhere on it', () {
    for (final xsheet in [false, true]) {
      testWidgets('on the cut\'s row${xsheet ? ' (X-sheet)' : ''}', (
        tester,
      ) async {
        final session = await theCutView(tester, xsheet: xsheet);
        final id = rowId(session);
        final crossing = crossingOf(session);
        final surface = surfaceOf(xsheet: xsheet);
        expect(
          find.byKey(
            ValueKey<String>('$surface-instruction-crossing-$id-$crossing'),
          ),
          findsOneWidget,
          reason: '⛔전제: the crossing fade wears the line',
        );

        await hoverAt(
          tester,
          onTheBlock(
            tester,
            find.byKey(ValueKey<String>('$surface-instruction-$id-2')),
            TimelineTabHost,
            axis: xsheet ? Axis.vertical : Axis.horizontal,
          ),
        );
        expect(find.text(warning()), findsNothing, reason: 'a clean fade');

        await hoverAt(
          tester,
          onTheBlock(
            tester,
            find.byKey(ValueKey<String>('$surface-instruction-$id-$crossing')),
            TimelineTabHost,
            axis: xsheet ? Axis.vertical : Axis.horizontal,
          ),
        );
        expect(find.text(warning()), findsOneWidget);
      });
    }

    testWidgets('and a hand held on the block keeps its press — held past a '
        'long press, then moved, it selects as on any block', (tester) async {
      final session = await theCutView(tester, xsheet: false);
      final block = find.byKey(
        ValueKey<String>(
          'timeline-instruction-${rowId(session)}-${crossingOf(session)}',
        ),
      );
      final cell = tester.getRect(block).width / 8;
      final hand = await tester.startGesture(
        onTheBlock(tester, block, TimelineTabHost),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(seconds: 1));
      await hand.moveBy(Offset(-cell * 3, 0));
      await tester.pump();
      await hand.up();
      await tester.pumpAndSettle();

      final picked = session.frameRangeSelection.value;
      expect(picked?.layerId, session.activeTrack.transitionLayer.id);
      expect(picked!.endIndexExclusive - picked.startIndex, greaterThan(1));
    });

    testWidgets('on the conte\'s row', (tester) async {
      final session = await theConte(tester);
      final id = rowId(session);
      final crossing = crossingOf(session);

      await hoverAt(
        tester,
        onTheBlock(
          tester,
          find.byKey(
            ValueKey<String>('storyboard-transition-paper-$id-$crossing'),
          ),
          StoryboardTabHost,
        ),
      );
      expect(find.text(warning()), findsOneWidget);
    });
  });

  group('② the line follows the hand', () {
    /// The end grip of the crossing fade on [host]'s row.
    Finder endGrip(EditorSessionManager session, Type host) => find.descendant(
      of: find.byType(host),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TimelineBlockEdgeGrip &&
            widget.layer.id == session.activeTrack.transitionLayer.id &&
            widget.edge == TimelineBlockEdge.end &&
            widget.blockStartIndex == crossingOf(session),
      ),
    );

    /// Drags the crossing fade's end five frames in, then back out, the
    /// hand down throughout — what [line] finds at each, and once let go.
    Future<void> inAndOut(
      WidgetTester tester,
      EditorSessionManager session, {
      required Type host,
      required Finder line,
      Axis axis = Axis.horizontal,
    }) async {
      final grip = endGrip(session, host);
      expect(grip, findsOneWidget, reason: '⛔전제');
      expect(line, findsOneWidget, reason: '⛔전제: it crosses');
      final cell = tester
          .widget<TimelineBlockEdgeGrip>(grip)
          .geometry
          .value
          .frameCellExtent;
      final step = offsetAlong(axis, along: -cell, across: 0);
      final hand = await tester.startGesture(tester.getCenter(grip));
      for (var frame = 0; frame < 5; frame += 1) {
        await hand.moveBy(step);
        await tester.pump();
      }
      expect(line, findsNothing, reason: 'inside, the hand still down');
      expect(
        session.activeTrack.transitionLayer.instructions[crossingOf(session)]!
            .length,
        8,
        reason: '⛔전제: nothing is written until the release',
      );

      for (var frame = 0; frame < 5; frame += 1) {
        await hand.moveBy(-step);
        await tester.pump();
      }
      expect(line, findsOneWidget, reason: 'out again, the hand still down');

      for (var frame = 0; frame < 5; frame += 1) {
        await hand.moveBy(step);
        await tester.pump();
      }
      await hand.up();
      await tester.pumpAndSettle();
      expect(line, findsNothing, reason: 'and let go inside');
    }

    for (final xsheet in [false, true]) {
      testWidgets('an edge dragged on the cut\'s row'
          '${xsheet ? ' (X-sheet)' : ''}', (tester) async {
        final session = await theCutView(tester, xsheet: xsheet);
        await inAndOut(
          tester,
          session,
          host: TimelineTabHost,
          axis: xsheet ? Axis.vertical : Axis.horizontal,
          line: find.byKey(
            ValueKey<String>(
              '${surfaceOf(xsheet: xsheet)}-instruction-crossing-'
              '${rowId(session)}-${crossingOf(session)}',
            ),
          ),
        );
      });
    }

    testWidgets('an edge dragged on the conte\'s row', (tester) async {
      final session = await theConte(tester);
      await inAndOut(
        tester,
        session,
        host: StoryboardTabHost,
        line: find.byKey(
          ValueKey<String>(
            'storyboard-instruction-crossing-${rowId(session)}-'
            '${crossingOf(session)}',
          ),
        ),
      );
    });

    test('a block moved — the cut\'s row and the conte\'s read the row the '
        'move shows', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.cutVerbs.createCut();
      final first = session.repository.requireProject().tracks.first.cuts.first;
      final crossing = first.duration - 4;
      session.transitions.updateTransitionInstructions(
        SplayTreeMap<int, InstructionEvent>.from({
          crossing: const InstructionEvent(instructionId: 'fo', length: 8),
        }),
      );
      session.selectCut(first.id);
      final transitions = session.transitions;
      final row = session.activeTrack.transitionLayer.id;
      String? inTheCut(int start) =>
          transitions.transitionCrossingWarningInCutAt(start);
      String? onTheConte(int start) =>
          transitions.transitionCrossingWarningAtGlobalKey(start);
      expect(inTheCut(crossing), warning(), reason: '⛔전제');
      expect(onTheConte(crossing), warning(), reason: '⛔전제');

      session.updateFrameRangeSelectionDrag(
        layerId: row,
        anchorIndex: crossing,
        headIndex: crossing + 3,
      );
      expect(session.rangeMove.beginFrameRangeMoveDrag(row), isTrue);
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: -4);
      final moved = crossing - 4;
      expect(
        (session.dragPreview.value! as BlockMoveDragPreview)
            .previewLayers[row]!
            .instructions
            .keys,
        [moved],
        reason: '⛔전제: the cut\'s row shows it moved',
      );
      expect(inTheCut(moved), isNull);
      expect(onTheConte(moved), isNull);

      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: 0);
      expect(inTheCut(crossing), warning());
      expect(onTheConte(crossing), warning());
      session.rangeMove.endFrameRangeMoveDrag();
    });
  });
}
