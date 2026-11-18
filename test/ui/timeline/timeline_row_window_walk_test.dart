import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/timeline_row_edges.dart';
import 'package:anicel/src/ui/timeline/timeline_row_window_walk.dart';
import 'package:anicel/src/ui/timeline/timeline_visible_range.dart';

/// The rows' window walks to where the view stands a unit a frame after a
/// move whose rows stand laid, and is laid whole in the frame of a move
/// that shows an unlaid row.
///
/// 🗣️a-timeline-wheel-notch-lays-out-the-rail-Q2 = 1 (유저 2026-11-18,
/// 「칸 뒤 쉬는 프레임에 짓기」).
void main() {
  const rowExtent = 28.0;
  const viewport = 280.0;

  late TimelineRowEdges edges;
  late double offset;
  late int relays;
  late TimelineRowWindowWalk walk;

  TimelineVisibleRange window() =>
      edges.window(scrollOffset: offset, viewportExtent: viewport);

  setUp(() {
    edges = TimelineRowEdges.uniform(60, rowExtent);
    offset = 0;
    relays = 0;
    walk = TimelineRowWindowWalk(
      view: () =>
          (edges: edges, scrollOffset: offset, viewportExtent: viewport),
      relay: () => relays += 1,
    );
  });
  tearDown(() => walk.dispose());

  /// Each frame's window until the walk stands still, laid as a relay
  /// lays it — the window the frame after each relay lays.
  Future<List<TimelineVisibleRange>> walkOut(WidgetTester tester) async {
    final windows = <TimelineVisibleRange>[];
    for (var frame = 0; frame < 40; frame += 1) {
      final before = relays;
      await tester.pump();
      if (relays == before) {
        return windows;
      }
      windows.add(walk.laid()!);
    }
    fail('the walk never stood still');
  }

  testWidgets('the first lay lays the window the view stands in, the notch '
      'past it included', (tester) async {
    expect(walk.laid(), window());
    expect(window().endIndexExclusive * rowExtent, greaterThan(viewport));
    await tester.pump();
    expect(relays, 0, reason: 'nothing is left to walk');
  });

  testWidgets('a notch whose rows stand laid lays nothing in its own frame, '
      'and the window takes in a unit a frame after it, either way', (
    tester,
  ) async {
    // Rows away from the top, so a notch up takes rows in too.
    offset = 20 * rowExtent;
    for (final notch in [100.0, -100.0]) {
      walk.laid();
      await walkOut(tester);
      final before = walk.laid()!;
      offset += notch;
      expect(walk.moved(), isFalse, reason: 'every row shown stands laid');
      expect(walk.laid(), before, reason: 'the notch\'s frame lays no row');
      expect(relays, 0);

      final steps = await walkOut(tester);
      expect(steps, isNotEmpty);
      expect(steps.last, window(), reason: 'it ends where the view stands');
      var last = before;
      for (final step in steps) {
        final taken = notch > 0
            ? step.endIndexExclusive - last.endIndexExclusive
            : last.startIndex - step.startIndex;
        expect(taken, 1, reason: 'a unit a frame, from $last to $step');
        last = step;
      }
      expect(
        steps.length,
        greaterThan(1),
        reason: '⛔전제: the notch took in more than one row',
      );
      relays = 0;
    }
  });

  testWidgets('a move that shows an unlaid row lays the whole window in its '
      'own frame', (tester) async {
    walk.laid();
    offset = 20 * rowExtent;
    expect(walk.moved(), isTrue);
    expect(walk.laid(), window());
  });

  testWidgets('rows that join are taken in as one', (tester) async {
    edges = TimelineRowEdges([
      for (var index = 0; index < 60; index += 1)
        (extent: rowExtent, room: 0, joinsNext: index % 3 != 2),
    ]);
    walk.laid();
    await walkOut(tester);
    offset += 100;
    expect(walk.moved(), isFalse);
    for (final step in await walkOut(tester)) {
      expect(step.startIndex % 3, 0, reason: '$step starts a unit');
      expect(step.endIndexExclusive % 3, 0, reason: '$step ends one');
    }
    expect(walk.laid(), window());
  });

  testWidgets('a lay over other rows lays where the view stands', (
    tester,
  ) async {
    walk.laid();
    edges = TimelineRowEdges.uniform(60, rowExtent);
    offset = 40;
    expect(walk.moved(), isTrue);
    expect(walk.laid(), window());
  });

  testWidgets('a walk let go of lays nothing more', (tester) async {
    walk.laid();
    offset += 100;
    expect(walk.moved(), isFalse);
    walk.dispose();
    await tester.pump();
    expect(relays, 0);
  });
}
