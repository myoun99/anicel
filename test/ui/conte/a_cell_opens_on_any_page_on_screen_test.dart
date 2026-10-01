import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/page_stack.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/device_viewport.dart';

/// 🗣️F-214 (유저 2026-09-28): 「콘티 프리뷰패널, 텍스트 편집하려고 하는게
/// 85%밑 줌에서는 클릭해도 편집ui가 안열림? 그 이상에서만 클릭시 열리는데
/// 언제든 열리도록 통일」 · 「열리다가 안열리다가 하고 … 해당 칸 내에서
/// 펜업하면 창 열리게하고, 아니면 그냥 드래그 작동하도록. 픽쳐칸도
/// 똑같음.」
///
/// A cell's press is the cell's on every page the view shows. Zoomed out,
/// the view meets two pages at once (F-201) — and a press on the page
/// above has to reach it past the page laid after it.
void main() {
  /// Eight one-cell cuts: five rows a page, so two body pages after the
  /// cover and its blank back.
  Project project() => Project(
    id: const ProjectId('book'),
    name: 'Book',
    createdAt: DateTime.utc(2026, 9, 29),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          for (var index = 1; index <= 8; index += 1)
            Cut(
              id: CutId('$index'),
              name: '$index',
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(
                  id: LayerId('$index-sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(
                      id: FrameId('$index-0'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: TimelineExposure.drawing(
                      FrameId('$index-0'),
                      length: 12,
                      memo: ExposureMemo(inkId: 'ink-$index'),
                    ),
                  },
                ),
              ],
            ),
        ],
      ),
    ],
  );

  /// The panel with its brush off, through a view whose middle is the gap
  /// between the two body pages — the end of the first above it, the start
  /// of the second below.
  Future<
    (
      EditorSessionManager,
      List<ContePageLayout>,
      ValueNotifier<CanvasViewport?>,
    )
  >
  pump(WidgetTester tester) async {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    final pages = layoutConteBook(
      buildConteSheetSource(session.repository.requireProject()),
      metrics: ConteSheetMetrics(
        cameraAspect: session.camera.cameraFrameAspect,
      ),
    );
    final stack = PageStack([
      for (final page in pages)
        Size(page.metrics.pageWidth, page.metrics.pageHeight),
    ]);
    final seam = stack.pageRect(2).bottom + stack.gap / 2;
    final view = ValueNotifier<CanvasViewport?>(
      seedFromRender(
        tester,
        CanvasViewport(
          panX: -stack.margin,
          panY: (450 - seam).roundToDouble(),
        ),
      ),
    );
    addTearDown(view.dispose);
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, view]),
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewportController: view,
              inkController: ink,
              brushToolState: tool,
              brushAllowed: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('conte-page-2')),
      findsOneWidget,
      reason: 'fixture: the first body page is on screen',
    );
    expect(
      find.byKey(const ValueKey<String>('conte-page-3')),
      findsOneWidget,
      reason: 'fixture: and the second',
    );
    return (session, pages, view);
  }

  /// [paper] on page [pageIndex], where the screen shows it.
  Offset onScreen(WidgetTester tester, int pageIndex, Offset paper) {
    final page = find.byKey(ValueKey<String>('conte-page-$pageIndex'));
    final view = tester.widget<ConteBookPage>(page).viewport;
    final at = view.canvasToViewport(CanvasPoint(x: paper.dx, y: paper.dy));
    return tester.getTopLeft(page) + Offset(at.x, at.y);
  }

  // The last cell of the page above the gap, and the first below it.
  for (final (where, pageIndex, last) in [
    ('the page above', 2, true),
    ('the page below', 3, false),
  ]) {
    ContePlacedCell cellOf(List<ContePageLayout> pages) =>
        last ? pages[pageIndex].cells.last : pages[pageIndex].cells.first;

    testWidgets('$where: a press let go on a cell\'s ACTION opens its '
        'words', (tester) async {
      final (_, pages, _) = await pump(tester);
      final cell = cellOf(pages);
      final zone = find.byKey(
        ValueKey<String>('conte-action-edit-${cell.cutId}-${cell.cellIndex}'),
      );
      expect(zone, findsOneWidget, reason: 'fixture: the cell offers them');
      final at = tester.getCenter(zone);
      expect(
        const Rect.fromLTWH(0, 0, 900, 900).contains(at),
        isTrue,
        reason: 'fixture: the press lands on the screen',
      );

      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('conte-action-field')),
        findsOneWidget,
      );
    });

    testWidgets('$where: a press let go on a cell\'s picture selects its '
        'cut', (tester) async {
      final (session, pages, _) = await pump(tester);
      final cell = cellOf(pages);
      expect(
        session.activeCutOrNull?.id,
        isNot(CutId(cell.cutId)),
        reason: 'fixture: another cut is the active one',
      );
      final at = onScreen(tester, pageIndex, cell.pictureRect.center);

      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(session.activeCutOrNull?.id, CutId(cell.cutId));
    });

    testWidgets('$where: a pen that leaves a cell\'s ACTION moves the view, '
        'and the words stay shut', (tester) async {
      final (_, pages, view) = await pump(tester);
      final cell = cellOf(pages);
      final before = view.value;
      final zone = find.byKey(
        ValueKey<String>('conte-action-edit-${cell.cutId}-${cell.cellIndex}'),
      );
      final box = tester.getRect(zone);

      // Down, 20 a step, until well past the zone's bottom edge — along the
      // book, where the view is free to go (it stops at the paper's end).
      await _drag(tester, box.center, const Offset(0, 20), box.height / 40 + 4);

      expect(
        find.byKey(const ValueKey<String>('conte-action-field')),
        findsNothing,
      );
      expect(view.value!.panY, greaterThan(before!.panY));
      expect(view.value!.panX, before.panX);
    });

    testWidgets('$where: a pen that leaves a cell\'s picture moves the view, '
        'and its cut is not selected', (tester) async {
      final (session, pages, view) = await pump(tester);
      final cell = cellOf(pages);
      final active = session.activeCutOrNull?.id;
      expect(active, isNot(CutId(cell.cutId)), reason: 'fixture');
      final before = view.value;
      final picture = Rect.fromPoints(
        onScreen(tester, pageIndex, cell.pictureRect.topLeft),
        onScreen(tester, pageIndex, cell.pictureRect.bottomRight),
      );

      // Up, 20 a step, until well past the picture's top edge.
      await _drag(
        tester,
        picture.center,
        const Offset(0, -20),
        picture.height / 40 + 4,
      );

      expect(session.activeCutOrNull?.id, active);
      expect(view.value!.panY, lessThan(before!.panY));
      expect(view.value!.panX, before.panX);
    });
  }
}

/// A pen pressed at [from] and moved [step] at a time, [steps] times (at
/// least), then lifted.
Future<void> _drag(
  WidgetTester tester,
  Offset from,
  Offset step,
  double steps,
) async {
  final pen = await tester.startGesture(from, kind: PointerDeviceKind.stylus);
  await tester.pump();
  for (var i = 0; i < steps; i += 1) {
    await pen.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await pen.up();
  await tester.pumpAndSettle();
}
