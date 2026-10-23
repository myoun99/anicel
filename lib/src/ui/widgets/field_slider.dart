import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/input/modifier_keys.dart';
import '../input/control_press_claim.dart';
import '../input/wheel_law.dart';
import '../text/app_strings.dart';
import '../text/readout_text.dart';
import '../text/text_measure.dart';
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import '../theme/disabled_ink.dart';
import '../theme/text_on_ground.dart';
import '../timeline/axis_turn.dart';
import 'axis_bar_gesture.dart';
import 'ground_ink_writing.dart';
import 'inline_numeric_field.dart';
import 'superellipse_clip.dart';
import 'value_hands.dart';
import '../repaint_props.dart';

/// How a [FieldSlider] maps track position to value.
enum FieldSliderScale {
  /// Uniform mapping across the track.
  linear,

  /// Logarithmic mapping: equal track distance multiplies the value by a
  /// constant factor, so the left half of the track covers the small values
  /// where precision matters (brush size, spacing). Requires `min > 0`.
  exponential,
}

/// The app's shared settings slider: a filled-bar *field* where the whole bar
/// is the control (no thumb — friendlier to touch/stylus) and the label and
/// value live inside the track, so one row carries what used to take a label
/// row plus a slider plus a trailing value text.
///
/// Variants and interactions:
/// - `label == null` renders the micro variant (value only, centered) — the
///   timeline's inline slots, and equally a dialog row whose label is a
///   `Text` BESIDE the bar. ⚠️Those two are not the same situation even
///   though they take the same branch, which is why the `%`-dropping rule
///   sits in [FieldSlider.opacity] and not in the writing.
/// - A STOOD-UP bar writes the same row, turned a quarter clockwise.
/// - Drag or tap sets the value by absolute track position; holding Shift
///   switches to relative movement at 1/10 speed for fine control.
/// - The scroll wheel steps the value by 1% of the track (Shift: 0.1%); with
///   [divisions] it steps one division instead.
/// - A tap sets the value and KEEPS it, in every host and from every input
///   device — however much the hand wobbled while it landed. A scroll that
///   takes the gesture rolls the tentative jump back instead, so bars
///   inside scrollables stay safe to scroll over. What separates the two is
///   the DIRECTION the pointer went, not how far — see [_FieldSliderState].
///
/// It does NOT type (R10 R5). A bar is a bar: tap or drag sets the value,
/// and that is the whole control. The inline editor it used to carry was
/// reached by a DOUBLE-tap, which held every ordinary tap hostage for
/// 300ms — on the one control whose entire job is to answer a tap
/// immediately. The user: "수동입력 없어져도 ok. 어차피 조작할때
/// 번거롭기만했어."
///
/// Where an exact number really is needed, put a [DragValueLabel] BESIDE
/// the bar rather than inside it: that one types on a single tap, so the
/// app-wide rule ("tap = pick or edit, double-tap = open") stays whole.
class FieldSlider extends StatefulWidget {
  const FieldSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.displayScale = 1,
    this.onChangeEnd,
    this.valueTextBuilder,
    this.restingText,
    this.restingAccent,
    this.label,
    this.scale = FieldSliderScale.linear,
    this.divisions,
    this.stops,
    this.fillOrigin,
    this.height = defaultHeight,
    this.axis = Axis.horizontal,
    this.nameInside = true,
    this.upright = false,
  }) : assert(max > min, 'max must exceed min'),
       assert(
         !upright || (axis == Axis.vertical && (label == null || !nameInside)),
         'a bar stands its number up only stood, and writes the number alone',
       ),
       assert(
         scale != FieldSliderScale.exponential || min > 0,
         'exponential scale requires min > 0',
       ),
       assert(
         divisions == null || scale == FieldSliderScale.linear,
         'divisions only combine with the linear scale',
       ),
       assert(
         stops == null || divisions == null,
         'a step is the next stop or the next division, not both',
       );

  /// **A settings GRID's bar** ([ToolSettingRow.bar]): its name stands in
  /// the row's name column, so the bar writes its number alone — at the
  /// right, where a named bar writes it — and keeps its ± (a settings row's
  /// bar, not the inline slot).
  ///
  /// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「X값Y값 크기 통일한것처럼
  /// 이런부분 다 통일해서 정돈된 행/열 느낌 나도록」 — every row's name in one
  /// column, every control in the next. [label] still names the bar to a
  /// screen reader.
  const FieldSlider.cell({
    super.key,
    required String this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.displayScale = 1,
    this.onChangeEnd,
    this.valueTextBuilder,
    this.scale = FieldSliderScale.linear,
    this.divisions,
    this.fillOrigin,
  }) : nameInside = false,
       restingText = null,
       restingAccent = null,
       stops = null,
       height = defaultHeight,
       axis = Axis.horizontal,
       upright = false,
       assert(max > min, 'max must exceed min'),
       assert(
         scale != FieldSliderScale.exponential || min > 0,
         'exponential scale requires min > 0',
       ),
       assert(
         divisions == null || scale == FieldSliderScale.linear,
         'divisions only combine with the linear scale',
       );

  /// **An OPACITY bar**: 0..1 in the model, whole per cent on the screen.
  ///
  /// 🚨유저 2026-08-29 (F-34): 「슬라이더에서 데이터적으로 소수점이 필요없는
  /// 것들 정수화. **레이어나 브러시 불투명도가 소수점? 자연수가 아닐 이유가
  /// 없다고생각. 조절시 자연수이도록.**」
  ///
  /// The hundred divisions are what make that true WHILE DRAGGING.
  /// [readoutText] only ever rounded the label, so a bar reading `50%`
  /// could be holding 0.4963 — and the next thing to read that number (a
  /// composite, an export) got the 0.4963.
  ///
  /// ⛔THE RANGE AND THE FORMAT ARE FIXED HERE, not repeated per call. Six
  /// bars were each typing `min: 0, max: 1` with the same `value * 100`
  /// builder — six places to forget the divisions, and all six had. The
  /// resting [restingText] stays the caller's, because the legend's master
  /// bar reads `OPAC` at rest and the row's reads its number.
  ///
  /// ⚠️Not every slider is integral and this does not claim they are: brush
  /// SIZE goes down to 0.7, the pressure curve is a gamma, and the transform
  /// tool's scale is the exception 유저 named in the same sentence.
  const FieldSlider.opacity({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.restingText,
    this.restingAccent,
    this.label,
    this.height = defaultHeight,
    this.axis = Axis.horizontal,
    this.nameInside = true,
    this.upright = false,
  }) : assert(
         !upright || (axis == Axis.vertical && (label == null || !nameInside)),
         'a bar stands its number up only stood, and writes the number alone',
       ),
       min = 0,
       fillOrigin = null,
       max = 1,
       divisions = 100,
       stops = null,
       scale = FieldSliderScale.linear,
       // 🚨THE MICRO OPACITY BAR WRITES THE NUMBER ALONE (유저 2026-09-10:
       // 「타임라인 레이어영역에 있는 슬라이더 미니버전. **미니버전은 텍스트에
       // % 표기 삭제. 그냥 안보이게**」) — the layer rows, the storyboard's SE
       // rows, the x-sheet's stood-up rail and the legend's master bar. And
       // so does a bar whose name is not written in it ([nameInside]): the
       // brush pill's (F-460, 유저 2026-10-23: 「불투명도는 % 없앰」).
       //
       // ⛔Here and not in [FieldSlider._textFor]: `label == null` is
       // ALSO how a bar whose label sits BESIDE it is built (the stage
       // dialog's alpha, the export bitrate, the autosave minutes), and
       // those would have lost ` Mb` and their minutes with it. A bar that
       // says OPACITY in the column it lives in is what the user pointed at.
       unit = label == null || !nameInside ? '' : '%',
       // A hundred divisions of a 0..1 model IS a whole per cent on screen,
       // and saying the scale here is what lets the digit rule see that.
       displayScale = 100,
       valueTextBuilder = null;

  /// Current value in model units (e.g. 0..1 for opacity).
  final double value;

  final double min;
  final double max;

  /// Live per-move callback; `null` disables the control (dimmed, inert).
  final ValueChanged<double>? onChanged;

  /// Fires once when a drag ends or a wheel step lands — the hook for
  /// commit-on-release consumers (opacity/zoom drag
  /// smoothness, R4 #4/#5): route the cheap live preview through
  /// [onChanged] and the real write through this.
  final ValueChanged<double>? onChangeEnd;

  /// What follows the number — `%`, ` px`, `°`.
  ///
  /// ⛔THE DIGITS ARE NOT HERE and are not the caller's: the bar reads its
  /// own step for those (F-34, [_decimals]).
  final String unit;

  /// The factor between the number the MODEL holds and the number the bar
  /// WRITES — 100 for a 0..1 opacity shown as per cent.
  ///
  /// A field rather than arithmetic at the call site because the digit rule
  /// has to read the step THROUGH it: a per-cent bar with a hundred
  /// divisions steps by a whole per cent, and only this says so.
  final double displayScale;

  /// Replaces the number for values that do not READ as one — `off`, `Auto`,
  /// `L50`. It is handed the value AND the text the bar would have written,
  /// so an exception decorates the derived number instead of deriving a
  /// second one with a digit count of its own.
  final String Function(double value, String derived)? valueTextBuilder;

  /// Fill/edge color while NOT interacting; the drag always paints the
  /// accent (the legend's master-opacity bar reads gray at rest, accent
  /// while adjusting — R4 #6). Null = accent always.
  final Color? restingAccent;

  /// Inside-left label; `null` renders the micro variant (value only).
  final String? label;

  /// What the bar reads WHILE NOBODY IS TOUCHING IT, when that is not its
  /// number at all: the legend's master bar reads `OPAC` at rest and its per
  /// cent while it is being dragged (R4 #6). Null = the number, always.
  final String? restingText;

  final FieldSliderScale scale;

  /// Snaps values to `divisions` equal steps (linear scale only).
  final int? divisions;

  /// The values a STEP moves between — the +/− buttons and the wheel go
  /// to the next one above or below the value, wherever it stands; null
  /// steps along the track ([_FieldSliderState._stepBy]). A drag is not
  /// stepped: it lands where it is let go.
  ///
  /// 🗣️F-325 (유저 2026-10-09): 「브러시 사이즈의 + -버튼인 한걸음 조정
  /// 버튼, 툴 사이즈 패널의 프리셋을 그대로 따름」 — the brush size's step is
  /// the rack the tool size panel shows. ⚠️「그대로」: the stops ARE the
  /// step, so Shift asks for no finer one on a bar that has them.
  final List<double>? stops;

  /// The value the filled bar grows FROM; null means [min], which is what a
  /// quantity wants (a fader reads "how much"). A BALANCE — pan, a signed
  /// offset — passes its neutral value instead, so the fill leaves centre
  /// in the direction of the setting and hard-left stops reading as empty.
  final double? fillOrigin;

  /// The bar's extent ACROSS its axis — thickness, not length. The length
  /// always comes from the host.
  final double height;

  /// Whether the bar writes its [label] inside, at its left — false for a
  /// grid's bar ([FieldSlider.cell]), whose name stands in its row, and for
  /// the canvas's brush pill, whose stood bars write their number alone
  /// (I-34, 유저 2026-10-18: 「숫자만으로 하자」). Either way the bar keeps
  /// its hands, and its [label] still names it to a screen reader.
  final bool nameInside;

  /// Whether a stood bar writes its number STANDING UP — down the bar, one
  /// glyph to a cell ([uprightDigits]) — rather than as the row turned on
  /// its side.
  ///
  /// 🗣️I-125-Q1 (유저 2026-10-23): the brush pill's bars — 「숫자가 옆으로
  /// 누워있어서 읽기 힘든게 큰 단점」. The x-sheet's stood rail still lies
  /// (유저 2026-09-10: 「세로쓰기 세로표기」; I-125-Q2 a, the pill alone).
  final bool upright;

  /// How many digits a standing number sets in one cell: one — 「한 글자씩
  /// 한 칸」 (F-460-Q1, 유저 2026-10-23: 「2/0/0/0/./0 이렇게 위에서
  /// 한글자씩 한칸 차지하는거랑 동일」). ↩️Three, 「B 縦中横(두세 자리를 한
  /// 칸에)」 (I-125-Q1): `10.0` was 10 / . / 0 while `2000.0`, a run too
  /// long to set across, already stood a digit to a cell.
  static const int uprightDigits = 1;

  /// A settings row's bar — and the number box beside it, which wears this
  /// bar's face without the fill ([DragValueLabel.box]).
  static const double defaultHeight = 24;

  /// What a settings bar's HANDS — its ± and its pencil ([ValueSteps],
  /// [ValuePencil]) — take of its row, gaps included: the end column a
  /// settings grid keeps on every row ([ToolSettingEnd]).
  static const double handsReach = valueHandsReach;

  /// How round a bar [height] thick is cornered.
  static double radiusFor(double height) => height < 20 ? 3 : 4;

  /// The bar's FRAME — its ground and its hairline, each dimmed as a
  /// disabled bar draws it. One face for the bar and the number box
  /// (tool-settings-panel-tidy, 유저 2026-10-10: the box is 「다른 도구의
  /// 숫자 상자와 같은 모양」).
  ///
  /// [typed]: the frame of a bar or a box being typed in. Its field runs
  /// the whole of it, so the frame is the field's, in the accent a focused
  /// field wears (유저 2026-10-11: 「X 글자 없애고 최대치로 잡아도 될거같은데.
  /// 다른박스 마찬가지 통일」).
  static ShapeDecoration frameOf(
    double height, {
    required bool enabled,
    bool typed = false,
  }) => ShapeDecoration(
    color: dimmedIfDisabled(AppColors.surface, enabled: enabled),
    shape: AppShapes.container(
      radiusFor(height),
      side: BorderSide(
        color: typed
            ? AppColors.accent
            : dimmedIfDisabled(AppColors.hairline, enabled: enabled),
      ),
    ),
  );

  /// What a bar drawn [height] at 1× adds where it is shown: its one line
  /// of words (the value, set in the theme's `labelSmall`) grown under the
  /// OS text size — 0 at 1×, so nothing drawn at 1× moves.
  ///
  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
  /// 따라 자란다」) grew the timeline's zoom bar with a copy of this; the
  /// rail's opacity bars, the legend's master bar and the storyboard's
  /// asked the same (text-scale-rail-rows, 유저 2026-09-24: 「행도 글자
  /// 크기를 따라 자란다」 — 🔬at 1.5× the rail's digits wanted 24 in 18).
  static double growthIn(BuildContext context) => TextMeasure(
    context,
    Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
  ).lineGrowthOf(TextMeasure.everyScript);

  /// What the writing stands in from each end of the track.
  static const double inset = 8;

  /// The least a name and its number stand apart and still read as two —
  /// about a word space at the size the bar writes in.
  /// ⚠️My number, not a ruling: the answer below said to MEASURE the width,
  /// and a measure with nothing between the two has them touch at the
  /// widest number. Kept small because that number is the rare one (a
  /// 2000px brush) and every pixel here is window the bars give up early.
  static const double _breath = 4;

  /// The narrowest this bar can be and still write its name and the widest
  /// thing it says whole: the track's insets, the words measured in the
  /// styles the bar writes them in, a breath between the name and the
  /// number, and its hands where it carries them — the bar's own parts, so
  /// the width is measured rather than guessed.
  ///
  /// The number at an END of its range, never the one it holds: a floor
  /// that moved with the value would move whatever stands beside the bar
  /// while it is being dragged.
  ///
  /// 🗣️top-strip-narrow-overflow-Q1 (유저 2026-10-01, the answer as
  /// corrected): 「막대 먼저 줄어들고 다음 목록으로」 — 「이름과 숫자가 막대
  /// 안에 들어가는 최소 폭까지 줄어든다(최소 폭은 실측해서 정한다)」. Below
  /// this the name gives way to an ellipsis, which is where a bar stops
  /// saying what it is.
  double narrowestIn(BuildContext context) {
    final words = [_textFor(min), _textFor(max), ?restingText];
    final hands = _carriesHands ? handsReach : 0.0;
    if (upright) {
      // A standing number's column keeps the track's insets as its ends.
      return words
              .map(
                (word) =>
                    _standing(context, word).naturalSizeIn(context).height,
              )
              .reduce(math.max) +
          hands;
    }
    final name = label;
    final nameRun = name == null || !nameInside
        ? 0.0
        : TextMeasure(
                context,
                Theme.of(context).textTheme.labelSmall,
              ).size(name).width +
              _breath;
    return inset * 2 +
        nameRun +
        TextMeasure(context, valueStyleIn(context)).widest(words) +
        hands;
  }

  /// [word] as an [upright] bar writes it, the ground under it in [inks]:
  /// at the far end of the bar, where a lying bar writes its number — or
  /// in the middle, where a nameless one does.
  VerticalWritingText _standing(
    BuildContext context,
    String word, {
    List<GroundInkRun>? inks,
  }) =>
      VerticalWritingText(
        text: word,
        style: valueStyleIn(context),
        tateChuYokoDigits: uprightDigits,
        latinForm: VerticalLatinForm.upright,
        mainAlignment: label == null ? 0.5 : 1,
        endInset: inset,
        inks: inks,
      );

  /// Whether this is the kind of bar that carries the hands — the +/− pair
  /// and the pencil — the rule is [_FieldSliderState._withHands]'s, and
  /// this is its one statement.
  bool get _carriesHands => label != null;

  /// How many digits this bar writes after the point — THE SAME COUNT AT
  /// EVERY VALUE, which is the whole of F-34 (유저 확정 2026-09-01: 「위젯이
  /// 자기 스텝을 보고 자릿수를 고른다」).
  ///
  /// The only question is 「can this bar land BETWEEN two whole numbers?」:
  ///  * an EXPONENTIAL sweep multiplies, so it lands anywhere;
  ///  * a bar with no [divisions] is continuous, so it lands anywhere;
  ///  * otherwise every reachable value is `min + k·step`, whole for every
  ///    k exactly when min and step are both whole — IN DISPLAY UNITS,
  ///    which is what [displayScale] is for.
  ///
  /// ⛔It does not ask what the CURRENT value is. That is the bug: a rule
  /// that hides the decimal for a whole value makes the digit count appear
  /// and disappear under the finger, which is 「없다가 생기는 UI」.
  int get _decimals {
    final divisions = this.divisions;
    if (scale == FieldSliderScale.exponential || divisions == null) {
      return 1;
    }
    final step = (max - min) * displayScale / divisions;
    final origin = min * displayScale;
    return _isWhole(step) && _isWhole(origin) ? 0 : 1;
  }

  static bool _isWhole(double value) =>
      (value - value.roundToDouble()).abs() < 1e-9;

  /// The text this bar writes for [value] — the ONE place that is decided.
  /// (On the bar rather than on its state since 2026-10-07: [narrowestIn]
  /// asks it of a bar that is not on screen.)
  String _textFor(double value) {
    final derived = readoutText(
      value * displayScale,
      decimals: _decimals,
      unit: unit,
    );
    return valueTextBuilder?.call(value, derived) ?? derived;
  }

  // The bar's own arithmetic — where a value sits along the track, the
  // value at a place on it, where a step lands. Read off the bar's
  // settings alone, so it lives with them, as [_textFor] does.

  /// Where [value] sits along the track, 0..1.
  double _tFor(double value) {
    final double t;
    switch (scale) {
      case FieldSliderScale.linear:
        t = (value - min) / (max - min);
      case FieldSliderScale.exponential:
        t = math.log(value / min) / math.log(max / min);
    }
    return t.clamp(0.0, 1.0);
  }

  /// The value at [t] along the track, snapped to [divisions].
  double _valueFor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    double value;
    switch (scale) {
      case FieldSliderScale.linear:
        value = min + clamped * (max - min);
      case FieldSliderScale.exponential:
        value = min * math.pow(max / min, clamped);
    }
    final divisions = this.divisions;
    if (divisions != null) {
      final step = (max - min) / divisions;
      value = min + ((value - min) / step).round() * step;
    }
    return value.clamp(min, max);
  }

  /// Where one step [direction] from [value] lands: the next of the
  /// [stops], or one notch along the track — a [fine] one when Shift is
  /// held. Null when the stops run out that way.
  double? _stepFrom(double value, int direction, {required bool fine}) {
    if (stops != null) {
      return _stopPast(value, direction)?.clamp(min, max).toDouble();
    }
    final divisions = this.divisions;
    final double step;
    if (divisions != null) {
      step = 1.0 / divisions;
    } else {
      step = fine ? 0.001 : 0.01;
    }
    return _valueFor((_tFor(value) + direction * step).clamp(0.0, 1.0));
  }

  /// The stop next past [value] [direction] (+1 up, −1 down); null past
  /// the last.
  ///
  /// ⚠️A stop the bar WRITES [value] as is not the next one: a drag that
  /// left 10.03 reads 「10.0」, and a step from it to 10 would be a press
  /// that shows nothing.
  double? _stopPast(double value, int direction) {
    final shown = _textFor(value);
    double? next;
    for (final stop in stops!) {
      if (_textFor(stop) == shown || (stop > value) != (direction > 0)) {
        continue;
      }
      if (next == null || (stop < next) == (direction > 0)) {
        next = stop;
      }
    }
    return next;
  }

  /// The style a bar writes its value in — the theme's `labelSmall`, set
  /// solid.
  static TextStyle? valueStyleIn(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        // ⛔NO LETTER SPACING ON THE NUMBER. `labelSmall` carries 0.5 and
        // Flutter lays it after the LAST glyph too, so a centred `50` sits
        // half a space left of centre — 유저 2026-09-10: 「해당 불투명도
        // 슬라이더의 텍스트가 제대로 중앙정렬이 아닌거같음. **두자리수가
        // 미묘하게 왼쪽에 치우쳐있음**」. A number is set solid; the LABEL
        // beside it is a word and keeps the theme's spacing.
        letterSpacing: 0,
      );

  /// How much wider [words] run in the value style here than at 1× — what a
  /// bar sized around them at 1× adds across (text-scale-rail-columns).
  static double widthGrowthIn(BuildContext context, Iterable<String> words) =>
      TextMeasure(context, valueStyleIn(context)).widthGrowthOf(words);

  /// Which way the track runs. Vertical fills upward from the bottom and
  /// is dragged up/down — the x-sheet's stood-up rail, where a 28px column
  /// has no room for a horizontal fader, and the canvas's brush pill (I-34).
  ///
  /// ⛔THE BAR ITSELF IS NEVER A `RotatedBox`: the horizontal recognizer
  /// judges by the pointer's GLOBAL delta direction in the arena, so a
  /// turned slider would never receive an on-screen vertical drag at all.
  /// Its WRITING is turned, which is a different question — see [build].
  final Axis axis;

  @override
  State<FieldSlider> createState() => _FieldSliderState();
}

