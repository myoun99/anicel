import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../text/text_measure.dart';
import '../theme/app_theme.dart';
import '../widgets/inline_numeric_field.dart';
import 'color_hex.dart';
import '../input/control_press_claim.dart';

/// The colour window's bottom STATUS BAR (R10 R5, the user's layout B):
/// tabs / content / this, shared by every tab.
///
/// It is the window's one answer to "what colour am I on", so it does not
/// belong to the wheel or to the palette — switching tabs must not change
/// where you read the number.
///
/// Positions do not move as digits come and go. Each channel gets a fixed
/// three-digit cell and the numerals are tabular, so `R 226 G 75 B 74`
/// and `R 5 G 5 B 5` put their letters in the same places. A readout that
/// reflows while you drag is a readout you cannot watch.
///
/// HEX and each channel take a single TAP to type into — the app rule
/// (tap = pick or edit, double-tap = open).
class ColorStatusBar extends StatefulWidget {
  const ColorStatusBar({
    super.key,
    required this.color,
    required this.onColorChanged,
  });
  final int color;
  final ValueChanged<int> onColorChanged;

  /// The bar's height as drawn, at 1×.
  static const double height = 26;

  /// The bar where it is shown: [height] plus what one readout line grows
  /// by under the OS text size.
  ///
  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
  /// 따라 자란다」). The bar and every box that holds it — the RGB group's
  /// floor, the picker popup — ask here, so they cannot disagree about it.
  static double heightIn(BuildContext context) =>
      height + _measureIn(context).lineGrowthOf(_hexProbes.first);

  /// The width the readout takes laid out in full, padding included — what
  /// a box of a fixed width must at least give it.
  static double naturalWidthIn(BuildContext context) {
    final cells = _cellsIn(context);
    return 2 * _sidePadding +
        _swatch +
        _swatchGap +
        cells.hex +
        3 * (cells.label + cells.channel) +
        2 * _channelGap;
  }

  static const double _sidePadding = 8;
  static const double _swatch = 14;
  static const double _swatchGap = 6;
  static const double _channelGap = 4;

  static const TextStyle _readout = TextStyle(
    fontSize: 10,
    // The whole point of the fixed cells: a 3 and an 8 must be the same
    // width or the letters shuffle as the drag moves.
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Each hex at its widest: one glyph six times. A mixed hex is never
  /// wider than the widest of these.
  static final List<String> _hexProbes = [
    for (final glyph in '0123456789ABCDEF'.split('')) '#${glyph * 6}',
  ];
  static final List<String> _channelProbes = [
    for (final digit in '0123456789'.split('')) digit * 3,
  ];

  static TextMeasure _measureIn(BuildContext context) =>
      TextMeasure(context, DefaultTextStyle.of(context).style.merge(_readout));

  /// The cells' widths: the width they were drawn at, or what their widest
  /// value measures in the face and at the size the bar is shown in — the
  /// larger. 🔬At 1× in BIZ UDPGothic `#000000` is 56.5 wide, so the 54
  /// drawn for it wrapped its last digit onto a line the bar cut off.
  static ({double hex, double label, double channel}) _cellsIn(
    BuildContext context,
  ) {
    final measure = _measureIn(context);
    return (
      hex: math.max(54, measure.widest(_hexProbes).ceilToDouble()),
      label: measure.widest(const ['R ', 'G ', 'B ']).ceilToDouble(),
      channel: math.max(22, measure.widest(_channelProbes).ceilToDouble()),
    );
  }

  @override
  State<ColorStatusBar> createState() => _ColorStatusBarState();
}

/// Which readout is currently a text field; at most one at a time.
enum _Editing { none, hex, r, g, b }

class _ColorStatusBarState extends State<ColorStatusBar> {
  _Editing _editing = _Editing.none;
  static const TextStyle _readout = ColorStatusBar._readout;
  void _commitHex(String text) {
    setState(() => _editing = _Editing.none);
    final parsed = parseColorHex(text);
    if (parsed != null) {
      widget.onColorChanged(parsed);
    }
  }

