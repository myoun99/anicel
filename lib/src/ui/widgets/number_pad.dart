import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/control_press_claim.dart';
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import 'anchored_popup.dart';
import 'app_icon_button.dart';
import 'inline_edit_field.dart';
import 'selected_text_controller.dart';

/// What a typed number takes besides its digits — which of the pad's keys
/// stay lit. 🗣️I-134 (유저 2026-10-27): 「-가 존재하는 숫자라면 -넣고 그런식
/// … 입력할수있는 값에 따라 … 대응 불가능한거면 비활성화시키도록」.
typedef NumberPadKeys = ({bool minus, bool point});

/// THE NUMBER PAD a value's pencil opens, anchored under the value — the
/// number at its top, the keys under it.
///
/// 🗣️I-134 (유저 2026-10-27): 「숫자만 입력하는 값이라면 전용 숫자 앵커
/// 팝오버창 만들어서 그거로 입력가능하게 … 텍스트는 지금 바로 텍스트
/// 선택한 상태인데, 그러면 바로 키보드 올라와버리니까 선택하지 않은 상태로
/// 두고 숫자 누르면 기존 숫자 지워지고 해당 숫자 입력되는느낌. 위에 숫자
/// 텍스트 클릭하면 직접 키보드로 수정할수있게 텍스트 선택된상태 들어감 …
/// 디자인 자체는 따라하면 안되니 우리식으로 재 디자인」.
///
/// It types as the field types ([InlineEditField], whose law it keeps):
/// the number opens whole — selected, though nothing shows it and no
/// keyboard rises — so the first key replaces it; ✓ or Enter commits, a
/// press outside commits what was typed and drops an untouched number,
/// Escape abandons. Its top is that one field once pressed: the keyboard
/// rises on the number, all of it selected, and the keys still type into
/// it. [onSubmit] hears the text once, its numerals half-width; the host
/// parses and clamps, as it does a typed field's.
///
/// ↩️The pencil opened the field in the value's own place (`ValuePencil`,
/// 2026-10-10), the keyboard up at once.
Future<void> showNumberPad(
  BuildContext anchorContext, {
  required String keyValue,
  required String initialText,
  required NumberPadKeys keys,
  required ValueChanged<String> onSubmit,
  Key? fieldKey,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
}) => showAnchoredPopup<void>(
  anchorContext,
  label: '$keyValue-pad',
  width: _NumberPad.width,
  height: _NumberPad.height,
  builder: (context, close) => _NumberPad(
    keyValue: keyValue,
    initialText: initialText,
    keys: keys,
    onSubmit: onSubmit,
    close: close,
    fieldKey: fieldKey,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
  ),
);

