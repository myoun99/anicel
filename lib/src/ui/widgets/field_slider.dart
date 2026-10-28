import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
import '../timeline/memo_token.dart' show ByList, Kept, keptWhileSame;
import 'ground_ink_writing.dart';
import 'keyboard_press.dart';
import 'named.dart' show NamesItself;
import 'number_pad.dart';
import 'owning_axis_grip.dart';
import 'rail_glyph_button.dart' show RailPlateButton;
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

/// One thing a [FieldSlider.ceiling] shows under its value: a fill from 0
/// to [value], in [color].
typedef FieldSliderLevel = ({double value, Color color});

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
/// - A STOOD-UP bar writes the same row, turned a quarter clockwise — or
///   writes nothing, its number in a readout its host stands by it
///   ([readout]).
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
/// ↩️It types again, never on a tap of the bar: through its pencil since
/// 2026-10-10 ([ValuePencil]), and through its readout's press where its
/// readout stands for the pencil (I-135).
class FieldSlider extends StatefulWidget implements NamesItself {
  const FieldSlider({
    super.key,
    this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
    this.displayScale = 1,
    this.onChangeEnd,
    this.valueTextBuilder,
    this.restingText,
    this.color,
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
    this.readout,
  }) : levels = null,
       floor = null,
       assert(max > min, 'max must exceed min'),
       assert(
         !upright || (axis == Axis.vertical && (label == null || !nameInside)),
         'a bar stands its number up only stood, and writes the number alone',
       ),
       assert(
         readout == null || (axis == Axis.vertical && !upright),
         'a readout writes the number of a stood bar, which writes nothing',
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
    this.name,
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
       color = null,
       restingAccent = null,
       stops = null,
       levels = null,
       floor = null,
       height = defaultHeight,
       axis = Axis.horizontal,
       upright = false,
       readout = null,
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
    this.name,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.restingText,
    this.color,
    this.restingAccent,
    this.label,
    this.height = defaultHeight,
    this.axis = Axis.horizontal,
    this.nameInside = true,
    this.upright = false,
    this.readout,
  }) : assert(
         !upright || (axis == Axis.vertical && (label == null || !nameInside)),
         'a bar stands its number up only stood, and writes the number alone',
       ),
       assert(
         readout == null || (axis == Axis.vertical && !upright),
         'a readout writes the number of a stood bar, which writes nothing',
       ),
       min = 0,
       fillOrigin = null,
       max = 1,
       divisions = 100,
       stops = null,
       levels = null,
       floor = null,
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

  /// **A CEILING bar**: its value is a LIMIT, set over the [levels] it
  /// shows beneath it. The track is the whole scale, 0 to [max]; every level
  /// fills from 0 in its own colour, and the value is drawn as an OUTLINE
  /// over them, so what it limits stays in sight. It cannot be set under
  /// [floor]: a drag stops there rather than showing a value the setting
  /// would not take.
  ///
  /// 🗣️F-480 (유저 2026-10-27): the memory allowance's slider and the device
  /// bar under it — 「두번째 슬라이더랑 내용적으로 같아지니 내용 서로
  /// 합쳐서 통합」 — are one bar, the allowance outlined over the use
  /// (F-480-Q2 a: 「사용량 채움 위에 허용치 손잡이」).
  const FieldSlider.ceiling({
    super.key,
    this.name,
    required this.value,
    required this.max,
    required double this.floor,
    required List<FieldSliderLevel> this.levels,
    required this.onChanged,
    this.onChangeEnd,
    this.unit = '',
    this.color,
  }) : min = 0,
       displayScale = 1,
       valueTextBuilder = null,
       restingText = null,
       restingAccent = null,
       label = null,
       scale = FieldSliderScale.linear,
       divisions = null,
       stops = null,
       fillOrigin = null,
       height = defaultHeight,
       axis = Axis.horizontal,
       nameInside = true,
       upright = false,
       readout = null,
       assert(max > 0, 'max must exceed min'),
       assert(floor <= max, 'the floor stands on the scale');

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

  /// The bar's own fill/edge colour, at rest and while dragged alike — null
  /// is the app's accent.
  ///
  /// 🗣️F-474 (유저 2026-10-26): 「어니언스킨, 막대색이 지정된 색인거 좋은데,
  /// 막대 편집할때만 앱 강조색 되어있음 … 지정된 색으로 유지되도록」 — the
  /// onion bar's side tint is its colour, not a resting state: a separate
  /// question from [restingAccent]'s. ↩️The tint rode [restingAccent], and
  /// the drag painted the accent over it.
  final Color? color;

  /// Fill/edge color while NOT interacting; the drag paints [color] (the
  /// legend's master-opacity bar reads gray at rest, accent while adjusting
  /// — R4 #6). Null = [color] always.
  final Color? restingAccent;

  /// Inside-left label; `null` renders the micro variant (value only).
  final String? label;

  /// What a finder calls this bar ([NamesItself]) — its own, where a
  /// [Named] over it was an element more on every row that wears one (card
  /// frame-panels-build-in-one-frame, 2026-10-28).
  @override
  final String? name;

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

  /// What a [FieldSlider.ceiling] shows under its value, painted in order —
  /// a later level over an earlier one. Null on every other bar.
  final List<FieldSliderLevel>? levels;

  /// The least a [FieldSlider.ceiling] can be set to; its scale still starts
  /// at [min]. Null on every other bar.
  final double? floor;

  /// The bar's extent ACROSS its axis — thickness, not length. The length
  /// always comes from the host.
  final double height;

  /// Whether the bar writes its [label] inside, at its left — false for a
  /// grid's bar ([FieldSlider.cell]), whose name stands in its row, and for
  /// the canvas's brush pill, whose stood bars write their number alone
  /// (I-34, 유저 2026-10-18: 「숫자만으로 하자」) — ↩️above them since
  /// I-135, in their readouts ([readout]). Either way the bar keeps its
  /// hands, and its [label] still names it to a screen reader.
  final bool nameInside;

  /// Whether a stood bar writes its number STANDING UP — down the bar, one
  /// glyph to a cell ([uprightDigits]) — rather than as the row turned on
  /// its side.
  ///
  /// 🗣️I-125-Q1 (유저 2026-10-23): the brush pill's bars — 「숫자가 옆으로
  /// 누워있어서 읽기 힘든게 큰 단점」. The x-sheet's stood rail still lies
  /// (유저 2026-09-10: 「세로쓰기 세로표기」; I-125-Q2 a, the pill alone).
  /// ↩️The pill's bars stand nothing since their numbers stepped out of
  /// them ([readout]); the onion skin's pegs stand theirs.
  final bool upright;

  /// The link to this bar's number where it is written OUTSIDE the bar, in
  /// a readout its host stands by it ([FieldSliderValueReadout]) — the bar
  /// writes nothing in its track, and its readout is its pencil: the ±
  /// stay.
  ///
  /// 🗣️I-135 (유저 2026-10-27), the brush pill's bars: 「역시 사이즈 글자가
  /// 세로면 알기힘듬. 그러니 그냥 텍스트 독립시키자. 슬라이더 막대엔 텍스트
  /// 없애고, 연필버튼도 여기선 대체되니 없애고」.
  final FieldSliderReadout? readout;

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

  /// What the hands of a bar whose [readout] is its pencil take: its ±.
  static const double readoutHandsReach = ValueSteps.reach;

  /// What this bar's hands take of its run.
  double get _handsReach => readout == null ? handsReach : readoutHandsReach;

  /// How round a bar [height] thick is cornered.
  static double radiusFor(double height) => height < 20 ? 3 : 4;

  /// The bar's FRAME — its ground and its hairline, each dimmed as a
  /// disabled bar draws it. One face for the bar and the number box
  /// (tool-settings-panel-tidy, 유저 2026-10-10: the box is 「다른 도구의
  /// 숫자 상자와 같은 모양」).
  ///
  /// [typed]: the frame of a bar or a box being typed in — its number pad
  /// open ([showNumberPad]) — in the accent a focused field wears. ↩️Its
  /// field ran the whole of it, so the frame was the field's (유저
  /// 2026-10-11: 「X 글자 없애고 최대치로 잡아도 될거같은데. 다른박스 마찬가지
  /// 통일」), until the field moved into the pad (I-134).
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
    final hands = _carriesHands ? _handsReach : 0.0;
    if (readout != null) {
      // Its number is in its readout: nothing in its track asks room.
      return hands;
    }
    if (upright) {
      return standingRunIn(context) + hands;
    }
    final words = _saidAtEnds;
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

  /// How long a run the widest thing this bar says takes STANDING — a
  /// glyph to a cell, the track's insets as the column's ends, as an
  /// [upright] bar writes it.
  double standingRunIn(BuildContext context) => _saidAtEnds
      .map((word) => _standing(context, word).naturalSizeIn(context).height)
      .reduce(math.max);

  /// What this bar says at the ends of its range, and at rest where that is
  /// not its number — what it is sized around.
  List<String> get _saidAtEnds => [
    _textFor(min),
    _textFor(max),
    ?restingText,
  ];

  /// What this bar says while nobody is touching it.
  String get _saidAtRest => restingText ?? _textFor(value);

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

  /// The value at [t] along the track, snapped to [divisions] and [held].
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
    return held(value);
  }

  /// [value] as this bar holds it: in its range, and on the numbers it
  /// writes — [_decimals] digits after the point, in the units it writes
  /// them in ([displayScale]). Every value the bar hands over is one, by
  /// drag, tap, step or typing.
  ///
  /// 🗣️F-488 (유저 2026-10-27): 「브러시 크기 사이즈 슬라이더, 0.1대에서
  /// 슬라이더 움직이는데 0.1인채로 유지되는데 설마 0.1 밑의 소수점자리도
  /// 존재하는건가? … 소수점한자리까지만 존재하도록하고 아니면 조정가능한 값만
  /// 조정되도록. 슬라이더를 전부 그렇게」 — a bar handed over values it did
  /// not write, its fill sliding while its number stood still.
  double held(double value) {
    final written = _writtenPerUnit;
    // The least and the most it writes inside its range: an end it cannot
    // write — a 0.25 on a bar of tenths — is no value it holds either.
    final least = ((floor ?? min) * written - _slack).ceil();
    final most = (max * written + _slack).floor();
    if (least > most) {
      // A range inside one step of its last digit writes no number at all.
      return value.clamp(floor ?? min, max).toDouble();
    }
    return (value * written).round().clamp(least, most) / written;
  }

  /// How many of the last digit the bar writes one unit of its value holds.
  double get _writtenPerUnit =>
      math.pow(10, _decimals).toDouble() * displayScale;

  /// What a product of two doubles misses a whole number by: 0.7 × 10 is
  /// 7.000000000000001.
  static const double _slack = 1e-9;

  /// Where one step [direction] from [value] lands: the next of the
  /// [stops], or one notch along the track — a [fine] one when Shift is
  /// held. Null when the stops run out that way.
  ///
  /// A notch that would land on the number [value] writes moves it by the
  /// last digit instead: an exponential sweep's notch is less than a tenth
  /// under 0.2, and a step that writes the same number is no step (F-488).
  double? _stepFrom(double value, int direction, {required bool fine}) {
    if (stops != null) {
      final stop = _stopPast(value, direction);
      return stop == null ? null : held(stop);
    }
    final divisions = this.divisions;
    final double step;
    if (divisions != null) {
      step = 1.0 / divisions;
    } else {
      step = fine ? 0.001 : 0.01;
    }
    final next = _valueFor((_tFor(value) + direction * step).clamp(0.0, 1.0));
    final now = held(value);
    return next != now ? next : held(now + direction / _writtenPerUnit);
  }

  /// The stop next past [value] [direction] (+1 up, −1 down); null past
  /// the last.
  ///
  /// ⚠️A stop the bar WRITES [value] as is not the next one: a value set
  /// where the bar does not hold it — a brush's own 10.03 — reads 「10.0」,
  /// and a step from it to 10 would be a press that shows nothing.
  /// (↩️A drag left such values too, until the bar [held] what it hands
  /// over — F-488.)
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
    if (widget.levels != null) {
      return _inkRunsOverLevels();
    }
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

  /// A ceiling bar's levels, as where each ends along the track
  /// ([FieldSlider.ceiling]) — none on every other bar.
  List<({double t, Color color})> get _laidLevels => [
    for (final level in widget.levels ?? const <FieldSliderLevel>[])
      (t: widget._tFor(level.value), color: level.color),
  ];

  /// A ceiling bar's ink: the ground under each stretch of the writing is
  /// the level on top there, or the empty track past them all — the value's
  /// outline is an edge, not a ground.
  List<GroundInkRun> _inkRunsOverLevels() {
    final laid = _laidLevels;
    final ends = {
      for (final level in laid)
        if (level.t > 0) level.t,
      1.0,
    }.toList()..sort();
    Color groundUpTo(double end) => laid
        .lastWhere(
          (level) => level.t >= end,
          orElse: () => (t: 1.0, color: AppColors.surface),
        )
        .color;
    return [
      for (final end in ends)
        (end: end, ink: _asDrawn(textOnColor(groundUpTo(end)))),
    ];
  }

  /// What the track fills: the value, from its origin — or on a ceiling
  /// bar, its levels with the value's outline over them.
  CustomPainter _trackFill(double t, Color accent) => widget.levels == null
      ? _FieldSliderTrackPainter(
          axis: widget.axis,
          t: t,
          originT: _originFraction,
          accent: _asDrawn(accent),
        )
      : _FieldSliderCeilingPainter(
          levels: [
            for (final level in _laidLevels)
              (t: level.t, color: _asDrawn(level.color)),
          ],
          t: t,
          edge: _asDrawn(accent),
        );

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
  /// they were built from ([keptWhileSame]).
  ///
  /// 🔬H40 (유저 2026-09-11): 「고를때 렉있어서 그부분도 효율적으로 가볍게
  /// 하고싶어」. A bar rebuilds for every value it is handed and every frame
  /// of a drag, and the pair — two buttons, their tooltips, their ink —
  /// changes with none of that: only with the bar's height and its axis,
  /// whether it takes the gesture, and the language its tooltips speak.
  final Map<Type, Kept<Object?>> _hands = {};

  /// Whether the bar is being typed into: its pencil opened the number pad
  /// ([ValuePencil], [showNumberPad]) — or its readout did, being its
  /// pencil — and the bar wears the typed frame until the pad closes.
  bool _typing = false;

  /// The pencil: the number pad, anchored under the bar (I-134), on the
  /// number alone ([readoutParts]) — a − where the bar runs below zero, a
  /// point where it lands between whole numbers ([FieldSlider._decimals]).
  Future<void> _beginTyping() async {
    setState(() => _typing = true);
    final shown = widget._saidAtRest;
    await showNumberPad(
      context,
      keyValue: 'field-slider-type',
      initialText: switch (readoutParts(shown)) {
        [final part] => part.number,
        _ => shown,
      },
      keys: (
        minus: widget.min * widget.displayScale < 0,
        point: widget._decimals > 0,
      ),
      fieldKey: const ValueKey<String>('field-slider-type-input'),
      onSubmit: _typed,
    );
    if (mounted) {
      setState(() => _typing = false);
    }
  }

  // The readout's press reaches [_beginTyping] while this bar stands.
  @override
  void initState() {
    super.initState();
    widget.readout?._type = _beginTyping;
  }

  @override
  void didUpdateWidget(FieldSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.readout?._letGo(_beginTyping);
    widget.readout?._type = _beginTyping;
  }

  @override
  void dispose() {
    widget.readout?._letGo(_beginTyping);
    super.dispose();
  }

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
    // An active gesture echoes locally (snapped like the emitted value);
    // otherwise display derives from widget.value (fully controlled).
    final gestureT = _gestureT;
    final dragging = gestureT != null;
    final t = dragging
        ? widget._tFor(widget._valueFor(gestureT))
        : widget._tFor(widget.value);
    final valueText = dragging
        ? widget._textFor(widget._valueFor(gestureT))
        : widget._saidAtRest;

    final own = widget.color ?? AppColors.accent;
    final accent = dragging ? own : (widget.restingAccent ?? own);
    Widget bar = FieldSliderTrack(
      axis: widget.axis,
      onExtent: _takeTrackExtent,
      frame: FieldSlider.frameOf(
        widget.height,
        enabled: _enabled,
        typed: _typing,
      ),
      shape: AppShapes.container(_radius),
      fill: _trackFill(t, accent),
      child: acrossBox(
        widget.axis,
        widget.height,
        // A readout's bar writes nothing: its number is in its readout.
        child: widget.readout == null
            ? _FieldSliderWriting(
                bar: widget,
                valueText: valueText,
                runs: _inkRuns(t, accent),
              )
            : null,
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
      // T11: this press is the slider's — the claim and the recogniser in
      // one box ([OwningAxisGrip]). ↩️They were written here by hand, a
      // [DragVerbClaim] over a detector, as the splitter wore the pair.
      child: OwningAxisGrip(
        axis: widget.axis,
        configure: _configureDrag,
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
  ///
  /// A bar whose number is in its readout has no pencil: the readout is
  /// its pencil (I-135: 「연필버튼도 여기선 대체되니 없애고」).
  Widget _withHands(Widget bar) {
    if (!widget._carriesHands) {
      return bar;
    }
    // Kept while nothing they show changes (see [_hands]). Its [_stepBy]
    // reads the bar's value at press time, so a pair built under an earlier
    // value steps from the current one.
    final hands = keptWhileSame(
      _hands,
      FieldSlider,
      (widget.height, widget.axis, _enabled, widget.readout == null),
      () => Flex(
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
          if (widget.readout == null)
            ValuePencil(
              keyValue: 'field-slider-type',
              height: widget.height,
              enabled: _enabled,
              onPressed: _beginTyping,
              axis: widget.axis,
            ),
        ],
      ),
    );
    return Flex(
      direction: widget.axis,
      children: [
        Expanded(child: bar),
        hands,
      ],
    );
  }
}

/// What a bar writes in its track — its name and its number, or its number
/// alone — in the ink the ground under each stretch asks for ([runs]),
/// typed in too: the number pad opens under the bar ([showNumberPad]).
/// ↩️It gave way to a typed face, all field, while the bar was typed in.
class _FieldSliderWriting extends StatelessWidget {
  const _FieldSliderWriting({
    required this.bar,
    required this.valueText,
    required this.runs,
  });

  final FieldSlider bar;
  final String valueText;

  /// The ink over each stretch of the track ([_FieldSliderState._inkRuns]).
  final List<GroundInkRun> runs;

  @override
  Widget build(BuildContext context) {
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
    // the brush pill's, by I-125-Q1 — a glyph to a cell since F-460-Q1 —
    // and the onion skin's pegs' (F-461). ↩️The pill's own numbers stand
    // above its bars in readouts since I-135.
    //
    // ⚠️A `RotatedBox` HERE and never around the bar: the writing has no
    // gesture, while a turned recognizer would never see an on-screen
    // vertical drag at all (see [FieldSlider.axis]).
    // The ink follows the ground under it — see [runs]. The writing's box
    // is the whole track, padding and all, so the runs' fractions are the
    // painter's.
    if (bar.upright) {
      return SizedBox.expand(
        child: bar._standing(context, valueText, inks: runs),
      );
    }
    final valueStyle = FieldSlider.valueStyleIn(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final row = GroundInkWriting(
      runs: runs,
      builder: (context, ink) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: FieldSlider.inset),
        child: _rowIn(
          value: valueStyle?.merge(ink) ?? ink,
          label: labelStyle?.merge(ink) ?? ink,
        ),
      ),
    );
    return bar.axis == Axis.vertical
        ? RotatedBox(quarterTurns: 1, child: row)
        : row;
  }

  /// The row in one ink: the number in [value], the name in [label].
  Widget _rowIn({required TextStyle value, required TextStyle label}) {
    if (bar.label == null) {
      return Center(
        child: Text(
          valueText,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: value,
        ),
      );
    }
    if (!bar.nameInside) {
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
            bar.label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: label,
          ),
        ),
        Text(valueText, maxLines: 1, style: value),
      ],
    );
  }
}

