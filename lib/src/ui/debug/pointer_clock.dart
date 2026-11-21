/// 🔬What the pointer packets the platform hands over cost the thread that
/// builds the app's frames: how many came, how many points they held, and
/// how long each took to be dealt with — the hit test and every handler of
/// every point in it, a stroke's step and a view's move among them
/// (`UiScaleViewConfiguration`, where they come in and are timed). None of
/// it is in a frame's build: a packet is dealt with between frames. The
/// frame statistics read these (`FrameStats`, Settings ▸ Debug), and
/// nothing is timed while they are off.
///
/// 🗣️유저 2026-11-21, on a Galaxy Tab out of this machine's reach (card
/// the-galaxy-tab-canvas-went-slow-on-build-1095): 「팬이랑 스트로크나 줌
/// 이런거만 느리네. 혹시 화면 클릭 점을 많이받아서 그거 비효율적인구조있어서
/// 그런다던가」 — and nothing the app showed could say yes or no.
abstract final class PointerClock {
  /// How long the newest packets took to be dealt with, in microseconds,
  /// oldest first, [packetsKept] of them at the most.
  static List<int> get packetMicros => List.unmodifiable(_packetMicros);
  static final List<int> _packetMicros = [];

  /// How many packets [packetMicros] keeps: a second or two of them, at a
  /// pen's rate.
  static const int packetsKept = 240;

  /// The packets dealt with in all, the points they held, and the
  /// microseconds they took.
  static int get packetsCounted => _packetsCounted;
  static int _packetsCounted = 0;

  static int get pointsCounted => _pointsCounted;
  static int _pointsCounted = 0;

  static int get microsCounted => _microsCounted;
  static int _microsCounted = 0;

  /// A packet of [points] points was dealt with in [micros].
  static void handled({required int points, required int micros}) {
    _packetsCounted += 1;
    _pointsCounted += points;
    _microsCounted += micros;
    _packetMicros.add(micros);
    if (_packetMicros.length > packetsKept) {
      _packetMicros.removeAt(0);
    }
  }

  /// No packet timed yet: what was timed while the statistics were last up
  /// says nothing of now.
  static void forget() {
    _packetMicros.clear();
    _packetsCounted = 0;
    _pointsCounted = 0;
    _microsCounted = 0;
  }
}
