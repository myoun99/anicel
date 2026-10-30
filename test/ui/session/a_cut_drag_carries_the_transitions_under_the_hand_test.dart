import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/timeline_cut_end_handle.dart'
    show timelineDrawnEndPreviewFrameCount;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show timelineDragPreviewGlobalLayerFor;

import '../../helpers/storyboard_host.dart';

/// transitions-follow-a-cut-drag-live (F-495 매트릭스의 남은 칸, 10-29 —
/// 유저 F-495 「뭐든 최대한 라이브로」 · F-195 「끄는 중인 값은 미리보기
/// 채널 하나에 — 커밋과 같은 계산으로」): a cut's trim or move carries the
/// track's transition spans with the boundaries under the hand, the way its
/// release carries them (`TransitionsRideTheCuts`) — the conte's row, its
/// red line and the canvas's fade — and every answer that reads the spans
/// against the open cut reads them against the cut as the drag lays it.
void main() {
  /// Two cuts on the default track, the first open; its id and length.
  (EditorSessionManager, CutId, int) twoCuts() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    session.selectCut(first.id);
    return (session, first.id, first.duration);
  }

  /// The first cut's end, grabbed and held [by] frames along.
  void holdTheEnd(EditorSessionManager session, CutId cut, int by) {
    expect(
      session.edgeDrag.beginCutEdgeDrag(
        cutId: cut,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: '⛔전제',
    );
    session.edgeDrag.updateCutEdgeDrag(by);
  }

  /// [read] held mid-drag of the first cut's end [by] frames, then once
  /// the release has written it — the hand shows what the release leaves.
  void heldAsReleased<T>(
    EditorSessionManager session,
    CutId cut,
    int by,
    T Function() read, {
    T? before,
  }) {
    if (before != null) {
      expect(read(), before, reason: '⛔전제: before the drag');
    }
    holdTheEnd(session, cut, by);
    final held = read();
    session.edgeDrag.endCutEdgeDrag();
    expect(held, read());
    if (before != null) {
      expect(held, isNot(before), reason: '⛔전제: the drag changes it');
    }
  }

  test("🎯an O.L across the cut's end rides the end under the hand — on "
      "the track's axis, the row the release writes", () {
    final (session, first, length) = twoCuts();
    session.transitions.updateTransitionInstructions({
      length - 6: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    final row = session.activeTrack.transitionLayer.id;

    holdTheEnd(session, first, -3);
    final shown = timelineDragPreviewGlobalLayerFor(
      session.dragPreview.value,
      row,
    );
    expect(shown?.instructions.keys, [length - 9]);
    expect(session.transitions.activeTrackTransitionRowShown, same(shown));
    expect(
      session.activeTrack.transitionLayer.instructions.keys,
      [length - 6],
      reason: '⛔전제: nothing is written until the release',
    );

    session.edgeDrag.endCutEdgeDrag();
    expect(
      session.activeTrack.transitionLayer.instructions,
      shown!.instructions,
    );
  });

  test("an F.O the cut's end is pulled in over: the conte's red line stands "
      'while the hand is down, and goes as it lets the end back out', () {
    final (session, first, length) = twoCuts();
    final start = length - 6;
    session.transitions.updateTransitionInstructions({
      start: const InstructionEvent(instructionId: 'fo', length: 4),
    });
    String? line() =>
        session.transitions.transitionCrossingWarningAtGlobalKey(start);
    expect(line(), isNull, reason: '⛔전제: inside its cut');

    holdTheEnd(session, first, -4);
    expect(line(), AppText.strings.tlTransitionCrossingWarning);
    session.edgeDrag.updateCutEdgeDrag(0);
    expect(line(), isNull);
    session.edgeDrag.endCutEdgeDrag();
  });

  group('the canvas reads the spans against the cut as the drag lays it', () {
    test('the cut going out under the O.L thins where the release thins '
        'it', () {
      final (session, first, length) = twoCuts();
      session.transitions.updateTransitionInstructions({
        length - 6: const InstructionEvent(instructionId: 'ol', length: 12),
      });
      double fade() => session.opacityVerbs.activeCutEditingFadeOpacity(
        frameIndex: length - 5,
      );

      heldAsReleased(session, first, -3, fade, before: fade());
    });

    test('the cut coming in under it stands as it stood: the O.L rode the '
        'boundary its own frames start at', () {
      final (session, first, length) = twoCuts();
      session.transitions.updateTransitionInstructions({
        length - 6: const InstructionEvent(instructionId: 'ol', length: 12),
      });
      final second =
          session.repository.requireProject().tracks.first.cuts[1].id;
      session.selectCut(second);
      double fade() =>
          session.opacityVerbs.activeCutEditingFadeOpacity(frameIndex: 2);
      final before = fade();

      holdTheEnd(session, first, -3);
      expect(fade(), before);
      session.edgeDrag.endCutEdgeDrag();
      expect(fade(), before, reason: '⛔전제: so the release leaves it');
    });

    test('…and counts the のりしろ before it while the hand is down — its '
        'drawn end and the name across it', () {
      final (session, first, length) = twoCuts();
      session.transitions.updateTransitionInstructions({
        length - 6: const InstructionEvent(instructionId: 'ol', length: 12),
      });
      final second = session.repository.requireProject().tracks.first.cuts[1];
      session.selectCut(second.id);
      final span = session.activeCutSpan;

      holdTheEnd(session, first, -3);
      expect(span.activeCutDrawnFrameCount, second.duration + 6);
      expect(span.activeCutNoriShiroLabel, isNotEmpty);
      session.edgeDrag.endCutEdgeDrag();
    });

    test('an F.O pulled over drops its screen while the hand is down, as '
        'its release refuses it', () {
      final (session, first, length) = twoCuts();
      session.transitions.updateTransitionInstructions({
        length - 6: const InstructionEvent(instructionId: 'fo', length: 4),
      });
      int veils() => session.opacityVerbs
          .activeCutEditingVeils(frameIndex: length - 4)
          .length;

      heldAsReleased(session, first, -4, veils, before: veils());
    });

    test('…and the ruler stops naming it while the hand is down', () {
      final (session, first, length) = twoCuts();
      session.transitions.updateTransitionInstructions({
        length - 6: const InstructionEvent(instructionId: 'fo', length: 4),
      });
      String named() => session.activeCutSpan.activeCutNoriShiroLabel;

      heldAsReleased(session, first, -4, named, before: named());
    });

    test("the ruler's drawn end keeps the O.L's のりしろ past the end the "
        'hand holds', () {
      final (session, first, length) = twoCuts();
      session.transitions.updateTransitionInstructions({
        length - 6: const InstructionEvent(instructionId: 'ol', length: 12),
      });
      int drawnEnd() => timelineDrawnEndPreviewFrameCount(
        preview: session.dragPreview.value,
        cutId: first,
        playbackFrameCount: session.activeCutSpan.activeCutPlaybackFrameCount,
        drawnFrameCount: session.activeCutSpan.activeCutDrawnFrameCount,
      );

      heldAsReleased(session, first, -3, drawnEnd, before: drawnEnd());
    });
  });

  test("the cut view's line answers for the row it shows: a cut's drag "
      'leaves it the committed one, so a refused F.O keeps its line', () {
    final (session, first, length) = twoCuts();
    final second = session.repository.requireProject().tracks.first.cuts[1];
    final end = length + second.duration;
    session.transitions.updateTransitionInstructions({
      end - 2: const InstructionEvent(instructionId: 'fo', length: 4),
    });
    session.selectCut(second.id);
    final transitions = session.transitions;
    final shown =
        transitions.trackTransitionDisplayLayer.instructions.keys.single;
    String? line() => transitions.transitionCrossingWarningInCutAt(shown);
    expect(
      line(),
      AppText.strings.tlTransitionCrossingWarning,
      reason: "⛔전제: it crosses its cut's end",
    );

    holdTheEnd(session, first, -3);
    expect(
      transitions.trackTransitionDisplayLayer.instructions.keys.single,
      shown,
      reason: '⛔전제: the cut view shows the committed row',
    );
    expect(line(), AppText.strings.tlTransitionCrossingWarning);
    session.edgeDrag.endCutEdgeDrag();
  });

  testWidgets("the conte's transition block stands where the drag carries "
      'it before the release', (tester) async {
    final session = await pumpStoryboardHost(
      tester,
      createDefaultProject(),
      surface: const Size(2400, 700),
    );
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final first = session.repository.requireProject().tracks.first.cuts.first;
    session.transitions.updateTransitionInstructions({
      first.duration - 6: const InstructionEvent(
        instructionId: 'ol',
        length: 12,
      ),
    });
    await tester.pumpAndSettle();
    final id = session.activeTrack.transitionLayer.id.value;
    Finder blockAt(int start) =>
        find.byKey(ValueKey<String>('storyboard-transition-paper-$id-$start'));
    expect(blockAt(first.duration - 6), findsOneWidget, reason: '⛔전제');

    holdTheEnd(session, first.id, -3);
    await tester.pump();
    expect(blockAt(first.duration - 9), findsOneWidget);
    expect(blockAt(first.duration - 6), findsNothing);
    session.edgeDrag.endCutEdgeDrag();
    await tester.pumpAndSettle();
  });
}
