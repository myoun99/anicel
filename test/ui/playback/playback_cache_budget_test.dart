import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// ↩️What a run borrows of the line, and a cel's ink-corner cost, were
/// pinned on the row images here, until a frame's one picture was all the
/// line kept (one-picture-per-frame ②-5b-1) — the borrowing is pinned on
/// the pictures (`the_budget_keeps_what_the_canvas_shows_test`).
void main() {
  /// The frames' pictures, none laid.
  FramePictureStore<FramePictureKey> pictures() {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    return store;
  }

  /// 🚨★★★**THE LARGEST CACHE IN THE APP USED TO BE THE DEAF ONE.**
  ///
  /// `EditorSessionManager.respondToMemoryPressure` always ended by calling
  /// [PlaybackCacheBudgetEnforcer.enforce], and its comment said the
  /// playback caches "re-run their budget against the shrunken world" —
  /// but nothing shrank their world. 600MB went in and 600MB came out,
  /// beside a cel store that had just halved itself.
  group('memory pressure', () {
    PlaybackCacheBudgetEnforcer enforcerAt(int maxBytes) =>
        PlaybackCacheBudgetEnforcer(pictures: pictures(), maxBytes: maxBytes);

    test('the budget halves, and keeps halving', () {
      final enforcer = enforcerAt(playbackCacheBudgetBytes);
      expect(enforcer.maxBytes, playbackCacheBudgetBytes);
      expect(enforcer.respondToMemoryPressure(), isTrue);
      expect(enforcer.maxBytes, playbackCacheBudgetBytes ~/ 2);
      expect(enforcer.respondToMemoryPressure(), isTrue);
      expect(enforcer.maxBytes, playbackCacheBudgetBytes ~/ 4);
    });

    test('it stops at four frames and stays there', () {
      final enforcer = enforcerAt(playbackCacheBudgetUnderPressureBytes * 2);
      expect(enforcer.respondToMemoryPressure(), isTrue);
      expect(enforcer.maxBytes, playbackCacheBudgetUnderPressureBytes);
      // iOS sends the warning again as things get worse; a budget that
      // kept halving would walk to zero and rebuild every scrubbed frame.
      expect(enforcer.respondToMemoryPressure(), isFalse);
      expect(enforcer.maxBytes, playbackCacheBudgetUnderPressureBytes);
    });

    test('a caller already tighter than the floor is left alone', () {
      final enforcer = enforcerAt(1024);
      expect(enforcer.respondToMemoryPressure(), isFalse);
      expect(enforcer.maxBytes, 1024);
    });
  });
}
