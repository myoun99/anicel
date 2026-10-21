import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';
import 'package:anicel/src/ui/session/live_stroke_landing.dart';

/// 🗣️F-419 (유저 2026-10-21, after lowering the line layer's opacity to 80
/// and raising it back: 「안그려지기 시작했어」): a view built anew comes up
/// before the one it replaces goes down, and each view puts down only its
/// own hand.
void main() {
  test('the view that came up last keeps its hand when the one it replaced '
      'goes down after it', () {
    final hand = ViewHand<String>()
      ..up('old')
      ..up('new')
      ..down('old');

    expect(hand.now, 'new');
  });

  test('while both are up — the new view\'s hello before the old one\'s '
      'goodbye — the new one answers', () {
    final hand = ViewHand<String>()
      ..up('old')
      ..up('new');

    expect(hand.now, 'new', reason: 'the new view is the one that stays');
  });

  test('the last view going down takes the hand away', () {
    final hand = ViewHand<String>()
      ..up('old')
      ..up('new')
      ..down('old')
      ..down('new');

    expect(hand.now, isNull);
  });

  test('a view that comes up after the old one went down holds it up', () {
    final hand = ViewHand<String>()
      ..up('old')
      ..down('old')
      ..up('new');

    expect(hand.now, 'new');
  });

  test('a newer view going down first leaves the older one\'s hand, never '
      'its own', () {
    final hand = ViewHand<String>()
      ..up('old')
      ..up('new')
      ..down('new');

    expect(hand.now, 'old', reason: 'the hand of a view that is gone is no '
        'hand — a lander into tiles already given back');
  });

  test('a view putting down a hand it never held up changes nothing', () {
    final hand = ViewHand<String>()
      ..up('new')
      ..down('stranger');

    expect(hand.now, 'new');
  });

  test('a save still lands the pen of the view that replaced another', () {
    final landing = LiveStrokeLanding();
    final landed = <String>[];
    bool old() {
      landed.add('old');
      return true;
    }

    bool fresh() {
      landed.add('new');
      return true;
    }

    landing.lander
      ..up(old)
      ..up(fresh)
      ..down(old);

    expect(landing.landNow(), isTrue);
    expect(landed, ['new']);
  });
}