class _FieldSliderState extends State<FieldSlider> {
  /// The ink over each stretch of the bar: the text-on-ground law
  /// ([textOnColor]) over the fill and over the empty track, changing part
  /// way through a word where the fill ends.
  ///
  /// 🚨H38 again (유저 2026-09-11): 「공용 슬라이더 텍스트말인데, 검정색으로
  /// 하니 뒤가 비어있으면 안보인다. 그러니까 그냥 저번에 한대로 뒤 색에 따라
  /// 하양/검정 바꾸는거 있잖아. 그거대로 하자」. ↩️The history, so neither
  /// fixed ink comes back as a "fix": 09-08 laid the law on the bar (a
  /// `ShaderMask` over the fill's edge); 09-10 fixed it white — 「공용
  /// 색바뀌는 텍스트ui 쓰는게아니라 흰색 고정」; the morning of 09-11 (H38)
  /// fixed it black — 「그냥 검정색으로 통일해보자. 흰색 좀 보기힘들어」; and
  /// black vanished over the empty track. The law is back through
  /// [GroundInkWriting], without the mask's offscreen layer. (A brush row's
  /// name shared it from H38 again until F-82 put that name on a plate.)
  ///
  /// Label and value stay ONE ink per ground: 09-10 flattened their dim and
  /// bright pair by decision, and that is not what was reversed.
  List<GroundInkRun> _inkRuns(double t, Color accent) {
    final near = math.min(_originFraction, t);
    final far = math.max(_originFraction, t);
    // A stood-up bar's writing is the row turned a quarter clockwise, so its
    // x runs DOWN the bar while the fill grows UP it.
    //
    // ⚠️The ink is chosen against the ground at FULL strength and dimmed
    // after: which ink reads on a ground is a fact about the ground, and a
    // disabled bar must not flip from black to white because its fill went
    // pale.
    return groundInkRunsForFill(
      near: _vertical ? 1 - far : near,
      far: _vertical ? 1 - near : far,
      onFill: _asDrawn(textOnColor(accent)),
      onTrack: _asDrawn(textOnColor(AppColors.surface)),
    );
  }

