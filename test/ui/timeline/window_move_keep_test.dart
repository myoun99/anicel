import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/window_move_keep.dart';

/// [WindowMoveKeep]: a lay in the pass the last one laid hands back the
/// rows it kept; a lay in another pass, or a row the last lay left out,
/// builds again.
void main() {
  late List<String> builds;

  Widget built(String key) {
    builds.add(key);
    return SizedBox(key: ValueKey<String>(key));
  }

  setUp(() => builds = []);

  test('a lay in the same pass hands back the rows it kept', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    expect(keep.lay(pass), isTrue, reason: 'the first lay is a pass');
    final a = keep.row('a', () => built('a'));
    expect(keep.lay(pass), isFalse);
    expect(keep.row('a', () => built('a')), same(a));
    keep.row('b', () => built('b'));
    expect(builds, ['a', 'b'], reason: 'only the row that arrived is built');
  });

  test('a lay in another pass keeps nothing', () {
    final keep = WindowMoveKeep();
    keep.lay(Object());
    final a = keep.row('a', () => built('a'));
    expect(keep.lay(Object()), isTrue);
    expect(keep.row('a', () => built('a')), isNot(same(a)));
    expect(builds, ['a', 'a']);
  });

  test('a pass is told by its value', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    keep.lay((pass, 100.0));
    final a = keep.row('a', () => built('a'));
    expect(keep.lay((pass, 100.0)), isFalse);
    expect(keep.row('a', () => built('a')), same(a));
    expect(keep.lay((pass, 120.0)), isTrue, reason: 'the view grew');
  });

  test('a row the last lay left out is let go of', () {
    final keep = WindowMoveKeep();
    final pass = Object();
    keep.lay(pass);
    final b = keep.row('b', () => built('b'));
    keep.lay(pass);
    keep.row('a', () => built('a'));
    keep.lay(pass);
    expect(keep.row('b', () => built('b')), isNot(same(b)));
    expect(builds, ['b', 'a', 'b']);
  });
}
