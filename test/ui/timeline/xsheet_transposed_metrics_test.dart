import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// R10 R6 — THE X-SHEET IS THE TIMELINE, TURNED ON ITS SIDE.
///
/// Every number the sheet used to type for itself (36 / 164 / 72 / 92) is
/// one of the timeline's, rotated. These tests exist so that stops being a
/// comment: compacting the timeline rail has to move the sheet, and a
/// derivation nobody asserts is a coincidence waiting to be re-typed.

Layer _layer(String id, String name, {LayerKind kind = LayerKind.animation}) {
  return Layer(
    id: LayerId(id),
    name: name,
    kind: kind,
    frames: [Frame(id: FrameId('frame-$id'), duration: 4, strokes: const [])],
  );
}

Widget _grid({double height = 900}) {
  final cursor = ValueNotifier<int>(0);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: height,
        child: XSheetTimelineGrid(
          layers: [_layer('layer-1', 'Layer 1'), _layer('layer-2', 'Layer 2')],
          activeLayerId: const LayerId('layer-1'),
          frameCursor: cursor,
          frameCount: 8,
          exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
        ),
      ),
    ),
  );
}

void main() {
  group('the transposition, as arithmetic', () {
    const sheet = XSheetTimelineGrid.defaultMetrics;

    test('a layer COLUMN is as wide as a layer ROW is tall', () {
      expect(sheet.layerRowHeight, timelineLayerRowHeight);
      // 164 → 28. This is the change that makes everything in the header
      // stand up: nothing reads horizontally in 28px.
      expect(sheet.layerRowHeight, 28);
    });

    test('a frame ROW is as tall as a frame CELL is wide', () {
      expect(sheet.frameCellWidth, timelineFrameCellWidth);
      expect(sheet.frameCellWidth, 24);
    });

    test('the frame-number RAIL is as wide as the RULER is tall', () {
      expect(sheet.layerControlsWidth, timelineFrameRulerExtent);
      // And the ruler is exactly one row, which is why its ticks line up
      // with the rows below it.
      expect(timelineFrameRulerExtent, timelineLayerRowHeight);
    });

    test('the sheet keeps no section gutter — its section axis is the '
        'other one', () {
      expect(sheet.sectionLabelGutterWidth, 0);
    });
  });

  group('the header block is the rail, stood up', () {
    test('its natural height is the rail width less the columns this host '
        'does not carry', () {
      final layout = XSheetTimelineGrid.headerLayoutFor(10000);
      expect(
        layout.blockHeight,
        timelineLayerControlsWidth - layerOnionSlotWidth - layerBlendSlotWidth,
      );
      expect(layout.showsFillReference, isTrue);
      expect(layout.showsOpacity, isTrue);
    });

    test('a short panel gives ground in a fixed order: name, then opacity, '
        'then fill-reference', () {
      final tall = XSheetTimelineGrid.headerLayoutFor(10000);

      // Enough to squeeze the NAME but keep every column.
      final squeezed = XSheetTimelineGrid.headerLayoutFor(400);
      expect(squeezed.blockHeight, lessThan(tall.blockHeight));
      expect(squeezed.showsOpacity, isTrue);
      expect(squeezed.showsFillReference, isTrue);

      // Tighter still: opacity is the first column to go — a 28px-wide
      // slider was never worth the 42px it stood in.
      final tight = XSheetTimelineGrid.headerLayoutFor(330);
      expect(tight.showsOpacity, isFalse);
      expect(tight.showsFillReference, isTrue);

      // Tighter again: the fill-reference flag follows.
      final cramped = XSheetTimelineGrid.headerLayoutFor(280);
      expect(cramped.showsOpacity, isFalse);
      expect(cramped.showsFillReference, isFalse);
    });

    test('the block never grows as the panel shrinks', () {
      var previous = double.infinity;
      for (var extent = 900.0; extent >= 100; extent -= 10) {
        final height = XSheetTimelineGrid.headerLayoutFor(extent).blockHeight;
        expect(height, lessThanOrEqualTo(previous));
        previous = height;
      }
    });
  });

  group('the mounted header agrees with the derived height', () {
    // The crosscheck's gap: every downstream number — the body viewport,
    // the paint window, the scrollbar thumb — is computed FROM the header
    // constant, so a header whose real height differs from it mis-sizes all
    // three and NOTHING throws. Read the pixels back.
    testWidgets('a column header renders exactly its resolved extent', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_grid());

      final expected = XSheetTimelineGrid.headerLayoutFor(900);
      final header = tester.getRect(
        find.byKey(const ValueKey<String>('xsheet-layer-header-layer-1')),
      );
      expect(header.height, closeTo(expected.headerHeight, 0.01));
      expect(header.width, XSheetTimelineGrid.defaultMetrics.layerRowHeight);
    });

    testWidgets('the legend column spans the whole block, band included', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_grid());

      final expected = XSheetTimelineGrid.headerLayoutFor(900);
      final legend = tester.getRect(find.byType(TimelineLayerControlsHeader));
      expect(legend.height, closeTo(expected.blockHeight, 0.01));
      // It is the CORNER: as wide as the frame-number rail it sits over.
      expect(
        legend.width,
        XSheetTimelineGrid.defaultMetrics.layerControlsWidth,
      );
    });

    testWidgets('a short panel does not overflow — the whole point of the '
        'give-ground ladder', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 260 is the tightest x-sheet harness in the corpus, and roughly what
      // a docked timesheet gets in a small window.
      await tester.pumpWidget(_grid(height: 260));
      expect(tester.takeException(), isNull);
    });
  });

  group('the legend names the columns it sits over', () {
    testWidgets('the corner carries the legend cells, not the word Frame', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_grid());

      // The sheet was the one grid whose columns had no headings at all.
      expect(find.text('Frame'), findsNothing);
      for (final key in [
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
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '$key must label its stood-up column',
        );
      }
    });

    testWidgets('each legend cell sits ON its header slot', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_grid());

      // The Excel-header rule, stood up: the legend's vertical offset
      // inside the corner must match the control's inside its column.
      // Measured against the REAL geometry, never against a constant, so a
      // drift cannot be papered over by editing one.
      final legendTop = tester
          .getRect(find.byType(TimelineLayerControlsHeader))
          .top;
      final headerTop = tester
          .getRect(
            find.byKey(const ValueKey<String>('xsheet-layer-header-layer-1')),
          )
          .top;
      // The header starts one band strip below the legend's own top.
      expect(
        headerTop - legendTop,
        closeTo(layerSectionLabelSlotWidth, 0.01),
      );

      double centerOf(Finder finder) => tester.getRect(finder).center.dy;
      final eyeLegend = centerOf(
        find.byKey(const ValueKey<String>('legend-eye')),
      );
      final eyeRow = centerOf(
        find.byKey(
          const ValueKey<String>('xsheet-layer-visibility-layer-1'),
        ),
      );
      expect(
        eyeLegend - legendTop,
        closeTo(eyeRow - legendTop, 1.0),
        reason: 'the eye legend must sit over the eye column',
      );
    });
  });

  group('the trailing run knows its own order', () {
    test('counting from a slot answers what sits after it', () {
      expect(
        layerRailTrailingWidth(from: LayerRailTrailingSlot.mute),
        layerMuteSlotWidth + layerOpacitySlotWidth,
      );
      expect(
        layerRailTrailingWidth(
          from: LayerRailTrailingSlot.mute,
          hasBlendColumn: true,
        ),
        layerMuteSlotWidth + layerOpacitySlotWidth + layerBlendSlotWidth,
      );
      // R10 R6: the eye-swipe band read the tail by hand and forgot BLEND
      // entirely, so the band sat 58px off the eye whenever blend showed.
      // The difference the hand-written version missed:
      expect(
        layerRailTrailingWidth(
              from: LayerRailTrailingSlot.mute,
              hasBlendColumn: true,
            ) -
            layerRailTrailingWidth(from: LayerRailTrailingSlot.mute),
        layerBlendSlotWidth,
      );
    });

    test('a dropped column costs nothing', () {
      expect(
        layerRailTrailingWidth(hasOpacityColumn: false),
        layerRailTrailingWidth() - layerOpacitySlotWidth,
      );
      expect(
        layerRailTrailingWidth(hasFillReferenceColumn: false),
        layerRailTrailingWidth() - layerFillReferenceSlotWidth,
      );
    });
  });

  group('one slot skeleton, two orientations', () {
    test('the leading cells spend the same extents either way', () {
      final horizontal = layerRailLeadingCells();
      final vertical = layerRailLeadingCells(axis: Axis.vertical);
      expect(horizontal, hasLength(vertical.length));
    });

    test('the x-sheet header skips the band slot — its band is a strip of '
        'its own above the columns', () {
      expect(
        layerRailLeadingCells(
          axis: Axis.vertical,
          includeSectionSlot: false,
        ),
        hasLength(layerRailLeadingCells(axis: Axis.vertical).length - 1),
      );
    });
  });
}
