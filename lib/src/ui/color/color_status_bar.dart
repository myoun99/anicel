import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/inline_numeric_field.dart';
import 'color_hex.dart';

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
  static const double height = 26;
  @override
  State<ColorStatusBar> createState() => _ColorStatusBarState();
}

/// Which readout is currently a text field; at most one at a time.
enum _Editing { none, hex, r, g, b }

class _ColorStatusBarState extends State<ColorStatusBar> {
  _Editing _editing = _Editing.none;
  static const TextStyle _readout = TextStyle(
    fontSize: 10,
    // The whole point of the fixed cells: a 3 and an 8 must be the same
    // width or the letters shuffle as the drag moves.
    fontFeatures: [FontFeature.tabularFigures()],
  );
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

  Widget _channel(String label, _Editing which, int value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: _readout.copyWith(color: AppColors.textDim)),
        SizedBox(
          // Three digits, always — the cell holds its width at 5 and at
          // 255 so the next label never shifts.
          width: 22,
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
              : GestureDetector(
                  key: ValueKey<String>('color-status-${label.toLowerCase()}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _editing = which),
                  child: Text(
                    '$value',
                    textAlign: TextAlign.right,
                    style: _readout,
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
    return Container(
      height: ColorStatusBar.height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            key: const ValueKey<String>('color-status-swatch'),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Color(widget.color),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 54,
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
                : GestureDetector(
                    key: const ValueKey<String>('color-status-hex'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _editing = _Editing.hex),
                    child: Text(colorHexOf(widget.color), style: _readout),
                  ),
          ),
          const Spacer(),
          _channel('R', _Editing.r, channels.r),
          const SizedBox(width: 4),
          _channel('G', _Editing.g, channels.g),
          const SizedBox(width: 4),
          _channel('B', _Editing.b, channels.b),
        ],
      ),
    );
  }
}
