import '../../models/canvas_viewport.dart';

/// THE number a readout writes: [value] to [decimals] places, then [unit] —
/// every digit, whether the value happens to be whole or not.
///
/// F-9 (유저 2026-08-24):
///
/// > 「슬라이더 값에 소수점 텍스트 표시 (1.2px) … 브러시 사이즈만이 아니라
/// > **조절 가능한 모든 슬라이더**」
///
/// The panels used to `.round()` at each call site, so a bar you could set to
/// 1.2 read `1` — and then setting it again from the number you could see
/// moved the value. Rounding is a DISPLAY choice, and it was being made by
/// twenty call sites that could not agree.
///
/// 🚨F-34 (유저 확정 2026-09-01, 선택 1) is why [decimals] has NO DEFAULT:
///
/// > 「**슬라이더가 스스로 정한다 — 위젯이 자기 스텝을 보고 자릿수를
/// > 고른다**」
///
/// This used to hide the decimal whenever the value happened to be whole, so
/// one bar read `1`, then `1.2` under the same finger, then `1` again — 유저
/// 2026-08-31: 「소수점이 있는 슬라이더는 처음부터 소수점까지 보여주도록.
/// **없는 UI가 생겨나지 않게 하라는 원칙이 이 경우를 말함**」. The digit
/// count belongs to the BAR (`FieldSlider._decimals`), and the few
/// labels that are not plain numbers (`L50`, `off`, `Auto`) name their own.
///
/// ↩️Named `sliderValueText`, in the slider's file, until F-326 (2026-10-10)
/// made it every readout's: the view's pill and the value columns
/// ([columnValueText]) write their numbers through it too.
String readoutText(num value, {required int decimals, String unit = ''}) {
  final text = value.toStringAsFixed(decimals);
  // ⚠️`-0`: a value a hair below zero rounds to zero and KEEPS its sign, and
  // `-0%` beside a `0%` reads as a different number. Rounding alone can reach
  // it, so the guard is here rather than at the values.
  final zero = 0.toStringAsFixed(decimals);
  return '${text == '-$zero' ? zero : text}$unit';
}

/// THE number a value column writes — a timeline lane's and a tool
/// setting's drag readout: every digit of the readout grid
/// ([CanvasViewport.readoutDecimals]), always. The unit (`%`, `°`, ` px`)
/// is the column's, so it stays at the call site.
///
/// 🗣️F-326 (유저 2026-10-09): 「트랜스폼이든 카메라행이든 위치값같은게
/// 소수점까지 조정가능한 숫자 다 보여줌이라는 규칙에 어긋남. 1218이다가
/// 조절하면 소수점보엿다가 정수면 소수점사라지고 이럼. 이건 변형도구 숫자
/// 바뀔떄도 같음」 — the slider's law ([readoutText], 08-31).
/// ↩️The columns rounded to one decimal — two in the Move tool — and dropped
/// trailing zeros. The lanes and the tool settings are one column to the
/// user (2026-09-07: a number reads the same in every value column), so
/// they keep one digit count too: the view's (F-122, 「소수점 조작하는
/// 동작은 기본적으로 최대치를 소수점 두자리로」).
String columnValueText(num value) =>
    readoutText(value, decimals: CanvasViewport.readoutDecimals);

/// The number a value column's text holds — [columnValueText] read back,
/// with or without the column's unit (`%`, `°`, `px`). Null when the text
/// is not a number. Whatever the column then makes of it (a percent over
/// 100, a range's clamp, a whole cell count) stays at the call site.
///
/// The same law the other way: a number reads the same in every value
/// column (2026-09-07). ↩️Each column read its own — twelve copies of
/// `double.tryParse(text.replaceAll('%', '')…)`, each knowing a different
/// set of units, until F-407's made the clone scan name two of them.
///
/// An angle's turns and degrees ([turnsReadoutText]) read as the degrees
/// they come to — `1x+90°` is 450 — whichever column they are typed into.
double? columnValueOf(String text) {
  final mark = text.indexOf(turnsMark);
  // Whole turns lead it: the `x` of `12 px` stands after no turns.
  final turns = mark <= 0
      ? null
      : int.tryParse(text.substring(0, mark).trim());
  if (turns == null) {
    return _bareValueOf(text);
  }
  final rest = _bareValueOf(text.substring(mark + turnsMark.length));
  return rest == null ? null : turns * 360 + rest;
}

double? _bareValueOf(String text) => double.tryParse(
  text.replaceAll('%', '').replaceAll('°', '').replaceAll('px', '').trim(),
);

/// What stands after an angle's whole turns — `1x+90.00°`.
const String turnsMark = 'x';

