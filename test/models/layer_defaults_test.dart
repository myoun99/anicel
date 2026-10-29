// A NEW LAYER IS VISIBLE, OPEN, AUDIBLE AND CARRIES THE DEFAULT SOUND.
//
// The mutation campaign (2026-09-03) flipped `isVisible = true` to false in
// the constructor and nothing noticed: every test that built a layer set
// what it needed and never asked what the defaults were. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/se_sound.dart';

void main() {
  test('a layer built with only the required fields shows, is open, '
      'is audible and carries the default sound', () {
    final layer = Layer(id: const LayerId('l'), name: 'L', frames: const []);
    expect(layer.isVisible, isTrue);
    expect(layer.collapsed, isFalse);
    expect(layer.muted, isFalse);
    expect(layer.seSound, const SeSound());
    expect(layer.timeline, isEmpty);
    expect(layer.audioClips, isEmpty);
  });
}
