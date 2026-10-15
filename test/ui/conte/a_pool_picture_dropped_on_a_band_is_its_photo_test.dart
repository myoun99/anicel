import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
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
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import '../../helpers/conte_book.dart';
import '../../helpers/device_viewport.dart';
import '../../helpers/sheet_photo_drops.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 I-97 (2026-10-15): a pool picture dropped on a conte cell's band
/// is a PHOTO in the handwriting a stroke started there writes (H49) —
/// its block's own, the block made as a stroke makes it (the cell with no
/// block, the next cut's row), in the photo's own undo step. A cell's
/// picture is its cut's cel, not the sheet's ink, and takes none.
void main() {
  const canvas = CanvasSize(width: 640, height: 360);
  const twins = CutId('38');
  const hollow = CutId('39');

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('conte_photo_');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  Project project(String png) => Project(
    id: const ProjectId('conte-project'),
    name: 'Conte',
    createdAt: DateTime.utc(2026, 10, 15),
    mediaAssets: [
      MediaAsset(path: png, name: 'photo', kind: MediaAssetKind.image),
    ],
    tracks: [
      Track(
        id: const TrackId('first'),
        name: 'V1',
        cuts: [
          // One cel exposed twice: two blocks of the same drawing.
          Cut(
            id: twins,
            name: '38',
            duration: 6,
            canvasSize: canvas,
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
                  0: TimelineExposure.drawing(FrameId('f'), length: 3),
                  3: TimelineExposure.drawing(FrameId('f'), length: 3),
                },
              ),
            ],
          ),
        ],
      ),
      Track(
        id: const TrackId('second'),
        name: 'V2',
        cuts: [
          // A cut whose conte row lost every block — the sheet's last, so
          // the next cut's row follows it.
          Cut(
            id: hollow,
            name: '39',
            duration: 10,
            canvasSize: canvas,
            layers: [
              Layer(
                id: const LayerId('sb-39'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
        ],
      ),
    ],
  );

  late EditorSessionManager session;
  late ConteInkController ink;
  late String png;
  late Offset paper;

  /// The panel, its brush [brush], with the canvas's 「프레임 자동 생성」 set
  /// to [autoCreates].
  Future<void> pumpPanel(
    WidgetTester tester, {
    required bool autoCreates,
    required bool brush,
  }) async {
    final input = AppInput.settings.value;
    AppInput.settings.value = input.copyWith(
      autoCreateFrameOnDraw: autoCreates,
    );
    addTearDown(() => AppInput.settings.value = input);
    png = normalizedMediaPath(
      (await tester.runAsync(
        () => writeSolidPng(tempDir, 'photo.png', width: 40, height: 10),
      ))!,
    );
    session = EditorSessionManager(initialProject: project(png));
    addTearDown(session.dispose);
    session.selectCut(twins);
    ink = ConteInkController();
    addTearDown(ink.dispose);
    final cels = ContePictureInkController(
      cels: session.renderCaches.brushFrameStore,
    );
    addTearDown(cels.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The panel goes first (tear-downs run last-added first): what it
    // listens to and draws into is let go after it.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, ink, cels]),
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewport: seedFromRender(
                tester,
                onConteBody(session, CanvasViewport()),
              ),
              inkController: ink,
              pictures: cels,
              brushToolState: tool,
              brushAllowed: brush,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    paper = conteBodyTopLeft(tester);
  }

  ConteSheetMetrics metrics() =>
      ConteSheetMetrics(cameraAspect: session.camera.cameraFrameAspect);

  List<ContePageLayout> pages() => layoutConteSheet(
    buildConteSheetSource(session.repository.requireProject()),
    metrics: metrics(),
  );

  ContePlacedCell cellOf(CutId cut, {int start = 0}) => pages().first.cells
      .firstWhere(
        (cell) => cell.cutId == cut.value && cell.source.startFrame == start,
      );

  /// A spot of [cell]'s band away from its picture — the band's, and no
  /// picture's.
  Offset bandOf(ContePlacedCell cell) => paper.translate(
    cell.rowBandRect(metrics()).right - 30,
    cell.pictureRect.center.dy,
  );

  /// The same spot on the row after the last cell — the next cut's (H44).
  Offset nextCutsBand() {
    final last = pages().last.cells.last;
    final row = last.rowOnPage + last.rowSpan;
    final top = metrics().rowTop(row);
    final bottom = metrics().rowTop(row + 1);
    return paper.translate(metrics().bodyRight - 30, (top + bottom) / 2);
  }

  String? inkIdOf(CutId cut, {int start = 0}) => storyboardLayerForCut(
    session.cutById(cut)!,
  )?.timeline[start]?.memo?.inkId;

  /// The photos the block at [start] of [cut] carries — under its own id,
  /// or the name the pen would write it under.
  List<CelPhoto> photosOf(CutId cut, {int start = 0}) => sheetPhotosOn(
    ink,
    conteInkRowKey(cut, switch (inkIdOf(cut, start: start)) {
      final inkId? when inkId.isNotEmpty => inkId,
      _ => session.storyboardCursor.conteInkIdFor(cut, start),
    }),
  );

  List<Cut> cutsOnTheSecond() => session.repository
      .requireProject()
      .tracks
      .singleWhere((track) => track.id == const TrackId('second'))
      .cuts;

  for (final brush in [true, false]) {
    testWidgets('the brush ${brush ? 'on' : 'off'}, a photo dropped on the '
        'band of a block not yet written on is that block\'s — it takes the '
        'block\'s id, its twin of the same cel none — and ONE undo takes '
        'both', (tester) async {
      await pumpPanel(tester, autoCreates: false, brush: brush);

      dropOnSheet(tester, png, bandOf(cellOf(twins)));
      await settleSheetDrop(tester, () => photosOf(twins).isNotEmpty);

      final inkId = inkIdOf(twins) ?? '';
      expect(inkId, isNotEmpty, reason: 'the block took its id');
      expect(photosOf(twins), hasLength(1));
      expect(inkIdOf(twins, start: 3), isNull);
      expect(photosOf(twins, start: 3), isEmpty, reason: 'one cel, two bands');

      session.historyManager.undo();
      await tester.pumpAndSettle();
      expect(inkIdOf(twins) ?? '', isEmpty);
      expect(sheetPhotosOn(ink, conteInkRowKey(twins, inkId)), isEmpty);

      session.historyManager.redo();
      await tester.pumpAndSettle();
      expect(inkIdOf(twins), inkId);
      expect(photosOf(twins), hasLength(1));
    });
  }

  testWidgets('with 「프레임 자동 생성」 on, a photo dropped on the band of a '
      'cut with no block makes the block and lands in ITS handwriting — ONE '
      'undo takes both', (tester) async {
    await pumpPanel(tester, autoCreates: true, brush: false);

    dropOnSheet(tester, png, bandOf(cellOf(hollow)));
    await settleSheetDrop(tester, () => inkIdOf(hollow) != null);

    final row = storyboardLayerForCut(session.cutById(hollow)!)!;
    expect(row.frames, hasLength(1), reason: 'the block covers the cut');
    final inkId = inkIdOf(hollow)!;
    expect(photosOf(hollow), hasLength(1));

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(
      storyboardLayerForCut(session.cutById(hollow)!)?.timeline ?? const {},
      isEmpty,
    );
    expect(sheetPhotosOn(ink, conteInkRowKey(hollow, inkId)), isEmpty);
  });

  testWidgets('with it off, that band takes no photo, and the chip says '
      'so', (tester) async {
    await pumpPanel(tester, autoCreates: false, brush: false);
    final at = bandOf(cellOf(hollow));

    expect(
      sheetPhotoTarget(
        tester,
      ).accepts!(MediaAssetDragData(path: png, name: 'photo'), at),
      isFalse,
    );
    dropOnSheet(tester, png, at);
    await settleSheetDrop(tester, () => false, tries: 5);

    expect(
      storyboardLayerForCut(session.cutById(hollow)!)?.timeline ?? const {},
      isEmpty,
    );
    expect(photosOf(hollow), isEmpty);
  });

  testWidgets('a cell\'s picture takes no photo — it is its cut\'s cel, not '
      'the sheet\'s ink — and the chip says so', (tester) async {
    await pumpPanel(tester, autoCreates: true, brush: false);
    final at = paper + cellOf(twins).pictureRect.center;

    expect(
      sheetPhotoTarget(
        tester,
      ).accepts!(MediaAssetDragData(path: png, name: 'photo'), at),
      isFalse,
    );
    dropOnSheet(tester, png, at);
    await settleSheetDrop(tester, () => false, tries: 5);

    expect(inkIdOf(twins), isNull);
    expect(photosOf(twins), isEmpty);
  });

  testWidgets('with 「프레임 자동 생성」 on, a photo dropped on the row after '
      'the last cell makes the next cut — its row, its block, the photo in '
      'its handwriting — and ONE undo takes it all', (tester) async {
    await pumpPanel(tester, autoCreates: true, brush: false);

    dropOnSheet(tester, png, nextCutsBand());
    await settleSheetDrop(tester, () => cutsOnTheSecond().length > 1);

    expect([for (final cut in cutsOnTheSecond()) cut.name], ['39', '40']);
    final made = cutsOnTheSecond().last.id;
    final inkId = inkIdOf(made)!;
    expect(photosOf(made), hasLength(1));

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect([for (final cut in cutsOnTheSecond()) cut.name], ['39']);
    expect(sheetPhotosOn(ink, conteInkRowKey(made, inkId)), isEmpty);
  });
}
