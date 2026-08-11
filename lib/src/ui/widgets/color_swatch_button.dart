import 'package:flutter/material.dart';

import '../color/color_wheel_panel.dart' show ColorWheel;
import '../theme/app_theme.dart';
import 'anchored_popup.dart';

/// The ONE color-picking control (R28 #9): a round swatch that opens the
/// shared color wheel in the shared anchored sub-window.
///
/// The user's spec: "색만 동그랗게 아이콘마냥 있고 버튼누르면 컬러휠같은
/// ui떠서 색 고를수있게." Anywhere the app needs a color chosen, it mounts
/// THIS — so the picker's look and its window behaviour are defined once.
///
/// [onChanged] fires live while the wheel is dragged; the popup keeps its
/// own working color, so the caller may rebuild underneath freely.
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.keyValue,
    required this.title,
    required this.color,
    required this.onChanged,
    this.tooltip,
    this.diameter = 18,
  });

  /// Widget key string for the trigger ('canvas-paper-color-button').
  final String keyValue;

  /// Popup header — what this color IS ('Canvas', 'Pasteboard').
  final String title;

  final int color;
  final ValueChanged<int> onChanged;
  final String? tooltip;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final swatch = Builder(
      builder: (anchorContext) => Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>(keyValue),
          customBorder: const CircleBorder(),
          onTap: () => showColorPickerPopup(
            anchorContext,
            title: title,
            color: color,
            onChanged: onChanged,
          ),
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
            ),
          ),
        ),
      ),
    );
    final message = tooltip;
    if (message == null) {
      return swatch;
    }
    return Tooltip(message: message, child: swatch);
  }
}

/// Opens the shared color picker anchored to [anchorContext]'s widget.
Future<void> showColorPickerPopup(
  BuildContext anchorContext, {
  required String title,
  required int color,
  required ValueChanged<int> onChanged,
}) {
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'color-picker-popup',
    width: 216,
    height: 252,
    builder: (context, _) => _ColorPickerBody(
      title: title,
      initialColor: color,
      onChanged: onChanged,
    ),
  );
}

class _ColorPickerBody extends StatefulWidget {
  const _ColorPickerBody({
    required this.title,
    required this.initialColor,
    required this.onChanged,
  });

  final String title;
  final int initialColor;
  final ValueChanged<int> onChanged;

  @override
  State<_ColorPickerBody> createState() => _ColorPickerBodyState();
}

class _ColorPickerBodyState extends State<_ColorPickerBody> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.initialColor));
  }

  void _apply(HSVColor next) {
    setState(() => _hsv = next);
    // Opaque: these are surfaces (paper, pasteboard), never stencils.
    widget.onChanged(next.toColor().withAlpha(0xFF).toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    // ⛔No `Material` of its own (R4 #8). It drew elevation 8 where the two
    // other anchored windows drew 6 — one window in three costumes, until a
    // fourth arrived with none.
    return Padding(
      padding: AnchoredPopupText.bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnchoredPopupHeader(
            title: widget.title,
            // The live result, in the same round swatch vocabulary as
            // the button that opened this.
            trailing: Container(
              key: const ValueKey<String>('color-picker-preview'),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
            ),
          ),
          const SizedBox(height: AnchoredPopupText.titleGap),
          SizedBox(
            height: 180,
            child: ColorWheel(
              key: const ValueKey<String>('color-picker-wheel'),
              hsv: _hsv,
              onChanged: _apply,
            ),
          ),
        ],
      ),
    );
  }
}