  /// [color] the way this bar draws it — dimmed when the bar is disabled.
  ///
  /// 🚨★★★**A DISABLED BAR DIMS WITHOUT A LAYER** (유저 확정 2026-09-22,
  /// 보드 `a-disabled-bar-dims-without-a-layer-Q1`: 「요소별로 흐리게
  /// 칠한다」).
  ///
  /// 🪦An `Opacity(0.4)` wrapped the whole bar here. It is a COMPOSITING
  /// BOUNDARY — `RenderOpacity` composites at any alpha above zero — and a
  /// boundary anywhere inside a panel makes that panel's [StaticRaster]
  /// give up and pay its full raster price on EVERY frame the app produces,
  /// looking identical while doing it. 🔬One disabled bar cost the whole
  /// brush settings panel its bake (measured 2026-09-22; the panel sweep
  /// `panel_static_raster_test` is what found it, having just learned to
  /// open the rail groups, and it is what keeps it gone).
  ///
  /// ⚠️What changed for the eye: a layer dims the bar ONCE, after its
  /// pieces have covered each other; this dims each piece. Where the value
  /// text sits over the fill, the fill now shows through the text at 24%.
  /// The same 40% reading, and every pixel that is not an overlap is the
  /// pixel that was there before.
  ///
  /// ⛔The 40% and the reason for it are [disabledInkOpacity]'s, not this
  /// widget's: the pressure-curve well dims to the same figure on purpose
  /// (「a disabled group reads as one thing rather than as three different
  /// greys」), and two widgets spelling one rule is how the two drift.
  Color _asDrawn(Color color) => dimmedIfDisabled(color, enabled: _enabled);

