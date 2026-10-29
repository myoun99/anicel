import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../text/readout_text.dart' show readoutText;
import '../text/text_measure.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/app_icon_button.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/kept_tail_row.dart' show FoldFloor;
import '../widgets/tick_layer.dart';
import 'timeline_zoom_limits.dart';

import '../../models/project_frame_rate.dart';

/// What a [TimelineViewCluster] shows — the key both frame panels keep
/// theirs by across their host's rebuilds (F-244 ⑧, `keptWhileSame`): its
/// zoom, the cut's name it hears, and [trailing] — what the host's own
/// controls beside it show.
///
/// 🔬Measured (10-01, a comma drag released on 24 rows): the timeline's
/// cluster was built anew at every commit — 47 elements, every one of them
/// the same — because the panel made it afresh in its build.
///
/// The zoom's callback is a fact, by equality, as the cells rows' content
/// callbacks are: whether there is one is whether the readout turns, and a
/// host's tear-off compares equal across its rebuilds.
typedef TimelineViewClusterFacts = ({
  ProjectFrameRate projectFrameRate,
  double pixelsPerFrame,
  ValueChanged<double>? onPixelsPerFrameChanged,
  VoidCallback? onZoomFit,
  ValueListenable<String> cutName,
  Object? trailing,
});

/// The view cluster shared VERBATIM by the timeline and storyboard tabs —
/// the bar's right group: the cut's name, the zoom and its fit, plus
/// host-specific trailing controls (the timeline's orientation toggle).
///
/// 🗣️F-491 (유저 2026-10-27 23:15): 「오른쪽묶음엔 컷이름/줌/fit 이순서로
/// 남도록」.
///
/// The seconds TOGGLE left this bar in the rail-window round — it lives
/// in each grid's top-left corner now, over the layer-axis scrollbar,
/// beside the axis whose labels it rewrites.
///
/// 🗣️F-463 ④ (유저 2026-10-25): 「기존 줌 왼쪽의 로컬인덱스/글로벌인덱스
/// 텍스트 표시, 필요없으니 일단 삭제. 컷 번호 보여주는거만 컷 알약안에」.
/// ↩️The frame counter stood at the cluster's head from 2026-08-10 — the
/// track-global frame over the cut-local one, both panels — and I-57 (유저
/// 2026-10-01) put the cut's name between it and the zoom; the name was the
/// cut pill's from F-463 ④ (`CutCommandGroup`), and is the cluster's head
/// again since F-491 ([_CutName]). The counter was the one thing on the bar
/// that ticked with playback, which is what stood the zoom on a layer and
/// a semantics boundary of its own (10-11 · 10-12) — gone with it.
///
/// One widget instead of two hand-copied Rows — the key strings
/// ('timeline-zoom-readout', 'timeline-zoom-fit-button') stay unique on
/// screen because only one tab is ever mounted.
class TimelineViewCluster extends StatelessWidget {
  const TimelineViewCluster({
    super.key,
    required this.projectFrameRate,
    required this.pixelsPerFrame,
    required this.onPixelsPerFrameChanged,
    required this.cutName,
    this.onZoomFit,
    this.trailing = const <Widget>[],
  });

  final ProjectFrameRate projectFrameRate;
  final double pixelsPerFrame;
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// The name of the cut the panel's playhead stands in
  /// (`CutUnderPlayhead.cutName`).
  final ValueListenable<String> cutName;

  /// The zoom fit (I-111): the host's, which knows the end line its panel
  /// draws and the window it shows it in. Null keeps the button dark.
  final VoidCallback? onZoomFit;

  /// Host-specific controls after the zoom (orientation toggle).
  final List<Widget> trailing;

  /// The zoom readout's words — the canvas zoom readout's.
  static const TextStyle _zoomStyle = TextStyle(fontSize: 12);

  /// The digits the zoom readout writes after the point — none: a step is
  /// a whole percent (F-491). ↩️One from F-403 to F-491, when a step was
  /// 0.1%.
  static const int _zoomDecimals = 0;

