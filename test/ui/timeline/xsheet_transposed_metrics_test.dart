import 'dart:math' as math;

import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
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

Widget _grid({double height = 900, LayerRailExtent? railExtent}) {
  final cursor = ValueNotifier<int>(0);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: height,
        child: XSheetTimelineGrid(
          railExtent: railExtent,
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

/// The sheet as the panel really builds it: onion and blend columns on,
/// and no legend bulk callbacks (it has no flyouts of its own).
Widget _gridWithOptionalColumns() {
  final cursor = ValueNotifier<int>(0);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 900,
        child: XSheetTimelineGrid(
          layers: [_layer('layer-1', 'Layer 1')],
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
          onToggleLayerOnionSkin: (_) {},
          onLayerBlendModeSelected: (_, _) {},
        ),
      ),
    ),
  );
}

double sheetLeft(WidgetTester tester) =>
    tester.getRect(find.byType(XSheetTimelineGrid)).left;

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
    test('the natural block is the WHOLE rail, plus its two hairlines', () {
      // The user overturned the shedding design outright: "타임라인에
      // 있는거 싹다 넣어. 뭐 빼지말고."
      expect(
        XSheetTimelineGrid.naturalHeaderBlockExtent(
          hasOnionColumn: true,
          hasBlendColumn: true,
        ),
        timelineLayerControlsWidth + 2,
      );
      // A host that declines the two optional columns costs exactly them
      // less — the legend beside the headers sizes from the same call, so
      // the two cannot part.
      expect(
        XSheetTimelineGrid.naturalHeaderBlockExtent(
          hasOnionColumn: false,
          hasBlendColumn: false,
        ),
        timelineLayerControlsWidth +
            2 -
            layerOnionSlotWidth -
            layerBlendSlotWidth,
      );
    });

    testWidgets('untouched, the block is its natural extent whatever the '
        'panel has to spare', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // This harness declines the two optional columns, so the sheet's own
      // natural block is that much shorter — and the legend must size from
      // the same answer.
      final natural = XSheetTimelineGrid.naturalHeaderBlockExtent(
        hasOnionColumn: false,
        hasBlendColumn: false,
      );
      for (final height in [700.0, 1000.0]) {
        await tester.pumpWidget(_grid(height: height));
        final legend = tester.getRect(find.byType(TimelineLayerControlsHeader));
        expect(
          legend.height,
          closeTo(natural, 0.01),
          reason: 'a $height panel did not show the whole block',
        );
        expect(
          tester.getRect(find.byType(LayerRailWindow).first).height,
          closeTo(natural, 0.01),
          reason: 'a $height panel cut a block it could afford whole',
        );
      }
    });

    testWidgets('the splitter cuts the block, and the header inside it does '
        'not move', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final rail = LayerRailExtent();
      addTearDown(rail.dispose);
      await tester.pumpWidget(_grid(railExtent: rail));

      final headerKey = const ValueKey<String>('xsheet-layer-header-layer-1');
      final naturalHeader = tester.getSize(find.byKey(headerKey)).height;

      rail.resizeBy(
        -100,
        naturalExtent: XSheetTimelineGrid.naturalHeaderBlockExtent(
          hasOnionColumn: false,
          hasBlendColumn: false,
        ),
      );
      await tester.pump();

      // NOTHING inside rearranged — that is the whole model. R10 R6 packed
      // the name here and R6a scaled the column; both would move this
      // number.
      expect(tester.getSize(find.byKey(headerKey)).height, naturalHeader);
      // What changed is the WINDOW, and the legend beside it was cut at
      // exactly the same line (R6a's bug: the legend clipped while the
      // headers scaled, and below 494px they visibly parted).
      final windows = tester.widgetList<LayerRailWindow>(
        find.byType(LayerRailWindow),
      );
      expect(windows, hasLength(2));
      final bottoms = {
        for (final window in windows)
          tester.getRect(find.byWidget(window)).bottom.round(),
      };
      expect(bottoms, hasLength(1), reason: 'one cut, one line');
    });

    testWidgets('the sheet carries three bars and a corner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_grid());

      // The LAYER axis runs across the sheet, so its bar is the strip
      // along the TOP — and the seconds toggle sits in the corner beside
      // it, off the command bar.
      final layerAxisBar = tester.getRect(
        find.byKey(const ValueKey<String>('xsheet-horizontal-scrollbar')),
      );
      final sheetTop = tester.getRect(find.byType(XSheetTimelineGrid)).top;
      expect(layerAxisBar.top, closeTo(sheetTop, 0.01));
      expect(
        find.byKey(const ValueKey<String>('xsheet-time-display-toggle-button')),
        findsOneWidget,
      );

      // The 16px column carries TWO bars, split by the splitter: the
      // rail's above, the frame axis's below.
      final railBar = tester.getRect(
        find.byKey(const ValueKey<String>('xsheet-rail-scrollbar')),
      );
      final splitter = tester.getRect(
        find.byKey(const ValueKey<String>('xsheet-rail-splitter')),
      );
      final frameBar = tester.getRect(
        find.byKey(const ValueKey<String>('xsheet-vertical-scrollbar')),
      );
      expect(railBar.bottom, closeTo(splitter.top, 0.01));
      expect(frameBar.top, closeTo(splitter.bottom, 0.01));
      expect(
        railBar.width,
        XSheetTimelineGrid.defaultMetrics.verticalScrollbarWidth,
      );
      expect(railBar.left, closeTo(frameBar.left, 0.01));
      // The splitter starts after the frame-number rail: that column is
      // the FRAME axis's and the splitter has nothing to say about it.
      expect(
        splitter.left,
        closeTo(
          sheetLeft(tester) +
              XSheetTimelineGrid.defaultMetrics.layerControlsWidth,
          0.01,
        ),
      );
    });

    testWidgets('the frame area always keeps its two-row reserve', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Even untouched — the natural block is 436 and most of this range
      // cannot pay for it, so the WINDOW is what gives.
      for (var height = 200.0; height <= 900; height += 20) {
        await tester.pumpWidget(_grid(height: height));
        final legend = tester.getRect(find.byType(TimelineLayerControlsHeader));
        final window = tester
            .getRect(find.byType(LayerRailWindow).first)
            .height;
        expect(
          window,
          lessThanOrEqualTo(legend.height + 0.01),
          reason: 'a $height panel let the window outgrow the block',
        );
        expect(
          height - window,
          greaterThanOrEqualTo(layerRailFrameReserveExtent),
          reason: 'a $height panel left the sheet less than two rows',
        );
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

      final expected =
          XSheetTimelineGrid.naturalHeaderBlockExtent(
            hasOnionColumn: false,
            hasBlendColumn: false,
          ) -
          layerSectionLabelSlotWidth;
      final header = tester.getRect(
        find.byKey(const ValueKey<String>('xsheet-layer-header-layer-1')),
      );
      expect(header.height, closeTo(expected, 0.01));
      expect(header.width, XSheetTimelineGrid.defaultMetrics.layerRowHeight);
    });

    testWidgets('the legend column spans the whole block, band included', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_grid());

      final expected = XSheetTimelineGrid.naturalHeaderBlockExtent(
        hasOnionColumn: false,
        hasBlendColumn: false,
      );
      final legend = tester.getRect(find.byType(TimelineLayerControlsHeader));
      expect(legend.height, closeTo(expected, 0.01));
      // It is the CORNER: as wide as the frame-number rail it sits over.
      expect(
        legend.width,
        XSheetTimelineGrid.defaultMetrics.layerControlsWidth,
      );
    });

    testWidgets('NO panel height overflows, and none hides the name', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Every 10px from a panel far below the dock minimum up to a tall
      // one. The first cut passed a single probe at 260 — which happened to
      // sit 4px inside the one band that still worked.
      // From below the point where even a kind icon, a name, a twirl and
      // an eye fit
      // — the round's own sweep started at 80 and stopped 28px short of a
      // negative-height assert nobody had floored.
      for (var height = 20.0; height <= 900; height += 10) {
        await tester.pumpWidget(_grid(height: height));
        expect(
          tester.takeException(),
          isNull,
          reason: 'a $height panel overflowed',
        );
        final name = tester.getRect(
          find.byKey(const ValueKey<String>('xsheet-layer-name-layer-1')),
        );
        if (height >= 240) {
          expect(
            name.height,
            greaterThan(0),
            reason: 'a $height panel rendered its column names 0px tall',
          );
          // …and VISIBLE, not merely laid out. The header clips below the
          // ladder's last rung, so a size alone proves nothing: a name
          // pushed past the clip still measures its forced extent.
          final header = tester.getRect(
            find.byKey(const ValueKey<String>('xsheet-layer-header-layer-1')),
          );
          expect(
            name.bottom,
            lessThanOrEqualTo(header.bottom + 0.01),
            reason: 'a $height panel pushed its column name past the clip',
          );
        }
      }
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
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '$key must label its stood-up column',
        );
      }
    });

    testWidgets('ONION and BLND get their headings too — the heading '
        'follows the COLUMN, not the bulk command', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_gridWithOptionalColumns());

      // The sheet carries onion and blend columns but passes no legend
      // bulk callbacks, and the two cells were gated on those callbacks —
      // so exactly those two columns had a reserved slot and no heading.
      for (final key in ['legend-onion', 'legend-blend']) {
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
      expect(headerTop - legendTop, closeTo(layerSectionLabelSlotWidth, 0.01));

      double centerOf(Finder finder) => tester.getRect(finder).center.dy;
      final eyeLegend = centerOf(
        find.byKey(const ValueKey<String>('legend-eye')),
      );
      final eyeRow = centerOf(
        find.byKey(const ValueKey<String>('xsheet-layer-visibility-layer-1')),
      );
      expect(
        eyeLegend - legendTop,
        closeTo(eyeRow - legendTop, 1.0),
        reason: 'the eye legend must sit over the eye column',
      );
    });
  });

  group('the frame rail', () {
    testWidgets('a PRESS near either end selects, and does not scroll', (
      tester,
    ) async {
      // The rail scrubs from `onPointerDown`, and the auto-pan band is a
      // fraction of the viewport — so the shorter the panel, the larger the
      // share of the rail that could not be tapped without the sheet
      // sliding out from under the finger. Landing near an end is not a
      // push toward it.
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final height in [300.0, 420.0, 600.0]) {
        await tester.pumpWidget(_grid(height: height));
        final rail = tester.getRect(
          find.byKey(const ValueKey<String>('xsheet-frame-rail-scrub-area')),
        );
        // Where the frame rows sit before anyone touches anything.
        final cells = find.byKey(
          const ValueKey<String>('xsheet-column-layer-1-cells'),
        );
        final before = tester.getRect(cells);

        for (final y in [rail.top + 2, rail.bottom - 2, rail.center.dy]) {
          await tester.tapAt(Offset(rail.center.dx, y));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'a $height panel threw on a rail press',
          );
          expect(
            tester.getRect(cells).top,
            closeTo(before.top, 0.01),
            reason:
                'a press at y=$y scrolled a $height panel out from under '
                'the finger',
          );
        }
      }
    });
  });

  group('a lane column heading is a heading too', () {
    // The layer heading beside it is guaranteed a name floor and sheds
    // controls to keep it. The lane heading had neither: its label was
    // simply `Expanded` over whatever the navigator and the value readout
    // left, so at the default dock 'Position' packed into 35px — 2.6px a
    // glyph — while the column one to its left kept its 48.
    Future<Size> pumpLane(WidgetTester tester, double height) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TimelineLaneControlsRow(
                axis: Axis.vertical,
                keyPrefix: 'xsheet',
                layer: _layer('layer-1', 'Layer 1'),
                lane: PropertyLaneRow(
                  laneId: 'position',
                  label: 'Position',
                  keyedFrames: const {0},
                  valueLabel: (_) => '0.0, 0.0',
                ),
                metrics: XSheetTimelineGrid.defaultMetrics,
                width: XSheetTimelineGrid.defaultMetrics.layerRowHeight,
                height: height,
              ),
            ),
          ),
        ),
      );
      return tester.getSize(
        find.byKey(
          const ValueKey<String>('xsheet-lane-label-layer-1-position'),
        ),
      );
    }

    testWidgets('its label keeps a floor, and the controls shed for it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Roomy: everything is there.
      await pumpLane(tester, 300);
      expect(
        find.byKey(
          const ValueKey<String>('xsheet-lane-key-toggle-layer-1-position'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('xsheet-lane-value-layer-1-position'),
        ),
        findsOneWidget,
      );

      // Cramped: the value goes first, then the navigator — and the label
      // never packs below two frame rows.
      for (var height = 60.0; height <= 300; height += 4) {
        await pumpLane(tester, height);
        expect(tester.takeException(), isNull, reason: 'lane at $height');
        final label = tester.getSize(
          find.byWidgetPredicate(
            (w) => w is VerticalWritingText && w.text == 'Position',
          ),
        );
        expect(
          label.height,
          greaterThanOrEqualTo(
            math.min(2 * timelineFrameCellWidth, height - 8),
          ),
          reason: 'the lane label was crushed at $height',
        );
      }
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

    test('the optional columns are the only ones a host may decline', () {
      // Onion and blend are the two the SKELETON makes optional, and the
      // sheet now carries both. Nothing else can be dropped: every rail
      // surface draws every other slot, which is what makes the legend's
      // icons line up over them.
      expect(
        layerRailTrailingWidth(hasOnionColumn: true, hasBlendColumn: true) -
            layerRailTrailingWidth(),
        layerOnionSlotWidth + layerBlendSlotWidth,
      );

      // A panel too short for even the rail's floor never produces a
      // negative window: the panel wins, because an overflow stripe helps
      // nobody.
      final rail = LayerRailExtent();
      addTearDown(rail.dispose);
      for (final extent in [0.0, 10.0, 36.0, 51.9, 52.0]) {
        final window = rail.windowExtent(436, availableExtent: extent);
        expect(window, greaterThanOrEqualTo(0));
        expect(
          window,
          lessThanOrEqualTo(extent),
          reason: 'a $extent panel produced a window it cannot hold',
        );
      }
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
        layerRailLeadingCells(axis: Axis.vertical, includeSectionSlot: false),
        hasLength(layerRailLeadingCells(axis: Axis.vertical).length - 1),
      );
    });
  });
}
