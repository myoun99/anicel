import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show SectionBandZone, sectionBandLabelWithin;
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';

Layer _layer(String id, LayerKind kind) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: kind == LayerKind.camera
        ? const []
        : [Frame(id: FrameId('$id-frame'), duration: 1, strokes: const [])],
    timeline: const {},
  );
}

void main() {
  group('timeline section policy', () {
    test('maps layer kinds onto timesheet sections', () {
      expect(
        timelineSectionForLayerKind(LayerKind.animation),
        TimelineSection.drawing,
      );
      expect(
        timelineSectionForLayerKind(LayerKind.storyboard),
        TimelineSection.drawing,
      );
      expect(timelineSectionForLayerKind(LayerKind.se), TimelineSection.se);
      expect(
        timelineSectionForLayerKind(LayerKind.camera),
        TimelineSection.camera,
      );
    });

    // ㉑ (user, 2026-08-12): 「스토리보드에서만 트랜지션 섹션이 `CI`처럼
    // 잘려 보인다」. The band there is ONE 30px row, and the tag is set at
    // 9pt/1.15 = 10.35px per glyph cell — so three cells need 31px and the
    // renderer's ellipsis rule replaced the tail with a rotated `…`.
    group('a band too short for its tag wears the tag initial', () {
      // The numbers the band actually paints with, so a type change that
      // breaks the fit shows up here rather than on the user's screen.
      const cell = SectionBandZone.fontSize * SectionBandZone.lineHeight;

      test('the whole word stays while it fits', () {
        // The timeline's camera run is two rows or more.
        expect(
          sectionBandLabelWithin('CAM', extent: 43, cellExtent: cell),
          'CAM',
        );
        // Exactly three cells is a fit, not an overflow.
        expect(
          sectionBandLabelWithin('CAM', extent: 3 * cell, cellExtent: cell),
          'CAM',
        );
        expect(
          sectionBandLabelWithin('ACTION', extent: 6 * cell, cellExtent: cell),
          'ACTION',
        );
      });

      test('one storyboard row shows C, and never C plus an ellipsis', () {
        // 30px row less the band's bottom hairline.
        final shown = sectionBandLabelWithin(
          'CAM',
          extent: 29,
          cellExtent: cell,
        );
        expect(shown, 'C');
        expect(shown, isNot(contains('…')));
      });

      test('SE fits the same row, so it is NOT abbreviated', () {
        // The control: the rule is about the space, not about the panel.
        // Two cells need 20.7px and the row has 29.
        expect(sectionBandLabelWithin('SE', extent: 29, cellExtent: cell), 'SE');
      });

      test('an unbounded or empty band changes nothing', () {
        expect(
          sectionBandLabelWithin(
            'CAM',
            extent: double.infinity,
            cellExtent: cell,
          ),
          'CAM',
        );
        expect(sectionBandLabelWithin('', extent: 29, cellExtent: cell), '');
        expect(
          sectionBandLabelWithin('CAM', extent: 29, cellExtent: 0),
          'CAM',
        );
      });

      test('a band with no room for even one cell still names itself', () {
        // Zero capacity is where the renderer draws NOTHING at all; an
        // initial under a clip is the better failure.
        expect(sectionBandLabelWithin('CAM', extent: 4, cellExtent: cell), 'C');
      });
    });

    test('sectioned order pins camera last, keeping in-section order', () {
      // Defensive: camera sits mid-list here even though the model normally
      // keeps it last.
      final layers = [
        _layer('a', LayerKind.animation),
        _layer('cam', LayerKind.camera),
        _layer('b', LayerKind.animation),
        _layer('sb', LayerKind.storyboard),
      ];

      final ordered = sectionedLayerOrder(layers);

      expect(ordered.map((layer) => layer.id.value), ['a', 'b', 'sb', 'cam']);
    });

    test('SE layers sort between the drawing cels and the camera', () {
      final layers = [
        _layer('se1', LayerKind.se),
        _layer('a', LayerKind.animation),
        _layer('cam', LayerKind.camera),
        _layer('se2', LayerKind.se),
        _layer('b', LayerKind.animation),
      ];

      final ordered = sectionedLayerOrder(layers);

      expect(ordered.map((layer) => layer.id.value), [
        'a',
        'b',
        'se1',
        'se2',
        'cam',
      ]);
      // Dividers open at the drawing→SE and SE→camera boundaries.
      expect(timelineSectionStartsAt(ordered, 2), isTrue);
      expect(timelineSectionStartsAt(ordered, 3), isFalse);
      expect(timelineSectionStartsAt(ordered, 4), isTrue);
    });

    test('horizontal display order reverses sections (camera on top)', () {
      final layers = [
        _layer('a', LayerKind.animation),
        _layer('b', LayerKind.animation),
        _layer('cam', LayerKind.camera),
      ];

      expect(
        horizontalLayerDisplayOrder(layers).map((layer) => layer.id.value),
        ['cam', 'b', 'a'],
      );
      expect(xsheetLayerDisplayOrder(layers).map((layer) => layer.id.value), [
        'a',
        'b',
        'cam',
      ]);
    });

    test('section starts only at section boundaries in display order', () {
      final display = sectionedLayerOrder([
        _layer('a', LayerKind.animation),
        _layer('b', LayerKind.animation),
        _layer('cam', LayerKind.camera),
      ]);

      expect(timelineSectionStartsAt(display, 0), isFalse);
      expect(timelineSectionStartsAt(display, 1), isFalse);
      expect(timelineSectionStartsAt(display, 2), isTrue);
    });
  });

  group('timeline section visuals', () {
    Widget panel(TimelineOrientation orientation) {
      final layers = [
        _layer('a', LayerKind.animation),
        _layer('b', LayerKind.animation),
        _layer('cam', LayerKind.camera),
      ];
      return MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayerId: const LayerId('a'),
            frameCursor: ValueNotifier<int>(0),
            playbackFrameCount: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: orientation,
            onOrientationChanged: (_) {},
          ),
        ),
      );
    }

    testWidgets('horizontal: camera row sits on top; no extra divider '
        'furniture (single shared hairline, R3 #6)', (tester) async {
      await tester.pumpWidget(panel(TimelineOrientation.horizontal));

      final cameraTop = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('timeline-layer-row-cam')),
          )
          .dy;
      final drawingTop = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('timeline-layer-row-b')),
          )
          .dy;
      expect(cameraTop, lessThan(drawingTop));

      // Section boundaries carry NO extra overlay — one hairline like every
      // row boundary; the gutter bracket is the section marker.
      expect(
        find.byKey(const ValueKey<String>('timeline-section-divider-rail-b')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-section-divider-row-b')),
        findsNothing,
      );
    });

    testWidgets('horizontal: one section ZONE per run inside the rows '
        '(UI-R7 #2 — the old gutter bracket, in the leading slot)', (
      tester,
    ) async {
      await tester.pumpWidget(panel(TimelineOrientation.horizontal));

      // Display order: cam (camera section) then b, a (one drawing run).
      expect(
        find.byKey(const ValueKey<String>('section-bracket-camera')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('section-bracket-drawing')),
        findsOneWidget,
      );
      // ONE zone spans the b+a run: its height covers both rows.
      final drawingZone = tester.getRect(
        find.byKey(const ValueKey<String>('section-bracket-drawing')),
      );
      final rowB = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-layer-row-b')),
      );
      final rowA = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-layer-row-a')),
      );
      expect(drawingZone.top, lessThanOrEqualTo(rowB.top + 1));
      expect(drawingZone.bottom, greaterThanOrEqualTo(rowA.bottom - 1));
      // The per-row inline tags are retired.
      expect(
        find.byKey(const ValueKey<String>('timeline-section-tag-b')),
        findsNothing,
      );
    });

    // A3 (2026-08-17): the gutter bracket anchors to its section's FULL
    // extent in content coordinates. It scrolls away with the content
    // (「그 결과 안 보여도 됨」) instead of chasing the viewport, and a
    // section scrolled out of view keeps its bracket mounted (reserve
    // space, swap content). The x-sheet and storyboard were already on
    // this law; feeding the overlay the full row list joins the timeline.
    group('A3: section brackets anchor to content, not the viewport', () {
      Widget tallPanel() {
        final layers = [
          for (var i = 0; i < 30; i += 1)
            _layer('cel-$i', LayerKind.animation),
          _layer('cam', LayerKind.camera),
        ];
        return MaterialApp(
          home: Scaffold(
            body: TimelinePanel(
              layers: layers,
              activeLayerId: const LayerId('cel-0'),
              frameCursor: ValueNotifier<int>(0),
              playbackFrameCount: 12,
              exposureStateForLayer: (_, _) =>
                  TimelineCellExposureState.uncovered,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
            ),
          ),
        );
      }

      ScrollPosition verticalPosition(WidgetTester tester) {
        return tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(
                      const ValueKey<String>(
                        'timeline-vertical-scroll-viewport',
                      ),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
      }

      testWidgets('a bracket spans its whole run even when most of the run '
          'is off screen', (tester) async {
        await tester.pumpWidget(tallPanel());

        // Display order puts the camera on top; 'cel-29' heads the drawing
        // run and is on screen while most of the run is windowed away.
        final rowHeight = tester
            .getRect(
              find.byKey(const ValueKey<String>('timeline-layer-row-cel-29')),
            )
            .height;
        final drawingZone = tester.getRect(
          find.byKey(const ValueKey<String>('section-bracket-drawing')),
        );
        expect(drawingZone.height, moreOrLessEquals(30 * rowHeight));
      });

      testWidgets('scrolling moves the bracket with the content — the label '
          'never re-centers on the viewport', (tester) async {
        await tester.pumpWidget(tallPanel());

        final before = tester
            .getRect(
              find.byKey(const ValueKey<String>('section-bracket-drawing')),
            )
            .top;
        final delta = 3 *
            tester
                .getRect(
                  find.byKey(
                    const ValueKey<String>('timeline-layer-row-cel-29'),
                  ),
                )
                .height;
        verticalPosition(tester).jumpTo(delta);
        await tester.pump();

        final after = tester
            .getRect(
              find.byKey(const ValueKey<String>('section-bracket-drawing')),
            )
            .top;
        expect(after, moreOrLessEquals(before - delta));
      });

      testWidgets('a section scrolled fully out of view keeps its bracket '
          'mounted', (tester) async {
        await tester.pumpWidget(tallPanel());

        final position = verticalPosition(tester);
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();

        // The camera run sits at the top of the display order; at the
        // bottom of the scroll it is far outside the row window.
        expect(
          find.byKey(const ValueKey<String>('section-bracket-camera')),
          findsOneWidget,
        );
      });
    });

    testWidgets('xsheet: camera column sits rightmost; no extra divider '
        'furniture', (tester) async {
      await tester.pumpWidget(panel(TimelineOrientation.vertical));

      final cameraLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('xsheet-layer-header-cam')),
          )
          .dx;
      final drawingLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('xsheet-layer-header-b')),
          )
          .dx;
      expect(cameraLeft, greaterThan(drawingLeft));

      expect(
        find.byKey(const ValueKey<String>('xsheet-section-divider-header-cam')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('xsheet-section-divider-column-cam')),
        findsNothing,
      );
    });
  });
}
