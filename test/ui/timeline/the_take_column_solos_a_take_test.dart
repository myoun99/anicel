import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_legend_callbacks.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/timeline/timeline_legend_menus.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️take-legend-button (유저 2026-11-04, F-553: 「색 라벨로만 보고
/// 인식하도록. 테이크 다른거는 신경쓰지않음. 그거는 테이크 레전드버튼
/// 만들어서 별도구현」).
///
/// The legend's take column, over the rows' take chips: its flyout lists
/// the takes the rows are on — and every take the filter holds — to solo,
/// under 「테이크 솔로 지우기」. A take solo is one more facet of the row
/// filter, AND with the others.
void main() {
  const layout = LayerMark(process: LayerProcess.layout);

  group('the facet', () {
    bool shows(TimelineRowFilter filter, LayerMark mark) =>
        filter.allowsFacets(mark: mark, fxEnabled: false);

    test('a take solo passes the rows on its takes, whatever their colour', () {
      const filter = TimelineRowFilter(takes: {2});
      expect(
        [
          shows(filter, LayerMark.none.withTake(2)),
          shows(filter, layout.withTake(2)),
          shows(filter, LayerMark.none),
          shows(filter, layout),
        ],
        [true, true, false, false],
      );
      expect(filter.isActive, isTrue);
    });

    test('it is AND with the colour solo', () {
      final filter = TimelineRowFilter(markColors: {layout}, takes: {2});
      expect(
        [
          shows(filter, layout.withTake(2)),
          shows(filter, layout),
          shows(filter, LayerMark.none.withTake(2)),
        ],
        [true, false, false],
      );
    });

    test('a row with no mark is not judged by it, and the row stood on '
        'stays', () {
      const filter = TimelineRowFilter(takes: {2});
      expect(filter.allowsFacets(fxEnabled: false), isTrue);
      expect(
        filter.allowsRow(
          standing: true,
          mark: LayerMark.none,
          fxEnabled: false,
        ),
        isTrue,
      );
    });

    test('toggling a take holds it and lets it go; two filters that hold '
        'different takes differ', () {
      final held = TimelineRowFilter.none.toggledTake(3);
      expect(held.takes, {3});
      expect(held.toggledTake(3).takes, isEmpty);
      expect(held == TimelineRowFilter.none.toggledTake(4), isFalse);
      expect(held, TimelineRowFilter.none.toggledTake(3));
      expect(held.hashCode, TimelineRowFilter.none.toggledTake(3).hashCode);
    });
  });

  group('the session\'s verbs', () {
    test('a take row toggles that take, and the reset lets every take go '
        'and keeps the other facets', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final heard = <TimelineRowFilter>[];
      final before = TimelineRowFilter(markColors: {layout}, takes: {1});

      final legend = sessionLegendCallbacks(
        session,
        rowFilter: before,
        onSetRowFilter: heard.add,
      );
      legend.onToggleTakeFilter(2);
      legend.onClearTakeFilter();

      expect(heard.map((filter) => filter.takes), [
        {1, 2},
        <int>{},
      ]);
      expect(heard.last.markColors, {layout});
    });
  });

  group('the column', () {
    TimelineLegendMenus menus(
      TimelineRowFilter filter,
      Set<LayerMark> worn,
      List<Object> heard,
    ) => TimelineLegendMenus(
      legend: _legend(heard),
      rowFilter: filter,
      marksInUse: () => worn,
    );

    List<String> keysOf(List<PanelFlyoutEntry> entries) => [
      for (final entry in entries)
        switch (entry) {
          PanelFlyoutItem(:final keyValue) => keyValue,
          PanelFlyoutHeader() => 'header',
          _ => 'divider',
        },
    ];

    test('its reset over the takes the rows are on — an unlabelled row\'s '
        'T1 among them — in order', () {
      final entries = menus(TimelineRowFilter.none, {
        layout.withTake(3),
        LayerMark.none,
      }, []).take!();

      expect(keysOf(entries), [
        'legend-take-filter-clear',
        'divider',
        'header',
        'legend-filter-take-1',
        'legend-filter-take-3',
      ]);
    });

    test('a take the filter holds is listed and checked though no row is '
        'on it, and pressing it asks for it', () {
      final heard = <Object>[];
      final entries = menus(
        const TimelineRowFilter(takes: {5}),
        {LayerMark.none},
        heard,
      ).take!();
      final five = entries.whereType<PanelFlyoutItem>().singleWhere(
        (item) => item.keyValue == 'legend-filter-take-5',
      );

      expect(five.checked, isTrue);
      expect(five.shortcuts, [railSoloTakeActionId(5)]);
      five.onSelected!();
      expect(heard, [5]);
    });

    test('the reset is lit while a take is held, and asks for the reset', () {
      final heard = <Object>[];
      PanelFlyoutItem resetOf(TimelineRowFilter filter) =>
          menus(filter, {LayerMark.none}, heard).take!().first
              as PanelFlyoutItem;

      expect(resetOf(TimelineRowFilter.none).enabled, isFalse);
      final held = resetOf(const TimelineRowFilter(takes: {2}));
      expect(held.enabled, isTrue);
      expect(held.shortcuts, [RailLegendActionIds.takeFilterClear]);
      held.onSelected!();
      expect(heard, ['clear takes']);
    });

    test('its rows are among the legend\'s rows a key presses', () {
      final rows = menus(TimelineRowFilter.none, {LayerMark.none}, []).rows();
      expect(
        rows.map((row) => row.keyValue),
        containsAll(['legend-take-filter-clear', 'legend-filter-take-1']),
      );
    });
  });

  testWidgets('🎯on the timeline: soloing T2 from the take column leaves the '
      'rows on T2, whatever their colour, and pressing it again brings the '
      'rest back', (tester) async {
    final session = await pumpTimelineHost(tester, _project());
    session.selectLayer(const LayerId('t1-plain'));
    await tester.pumpAndSettle();
    expect(_row('t3-layout'), findsOneWidget, reason: '⛔전제');
    await tester.tap(find.byKey(const ValueKey<String>('legend-take')));
    await tester.pumpAndSettle();
    expect(_listedTakes(), [1, 2, 3], reason: 'T1 is worn only unlabelled');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _pick(tester, 'legend-filter-take-2');

    expect(
      [for (final id in _ids) _row(id).evaluate().length],
      [0, 1, 1, 0],
    );
    expect(
      session.activeLayerId?.value,
      isIn(['t2-plain', 't2-layout']),
      reason: 'you stand only on a shown row',
    );

    await _pick(tester, 'legend-filter-take-2');
    expect(
      [for (final id in _ids) _row(id).evaluate().length],
      [1, 1, 1, 1],
    );
  });

  testWidgets('the conte panel\'s legend lists the takes its rows are on — '
      'an unlabelled row\'s T1 too', (tester) async {
    await pumpStoryboardHost(tester, _project());

    await tester.tap(find.byKey(const ValueKey<String>('legend-take')).first);
    await tester.pumpAndSettle();

    expect(_listedTakes(), [1, 2, 3]);
  });
}