/// The link between a stood bar and the readout its number stands in
/// OUTSIDE it ([FieldSlider.readout], [FieldSliderValueReadout]): the
/// readout's press reaches the bar's typing. The bar's host makes one for
/// each such bar, hands it to both, and keeps it while they stand.
///
/// 🗣️I-135 (유저 2026-10-27): 「그냥 해당하는 막대 슬라이더 위에 이 텍스트
/// 두자. 물론 다 안들어가니 최대한 텍스트쪽 위젯 컴팩트하게 하고」. ↩️The
/// number stood a day in a bubble beside its bar that followed the value
/// (「막대 옆에 <20.0 이런식으로 약간 말풍선컨셉?」), until 「생각보다 너무
/// 캔버스 좌우공간을 차지함」.
class FieldSliderReadout {
  /// The bar's typing, while the bar stands
  /// ([_FieldSliderState._beginTyping]).
  VoidCallback? _type;

  void _letGo(VoidCallback type) {
    if (_type == type) {
      _type = null;
    }
  }
}

/// A stood bar's number OUTSIDE it ([FieldSlider.readout]), where its host
/// stands it — the pill stands each right above its bar: what the bar
/// would write at rest, centred, and the bar's pencil: a press types into
/// the bar as the pencil's did.
///
/// [bar] is the bar it writes for, as its host built it from the same
/// state: the readout reads the value off it as the bar does, so the two
/// say one number. ⚠️A bar that echoes a drag before its value comes back
/// (R4 #4/#5's commit-on-release bars) would run ahead of its readout; the
/// pill's bars are handed every move, and no other bar has a readout.
///
/// Its box is FIXED — the bubble's law, kept: 「고정으로 하는게 성능적인
/// 면에서 효율적인가? 그렇다면 길이 브러시사이즈 최대 길이(2000.0 의 길이)를
/// 고정으로, 텍스트 중앙정렬로 하도록. 그냥 고정크기로하자. 그러고 불투명도도
/// 그 고정크기로 통일」 — and its letters are as large as the box lets a
/// number of their length be ([FieldSliderReadoutSizes]).
class FieldSliderValueReadout extends StatefulWidget {
  const FieldSliderValueReadout({
    super.key,
    required this.keyValue,
    required this.bar,
    required this.sizes,
  });

