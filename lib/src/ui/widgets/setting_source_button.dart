import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../theme/app_theme.dart';
import '../theme/disabled_ink.dart';
import '../theme/text_on_ground.dart' show textOnColor;
import 'app_tooltip.dart';

/// The button at a settings row's END that says whether anything moves the
/// setting and opens the window that sets what does — the curve button
/// beside size, opacity and the rest (BB-3), and the one beside 각도 (F-176-
/// Q6, 유저 2026-10-21 「클튜처럼 — 각도 옆 버튼 하나」). Clip Studio gives
/// every such setting the same button, and so does this: one well, one
/// edge, one way to say "off".
class SettingSourceButton extends StatelessWidget {
  const SettingSourceButton({
    super.key,
    required this.keyValue,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.glyph,
    this.enabled = true,
  });

  /// Widget key string for the button ('brush-tool-pressure-size').
  final String keyValue;
  final String tooltip;

  /// Whether anything moves the setting — the accent edge and ink.
  final bool active;

  /// False dims the button and refuses the press (TP2): the tools that take
  /// no pressure keep the control in place and greyed rather than losing it,
  /// so the row never changes shape and "does pressure apply here?" has a
  /// visible answer.
  final bool enabled;

  /// Opens the window, anchored to the button's own [BuildContext].
  final void Function(BuildContext anchor) onPressed;

  /// The mark inside the well, painted in the ink it is handed.
  final CustomPainter Function(Color ink) glyph;

  /// The OFF state's ink, mark and edge together.
  ///
  /// 유저, R6 #2: 「필압아이콘 필압설정안하면 x잖아. 지금 진하니까 불투명도
  /// 낮은 하얀색 x로」 · 「테두리도 그럼 흐리게하자」.
  ///
  /// ⚠️It is NOT [AppColors.textDim], which is what it used to be and is the
  /// reason it read as loud: that token is 0xFF9DA2A6 against body text's
  /// 0xFFB4B8BB — a "dim" that is only dim beside white, and BRIGHTER than
  /// most of the row it sits in. The one control whose whole message is
  /// "this setting is doing nothing" was the strongest mark on the line.
  ///
  /// A transparent white — the ink the chrome takes, black on the light
  /// palette (I-143) — rather than another opaque grey, so it dims
  /// against whatever surface the button lands on — the tool settings, the
  /// brush panel and the top strip are three different greys.
  static Color get offInk => textOnColor(AppColors.surface).withAlpha(0x4D);
  static Color get _offEdge =>
      textOnColor(AppColors.surface).withAlpha(0x1A);

  /// The mark's box, and the padding around it. Named because [slotWidth]
  /// is derived from them and a row reserving the slot must not re-derive
  /// either.
  /// ⚠️Two doubles rather than a `Size`: `Size.width` is not a constant
  /// expression, and [slotWidth] has to be one.
  ///
  /// ↩️The mark was 22 wide. 유저 2026-10-18 (I-34, the canvas's brush
  /// pill): 「압력버튼 특히 그냥 정사각형이어도 문제없겟는데」 — square, so
  /// the button is as wide as the pill's bars are thick (20), and as it is
  /// one button, the strip's, the settings rows' and the angle's are square
  /// with it.
  static const double _glyphWidth = 14;
  static const double _glyphHeight = 14;
  static const Size _glyphSize = Size(_glyphWidth, _glyphHeight);
  static const double _padding = 3;

  /// How wide this button stands in a settings row.
  ///
  /// ⚠️The border is NOT in the sum: a [DecoratedBox] sizes itself to its
  /// child and paints the shape over that box, so the stroke costs no
  /// layout width. (A `Container` with the same decoration would differ —
  /// it applies `decoration.padding`.)
  ///
  /// 🚨A ROW WITHOUT ONE OF THESE RESERVES THIS MUCH ANYWAY (유저 09-08:
  /// 「슬라이더 크기는 항상 고정되도록. 압력버튼없으면 그냥 빈공간으로」).
  /// Two of the settings panel's twenty sliders carried a button, and before
  /// this the other eighteen ate the space — the same control at two widths
  /// in one panel, which is the 「자리는 항상 예약하고 내용만 바꾼다」 rule
  /// read backwards.
  ///
  /// ⚠️Kept honest by `pressure_curve_button_slot_test`, which lays the real
  /// buttons out and fails if their width stops matching this number.
  static const double slotWidth = _glyphWidth + _padding * 2;

