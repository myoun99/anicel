import 'package:flutter/widgets.dart';

import '../../models/brush_shape.dart';
import '../text/app_strings.dart';
import '../widgets/field_slider.dart';
import 'brush_tool_state.dart';

/// THE BAR A SPACING IS SET ON — a brush's tip, its dual tip, the stamp's
/// trail: a share of the size the marks are laid by, from
/// [BrushShape.minSpacing] to [BrushShape.maxSpacing], read in per cent on
/// an exponential scale.
///
/// One bar for the three: the brush's two rows wrote it out twice, and the
/// stamp's (🗣️a-stamp-drag-undoes-a-stamp-at-a-time-Q1, 유저 2026-11-19:
/// 「스탬프 도구설정에 간격설정도 두도록」) would have been the third.
FieldSlider spacingBar({
  required String keyValue,
  required double value,
  required ValueChanged<double> onChanged,
}) => FieldSlider.cell(
  key: ValueKey<String>(keyValue),
  label: AppText.strings.brSpacing,
  unit: '%',
  displayScale: 100,
  value: BrushToolState.clampSpacing(value),
  min: BrushShape.minSpacing,
  max: BrushShape.maxSpacing,
  scale: FieldSliderScale.exponential,
  onChanged: onChanged,
);
