import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_picture_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import '../../helpers/conte_book.dart';
import '../../helpers/device_viewport.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/sheet_photo_drops.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// I-97-Q3 on every sheet that takes the pen: a photo dropped on the
/// timesheet's page, a conte block's band or a box of the 봉투, the brush
/// on, is taken by a press of the tool on it, and the same press drags it
/// — ONE step. One layer answers all three (`SheetInkLayer`); this holds
/// each panel to handing it the project's hand.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sheet_photo_take_');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A 40×20 picture in the pool.
  Future<String> poolPicture(WidgetTester tester) async => normalizedMediaPath(
    (await tester.runAsync(
      () => writeSolidPng(tempDir, 'photo.png', width: 40, height: 20),
    ))!,
  );

  MediaAsset asset(String png) =>
      MediaAsset(path: png, name: 'photo', kind: MediaAssetKind.image);

  /// The panel, brush on, as the workspace rebuilds it — on [session]'s
  /// own stores.
  Future<void> pumpPanel(
    WidgetTester tester,
    EditorSessionManager session,
    Widget Function() panel,
    List<Listenable> heard,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, ...heard]),
            builder: (context, _) => panel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ValueNotifier<BrushToolState> holding(CanvasTool held) {
    final tool = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.copyWith(tool: held),
    );
    addTearDown(tool.dispose);
    return tool;
  }

  /// [body] under the brush, and under the shape tool, whose layer lies
  /// over the sheet (F-420) — 「어느 도구든」.
  void underTheTools(
    String what,
    Future<void> Function(
      WidgetTester tester,
      ValueNotifier<BrushToolState> tool,
    )
    body,
  ) {
    for (final held in const [CanvasTool.brush, CanvasTool.shape]) {
      testWidgets(
        '$what — the ${held.name} tool',
        (tester) => body(tester, holding(held)),
      );
    }
  }

  /// The one photo on [session]'s sheets: its cel and where it stands.
  (BrushFrameKey, CanvasPoint) thePhoto(EditorSessionManager session) {
    final key = session.sheetPhotoEdits.pathsByCel.keys.single;
    final picture = [
      for (final store in session.renderCaches.sheetInkStores)
        ?store.bakedSurfaceOrNull(key),
    ].single;
    return (key, picture.photos.single.reference.pose.center);
  }

  /// Drops [png] at [at] and waits for it to land, then presses the tool
  /// there and drags.
  Future<void> dropThenDrag(
    WidgetTester tester,
    EditorSessionManager session,
    String png,
    Offset at,
  ) async {
    dropOnSheet(tester, png, at);
    await settleAsync(
      tester,
      () => session.sheetPhotoEdits.pathsByCel.isNotEmpty,
    );
    await tester.pump();
    final (key, stood) = thePhoto(session);
    final history = session.historyManager;
    final steps = history.undoCount;

    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(session.sheetPhotoHold.held, (key: key, id: 1));
    for (var step = 0; step < 3; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final (_, landed) = thePhoto(session);
    expect(landed.x, greaterThan(stood.x), reason: 'dragged by the press');
    expect(history.undoCount, steps + 1);
  }

  underTheTools('the timesheet: a press of the tool on a page\'s photo takes '
      'it and drags it', (tester, tool) async {
    final png = await poolPicture(tester);
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [asset(png)],
      ),
    );
    addTearDown(session.dispose);
    final ink = TimesheetInkController(
      store: session.renderCaches.timesheetInkStore,
    );
    addTearDown(ink.dispose);
    await pumpPanel(
      tester,
      session,
      () => TimesheetTabHost(
        session: session,
        viewport: CanvasViewport(),
        onViewportChanged: (_) {},
        inkController: ink,
        brushToolState: tool,
        brushAllowed: true,
        onBrushAllowedChanged: (_) {},
      ),
      [ink],
    );
    final page = sheetPhotoEntrance(tester)
        .windows()
        .whereType<SheetInkWindow>()
        .firstWhere((window) => window.id == 'page-0');

    await dropThenDrag(
      tester,
      session,
      png,
      sheetPaperOnScreen(tester, page.documentRect.center),
    );
  });

  underTheTools('the conte: a press of the tool on a block\'s photo takes it '
      'and drags it', (tester, tool) async {
    const cut = CutId('38');
    final png = await poolPicture(tester);
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-project'),
        name: 'Conte',
        createdAt: DateTime.utc(2026, 10, 16),
        mediaAssets: [asset(png)],
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
                      0: TimelineExposure.drawing(FrameId('f'), length: 6),
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
    await pumpPanel(
      tester,
      session,
      () => ConteTabHost(
        session: session,
        thumbnails: null,
        viewport: seedFromRender(
          tester,
          onConteBody(session, CanvasViewport()),
        ),
        inkController: ink,
        pictures: cels,
        brushToolState: tool,
        brushAllowed: true,
      ),
      [ink, cels],
    );
    final metrics = ConteSheetMetrics(
      cameraAspect: session.camera.cameraFrameAspect,
    );
    final cell = layoutConteSheet(
      buildConteSheetSource(session.repository.requireProject()),
      metrics: metrics,
    ).first.cells.firstWhere((cell) => cell.cutId == cut.value);
    // On the band, away from the cell's picture — the band's, no picture's.
    final band = conteBodyTopLeft(tester).translate(
      cell.rowBandRect(metrics).right - 30,
      cell.pictureRect.center.dy,
    );

    await dropThenDrag(tester, session, png, band);
  });

  underTheTools('the 봉투: a press of the tool on a box\'s photo takes it and '
      'drags it', (tester, tool) async {
    final png = await poolPicture(tester);
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [asset(png)],
      ),
    );
    addTearDown(session.dispose);
    final ink = CutEnvelopeInkController(
      store: session.renderCaches.envelopeInkStore,
    );
    addTearDown(ink.dispose);
    await pumpPanel(
      tester,
      session,
      () => CutEnvelopeTabHost(
        session: session,
        inkController: ink,
        brushToolState: tool,
        brushAllowed: true,
      ),
      [ink],
    );
    double area(SheetInkWindow box) =>
        box.documentRect.width * box.documentRect.height;
    final live = [
      for (final box
          in sheetPhotoEntrance(tester).windows().whereType<SheetInkWindow>())
        if (find
            .byKey(ValueKey<String>('envelope-ink-${box.id}'))
            .evaluate()
            .isNotEmpty)
          box,
    ]..sort((a, b) => area(b).compareTo(area(a)));

    await dropThenDrag(
      tester,
      session,
      png,
      sheetPaperOnScreen(tester, live.first.documentRect.center),
    );
  });
}
