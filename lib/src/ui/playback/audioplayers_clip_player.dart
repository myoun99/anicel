import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';

import 'audio_playback_sync.dart';

/// Production [AudioClipPlayer] backed by the `audioplayers` plugin (the
/// app's first native plugin — real playback needs a device run, never
/// FLUTTER_TEST). One underlying player per clip; lowLatency mode is for
/// short soundboard assets, SE clips use the default mediaPlayer mode.
///
/// All heavyweight native work (player creation, media source opening)
/// happens in [prepare] at playback activation. [startAt] only seeks and
/// resumes, and [stop] keeps the source loaded (ReleaseMode.stop), so cut
/// boundary ticks never open or tear down a media pipeline — on Windows
/// that work runs on the platform thread and visibly stalled playback at
/// the boundary.
///
/// ⛔NOT UNIT-TESTABLE, measured 2026-09-05: constructing `ap.AudioPlayer`
/// alone blocks on a platform channel that never answers under
/// `flutter test`, so even a test that only checks this class's own
/// control flow (prepare's memoisation, startAt standing down before it)
/// hangs until the 30s timeout. The audit left it unpinned deliberately
/// rather than adding a test that cannot run — the seam that COULD be
/// pinned is an injected player, and nothing has asked for one.
class AudioplayersClipPlayer implements AudioClipPlayer {
  final ap.AudioPlayer _player = ap.AudioPlayer();
  Future<void>? _prepared;
  bool _ready = false;

  @override
  Future<void> prepare(String filePath) =>
      _prepared ??= _prepareSource(filePath);

  Future<void> _prepareSource(String filePath) async {
    try {
      // ReleaseMode.stop keeps the prepared source across stop(); the
      // default (release) would tear it down and force a reload on the
      // next start — exactly the boundary stall prepare-ahead avoids.
      await _player.setReleaseMode(ap.ReleaseMode.stop);
      await _player.setSource(ap.DeviceFileSource(filePath));
      _ready = true;
    } on Object catch (error) {
      debugPrint('[AudioplayersClipPlayer] failed to load $filePath: $error');
    }
  }

  @override
  Future<void> startAt(Duration position) async {
    final prepared = _prepared;
    if (prepared == null) {
      return;
    }
    await prepared;
    if (!_ready) {
      return;
    }
    try {
      await _player.seek(position);
      await _player.resume();
    } on Object catch (error) {
      debugPrint('[AudioplayersClipPlayer] failed to start: $error');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
    } on Object catch (error) {
      debugPrint('[AudioplayersClipPlayer] failed to set volume: $error');
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
