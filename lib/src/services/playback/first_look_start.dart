/// When a device's run STARTS: on the first look of the clock that reads
/// it — not when the run is armed.
///
/// 🚨THE SOUND STARTS WITH THE PICTURE'S FIRST FRAME
/// (play-press-first-frame-stall, 10-15; 유저 2026-10-08: 「소리 싱크나
/// 영상이나 뭐 그런거 정확하기만하면되. 그게 제일 최우선」). A press arms a run
/// — the device opened, its window uploaded — and the clock first looks on
/// the next frame that begins: that frame is the run's first picture, and
/// the sound starts with it. ↩️The device was started at the press, and it
/// played on through everything that came before that look — the press's
/// own work, the frame it held up — so the picture, which shows what is
/// heard, met the sound a few frames in: 🔬on the AMMI OP (profile, 10-15)
/// the first look came 100–370ms after the press (opening the device 63ms,
/// uploading its window 37ms, of the UI thread), and the playhead went
/// 0 → 2, 0 → 3, 0 → 4 — the frames the press stood on never shown.
///
/// ONE LAW for everything that puts a picture beside a device's sound: the
/// canvas's transport and the media viewer's sound each arm their runs
/// here, and look through it before they read the device.
final class FirstLookStart {
  void Function()? _start;

  /// A run is armed: [start] starts its device — on the first [look]. A run
  /// armed again before then is the run armed last.
  void arm(void Function() start) => _start = start;

  /// The device is read for a look of the clock: the run armed last starts
  /// now, if it has not. Every later look finds nothing to start.
  void look() {
    final start = _start;
    _start = null;
    start?.call();
  }

  /// The run stopped before its first look: it never starts.
  void disarm() => _start = null;
}
