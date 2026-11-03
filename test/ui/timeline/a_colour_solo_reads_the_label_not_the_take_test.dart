import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/timeline/timeline_legend_menus.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../shortcuts/the_rail_legend_rows_are_actions_test.dart'
    show everyVerb;

/// 🗣️F-553 (유저 2026-11-04): 「타임라인 레전드행의 색 라벨버튼의 색 솔로,
/// 테이크가 다르면 행 나뉘는데 그냥 딱 색 라벨로만 보고 인식하도록. 테이크
/// 다른거는 신경쓰지않음」 — a colour solo is one per colour label, and it
/// shows a row of that label on any take.
void main() {
  const layout = LayerMark(process: LayerProcess.layout);
  final layoutTake3 = layout.withTake(3);
  const conte = LayerMark(process: LayerProcess.conte);

  Layer row(String id, LayerMark mark) => Layer(
    id: LayerId(id),
    name: id,
    mark: mark,
    frames: const [],
    timeline: const {},
  );

  bool shows(TimelineRowFilter filter, LayerMark mark) =>
      filter.allowsLayerRow(row('r', mark), standing: false, fxEnabled: true);

  test('a solo of a label shows its rows on every take, and no other', () {
    final filter = TimelineRowFilter.none.toggledMark(layout);
    expect(shows(filter, layout), isTrue);
    expect(shows(filter, layoutTake3), isTrue);
    expect(shows(filter, conte), isFalse);
  });

  test('a solo pressed from a row on another take is its label\'s — the '
      'same press lets it go', () {
    final held = TimelineRowFilter.none.toggledMark(layoutTake3);
    expect(held.markColors, {layout});
    expect(held.toggledMark(layout).markColors, isEmpty);
  });

  test('the legend lists one solo a label, whatever takes its rows are on', () {
    final menus = TimelineLegendMenus(
      legend: everyVerb(),
      marksInUse: () => {layout, layoutTake3, conte},
    );
    final solos = [
      for (final entry in menus.mark!())
        if (entry case PanelFlyoutItem(:final keyValue)
            when keyValue.startsWith('legend-filter-mark-'))
          keyValue,
    ];
    expect(solos.toSet(), {
      'legend-filter-mark-${conte.keySlug}',
      'legend-filter-mark-${layout.keySlug}',
    });
    expect(solos, hasLength(2), reason: 'not three: no take apart');
  });
}
