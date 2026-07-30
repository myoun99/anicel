import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

void main() {
  group('TimelineLayerControlsHeader', () {
    testWidgets('the wide add-layer button is GONE — the header is the legend '
        '(R-toolbar round) with the column cells exposed by key', (
      tester,
    ) async {
      await tester.pumpWidget(_header());

      expect(
        find.byKey(const ValueKey<String>('timeline-add-layer-button')),
        findsNothing,
      );
      for (final cell in [
        'legend-sections',
        'legend-sheet',
        'legend-mark',
        'legend-kind',
        'legend-layer',
        'legend-fill-ref',
        'legend-fx',
        'legend-eye',
        'legend-mute',
        'legend-opacity',
      ]) {
        expect(find.byKey(ValueKey<String>(cell)), findsOneWidget);
      }
    });

    testWidgets('LAYER is a plain heading now (R4 #3): no flyout, no add '
        'entry — the command bar owns Add Layer', (tester) async {
      await tester.pumpWidget(_header());

      await tester.tap(find.byKey(const ValueKey<String>('legend-layer')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('legend-layer-add')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('legend-lanes-expand')),
        findsNothing,
      );
    });
  });

  group('TimelineLayerControlsRow', () {
    testWidgets('exposes stable row keys', (tester) async {
      final layer = _layer();

      await tester.pumpWidget(_row(layer: layer));

      expect(
        find.byKey(ValueKey<String>('timeline-layer-row-${layer.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('timeline-layer-name-${layer.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('timeline-layer-kind-icon-${layer.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('timeline-layer-visibility-${layer.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('timeline-layer-opacity-${layer.id}')),
        findsOneWidget,
      );
    });

    testWidgets('the row border stays a constant 1px side/bottom set — the '
        'ACTIVE accent is color only, never a 2px content shift '
        '(UI-R10 #20)', (tester) async {
      final layer = _layer();

      Border borderOf() {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(
                  ValueKey<String>('timeline-layer-row-${layer.id}'),
                ),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.decoration! as BoxDecoration).border! as Border;
      }

      await tester.pumpWidget(_row(layer: layer));
      final restBorder = borderOf();
      expect(
        restBorder.top,
        BorderSide.none,
        reason:
            'the neighbor above '
            '(or the legend header) owns the seam',
      );
      expect(restBorder.bottom.width, 1);
      expect(restBorder.left.width, 1);
      expect(restBorder.right.width, 1);

      await tester.pumpWidget(_row(layer: layer, active: true));
      final activeBorder = borderOf();
      expect(activeBorder.top, BorderSide.none);
      expect(activeBorder.bottom.width, 1);
      // UI-R18 #5: selection speaks through the BACKGROUND alone — the
      // border never changes with activation.
      expect(
        activeBorder.bottom.color,
        restBorder.bottom.color,
        reason: 'no accent border; the row fill carries the selection',
      );
    });

    testWidgets('tapping row selects layer', (tester) async {
      final layer = _layer();
      LayerId? selectedLayerId;

      await tester.pumpWidget(
        _row(
          layer: layer,
          onSelectLayer: (layerId) => selectedLayerId = layerId,
        ),
      );

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-row-${layer.id}')),
      );

      expect(selectedLayerId, layer.id);
    });

    testWidgets('tapping layer name selects layer', (tester) async {
      final layer = _layer();
      LayerId? selectedLayerId;

      await tester.pumpWidget(
        _row(
          layer: layer,
          onSelectLayer: (layerId) => selectedLayerId = layerId,
        ),
      );

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-name-${layer.id}')),
      );

      expect(selectedLayerId, layer.id);
    });

    testWidgets('tapping visibility button toggles layer visibility', (
      tester,
    ) async {
      final layer = _layer();
      LayerId? toggledLayerId;

      await tester.pumpWidget(
        _row(
          layer: layer,
          onToggleLayerVisibility: (layerId) => toggledLayerId = layerId,
        ),
      );

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-visibility-${layer.id}')),
      );

      expect(toggledLayerId, layer.id);
    });

    testWidgets('changing opacity invokes callback with layer id and value', (
      tester,
    ) async {
      final layer = _layer();
      LayerId? changedLayerId;
      double? changedOpacity;

      await tester.pumpWidget(
        _row(
          layer: layer,
          onLayerOpacityChanged: (layerId, opacity) {
            changedLayerId = layerId;
            changedOpacity = opacity;
          },
        ),
      );

      final slider = tester.widget<FieldSlider>(
        find.byKey(ValueKey<String>('timeline-layer-opacity-${layer.id}')),
      );
      slider.onChanged?.call(0.25);

      expect(changedLayerId, layer.id);
      expect(changedOpacity, 0.25);
    });

    testWidgets('the row slider FOLLOWS a master-bar drag targeting it and '
        'snaps back when the drag ends (UI-R6 #2)', (tester) async {
      final layer = _layer();
      final preview = ValueNotifier<({Set<LayerId> layerIds, double opacity})?>(
        null,
      );
      addTearDown(preview.dispose);

      await tester.pumpWidget(_row(layer: layer, opacityDragPreview: preview));
      final sliderFinder = find.byKey(
        ValueKey<String>('timeline-layer-opacity-${layer.id}'),
      );
      expect(tester.widget<FieldSlider>(sliderFinder).value, 1.0);

      // A drag step targeting THIS layer moves the slider live.
      preview.value = (layerIds: {layer.id}, opacity: 0.3);
      await tester.pump();
      expect(
        tester.widget<FieldSlider>(sliderFinder).value,
        closeTo(0.3, 1e-9),
      );

      // A drag targeting OTHER rows leaves it at rest.
      preview.value = (layerIds: {const LayerId('someone-else')}, opacity: 0.7);
      await tester.pump();
      expect(tester.widget<FieldSlider>(sliderFinder).value, 1.0);

      // Release: back to the layer's own (repo) value.
      preview.value = null;
      await tester.pump();
      expect(tester.widget<FieldSlider>(sliderFinder).value, 1.0);
    });

    testWidgets('active row exposes selected-layer semantic key', (
      tester,
    ) async {
      final layer = _layer();

      await tester.pumpWidget(_row(layer: layer, active: true));

      expect(
        find.byKey(const ValueKey<String>('timeline-selected-layer')),
        findsOneWidget,
      );

      await tester.pumpWidget(_row(layer: layer));

      expect(
        find.byKey(const ValueKey<String>('timeline-selected-layer')),
        findsNothing,
      );
    });

    testWidgets('tapping timesheet toggle reports the layer', (tester) async {
      final layer = _layer();
      LayerId? toggledLayerId;

      await tester.pumpWidget(
        _row(
          layer: layer,
          onToggleLayerTimesheet: (layerId) => toggledLayerId = layerId,
        ),
      );

      expect(find.byTooltip('Remove from timesheet'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-timesheet-${layer.id}')),
      );

      expect(toggledLayerId, layer.id);
    });

    testWidgets('excluded layer offers the add-to-timesheet tooltip', (
      tester,
    ) async {
      final layer = _layer().copyWith(onTimesheet: false);

      await tester.pumpWidget(_row(layer: layer));

      expect(find.byTooltip('Add to timesheet'), findsOneWidget);
      expect(find.byTooltip('Remove from timesheet'), findsNothing);
    });

    testWidgets('selecting a mark from the chip popup reports it', (
      tester,
    ) async {
      final layer = _layer();
      LayerId? markedLayerId;
      LayerMark? selectedMark;

      await tester.pumpWidget(
        _row(
          layer: layer,
          onLayerMarkSelected: (layerId, mark) {
            markedLayerId = layerId;
            selectedMark = mark;
          },
        ),
      );

      await tester.tap(
        find.byKey(ValueKey<String>('timeline-layer-mark-${layer.id}')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('layer-mark-option-blue')),
      );
      await tester.pumpAndSettle();

      expect(markedLayerId, layer.id);
      expect(selectedMark, LayerMark.blue);
    });

    testWidgets('every kind carries the timesheet toggle (unified layer '
        'controls)', (tester) async {
      final storyboardLayer = _layer().copyWith(kind: LayerKind.storyboard);

      await tester.pumpWidget(_row(layer: storyboardLayer));

      expect(
        find.byKey(
          ValueKey<String>('timeline-layer-timesheet-${storyboardLayer.id}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('timeline-layer-mark-${storyboardLayer.id}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the camera layer carries both chips AND the opacity '
        'slider (camera-view dim, unified layer controls)', (tester) async {
      final cameraLayer = _layer().copyWith(kind: LayerKind.camera);

      await tester.pumpWidget(_row(layer: cameraLayer));

      expect(
        find.byKey(
          ValueKey<String>('timeline-layer-timesheet-${cameraLayer.id}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('timeline-layer-mark-${cameraLayer.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('timeline-layer-opacity-${cameraLayer.id}'),
        ),
        findsOneWidget,
      );
    });
  });

  /// R8: the label's fx switch is a MASTER over the row's per-group
  /// switches, so it has a third look — and the tooltip has to say which
  /// way a tap will resolve the row.
  group('the fx master switch (R8)', () {
    Finder fxButton(Layer layer) =>
        find.byKey(ValueKey<String>('timeline-layer-fx-${layer.id}'));

    TextStyle glyphStyle(WidgetTester tester, Layer layer) => tester
        .widget<Text>(
          find.descendant(of: fxButton(layer), matching: find.text('fx')),
        )
        .style!;

    testWidgets('MIXED reads as neither on nor off — half accent plus an '
        'underline the colour-blind eye can see', (tester) async {
      final layer = _layer();

      await tester.pumpWidget(
        _row(layer: layer, fxState: LayerFxState.on, onToggleLayerFx: (_) {}),
      );
      final on = glyphStyle(tester, layer);
      expect(on.decoration, TextDecoration.none);

      await tester.pumpWidget(
        _row(layer: layer, fxState: LayerFxState.off, onToggleLayerFx: (_) {}),
      );
      final off = glyphStyle(tester, layer);
      expect(off.decoration, TextDecoration.none);

      await tester.pumpWidget(
        _row(
          layer: layer,
          fxState: LayerFxState.mixed,
          onToggleLayerFx: (_) {},
        ),
      );
      final mixed = glyphStyle(tester, layer);
      expect(mixed.decoration, TextDecoration.underline);
      expect(mixed.color, isNot(on.color));
      expect(mixed.color, isNot(off.color));
      expect(
        mixed.color!.a,
        closeTo(on.color!.a * 0.5, 0.01),
        reason: 'the ON accent held back to half',
      );
    });

    testWidgets('the tooltip names what a tap will do to the whole row', (
      tester,
    ) async {
      final layer = _layer();

      for (final (state, expected) in [
        (LayerFxState.on, 'Bypass layer FX'),
        (LayerFxState.off, 'Apply layer FX'),
        (LayerFxState.mixed, 'Bypass all layer FX (some are off)'),
      ]) {
        await tester.pumpWidget(
          _row(layer: layer, fxState: state, onToggleLayerFx: (_) {}),
        );
        expect(
          tester.widget<IconButton>(fxButton(layer)).tooltip,
          expected,
          reason: 'state $state',
        );
      }
    });

    testWidgets('tapping reports the layer once', (tester) async {
      final layer = _layer();
      final taps = <LayerId>[];

      await tester.pumpWidget(
        _row(
          layer: layer,
          fxState: LayerFxState.mixed,
          onToggleLayerFx: taps.add,
        ),
      );
      await tester.tap(fxButton(layer));
      await tester.pump();

      expect(taps, [layer.id]);
    });
  });
}

Widget _header() {
  return MaterialApp(
    home: Material(
      child: TimelineLayerControlsHeader(metrics: TimelineGridMetrics.defaults),
    ),
  );
}

Widget _row({
  required Layer layer,
  bool active = false,
  ValueChanged<LayerId>? onSelectLayer,
  ValueChanged<LayerId>? onToggleLayerVisibility,
  void Function(LayerId layerId, double opacity)? onLayerOpacityChanged,
  ValueChanged<LayerId>? onToggleLayerTimesheet,
  void Function(LayerId layerId, LayerMark mark)? onLayerMarkSelected,
  LayerFxState fxState = LayerFxState.on,
  ValueChanged<LayerId>? onToggleLayerFx,
  ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview,
}) {
  return MaterialApp(
    home: Material(
      child: TimelineLayerControlsRow(
        layer: layer,
        active: active,
        metrics: TimelineGridMetrics.defaults,
        onSelectLayer: onSelectLayer ?? (_) {},
        onToggleLayerVisibility: onToggleLayerVisibility ?? (_) {},
        onLayerOpacityChanged: onLayerOpacityChanged ?? (_, _) {},
        onToggleLayerTimesheet: onToggleLayerTimesheet ?? (_) {},
        onLayerMarkSelected: onLayerMarkSelected ?? (_, _) {},
        fxState: fxState,
        onToggleLayerFx: onToggleLayerFx,
        opacityDragPreview: opacityDragPreview,
      ),
    ),
  );
}

Layer _layer() {
  return Layer(
    id: const LayerId('layer-test'),
    name: 'Layer Test',
    frames: const [],
  );
}