  /// The readout's handle: its box's key, and its press's name.
  final String keyValue;

  /// A bar with a [FieldSlider.readout].
  final FieldSlider bar;

  /// Its box and its letters — one for every readout its host shows
  /// ([FieldSliderReadoutSizes.of]).
  final FieldSliderReadoutSizes sizes;

  /// The size the WIDEST number is written at, which the box is as wide
  /// as.
  ///
  /// 🗣️I-135-Q1 (유저 2026-10-27: 「a로가자」): of 8, 9 and the other bars'
  /// 11, the size that asks the canvas for the least room — 「2000.0」 runs
  /// 33 across at 8, so the pill stands 37 across where it stood 28 (41 at
  /// 9, 50 at 11). ↩️Every number was written at it until F-493.
  static const double fontSize = 8;

  /// The room either side of the words.
  static const double _pad = 1;

  /// The room above and below the line, for the press — I-135-Q1's sheet
  /// drew two.
  static const double _rim = 2;

  /// The style it writes in: a bar's own ([FieldSlider.valueStyleIn]) at
  /// [fontSize], the line as tall as the letters.
  static TextStyle? styleIn(BuildContext context) => FieldSlider.valueStyleIn(
    context,
  )?.copyWith(fontSize: fontSize, height: 1);

  @override
  State<FieldSliderValueReadout> createState() =>
      _FieldSliderValueReadoutState();
}

