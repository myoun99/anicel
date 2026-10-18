import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/input/modifier_keys.dart';
import '../../text/canvas_letter_style.dart';
import '../../text/cel_text_layout.dart';
import 'cel_text_editing_controller.dart';
import 'cel_text_stage.dart';

/// THE FIELD THE KEYBOARD TYPES INTO while a text's letters are held
/// (R9-rest) — there for the keyboard and never seen.
///
/// A real field, so that everything a keyboard does to a field is done to
/// the text with nothing written again: an IME composes into it (on Windows
/// the IME is on only while one has the keyboard — `KeyboardImeSwitch`),
/// the app's shortcuts stand down for it (`focusedTextField`), and the
/// arrows, the selection keys, the clipboard and the line break are the
/// field's own.
///
/// 🚨IT IS OFFSTAGE: laid out and focused, never painted, never pressed.
/// The letters on screen are the cel's — the text's plate laid into its
/// cel, at the cel's own resolution and under whatever is above it — which
/// is what the text will BE (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑
/// 절대로 다르면 안 되」). A field drawn over the canvas would be sharp
/// letters on top of everything, and neither.
///
/// It is laid out ON THE ARTWORK, where the text is — the very spans, the
/// very width, no strut and no text scaling (the sheet's in-place editor
/// learned each of these, `SheetTextEditLayer`) — and stood under the
/// panel's view of it, so the IME composes beside the caret and the field
/// breaks its lines where the canvas does.
///
/// 🧭A TEXT IN COLUMNS HAS ITS FIELD LYING DOWN THEM. A field sets lines;
/// turned a quarter clockwise about the block's top right corner, its
/// first line runs down the first column and its next line is to the left
/// — near enough to where the letters are that the IME's window opens
/// beside them. Near enough, not exactly: the field breaks its lines by
/// the letters' widths, the columns by the table's cells.
///
/// 🧭AND A FIELD ALIGNS ALL ITS LINES BY ONE ALIGNMENT, where a text's
/// paragraphs are aligned each its own way (text-letters-lean-and-underline
/// ④): it is aligned as the paragraph the caret is in, where the IME looks.
///
/// So the arrows ACROSS the lines — up and down in lines, left and right
/// in columns — are answered here, off the text as it is shown ([_arrow]),
/// and never left to the field's own idea of the line above.
class CelTextField extends StatelessWidget {
  const CelTextField({
    super.key,
    required this.letters,
    required this.focusNode,
    required this.stage,
    required this.shown,
    required this.onEscape,
  });

  final CelTextEditingController letters;
  final FocusNode focusNode;
  final CelTextStage stage;

  /// The text as it is shown — where the field stands.
  final CelTextLayout shown;

  /// Esc lets go of the letters; what was typed stays.
  final VoidCallback onEscape;

  /// `RenderEditable`'s gap after the last letter, with a caret of no
  /// width: a field takes it off the width it breaks its lines at.
  static const double _caretGap = 1;

