import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';

import '../../helpers/project_scratch_folder.dart';

/// The Cels tab's RUN, down to the files on disk — the plan and the list
/// are pinned beside it (`export_cel_group_plan_test.dart`,
/// `export_dialog_cels_test.dart`), and neither of them writes anything.
///
/// 🚨The run walked every cel the window PREVIEWS, so a bundle whose dot was
/// off — counted out of the headline — was rendered and written all the
/// same (found reading the run for F-289, 2026-10-06).
///
/// 🗣️F-289 (유저 2026-10-05): 「디렉션레이어 출력시, 그림이 디렉션레이어의
/// 지시인데, 그게아니라 그림 그릴수있는 레이어니 거기 있는 그림 출력하도록」.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const size = CanvasSize(width: 8, height: 8);
  const cutId = CutId('cut');
  const black = (0, 0, 0, 255);
  const red = (255, 0, 0, 255);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer cels(String id, String name, List<Frame> frames) => Layer(
    id: LayerId(id),
    name: name,
    frames: frames,
    mark: const LayerMark(process: LayerProcess.key),
  );

  /// A (two cels) · B (one) · a direction row whose one block says PAN.
  EditorSessionManager film() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: 'CUT1',
              duration: 2,
              canvasSize: size,
              layers: [
                cels('a', 'A', [frame('a1', '1'), frame('a2', '2')]),
                cels('b', 'B', [frame('b1', '1')]),
                Layer(
                  id: const LayerId('inst'),
                  name: 'Camera',
                  frames: const [],
                  kind: LayerKind.instruction,
                  instructions: {
                    0: const InstructionEvent(
                      instructionId: 'pan',
                      length: 2,
                      text: 'PAN',
                    ),
                  },
                ),
                createCameraLayer(cutId: cutId),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// One pixel of [colour] at ([x], [y]) on an empty canvas.
  BitmapSurface dot((int, int, int, int) colour, int x, int y) {
    final pixels = Uint8List(8 * 8 * 4);
    final i = (y * 8 + x) * 4;
    pixels[i] = colour.$1;
    pixels[i + 1] = colour.$2;
    pixels[i + 2] = colour.$3;
    pixels[i + 3] = colour.$4;
    return BitmapSurface(
      canvasSize: size,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  /// [session] with a picture on every drawing: a black dot at (1, 1) on
  /// each cel, and a red one at (2, 2) on the direction row's own drawing.
  void draw(EditorSessionManager session) {
    final cut = session.cutById(cutId)!;
    final store = session.renderCaches.brushFrameStore;
    void put(String row, FrameId cel, BitmapSurface pixels) =>
        store.storeBakedSurface(
          session.brushFrameKeyForCut(cut, LayerId(row), cel),
          pixels,
        );
    put('a', const FrameId('a1'), dot(black, 1, 1));
    put('a', const FrameId('a2'), dot(black, 1, 1));
    put('b', const FrameId('b1'), dot(black, 1, 1));
    final direction = cut.layers.singleWhere(
      (layer) => layer.kind == LayerKind.instruction,
    );
    put('inst', direction.frames.single.id, dot(red, 2, 2));
  }

  Future<ExportDialogState> pumpCels(
    WidgetTester tester,
    EditorSessionManager session,
    Directory into,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: () async => into.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('export-browse-button')),
    );
    await tester.pump();
    await tester.pump();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
  }

  List<String> filesIn(Directory directory) => [
    for (final file in directory.listSync(recursive: true).whereType<File>())
      file.path.substring(directory.path.length + 1).replaceAll('\\', '/'),
  ]..sort();

  /// The pixel of the written [png] at ([x], [y]).
  Future<(int, int, int, int)> pixelOf(File png, int x, int y) async {
    final codec = await ui.instantiateImageCodec(png.readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final i = (y * image.width + x) * 4;
    image.dispose();
    return (
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
      bytes.getUint8(i + 3),
    );
  }

  testWidgets('🚨the run writes the TICKED cels: a bundle whose dot is off '
      'leaves no file', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-ticked');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpCels(tester, session, temp);
    await tapKey(tester, 'export-cels-bundle-dot-a');
    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      filesIn(temp),
      ['B1.png'],
      reason: 'A\'s two cels were written with their dot off',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('every ticked cel is a file — the same film with nothing '
      'turned off', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-all');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpCels(tester, session, temp);
    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesIn(temp), ['A1.png', 'A2.png', 'B1.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️the direction kind writes the picture DRAWN on the row, '
      'under what its block says', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-direction');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpCels(tester, session, temp);
    await tapKey(tester, 'export-cels-kind-direction');
    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      filesIn(temp),
      ['A1.png', 'A2.png', 'B1.png', '_Camera_PAN.png'],
    );
    final written = File('${temp.path}/_Camera_PAN.png');
    final (drawn, beside) = (await tester.runAsync(
      () async => (await pixelOf(written, 2, 2), await pixelOf(written, 5, 5)),
    ))!;
    expect(drawn, red, reason: 'the dot drawn on the row');
    expect(
      beside,
      isNot(red),
      reason: '↩️the file was a picture of the block\'s writing — its text, '
          'its arrow and its length — and never the drawing',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });
}