/// The readouts of one host as one: one box for all of them — as wide as
/// the widest number any of them says, set at
/// [FieldSliderValueReadout.fontSize] — and in it, a number's letters as
/// large as the box lets a number of its LENGTH be.
///
/// 🗣️F-493 (유저 2026-10-28): 「4자리(99.9 등 숫자2개+점+숫자하나)를 지금의
/// 길이에서 최대치로 키우도록. 즉 0.1이나 99.9나 텍스트크기 똑같고(지금보다는
/// 큼.), 100넘어가면 작아지고, 1000넘어가면 또 작아지는 방식으로 가변으로
/// 크기조절. 불투명도도 규칙은 통일」. 「4자리」 counts the point, so the
/// size is read off how many letters a number has, four or fewer being one
/// size ([_fullest]): the opacity's 「100」, three long, stands as large as
/// the size's 「0.1」 and 「99.9」, and 「100.0」 and 「1000.0」 step down.
///
/// The box stays as I-135-Q1 took it, and its height is the largest
/// letters' — a number that crosses into another length changes its
/// letters and moves nothing.
@immutable
class FieldSliderReadoutSizes {
  const FieldSliderReadoutSizes._({
    required this.width,
    required this.height,
    required Map<int, double> fontSizes,
  }) : _fontSizes = fontSizes;