  /// The track's length along [FieldSlider.axis].
  double _trackExtent = 0;

  void _takeTrackExtent(double extent) => _trackExtent = extent;

  /// The hands — the +/− pair and the pencil — as last built, and what
  /// they were built from.
  ///
  /// 🔬H40 (유저 2026-09-11): 「고를때 렉있어서 그부분도 효율적으로 가볍게
  /// 하고싶어」. A bar rebuilds for every value it is handed and every frame
  /// of a drag, and the pair — two buttons, their tooltips, their ink —
  /// changes with none of that: only with the bar's height and its axis,
  /// whether it takes the gesture, and the language its tooltips speak.
  Widget? _hands;
  Object? _handsFor;

  /// Whether the bar is being typed into: its pencil opened the field
  /// ([ValuePencil]), and the bar stands as a box holding it until Enter,
  /// a press elsewhere, or Escape.
  bool _typing = false;

  void _beginTyping() => setState(() => _typing = true);

  /// A typed number, in the units the bar writes ([FieldSlider
  /// .displayScale]): held to the bar's range and its steps, and handed
  /// over as a drag's release is — one complete edit.
  void _typed(String text) {
    setState(() => _typing = false);
    final typed = columnValueOf(text);
    if (typed == null || !_enabled) {
      return;
    }
    final kept = (typed / widget.displayScale).clamp(widget.min, widget.max);
    final value = widget._valueFor(widget._tFor(kept));
    _emit(value);
    widget.onChangeEnd?.call(value);
  }

