import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/transform_values.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/transform_box.dart';

/// 🗣️F-586 (유저 2026-11-12): 「다시말하지만 화면에서 조작하는건 설정쪽에서도
/// 보여야함. 지금 중간 왼쪽아래 사각형 조작했는데 도구설정패널에서 바뀌는게
/// 없는거 보고 확인함. 포인트별로 좌표 둔다거나. 최대한 알기쉽게」 — and
/// F-586-Q1 (11-14) 「모든 점 목록」. The box's warp is what the list reads:
/// its points row by row from the top left, and the one in hand.
void main() {
  CanvasPoint at(double x, double y) => CanvasPoint(x: x, y: y);
  final rest = at(0, 0);

  BoxWarp warpIn(TransformMode mode, {int columns = 3, int rows = 3}) =>
      BoxWarp()..syncToMode(mode, columns: columns, rows: rows);

  test('일반 holds no points to read, and a write names nothing', () {
    final warp = warpIn(TransformMode.normal);

    expect(warp.asRead, isNull);
    warp.moveRead(0, (_) => at(5, 5));
    expect(warp.asRead, isNull);
    expect(warp.inHand, isEmpty);
    expect(warp.isFlat, isTrue);
  });

  test('a 메쉬 grid reads as it is kept — row by row from the top left', () {
    final warp = warpIn(TransformMode.mesh);

    warp.moveRead(9, (now) => at(now.x + 12, now.y - 5));

    expect(warp.mesh![9], at(12, -5), reason: 'second across, third down');
    expect(warp.asRead, warp.mesh);
    expect(warp.inHand, [9]);
    expect(warp.inHandAsRead, [9]);
    expect(
      [
        for (final (index, offset) in warp.mesh!.indexed)
          if (index != 9) offset,
      ],
      everyElement(rest),
      reason: 'every other point where it rests',
    );
  });

  test('🚨the 퍼스 quad — kept TL · TR · BR · BL, as its outline walks it — '
      'reads as two rows of two', () {
    final warp = warpIn(TransformMode.perspective)
      ..corners = [at(1, 1), at(2, 2), at(3, 3), at(4, 4)];

    expect(
      warp.asRead,
      [at(1, 1), at(2, 2), at(4, 4), at(3, 3)],
      reason: 'top left, top right, bottom left, bottom right',
    );

    // The third a list reads is the bottom LEFT: the quad's fourth.
    warp.moveRead(2, (now) => at(now.x + 10, now.y));
    expect(warp.corners, [at(1, 1), at(2, 2), at(3, 3), at(14, 4)]);
    expect(warp.inHand, [3], reason: 'its place in the quad');
    expect(warp.inHandAsRead, [2], reason: 'and its place in the list');

    warp.moveRead(3, (_) => at(0, 9));
    expect(warp.corners![2], at(0, 9), reason: 'the bottom right');
    expect(warp.inHandAsRead, [3]);

    // An edge's grip carries its two corners: the right edge is TR and BR.
    warp.inHand = const [1, 2];
    expect(warp.inHandAsRead, [1, 3]);
  });

  test('a write leaves a list of its own — the one a step back was handed '
      'is as it was', () {
    final warp = warpIn(TransformMode.mesh);
    final before = warp.mesh!;

    warp.moveRead(0, (_) => at(7, 7));

    expect(identical(warp.mesh, before), isFalse);
    expect(before, everyElement(rest));
  });

  test('a point past the list\'s end is no point', () {
    for (final mode in [TransformMode.perspective, TransformMode.mesh]) {
      final warp = warpIn(mode);
      final count = warp.asRead!.length;

      warp
        ..moveRead(count, (_) => at(5, 5))
        ..moveRead(-1, (_) => at(5, 5));

      expect(warp.isFlat, isTrue, reason: '$mode');
      expect(warp.inHand, isEmpty, reason: '$mode');
    }
  });

  group('the point in hand goes with the points it names', () {
    test('another mode leaves nothing in hand', () {
      final warp = warpIn(TransformMode.mesh)..moveRead(5, (_) => at(3, 3));
      expect(warp.inHand, [5], reason: 'the premise');

      warp.syncToMode(TransformMode.perspective, columns: 3, rows: 3);

      expect(warp.inHand, isEmpty);
    });

    test('another grid leaves nothing in hand', () {
      final warp = warpIn(TransformMode.mesh)..moveRead(5, (_) => at(3, 3));

      warp.syncToMode(TransformMode.mesh, columns: 4, rows: 3);

      expect(warp.inHand, isEmpty);
    });

    test('the same mode and the same grid keep it', () {
      final grid = warpIn(TransformMode.mesh)..moveRead(5, (_) => at(3, 3));
      grid.syncToMode(TransformMode.mesh, columns: 3, rows: 3);
      expect(grid.inHand, [5]);

      final quad = warpIn(TransformMode.perspective)
        ..moveRead(1, (_) => at(3, 3));
      quad.syncToMode(TransformMode.perspective, columns: 3, rows: 3);
      expect(quad.inHand, [1]);
    });

    test('초기화 puts every point back and leaves none in hand', () {
      final warp = warpIn(TransformMode.mesh)..moveRead(5, (_) => at(3, 3));

      warp.reset();

      expect(warp.isFlat, isTrue);
      expect(warp.inHand, isEmpty);
    });
  });

  test('the tool\'s options say how the armed mode\'s points stand — the '
      'rows the list names them by', () {
    expect(
      TransformToolOptions.defaults.warpPoints,
      (across: 0, down: 0),
      reason: '일반 has none',
    );
    expect(
      const TransformToolOptions(mode: TransformMode.perspective).warpPoints,
      (across: 2, down: 2),
    );
    const grid = TransformToolOptions(
      mode: TransformMode.mesh,
      meshColumns: 5,
      meshRows: 2,
    );
    expect(grid.warpPoints, (across: 6, down: 3));
    expect(
      warpIn(TransformMode.mesh, columns: 5, rows: 2).asRead,
      hasLength(grid.warpPoints.across * grid.warpPoints.down),
      reason: 'the points the box holds for that grid',
    );
    expect(
      warpIn(TransformMode.perspective).asRead,
      hasLength(4),
      reason: 'and for the quad',
    );
  });

  group('the points as the channel carries them', () {
    test('two readings of the same points are one value — a publish that '
        'changes nothing is no news', () {
      final commands = CanvasSelectionCommands();
      addTearDown(commands.dispose);
      var heard = 0;
      commands.liveWarpPoints.addListener(() => heard += 1);

      commands.publishWarpPoints(
        WarpPointsShown(offsets: [at(1, 2), rest], inHand: const [0]),
      );
      commands.publishWarpPoints(
        WarpPointsShown(offsets: [at(1, 2), rest], inHand: const [0]),
      );
      expect(heard, 1);

      commands.publishWarpPoints(
        WarpPointsShown(offsets: [at(1, 2), rest], inHand: const [1]),
      );
      expect(heard, 2, reason: 'another point in hand is news');

      commands.publishWarpPoints(
        WarpPointsShown(offsets: [at(1, 3), rest], inHand: const [1]),
      );
      expect(heard, 3, reason: 'and so is a point moved');
    });

    test('a point the box does not hold reads as none', () {
      final shown = WarpPointsShown(offsets: [at(1, 2)]);

      expect(shown.offsetAt(0), at(1, 2));
      expect(shown.offsetAt(1), isNull);
    });

    test('a channel that is gone is told nothing — a layer on its way out '
        'says its box closed a frame after the channel can have gone', () {
      final commands = CanvasSelectionCommands()..dispose();

      expect(
        () => commands.publishWarpPoints(WarpPointsShown(offsets: [rest])),
        returnsNormally,
      );
      expect(
        () => commands.publishTransformValues(const TransformValues(tx: 3)),
        returnsNormally,
      );
    });
  });
}