  /// The box's width — the widest number any of the readouts says, whole,
  /// and the room either side of it.
  final double width;

  /// The box's height: the largest letters' line and the room above and
  /// below it, grown as the line grows with the text scale
  /// (text-scale-fixed-height-bars).
  final double height;

  /// The letters' size for a number of each length, from [_fullest] up.
  final Map<int, double> _fontSizes;

  /// 「4자리 … 최대치로」: a number this long or shorter is written in the
  /// largest letters.
  static const int _fullest = 4;

  static final RegExp _digit = RegExp(r'\d');

  static int _lengthOf(String said) => math.max(_fullest, said.length);

  /// The size [said] is written at — the largest at which every number of
  /// its length the readouts can say stands whole in the box.
  double fontSizeFor(String said) =>
      _fontSizes[_lengthOf(said)] ?? FieldSliderValueReadout.fontSize;

  /// [bars]' readouts' sizes, measured where [context] lays text out.
  factory FieldSliderReadoutSizes.of(
    BuildContext context,
    Iterable<FieldSlider> bars,
  ) {
    final base = FieldSliderValueReadout.styleIn(context);
    final measure = TextMeasure(context, base);
    final said = [for (final bar in bars) ...bar._saidAtEnds];
    const pad = FieldSliderValueReadout._pad;
    final width = measure.widest(said).ceilToDouble() + pad * 2;
    final widestOf = <int, double>{};
    for (final form in said.expand(_shorter)) {
      final length = _lengthOf(form);
      final widest = measure.widest(
        everyDigitIn((digit) => form.replaceAll(_digit, digit)),
      );
      widestOf[length] = math.max(widestOf[length] ?? 0, widest);
    }
    final fontSizes = {
      for (final MapEntry(key: length, value: widest) in widestOf.entries)
        length: _wholeBelow(
          FieldSliderValueReadout.fontSize * (width - pad * 2) / widest,
        ),
    };
    final largest = fontSizes.values.fold(
      FieldSliderValueReadout.fontSize,
      math.max,
    );
    return FieldSliderReadoutSizes._(
      width: width,
      height:
          largest +
          FieldSliderValueReadout._rim * 2 +
          TextMeasure(
            context,
            base?.copyWith(fontSize: largest),
          ).lineGrowthOf(TextMeasure.everyScript),
      fontSizes: fontSizes,
    );
  }

