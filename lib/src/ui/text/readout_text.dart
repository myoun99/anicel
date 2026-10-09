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