  bool get _vertical => widget.axis == Axis.vertical;

  /// Where a pointer sits along the track, 0..1.
  ///
  /// The vertical bar fills UPWARD — a fader's direction, and the same one
  /// the horizontal bar reads left-to-right — so the axis position is
  /// measured from the bottom.
  double _trackT(Offset localPosition) {
    if (_trackExtent <= 0) {
      return 0;
    }
    final along = _vertical
        ? _trackExtent - localPosition.dy
        : localPosition.dx;
    return (along / _trackExtent).clamp(0.0, 1.0);
  }

  double _deltaT(Offset delta) {
    if (_trackExtent <= 0) {
      return 0;
    }
    return (_vertical ? -delta.dy : delta.dx) / _trackExtent;
  }

  // Gesture-local position in t-space (0..1). Owned by the active drag so
  // Shift's relative fine mode has something to accumulate against; display
  // always derives from widget.value (the widget stays fully controlled).
  double? _gestureT;

  // ⛔Four fields left with the workaround they served (유저 확정
  // 2026-08-14): the pre-down value to restore, the pointer's down position
  // and its signed travel from there — which together decided whether a
  // rival "legitimately" owned the gesture — and the rival's scroll slop
  // that travel was measured against.
  //
  // All four existed to answer *did someone take this from me, and were
  // they entitled to?* Nobody can take it any more — the recogniser accepts
  // on the first movement — so the question has no askers left, and a
  // restore path that never runs is a trap for whoever reads it next.

  bool get _enabled => widget.onChanged != null;

  void _emit(double value) => widget.onChanged?.call(value);

  void _handleDown(DragDownDetails details) {
    if (!_enabled) {
      return;
    }
    if (_trackExtent <= 0) {
      return;
    }
    // setState: the bar ECHOES the gesture locally (R4 #4/#5) — commit-on-
    // release consumers don't rebuild the parent per move, so the display
    // must follow from gesture state, not widget.value.
    setState(() {
      _gestureT = _trackT(details.localPosition);
    });
    _emit(widget._valueFor(_gestureT!));
  }

  void _handleUpdate(DragUpdateDetails details) {
    if (!_enabled || _trackExtent <= 0) {
      return;
    }
    final current = _gestureT ?? widget._tFor(widget.value);
    setState(() {
      if (ModifierKeys.isShiftPressed) {
        _gestureT = (current + _deltaT(details.delta) / 10).clamp(0.0, 1.0);
      } else {
        _gestureT = _trackT(details.localPosition);
      }
    });
    _emit(widget._valueFor(_gestureT!));
  }

  void _handleEnd(DragEndDetails details) {
    final t = _gestureT;
    setState(() => _gestureT = null);
    if (t != null) {
      widget.onChangeEnd?.call(widget._valueFor(t));
    }
  }