  /// [word], and [word] a whole digit shorter for as long as it has one to
  /// spare — `2000.0`, `000.0`, `00.0`, `0.0`: every length the numbers
  /// under it run to.
  static Iterable<String> _shorter(String word) sync* {
    var form = word;
    while (true) {
      yield form;
      if (_digit.allMatches(form.split('.').first).length < 2) {
        return;
      }
      form = form.replaceFirst(_digit, '');
    }
  }

  /// A letter size a whole pixel at a time, never past [size]: a line set
  /// at 12.7 lays out 13 tall, so the box's height and its letters' line
  /// would part — and a size measured to fill the box exactly would stand
  /// a hair over it.
  static double _wholeBelow(double size) => size.floorToDouble();
}

class _FieldSliderValueReadoutState extends State<FieldSliderValueReadout>
    with KeyboardPress {
  bool get _enabled => widget.bar.onChanged != null;

  void _type() => widget.bar.readout?._type?.call();

  @override
  VoidCallback? get keyboardPress => _enabled ? _type : null;

  @override
  Widget build(BuildContext context) {
    final sizes = widget.sizes;
    final said = widget.bar._saidAtRest;
    // On its host's ground — the pill's, the surface ([AppColors.surface]).
    final ink = dimmedIfDisabled(
      textOnColor(AppColors.surface),
      enabled: _enabled,
    );
    final style =
        FieldSliderValueReadout.styleIn(context) ?? const TextStyle();
    return SizedBox(
      key: ValueKey<String>(widget.keyValue),
      width: sizes.width,
      height: sizes.height,
      child: keyboardReaches(
        RailPlateButton(
          name: widget.keyValue,
          tooltip: AppText.strings.valueTypeIn,
          onPressed: _enabled ? _type : null,
          focus: keyboardFocus,
          hoverShape: AppShapes.control(sizes.height),
          child: Center(
            child: Text(
              said,
              maxLines: 1,
              softWrap: false,
              style: style.copyWith(
                color: ink,
                fontSize: sizes.fontSizeFor(said),
              ),
            ),
          ),
        ),
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

/// A [FieldSlider.ceiling]'s track: its levels filled from the left, a
/// later one over an earlier one, and the value as an outline over them.
class _FieldSliderCeilingPainter extends CustomPainter with RepaintOnProps {
  const _FieldSliderCeilingPainter({
    required this.levels,
    required this.t,
    required this.edge,
  });

  /// Where each level ends along the track, 0..1, and its colour.
  final List<({double t, Color color})> levels;

  /// Where the value — the outline's far edge — sits along the track.
  final double t;

  final Color edge;

  /// The outline's stroke: the one the device bar drew the allowance in
  /// before the two bars were one (F-480).
  static const double edgeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    for (final level in levels) {
      if (level.t > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * level.t, size.height),
          Paint()..color = level.color,
        );
      }
    }
    final reach = math.max(size.width * t, edgeWidth);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, reach, size.height).deflate(edgeWidth / 2),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth,
    );
  }

  // A list compares by identity; its levels are records, so by value.
  @override
  Object get props => (ByList(levels), t, edge);
}

