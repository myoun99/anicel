import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';

import '../../helpers/home_page_probes.dart';

/// 🚨★★★**THE FRAME AXIS KEEPS ITS PLACE THROUGH A FOLD.**
///
/// 🗣️유저 2026-09-16 (F-143): 「간편 오버레이가 타임라인의 스크롤을 그대로
/// 안받음. 꽤 오른쪽으로 스크롤한채로 접으면 간편오버레이는 첫 인덱스쪽을
/// 보여주고있어서. 뭐지?싶어서 타임라인 열면 스크롤바가 왼쪽으로
/// 초기화되있는상태.」
///
/// ⛔TWO SYMPTOMS, ONE ROOT. Where the frame axis is scrolled to lived
/// INSIDE the grid, so it died with the grid when the panel folded: the
/// overlay had nothing to read (it drew from frame 0) and the grid that
/// came back started at 0. The rail's width already lived above both — the
/// overlay reads 「the same stored window the panel's own rail lays out
/// against」 — and the frame axis joins it there.
void main() {
  /// A cut long enough to scroll well to the right. ⚠️The default cut at
  /// this size scrolls 57px in all — the premise below caught it, and a
  /// "scroll" that short measures a fold that barely moved anything.
  Project longCut() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [track.cuts.first.copyWith(duration: 480)],
        ),
      ],
    );
  }

  Future<void> openTimeline(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: longCut())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
  }

  final frameScroller = find.byKey(
    const ValueKey<String>('timeline-frame-scroll-viewport'),
  );

  ScrollController controllerOf(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(frameScroller).controller!;

  Future<void> toggleFold(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the frame axis well to the right, the way 유저 did before
  /// folding, and says where it landed.
  Future<double> scrollRight(WidgetTester tester) async {
    final controller = controllerOf(tester);
    final target = (controller.position.maxScrollExtent * 0.6).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
    await tester.pumpAndSettle();
    expect(
      controller.offset,
      greaterThan(100),
      reason: '⛔전제: the frame axis really is scrolled well to the right',
    );
    return controller.offset;
  }

  testWidgets('🚨fold and unfold: the timeline comes back where it was', (
    tester,
  ) async {
    await openTimeline(tester);
    final before = await scrollRight(tester);

    await toggleFold(tester);
    expect(
      find.byType(CollapsedRowOverlay),
      findsOneWidget,
      reason: '⛔전제: the panel really folded',
    );
    await toggleFold(tester);

    expect(
      controllerOf(tester).offset,
      closeTo(before, 1),
      reason: '🚨유저: 「타임라인 열면 스크롤바가 왼쪽으로 초기화되있는상태」',
    );
  });

  testWidgets('🚨folded, the overlay starts where the timeline stood', (
    tester,
  ) async {
    await openTimeline(tester);
    final before = await scrollRight(tester);

    await toggleFold(tester);

    // The overlay's row lays its cells off the geometry the overlay
    // publishes — the same handle type the open grid's rows read.
    final rows = find.descendant(
      of: find.byType(CollapsedRowOverlay),
      matching: find.byType(TimelineFrameCellsRow),
    );
    expect(rows, findsWidgets, reason: '⛔전제: the overlay has a frame row');
    final geometry = tester
        .widget<TimelineFrameCellsRow>(rows.first)
        .geometry
        .value;

    expect(
      geometry.frameStartIndex * geometry.frameCellExtent +
          geometry.leadingFrameSpacerWidth,
      closeTo(before, geometry.frameCellExtent),
      reason: '🚨유저: 「접으면 간편오버레이는 첫 인덱스쪽을 보여주고있어서」',
    );
  });

  testWidgets('🚨the SHEET keeps its place through a fold too', (tester) async {
    // ⛔THE WHOLE FAMILY, not the reported half. The x-sheet's frame axis
    // lived in its grid exactly as the timeline's did, and a fold remounts
    // it the same way — 유저 reported the timeline, and the sheet is the
    // same grid transposed.
    await openTimeline(tester);
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );
    final sheetScroller = find.byKey(
      const ValueKey<String>('xsheet-frame-vertical-viewport'),
    );
    ScrollController sheetController() =>
        tester.widget<SingleChildScrollView>(sheetScroller).controller!;
    final controller = sheetController();
    controller.jumpTo(controller.position.maxScrollExtent * 0.6);
    await tester.pumpAndSettle();
    final before = sheetController().offset;
    expect(
      before,
      greaterThan(100),
      reason: '⛔전제: the sheet really is scrolled well down',
    );

    await toggleFold(tester);
    await toggleFold(tester);

    expect(
      sheetController().offset,
      closeTo(before, 1),
      reason: 'x시트도 접었다 펴면 제자리',
    );
  });

  // ── the STORYBOARD: the third frame panel that folds ──────────────────
  //
  // ⛔Same follower, same panel-local offset, same controller born at 0 —
  // the storyboard is not a different mechanism, only a different panel.

  final storyboardScroller = find.byKey(
    const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
  );

  ScrollController storyboardController(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(storyboardScroller).controller!;

  Future<double> openStoryboardScrolledRight(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: longCut())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final controller = storyboardController(tester);
    controller.jumpTo(controller.position.maxScrollExtent * 0.6);
    await tester.pumpAndSettle();
    final at = storyboardController(tester).offset;
    expect(
      at,
      greaterThan(100),
      reason: '⛔전제: the storyboard really is scrolled well to the right',
    );
    return at;
  }

  testWidgets('🚨the STORYBOARD keeps its place through a fold', (
    tester,
  ) async {
    final before = await openStoryboardScrolledRight(tester);

    await toggleFold(tester);
    await toggleFold(tester);

    expect(
      storyboardController(tester).offset,
      closeTo(before, 1),
      reason: '스토리보드도 접었다 펴면 제자리',
    );
  });

  testWidgets('🚨folded, the storyboard\'s track row starts where it stood', (
    tester,
  ) async {
    final before = await openStoryboardScrolledRight(tester);

    await toggleFold(tester);

    // The folded TRACK row draws its cuts through the painter the panel's
    // own track row uses, handed the overlay's frame geometry.
    final overlay = find.byType(CollapsedRowOverlay);
    expect(overlay, findsOneWidget, reason: '⛔전제: the storyboard folded');
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: overlay,
        matching: find.byKey(
          const ValueKey<String>('collapsed-storyboard-cut-blocks'),
        ),
      ),
    );
    final painter = paint.painter! as StoryboardCutBlocksPainter;
    final geometry = painter.geometry.value;

    // ⛔NOT the offset handed over — the BLOCK AS DRAWN. The one cut spans
    // frames 0..480 and the axis stands far past its start, so the block
    // begins LEFT of the folded row's edge. A painter that placed frames
    // from 0 instead of from the geometry's first frame drew it starting at
    // the edge — the row would have read 「첫 인덱스쪽」 all over again.
    final block = painter.blocks().single;
    final firstShown = geometry.frameStartIndex * geometry.frameCellExtent;
    expect(
      firstShown,
      closeTo(before, geometry.frameCellExtent),
      reason: '⛔전제: the folded row\'s window starts where the panel stood',
    );
    expect(
      block.rect.left,
      lessThan(-firstShown / 2),
      reason: '접힌 스토리보드 행도 펼쳐져 있던 자리부터 — the block started '
          '${firstShown.round()}px before the window, so it is drawn from '
          'there, not from the edge',
    );
  });

  // ── the fallback STRIP: the folded row with no row widget to mount ─────

  testWidgets('🚨the fallback strip stands where the axis stands too', (
    tester,
  ) async {
    // ⛔A folded PROPERTY LANE (or a film with no track) has no row widget,
    // and the overlay paints it itself. Same origin as everything else in
    // the frame half, or the lane would be the one row still reading from
    // frame 0.
    const cell = 24.0;
    const current = 105;
    final offset = ValueNotifier<double>(100 * cell);
    addTearDown(offset.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: CollapsedRowOverlay.defaultHeight,
              child: CollapsedRowOverlay(
                snapshot: const FlipHudSnapshot(
                  rows: [
                    FlipHudRow(name: 'a', kind: LayerKind.animation, runs: []),
                  ],
                  rowIndex: 0,
                  frameIndex: current,
                  frameCount: 480,
                ),
                rail: null,
                naturalRailWidth: 100,
                pixelsPerFrame: cell,
                framesPerSecond: 24,
                frameAxisOffset: offset,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byKey(const ValueKey<String>('collapsed-strip'));
    expect(strip, findsOneWidget, reason: '⛔전제: the strip is what painted');
    final painter = tester.widget<CustomPaint>(strip).painter!;
    final size = tester.getSize(strip);
    final primary = Theme.of(tester.element(strip)).colorScheme.primary;

    // Painted on its own, straight to an image: no 70% glass over it, so
    // the playhead is the theme's primary exactly.
    late ByteData pixels;
    late int width;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final image = await recorder.endRecording().toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      width = image.width;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    final y = size.height ~/ 2;
    final playhead = [
      for (var x = 0; x < width; x++)
        if (Color.fromARGB(
              pixels.getUint8((y * width + x) * 4 + 3),
              pixels.getUint8((y * width + x) * 4),
              pixels.getUint8((y * width + x) * 4 + 1),
              pixels.getUint8((y * width + x) * 4 + 2),
            ) ==
            primary.withValues(alpha: 1))
          x,
    ];

    expect(
      playhead,
      isNotEmpty,
      reason: '🚨the playhead (frame $current) sits inside the window that '
          'starts at frame 100 — a strip drawn from frame 0 put it at '
          '${(current * cell).round()}px, off the strip altogether',
    );
    expect(
      playhead.first,
      closeTo((current - 100) * cell, 1),
      reason: 'and it sits five cells in, where frame $current is',
    );
  });
}