  /// The drag recognizer lost the pointer. What that MEANS depends on WHICH
  /// WAY the pointer went.
  ///
  /// ★THE BAR KEEPS WHAT MOVED ALONG ITS OWN AXIS. Only travel ACROSS the
  /// bar — the direction a scrollable above us scrolls — can mean the
  /// gesture was taken, so only that direction rolls the value back.
  /// Everything else is a tap, and a tap sets the value: the bar's whole
  /// job is to answer one immediately (R10 R5 retired the double-tap editor
  /// for exactly this).
  ///
  /// 🐛 This USED to ask how FAR the pointer had travelled, in any
  /// direction, and call anything past 6px a scroll. Which quietly made a
  /// wobble into a cancellation: a stylus tap that slid 8px sideways —
  /// still nowhere near the 18px a scrollable needs, so nothing had taken
  /// anything — rolled the value straight back, and the bar read as dead.
  /// 유저, R6 #1: "툴설정은 뭔가 제스쳐 경합된다고? 6px인가 안움직이면
  /// 변경인가 그랬는데 이거 진짜 못없애나? 아직도 불편해 ... 상단띠
  /// 브러시사이즈 변경처럼 대충눌러도 바뀌도록하고싶음."
  ///
  /// A DISTANCE cannot express the rule, because the two cases it has to
  /// separate are not near and far — they are along and across. So there is
  /// no tap slop here and no number of our own.
  ///
  /// ★THIS WAS THE PRECEDENT, and the whole app reached it on 2026-08-30:
  /// 유저, on finding a device slop still being consulted for buttons —
  /// 「**1px 이동했는지 같은 px 이동으로 판단하는거** 설마 아직도 남아있나?
  /// 내가 다른방법 제안하지 않았어?」 · 「싹 깔끔하게 걷어내」. A button
  /// answers 「click or not」 by where the finger came UP, a slider by which
  /// way it went; neither needs a distance. See [ControlPressClaim].
  ///
  /// 🚨 A cancel is the NORMAL end of a tap, not an error path — a drag
  /// recognizer that never met its threshold rejects itself when the
  /// pointer lifts, so this runs on every tap the bar ever receives,
  /// scrollable above or not. That is why the top strip and the tool
  /// settings only ever differed here: a desktop `Scrollable` puts a drag
  /// recognizer in the arena for touch and stylus alone, so a MOUSE tap had
  /// no rival to lose to and a PEN tap did.
  /// Wires one drag recogniser. Both axes take the same four handlers, so
  /// the vertical and horizontal factories cannot drift apart.
  void _configureDrag(DragGestureRecognizer recognizer) {
    // Down, not start: the bar answers the press itself (R9 #12's rule for
    // grips) — and with acceptance now on the first movement there is no
    // slop left to discard anyway.
    recognizer
      ..dragStartBehavior = DragStartBehavior.down
      ..onDown = _handleDown
      ..onUpdate = _handleUpdate
      ..onEnd = _handleEnd
      ..onCancel = _handleCancel;
  }

  void _handleCancel() {
    final t = _gestureT;
    setState(() => _gestureT = null);
    // ⛔The 「did the pointer cross my axis far enough that the rival owns
    // this?」 branch is GONE (유저 확정 2026-08-14: 「슬라이더위에서 조작하기
    // 시작하면 슬라이더조작하는거고 그 외가 스크롤인거야」). There is no
    // rival to lose to any more — the recogniser takes the arena on the
    // first movement — so a cancel can only mean the one thing left:
    //
    // ★a TAP. A drag recogniser that never moved rejects itself when the
    // pointer lifts, so this is the normal end of every tap the bar
    // receives, not an error path. Pointer-down already emitted the value;
    // only the commit is owed.
    if (t != null) {
      widget.onChangeEnd?.call(widget._valueFor(t));
    }
  }

  void _handleWheel(PointerScrollEvent event) {
    if (event.scrollDelta.dy == 0) {
      return;
    }
    _stepBy(event.scrollDelta.dy < 0 ? 1 : -1);
  }

  /// One notch [direction] (+1 up, -1 down).
  ///
  /// 🚨★THE ONE PLACE A STEP IS DEFINED. The wheel and the +/− buttons are
  /// two ways of asking for the same thing, and 유저 확정 (2026-09-08) says
  /// so outright: 「`+1` = 휠과 같은 걸음」. Two implementations would be one
  /// question with two answers, and they would drift the first time either
  /// scale changed.
  ///
  /// A step is a COMPLETE edit — there is no release to wait for — so
  /// commit-on-release consumers get their commit right away.
  void _stepBy(int direction) {
    if (!_enabled) {
      return;
    }
    final value = widget._stepFrom(
      widget.value,
      direction,
      fine: ModifierKeys.isShiftPressed,
    );
    if (value == null) {
      return;
    }
    _emit(value);
    widget.onChangeEnd?.call(value);
  }

  double get _radius => FieldSlider.radiusFor(widget.height);

  /// Where the fill starts, in track space — 0 for a quantity, the neutral
  /// value for a balance ([FieldSlider.fillOrigin]).
  double get _originFraction => widget.fillOrigin == null
      ? 0.0
      : widget._tFor(widget.fillOrigin!).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall;
    final valueStyle = FieldSlider.valueStyleIn(context);
    // An active gesture echoes locally (snapped like the emitted value);
    // otherwise display derives from widget.value (fully controlled).
    final gestureT = _gestureT;
    final dragging = gestureT != null;
    final t = dragging
        ? widget._tFor(widget._valueFor(gestureT))
        : widget._tFor(widget.value);
    final valueText = dragging
        ? widget._textFor(widget._valueFor(gestureT))
        : widget.restingText ?? widget._textFor(widget.value);
    if (_typing) {
      return _withHands(
        _FieldSliderTypedFace(
          bar: widget,
          valueText: valueText,
          onSubmit: _typed,
          onCancel: () => setState(() => _typing = false),
        ),
      );
    }

    final accent = dragging
        ? AppColors.accent
        : (widget.restingAccent ?? AppColors.accent);
    Widget writingIn(TextStyle ink) {
      final value = valueStyle?.merge(ink) ?? ink;
      if (widget.label == null) {
        return Center(
          child: Text(
            valueText,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: value,
          ),
        );
      }
      if (!widget.nameInside) {
        // A grid's bar: the name stands in the row, the number where a
        // named bar writes it.
        return Align(
          alignment: Alignment.centerRight,
          child: Text(valueText, maxLines: 1, style: value),
        );
      }
      return Row(
        children: [
          Expanded(
            child: Text(
              widget.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle?.merge(ink) ?? ink,
            ),
          ),
          Text(valueText, maxLines: 1, style: value),
        ],
      );
    }

