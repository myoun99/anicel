import 'package:flutter/material.dart';

import '../widgets/field_slider.dart';
import 'color_hex.dart';

/// The RGB tab (R10 R5): the same colour, said in the three numbers that
/// a spec sheet, a client's note and a paint bucket all speak.
///
/// The wheel is for finding a colour; this is for BEING GIVEN one. The
/// bars carry no numeric entry of their own — typing a channel is the
/// status bar's job, one tap on the number itself, so the window has one
/// place where numbers are typed rather than three.
class ColorRgbPanel extends StatelessWidget {
  const ColorRgbPanel({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  final int color;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final channels = colorChannels(color);

    Widget bar(
      String label,
      String keySuffix,
      int value,
      int Function(int) withValue,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FieldSlider(
          key: ValueKey<String>('color-rgb-$keySuffix'),
          min: 0,
          max: 255,
          value: value.toDouble(),
          label: label,
          valueText: '$value',
          valueTextBuilder: (v) => '${v.round()}',
          // A channel is a whole number of steps, so the bar snaps to them
          // instead of handing 137.4 to a byte.
          divisions: 255,
          onChanged: (v) => onColorChanged(withValue(v.round())),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar(
          'R',
          'r',
          channels.r,
          (v) => colorFromChannels(r: v, g: channels.g, b: channels.b),
        ),
        bar(
          'G',
          'g',
          channels.g,
          (v) => colorFromChannels(r: channels.r, g: v, b: channels.b),
        ),
        bar(
          'B',
          'b',
          channels.b,
          (v) => colorFromChannels(r: channels.r, g: channels.g, b: v),
        ),
      ],
    );
  }
}
