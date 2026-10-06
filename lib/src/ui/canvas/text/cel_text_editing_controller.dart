import 'package:flutter/widgets.dart';

import '../../../models/cel_text.dart';
import '../../../models/text_cel_style.dart';
import '../../../services/cel_text_edits.dart';
import '../../text/cel_text_layout.dart';

/// THE LETTERS OF A TEXT WHILE IT IS TYPED INTO (R9-rest): what a keyboard
/// edits, kept as the text's own runs — each letter with how it is set.
///
/// A keyboard — an IME most of all — hands over the text it LEFT, never the
/// edit it made, and knows nothing of styles. So every new value is read
/// back into one replacement ([textReplacementBetween]) and made on the
/// runs ([celTextWithLetters]): a letter typed wears what stands beside
/// it, and the rest keep what they wore.
///
/// 🚨IT KEEPS ITS OWN STEPS BACK. The field's own undo holds texts alone:
/// it would put letters back by typing them again, in the style of
/// whatever stands beside them now — a red word taken out and undone would
/// come back black. A step here is the runs themselves, so [undo] puts
/// back exactly what was there.
///
/// ONE STEP IS ONE RUN OF TYPING: letters set one after another with no
/// space or break among them — a word — however an IME sets them again on
/// the way (a syllable growing, a clause converted). The run ends where
/// the caret is moved or a composition is committed; and anything that is
/// not typing — a letter taken out, a paste, a space, a break, a change of
/// setting — is a step of its own.
///
/// ↩️A run used to go on for as long as EITHER side of an edit was
/// composing, and under a Korean or a Japanese IME one side always is: a
/// whole paragraph was one step, and one Ctrl+Z took all of it (found
/// reading it back, 2026-10-06).
class CelTextEditingController extends TextEditingController {
  CelTextEditingController({
    required CelTextContent content,
    required TextLetterStyle nextLetterStyle,
    TextSelection? selection,
  }) : _content = content,
       _nextLetterStyle = nextLetterStyle,
       super.fromValue(
         TextEditingValue(
           text: content.text,
           selection:
               selection ??
               TextSelection.collapsed(offset: content.text.length),
         ),
       );

  /// The text as it stands: the field's letters, in their runs.
  CelTextContent get content => _content;
  CelTextContent _content;

  /// What the first letter typed into a text with none will wear — the
  /// tool's setting, or what the last letter taken out of this one wore.
  TextLetterStyle get nextLetterStyle => _nextLetterStyle;
  TextLetterStyle _nextLetterStyle;

  final List<_Step> _stepsBack = [];
  final List<_Step> _stepsForward = [];

  /// The edit before this one, while a run of typing can still go on from
  /// it.
  _Typed? _lastEdit;

  /// How many steps back are kept: beyond it the oldest is let go.
  static const int _stepsKept = 200;

  bool get canUndo => _stepsBack.isNotEmpty;
  bool get canRedo => _stepsForward.isNotEmpty;

