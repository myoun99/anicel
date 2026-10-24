import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/canvas/view_hand.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/rail_legends.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_legend_menus.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// 🚨I-57 ㉢-2 (10-13, measured on the user's project): the rail's legend
/// header was kept by every fact it shows — and by the set of layers on
/// display, which it shows nowhere: its bulk verbs ACT on that set (the
/// master opacity bar, the blend flyout). Every cut switch changed the set,
/// so the whole header was built again at every crossing a scrub or a play
/// made: 223 widgets of a crossing's 855. The set is read at the press.
///
/// 🚨And by the marks and kinds on the rows (10-14), which only its mark
/// and kind flyouts list: a cut of other marks or kinds — most of them —
/// built it again whole, 221 widgets of a crossing's 821. They are read
/// when a flyout opens.
///
/// 🗣️F-408 ② (유저 2026-10-19): 「다른 레전드 행도 점검하면서 법 통일」 — the
/// x-sheet's corner is the same legend, kept the same way.
void main() {
  for (final orientation in TimelineOrientation.values) {
    testWidgets('$orientation: a cut switch builds nothing of the legend '
        'header again', (tester) async {
      await _show(tester, _panel('one', [], orientation: orientation));
      expect(
        find.byType(TimelineLayerControlsHeader),
        findsOneWidget,
        reason: 'LIVENESS: the legend stands',
      );

      final built = await _legendBuildsWhile(
        () => _show(tester, _panel('two', [], orientation: orientation)),
        around: _gridOf(orientation),
      );

      expect(
        built.grids,
        greaterThan(0),
        reason: 'LIVENESS: the grid was built',
      );
      expect(built.inLegend, isEmpty);
    });

    testWidgets('$orientation: the master opacity bar acts on the layers on '
        'display NOW', (tester) async {
      final committed = <Set<LayerId>>[];
      final values = <double>[];
      for (final cut in const ['one', 'two']) {
        await _show(
          tester,
          _panel(cut, committed, orientation: orientation, values: values),
        );
      }

      await tester.drag(
        find.byKey(const ValueKey<String>('legend-opacity')),
        // Toward empty: the rail's runs along the row; the sheet's, turned
        // with its header, up the column — two ways, not one turned.
        const {
          TimelineOrientation.horizontal: Offset(-40, 0),
          TimelineOrientation.vertical: Offset(0, 40),
        }[orientation]!,
      );
      await tester.pumpAndSettle();

      expect(committed, isNotEmpty, reason: 'LIVENESS: the bar committed');
      expect(committed.last, {
        const LayerId('two-1'),
        const LayerId('two-2'),
        const LayerId('two-3'),
      });
      expect(
        values.last,
        lessThan(values.first),
        reason: 'the bar runs along the rail, as the drag did (F-408 ②)',
      );
    });
  }

  testWidgets('the menus the header tells go with the panel — not with a '
      'turn, which builds the other grid\'s header before the grid it '
      'replaces goes', (tester) async {
    final hand = ViewHand<RailLegendHold>();
    await _show(tester, _panel('one', [], legendHand: hand));
    expect(hand.now?.menus, isNotNull, reason: '⛔premise: the rail told them');

    await _show(
      tester,
      _panel(
        'one',
        [],
        orientation: TimelineOrientation.vertical,
        legendHand: hand,
      ),
    );
    expect(find.byType(XSheetTimelineGrid), findsOneWidget);
    expect(hand.now?.menus, isNotNull, reason: 'the corner\'s, last');

    await tester.pumpWidget(const SizedBox());
    expect(hand.now, isNull, reason: 'the panel went, and they with it');
  });

  testWidgets('a panel built anew comes up before the one it replaces goes, '
      'and its legend stays held up (rail-legend-menus-lost-to-an-old-'
      'goodbye)', (tester) async {
    final hand = ViewHand<RailLegendHold>();
    await _show(
      tester,
      _panel('one', [], legendHand: hand, key: const ValueKey('old')),
    );
    final old = hand.now;
    expect(old?.menus, isNotNull, reason: '⛔premise: the rail told them');

    await _show(
      tester,
      _panel('one', [], legendHand: hand, key: const ValueKey('new')),
    );
    expect(hand.now, isNot(same(old)), reason: '⛔premise: built anew');
    expect(hand.now?.menus, isNotNull);
  });

  testWidgets('nor a switch to a cut of other marks and kinds, whose flyouts '
      'list the rows on display when they open', (tester) async {
    await _show(tester, _panel('one', []));

    final built = await _legendBuildsWhile(
      () => _show(tester, _panel('two', [], marked: true)),
    );

    expect(built.grids, greaterThan(0), reason: 'LIVENESS: the grid was built');
    expect(built.inLegend, isEmpty);
    for (final (column, row) in [
      ('legend-mark', 'legend-filter-mark-${_layout.keySlug}'),
      ('legend-kind', 'legend-filter-kind-${LayerKind.instruction.name}'),
    ]) {
      await tester.tap(find.byKey(ValueKey<String>(column)));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey<String>(row)), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('and a switch from a cut with no rows opens its kind column on '
      'the rows that came', (tester) async {
    await _show(tester, _panel('none', [], rows: 0));
    await _show(tester, _panel('two', []));

    await tester.tap(find.byKey(const ValueKey<String>('legend-kind')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey<String>('legend-filter-kind-${LayerKind.animation.name}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a kept header follows the words\' scale: its cells stand '
      'where a header built at that scale stands them', (tester) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _show(tester, _panel('one', []));
    final atOne = _legendCells(tester);

    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    await tester.pumpAndSettle();
    final followed = _legendCells(tester);
    await tester.pumpWidget(const SizedBox());
    await _show(tester, _panel('one', []));

    expect(followed, isNot(atOne), reason: 'premise: the scale moves them');
    expect(followed, _legendCells(tester));
  });

  testWidgets('the storyboard\'s legend is kept through a switch as well', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final cuts = session.repository.requireProject().tracks.first.cuts;

    final built = await _legendBuildsWhile(() async {
      session.selectCut(cuts.first.id);
      await tester.pumpAndSettle();
    }, around: StoryboardPanel);

    expect(built.grids, greaterThan(0), reason: 'LIVENESS: the board built');
    expect(built.inLegend, isEmpty);
  });

  testWidgets('the storyboard holds its legend up, and puts it down as it '
      'goes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final legends = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .railLegends;
    expect(legends.rowsOf(WorkingPanel.storyboard), isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    expect(legends.handOf(WorkingPanel.storyboard).now, isNull);
  });

}

/// The grid [orientation] stands up.
Type _gridOf(TimelineOrientation orientation) => switch (orientation) {
  TimelineOrientation.horizontal => LayerTimelineGrid,
  TimelineOrientation.vertical => XSheetTimelineGrid,
};

const _layout = LayerMark(process: LayerProcess.layout);

/// The widgets built under the legend header while [act] runs — the
/// header's own build, which only compares what it shows, aside — and how
/// many times the panel [around] it was.
Future<({List<Type> inLegend, int grids})> _legendBuildsWhile(
  Future<void> Function() act, {
  Type around = LayerTimelineGrid,
}) async {
  final inLegend = <Type>[];
  var grids = 0;
  debugOnRebuildDirtyWidget = (element, _) {
    if (element.widget.runtimeType == around) {
      grids += 1;
    }
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is! TimelineLayerControlsHeader) {
        return true;
      }
      inLegend.add(element.widget.runtimeType);
      return false;
    });
  };
  try {
    await act();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return (inLegend: inLegend, grids: grids);
}

/// Where the legend's cells stand.
List<Rect> _legendCells(WidgetTester tester) => [
  for (final cell in const ['legend-eye', 'legend-mark', 'legend-kind'])
    tester.getRect(find.byKey(ValueKey<String>(cell))),
];

Future<void> _show(WidgetTester tester, Widget panel) async {
  await tester.binding.setSurfaceSize(const Size(1400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(panel);
  await tester.pumpAndSettle();
}

/// A cut of [rows] drawings — the same faces in every cut, other layers;
/// [marked], the first one an instruction labelled for layout.
List<Layer> _layersOf(String cut, {required bool marked, int rows = 3}) => [
  for (final (index, name) in const ['One', 'Two', 'Three'].take(rows).indexed)
    Layer(
      id: LayerId('$cut-${index + 1}'),
      name: name,
      frames: const [],
      kind: marked && index == 0 ? LayerKind.instruction : LayerKind.animation,
      mark: marked && index == 0 ? _layout : LayerMark.none,
    ),
];

final _cursor = ValueNotifier<int>(0);

Widget _panel(
  String cut,
  List<Set<LayerId>> committed, {
  bool marked = false,
  int rows = 3,
  TimelineOrientation orientation = TimelineOrientation.horizontal,
  ViewHand<RailLegendHold>? legendHand,
  Key? key,
  List<double>? values,
  List<Layer>? layers,
}) => MaterialApp(
  home: Scaffold(
    body: TimelinePanel(
      key: key,
      layers: layers ?? _layersOf(cut, marked: marked, rows: rows),
      activeLayerId: rows == 0 ? null : LayerId('$cut-1'),
      substrateGeneration: cut,
      frameCursor: _cursor,
      playbackFrameCount: 12,
      exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
      onSelectLayer: (_) {},
      onSelectFrame: (_) {},
      onAddLayer: () {},
      onToggleLayerVisibility: (_) {},
      onLayerOpacityChanged: (_, _) {},
      onToggleLayerTimesheet: (_) {},
      onLayerMarkSelected: (_, _) {},
      orientation: orientation,
      onOrientationChanged: (_) {},
      legendHand: legendHand,
      legend: LayerLegendCallbacks(
        onShowAllLayers: () {},
        onHideAllLayers: () {},
        onToggleVisibilitySolo: () {},
        onSheetAllOn: () {},
        onSheetAllOff: () {},
        onClearMarkFilter: () {},
        onClearAllClips: () {},
        onBypassAllFx: () {},
        onEnableAllFx: () {},
        onToggleMarkFilter: (_) {},
        onToggleKindFilter: (_) {},
        onToggleSheetOnlyFilter: () {},
        onToggleFxOnlyFilter: () {},
        onToggleClippedOnlyFilter: () {},
        onPreviewLayersOpacity: (_, value) => values?.add(value),
        onCommitLayersOpacity: (ids, value) {
          committed.add(ids);
          values?.add(value);
        },
      ),
    ),
  ),
);
