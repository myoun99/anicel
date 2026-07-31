import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../text/full_width_numerals.dart';

/// A numeric READOUT you can operate (UI-R18 #21, the shared vocabulary
/// for the canvas angle/zoom texts and any future value label):
/// - horizontal DRAG adjusts the value ([unitsPerPixel] per pixel,
///   reported as whole-unit deltas through [onDragDelta]);
/// - a single TAP swaps to an inline numeric field (Enter/tap-out commits
///   through [onEditSubmit], Escape cancels).
///
/// R10: the field used to open on a DOUBLE tap, which held every tap on
/// this label for the double-tap window — ~300ms of nothing happening,
/// which is what the user asked to be rid of everywhere. It cost nothing
/// to give up: there was no single-tap action to collide with, and the
/// app's rule is now one line — a tap edits a number, a double tap opens
/// a thing. Tap and drag do not fight: past the slop the drag takes the
/// arena and the tap is refused; release without moving and it is a tap.
class DragValueLabel extends StatefulWidget {
  const DragValueLabel({
    super.key,
    required this.keyValue,
    required this.text,
    required this.onDragDelta,
    required this.onEditSubmit,
    this.unitsPerPixel = 1.0,
    this.width = 48,
    this.tooltip,
    this.textStyle,
    this.inputKeyValue,
  });

  /// Stable widget key base (`keyValue` label / `keyValue`-input).
  final String keyValue;

  /// Overrides the inline editor's key (hosts with pre-existing key
  /// contracts); defaults to `keyValue`-input.
  final String? inputKeyValue;

  /// The resting readout ('90%', '-15°', …).
  final String text;

  /// Whole-unit drag steps (sign follows the drag direction).
  final ValueChanged<double> onDragDelta;

  /// Receives the raw typed text on commit; the owner parses/clamps.
  final ValueChanged<String> onEditSubmit;

  final double unitsPerPixel;
  final double width;
  final String? tooltip;
  final TextStyle? textStyle;

  @override
  State<DragValueLabel> createState() => _DragValueLabelState();
}

class _DragValueLabelState extends State<DragValueLabel> {
  final TextEditingController _editController = TextEditingController();
  bool _editing = false;
  double _pendingUnits = 0;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _beginEdit() {
    _editController.text = widget.text.replaceAll(RegExp(r'[^0-9.\-]'), '');
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _editController.text.length,
    );
    setState(() => _editing = true);
  }

  void _commitEdit() {
    if (!_editing) {
      return;
    }
    final text = _editController.text.trim();
    setState(() => _editing = false);
    if (text.isNotEmpty) {
      widget.onEditSubmit(text);
    }
  }

  void _dragBy(double dx) {
    _pendingUnits += dx * widget.unitsPerPixel;
    final whole = _pendingUnits.truncateToDouble();
    if (whole != 0) {
      _pendingUnits -= whole;
      widget.onDragDelta(whole);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: widget.width,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() => _editing = false);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: ValueKey<String>(
              widget.inputKeyValue ?? '${widget.keyValue}-input',
            ),
            controller: _editController,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            // R9 #15: 全角 numerals become half-width as they are typed.
            inputFormatters: halfWidthNumerals,
            style: widget.textStyle ?? const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              // Bare: the editor replaces the label in place, so it opts
              // out of the app-wide filled box.
              filled: false,
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _commitEdit(),
            onTapOutside: (_) => _commitEdit(),
          ),
        ),
      );
    }
    final label = MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: ValueKey<String>(widget.keyValue),
        behavior: HitTestBehavior.opaque,
        onTap: _beginEdit,
        onHorizontalDragStart: (_) => _pendingUnits = 0,
        onHorizontalDragUpdate: (details) => _dragBy(details.delta.dx),
        child: SizedBox(
          width: widget.width,
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: widget.textStyle ?? const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? label : Tooltip(message: tooltip, child: label);
  }
}