  /// How wide the windows these buttons open stand. The curve window's
  /// width was frozen at 248 (유저 확정 2026-09-08 ⑧); the angle's opens
  /// from the same button and stands as wide.
  static const double windowWidth = 248;

  /// Spelled out rather than left to [BorderSide]'s default, so the note in
  /// [slotWidth] about the stroke costing no width names a real number.
  static const double _borderWidth = 1;

  @override
  Widget build(BuildContext context) {
    // Disabled, the well dims by the same 40% the field slider dims to, so a
    // disabled group reads as one thing rather than as three different
    // greys — [disabledInkOpacity] is where that figure lives now.
    //
    // 🪦It used to be `Opacity(0.4)` around the whole button, and that is a
    // compositing boundary: it cost the panel it sits in its bake, on every
    // frame (유저 확정 2026-09-22, 보드
    // `a-disabled-bar-dims-without-a-layer-Q1`). The well's own two colours
    // carry the dimming now.
    final lit = enabled && active;
    return AppTooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: ControlPressClaim(
          onPressed: enabled ? () => onPressed(context) : null,
          child: InkWell(
            mouseCursor: AppCursors.press,
            key: ValueKey<String>(keyValue),
            customBorder: AppShapes.container(AppShapes.wellRadius),
            onTap: silentPress(enabled ? () => onPressed(context) : null),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: AppShapes.container(
                  AppShapes.wellRadius,
                  side: BorderSide(
                    color: dimmedIfDisabled(
                      lit ? AppColors.accent : _offEdge,
                      enabled: enabled,
                    ),
                    width: _borderWidth,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_padding),
                child: CustomPaint(
                  size: _glyphSize,
                  painter: glyph(
                    dimmedIfDisabled(
                      lit ? AppColors.accent : offInk,
                      enabled: enabled,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The OFF mark inside a [SettingSourceButton]: an X.
///
/// 유저, R4 #9: 필압 적용 안 했을 때의 ui, 지금 버튼이 상단정렬된 직선의
/// 그래프가 그대로 보이는데, 그게 아니라 해당 버튼에 그래프 말고 x 이렇게 둬서
/// 필압 적용 안 되어 있다는 거 알기 쉽게.
///
/// An X is not a graph at all, which is exactly the point: OFF is a
/// different KIND of state, not a shape the setting can take.
void paintSettingOffMark(Canvas canvas, Size size, Paint paint) {
  // Inset, so the X is a mark inside the button rather than a cross that
  // touches its border on all four sides.
  const inset = 3.0;
  final box = Rect.fromLTRB(
    inset,
    inset,
    size.width - inset,
    size.height - inset,
  );
  canvas.drawLine(box.topLeft, box.bottomRight, paint);
  canvas.drawLine(box.topRight, box.bottomLeft, paint);
}

/// The stroke both buttons' marks are drawn with.
Paint settingGlyphPaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.2
  // Round ends so the X's four arms do not read as chipped at this size.
  ..strokeCap = StrokeCap.round;

/// A row's NAME that is its own toggle, in the windows these buttons open —
/// 「선택 표시는 색상만」, so on and off differ in ink and in nothing else.
/// Fires on release inside it: these are not rail rows, so not a tap-down.
class SettingSourceName extends StatelessWidget {
  const SettingSourceName({
    super.key,
    required this.keyValue,
    required this.label,
    required this.lit,
    required this.onPressed,
  });

  final String keyValue;
  final String label;
  final bool lit;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ControlPressClaim(
    onPressed: onPressed,
    child: InkWell(
      mouseCursor: AppCursors.press,
      key: ValueKey<String>(keyValue),
      customBorder: AppShapes.container(AppShapes.wellRadius),
      onTap: silentPress(onPressed),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: lit ? AppColors.accent : SettingSourceButton.offInk,
          ),
        ),
      ),
    ),
  );
}
