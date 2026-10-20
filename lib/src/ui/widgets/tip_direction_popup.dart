import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/brush_tip_rotation_mode.dart';
import '../repaint_props.dart';
import '../text/app_strings.dart' show AppText;
import 'anchored_popup.dart';
import 'field_slider.dart';
import 'setting_source_button.dart';

/// 向き — the base a tip turns from and its random turn — as Clip Studio
/// keeps it: behind ONE button beside the angle, the way size and the rest
/// keep their curves (F-176-Q6, 유저 2026-10-21 「클튜처럼 — 각도 옆 버튼
/// 하나」). ↩️The base and the random turn were two rows of their own under
/// the angle, and 「방향」 read as a setting apart from it (유저 10-20 「방향은
/// 뭐지? 각도랑 다른건가」).
typedef TipDirection = ({BrushTipRotationMode base, double random});

/// The button in the angle row's end slot: lit while a base turns the tip
/// or the random turn is up, the off mark while the angle stands alone.
class TipDirectionButton extends StatelessWidget {
  const TipDirectionButton({
    super.key,
    required this.direction,
    required this.onChanged,
  });

  final TipDirection direction;

  /// Every change hands back the whole setting — see [showTipDirectionPopup].
  final ValueChanged<TipDirection> onChanged;

  static const String keyValue = 'brush-tool-direction-button';

  @override
  Widget build(BuildContext context) {
    final active =
        direction.base != BrushTipRotationMode.fixed || direction.random > 0;
    return SettingSourceButton(
      keyValue: keyValue,
      tooltip: AppText.strings.brTipRotation,
      active: active,
      onPressed: (anchor) => showTipDirectionPopup(
        anchor,
        initial: direction,
        onChanged: onChanged,
      ),
      glyph: (ink) => _DialPainter(on: active, color: ink),
    );
  }
}

/// A dial with its needle while something turns the tip; the off mark
/// while nothing does.
class _DialPainter extends CustomPainter with RepaintOnProps {
  const _DialPainter({required this.on, required this.color});

  final bool on;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = settingGlyphPaint(color);
    if (!on) {
      paintSettingOffMark(canvas, size, paint);
      return;
    }
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    canvas.drawCircle(center, radius, paint);
    const needle = -math.pi / 4;
    canvas.drawLine(
      center,
      center + Offset(math.cos(needle), math.sin(needle)) * radius,
      paint,
    );
  }

  @override
  Object get props => (on, color);
}

/// The bases in the order Clip Studio lists them: なし · ペンの向き ·
/// 線の方向.
///
/// ⚠️Every base is here — `the_tip_direction_window_test` fails on one left
/// out, so a base added to [BrushTipRotationMode] cannot go unoffered.
const List<BrushTipRotationMode> tipDirectionBases = [
  BrushTipRotationMode.fixed,
  BrushTipRotationMode.penTilt,
  BrushTipRotationMode.direction,
];

/// A base's name, as the window offers it.
String tipDirectionBaseName(BrushTipRotationMode base) => switch (base) {
  BrushTipRotationMode.fixed => AppText.strings.brRotationFixed,
  BrushTipRotationMode.direction => AppText.strings.brRotationDirection,
  BrushTipRotationMode.penTilt => AppText.strings.brRotationPenTilt,
};

const double _headerHeight = 24;
const double _rowHeight = FieldSlider.defaultHeight;
const double _rowGap = 4;
const double _sectionGap = 8;

/// 🚨The declared height and the drawn height are the same number BY
/// CONSTRUCTION: this sums exactly the boxes [_TipDirectionEditor] stacks.
double get _windowHeight =>
    AnchoredPopupText.bodyPadding.vertical +
    _headerHeight +
    AnchoredPopupText.titleGap +
    tipDirectionBases.length * _rowHeight +
    (tipDirectionBases.length - 1) * _rowGap +
    _sectionGap +
    _rowHeight;

/// Shows the angle's 向き window next to [anchor]'s widget.
///
/// 🚨[onChanged] gets THE WHOLE SETTING every time — the base and the
/// random turn together — for the reason [showPressureCurvePopup] gives: the
/// closure is the button's, built over the tool state as it stood then, and
/// a write of one half off that stale base would put the other half back.
Future<void> showTipDirectionPopup(
  BuildContext anchor, {
  required TipDirection initial,
  required ValueChanged<TipDirection> onChanged,
}) => showAnchoredPopup<void>(
  anchor,
  label: 'tip-direction-popup',
  width: SettingSourceButton.windowWidth,
  height: _windowHeight,
  builder: (context, _) =>
      _TipDirectionEditor(initial: initial, onChanged: onChanged),
);

class _TipDirectionEditor extends StatefulWidget {
  const _TipDirectionEditor({required this.initial, required this.onChanged});

  final TipDirection initial;
  final ValueChanged<TipDirection> onChanged;

  @override
  State<_TipDirectionEditor> createState() => _TipDirectionEditorState();
}

class _TipDirectionEditorState extends State<_TipDirectionEditor> {
  late TipDirection _draft = widget.initial;

  void _set(TipDirection next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('tip-direction-popup'),
    padding: AnchoredPopupText.bodyPadding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: AnchoredPopupHeader(
            title:
                '${AppText.strings.brAngle} — '
                '${AppText.strings.brTipRotation}',
          ),
        ),
        const SizedBox(height: AnchoredPopupText.titleGap),
        // ONE base at a time: the lit name is the one the tip turns from.
        for (final (i, base) in tipDirectionBases.indexed) ...[
          if (i > 0) const SizedBox(height: _rowGap),
          SizedBox(
            height: _rowHeight,
            child: SettingSourceName(
              keyValue: 'brush-tool-rotation-${base.name}',
              label: tipDirectionBaseName(base),
              lit: _draft.base == base,
              onPressed: () => _set((base: base, random: _draft.random)),
            ),
          ),
        ],
        const SizedBox(height: _sectionGap),
        SizedBox(
          height: _rowHeight,
          child: FieldSlider(
            key: const ValueKey<String>('brush-tool-angle-jitter-slider'),
            label: AppText.strings.curveSourceRandom,
            value: _draft.random,
            min: 0,
            max: 1,
            unit: '%',
            displayScale: 100,
            onChanged: (value) => _set((base: _draft.base, random: value)),
          ),
        ),
      ],
    ),
  );
}
