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

  testWidgets('a move repaints the playhead\'s layer, and the blocks only '
      'when it crosses into another block', (tester) async {
    final playhead = await pumpStrip(tester);
    final standingOnTwo = painterOf(tester, blocks);

    // Inside the block it stands on: the playhead's layer, and nothing of
    // the blocks.
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
    expect(
      identical(painterOf(tester, blocks), standingOnTwo),
      isTrue,
      reason: 'nor rebuilds them',
    );

    // The block it stands on is the one in the playhead's ink — the one
    // under the channel, not under the snapshot's frame (0, between blocks).
    final ink = Theme.of(tester.element(blocks)).colorScheme.primary;
    List<double> solid() {
      final strokes = _Strokes(ink);
      painterOf(tester, blocks).paint(strokes, tester.getSize(blocks));
      return strokes.solid;
    }

    expect(solid(), [2 * 12 + 1], reason: 'standing on the block at 2');
    playhead.value = 9;
    await tester.pump();
    expect(
      solid(),
      [9 * 12 + 1],
      reason: '🚨the block the playhead crossed into is the one it stands on '
          '— the strip drew its snapshot\'s frame',
    );
    playhead.value = 7;
    await tester.pump();
    expect(solid(), isEmpty, reason: 'between blocks, none is');
  });
}

/// The blocks' outlines as the strip strokes them: the left edge of each
/// stroked in [standing] ink — the block the playhead stands on.
class _Strokes implements Canvas {
  _Strokes(this.standing);

  final Color standing;
  final solid = <double>[];
  final _saved = <double>[];
  var _dx = 0.0;

  @override
  void save() => _saved.add(_dx);

  @override
  void restore() => _dx = _saved.removeLast();

  @override
  void translate(double dx, double dy) => _dx += dx;

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.style == PaintingStyle.stroke &&
        paint.color.toARGB32() == standing.toARGB32()) {
      solid.add(rrect.left + _dx);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
