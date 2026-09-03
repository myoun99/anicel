// A NEW LAYER IS VISIBLE, OPEN, AUDIBLE AND AT FULL GAIN.
//
// The mutation campaign (2026-09-03) flipped `isVisible = true` to false in
// the constructor and nothing noticed: every test that built a layer set
// what it needed and never asked what the defaults were. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';

void main() {
  test('a layer built with only the required fields shows, is open, '
      'is audible and sits at gain 1', () {
    final layer = Layer(id: const LayerId('l'), name: 'L', frames: const []);
    expect(layer.isVisible, isTrue);
    expect(layer.collapsed, isFalse);
    expect(layer.muted, isFalse);
    expect(layer.audioGain, 1.0);
    expect(layer.timeline, isEmpty);
    expect(layer.audioClips, isEmpty);
  });
}