/// The bar's TRACK, as one box: its [frame] under everything, its [fill]
/// inside the frame's corner under the writing, and the writing — the
/// order a [DecoratedBox], a [SuperellipseClip] and a [CustomPaint] painted
/// them in, and the clip's exact corner for a pointer.
///
/// 🪶WHY (card frame-panels-build-in-one-frame, 2026-10-25): the track was
/// those three and a probe of its length — four elements and four render
/// objects for one painted bar, made again for every bar a tab reopens
/// (fourteen on each of the timeline's tabs). It IS the clip, so the
/// corner is the clip's code and not a second spelling of it.
///
/// It also hands the bar's length along its axis to the gesture math as the
/// bar is laid out — the one thing the bar needed a `LayoutBuilder` for.
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
class FieldSliderTrack extends SuperellipseClip {
  const FieldSliderTrack({
    super.key,
    required this.axis,
    required this.frame,
    required this.fill,
    required this.onExtent,
    required super.shape,
    required super.child,
  });

  final Axis axis;

  /// The bar's frame ([FieldSlider.frameOf]).
  final ShapeDecoration frame;

  /// What the track fills, inside the corner and under the writing.
  final CustomPainter fill;

  final ValueChanged<double> onExtent;

  @override
  RenderSuperellipseClip createRenderObject(BuildContext context) =>
      RenderFieldSliderTrack(
        borderRadius: borderRadiusIn(context),
        clipBehavior: clipBehavior,
        axis: axis,
        frame: frame,
        textDirection: Directionality.maybeOf(context),
        fill: fill,
        onExtent: onExtent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFieldSliderTrack renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject
      ..axis = axis
      ..frame = frame
      ..textDirection = Directionality.maybeOf(context)
      ..fill = fill
      ..onExtent = onExtent;
  }
}

