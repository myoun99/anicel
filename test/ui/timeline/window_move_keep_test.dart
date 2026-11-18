import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/window_move_keep.dart';

/// [WindowMoveKeep]: a lay in the pass the last one laid hands back the
/// rows it kept, their facts never asked; a lay in another pass hands
/// back a row while what it is built from holds, and builds the rest; a
/// row the last lay left out builds again.
void main() {
  late List<String> builds;
  late List<String> asked;

  Widget built(String key) {
    builds.add(key);
    return SizedBox(key: ValueKey<String>(key));
  }

  /// [key]'s row in [keep], built from [facts].
  Widget rowOf(WindowMoveKeep keep, String key, Object? facts) => keep.row(
    key,
    () {
      asked.add(key);
      return facts;
    },
    (_) => built(key),
  );

  setUp(() {
    builds = [];
    asked = [];
  });

  test('a lay in the same pass hands back the rows it kept', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    expect(keep.lay(pass), isTrue, reason: 'the first lay is a pass');
    final a = rowOf(keep, 'a', 1);
    expect(keep.lay(pass), isFalse);
    expect(rowOf(keep, 'a', 2), same(a), reason: 'its facts are not asked');
    rowOf(keep, 'b', 1);
    expect(builds, ['a', 'b'], reason: 'only the row that arrived is built');
    expect(asked, ['a', 'b']);
  });

  test('a lay in another pass keeps a row while its facts hold', () {
    final keep = WindowMoveKeep();
    keep.lay(Object());
    final a = rowOf(keep, 'a', 1);
    final b = rowOf(keep, 'b', 1);
    expect(keep.lay(Object()), isTrue);
    expect(rowOf(keep, 'a', 1), same(a));
    expect(rowOf(keep, 'b', 2), isNot(same(b)));
    expect(builds, ['a', 'b', 'b']);
  });

  test('the row is built from the facts it is kept by', () {
    final keep = WindowMoveKeep();
    keep.lay(Object());
    final seen = <Object?>[];
    keep.row('a', () => 7, (facts) {
      seen.add(facts);
      return const SizedBox();
    });
    expect(seen, [7]);
  });

  test('a pass is told by its value', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    keep.lay((pass, 100.0));
    final a = rowOf(keep, 'a', 1);
    expect(keep.lay((pass, 100.0)), isFalse);
    expect(rowOf(keep, 'a', 1), same(a));
    expect(keep.lay((pass, 120.0)), isTrue, reason: 'the view grew');
  });

  test('a row the last lay left out is let go of', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    keep.lay(pass);
    final b = rowOf(keep, 'b', 1);
    keep.lay(pass);
    rowOf(keep, 'a', 1);
    keep.lay(Object());
    expect(rowOf(keep, 'b', 1), isNot(same(b)), reason: 'its facts held');
    expect(builds, ['b', 'a', 'b']);
  });

  test('let go of, a row the last lay left out is not handed back after '
      'it', () {
    final keep = WindowMoveKeep();
    keep.lay(Object());
    final b = rowOf(keep, 'b', 1);
    keep.lay(Object());
    rowOf(keep, 'a', 1);
    expect(
      rowOf(keep, 'b', 1),
      same(b),
      reason: '⛔전제: until it is let go of, its facts hand it back',
    );
    keep.lay(Object());
    rowOf(keep, 'a', 1);
    keep.letGo();
    final again = rowOf(keep, 'b', 1);
    expect(again, isNot(same(b)));
  });

  test('what is built from the pass alone is built again in another', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    keep.lay(pass);
    final zone = keep.ofThePass('zone', () => built('zone'));
    keep.lay(pass);
    expect(keep.ofThePass('zone', () => built('zone')), same(zone));
    keep.lay(Object());
    expect(keep.ofThePass('zone', () => built('zone')), isNot(same(zone)));
    expect(builds, ['zone', 'zone']);
  });
}
