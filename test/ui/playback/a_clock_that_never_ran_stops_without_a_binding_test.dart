import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/playback/looking_ticker.dart';

/// A clock is stopped on every dispose — a session's, a playback rig's —
/// and a session can be disposed where no binding was ever made: a
/// service's own test. A clock that never ran has nothing to say
/// ([LookingTicker.stop]).
void main() {
  test('a clock that never ran stops with no binding to tell', () {
    expect(() => LookingTicker((_) {}).stop(), returnsNormally);
  });
}
