import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

/// 🚨★★★**ONE RULE MOVES EVERY STREAMING WINDOW**
/// (import-preview-plays-silent, 2026-09-29).
///
/// A file past two minutes streams from disk through a window two seconds
/// behind and thirty ahead. The rule that moves the window with a playing
/// stream lived inside the timeline's transport alone, and the media
/// viewer's sound never moved its window: it went silent half a minute
/// after play was pressed. Both call [AudioStreamingWindow.followPlayback]
/// now, and this is the rule.
void main() {
  const rate = 48000;

  AudioStreamingWindow streaming({required int centre}) =>
      AudioStreamingWindow()
        ..hasStreaming = true
        ..centerSample = centre;

  AudioConformStore store() {
    final conform = AudioConformStore(resolveConformPath: (_) => null);
    addTearDown(conform.dispose);
    return conform;
  }

  test('a window with nothing streaming never moves', () {
    final window = AudioStreamingWindow();
    expect(window.wantsRecentreAt(rate * 600, rate), isFalse);
  });

  test('🎯it moves once the stream is past halfway to its leading edge — '
      '~15 s before the mix could read past it', () {
    final window = streaming(centre: rate * 10);
    const halfway =
        rate * 10 + (AudioStreamingWindow.aheadSeconds * rate) ~/ 2;

    expect(window.wantsRecentreAt(halfway, rate), isFalse);
    expect(window.wantsRecentreAt(halfway + 1, rate), isTrue);
  });

  test('and once it is behind the trailing edge', () {
    final window = streaming(centre: rate * 10);
    const trailing = rate * 10 - AudioStreamingWindow.backSeconds * rate;

    expect(window.wantsRecentreAt(trailing, rate), isFalse);
    expect(window.wantsRecentreAt(trailing - 1, rate), isTrue);
  });

  test('a stream still inside its window asks nothing of the '
      'player', () async {
    final window = streaming(centre: 0);
    var asked = 0;

    window.followPlayback(
      positionSamples: rate,
      deviceRate: rate,
      conformStore: store(),
      current: () {
        asked += 1;
        return null;
      },
    );
    await Future<void>.delayed(Duration.zero);

    expect(asked, 0);
  });

  test('an advance runs off the caller\'s stack, ONE at a time — and the '
      'next tick may ask again once it is done', () async {
    final window = streaming(centre: 0);
    final conformStore = store();
    var asked = 0;
    void tick() => window.followPlayback(
      positionSamples: rate * 20,
      deviceRate: rate,
      conformStore: conformStore,
      current: () {
        asked += 1;
        return null;
      },
    );

    tick();
    expect(asked, 0, reason: 'off the stack — the tick does not wait on disk');
    tick();
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1, reason: 'a poll cannot stack a second read on the first');

    tick();
    await Future<void>.delayed(Duration.zero);
    expect(asked, 2, reason: 'the guard lets go when the advance is done');
  });
}