  /// What the cluster adds to the height it was drawn at where it is shown:
  /// the zoom readout's one line grown under the OS text size.
  ///
  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
  /// 따라 자란다」).
  static double growthIn(BuildContext context) =>
      TextMeasure(context, _zoomStyleIn(context))
          .lineGrowthOf(TextMeasure.everyScript);

  static TextStyle _zoomStyleIn(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(_zoomStyle);

  /// 🗣️I-111 (유저 2026-10-19): 「타임라인/콘티패널등 줌 fit 버튼 추가.
  /// 해당 패널의 엔드라인에 맞춰서 스크롤바 fit하는것」 — the zoom at which
  /// the panel's end line stands in its window, the host's to work out.
  Widget _zoomFitButton() => AppIconButton(
    keyValue: 'timeline-zoom-fit-button',
    tooltip: editorActionLabel(EditorActionIds.timelineZoomFit),
    shortcuts: const [EditorActionIds.timelineZoomFit],
    icon: const Icon(Icons.fit_screen),
    onPressed: onZoomFit,
  );


  // ↩️Its last button was the least of it its bar showed, under F-463-Q1's
  // 「묶음 안에서 재생 · 줌이 따로」 (15:23) — until the answer became one
  // right group, kept by the transport's first button (20:2x: 「줌쪽부터
  // 가려지도록」), and the transport left for the left group (F-491).
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CutName(name: cutName),
      _zoomReadout(context),
      // 🗣️F-491 (23:15): 「오른쪽이 마지막에 남도록. 즉 지금으로 치면
      // fit버튼」 — the least of the group its bar shows, from the fit to
      // the group's end ([FoldFloor]).
      FoldFloor(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🗣️F-463: 「그 옆의 줌 fit버튼은 그대로」 — I-111's 「위치는 줌
            // 확대버튼 오른쪽」, the + gone from beside it.
            _zoomFitButton(),
            ...trailing,
          ],
        ),
      ),
    ],
  );

  /// The zoom as a number to drag — 🗣️F-463 (유저 2026-10-25): 「축소,확대
  /// 버튼 없애고, 슬라이더는 캔버스패널의 줌 위젯마냥 숫자로 이루어진 위젯에
  /// 드래그로 조절. 공용화된거 그대로 사용. 이유는 이렇게 하면 더 공간
  /// 간략화 가능하니」 — the canvas zoom's readout ([DragValueLabel]): a
  /// percent a pixel of drag, a step a notch of the wheel, each landed on
  /// the zoom's steps inside its range ([TimelineZoomLimits.clamped]). The
  /// keys still press the zoom in and out (`EditorActionIds.timelineZoomIn`).
  ///
  /// 🗣️F-463 (유저 2026-10-27): 「타임라인 줌 버튼에 연필버튼 삭제.
  /// 텍스트줌이랑 fit버튼으로 줌관련은 충분」 — no number is typed here.
  /// ↩️Its pencil typed one, as the canvas zoom's still does.
  ///
  /// ↩️A 140px `FieldSlider` stood here between a − and a + (UI-R11 #11),
  /// on a MULTIPLICATIVE track (I-22 ②-1: a linear one spent 97% of its
  /// length on 24→96px). A drag has no length to spend.
  Widget _zoomReadout(BuildContext context) {
    final style = _zoomStyleIn(context);
    final onChanged = onPixelsPerFrameChanged;
    // ↩️It counted from the zoom it last sent, not the one it was built
    // with: two moves of the hand landed before the host built it again.
    // The readout hands them on once a frame now ([DragValueLabel
    // .onDragDelta]), each to a host built with the last.
    void zoomTo(double percent) {
      final zoom = TimelineZoomLimits.clamped(
        TimelineZoomLimits.atPercent(percent),
        framesPerSecond: projectFrameRate.countingBase,
      );
      if (zoom != pixelsPerFrame) {
        onChanged!(zoom);
      }
    }

    return DragValueLabel(
      keyValue: 'timeline-zoom-readout',
      text: readoutText(
        TimelineZoomLimits.percentOf(pixelsPerFrame),
        decimals: _zoomDecimals,
        unit: '%',
      ),
      tooltip: AppText.strings.viewZoomDrag,
      // As wide as the widest zoom it writes, so no digit moves the row.
      width: TextMeasure(context, style)
          .widest(everyDigitIn((d) => '$d$d$d%'))
          .ceilToDouble(),
      enabled: onChanged != null,
      textStyle: _zoomStyle,
      onDragDelta: (units) =>
          zoomTo(TimelineZoomLimits.percentOf(pixelsPerFrame) + units),
    );
  }
}

