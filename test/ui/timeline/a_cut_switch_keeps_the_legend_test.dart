import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
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
    final inLegend = <Type>[];
    var grids = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is LayerTimelineGrid) {
        grids += 1;
      }
      var under = element.widget is TimelineLayerControlsHeader;
      element.visitAncestorElements((ancestor) {
        under = under || ancestor.widget is TimelineLayerControlsHeader;
        return !under;
      });
      if (under) {
        inLegend.add(element.widget.runtimeType);
      }
    };
    try {
      await _show(tester, _panel('two', []));
    } finally {
      debugOnRebuildDirtyWidget = null;
    }

    expect(grids, greaterThan(0), reason: 'LIVENESS: the grid was built');
    expect(inLegend, isEmpty);
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

Future<void> _show(WidgetTester tester, Widget panel) async {
  await tester.binding.setSurfaceSize(const Size(1400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(panel);
  await tester.pumpAndSettle();
}

/// A cut of three drawings — the same faces in every cut, other layers.
List<Layer> _layersOf(String cut) => [
  for (final (index, name) in const ['One', 'Two', 'Three'].indexed)
    Layer(id: LayerId('$cut-${index + 1}'), name: name, frames: const []),
];

final _cursor = ValueNotifier<int>(0);

Widget _panel(String cut, List<Set<LayerId>> committed) => MaterialApp(
  home: Scaffold(
    body: TimelinePanel(
      layers: _layersOf(cut),
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
