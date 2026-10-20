import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/brush/tool_cursor_sprite.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import '../../helpers/conte_book.dart';
import '../../helpers/device_viewport.dart';
import '../../helpers/sheet_photo_drops.dart';

/// 🚨F-420 — A SHEET RUNS THE TOOL IN HAND (유저 2026-10-20: 「캔버스
/// 베이스패널에서 브러시허용일때, 도형도구 선택되있는데 브러시가 그려짐.
/// 선택한 도구가 작동하게하도록.」).
///
/// The brush switch on, a sheet answers a press with the tool in hand —
/// F-80's law, a tool at a time: 「작동가능한거면 해당 도구 작동시키고,
/// 불가능하면 팬」 — on every sheet that takes the pen.
void main() {
  /// The panel, brush on, with [tool] in hand, on [session]'s own stores —
  /// and every view it reports from here on.
  Future<List<CanvasViewport>> pumpPanel(
    WidgetTester tester,
    EditorSessionManager session,
    Widget Function(ValueChanged<CanvasViewport> onViewportChanged) panel,
    List<Listenable> heard,
  ) async {
    final views = <CanvasViewport>[];
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, ...heard]),
            builder: (context, _) => panel(views.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Whatever the first layout framed is not a move.
    views.clear();
    return views;
  }

  ValueNotifier<BrushToolState> holding(CanvasTool tool) {
    final state = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.copyWith(tool: tool),
    );
    addTearDown(state.dispose);
    return state;
  }

  /// The biggest window of the sheet on screen that takes ink.
  SheetInkWindow aWindow(WidgetTester tester, String keyPrefix) {
    double area(SheetInkWindow window) =>
        window.documentRect.width * window.documentRect.height;
    return [
      for (final window
          in sheetPhotoEntrance(tester).windows().whereType<SheetInkWindow>())
        if (window.refusal == null &&
            find
                .byKey(ValueKey<String>('$keyPrefix-ink-${window.id}'))
                .evaluate()
                .isNotEmpty)
          window,
    ].reduce((a, b) => area(a) >= area(b) ? a : b);
  }

  /// Whether [window]'s cel holds ink under paper point [paper].
  bool inkUnder(WidgetTester tester, SheetInkWindow window, Offset paper) {
    final surface = tester
        .widget<SheetInkLayer>(find.byType(SheetInkLayer))
        .sessionStateFor(window)
        .canvasState
        .currentSurface;
    final pixel = window.placement.pixelOf(paper);
    return (surfacePixelRgba(surface, pixel.dx.floor(), pixel.dy.floor()) ??
            0) !=
        0;
  }

  /// A drag across the middle half of [window], top left to bottom right.
  Future<({Offset from, Offset to, Offset middle})> dragAcross(
    WidgetTester tester,
    SheetInkWindow window, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final rect = window.documentRect;
    final from = rect.center - Offset(rect.width / 4, rect.height / 4);
    final to = rect.center + Offset(rect.width / 4, rect.height / 4);
    final gesture = await tester.startGesture(
      sheetPaperOnScreen(tester, from),
      kind: kind,
    );
    await tester.pump();
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(
        sheetPaperOnScreen(tester, Offset.lerp(from, to, step / 6)!),
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    return (from: from, to: to, middle: rect.center);
  }

  final sheets =
      <
        ({
          String name,
          String keyPrefix,
          Future<(EditorSessionManager, List<CanvasViewport>)> Function(
            WidgetTester tester,
            ValueNotifier<BrushToolState> tool,
          )
          pump,
        })
      >[
        (
          name: 'the timesheet',
          keyPrefix: 'timesheet',
          pump: (tester, tool) async {
            final session = EditorSessionManager(
              initialProject: createDefaultProject(),
            );
            addTearDown(session.dispose);
            final ink = TimesheetInkController(
              store: session.renderCaches.timesheetInkStore,
            );
            addTearDown(ink.dispose);
            final views = await pumpPanel(
              tester,
              session,
              (onViewportChanged) => TimesheetTabHost(
                session: session,
                viewport: CanvasViewport(),
                onViewportChanged: onViewportChanged,
                inkController: ink,
                brushToolState: tool,
                brushAllowed: true,
                onBrushAllowedChanged: (_) {},
              ),
              [ink],
            );
            return (session, views);
          },
        ),
        (
          name: 'the conte',
          keyPrefix: 'conte',
          pump: (tester, tool) async {
            const cut = CutId('38');
            final session = EditorSessionManager(
              initialProject: Project(
                id: const ProjectId('conte-project'),
                name: 'Conte',
                createdAt: DateTime.utc(2026, 10, 20),
                tracks: [
                  Track(
                    id: const TrackId('first'),
                    name: 'V1',
                    cuts: [
                      Cut(
                        id: cut,
                        name: '38',
                        duration: 6,
                        canvasSize: const CanvasSize(width: 640, height: 360),
                        layers: [
                          Layer(
                            id: const LayerId('sb-38'),
                            name: 'SB',
                            kind: LayerKind.storyboard,
                            frames: [
                              Frame(
                                id: const FrameId('f'),
                                duration: 1,
                                strokes: const [],
                              ),
                            ],
                            timeline: const {
                              0: TimelineExposure.drawing(
                                FrameId('f'),
                                length: 6,
                              ),
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
            addTearDown(session.dispose);
            session.selectCut(cut);
            final ink = ConteInkController(
              rowStore: session.renderCaches.conteInkRowStore,
            );
            addTearDown(ink.dispose);
            final cels = ContePictureInkController(
              cels: session.renderCaches.brushFrameStore,
            );
            addTearDown(cels.dispose);
            final views = await pumpPanel(
              tester,
              session,
              (onViewportChanged) => ConteTabHost(
                session: session,
                thumbnails: null,
                viewport: seedFromRender(
                  tester,
                  onConteBody(session, CanvasViewport()),
                ),
                onViewportChanged: onViewportChanged,
                inkController: ink,
                pictures: cels,
                brushToolState: tool,
                brushAllowed: true,
              ),
              [ink, cels],
            );
            return (session, views);
          },
        ),
        (
          name: 'the 봉투',
          keyPrefix: 'envelope',
          pump: (tester, tool) async {
            final session = EditorSessionManager(
              initialProject: createDefaultProject(),
            );
            addTearDown(session.dispose);
            final ink = CutEnvelopeInkController(
              store: session.renderCaches.envelopeInkStore,
            );
            addTearDown(ink.dispose);
            final views = await pumpPanel(
              tester,
              session,
              (onViewportChanged) => CutEnvelopeTabHost(
                session: session,
                onViewportChanged: onViewportChanged,
                inkController: ink,
                brushToolState: tool,
                brushAllowed: true,
              ),
              [ink],
            );
            return (session, views);
          },
        ),
      ];

  for (final sheet in sheets) {
    group(sheet.name, () {
      testWidgets('🎯a drag of the shape tool draws its box, not the '
          'brush\'s line along the drag — ONE undo', (tester) async {
        final (session, _) = await sheet.pump(
          tester,
          holding(CanvasTool.shape),
        );
        final window = aWindow(tester, sheet.keyPrefix);
        final steps = session.historyManager.undoCount;

        final drag = await dragAcross(tester, window);

        expect(
          (
            corner: inkUnder(tester, window, Offset(drag.from.dx, drag.to.dy)),
            middle: inkUnder(tester, window, drag.middle),
          ),
          (corner: true, middle: false),
          reason:
              'the box\'s corner, which the drag never passed, is drawn — '
              'and the middle, which the brush\'s line along the drag would '
              'cross, is not',
        );
        expect(session.historyManager.undoCount, steps + 1);
        session.undo();
        await tester.pump();
        expect(
          inkUnder(tester, window, Offset(drag.from.dx, drag.to.dy)),
          isFalse,
        );
      });

      testWidgets('the brush wears its own tip — and a tool the sheet does '
          'not run wears none', (tester) async {
        final tool = holding(CanvasTool.brush);
        tool.value = tool.value.copyWith(size: 80);
        await sheet.pump(tester, tool);
        final tip = find.byKey(const ValueKey<String>('brush-cursor-overlay'));
        Size extent() => tester.widget<ToolCursorSprite>(tip).look.extent;
        final big = extent();

        tool.value = tool.value.copyWith(size: 8);
        await tester.pump();
        expect(
          extent().width,
          lessThan(big.width),
          reason: 'the brush in hand, not the brush\'s defaults',
        );

        tool.value = tool.value.copyWith(tool: CanvasTool.select);
        await tester.pump();
        expect(tip, findsNothing, reason: 'a press here moves the sheet');
      });

      for (final tool in [
        for (final tool in CanvasTool.values)
          if (!sheetRunsTool(tool)) tool,
      ]) {
        for (final kind in const [
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
        ]) {
          testWidgets('a ${kind.name} drag of the ${tool.name} tool, which '
              'has nothing on a sheet to act on, moves the sheet and lays '
              'nothing', (tester) async {
            final (_, views) = await sheet.pump(tester, holding(tool));
            final window = aWindow(tester, sheet.keyPrefix);

            final drag = await dragAcross(tester, window, kind: kind);
            await tester.pumpAndSettle();

            expect(views, isNotEmpty, reason: 'the sheet moved');
            expect(inkUnder(tester, window, drag.from), isFalse);
            expect(inkUnder(tester, window, drag.middle), isFalse);
          });
        }
      }
    });
  }
}
