/// One float sample at unit scale, as the int16 this app's chain stores.
///
/// 🚨**32768, NOT 32767** — the industry convention, and what dr_wav uses
/// (it multiplies by the literal 0.000030517578125f). Matching it is not
/// cosmetic: a decoder hands back `raw / 32768`, so multiplying by 32768
/// returns the SAME int16 the file held, and -32768 survives, which the
/// 32767 convention cannot represent. Only +1.0 needs the clamp.
///
/// Clipping lives HERE, not in the mix — a bus is allowed past unity (that
/// is what headroom is), and only the conversion to a fixed-point format
/// has to decide what to do about it. Dart's `double.round()` rounds half
/// away from zero, exactly like C's `llround`.
///
/// ⛔THREE WRITERS SHARE THIS SCALE — the mixer's device output, the
/// conform encoder, and the video export's audio track. Written out per
/// writer, the same audio would sit at two different levels depending on
/// which door it left by, and the conform's own decoder note says exactly
/// that about the read side.
int int16FromUnitSample(double value) {
  var clamped = value;
  if (clamped > 1.0) {
    clamped = 1.0;
  } else if (clamped < -1.0) {
    clamped = -1.0;
  }
  final scaled = (clamped * 32768.0).round();
  return scaled > 32767 ? 32767 : scaled;
}