Future<void> _pick(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const ValueKey<String>('legend-take')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.named('timeline-layer-row-$id');

/// The takes the open take flyout lists.
List<int> _listedTakes() => [
  for (final take in LayerMark.takeChoices)
    if (find
        .byKey(ValueKey<String>('legend-filter-take-$take'))
        .evaluate()
        .isNotEmpty)
      take,
];

/// [_project]'s rows, bottom → top.
const _ids = ['t1-plain', 't2-plain', 't2-layout', 't3-layout'];

/// A legend whose take verbs write what they were asked into [heard].
LayerLegendCallbacks _legend(List<Object> heard) => LayerLegendCallbacks(
  onShowAllLayers: () {},
  onHideAllLayers: () {},
  onToggleVisibilitySolo: () {},
  onSheetAllOn: () {},
  onSheetAllOff: () {},
  onClearMarkFilter: () {},
  onClearTakeFilter: () => heard.add('clear takes'),
  onClearAllClips: () {},
  onBypassAllFx: () {},
  onEnableAllFx: () {},
  onToggleMarkFilter: (_) {},
  onToggleTakeFilter: heard.add,
  onToggleKindFilter: (_) {},
  onToggleSheetOnlyFilter: () {},
  onToggleFxOnlyFilter: () {},
  onToggleClippedOnlyFilter: () {},
  onPreviewLayersOpacity: (_, _) {},
  onCommitLayersOpacity: (_, _) {},
);

Layer _layer(String id, LayerMark mark) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.animation,
  mark: mark,
  frames: const [],
  timeline: const {},
);

/// Four rows, the colour label and the take crossed — T1 worn only by a
/// row with no label.
Project _project() {
  const layout = LayerMark(process: LayerProcess.layout);
  return Project(
    id: const ProjectId('take-solo'),
    name: 'Take solo',
    createdAt: DateTime.utc(2026, 11, 4),
    tracks: [
      Track(
        id: const TrackId('take-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('take-cut'),
            name: 'Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              _layer('t1-plain', LayerMark.none),
              _layer('t2-plain', LayerMark.none.withTake(2)),
              _layer('t2-layout', layout.withTake(2)),
              _layer('t3-layout', layout.withTake(3)),
            ],
          ),
        ],
      ),
    ],
  );
}
