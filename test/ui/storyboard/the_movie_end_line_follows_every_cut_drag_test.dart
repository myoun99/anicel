import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// 🚨F-119 (유저 2026-09-12): 「마지막에 있던 컷 블록을 앞으로 당기면 최종 영상
/// 엔드라인이 움직이면서 룰러랑 프레임영역이랑 어긋남 … 타임라인에도 같은
/// 현상 있는지 확인해서 법 하나로 통일」.
///
/// The misalignment on the RELEASE was F-95's and is pinned there. What was
/// left is the drag itself — 🧪measured before the fix, pulling the last cut
/// 20 frames forward: the blocks previewed an end at 68 while the strip's
/// end line, its grip and the ruler's line all stood at the committed 88
/// until the hand let go. The end lines read only a movie-end drag's
/// preview; a cut drag moves the movie's end just as surely.
///
/// ⛔Every drag that moves the last cut's end, and every end line: each is
/// read against the blocks the user is looking at, in the same frame.
void main() {
  const pixelsPerFrame = 24.0;

  Future<EditorSessionManager> openTwoCutsAtTheEnd(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final last = session.repository.requireProject().tracks.first.cuts.last;
    session.repository.updateCutLeadingGap(
      cutId: last.id,
      leadingGapFrames: 40,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: pixelsPerFrame,
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
    return session;
  }

  /// The frame every end line stands at, and the end of the blocks drawn.
  ({int blocksEnd, double strip, double grip, double ruler}) endsOnScreen(
    WidgetTester tester,
    EditorSessionManager session,
  ) {
    final track = session.repository.requireProject().tracks.first;
    final blocks =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    ValueKey<String>('storyboard-cut-blocks-${track.id.value}'),
                  ),
                )
                .painter!
            as StoryboardCutBlocksPainter;
    final cells = tester
        .getRect(
          find.byKey(
            ValueKey<String>('storyboard-track-timeline-area-${track.id.value}'),
          ),
        )
        .left;
    final rulerLeft = tester
        .getRect(find.byKey(const ValueKey<String>('storyboard-frame-ruler')))
        .left;
    double frameAt(String key, double origin) =>
        (tester.getRect(find.byKey(ValueKey<String>(key))).left - origin) /
        pixelsPerFrame;
    return (
      blocksEnd:
          blocks.entries
              .map((entry) => entry.endFrame)
              .reduce((a, b) => a > b ? a : b) +
          session.repository.requireProject().trailingFrames,
      strip: frameAt('storyboard-cut-end-line', cells),
      grip: frameAt('storyboard-cut-end-handle', cells),
      ruler: frameAt('timeline-cut-end-boundary-ruler', rulerLeft),
    );
  }

  void expectEveryLineOnTheBlocks(
    WidgetTester tester,
    EditorSessionManager session, {
    required int expected,
    required String when,
  }) {
    final ends = endsOnScreen(tester, session);
    expect(ends.blocksEnd, expected, reason: 'fixture ($when): the blocks');
    expect(ends.strip, moreOrLessEquals(expected.toDouble()), reason: when);
    expect(ends.grip, moreOrLessEquals(expected.toDouble()), reason: when);
    expect(ends.ruler, moreOrLessEquals(expected.toDouble()), reason: when);
  }

  testWidgets('pulling the last cut forward: every end line rides it '
      'mid-drag', (tester) async {
    final session = await openTwoCutsAtTheEnd(tester);
    final last = session.repository.requireProject().tracks.first.cuts.last;
    expectEveryLineOnTheBlocks(tester, session, expected: 88, when: 'rest');

    expect(session.cutMove.beginCutMoveDrag(last.id), isTrue);
    session.cutMove.updateCutMoveDrag(-20);
    await tester.pump();
    expectEveryLineOnTheBlocks(tester, session, expected: 68, when: '-20');

    session.cutMove.endCutMoveDrag();
    await tester.pumpAndSettle();
    expectEveryLineOnTheBlocks(tester, session, expected: 68, when: 'release');
  });

  testWidgets('trimming the last cut\'s end: every end line rides it '
      'mid-drag', (tester) async {
    final session = await openTwoCutsAtTheEnd(tester);
    final last = session.repository.requireProject().tracks.first.cuts.last;

    expect(
      session.edgeDrag.beginCutEdgeDrag(
        cutId: last.id,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    session.edgeDrag.updateCutEdgeDrag(-10);
    await tester.pump();
    expectEveryLineOnTheBlocks(tester, session, expected: 78, when: '-10');
    session.edgeDrag.cancelCutEdgeDrag();
    await tester.pump();
    expectEveryLineOnTheBlocks(tester, session, expected: 88, when: 'cancel');
  });
}