    // 🚨A STOOD-UP BAR IS THE ROW, TURNED — 세로쓰기 세로표기 (유저
    // 2026-09-10: 「x시트의 불투명도바는 **세로쓰기 세로표기**로 바꾸자」).
    // That is the reading 유저 named on 2026-08-24 for the SE blocks —
    // 「se블록의 이름이 세로쓰기세로표기 인거같은데, 가로쓰기 세로표기가
    // 되도록」, where the before state was `VerticalLatinForm.sideways`:
    // the glyphs LIE DOWN and the line reads along the column.
    //
    // ⛔It is NOT the vertical-writing table any more. That stacked one
    // glyph per cell and set `100%` as three-digit 縦中横 to keep it to two
    // cells — a horizontal number inside a vertical column, which is
    // exactly the 가로쓰기 the user is asking away from.
    // ↩️The table is back where a bar asks for it ([FieldSlider.upright]):
    // the brush pill's, by I-125-Q1 — a glyph to a cell since F-460-Q1.
    //
    // ⚠️A `RotatedBox` HERE and never around the bar: the writing has no
    // gesture, while a turned recognizer would never see an on-screen
    // vertical drag at all (see [FieldSlider.axis]).
    // The ink follows the ground under it — see [_inkRuns]. The writing's
    // box is the whole track, padding and all, so the runs' fractions are the
    // painter's.
    final runs = _inkRuns(t, accent);
    final inner = widget.upright
        ? SizedBox.expand(
            child: widget._standing(context, valueText, inks: runs),
          )
        : GroundInkWriting(
            runs: runs,
            builder: (context, ink) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FieldSlider.inset,
              ),
              child: writingIn(ink),
            ),
          );

    Widget bar = _TrackExtentProbe(
      axis: widget.axis,
      onExtent: _takeTrackExtent,
      child: DecoratedBox(
        decoration: FieldSlider.frameOf(widget.height, enabled: _enabled),
        child: SuperellipseClip(
          shape: AppShapes.container(_radius),
          child: CustomPaint(
            painter: _FieldSliderTrackPainter(
              axis: widget.axis,
              t: t,
              originT: _originFraction,
              accent: _asDrawn(accent),
            ),
            child: acrossBox(
              widget.axis,
              widget.height,
              child: _vertical && !widget.upright
                  ? RotatedBox(quarterTurns: 1, child: inner)
                  : inner,
            ),
          ),
        ),
      ),
    );

    if (!_enabled) {
      // ⛔THE STEPPER STILL STANDS THERE, dimmed and inert. A disabled bar
      // that dropped it would be 「없다가 생기는 UI」 — the row would be
      // wider the moment the control came alive, and everything beside it
      // would shift.
      //
      // 🪦The `Opacity(0.4)` that stood here is gone: the bar's pieces dim
      // themselves ([_asDrawn]) so that a disabled bar is not a compositing
      // boundary inside its panel.
      return _withHands(bar);
    }
    bar = MouseRegion(
      cursor: _vertical
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      // ★유저 확정 2026-08-14: a press that lands on the bar is the bar's,
      // scrolling included. These recognisers take the arena on the FIRST
      // movement instead of at a slop, so no ancestor scrollable is ever in
      // a position to take the gesture away — see [axis_bar_gesture].
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: _vertical
            ? <Type, GestureRecognizerFactory>{
                OwningVerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      OwningVerticalDragGestureRecognizer
                    >(
                      () =>
                          OwningVerticalDragGestureRecognizer(debugOwner: this),
                      _configureDrag,
                    ),
              }
            : <Type, GestureRecognizerFactory>{
                OwningHorizontalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      OwningHorizontalDragGestureRecognizer
                    >(
                      () => OwningHorizontalDragGestureRecognizer(
                        debugOwner: this,
                      ),
                      _configureDrag,
                    ),
              },
        child: bar,
      ),
    );
    final claimed = Semantics(
      // 🚨ITS OWN SEMANTICS BOUNDARY (2026-09-26). A value that changes lays
      // its writing out again, and every layout re-walks the nearest
      // boundary's whole share of the semantics tree — without one here that
      // was the panel's scroll view, about a thousand nodes for one number.
      // The bar was a node of its own already; this stops the walk at it.
      container: true,
      slider: true,
      label: widget.label,
      value: valueText,
      // T11: this press is the slider's. The claim is [DragVerbClaim] now —
      // the same four lines used to sit here, in the splitter and in the
      // rail's swipe column, three copies of one law.
      child: DragVerbClaim(
        child: Listener(
          // What is left here is the WHEEL. The raw travel this used to
          // track went with the workaround that read it.
          //
          // H23: registered rather than handled, so the notch this bar takes
          // is not also taken by the canvas layer above it.
          onPointerSignal: (event) =>
              handleWheelUnlessScrolling(event, context, _handleWheel),
          child: bar,
        ),
      ),
    );
    return _withHands(claimed);
  }

  /// [bar] with its hands beside it — the +/− pair and the pencil
  /// ([ValueSteps], [ValuePencil]) — when this is the kind of bar that
  /// carries them.
  ///
  /// 🚨★THERE ARE TWO KINDS OF BAR, AND THE VARIANT DECIDES WHICH — not the
  /// call site (유저 2026-09-09: 「슬라이더는 2개로 두자. 스텝퍼 적용 미적용
  /// 규칙. **초소형 변형은 기본적으로 빼도록**」).
  ///
  /// * A LABELLED bar is a settings row. It has room, it is read and nudged
  ///   deliberately, and it gets the hands — the pencil since 유저
  ///   2026-10-10 (tool-settings-panel-tidy): 막대에도 연필을 「달도록」.
  /// * The MICRO variant (`label == null`) is the inline slot — a timeline
  ///   layer row, a lane header — where the whole control is already down to
  ///   a number in a gap. More buttons there would take the track it has
  ///   left, and the value is not being tuned to a digit in that context.
  ///
  /// ⛔NO PER-SITE FLAG. A boolean here is how the two kinds stop being two
  /// kinds — the same trap `ControlPressClaim` names about its own scope: the
  /// panels would grow bars that disagree with the rows beside them.
  ///
  /// A STOOD bar carries them too, turned with it — under it, the pair lying
  /// across its width (the canvas's brush pill, I-34). ↩️Vertical bars were
  /// left out while the only one was the x-sheet's turned rail, whose row
  /// has no room across at all; that one is the micro variant, and the
  /// variant is what keeps it bare.
  Widget _withHands(Widget bar) {
    if (!widget._carriesHands) {
      return bar;
    }
    // Kept while nothing they show changes (see [_hands]). Its [_stepBy]
    // reads the bar's value at press time, so a pair built under an earlier
    // value steps from the current one.
    final key = (
      widget.height,
      widget.axis,
      _enabled,
      AppText.strings.stepUp,
      AppText.strings.stepDown,
      AppText.strings.valueTypeIn,
    );
    final hands = _hands != null && _handsFor == key
        ? _hands!
        : Flex(
            direction: widget.axis,
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueSteps(
                keyPrefix: 'field-slider-step',
                height: widget.height,
                enabled: _enabled,
                onStep: _stepBy,
                axis: widget.axis,
              ),
              ValuePencil(
                keyValue: 'field-slider-type',
                height: widget.height,
                enabled: _enabled,
                onPressed: _beginTyping,
                axis: widget.axis,
              ),
            ],
          );
    _hands = hands;
    _handsFor = key;
    return Flex(
      direction: widget.axis,
      children: [
        Expanded(child: bar),
        hands,
      ],
    );
  }
}