/// What a press of a key makes of [value]: [text] typed into its
/// selection — the whole number while the pad has just opened.
///
/// A point the number already has outside the selection is not typed
/// again, a point with no digit before it is typed after a zero, and a
/// lone leading zero gives way to the digit after it.
TextEditingValue numberPadTyped(TextEditingValue value, String text) {
  final TextSelection(:start, :end) = value.selection;
  final kept = value.text.replaceRange(start, end, '');
  if (text == '.' && kept.contains('.')) {
    return value;
  }
  final before = value.text.substring(0, start);
  final key = text == '.' && !RegExp(r'\d$').hasMatch(before) ? '0.' : text;
  var typed = value.text.replaceRange(start, end, key);
  var caret = start + key.length;
  if (RegExp(r'^-?0\d').hasMatch(typed)) {
    final zero = typed.indexOf('0');
    typed = typed.replaceRange(zero, zero + 1, '');
    caret -= 1;
  }
  return TextEditingValue(
    text: typed,
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// What the minus key makes of [value]: a minus to start a number with,
/// over a number still whole in the selection — else the number's sign,
/// turned.
TextEditingValue numberPadNegated(TextEditingValue value) {
  final TextSelection(:start, :end) = value.selection;
  if (start == 0 && end == value.text.length) {
    return numberPadTyped(value, '-');
  }
  final negative = value.text.startsWith('-');
  final shift = negative ? -1 : 1;
  return TextEditingValue(
    text: negative ? value.text.substring(1) : '-${value.text}',
    selection: TextSelection(
      baseOffset: (start + shift).clamp(0, value.text.length + shift),
      extentOffset: (end + shift).clamp(0, value.text.length + shift),
    ),
  );
}

/// What the backspace key makes of [value]: the selection gone, or the
/// character before the caret.
TextEditingValue numberPadErased(TextEditingValue value) {
  final TextSelection(:start, :end) = value.selection;
  final from = start == end ? (start - 1).clamp(0, start) : start;
  return TextEditingValue(
    text: value.text.replaceRange(from, end, ''),
    selection: TextSelection.collapsed(offset: from),
  );
}

class _NumberPad extends StatefulWidget {
  const _NumberPad({
    required this.keyValue,
    required this.initialText,
    required this.keys,
    required this.onSubmit,
    required this.close,
    this.fieldKey,
    this.keyboardType,
    this.inputFormatters,
  });

  final String keyValue;
  final String initialText;
  final NumberPadKeys keys;
  final ValueChanged<String> onSubmit;
  final VoidCallback close;
  final Key? fieldKey;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// A key's box: a finger's, in a window the pencil opened.
  static const double _keyWidth = 40;
  static const double _keyHeight = 32;
  static const double _gap = 4;

  /// How tall the number at the top stands.
  static const double _numberHeight = 32;

  static const TextStyle _numberStyle = TextStyle(fontSize: 16);

  static const double _pad = AnchoredPopupText.bodyPaddingValue;

  static const double width = 2 * _pad + 4 * _keyWidth + 3 * _gap;
  static const double height =
      2 * _pad +
      _numberHeight +
      AnchoredPopupText.titleGap +
      4 * _keyHeight +
      3 * _gap;

  @override
  State<_NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<_NumberPad> {
  late final TextEditingController _controller = selectedTextController(
    widget.initialText,
  );

  /// Whether the number is typed by the keyboard: its top was pressed.
  bool _keyboard = false;

  /// Whether the pad closed itself — ✓, Enter, Escape — so the pop that
  /// follows is not a press away ([_closedFromOutside]).
  bool _settled = false;

  /// The pad and its field are one region: a press on a key is not a
  /// press away from the field.
  final Object _region = Object();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit(TextEditingValue Function(TextEditingValue) edit) =>
      setState(() => _controller.value = edit(_controller.value));

  void _commit([String? text]) {
    _settled = true;
    widget.onSubmit(toHalfWidthNumerals(text ?? _controller.text).trim());
    widget.close();
  }

  void _abandon() {
    _settled = true;
    widget.close();
  }

  /// Closed from outside — a press away from it: what was typed commits,
  /// an untouched number does not ([InlineEditField]'s law).
  void _closedFromOutside() {
    if (_settled) {
      return;
    }
    if (_controller.text != widget.initialText) {
      widget.onSubmit(toHalfWidthNumerals(_controller.text).trim());
    }
  }

  void _typeByKeyboard() => setState(() {
    _keyboard = true;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  });

  /// A hardware key while the pad types: what its keys would do.
  KeyEventResult _hardwareKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _abandon();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commit();
    } else if (key == LogicalKeyboardKey.backspace) {
      _edit(numberPadErased);
    } else {
      final typed = toHalfWidthNumerals(event.character ?? '');
      final press = _pressOf(typed);
      if (press == null) {
        return KeyEventResult.ignored;
      }
      press();
    }
    return KeyEventResult.handled;
  }

  /// What the key that types [glyph] does, or null where it does nothing.
  VoidCallback? _pressOf(String glyph) => switch (glyph) {
    '-' when widget.keys.minus => () => _edit(numberPadNegated),
    '.' when widget.keys.point => () => _edit(
      (value) => numberPadTyped(value, '.'),
    ),
    _ when RegExp(r'^\d$').hasMatch(glyph) => () => _edit(
      (value) => numberPadTyped(value, glyph),
    ),
    _ => null,
  };

  Widget _number() {
    final style = DefaultTextStyle.of(context).style.merge(
      _NumberPad._numberStyle,
    );
    final number = _keyboard
        ? InlineEditField(
            fieldKey: widget.fieldKey,
            controller: _controller,
            groupId: _region,
            initialText: widget.initialText,
            textStyle: style,
            textAlign: TextAlign.right,
            signed: widget.keys.minus,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            onSubmit: _commit,
            onCancel: _abandon,
          )
        : ControlPressClaim(
            onPressed: _typeByKeyboard,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: SizedBox.expand(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _controller.text,
                    key: ValueKey<String>('${widget.keyValue}-pad-number'),
                    maxLines: 1,
                    style: style,
                  ),
                ),
              ),
            ),
          );
    return SizedBox(height: _NumberPad._numberHeight, child: number);
  }

  Widget _key(
    String name,
    Widget glyph,
    VoidCallback? onPressed, {
    String tooltip = '',
    int rows = 1,
  }) => AppIconButton(
    keyValue: '${widget.keyValue}-pad-$name',
    tooltip: tooltip,
    outlined: true,
    size: AppIconButtonBox(
      width: _NumberPad._keyWidth,
      height: rows * _NumberPad._keyHeight + (rows - 1) * _NumberPad._gap,
      iconSize: 18,
    ),
    icon: glyph,
    onPressed: onPressed,
  );

  Widget _typing(String glyph) => _key(
    switch (glyph) {
      '-' => 'minus',
      '.' => 'point',
      _ => glyph,
    },
    glyph == '-'
        ? const Icon(Icons.remove)
        : Text(glyph, style: const TextStyle(fontSize: 16)),
    _pressOf(glyph),
  );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox.square(dimension: _NumberPad._gap);
    Widget row(List<String> glyphs) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _NumberPad._gap,
      children: [for (final glyph in glyphs) _typing(glyph)],
    );
    final strings = AppText.strings;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closedFromOutside();
        }
      },
      child: TapRegion(
        groupId: _region,
        child: Focus(
          autofocus: true,
          onKeyEvent: _keyboard ? null : _hardwareKey,
          child: Padding(
            padding: AnchoredPopupText.bodyPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _number(),
                const SizedBox(height: AnchoredPopupText.titleGap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: _NumberPad._gap,
                      children: [
                        row(const ['7', '8', '9']),
                        row(const ['4', '5', '6']),
                        row(const ['1', '2', '3']),
                        row(const ['-', '0', '.']),
                      ],
                    ),
                    gap,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: _NumberPad._gap,
                      children: [
                        _key(
                          'backspace',
                          const Icon(Icons.backspace_outlined),
                          () => _edit(numberPadErased),
                          tooltip: strings.commonDelete,
                          rows: 2,
                        ),
                        _key(
                          'enter',
                          const Icon(Icons.check),
                          _commit,
                          tooltip: strings.commonApply,
                          rows: 2,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