/// [FieldSliderTrack]'s render object.
class RenderFieldSliderTrack extends RenderSuperellipseClip {
  RenderFieldSliderTrack({
    required super.borderRadius,
    required super.clipBehavior,
    required Axis axis,
    required ShapeDecoration frame,
    required TextDirection? textDirection,
    required CustomPainter fill,
    required this.onExtent,
  }) : _axis = axis,
       _frame = frame,
       _textDirection = textDirection,
       _fill = fill;

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

  ShapeDecoration get frame => _frame;
  ShapeDecoration _frame;
  BoxPainter? _framePainter;
  set frame(ShapeDecoration value) {
    if (_frame == value) {
      return;
    }
    _framePainter?.dispose();
    _framePainter = null;
    _frame = value;
    markNeedsPaint();
  }

  TextDirection? get textDirection => _textDirection;
  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  CustomPainter get fill => _fill;
  CustomPainter _fill;
  set fill(CustomPainter value) {
    final old = _fill;
    _fill = value;
    if (value.runtimeType != old.runtimeType || value.shouldRepaint(old)) {
      markNeedsPaint();
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    onExtent(extentAlong(_axis, constraints.biggest));
  }

  /// The fill's box takes a press anywhere inside the corner, as a
  /// [CustomPaint] whose painter does not say does.
  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _framePainter ??= _frame.createBoxPainter(markNeedsPaint);
    painter.paint(
      context.canvas,
      offset,
      ImageConfiguration(size: size, textDirection: _textDirection),
    );
    super.paint(context, offset);
  }

  @override
  void paintInside(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    if (offset != Offset.zero) {
      canvas.translate(offset.dx, offset.dy);
    }
    _fill.paint(canvas, size);
    canvas.restore();
    super.paintInside(context, offset);
  }

  @override
  void detach() {
    _framePainter?.dispose();
    _framePainter = null;
    super.detach();
    markNeedsPaint();
  }

  @override
  void dispose() {
    _framePainter?.dispose();
    super.dispose();
  }
}