/// An ANGLE as After Effects writes one: its whole turns, then what is
/// left of them with its own sign — `0x+90.00°`, `1x+90.00°` for 450,
/// `-1x-90.00°` for −450 — the degrees to every digit of the readout grid
/// ([columnValueText]). [columnValueOf] reads it back.
///
/// 🗣️I-132-Q17 a (유저 2026-10-28): 「키를 박는 각도 레인만」 — the angle
/// lanes a key is set on: a row's rotation and an effect's angle. A tool
/// setting's angle (the brush's, the view's, a guide's) is one number.
String turnsReadoutText(double degrees) {
  final gridded = CanvasViewport.onReadoutGrid(degrees);
  final turns = gridded ~/ 360;
  final rest = gridded - turns * 360;
  final sign = rest < 0 ? '-' : '+';
  return '$turns$turnsMark$sign${columnValueText(rest.abs())}°';
}

/// The two numbers a two-number column's text holds — `120, 45`, each read
/// by [columnValueOf]. Null unless it holds exactly two. ↩️The position's
/// editor, its scrub and the scale's scrub each split it on their own.
(double, double)? columnPairOf(String text) {
  final pieces = text.split(',');
  if (pieces.length != 2) {
    return null;
  }
  final first = columnValueOf(pieces[0]);
  final second = columnValueOf(pieces[1]);
  return first == null || second == null ? null : (first, second);
}

/// ONE editable piece of a readout: the number a person types, and the
/// FIXED text that trails it.
typedef ReadoutPart = ({String number, String unit});

/// A readout split into what is TYPED and what is chrome — the way every
/// number this app lets you type over opens its field.
///
/// 🗣️유저 2026-10-10: 「%나 각도같은 단위값은 텍스트 편집시 안보이도록. 즉
/// 100.00%를 눌러서 편집하려할때 %도 같이 편집되버리는 텍스트면 너무
/// 불편하니까. 편집시 100.00 만 뜨는느낌. 다른 모든 텍스트 직접편집의 기준」.
/// It was the timeline's law first — F-22 ②③ (유저 2026-08-24): 「**단위 같은
/// 고정요소를 편집창에서 제거**」, 「**포지션 등 2요소는 각각 편집**(온점
/// 없이)」 — and the drag readout kept a second one of its own, a regex that
/// dropped every character that was not a digit: `3 / 7` opened as `37`.
///
/// ⚠️Derived from the readout rather than declared per value. The readout
/// already says what shape it is (`85%`, `30°`, `12 px`, `120, 45`), and a
/// second declaration would be a second answer to drift from.
/// [joinReadoutParts] puts it back in the form the readout's own parser
/// already accepts.
///
/// ⛔A readout only SPLITS when every comma-separated piece reads as a
/// number: a text value that happens to contain a comma is one value, not
/// two.
///
/// An angle's readout ([turnsReadoutText]) is its two boxes, the turns and
/// the degrees — the way After Effects opens them (I-132-Q17: 「1x」 ·
/// 「+90.0°」).
List<ReadoutPart> readoutParts(String readout) {
  if (_turnsParts(readout) case final turns?) {
    return turns;
  }
  final pieces = readout.split(',');
  final parts = <ReadoutPart>[];
  for (final piece in pieces) {
    final part = _numberAndUnit(piece.trim());
    if (part == null) {
      return [(number: readout, unit: '')];
    }
    parts.add(part);
  }
  return parts.isEmpty ? [(number: readout, unit: '')] : parts;
}

/// [readoutParts] put back together — byte for byte what the readout was.
String joinReadoutParts(List<ReadoutPart> parts) => parts
    .map((part) => '${part.number}${part.unit}')
    .join(readsTurns(parts) ? '' : ', ');

/// Whether [parts] are an angle's turns and degrees ([turnsReadoutText]),
/// not a pair of numbers.
bool readsTurns(List<ReadoutPart> parts) =>
    parts.length == 2 && parts.first.unit == turnsMark;

/// `1x+90.00°` → (1, 'x'), (+90.00, '°'). Null unless [readout] is an
/// angle's turns and degrees, whole.
List<ReadoutPart>? _turnsParts(String readout) {
  final mark = readout.indexOf(turnsMark);
  if (mark <= 0) {
    return null;
  }
  final turns = _numberAndUnit(readout.substring(0, mark));
  final rest = _numberAndUnit(readout.substring(mark + turnsMark.length));
  if (turns == null || turns.unit.isNotEmpty || rest?.unit != '°') {
    return null;
  }
  return [(number: turns.number, unit: turnsMark), rest!];
}

/// `85%` → (85, '%'), `12 px` → (12, ' px'), `-3.5` → (-3.5, ''). Null when
/// the text does not lead with a number at all, which is every value that is
/// not one — a colour, a font name, a flag.
ReadoutPart? _numberAndUnit(String text) {
  var end = 0;
  if (end < text.length && (text[end] == '-' || text[end] == '+')) {
    end += 1;
  }
  final digitsStart = end;
  while (end < text.length && _isDigit(text[end])) {
    end += 1;
  }
  if (end < text.length && text[end] == '.') {
    end += 1;
    while (end < text.length && _isDigit(text[end])) {
      end += 1;
    }
  }
  if (end == digitsStart) {
    return null;
  }
  return (number: text.substring(0, end), unit: text.substring(end));
}

bool _isDigit(String character) {
  final code = character.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}
