import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';

import '../color/color_status_bar.dart' show ColorStatusBar;
import '../color/color_wheel_panel.dart' show ColorWheel;
import '../text/app_strings.dart';
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
    required this.color,
    required this.onChanged,
    required this.currentColorOf,
    this.tooltip,
    this.diameter = 18,
  });

  /// Widget key string for the trigger ('canvas-paper-color-button').
  final String keyValue;

  final int color;
  final ValueChanged<int> onChanged;

  /// The colour 「현재 색 반영」 copies in — the tool's own.
  ///
  /// A callback rather than a value: it is read at the moment the popup
  /// opens, which is the only moment it means anything, and that saves
  /// every host rebuilding its swatch each time the brush colour moves.
  final int Function() currentColorOf;

  final String? tooltip;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final swatch = Builder(
      // 🚨A swatch is a control: a press that lands here is its own,
      // scroll included ([ControlPressClaim]).
      builder: (anchorContext) => ControlPressClaim(
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: ControlPressClaim(
            onPressed: () => showColorPickerPopup(
              anchorContext,
              color: color,
              onChanged: onChanged,
              currentColorOf: currentColorOf,
            ),
            child: InkWell(
              key: ValueKey<String>(keyValue),
              customBorder: const CircleBorder(),
              onTap: silentPress(
                () => showColorPickerPopup(
                  anchorContext,
                  color: color,
                  onChanged: onChanged,
                  currentColorOf: currentColorOf,
                ),
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
  required int color,
  required ValueChanged<int> onChanged,
  required int Function() currentColorOf,
}) {
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'color-picker-popup',
    // Widened from 216 for the readout: R/G/B at three fixed digits each
    // plus the hex is 246 wide, and the bar keeps those cells fixed on
    // purpose (a readout that reflows while you drag cannot be watched).
    // So the WINDOW gives way, not the numbers.
    width: 248,
    // The wheel, the action row above it and the readout below it. Grown
    // by the readout's own height when it arrived, so the wheel keeps the
    // 180 it was drawn at.
    height: 252 + ColorStatusBar.height,
    builder: (context, _) => _ColorPickerBody(
      initialColor: color,
      onChanged: onChanged,
      currentColorOf: currentColorOf,
    ),
  );
}

class _ColorPickerBody extends StatefulWidget {
  const _ColorPickerBody({
    required this.initialColor,
    required this.onChanged,
    required this.currentColorOf,
  });

  final int initialColor;
  final ValueChanged<int> onChanged;
  final int Function() currentColorOf;

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
    // 🚨F-23 (유저 2026-08-24): 「지금 캔버스패널 색 선택시 왼쪽위에
    // **캔버스라고 써있거나 하는데, 그거 그냥 제거. 안뜨도록.** 오른쪽에 있는
    // **선택된 색 보여주는것도 어차피 버튼자체가 색 보여주는거니까 겹치니까
    // 삭제.** 대신 해당 위치에 **현재 색 반영** 이라는 버튼 추가 … 그리고
    // 아래에 컬러 패널처럼 **hex나 RGB있는거 그대로 로직 재사용**」.
    //
    // ⛔The title and the preview both said something the trigger already
    // says — you pressed a swatch of this colour, so the window naming it
    // and echoing it were two labels for what your finger is still on.
    //
    // ★The header ROW stays and only its contents change, which is the
    // standing rule: the wheel must not jump up the window when there is
    // nothing to put above it.
    return Padding(
      padding: AnchoredPopupText.bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ControlPressClaim(
              onPressed: () =>
                  _apply(HSVColor.fromColor(Color(widget.currentColorOf()))),
              child: TextButton(
                key: const ValueKey<String>('color-picker-use-current'),
                onPressed: silentPress(
                  () => _apply(
                    HSVColor.fromColor(Color(widget.currentColorOf())),
                  ),
                ),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(AppText.strings.colorUseCurrent),
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
          // The colour window's own readout, unchanged — 「그대로 로직
          // 재사용」. Typing a hex or a channel here moves the wheel,
          // because both write the same colour.
          ColorStatusBar(
            key: const ValueKey<String>('color-picker-status'),
            color: _hsv.toColor().toARGB32(),
            onColorChanged: (argb) => _apply(HSVColor.fromColor(Color(argb))),
          ),
        ],
      ),
    );
  }
}