  @override
  Widget build(BuildContext context) => Transform(
    transform: _frame,
    child: Offstage(
      child: MediaQuery.withNoTextScaling(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _key,
          child: Actions(
            // The field's own steps back hold letters alone; the text's
            // hold how each was set ([CelTextEditingController]).
            actions: <Type, Action<Intent>>{
              UndoTextIntent: CallbackAction<UndoTextIntent>(
                onInvoke: (_) => letters.undo(),
              ),
              RedoTextIntent: CallbackAction<RedoTextIntent>(
                onInvoke: (_) => letters.redo(),
              ),
            },
            child: _field(),
          ),
        ),
      ),
    ),
  );

  /// The field itself, its letters set as the canvas sets them: the very
  /// spans, no strut, and for a box the width the canvas sets its lines at
  /// ([celTextSetWidth]).
  Widget _field() {
    final content = letters.content;
    final wrapWidth = celTextSetWidth(content);
    // A field with no caret yet (−1, a field's own 「no selection」) is
    // aligned as its first paragraph.
    final caret = math.max(letters.selection.extentOffset, 0);
    final field = EditableText(
      key: const ValueKey<String>('cel-text-field'),
      controller: letters,
      focusNode: focusNode,
      style: celTextFieldSpan(
        content,
        nextLetterStyle: letters.nextLetterStyle,
      ).style!,
      // ⛔No strut: a field's own forces every line to one height, and the
      // canvas sets each line as tall as its letters.
      strutStyle: StrutStyle.disabled,
      cursorColor: const Color(0x00000000),
      backgroundCursorColor: const Color(0x00000000),
      showCursor: false,
      cursorWidth: 0,
      maxLines: null,
      // A text that grows is as wide as its lines, and is not forced to the
      // line it is given. A box sets its lines across its whole width, as
      // the canvas does — a short line stands where the alignment puts it
      // IN THE BOX, and that is where the IME is told the caret is — and
      // it is the width it is handed below that does that, not this.
      forceLine: false,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      // As the paragraph the caret is in is aligned. A field aligns every
      // line of it by one alignment, and the IME's window opens where the
      // FIELD puts the caret — so beside the letters as the canvas sets
      // them, in that paragraph. The arrows across the lines are answered
      // off the text as shown, every paragraph as it is set ([_arrow]).
      textAlign: canvasTextAlign(
        content.paragraphs[content.paragraphAt(caret)].align,
      ),
      textDirection: TextDirection.ltr,
      rendererIgnoresPointer: true,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      stylusHandwritingEnabled: false,
      // 🚨A PRESS OUTSIDE THIS FIELD DOES NOT TAKE THE KEYBOARD FROM IT.
      // Every press is outside it — it is never on screen — and a stock
      // field lets go of the keyboard on one: the click that moves the
      // caret would hand the next key to the app's shortcuts, and 「b」
      // would be the brush. When the letters are let go of is the text
      // tool's to say (the press table), and it says so by unmounting this.
      onTapOutside: _keepTheKeyboard,
      onTapUpOutside: _keepTheKeyboard,
    );
    return wrapWidth == null
        ? field
        : SizedBox(width: wrapWidth + _caretGap, child: field);
  }

  /// The text's own frame — its letters' block — on the panel: from the
  /// block's top left corner along its lines, as wide as their letters are
  /// drawn ([CelTextContent.letterWidth]), or — in columns — from its top
  /// right corner down them.
  Matrix4 get _frame {
    final content = letters.content;
    final frame = stage.artworkOnPanel
      ..translateByDouble(content.anchor.x, content.anchor.y, 0, 1)
      ..rotateZ(content.rotationDegrees * math.pi / 180);
    if (content.vertical) {
      return frame
        ..translateByDouble(shown.block.right, shown.block.top, 0, 1)
        ..rotateZ(math.pi / 2);
    }
    return frame
      ..translateByDouble(shown.block.left, shown.block.top, 0, 1)
      ..scaleByDouble(content.letterWidth, 1, 1, 1);
  }

  static void _keepTheKeyboard(PointerEvent event) {}

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onEscape();
      return KeyEventResult.handled;
    }
    if (event is! KeyUpEvent && _arrow(event)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// An arrow this answers, off the text as it is shown — with Shift, the
  /// end of the selection goes there. Whether [event] was one, and was
  /// answered.
  ///
  /// ACROSS the lines: down and up in lines — a field aligns its lines by
  /// one alignment, and a text's paragraphs are aligned each its own way —
  /// and in columns left, the column after, and right, the one before.
  /// ALONG them, in columns, down and up are the next letter and the one
  /// before; in lines left and right are the field's own.
  ///
  /// ⚠️Plain and with Shift alone. A jump by a word or to the end of the
  /// text — an arrow with Ctrl, or with ⌘ — is the field's own.
  ///
  /// ⛔The third modifier is not asked after: held under the text tool it
  /// is the eyedropper's (F-299 — 유저 2026-10-05: 「어떤 도구 들고있던 규칙
  /// 만들지말고 법 통일해서 작동하도록」), and two tools alone keep theirs
  /// (`canvasToolReadsAlt`).
  bool _arrow(KeyEvent event) {
    if (ModifierKeys.isControlPressed || ModifierKeys.isMetaPressed) {
      return false;
    }
    final selection = letters.selection;
    if (selection.extentOffset < 0) {
      return false;
    }
    final to = _whereGoes(event.logicalKey, selection.extent);
    if (to == null) {
      return false;
    }
    letters.selection = ModifierKeys.isShiftPressed
        ? selection.copyWith(extentOffset: to.offset, affinity: to.affinity)
        : TextSelection.fromPosition(to);
    return true;
  }

  /// Where [key] takes a caret at [from]; null for a key not answered here.
  TextPosition? _whereGoes(LogicalKeyboardKey key, TextPosition from) {
    final vertical = letters.content.vertical;
    final text = letters.text;
    final offset = from.offset;
    return switch (key) {
      LogicalKeyboardKey.arrowDown when vertical => TextPosition(
        offset: offset >= text.length
            ? text.length
            : offset + text.substring(offset).characters.first.length,
      ),
      LogicalKeyboardKey.arrowUp when vertical => TextPosition(
        offset: offset <= 0
            ? 0
            : offset - text.substring(0, offset).characters.last.length,
      ),
      // The column after is to the LEFT.
      LogicalKeyboardKey.arrowLeft when vertical => _onTheLineBeside(
        from,
        after: true,
      ),
      LogicalKeyboardKey.arrowRight when vertical => _onTheLineBeside(
        from,
        after: false,
      ),
      LogicalKeyboardKey.arrowDown => _onTheLineBeside(from, after: true),
      LogicalKeyboardKey.arrowUp => _onTheLineBeside(from, after: false),
      _ => null,
    };
  }

  /// The place on the line beside the one [from] stands on — the one
  /// after, or before ([CelTextLayout.placeBeside]) — as far along it as
  /// the arrows across the lines are aiming
  /// ([CelTextEditingController.arrowAim]). With no line on that side, the
  /// text's end, or its start.
  TextPosition _onTheLineBeside(TextPosition from, {required bool after}) {
    final at = TextPosition(
      offset: math.min(from.offset, shown.content.text.length),
      affinity: from.affinity,
    );
    final aim = letters.arrowAim;
    final along = aim != null && aim.landed == from.offset
        ? aim.along
        : _alongOf(at);
    final to =
        shown.placeBeside(at, after: after, along: along) ??
        TextPosition(offset: after ? letters.text.length : 0);
    letters.arrowAim = (landed: to.offset, along: along);
    return to;
  }

  /// How far along the lines the caret at [position] stands, as it is
  /// shown: its middle.
  double _alongOf(TextPosition position) {
    final caret = shown.caretRect(position);
    return letters.content.vertical ? caret.center.dy : caret.center.dx;
  }
}