/// The name of the cut the panel's playhead stands in, at the head of the
/// bar's right group — 🗣️F-491 (유저 2026-10-27): 「컷 이름 표시 역시 이게
/// 아닌듯. 컷 버튼 옆에 있는데 너무 쓸데없이 공간차지함 … 위치는 전처럼
/// 오른쪽묶음의 제일 왼쪽에 위치. 정렬은 해당 위치에서 오른쪽정렬. 그리고
/// 컷 이름 앞에 c 붙이도록. 즉 컷이름 500이면 c500 되도록」. ↩️It stood in
/// the cut pill right of its 「컷」 from F-463 ④ (유저 2026-10-25), and here
/// between the frame counter and the zoom's − before that (I-57, 유저
/// 2026-10-01), up to 160px wide.
///
/// 🗣️F-463 ④: 「글자는 숫자+영어기준 5글자까지만 정상적으로 표시하도록. 그
/// 이상은 생략. 호버하면 풀네임 뜨도록 툴팁표시」. Its place is always laid,
/// as wide as the `c`, five of the widest digit or Latin letter and the `…`
/// after them, and the name is what changes, at the place's right — a gap's
/// empty name keeps it. A name past five characters keeps its first five;
/// one in a wider script ends where the place does.
class _CutName extends StatelessWidget {
  const _CutName({required this.name});

  final ValueListenable<String> name;

  /// How many characters stand whole — 「숫자+영어기준 5글자」.
  static const int _wholeCharacters = 5;

  static const String _digitsAndLatin =
      '${decimalDigits}ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// The pills' name cells' words (`PillNameCell`), the name's weight.
  static TextStyle get _style => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  /// Between the name and the zoom after it.
  static const double _breath = 2;

  /// What a cut's name is written after — 「c500」.
  static const String _cut = 'c';

  static const String _ellipsis = '…';

  /// [name] as the place writes it, and its tooltip says it whole.
  static String _written(String name) => name.isEmpty ? '' : '$_cut$name';

  static String _shown(String name) => _written(
    name.characters.length > _wholeCharacters
        ? '${name.characters.take(_wholeCharacters)}$_ellipsis'
        : name,
  );

  /// A line of each script a name is written in, for the place's height.
  static const List<String> _scripts = ['0', 'あ', '가'];

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_style);
    final measure = TextMeasure(context, style);
    final width = measure
        .widest(
          everyDigitIn(
            (character) =>
                '$_cut${character * _wholeCharacters}$_ellipsis',
            digits: _digitsAndLatin,
          ),
        )
        .ceilToDouble();
    final height = _scripts
        .map((line) => measure.size(line).height)
        .reduce(math.max)
        .ceilToDouble();
    return Padding(
      padding: const EdgeInsets.only(right: _breath),
      child: SizedBox(
        width: width,
        height: height,
        // 🚨ON A TICK LAYER (I-22 ③): a scrub crosses into another cut on a
        // move, and the name turns over with it — drawn live, in a place of
        // its own size, it repaints the bar's strip at no crossing
        // (`a_scrub_repaints_only_its_tick_layers_test`).
        child: TickLayer(
          child: ValueListenableBuilder<String>(
            valueListenable: name,
            builder: (context, name, _) => AppTooltip(
              message: _written(name),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _shown(name),
                  key: const ValueKey<String>('timeline-cut-name'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
