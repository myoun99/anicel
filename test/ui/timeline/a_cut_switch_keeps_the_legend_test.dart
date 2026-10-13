import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_legend_menus.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

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
void main() {
  testWidgets('a cut switch builds nothing of the legend header again', (
    tester,
  ) async {
    await _show(tester, _panel('one', []));
    expect(
      find.byType(TimelineLayerControlsHeader),
      findsOneWidget,
      reason: 'LIVENESS: the legend stands',
    );

    final built = await _legendBuildsWhile(
      () => _show(tester, _panel('two', [])),
    );

    expect(built.grids, greaterThan(0), reason: 'LIVENESS: the grid was built');
    expect(built.inLegend, isEmpty);
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

  testWidgets('the master opacity bar acts on the layers on display NOW', (
    tester,
  ) async {
    final committed = <Set<LayerId>>[];
    await _show(tester, _panel('one', committed));
    await _show(tester, _panel('two', committed));

    await tester.drag(
      find.byKey(const ValueKey<String>('legend-opacity')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();

    expect(committed, isNotEmpty, reason: 'LIVENESS: the bar committed');
    expect(committed.last, {
      const LayerId('two-1'),
      const LayerId('two-2'),
      const LayerId('two-3'),
    });
  });
}

const _layout = LayerMark(process: LayerProcess.layout);

/// The widgets built under the legend header while [act] runs — the
/// header's own build, which only compares what it shows, aside — and how
/// many times the grid round it was.
Future<({List<Type> inLegend, int grids})> _legendBuildsWhile(
  Future<void> Function() act,
) async {
  final inLegend = <Type>[];
  var grids = 0;
  debugOnRebuildDirtyWidget = (element, _) {
    if (element.widget is LayerTimelineGrid) {
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

Future<void> _show(WidgetTester tester, Widget panel) async {
  await tester.binding.setSurfaceSize(const Size(1400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(panel);
  await tester.pumpAndSettle();
}

/// A cut of three drawings — the same faces in every cut, other layers;
/// [marked], the first one an instruction labelled for layout.
List<Layer> _layersOf(String cut, {required bool marked}) => [
  for (final (index, name) in const ['One', 'Two', 'Three'].indexed)
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
}) => MaterialApp(
  home: Scaffold(
    body: TimelinePanel(
      layers: _layersOf(cut, marked: marked),
      activeLayerId: LayerId('$cut-1'),
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
      orientation: TimelineOrientation.horizontal,
      onOrientationChanged: (_) {},
      legend: LayerLegendCallbacks(
        onShowAllLayers: () {},
        onHideAllLayers: () {},
        onToggleVisibilitySolo: () {},
        onSheetAllOn: () {},
        onSheetAllOff: () {},
        onClearMarkFilter: () {},
        onClearAllFillReferences: () {},
        onMuteAllSe: () {},
        onUnmuteAllSe: () {},
        onBypassAllFx: () {},
        onEnableAllFx: () {},
        onToggleMarkFilter: (_) {},
        onToggleKindFilter: (_) {},
        onToggleSheetOnlyFilter: () {},
        onToggleFxOnlyFilter: () {},
        onToggleFillReferenceOnlyFilter: () {},
        onPreviewLayersOpacity: (_, _) {},
        onCommitLayersOpacity: (ids, _) => committed.add(ids),
      ),
    ),
  ),
);
