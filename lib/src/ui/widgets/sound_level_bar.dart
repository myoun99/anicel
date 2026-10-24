import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppColors;
import 'field_slider.dart';

/// HOW LOUD A THING THAT PLAYS IS — the app's one value bar in its micro
/// form, the number alone, as the rail's opacity bars write theirs.
///
/// ONE bar for every level a surface's sound is played at: the viewer's
/// transport stands it beside its speaker, and a frame panel's transport at
/// the end of its row for the canvas's sound (I-85, 유저 2026-10-24 Q1:
/// 「그냥 막대 가로형. 늘 쓰던거」).
class SoundLevelBar extends StatelessWidget {
  const SoundLevelBar({
    super.key,
    required this.keyValue,
    required this.level,
    required this.onChanged,
    required this.onChangeEnd,
    this.muted = false,
  });

  static const double width = 64;
  static const double height = 18;

  /// The bar's own key — what a test finds the [FieldSlider] by.
  final String keyValue;

  /// 0..1.
  final double level;

  /// Grey, and still the level an unmute comes back to.
  final bool muted;

  /// Every step of the bar under the hand.
  final ValueChanged<double>? onChanged;

  /// Once, where the hand lets go.
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: FieldSlider(
      key: ValueKey<String>(keyValue),
      value: level.clamp(0.0, 1.0).toDouble(),
      min: 0,
      max: 1,
      divisions: 100,
      displayScale: 100,
      height: height + FieldSlider.growthIn(context),
      restingAccent: muted ? AppColors.textDim : null,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    ),
  );
}
