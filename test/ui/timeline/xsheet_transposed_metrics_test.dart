import 'dart:math' as math;

import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
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
    test('a tall panel gets the whole rail, and NOT ONE PIXEL MORE', () {
      final tall = XSheetTimelineGrid.headerLayoutFor(10000);
      // The sheet comes first: making the panel taller has to add FRAME
      // ROWS, never more header. The first cut of this got it backwards —
      // the block grew with the panel and the sheet sat pinned at its
      // minimum across a 160px range of panel heights.
      expect(
        XSheetTimelineGrid.headerLayoutFor(100000).blockHeight,
        tall.blockHeight,
      );
      // Opacity is the one column the sheet NEVER carries.
      expect(tall.shed, {LayerRailSlot.opacity});
    });

    test('controls come back last-shed-first, and NOT ONE of them before '
        'the name is paid in full', () {
      double comesBackAt(LayerRailSlot slot) {
        for (var extent = 60.0; extent <= 1400; extent += 1) {
          if (!XSheetTimelineGrid.headerLayoutFor(extent).shed.contains(slot)) {
            return extent;
          }
        }
        return double.infinity;
      }

      // Read the ladder back from behaviour rather than pinning pixels: the
      // contract is the ORDER, and the reverse of the shed order is what a
      // growing panel must restore.
      const restoreOrder = [
        LayerRailSlot.timesheet,
        LayerRailSlot.fx,
        LayerRailSlot.mute,
        LayerRailSlot.mark,
        LayerRailSlot.fillReference,
      ];
      var previous = 0.0;
      for (final slot in restoreOrder) {
        final extent = comesBackAt(slot);
        expect(
          extent,
          lessThan(double.infinity),
          reason: '$slot never comes back',
        );
        expect(
          extent,
          greaterThan(previous),
          reason: '$slot came back out of ladder order',
        );
        previous = extent;
      }

      // Opacity has no rung at all — the sheet never carries it.
      expect(comesBackAt(LayerRailSlot.opacity), double.infinity);

      // ★ Nor does the LANE TWIRL, and for the opposite reason: it is the
      // only way out of a state it puts the sheet into. Lane expansion
      // survives a resize, so shedding the twirl would leave the lane
      // columns on screen with nothing to close them.
      expect(
        comesBackAt(LayerRailSlot.laneToggle),
        60,
        reason: 'the lane twirl must never be shed',
      );

      // The ladder bottoms out: the KIND icon, the NAME and the EYE have
      // no rung, so however short the panel gets they are still there. A
      // column heading that cannot say which layer it heads is not a
      // heading, and this is the surface the user reads most.
      Set<LayerRailSlot> shedAt(double extent) =>
          XSheetTimelineGrid.headerLayoutFor(extent).shed;
      expect(shedAt(0), shedAt(60), reason: 'the ladder has a last rung');
      expect(shedAt(0), isNot(contains(LayerRailSlot.laneToggle)));
    });

    testWidgets('a splitter drag never takes back what it just gave', (
      tester,
    ) async {
      // The first cut asserted only `blockHeight` and `shed.length` under
      // this very title, and the name — the thing rule 2 says outranks the
      // controls — shrank 71px → 48px at six panel heights inside the
      // dock's own drag range, every one of them while the panel got
      // BIGGER. Measure the RENDERED name, one pixel at a time.
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var previousBlock = 0.0;
      var previousShed = 99;
      var previousName = 0.0;
      // Every rung boundary lives in here; the pure-math test below sweeps
      // the whole range more cheaply.
      for (var extent = 240.0; extent <= 440; extent += 1) {
        final layout = XSheetTimelineGrid.headerLayoutFor(extent);
        expect(
          layout.blockHeight,
          greaterThanOrEqualTo(previousBlock),
          reason: 'the header shrank as the panel grew ($extent)',
        );
        expect(
          layout.shed.length,
          lessThanOrEqualTo(previousShed),
          reason: 'a column vanished as the panel grew ($extent)',
        );

        await tester.pumpWidget(_grid(height: extent));
        final name = tester
            .getSize(
              find.byKey(const ValueKey<String>('xsheet-layer-name-layer-1')),
            )
            .height;
        expect(
          name,
          greaterThanOrEqualTo(previousName),
          reason: 'the column name shrank as the panel grew ($extent)',
        );

        previousBlock = layout.blockHeight;
        previousShed = layout.shed.length;
        previousName = name;
      }
    });

    test(
      'the block only ever grows with the panel, across the whole range',
      () {
        var previousBlock = 0.0;
        var previousShed = 99;
        for (var extent = 60.0; extent <= 1000; extent += 0.5) {
          final layout = XSheetTimelineGrid.headerLayoutFor(extent);
          expect(layout.blockHeight, greaterThanOrEqualTo(previousBlock));
          expect(layout.shed.length, lessThanOrEqualTo(previousShed));
          previousBlock = layout.blockHeight;
          previousShed = layout.shed.length;
        }
      },
    );

    test('the sheet always keeps four frame rows once the ladder can pay '
        'for them', () {
      const minSheet = 4 * timelineFrameCellWidth;
      for (var extent = 400.0; extent <= 1000; extent += 1) {
        final block = XSheetTimelineGrid.headerLayoutFor(extent).blockHeight;
        expect(
          extent - block - timelineBottomScrollbarRailHeight,
          greaterThanOrEqualTo(minSheet),
          reason: 'a $extent panel left less than four rows of sheet',
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

    testWidgets('NO panel height overflows, and none hides the name', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Every 10px from a panel far below the dock minimum up to a tall
      // one. The first cut passed a single probe at 260 — which happened to
      // sit 4px inside the one band that still worked.
      // From below the point where even a kind icon, a name and an eye fit
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
      // …and no OPACITY heading, because the sheet has no opacity column.
      expect(
        find.byKey(const ValueKey<String>('legend-opacity')),
        findsNothing,
      );
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

    test('a shed column costs nothing', () {
      expect(
        layerRailTrailingWidth(shed: const {LayerRailSlot.opacity}),
        layerRailTrailingWidth() - layerOpacitySlotWidth,
      );
      expect(
        layerRailTrailingWidth(shed: const {LayerRailSlot.fillReference}),
        layerRailTrailingWidth() - layerFillReferenceSlotWidth,
      );
      // The EYE has no rung, so there is no way to ask for it to go.
      expect(
        layerRailTrailingWidth(shed: LayerRailSlot.values.toSet()),
        layerVisibilitySlotWidth,
      );
      // Nor does a panel below the last rung reach zero height: the layout
      // floors the header so a `Container(height:)` never goes negative.
      for (final extent in [0.0, 10.0, 36.0, 51.9, 52.0]) {
        expect(
          XSheetTimelineGrid.headerLayoutFor(extent).headerHeight,
          greaterThanOrEqualTo(0),
          reason: 'a $extent panel produced a negative header height',
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
