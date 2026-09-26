import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/canvas_viewport.dart';
import '../input/control_press_claim.dart';

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

  /// What a tap on the paper hits, in paper units.
  final Rect box;

  /// Where the words are printed — the rect the printer sets them in, its
  /// width the width they wrap at: the field is laid out in it, so the
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

  /// 🚨THE EDITOR IS THE PRINTED WORDS, EDITABLE (F-188, 유저 2026-09-26:
  /// 「액션란 메모 시작할때 ui가 써져있는거랑 다름. 뭔가 이동되는느낌?
  /// 최대한 안움직이게하고 ui심플하게. 지금 실루엣 라인이 두개나있음」):
  /// the field sets the words the page printed on the glyphs it printed
  /// them with, so opening it changes nothing on the page but the caret.
  ///
  /// The field is laid out ON THE PAPER — at the printed size, the printed
  /// width, no strut and no text scaling, the printer's own layout — and
  /// shown through the panel's view as the paper is. The printed words are
  /// hidden only where they were printed; what the field types replaces
  /// them.
  ///
  /// ↩️It set the words at the SCREEN size with the field's default strut,
  /// which forces every line to the face's own height: lines the printer
  /// sets at their natural heights (a Korean line is set in the fallback
  /// face) moved as the editor opened. And it drew an accent outline round
  /// the box, beside the sheet's own lines.
  List<Widget> _editor(SheetTextTarget target) {
    final paper = target.textRect;
    return [
      Positioned.fromRect(
        rect: _onScreen(_printedWords(target)),
        child: const IgnorePointer(
          // White: both sheets this serves print on white (timesheet H4,
          // conte). ↩️It was the timesheet's old stock tint, which H4
          // retired.
          child: ColoredBox(color: Color(0xFFFFFFFF)),
        ),
      ),
      Positioned.fromRect(
        rect: _onScreen(
          Rect.fromLTWH(
            paper.left,
            paper.top,
            paper.width + _caretRoom,
            paper.height,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            // The field sets its words that much narrower than it is, for
            // the caret after the last glyph; this much wider, it breaks
            // them where the printer does.
            width: paper.width + _caretRoom,
            height: paper.height,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _cancel();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              // H24: a drag in the field selects text — the field's own
              // verb — so it takes the STRONG claim, and the canvas surface
              // under the sheet stands down for it rather than holding the
              // drag.
              child: DragVerbClaim(
                child: MediaQuery.withNoTextScaling(
                  child: TextField(
                    key: ValueKey<String>(widget.fieldKey),
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLines: target.multiline ? null : 1,
                    expands: target.multiline,
                    onSubmitted: target.multiline ? null : (_) => _commit(),
                    textAlign: target.centred
                        ? TextAlign.center
                        : TextAlign.start,
                    // The printer's style and nothing else: a field lays
                    // its words out in the theme's input style with this
                    // one over it, and whatever this leaves unset — the
                    // theme's letter spacing, for one — the printer never
                    // had.
                    style: target.style.copyWith(
                      inherit: false,
                      // The baseline a painter sets words on, which a
                      // style that inherits nothing has to name.
                      textBaseline:
                          target.style.textBaseline ?? TextBaseline.alphabetic,
                    ),
                    strutStyle: StrutStyle.disabled,
                    cursorWidth: _cursorWidth,
                    decoration: const InputDecoration(
                      // Bare: this field sits ON the printed sheet (paper
                      // white), so it opts out of the app-wide dark filled
                      // box.
                      filled: false,
                      isCollapsed: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// The caret's width, in paper units.
  static const double _cursorWidth = 2;

  /// What a field keeps free after its words for the caret —
  /// `RenderEditable`'s one-pixel gap and the caret's width — which it
  /// takes off the width it breaks its lines at.
  static const double _caretRoom = 1 + _cursorWidth;

  /// Where [target]'s words stand printed, in paper units: the printer's
  /// layout of them in [SheetTextTarget.textRect], and a paper unit round
  /// it for the edges of the glyphs.
  Rect _printedWords(SheetTextTarget target) {
    final slot = target.textRect;
    final painter = TextPainter(
      text: TextSpan(text: target.text, style: target.style),
      textAlign: target.centred ? TextAlign.center : TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: target.multiline ? null : 1,
    )..layout(maxWidth: slot.width);
    final left = target.centred
        ? slot.left + (slot.width - painter.width) / 2
        : slot.left;
    final printed = Rect.fromLTWH(
      left,
      slot.top,
      painter.width,
      painter.height,
    );
    painter.dispose();
    return printed.inflate(1).intersect(slot.inflate(1));
  }
}
