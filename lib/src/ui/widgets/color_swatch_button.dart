import 'dart:async';
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
    this.currentColorOf,
    this.onNone,
    this.tooltip,
  });

  /// Widget key string for the trigger ('canvas-paper-color-button').
  final String keyValue;

  /// The colour on the swatch, or null for 「없음」 — a real value where the
  /// host says it is one (the アフレコ box turned off), never a placeholder
  /// for 「not loaded yet」.
  final int? color;
  final ValueChanged<int> onChanged;

  /// The colour 「현재 색 반영」 copies in — the tool's own.
  ///
  /// A callback rather than a value: it is read at the moment the popup
  /// opens, which is the only moment it means anything, and that saves
  /// every host rebuilding its swatch each time the brush colour moves.
  ///
  /// ⚠️NULL where there is no tool colour to copy — a timeline member lane
  /// is nowhere near the brush. The button keeps its seat and goes dead
  /// (⛔없다가 생기는 UI 금지); it does not disappear and the wheel does not
  /// move up to fill the gap.
  final int Function()? currentColorOf;

  /// What 「없음」 does, or null where absence is not a value here.
  ///
  /// 🚨`Q-f22-none`, 유저 답 **1번**: the box behind a name can be turned
  /// off, and the only way back to that used to be typing the word `none`
  /// into a text cell. The row is in the SHARED window rather than beside
  /// the one swatch that needs it, so the picker stays one picker — 「없음이
  /// 가능한 자리에서만 눌리고, 아닌 데서는 회색으로 죽어 있음」.
  final VoidCallback? onNone;

  final String? tooltip;
  static const double _diameter = 18;

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
            onPressed: () => _open(anchorContext),
            child: InkWell(
              key: ValueKey<String>(keyValue),
              customBorder: const CircleBorder(),
              onTap: silentPress(() => _open(anchorContext)),
              child: SizedBox(
                width: _diameter,
                height: _diameter,
                child: CustomPaint(painter: _SwatchPainter(color: color)),
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

  void _open(BuildContext anchorContext) => showColorPickerPopup(
    anchorContext,
    color: color,
    onChanged: onChanged,
    currentColorOf: currentColorOf,
    onNone: onNone,
  );
}

/// The swatch face: the colour, or the 「없음」 diagonal.
///
/// ⛔A slash rather than an empty circle. Absence and 「a very dark colour」
/// are one glyph apart on this app's surfaces, and the box colour's default
/// is dark — an unfilled circle would have read as 「#202020」 to the eye.
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color});

  final int? color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    if (color != null) {
      fill.color = Color(color!);
      canvas.drawCircle(centre, radius, fill);
    }
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.hairline;
    canvas.drawCircle(centre, radius - 0.5, edge);
    if (color != null) {
      return;
    }
    // The 「no colour」 slash, corner to corner inside the ring.
    final inset = radius * 0.7071; // cos 45°, so the ends meet the circle
    canvas.drawLine(
      centre + Offset(-inset, inset),
      centre + Offset(inset, -inset),
      edge..color = AppColors.textDim,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) => oldDelegate.color != color;
}

/// Opens the shared color picker anchored to [anchorContext]'s widget.
Future<void> showColorPickerPopup(
  BuildContext anchorContext, {
  required int? color,
  required ValueChanged<int> onChanged,
  int Function()? currentColorOf,
  VoidCallback? onNone,
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
    height: 252 + _noneRowHeight + ColorStatusBar.height,
    builder: (context, _) => _ColorPickerBody(
      initialColor: color,
      onChanged: onChanged,
      currentColorOf: currentColorOf,
      onNone: onNone,
    ),
  );
}

/// The 「없음」 row's own height, counted into the window so the wheel keeps
/// the 180 it was drawn at rather than being squeezed by a row below it.
const double _noneRowHeight = 28;

class _ColorPickerBody extends StatefulWidget {
  const _ColorPickerBody({
    required this.initialColor,
    required this.onChanged,
    required this.currentColorOf,
    required this.onNone,
  });

