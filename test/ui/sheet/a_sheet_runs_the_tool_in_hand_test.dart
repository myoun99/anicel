import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/models/transform_track.dart';
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
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';
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

  /// Whether [window]'s cel holds ink at its own [pixel].
  bool celInkAt(WidgetTester tester, SheetWindow window, Offset pixel) {
    final surface = tester
        .widget<SheetInkLayer>(find.byType(SheetInkLayer))
        .sessionStateFor(window)
        .canvasState
        .currentSurface;
    return (surfacePixelRgba(surface, pixel.dx.floor(), pixel.dy.floor()) ??
            0) !=
        0;
  }

  /// Whether [window]'s cel holds ink under paper point [paper].
  bool inkUnder(WidgetTester tester, SheetInkWindow window, Offset paper) =>
      celInkAt(tester, window, window.placement.pixelOf(paper));

  /// A drag on the paper from [from] to [to].
  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset to, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
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
  }

  /// A drag across the middle half of [window], top left to bottom right.
  Future<({Offset from, Offset to, Offset middle})> dragAcross(
    WidgetTester tester,
    SheetWindow window, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final rect = window.documentRect;
    final from = rect.center - Offset(rect.width / 4, rect.height / 4);
    final to = rect.center + Offset(rect.width / 4, rect.height / 4);
    await drag(tester, from, to, kind: kind);
    return (from: from, to: to, middle: rect.center);
  }

  const conteCanvas = CanvasSize(width: 640, height: 360);

  /// Cut [id]'s conte row, lying on the canvas as [pose] puts it — as it
  /// is drawn, when null.
  Layer conteRow(String id, {TransformPose? pose}) => Layer(
    id: LayerId('sb-$id'),
    name: 'SB',
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('sb-$id-f'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('sb-$id-f'), length: 6)},
    transformTrack: pose == null ? null : TransformTrack(keyframes: {0: pose}),
  );

  Cut conteCut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 6,
    canvasSize: conteCanvas,
    layers: layers,
  );

  /// The conte of [cuts], [active] the cut it stands on, with [tool] in
  /// hand.
  Future<(EditorSessionManager, List<CanvasViewport>)> pumpConte(
    WidgetTester tester,
    ValueNotifier<BrushToolState> tool,
    List<Cut> cuts, {
    required String active,
  }) async {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-project'),
        name: 'Conte',
        createdAt: DateTime.utc(2026, 10, 20),
        tracks: [
          Track(id: const TrackId('first'), name: 'V1', cuts: cuts),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectCut(CutId(active));
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
        viewport: seedFromRender(tester, onConteBody(session, CanvasViewport())),
        onViewportChanged: onViewportChanged,
        inkController: ink,
        pictures: cels,
        brushToolState: tool,
        brushAllowed: true,
      ),
      [ink, cels],
    );
    return (session, views);
  }

  // F-80's law, a tool at a time: what a sheet has for a tool to act on is
  // a cel's pixels — the brush, the eraser and the shape tool reach them.
  const runs = {CanvasTool.brush, CanvasTool.eraser, CanvasTool.shape};

  test('a sheet runs the tools that act on a cel\'s pixels', () {
    for (final tool in CanvasTool.values) {
      expect(sheetRunsTool(tool), runs.contains(tool), reason: tool.name);
    }
  });

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
          pump: (tester, tool) => pumpConte(tester, tool, [
            conteCut('38', [conteRow('38')]),
          ], active: '38'),
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
          if (!runs.contains(tool)) tool,
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

  group('the conte', () {
    /// A cut drawn on its animation row alone: its band has no block to
    /// write in.
    Cut blockless(String id) => conteCut(id, [
      Layer(
        id: LayerId('anim-$id'),
        name: 'A',
        frames: [
          Frame(id: FrameId('anim-$id-f'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('anim-$id-f'), length: 6),
        },
      ),
    ]);

    /// With 「프레임 자동 생성」 off, so a band with no block takes no pen.
    void makingNoBlocks() {
      final input = AppInput.settings.value;
      AppInput.settings.value = input.copyWith(autoCreateFrameOnDraw: false);
      addTearDown(() => AppInput.settings.value = input);
    }

    /// A point of the window that refuses the pen, away from its picture,
    /// where it is the window on top.
    Offset onTheRefusingBand(WidgetTester tester) {
      final windows = sheetPhotoEntrance(tester).windows();
      final band = windows.firstWhere((window) => window.refusal != null);
      final at = Offset(
        band.documentRect.right - 30,
        band.documentRect.center.dy,
      );
      expect(sheetInkOwnerAt(windows, at), same(band), reason: 'premise');
      return at;
    }

    SheetPictureWindow pictureOf(WidgetTester tester, String cut) =>
        sheetPhotoEntrance(tester)
            .windows()
            .whereType<SheetPictureWindow>()
            .firstWhere((window) => window.key.cutId == CutId(cut));

    /// Paper point [paper] on the canvas [window]'s picture prints.
    Offset canvasOf(SheetPictureWindow window, Offset paper) =>
        MatrixUtils.transformPoint(
          Matrix4.inverted(window.picture.canvasToPaper),
          paper,
        );

    ValueNotifier<BrushToolState> thinShapes() {
      final tool = holding(CanvasTool.shape);
      tool.value = tool.value.copyWith(size: 4);
      return tool;
    }

    testWidgets('under the shape tool, a band that takes no pen says why — '
        'once, as it says it to the brush — and takes no shape', (
      tester,
    ) async {
      makingNoBlocks();
      final (session, _) = await pumpConte(tester, holding(CanvasTool.shape), [
        conteCut('38', [conteRow('38')]),
        blockless('39'),
      ], active: '38');
      final at = onTheRefusingBand(tester);
      final steps = session.historyManager.undoCount;
      final notices = cursorNotices.revision;

      await drag(tester, at, at + const Offset(-20, 10));

      expect(cursorNotices.revision, notices + 1);
      expect(
        cursorNotices.message,
        AppStrings.of(
          session.languageSettings.value.programLanguage,
        ).noticeNoConteLayer,
      );
      expect(session.historyManager.undoCount, steps);
      await tester.pump(CursorNoticeController.defaultDuration);
    });

    testWidgets('under a tool the sheet does not run, that band says '
        'nothing: the press moves the sheet', (tester) async {
      makingNoBlocks();
      final (_, views) = await pumpConte(tester, holding(CanvasTool.select), [
        conteCut('38', [conteRow('38')]),
        blockless('39'),
      ], active: '38');
      final at = onTheRefusingBand(tester);
      final notices = cursorNotices.revision;

      await drag(tester, at, at + const Offset(-20, 10));
      await tester.pumpAndSettle();

      expect(views, isNotEmpty, reason: 'the sheet moved');
      expect(cursorNotices.revision, notices);
    });

    testWidgets('🚨a shape on a picture of a row STRETCHED lands in the cel '
        'through the row\'s placement, as a stroke does — half as far '
        'across, twice as far down', (tester) async {
      // The row lies twice as wide and half as tall about the canvas's
      // middle, its anchor.
      await pumpConte(tester, thinShapes(), [
        conteCut('38', [
          conteRow(
            '38',
            pose: TransformPose(
              center: CanvasPoint(x: 320, y: 180),
              scaleX: 2,
              scaleY: 0.5,
            ),
          ),
        ]),
      ], active: '38');
      final picture = pictureOf(tester, '38');
      final from = picture.slot.center;
      final to = from + Offset(picture.slot.width / 10, picture.slot.height / 10);
      Offset celOf(Offset paper) {
        final canvas = canvasOf(picture, paper);
        return Offset(320 + (canvas.dx - 320) / 2, 180 + (canvas.dy - 180) * 2);
      }

      final start = celOf(from);
      final end = celOf(to);
      // Read as it is drawn, the box would end here.
      final unlaid = canvasOf(picture, to);

      await drag(tester, from, to);
      await tester.pumpAndSettle();

      expect(
        (
          rightEdge: celInkAt(
            tester,
            picture,
            Offset(end.dx, start.dy + (end.dy - start.dy) * 0.75),
          ),
          unlaidRightEdge: celInkAt(
            tester,
            picture,
            Offset(unlaid.dx, start.dy + (unlaid.dy - start.dy) * 0.5),
          ),
        ),
        (rightEdge: true, unlaidRightEdge: false),
      );
    });

    testWidgets('a shape still lands after the cuts trade places — the '
        'windows\' views mounted again under the new order', (tester) async {
      final (session, _) = await pumpConte(tester, thinShapes(), [
        conteCut('37', [conteRow('37')]),
        conteCut('38', [conteRow('38')]),
      ], active: '38');
      // The two trade places as a move drag's reorder commits it.
      final track = session.activeTrack;
      session.cutCommandCoordinator.commitCutMoveReorder(
        trackId: track.id,
        order: [track.cuts[1].id, track.cuts[0].id],
        beforeGaps: const {},
        afterGaps: const {},
      );
      session
        ..refreshAfterCutCommand()
        ..notifyChanged();
      await tester.pumpAndSettle();
      final picture = pictureOf(tester, '38');
      final from = picture.slot.center;
      final to = from + Offset(picture.slot.width / 5, picture.slot.height / 5);

      await drag(tester, from, to);
      await tester.pumpAndSettle();

      final start = canvasOf(picture, from);
      final end = canvasOf(picture, to);
      expect(
        (
          corner: celInkAt(tester, picture, Offset(end.dx, start.dy)),
          middle: celInkAt(tester, picture, (start + end) / 2),
        ),
        (corner: true, middle: false),
      );
    });
  });
}
