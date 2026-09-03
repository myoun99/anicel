import 'package:flutter/foundation.dart';

/// The app's UI scale: how large the CHROME draws, independent of the
/// monitor's own device-pixel ratio.
///
/// ## What it does and does not cover (유저 확정 2026-08-21)
///
/// It scales the chrome — toolbars, rails, panel strips, dialogs — and
/// **not the document views**: the canvas, the media viewer, the conte, the
/// cut envelope and the timesheet all keep their own zoom. The user drew
/// that line by KIND ("캔버스패널 베이스패널은 안 걸리는게 맞을거같아"),
/// not by "which surfaces happen to be rasters", so a new document panel
/// inherits the exclusion by being one rather than by being listed.
///
/// ## ⛔ It is a LADDER, not a slider
///
/// 유저 확정: "배율을 사다리로". Six stops clustered around 100 because that
/// is where a hand actually lands; a continuous control would multiply the
/// monitor ratio into an unbounded set of effective ratios, and every pin in
/// the quantization round would then assert about a grid nobody can
/// enumerate.
///
/// ## How it reaches the pixels
///
/// The scale multiplies into the ROOT DEVICE MATRIX (see
/// `AnicelBinding.createViewConfigurationFor`), so a logical pixel simply
/// becomes larger — nothing below has to know. That is also why
/// `EffectiveDevicePixelRatio` (ui) exists: once this is not 1.0,
/// `MediaQuery.devicePixelRatioOf` no longer answers "how many device pixels
/// is one logical pixel", and every site that quantizes has to read the
/// product instead.
class AppUiScale {
  const AppUiScale._();

  /// The stops, ascending. Tight around 100 (90/110) because that is the
  /// range a user reaches for to make one panel comfortable; wider steps
  /// further out, where the choice is "much bigger" rather than "a little".
  ///
  /// 🆕50% (유저 2026-08-29, I-11): 「**50%같은 더 낮은수도 넣어도
  /// 괜찮을거같은데.** 데스크톱은 쓰기 힘들지만 dpr높은 디바이스는
  /// 쾌적하니까」 — a stop that is unusable on a monitor and comfortable on a
  /// phone is still a stop worth having, because the phone is where a hand
  /// reaches for it.
  static const List<double> ladder = <double>[
    0.5,
    0.75,
    0.9,
    1.0,
    1.1,
    1.25,
    1.5,
  ];

  static const double defaultScale = 1.0;

  /// The scale a device starts on when NOTHING HAS EVER BEEN CHOSEN.
  ///
  /// 유저 2026-08-29 (I-11): 「폰에서 보니까 **75% ui로 봐도 문제없고
  /// 쾌적**해서 dpr값에 따라 ui초기값 배율 다르게하는게 좋을까싶어」, and
  /// on how often it may decide: 「**초기값은 첫 실행 때만** 정해짐」.
  ///
  /// ⛔THIS IS NOT A LIVE RULE. It is read once, on the launch that finds no
  /// settings file, and never again — not when the app moves to another
  /// screen, not when a device is replaced. A rule that re-derived would
  /// eventually overwrite a scale the user chose by hand, and there is no
  /// undo for a setting that changes itself.
  ///
  /// ⛔AND IT ONLY KNOWS WHAT THE USER TOLD IT. They named two devices — a
  /// desktop (uncomfortable small) and a phone (75% comfortable) — so those
  /// are the two answers. A tablet sits at 2.0 and keeps the 100% it has
  /// always had, because nobody said otherwise and inventing a middle step
  /// would be inventing a preference.
  static double firstRunScaleFor(double devicePixelRatio) =>
      devicePixelRatio.isFinite && devicePixelRatio >= 2.5
      ? 0.75
      : defaultScale;

  /// The LIVE scale. App-wide rather than session-owned for the same reason
  /// the accents are: widgets holding no session read it, and it outlives
  /// any one project.
  ///
  /// Writing it is what changes the root matrix — `AnicelBinding` listens.
  static final ValueNotifier<double> value = ValueNotifier<double>(
    defaultScale,
  );

  /// The nearest ladder stop to [scale].
  ///
  /// ⚠️Anything that arrives from OUTSIDE the ladder comes through here: a
  /// settings file written by an older build, a hand-edited JSON, a future
  /// build with more stops. Returning it unchanged would let a value the UI
  /// cannot represent sit in the notifier, and the settings row would then
  /// show no stop as selected.
  static double snap(double scale) {
    if (!scale.isFinite || scale <= 0) {
      return defaultScale;
    }
    var best = ladder.first;
    var bestDistance = (scale - best).abs();
    for (final stop in ladder.skip(1)) {
      final distance = (scale - stop).abs();
      if (distance < bestDistance) {
        best = stop;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The stop [steps] away from the current one, clamped at both ends.
  static double stepped(double from, int steps) {
    final index = ladder.indexOf(snap(from));
    return ladder[(index + steps).clamp(0, ladder.length - 1)];
  }

  /// "125%" — the label, with no trailing `.0`.
  static String label(double scale) {
    final percent = scale * 100;
    final rounded = percent.roundToDouble();
    return (percent - rounded).abs() < 1e-9
        ? '${rounded.toInt()}%'
        : '${percent.toStringAsFixed(1)}%';
  }
}
