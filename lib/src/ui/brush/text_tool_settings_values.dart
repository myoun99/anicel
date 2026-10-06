import 'package:flutter/foundation.dart';

import '../../models/cel_text.dart';
import '../../models/text_cel_style.dart';
import '../canvas/text/cel_text_tool.dart';
import '../text/cel_text_box_width.dart';
import 'text_tool_options.dart';

/// One setting of the letters as the tool settings show it: its value on
/// the first run the setting speaks for, and whether the runs disagree —
/// which shows as 「—」 (유저 2026-10-06).
typedef ShownLetterSetting<T> = ({T value, bool mixed});

/// WHAT THE TEXT TOOL'S SETTINGS READ AND WRITE (R9-rest) — the one law
/// every row of the panel keeps, so that no row can keep another.
///
/// 🗣️유저 2026-10-02: 「선택해서 그 상태에서 도구설정에서 폰트바꾸면 해당
/// 텍스트박스 설정 자동으로 바꿈 … 그냥 설정바꾸면 해당 텍스트박스 내 텍스트
/// 전체에 적용되서 바뀌고, 텍스트를 선택하고 조절하면 일부만 텍스트 조절」 ·
/// 2026-10-06: 「선택안하고 색 바꾸면 해당 텍스트 전체 색 바꾸고 선택하고
/// 바꾸면 선택된부분만 바꾸는 **공용화할 텍스트 도구설정 로직** 그대로 따라감」.
///
/// · READ: the text in hand when there is one — its letters by the range a
///   letter setting speaks for ([CelTextTool.letterStylesSpokenFor]), its
///   box as it is — and with none in hand what the NEXT text will start as
///   ([TextToolOptions]).
/// · WRITE: on BOTH — the text in hand, by that same range, and the next
///   text's values. Taking a text in hand changes neither: only a change
///   made here does.
///
/// [settled] false is a value still being dragged: it shows, and lands with
/// the one that follows it ([CelTextTool.changeLetters]).
class TextToolSettingsValues {
  const TextToolSettingsValues({required this.options, required this.tool});

  /// The next text's values. Null in a host that does not own them.
  final ValueNotifier<TextToolOptions>? options;

  /// The hand of the canvas on screen. Null where no canvas holds one.
  final CelTextTool? tool;

  TextToolOptions get _next => options?.value ?? TextToolOptions.defaults;

  /// The text in hand as a setting finds it.
  CelTextContent? get _inHand => tool?.contentInHand;

  /// Whether a change made here goes anywhere at all.
  bool get writable => options != null || _inHand != null;

  // ── the letters ─────────────────────────────────────────────────────

  /// One setting of the letters, read by [of].
  ShownLetterSetting<T> letter<T>(T Function(TextLetterStyle style) of) {
    final values = [
      for (final style in tool?.letterStylesSpokenFor ?? [_next.letters])
        of(style),
    ];
    return (
      value: values.first,
      mixed: values.any((value) => value != values.first),
    );
  }

  /// Makes [change] on the letters the setting speaks for, and on the next
  /// text's.
  void setLetters(
    TextLetterStyle Function(TextLetterStyle style) change, {
    bool settled = true,
  }) {
    tool?.changeLetters(change, settled: settled);
    _setNext((next) => next.copyWith(letters: change(next.letters)));
  }

  // ── the box ─────────────────────────────────────────────────────────

  TextCelAlign get align => _inHand?.align ?? _next.align;

  double get lineHeight => _inHand?.lineHeight ?? _next.lineHeight;

  /// The colour of the box behind the letters — null for none, which is a
  /// value: a text in hand with no box shows none whatever the next text's
  /// is.
  int? get backgroundColor {
    final inHand = _inHand;
    return inHand == null ? _next.backgroundColor : inHand.backgroundColor;
  }

  /// Whether the text in hand is a BOX — its lines wrap at a width — or one
  /// that grows with what is typed. Null with none in hand: which of the
  /// two the next text is, the hand says (a click or a drag, 유저
  /// 2026-10-06), and there is nothing here to set.
  bool? get wraps {
    final inHand = _inHand;
    return inHand == null ? null : inHand.wrapWidth != null;
  }

  /// Whether the text in hand can be made a box ([wraps]) or one that
  /// grows: there is one in hand — and, to be made a box, it has a line to
  /// be as wide as. A text with no letters has none ([celTextBoxed]).
  bool canSetWraps({required bool wraps}) {
    final inHand = _inHand;
    return inHand != null &&
        (!wraps || !inHand.isEmpty || inHand.wrapWidth != null);
  }

  void setAlign(TextCelAlign align) => _setBox(
    onText: (text) => text.copyWith(align: align),
    onNext: (next) => next.copyWith(align: align),
  );

  void setLineHeight(double lineHeight, {bool settled = true}) => _setBox(
    onText: (text) => text.copyWith(lineHeight: lineHeight),
    onNext: (next) => next.copyWith(lineHeight: lineHeight),
    settled: settled,
  );

  void setBackgroundColor(int? color, {bool settled = true}) => _setBox(
    onText: (text) => text.copyWith(backgroundColor: color),
    onNext: (next) => next.copyWith(backgroundColor: color),
    settled: settled,
  );

  /// Swaps the text in hand between a box and a text that grows — 유저
  /// 2026-10-06: 「이부분 고정할지 비고정할지는 도구설정에서 스왑가능」 — and
  /// it LOOKS THE SAME after ([celTextBoxed] · [celTextUnboxed]). Of the
  /// text in hand alone: the next text's is the hand's to say.
  void setWraps(bool wraps) =>
      tool?.changeBox(wraps ? celTextBoxed : celTextUnboxed);

  /// A value that was being dragged — a colour, picked in a window that
  /// says only when it closed — has come to rest.
  void settle() => tool?.landEdit();

  void _setBox({
    required CelTextContent Function(CelTextContent text) onText,
    required TextToolOptions Function(TextToolOptions next) onNext,
    bool settled = true,
  }) {
    tool?.changeBox(onText, settled: settled);
    _setNext(onNext);
  }

  void _setNext(TextToolOptions Function(TextToolOptions next) change) {
    final options = this.options;
    if (options != null) {
      options.value = change(options.value);
    }
  }
}