  @override
  set value(TextEditingValue newValue) {
    final old = value;
    final committed = old.composing.isValid && !newValue.composing.isValid;
    if (newValue.text == old.text) {
      // The caret moved, or a composition was committed where it stood: a
      // letter typed after either is a run of its own.
      if (committed || newValue.selection != old.selection) {
        _lastEdit = null;
      }
      super.value = newValue;
      return;
    }
    final caret = newValue.selection;
    final edit = textReplacementBetween(
      old.text,
      newValue.text,
      caretAfter: caret.isValid && caret.isCollapsed
          ? caret.extentOffset
          : null,
    );
    // The edit is INSIDE what the IME was composing — a syllable growing,
    // a clause converted, a letter put into the middle of it: the same
    // typing, however many letters it set again.
    final rewrites =
        old.composing.isValid &&
        edit.range.start >= old.composing.start &&
        edit.range.end <= old.composing.end;
    final typed = (
      end: edit.range.start + edit.letters.length,
      // Letters with no space or break among them, set by a keyboard: one
      // after the caret, or whatever an IME is composing.
      goesOn:
          !edit.letters.contains(_break) &&
          (rewrites ||
              newValue.composing.isValid ||
              (edit.range.start == edit.range.end &&
                  edit.letters.length == 1)),
    );
    final last = _lastEdit;
    final goesOn =
        last != null &&
        last.goesOn &&
        typed.goesOn &&
        (rewrites || edit.range.start == last.end);
    if (!goesOn) {
      _keepStep(old);
    }
    _stepsForward.clear();
    // A composition committed ends the run it was typed in.
    _lastEdit = committed ? null : typed;
    final before = _content;
    _content = celTextWithLetters(
      before,
      range: edit.range,
      letters: edit.letters,
      nextLetterStyle: _nextLetterStyle,
    );
    if (_content.isEmpty && !before.isEmpty) {
      // No letter is left to go by: the next one typed wears what the
      // first one taken out wore.
      _nextLetterStyle = celTextStylesOf(before, (start: 0, end: 1)).single;
    }
    super.value = newValue;
  }

  /// A space or a break: where a run of typing ends.
  static final RegExp _break = RegExp(r'\s');

  void _keepStep(TextEditingValue fieldValue) {
    _stepsBack.add(
      (content: _content, nextLetterStyle: _nextLetterStyle, field: fieldValue),
    );
    if (_stepsBack.length > _stepsKept) {
      _stepsBack.removeAt(0);
    }
  }

  /// Sets the text differently with every letter where it is — a change of
  /// a tool setting, of the letters' or of the box's.
  ///
  /// [goesOn] is a value still being dragged: it is the same step as the
  /// change before it, so a slider drawn across its track is one step back
  /// and not one for every value it passed.
  void restyle(
    CelTextContent content, {
    TextLetterStyle? nextLetterStyle,
    bool goesOn = false,
  }) {
    assert(content.text == _content.text, 'a restyle changes no letter');
    final letters = nextLetterStyle ?? _nextLetterStyle;
    if (content == _content && letters == _nextLetterStyle) {
      return;
    }
    if (!goesOn) {
      _keepStep(value);
    }
    _stepsForward.clear();
    _lastEdit = null;
    _content = content;
    _nextLetterStyle = letters;
    notifyListeners();
  }

  /// Takes the last step back: the letters, how they were set and where
  /// the caret stood.
  void undo() => _step(from: _stepsBack, onto: _stepsForward);

  void redo() => _step(from: _stepsForward, onto: _stepsBack);

  void _step({required List<_Step> from, required List<_Step> onto}) {
    if (from.isEmpty) {
      return;
    }
    final step = from.removeLast();
    final left = value;
    onto.add(
      (content: _content, nextLetterStyle: _nextLetterStyle, field: left),
    );
    _lastEdit = null;
    _content = step.content;
    _nextLetterStyle = step.nextLetterStyle;
    // ⚠️Past this class's own setter: the letters are put back as the runs
    // they were, not read back from a text.
    super.value = step.field.copyWith(composing: TextRange.empty);
    if (value == left) {
      // A step that changed only how letters are set moves no letter and
      // no caret, and the field then tells nobody.
      notifyListeners();
    }
  }

  /// The very spans the text on the canvas is set from, so the field
  /// breaks its lines — and moves its caret up and down them — where the
  /// canvas does. It is never seen: the letters on screen are the cel's.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => celTextFieldSpan(_content, nextLetterStyle: _nextLetterStyle);
}

/// The text at one step: its runs, the style a first letter would wear,
/// and the field's letters and caret.
typedef _Step = ({
  CelTextContent content,
  TextLetterStyle nextLetterStyle,
  TextEditingValue field,
});

/// What an edit left for the next one to go on from: where it ended, and
/// whether it was typing that a next letter can go on from.
typedef _Typed = ({int end, bool goesOn});
