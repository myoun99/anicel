import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/canvas_viewport.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart';

/// One place on a sheet whose typed text a tap edits in place.
class SheetTextTarget {
  const SheetTextTarget({
    required this.keyValue,
    required this.box,
    required this.textRect,
    required this.text,
    required this.style,
    required this.onCommitted,
    this.multiline = false,
    this.centred = false,
  });

  /// The tap zone's key.
  final String keyValue;

  /// What a tap on the paper hits, and what the editing outline marks — in
  /// paper units.
  final Rect box;

  /// Where the printed words sit: the field lands exactly on them, so the
  /// editing happens on the printed glyphs.
  final Rect textRect;

  /// The words as they stand.
  final String text;

  /// The face the sheet PRINTS these words in, its size in paper units: the
  /// field types in it, so the words break while typing where they will
  /// break on the paper.
  final TextStyle style;

  /// Called with the new words — only when they changed.
  final ValueChanged<String> onCommitted;

  final bool multiline;
  final bool centred;
}

/// Tap-to-edit on a sheet: a tap on one of [targets] swaps in a TextField
/// right over it under the panel's viewport — editing in place on the paper.
///
/// ONE in-place editor for the sheets: the timesheet's header boxes and
/// memo band, and the conte's ACTION (유저 2026-09-25: 「액션은
/// 콘티프리뷰에서 해당 칸 누르면 텍스트 편집할수있게」). It was the
/// timesheet's own layer; the conte's ACTION had a field that mounted under
/// the page instead.
///
/// The layer sits UNDER the ink layer in a sheet's stack, so the sheet's
/// brush switch is the mode switch: brush on → the pen draws (taps
/// included, like a pen on paper); brush off → taps edit text.
class SheetTextEditLayer extends StatefulWidget {
  const SheetTextEditLayer({
    super.key,
    required this.targets,
    required this.viewport,
    required this.fieldKey,
    required this.barrierKey,
  });

  final List<SheetTextTarget> targets;

  /// The live panel viewport — the transform the sheet's painter applies.
  final CanvasViewport viewport;

  /// The editing field's key and the tap-away barrier's.
  final String fieldKey;
  final String barrierKey;

  @override
  State<SheetTextEditLayer> createState() => _SheetTextEditLayerState();
}

class _SheetTextEditLayerState extends State<SheetTextEditLayer> {
  SheetTextTarget? _target;
  TextEditingController? _controller;
  FocusNode? _focusNode;
  bool _cancelled = false;

  @override
  void dispose() {
    _disposeEditor();
    super.dispose();
  }

  void _disposeEditor() {
    _controller?.dispose();
    _controller = null;
    _focusNode?.dispose();
    _focusNode = null;
  }

  Rect _onScreen(Rect paper) {
    final viewport = widget.viewport;
    return Rect.fromLTWH(
      viewport.panX + viewport.zoom * paper.left,
      viewport.panY + viewport.zoom * paper.top,
      viewport.zoom * paper.width,
      viewport.zoom * paper.height,
    );
  }

  void _beginEdit(SheetTextTarget target) {
    _disposeEditor();
    _cancelled = false;
    _controller = TextEditingController(text: target.text);
    _focusNode = FocusNode();
    _focusNode!.addListener(() {
      if (!(_focusNode?.hasFocus ?? false)) {
        _commit();
      }
    });
    setState(() => _target = target);
  }

  void _commit() {
    final target = _target;
    final controller = _controller;
    if (!mounted || target == null || controller == null) {
      return;
    }
    final text = controller.text.trim();
    final changed = !_cancelled && text != target.text.trim();
    setState(() => _target = null);
    if (changed) {
      target.onCommitted(text);
    }
  }

  void _cancel() {
    _cancelled = true;
    setState(() => _target = null);
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Stack(
      children: [
        if (target == null)
          for (final each in widget.targets) _tapZone(each)
        else ...[
          // Tap-away barrier: clicking anywhere else commits the edit. A
          // claimed press like the zones (H24): the canvas surface under the
          // sheet takes the arena on the first movement, and a plain tap
          // recogniser lost its tap to it whenever the hand moved.
          Positioned.fill(
            child: ControlPressClaim(
              onPressed: () => _focusNode?.unfocus(),
              child: GestureDetector(
                key: ValueKey<String>(widget.barrierKey),
                behavior: HitTestBehavior.opaque,
                onTap: silentPress(() => _focusNode?.unfocus()),
              ),
            ),
          ),
          ..._editor(target),
        ],
      ],
    );
  }

  Widget _tapZone(SheetTextTarget target) {
    final rect = _onScreen(target.box);
    void onTap() => _beginEdit(target);
    return Positioned(
      key: ValueKey<String>(target.keyValue),
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: ControlPressClaim(
        onPressed: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: silentPress(onTap),
        ),
      ),
    );
  }

  /// The in-place editor, in two parts: an outline over the whole box (the
  /// printed labels stay visible through it) and the TextField on the
  /// printed words' exact place.
  List<Widget> _editor(SheetTextTarget target) {
    final box = _onScreen(target.box);
    final text = _onScreen(target.textRect);
    return [
      Positioned(
        left: box.left,
        top: box.top,
        width: box.width,
        height: box.height,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
      ),
      Positioned(
        left: text.left,
        top: text.top,
        width: text.width,
        height: text.height,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _cancel();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          // Paper-coloured backing hides only the printed glyphs the field
          // replaces (the live text sits exactly on top of them). White:
          // both sheets this serves print on white (timesheet H4, conte).
          // ↩️It was the timesheet's old stock tint, which H4 retired.
          child: Container(
            color: const Color(0xFFFFFFFF),
            alignment: Alignment.topLeft,
            // H24: a drag in the field selects text — the field's own verb —
            // so it takes the STRONG claim, and the canvas surface under the
            // sheet stands down for it rather than holding the drag.
            child: DragVerbClaim(
              child: TextField(
                key: ValueKey<String>(widget.fieldKey),
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: target.multiline ? null : 1,
                expands: target.multiline,
                onSubmitted: target.multiline ? null : (_) => _commit(),
                textAlign: target.centred ? TextAlign.center : TextAlign.start,
                style: target.style.copyWith(
                  fontSize:
                      (target.style.fontSize ?? 14) * widget.viewport.zoom,
                ),
                decoration: const InputDecoration(
                  // Bare: this field sits ON the printed sheet (paper
                  // white), so it opts out of the app-wide dark filled box.
                  filled: false,
                  isCollapsed: true,
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