  void _commitChannel(_Editing which, String text) {
    setState(() => _editing = _Editing.none);
    final typed = int.tryParse(text.trim());
    if (typed == null) {
      return;
    }
    final channels = colorChannels(widget.color);
    widget.onColorChanged(
      colorFromChannels(
        r: which == _Editing.r ? typed : channels.r,
        g: which == _Editing.g ? typed : channels.g,
        b: which == _Editing.b ? typed : channels.b,
      ),
    );
  }

  Widget _channel(String label, _Editing which, int value, double width) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: _readout.copyWith(color: AppColors.textDim)),
        SizedBox(
          // Three digits, always — the cell holds its width at 5 and at
          // 255 so the next label never shifts.
          width: width,
          child: _editing == which
              ? InlineNumericField(
                  fieldKey: ValueKey<String>(
                    'color-status-${label.toLowerCase()}-input',
                  ),
                  initialText: '$value',
                  textStyle: _readout,
                  // The readout it replaces is right-aligned, and this bar
                  // promises the digits do not move. A centred field would
                  // shift them the moment you tapped.
                  textAlign: TextAlign.right,
                  signed: false,
                  onSubmit: (text) => _commitChannel(which, text),
                  onCancel: () => setState(() => _editing = _Editing.none),
                )
              : ControlPressClaim(
                  onPressed: () => setState(() => _editing = which),
                  child: GestureDetector(
                    key: ValueKey<String>(
                      'color-status-${label.toLowerCase()}',
                    ),
                    behavior: HitTestBehavior.opaque,
                    onTap: silentPress(() => setState(() => _editing = which)),
                    child: Text(
                      '$value',
                      textAlign: TextAlign.right,
                      style: _readout,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final channels = colorChannels(widget.color);
    final cells = ColorStatusBar._cellsIn(context);
    return Container(
      height: ColorStatusBar.heightIn(context),
      padding: const EdgeInsets.symmetric(
        horizontal: ColorStatusBar._sidePadding,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            key: const ValueKey<String>('color-status-swatch'),
            width: ColorStatusBar._swatch,
            height: ColorStatusBar._swatch,
            // F-23: a chip that shows a colour is a circle, here as
            // everywhere ([ColorSlotPair] carries the whole reason).
            decoration: BoxDecoration(
              color: Color(widget.color),
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outlineVariant),
            ),
          ),
          const SizedBox(width: ColorStatusBar._swatchGap),
          SizedBox(
            width: cells.hex,
            child: _editing == _Editing.hex
                ? InlineNumericField(
                    fieldKey: const ValueKey<String>('color-status-hex-input'),
                    initialText: colorHexOf(widget.color).substring(1),
                    textStyle: _readout,
                    textAlign: TextAlign.left,
                    // A–F are digits here, so the field takes text.
                    keyboardType: TextInputType.text,
                    onSubmit: _commitHex,
                    onCancel: () => setState(() => _editing = _Editing.none),
                  )
                : ControlPressClaim(
                    onPressed: () => setState(() => _editing = _Editing.hex),
                    child: GestureDetector(
                      key: const ValueKey<String>('color-status-hex'),
                      behavior: HitTestBehavior.opaque,
                      onTap: silentPress(
                        () => setState(() => _editing = _Editing.hex),
                      ),
                      child: Text(colorHexOf(widget.color), style: _readout),
                    ),
                  ),
          ),
          const Spacer(),
          _channel('R', _Editing.r, channels.r, cells.channel),
          const SizedBox(width: ColorStatusBar._channelGap),
          _channel('G', _Editing.g, channels.g, cells.channel),
          const SizedBox(width: ColorStatusBar._channelGap),
          _channel('B', _Editing.b, channels.b, cells.channel),
        ],
      ),
    );
  }
}
