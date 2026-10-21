import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';
import 'package:anicel/src/ui/session/live_stroke_landing.dart';

/// 🗣️F-419 (유저 2026-10-21, after lowering the line layer's opacity to 80
/// and raising it back: 「안그려지기 시작했어」): a view built anew comes up
/// before the one it replaces goes down, and the one going down takes away
/// only a hand nobody else holds up.
void main() {
  test('the view that came up last keeps its hand when the one it replaced '
      'goes down after it', () {
    final hand = ViewHand<String>()
      ..call('old')
      ..call('new')
      ..call(null);

    expect(hand.now, 'new');
  });

  test('the last view going down takes the hand away', () {
    final hand = ViewHand<String>()
      ..call('old')
      ..call('new')
      ..call(null)
      ..call(null);

    expect(hand.now, isNull);
  });

  test('a view that comes up after the old one went down holds it up', () {
    final hand = ViewHand<String>()
      ..call('old')
      ..call(null)
      ..call('new');

    expect(hand.now, 'new');
  });

  test('a goodbye with no view up counts for nothing', () {
    final hand = ViewHand<String>()
      ..call(null)
      ..call('new');

    expect(hand.now, 'new');
    hand.call(null);
    expect(hand.now, isNull);
  });

  test('a save still lands the pen of the view that replaced another', () {
    final landing = LiveStrokeLanding();
    final landed = <String>[];
    landing
      ..lander(() {
        landed.add('old');
        return true;
      })
      ..lander(() {
        landed.add('new');
        return true;
      })
      ..lander(null);

    expect(landing.landNow(), isTrue);
    expect(landed, ['new']);
  });
}
