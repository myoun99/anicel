import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/keyed_notices.dart';

/// Listeners held by what they show ([KeyedNotices]) — the one law the
/// timeline tiles' landings, the rows' cel answers and the panel pictures'
/// landings each hear through (conte-one-eye-repaints-every-track).
void main() {
  test('a listener hears the notices that name its key, never another\'s — '
      'and once, though it listens for several the notice names', () {
    final notices = KeyedNotices<String>();
    var a = 0;
    var both = 0;
    void onA() => a += 1;
    void onBoth() => both += 1;
    notices.of('a').addListener(onA);
    notices.of('a').addListener(onBoth);
    notices.of('b').addListener(onBoth);

    notices.notice(['b']);
    expect((a, both), (0, 1));

    notices.notice(['a', 'b']);
    expect((a, both), (1, 2));

    notices.notice(['c']);
    expect((a, both), (1, 2), reason: 'a key nothing shows tells nobody');
  });

  test('a notice to all tells every listener once', () {
    final notices = KeyedNotices<String>();
    var one = 0;
    var two = 0;
    notices.of('a').addListener(() => one += 1);
    void onTwo() => two += 1;
    notices.of('a').addListener(onTwo);
    notices.of('b').addListener(onTwo);

    notices.noticeAll();

    expect((one, two), (1, 1));
  });

  test('a key is held while something shows it, and its last listener '
      'leaving lets it go — and says so', () {
    final unheard = <String>[];
    final notices = KeyedNotices<String>(unheard: unheard.add);
    void first() {}
    void second() {}
    notices.of('a').addListener(first);
    notices.of('a').addListener(second);
    expect(notices.isHeard('a'), isTrue);
    expect(notices.isHeard('b'), isFalse);

    notices.of('a').removeListener(first);
    expect(notices.isHeard('a'), isTrue, reason: 'one still shows it');
    expect(unheard, isEmpty);

    notices.of('a').removeListener(second);
    expect(notices.isHeard('a'), isFalse);
    expect(unheard, ['a']);

    notices.of('a').removeListener(second);
    expect(unheard, ['a'], reason: 'a key let go is not let go again');
  });

  test('a listener that leaves while the others are told leaves no one '
      'untold', () {
    final notices = KeyedNotices<String>();
    final heard = <String>[];
    late void Function() leaver;
    leaver = () {
      heard.add('leaver');
      notices.of('a').removeListener(leaver);
    };
    notices.of('a').addListener(leaver);
    notices.of('a').addListener(() => heard.add('stayer'));

    notices.notice(['a']);

    expect(heard, unorderedEquals(['leaver', 'stayer']));
  });
}