  final int? initialColor;
  final ValueChanged<int> onChanged;
  final int Function()? currentColorOf;
  final VoidCallback? onNone;

  @override
  State<_ColorPickerBody> createState() => _ColorPickerBodyState();
}

class _ColorPickerBodyState extends State<_ColorPickerBody> {
  /// The wheel's own colour. A swatch opened on 「없음」 has none, so the
  /// wheel starts where the app's other pickers start rather than on a
  /// colour nobody chose.
  late HSVColor _hsv = HSVColor.fromColor(
    Color(widget.initialColor ?? 0xFF808080),
  );

  void _apply(HSVColor next) {
    setState(() => _hsv = next);
    // Opaque: these are surfaces (paper, pasteboard), never stencils.
    widget.onChanged(next.toColor().withAlpha(0xFF).toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final currentColorOf = widget.currentColorOf;
    // ⛔No `Material` of its own (R4 #8). It drew elevation 8 where the two
    // other anchored windows drew 6 — one window in three costumes, until a
    // fourth arrived with none.
    // 🚨F-23 (유저 2026-08-24): 「지금 캔버스패널 색 선택시 왼쪽위에
    // **캔버스라고 써있거나 하는데, 그거 그냥 제거. 안뜨도록.** 오른쪽에도
    // **선택된 색 보여주는것도 어차피 버튼자체가 색 보여주는거니까 겹치니
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
    //
    // 🚨THE READOUT IS NOT INSIDE THE MARGIN (유저 2026-08-26: 「공통
    // 색선택창, 바탕색이나 **아래 디자인**이나 전체적으로 컬러휠패널이랑
    // **너무다름. 최대한 통일화**」). [ColorStatusBar] paints its own
    // background and a top border because it is a FOOTER — that is how
    // `ColorPickerPanel` mounts it, edge to edge under the picker. Wrapped
    // in the window's margin it became a floating grey patch with a stray
    // line over it, which is exactly the difference the user was pointing
    // at. So the margin belongs to the content above it, and the bar spans
    // the window like it spans the panel.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: AnchoredPopupText.bodyPadding.copyWith(bottom: 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _action(
                  keyValue: 'color-picker-use-current',
                  label: AppText.strings.colorUseCurrent,
                  onPressed: currentColorOf == null
                      ? null
                      : () =>
                            _apply(HSVColor.fromColor(Color(currentColorOf()))),
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
              SizedBox(height: _noneRowHeight, child: _noneRow()),
            ],
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
    );
  }

  /// 🚨A ROW OF ITS OWN, UNDER THE WHEEL — which is what `Q-f22-none` 답 1번
  /// actually says: 「색상환과 「현재 색 반영」이 있는 그 창 **아래**에
  /// 「없음」 버튼이 **한 줄 더** 생깁니다」.
  ///
  /// ⛔It spent one CI run beside 「현재 색 반영」 instead, because that read
  /// as the tidier layout. The window overflowed by 100px and the striped
  /// overflow bar went up in twelve tests — 「Use current color」 alone very
  /// nearly fills 248. **The drawn design was right and the tidier one was
  /// not mine to substitute** ([[build-what-was-drawn]]).
  ///
  /// ⛔THE SEAT IS ALWAYS THERE, live or dead (유저 2026-08-26: 「none버튼
  /// 신설해서 **캔버스알약쪽이랑 멤버쪽에 존재하도록**」, and 없다가 생기는
  /// UI 금지). The window is one window; a row that appears only on member
  /// lanes would make it two.
  Widget _noneRow() {
    final onNone = widget.onNone;
    return Align(
      alignment: Alignment.centerLeft,
      child: _action(
        keyValue: 'color-picker-none',
        label: AppText.strings.colorNone,
        onPressed: onNone == null
            ? null
            : () {
                onNone();
                unawaited(Navigator.of(context).maybePop());
              },
      ),
    );
  }

  Widget _action({
    required String keyValue,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ControlPressClaim(
      onPressed: onPressed,
      child: TextButton(
        key: ValueKey<String>(keyValue),
        onPressed: silentPress(onPressed),
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      ),
    );
  }
}