/// The bar while it is typed in ([_FieldSliderState._typing]): its frame,
/// typed ([FieldSlider.frameOf]), and all of it the field — the number
/// alone, the law every typed number opens by ([readoutParts]), with no
/// name, no unit and no fill, as a number box typed in (`DragValueLabel`).
class _FieldSliderTypedFace extends StatelessWidget {
  const _FieldSliderTypedFace({
    required this.bar,
    required this.valueText,
    required this.onSubmit,
    required this.onCancel,
  });

  final FieldSlider bar;

  /// What the bar writes at rest — its number and its unit.
  final String valueText;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final parts = readoutParts(valueText);
    final part = parts.length == 1 ? parts.single : null;
    final ink = TextStyle(color: textOnColor(AppColors.surface));
    final style = FieldSlider.valueStyleIn(context)?.merge(ink) ?? ink;
    final field = Padding(
      padding: const EdgeInsets.symmetric(horizontal: FieldSlider.inset),
      child: Row(
        children: [
          Expanded(
            child: InlineNumericField(
              fieldKey: const ValueKey<String>('field-slider-type-input'),
              initialText: part?.number ?? valueText,
              textStyle: style,
              textAlign: TextAlign.right,
              onSubmit: onSubmit,
              onCancel: onCancel,
            ),
          ),
        ],
      ),
    );
    // A stood bar is typed in as it writes: the row turned a quarter
    // clockwise, its number at the foot ([FieldSlider.axis] — the writing
    // turns, and a field has no drag to lose by turning).
    final stood = bar.axis == Axis.vertical;
    return DecoratedBox(
      decoration: FieldSlider.frameOf(bar.height, enabled: true, typed: true),
      child: acrossBox(
        bar.axis,
        bar.height,
        child: stood ? RotatedBox(quarterTurns: 1, child: field) : field,
      ),
    );
  }
}

class _FieldSliderTrackPainter extends CustomPainter with RepaintOnProps {
  const _FieldSliderTrackPainter({
    required this.t,
    required this.accent,
    this.axis = Axis.horizontal,
    this.originT = 0.0,
  });

  /// Vertical fills UPWARD from the bottom — a fader's direction.
  final Axis axis;

  final double t;

  /// Where the fill starts, in track space — 0 for a quantity, 0.5 for a
  /// balance (see [FieldSlider.fillOrigin]).
  final double originT;

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final trackExtent = extentAlong(axis, size);
    // Along the axis, measured from the fill's ORIGIN edge — the left for
    // a horizontal bar, the BOTTOM for a vertical one.
    double along(double fraction) => axis == Axis.horizontal
        ? trackExtent * fraction
        : trackExtent * (1 - fraction);
    final fillEnd = along(t);
    final fillStart = along(originT);
    final near = math.min(fillStart, fillEnd);
    final far = math.max(fillStart, fillEnd);
    // 🚨THE FILL IS THE ACCENT ITSELF (유저 2026-09-08: 「그냥 깔끔하게 앱
    // 강조색 그대로 칠하도록. 이상한 세로선 넣지말고」).
    //
    // ⛔The 26%-alpha wash and the 2px accent edge that used to ride the
    // fill's end are BOTH gone, and they went together: the edge existed to
    // mark the position because a wash that pale did not read as an end. A
    // solid fill IS the position, so keeping the line would be marking the
    // same fact twice.
    final fill = Paint()..color = accent;
    if (far > near) {
      final extent = far - near;
      canvas.drawRect(
        rectAlong(
          axis,
          along: (from: near, to: near + extent),
          across: (from: 0, to: extentAcross(axis, size)),
        ),
        fill,
      );
    }
  }

  @override
  Object get props => (t, originT, axis, accent);
}

/// Hands the bar's length along its axis to the gesture math as the bar is
/// laid out — the one thing the bar needed a `LayoutBuilder` for.
///
/// 🚨NOT A LAYOUT BUILDER (2026-09-26). A layout builder re-runs its builder
/// on every rebuild, and that is a relayout — which climbs past the bar to
/// whatever the row's first relayout boundary is. In a settings panel that
/// is the scroll view's content: a brush pick handed every bar a new value
/// and laid out the whole panel column (91 render objects for 5 changed
/// numbers), and a drag did it on every move. Each object laid out is also
/// a semantics update — on a machine whose accessibility tree is on, the
/// pick's heaviest frame spent ~4 ms there. This lays the bar out exactly
/// as the builder did (its constraints, handed straight through) and asks
/// for nothing when the bar is only repainted.
class _TrackExtentProbe extends SingleChildRenderObjectWidget {
  const _TrackExtentProbe({
    required this.axis,
    required this.onExtent,
    required super.child,
  });

  final Axis axis;
  final ValueChanged<double> onExtent;

  @override
  _RenderTrackExtentProbe createRenderObject(BuildContext context) =>
      _RenderTrackExtentProbe(axis: axis, onExtent: onExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTrackExtentProbe renderObject,
  ) {
    renderObject
      ..axis = axis
      ..onExtent = onExtent;
  }
}

class _RenderTrackExtentProbe extends RenderProxyBox {
  _RenderTrackExtentProbe({required Axis axis, required this.onExtent})
    : _axis = axis;

  ValueChanged<double> onExtent;

  Axis get axis => _axis;
  Axis _axis;
  set axis(Axis value) {
    if (_axis == value) {
      return;
    }
    _axis = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    onExtent(extentAlong(_axis, constraints.biggest));
  }
}
