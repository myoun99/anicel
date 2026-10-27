import 'package:flutter/material.dart';

import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../text/readout_text.dart' show columnValueOf, readoutText;
import '../text/text_measure.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/drag_value_label.dart';
import 'timeline_zoom_limits.dart';

import '../../models/project_frame_rate.dart';

/// What a [TimelineViewCluster] shows — the key both frame panels keep
/// theirs by across their host's rebuilds (F-244 ⑧, `keptWhileSame`): its
/// zoom, and [trailing] — what the host's own controls beside it show.
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
  Object? trailing,
});

/// The view cluster shared VERBATIM by the timeline and storyboard tabs:
/// the zoom and its fit, plus host-specific trailing controls (the
/// timeline's orientation toggle).
///
/// The seconds TOGGLE left this bar in the rail-window round — it lives
/// in each grid's top-left corner now, over the layer-axis scrollbar,
/// beside the axis whose labels it rewrites.
///
/// 🗣️F-463 ④ (유저 2026-10-25): 「기존 줌 왼쪽의 로컬인덱스/글로벌인덱스
/// 텍스트 표시, 필요없으니 일단 삭제. 컷 번호 보여주는거만 컷 알약안에」.
/// ↩️The frame counter stood at the cluster's head from 2026-08-10 — the
/// track-global frame over the cut-local one, both panels — and I-57 (유저
/// 2026-10-01) put the cut's name between it and the zoom; the name is the
/// cut pill's now (`CutCommandGroup`). The counter was the one thing on the
/// bar that ticked with playback, which is what stood the zoom on a layer
/// and a semantics boundary of its own (10-11 · 10-12) — gone with it.
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
    this.onZoomFit,
    this.trailing = const <Widget>[],
  });

  final ProjectFrameRate projectFrameRate;
  final double pixelsPerFrame;
  final ValueChanged<double>? onPixelsPerFrameChanged;

  /// The zoom fit (I-111): the host's, which knows the end line its panel
  /// draws and the window it shows it in. Null keeps the button dark.
  final VoidCallback? onZoomFit;

  /// Host-specific controls after the zoom (orientation toggle).
  final List<Widget> trailing;

  /// The zoom readout's words — the canvas zoom readout's.
  static const TextStyle _zoomStyle = TextStyle(fontSize: 12);

  /// The digits the zoom readout writes after the point — every digit the
  /// zoom has (F-403: a step is 0.1%).
  static const int _zoomDecimals = 1;

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

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _zoomReadout(context),
      // 🗣️F-463: 「그 옆의 줌 fit버튼은 그대로」 — I-111's 「위치는 줌
      // 확대버튼 오른쪽」, the + gone from beside it.
      _zoomFitButton(),
      ...trailing,
    ],
  );

  /// The zoom as a number to drag — 🗣️F-463 (유저 2026-10-25): 「축소,확대
  /// 버튼 없애고, 슬라이더는 캔버스패널의 줌 위젯마냥 숫자로 이루어진 위젯에
  /// 드래그로 조절. 공용화된거 그대로 사용. 이유는 이렇게 하면 더 공간
  /// 간략화 가능하니」 — the canvas zoom's readout ([DragValueLabel]): a
  /// percent a pixel of drag, a step a notch of the wheel, its pencil to
  /// type one, each landed on the zoom's steps inside its range
  /// ([TimelineZoomLimits.clamped]). The keys still press the zoom in and
  /// out (`EditorActionIds.timelineZoomIn`).
  ///
  /// ↩️A 140px `FieldSlider` stood here between a − and a + (UI-R11 #11),
  /// on a MULTIPLICATIVE track (I-22 ②-1: a linear one spent 97% of its
  /// length on 24→96px). A drag has no length to spend.
  Widget _zoomReadout(BuildContext context) {
    final style = _zoomStyleIn(context);
    final onChanged = onPixelsPerFrameChanged;
    // ⚠️The zoom this readout last sent, not the one it was built with: two
    // moves of the hand can land before the host builds it again, and the
    // second, counted from the zoom built, would undo the first.
    var sent = pixelsPerFrame;
    void zoomTo(double percent) {
      final zoom = TimelineZoomLimits.clamped(
        percent * TimelineZoomLimits.referencePixelsPerFrame / 100,
        framesPerSecond: projectFrameRate.countingBase,
      );
      if (zoom != sent) {
        sent = zoom;
        onChanged!(zoom);
      }
    }

    double percentOf(double zoom) =>
        zoom * 100 / TimelineZoomLimits.referencePixelsPerFrame;

    return DragValueLabel(
      keyValue: 'timeline-zoom-readout',
      text: readoutText(
        percentOf(pixelsPerFrame),
        decimals: _zoomDecimals,
        unit: '%',
      ),
      tooltip: AppText.strings.viewZoomDrag,
      // As wide as the widest zoom it writes, so no digit moves the row.
      width: TextMeasure(context, style)
          .widest(everyDigitIn((d) => '$d$d$d.$d%'))
          .ceilToDouble(),
      enabled: onChanged != null,
      textStyle: _zoomStyle,
      onDragDelta: (units) => zoomTo(percentOf(sent) + units),
      onEditSubmit: (text) {
        final parsed = columnValueOf(text);
        if (parsed != null) {
          zoomTo(parsed);
        }
      },
    );
  }
}
