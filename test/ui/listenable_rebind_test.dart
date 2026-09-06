// ONE LISTENER MOVES FROM THE OLD LISTENABLE TO THE NEW — AND STAYS PUT
// WHEN THEY ARE THE SAME OBJECT.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/listenable_rebind.dart';

void main() {
  test('a different listenable takes the listener; the old one loses it', () {
    final previous = ChangeNotifier();
    final next = ChangeNotifier();
    addTearDown(previous.dispose);
    addTearDown(next.dispose);
    var heard = 0;
    void listener() => heard += 1;
    previous.addListener(listener);

    expect(rebindListener(previous, next, listener), isTrue);

    previous.notifyListeners();
    expect(heard, 0, reason: 'the old listenable must be fully detached');
    next.notifyListeners();
    expect(heard, 1, reason: 'the new one must be live');
  });

  test('the same object is left alone — no remove, no double add', () {
    final same = ChangeNotifier();
    addTearDown(same.dispose);
    var heard = 0;
    void listener() => heard += 1;
    same.addListener(listener);

    expect(rebindListener(same, same, listener), isFalse);

    same.notifyListeners();
    expect(heard, 1, reason: 'still exactly one subscription');
  });

  test('null on either side is a plain add or a plain remove', () {
    final only = ChangeNotifier();
    addTearDown(only.dispose);
    var heard = 0;
    void listener() => heard += 1;

    expect(rebindListener(null, only, listener), isTrue);
    only.notifyListeners();
    expect(heard, 1);

    expect(rebindListener(only, null, listener), isTrue);
    only.notifyListeners();
    expect(heard, 1, reason: 'removed again');

    expect(rebindListener(null, null, listener), isFalse);
  });
}
