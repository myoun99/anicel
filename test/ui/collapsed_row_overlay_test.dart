import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show TimelineGridLaw, TimelineOutsideCutWashPainter;
import 'package:anicel/src/ui/timeline/timeline_body_cut_end_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_body_norishiro_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cursor_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

/// ⑩ 뿌리 C — the collapsed row draws NOTHING of its own.
///
/// Half of it already mounted the real rail row; the frame half was a
/// private painter, and every symptom reported against the overlay was that
/// copy falling behind the original — blocks that did not move, names that
/// never appeared, SE rows shaped differently, an index that did not
/// update. There was no test on it at all, which is how a second drawing of
/// the same row stayed wrong quietly.
///
/// So these tests do not check pixels. They check WHICH WIDGET is doing the
/// drawing, because that is the property that keeps being true when the row
/// grows a column.
void main() {
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  Future<void> collapseBottom(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
  }

  Finder inOverlay(Finder matching) => find.descendant(
    of: find.byType(CollapsedRowOverlay),
    matching: matching,
  );

  testWidgets('the frame half is the timeline\'s OWN row widget, not a '
      'second drawing of it', (tester) async {
    await pumpApp(tester);
    expect(find.byType(CollapsedRowOverlay), findsNothing);

    await collapseBottom(tester);

    expect(find.byType(CollapsedRowOverlay), findsOneWidget);
    expect(
      inOverlay(find.byType(TimelineFrameCellsRow)),
      findsOneWidget,
      reason: 'the cells are the shared row, so they cannot drift from it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail half is still the real rail row — both halves come '
      'from the same place now', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    expect(inOverlay(find.byType(TimelineLayerControlsRow)), findsOneWidget);
  });

  /// T16-ⓐ — mounting the real row brought the panel's GROUND with it.
  ///
  /// 유저 2026-08-13: 「원래 구상대로라면 프레임셀쪽은 바탕색은 싹 없애고
  /// 그리드선 띄우고 그 부분도 전체적으로 반투명하게 하기로 하지 않았나?」 —
  /// and it had been confirmed in 2026-08-10. Only the rail half knew how to
  /// take a ground off, so the fix for one half undid the look of the other.
  ///
  /// ⇒ I-44: the cells half has no ground to take off any more — no row
  /// paints one; the grid sheet under the rows does, and the folded row's
  /// law gives it none to paint. So the cells half is asked what it stands
  /// on, and the rail half, which still has a ground of its own, keeps its
  /// flag.
  testWidgets('BOTH halves stand on the artwork, not on a panel', (
    tester,
  ) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    final cells = tester.element(inOverlay(find.byType(TimelineFrameCellsRow)));
    final law = cells.findAncestorWidgetOfExactType<TimelineGridLaw>();
    expect(law, isNotNull, reason: 'the folded row states its own ground');
    expect(
      law!.ground,
      isNull,
      reason: 'a folded row lies ON the artwork — there is nothing to paint '
          'its rows on, and nothing to pre-blend its paper onto',
    );
    expect(
      tester
          .widget<TimelineLayerControlsRow>(
            inOverlay(find.byType(TimelineLayerControlsRow)),
          )
          .chromeless,
      isTrue,
    );
  });

  /// ⑨ — 「간편오버레이, **프레임셀쪽, 블록 뒤에 전체적으로 해당영역에 깔린
  /// 바탕색은 없애라니까?**」 (재지시).
  ///
  /// 🚨The flag was true the whole time and the ground was still there,
  /// because `chromeless` reached the PAINTER and stopped: the row's paper
  /// underlay was not painted per cell, it was two `ColoredBox`es laid
  /// row-wide under the whole strip (UI-R21 #2 moved them there so that
  /// switching the active layer re-rasterises nothing). I-44 took the pair
  /// off every row — the grid sheet paints the rows' grounds now — so this
  /// pins that nothing brought one back.
  ///
  /// Asking a flag is not enough — the test has to ask whether the ground is
  /// THERE. The two colours are named rather than sampled: a pixel test
  /// would pass on any theme whose surface happens to be near the artwork's
  /// colour.
  testWidgets('and no row-wide GROUND is painted, not just the empty cells', (
    tester,
  ) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    final scheme = buildAppTheme().colorScheme;
    final ground = {
      scheme.surface,
      timelineActiveRowWashColor(scheme),
    };
    final painted = tester
        .widgetList<ColoredBox>(inOverlay(find.byType(ColoredBox)))
        .where((box) => ground.contains(box.color))
        .toList();

    expect(
      painted,
      isEmpty,
      reason: 'a folded row lies ON the artwork: no surface base, and no '
          'active-row wash either — it is standing on the drawing, not on '
          'a panel that could be the active one',
    );
  });

  /// T16-ⓑ — 유저: 「레이어영역의 가로길이같은거 타임라인 그대로 가져와.
  /// 그래야 열의 규격이 맞을거니까」 · 「없는 버튼이 많고 폭 규격이 안 맞는다」.
  testWidgets('the rail half measures itself with the TIMELINE\'s numbers, '
      'and every column it gates on a callback is present', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    final rail = tester.widget<TimelineLayerControlsRow>(
      inOverlay(find.byType(TimelineLayerControlsRow)),
    );
    final cells = tester.widget<TimelineFrameCellsRow>(
      inOverlay(find.byType(TimelineFrameCellsRow)),
    );

    // ONE metrics object for the two halves: a row whose rail and cells
    // disagreed about a frame's width is a row with two opinions.
    expect(rail.metrics.frameCellWidth, cells.geometry.value.frameCellExtent);
    // The horizontal規格 the columns line up on comes from the panel.
    expect(
      rail.metrics.layerControlsWidth,
      TimelineGridMetrics.defaults.layerControlsWidth,
    );
    expect(
      rail.metrics.sectionLabelGutterWidth,
      TimelineGridMetrics.defaults.sectionLabelGutterWidth,
    );

    // 🚨A null callback is read as "this slot does not exist" by the row, so
    // leaving them out to mean "nothing is pressable here" DELETED buttons —
    // and shifted every column after them.
    expect(rail.onToggleLayerFx, isNotNull);
    expect(rail.onToggleLayerOnionSkin, isNotNull);
    expect(rail.onToggleLanes, isNotNull);
    expect(rail.onToggleLayerFillReference, isNotNull);
    expect(rail.onLayerBlendModeSelected, isNotNull);
  });

  testWidgets('WHERE YOU ARE is its own layer: the cursor rides a value '
      'channel so a frame tick repaints instead of rebuilding',
      (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);

    expect(
      inOverlay(find.byType(TimelineCursorLayer)),
      findsOneWidget,
      reason: 'the cells row is CURSOR-INDEPENDENT by design, so the '
          'playhead cannot live inside it — mounting the row without this '
          'would silently drop "where am I"',
    );
  });

  /// T16-ⓒ — 유저 2026-08-13: 「접기 전에 프레임 없는 곳에 인덱스 두고, 접고
  /// 나서 프레임으로 이동하면 1,2,3,4,n 같은 버튼이 비활성화인 채 그대로」.
  ///
  /// The bar survives a fold (only the grid goes offstage), so the buttons on
  /// it are still the app's answer to "what can I do here" while the panel is
  /// away — and they were answering about the frame the fold happened on.
  testWidgets('folded, the bar still follows the playhead', (tester) async {
    final session = await pumpApp(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    bool commaEnabled() =>
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey<String>('set-comma-1-button')),
            )
            .onPressed !=
        null;

    expect(commaEnabled(), isTrue);

    // Stand on empty paper, THEN fold — the order the user reported.
    session.selectFrameIndex(session.activeCutSpan.activeCutPlaybackFrameCount - 1);
    await tester.pumpAndSettle();
    expect(commaEnabled(), isFalse);

    await collapseBottom(tester);
    expect(find.byType(CollapsedRowOverlay), findsOneWidget);

    // Back onto the cel while folded.
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();

    expect(
      session.exposureVerbs.canSetCommaForSelectionOrCurrent,
      isTrue,
      reason: 'the state moved',
    );
    expect(
      commaEnabled(),
      isTrue,
      reason: 'and the buttons have to say so while the panel is folded — '
          'they are the only ones left saying anything',
    );
  });

  testWidgets('expanding puts it away again', (tester) async {
    await pumpApp(tester);
    await collapseBottom(tester);
    expect(find.byType(CollapsedRowOverlay), findsOneWidget);

    await collapseBottom(tester);

    expect(find.byType(CollapsedRowOverlay), findsNothing);
    expect(tester.takeException(), isNull);
  });

  /// The 08-10 design keeps ONE ground, the out-of-cut wash — and the
  /// folded row that mounts the real row (every folded timeline row since
  /// ⑩ 뿌리 C) had none: only the fallback strip painted it, from the cut end
  /// in a colour of its own.
  testWidgets('the REAL folded row says where the film stops, from the '
      'drawn end, over the row', (tester) async {
    final session = await pumpApp(tester);
    await collapseBottom(tester);
    expect(inOverlay(find.byType(TimelineFrameCellsRow)), findsOneWidget);

    final overlay = tester.widget<CollapsedRowOverlay>(
      find.byType(CollapsedRowOverlay),
    );
    expect(
      overlay.drawnFrameCount,
      session.activeCutSpan.activeCutDrawnFrameCount,
      reason: 'handed the open grid\'s own number — this project crosses no '
          'transition, so the offsets below alone could not tell the drawn '
          'end from the cut end',
    );
    final cell = overlay.pixelsPerFrame;
    final origin =
        (overlay.frameAxisOffset?.value ?? 0) ~/ cell * cell;
    final wash = inOverlay(
      find.byKey(const ValueKey<String>('collapsed-out-of-cut-wash')),
    );
    expect(wash, findsOneWidget);
    expect(
      (tester.widget<CustomPaint>(wash).painter!
              as TimelineOutsideCutWashPainter)
          .outsideStart,
      session.activeCutSpan.activeCutDrawnFrameCount * cell - origin,
      reason: 'the open grid\'s wash starts at the DRAWN end (유저 '
          '2026-08-11), and the folded row is the open row seen through glass',
    );
    expect(
      tester
          .widget<TimelineBodyCutEndBoundary>(
            inOverlay(
              find.byKey(const ValueKey<String>('collapsed-cut-end-boundary')),
            ),
          )
          .left,
      session.activeCutSpan.activeCutPlaybackFrameCount * cell - origin,
    );

    // Over the row, as the open stack lays it over everything.
    final stack = tester.widget<Stack>(
      find.ancestor(of: wash, matching: find.byType(Stack)).first,
    );
    final rowSlot = stack.children.indexWhere(
      (child) => find
          .descendant(
            of: find.byWidget(child),
            matching: find.byType(TimelineFrameCellsRow),
          )
          .evaluate()
          .isNotEmpty,
    );
    final washSlot = stack.children.indexWhere(
      (child) => find
          .descendant(of: find.byWidget(child), matching: wash)
          .evaluate()
          .isNotEmpty,
    );
    expect(rowSlot, greaterThanOrEqualTo(0));
    expect(washSlot, greaterThan(rowSlot));
  });

  group('where the film stops, on the overlay itself', () {
    FlipHudSnapshot snapshot({int? playbackFrameCount}) => FlipHudSnapshot(
      rows: const [
        FlipHudRow(
          name: 'A',
          kind: LayerKind.animation,
          runs: [FlipHudRun(startIndex: 0, length: 4, label: '1')],
        ),
      ],
      rowIndex: 0,
      frameIndex: 0,
      frameCount: 40,
      playbackFrameCount: playbackFrameCount,
    );

    Future<void> pumpOverlay(
      WidgetTester tester, {
      required FlipHudSnapshot snapshot,
      bool realRow = false,
    }) async {
      final axis = ValueNotifier<double>(55);
      addTearDown(axis.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              child: CollapsedRowOverlay(
                snapshot: snapshot,
                rail: null,
                naturalRailWidth: 100,
                pixelsPerFrame: 10,
                framesPerSecond: 24,
                frameAxisOffset: axis,
                drawnFrameCount: 13,
                frameRowBuilder: realRow
                    ? (context, geometry) => const SizedBox.expand()
                    : null,
              ),
            ),
          ),
        ),
      );
    }

    for (final realRow in [true, false]) {
      testWidgets('${realRow ? 'a mounted row' : 'the fallback strip'}: the '
          'wash from the drawn end, the のりしろ and the cut-end line, in '
          'the scrolled axis\'s frame', (tester) async {
        await pumpOverlay(
          tester,
          snapshot: snapshot(playbackFrameCount: 10),
          realRow: realRow,
        );

        // The axis stands at 55px: frame 5 is the first laid out, so every
        // offset is measured from 50.
        expect(
          (tester
                      .widget<CustomPaint>(
                        find.byKey(
                          const ValueKey<String>('collapsed-out-of-cut-wash'),
                        ),
                      )
                      .painter!
                  as TimelineOutsideCutWashPainter)
              .outsideStart,
          130 - 50,
        );
        final noriShiro = tester.widget<TimelineBodyNoriShiroBoundary>(
          find.byKey(const ValueKey<String>('collapsed-norishiro-boundary')),
        );
        expect(noriShiro.left, 130 - 50);
        expect(noriShiro.cutEnd, 100 - 50);
        expect(
          tester
              .widget<TimelineBodyCutEndBoundary>(
                find.byKey(
                  const ValueKey<String>('collapsed-cut-end-boundary'),
                ),
              )
              .left,
          100 - 50,
        );
      });
    }

    testWidgets('a snapshot with no cut end — the storyboard\'s track — has '
        'nowhere the film stops', (tester) async {
      await pumpOverlay(tester, snapshot: snapshot(), realRow: true);

      expect(
        find.byKey(const ValueKey<String>('collapsed-out-of-cut-wash')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('collapsed-cut-end-boundary')),
        findsNothing,
      );
    });
  });
}
