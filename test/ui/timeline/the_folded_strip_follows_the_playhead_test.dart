import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';

/// 🚨THE FOLDED ROW'S FALLBACK STRIP FOLLOWS THE PLAYHEAD, A LAYER AT A TIME
/// (유저 2026-09-27, folded-row-playhead-during-playback-Q1: 「재생헤드나
/// 인덱스나 … 다 구조적으로 동기화」 — 「층 최대한 나눠서 굽는다던가」).
///
/// The strip — what a folded row draws when the row it stands on has no
/// widget of its own, the gap's track among them — drew its snapshot's
/// frame: a playing film or a scrub moved no snapshot, so its playhead and
/// the block it stood on stayed where the snapshot was taken. It follows
/// the channel it is handed now, and by layers: the playhead moves on a
/// tick layer of its own, and the blocks repaint only when it crosses into
/// another block.
void main() {
  // Runs over 2-4 and 9.
  const row = FlipHudRow(
    name: 'A',
    kind: LayerKind.animation,
    runs: [
      FlipHudRun(startIndex: 2, length: 3, label: '1'),
      FlipHudRun(startIndex: 9, length: 1, label: '2'),
    ],
  );

  Future<ValueNotifier<int?>> pumpStrip(WidgetTester tester) async {
    final playhead = ValueNotifier<int?>(2);
    final playing = ValueNotifier<int?>(null);
    final walk = ValueNotifier<int>(0);
    addTearDown(playhead.dispose);
    addTearDown(playing.dispose);
    addTearDown(walk.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: CollapsedRowOverlay.defaultHeight,
              child: CollapsedRowOverlay(
                snapshot: const FlipHudSnapshot(
                  rows: [row],
                  rowIndex: 0,
                  frameIndex: 0,
                  frameCount: 40,
                ),
                rail: null,
                naturalRailWidth: 100,
                pixelsPerFrame: 12,
                framesPerSecond: 24,
                follows: (
                  playhead: playhead,
                  playing: playing,
                  revealSelectionTick: walk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return playhead;
  }

  final blocks = find.byKey(const ValueKey<String>('collapsed-strip'));
  final head = find.byKey(const ValueKey<String>('collapsed-strip-playhead'));

  CustomPainter painterOf(WidgetTester tester, Finder paint) =>
      tester.widget<CustomPaint>(paint).painter!;

  testWidgets('a move repaints the playhead\'s layer, and never the blocks — '
      'not even into another block', (tester) async {
    final playhead = await pumpStrip(tester);
    final before = painterOf(tester, blocks);

    playhead.value = 3;
    expect(
      tester.renderObject(head).debugNeedsPaint,
      isTrue,
      reason: 'the playhead follows its channel — a move repaints it',
    );
    expect(
      tester.renderObject(blocks).debugNeedsPaint,
      isFalse,
      reason: 'a move inside the block repaints no block',
    );
    await tester.pump();

    // Where you stand is the playhead's column alone (F-212). ↩️The block
    // the playhead stood on was filled and outlined in its ink, so crossing
    // into another one rebuilt the blocks.
    playhead.value = 9;
    expect(tester.renderObject(blocks).debugNeedsPaint, isFalse);
    await tester.pump();
    expect(
      identical(painterOf(tester, blocks), before),
      isTrue,
      reason: 'nor rebuilds them',
    );
  });
}
