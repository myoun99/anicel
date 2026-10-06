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
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
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
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart'
    show debugOperatingSystemOverride;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/export_cels_alone.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/project_scratch_folder.dart';

/// The Cels tab's RUN, down to the files on disk — the plan and the list
/// are pinned beside it (`export_cel_group_plan_test.dart`,
/// `export_dialog_cels_test.dart`), and neither of them writes anything.
///
/// 🚨The run walked every cel the window PREVIEWS, so one that was turned
/// off — counted out of the headline — was rendered and written all the
/// same (found reading the run for F-289, 2026-10-06).
///
/// 🗣️F-289 (유저 2026-10-05): 「디렉션레이어 출력시, 그림이 디렉션레이어의
/// 지시인데, 그게아니라 그림 그릴수있는 레이어니 거기 있는 그림 출력하도록」.
void main() {
  setUp(() => AppExport.settings.value = exportSettingsWritingCelsAlone());
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
    Directory into, {
    Directory? Function()? askedWhere,
    bool throughTheSystemsWindows = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            // The folder a person picks in whichever window is asked (null:
            // they backed out) — or the system's own windows, behind
            // [FolderPicker]'s seams.
            exportDirectoryPicker: throughTheSystemsWindows
                ? null
                : () async =>
                      askedWhere == null ? into.path : askedWhere()?.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-cels')));
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

  testWidgets('🚨the run writes the drawings that are ON: one turned off '
      'leaves no file', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-ticked');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpCels(tester, session, temp);
    await tapKey(tester, 'export-cels-block-a-a1');
    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      filesWrittenUnder(temp),
      ['A2.png', 'B1.png'],
      reason: 'A 1 was written with its block turned off',
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

    expect(filesWrittenUnder(temp), ['A1.png', 'A2.png', 'B1.png']);
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
      filesWrittenUnder(temp),
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

  testWidgets('🗣️a direction laid over ONE drawing is in that drawing\'s '
      'file, over its picture — and in no other (유저 2026-10-06: 「BG의 1번 '
      '그림에 디렉션레이어의 1번을 얹고싶다거나」)', (tester) async {
    final temp = Directory.systemTemp.createTempSync('qa-cels-laid');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final direction = session
        .cutById(cutId)!
        .layers
        .singleWhere((layer) => layer.kind == LayerKind.instruction);

    final state = await pumpCels(tester, session, temp);
    // The list stands on its top row, B, with its one drawing shown.
    await tapKey(tester, 'export-cels-stand-a');
    await tapKey(
      tester,
      'export-cels-direction-inst-${direction.frames.single.id.value}',
    );
    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      filesWrittenUnder(temp),
      ['A1.png', 'A2.png', 'B1.png'],
      reason: 'the direction KIND is off: no file of its own',
    );
    Future<((int, int, int, int), (int, int, int, int))> dotsOf(
      String file,
    ) async => (await tester.runAsync(() async {
      final png = File('${temp.path}/$file');
      return (await pixelOf(png, 1, 1), await pixelOf(png, 2, 2));
    }))!;
    expect(
      await dotsOf('A1.png'),
      (black, red),
      reason: 'its own drawing, and the direction over it',
    );
    final (own, laid) = await dotsOf('A2.png');
    expect(own, black);
    expect(laid, isNot(red), reason: 'nothing was laid over A 2');
    session.playbackRig.prerenderScheduler.cancel();
  });

  String? status(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('export-status')))
      .data;

  /// The lone file of the tests below is asked the save window — which is
  /// Windows' and Linux's, and not yet the host's on every runner.
  void asWindows() {
    debugOperatingSystemOverride = 'windows';
    addTearDown(() => debugOperatingSystemOverride = null);
  }

  testWidgets('🚨a queued job asked ONE file\'s place that has come to write '
      'several is asked again when the queue is run — a FOLDER, this time, '
      'opening where the file was placed — and every cel is its own file '
      'there (F-221)', (tester) async {
    asWindows();
    final first = Directory.systemTemp.createTempSync('qa-cels-queued-file');
    final second = Directory.systemTemp.createTempSync('qa-cels-queued-into');
    deleteAfterSessionEnds(first);
    deleteAfterSessionEnds(second);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final saves = <String>[];
    final folders = <String?>[];
    FolderPicker.debugSaveDestinationPicker =
        ({required String suggestedName, String? initialDirectory}) async {
          saves.add(suggestedName);
          return FolderGrant.granted(
            path: '${first.path}/B1.png',
            kind: GrantKind.file,
          );
        };
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      folders.add(initialDirectory);
      return FolderGrant.granted(path: second.path);
    };
    addTearDown(() {
      FolderPicker.debugSaveDestinationPicker = null;
      FolderPicker.debugFolderPicker = null;
    });

    final state = await pumpCels(
      tester,
      session,
      first,
      throughTheSystemsWindows: true,
    );
    // A's two drawings off: B 1 is the one file the run writes.
    await tapKey(tester, 'export-cels-block-a-a1');
    await tapKey(tester, 'export-cels-block-a-a2');
    await tapKey(tester, 'export-queue-add-button');
    expect(saves, ['B1.png'], reason: 'asked as it is queued: ONE file');
    expect(folders, isEmpty);
    // One of them back on. The ticks are the project's, not the job's: the
    // queued job writes two files now.
    await tapKey(tester, 'export-cels-block-a-a1');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(saves, hasLength(1));
    expect(
      folders,
      [first.path.replaceAll(r'\', '/')],
      reason: 'the place of one file cannot take two: a folder is asked',
    );
    expect(
      filesWrittenUnder(second),
      ['A1.png', 'B1.png'],
      reason: '↩️both would have landed on the one name the file was given',
    );
    expect(filesWrittenUnder(first), isEmpty);

    // The place asked again is the last place asked: the next window opens
    // there.
    await tester.runAsync(state.export);
    await tester.pump();
    expect(folders.last, second.path);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('backing out of the window that asks again runs NOTHING and '
      'says nothing — the job stays queued, and runs the next time the '
      'queue is asked', (tester) async {
    asWindows();
    final first = Directory.systemTemp.createTempSync('qa-cels-reask-file');
    final later = Directory.systemTemp.createTempSync('qa-cels-reask-into');
    deleteAfterSessionEnds(first);
    deleteAfterSessionEnds(later);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    // The place of one file, as it is queued; backed out of, when the queue
    // asks again; a folder, the time after.
    final answers = <Directory?>[first, null, later];
    var asked = 0;

    final state = await pumpCels(
      tester,
      session,
      first,
      askedWhere: () => answers[asked++],
    );
    await tapKey(tester, 'export-cels-block-a-a1');
    await tapKey(tester, 'export-cels-block-a-a2');
    await tapKey(tester, 'export-queue-add-button');
    await tapKey(tester, 'export-cels-block-a-a1');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(asked, 2);
    expect(filesWrittenUnder(first), isEmpty);
    expect(status(tester), '');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(asked, 3, reason: 'still queued, and still owed a place');
    expect(filesWrittenUnder(later), ['A1.png', 'B1.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a queued job whose place still fits is asked nothing when '
      'the queue is run', (tester) async {
    asWindows();
    final temp = Directory.systemTemp.createTempSync('qa-cels-queued-fits');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    var asked = 0;

    final state = await pumpCels(
      tester,
      session,
      temp,
      askedWhere: () {
        asked += 1;
        return temp;
      },
    );
    await tapKey(tester, 'export-cels-block-a-a1');
    await tapKey(tester, 'export-cels-block-a-a2');
    await tapKey(tester, 'export-queue-add-button');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(asked, 1);
    expect(filesWrittenUnder(temp), ['B1.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a queued job that has come to write NOTHING is not asked '
      'again, and does not fail — there is nothing to put anywhere', (
    tester,
  ) async {
    asWindows();
    final temp = Directory.systemTemp.createTempSync('qa-cels-queued-none');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    var asked = 0;

    final state = await pumpCels(
      tester,
      session,
      temp,
      askedWhere: () {
        asked += 1;
        return temp;
      },
    );
    await tapKey(tester, 'export-cels-block-a-a1');
    await tapKey(tester, 'export-cels-block-a-a2');
    await tapKey(tester, 'export-queue-add-button');
    // The last drawing off as well: the queued job writes nothing now.
    await tapKey(tester, 'export-cels-block-b-b1');

    await tester.runAsync(state.runQueue);
    await tester.pump();

    expect(asked, 1);
    expect(filesWrittenUnder(temp), isEmpty);
    final strings = AppText.strings;
    expect(
      status(tester),
      strings.exQueueRest(strings.exJobCount(1), failed: 0, kept: false),
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('ONE cel behind folders of its rule\'s making is a FOLDER to '
      'hand over: it is asked the folder window — a save window cannot name '
      'it — and written under its folders there', (tester) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: const ExportTabSpecs(
        cels: CelsExportSpec(
          kinds: celKindsAlone,
          naming: ExportCelNaming(cutFolder: true),
        ),
      ),
    );
    final temp = Directory.systemTemp.createTempSync('qa-cels-one-in-folder');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final savesAsked = <String>[];
    FolderPicker.debugSaveDestinationPicker =
        ({required String suggestedName, String? initialDirectory}) async {
          savesAsked.add(suggestedName);
          return FolderGrant.granted(
            path: '${temp.path}/asked.png',
            kind: GrantKind.file,
          );
        };
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        FolderGrant.granted(path: temp.path);
    addTearDown(() {
      FolderPicker.debugSaveDestinationPicker = null;
      FolderPicker.debugFolderPicker = null;
    });

    final state = await pumpCels(
      tester,
      session,
      temp,
      throughTheSystemsWindows: true,
    );
    await tapKey(tester, 'export-cels-block-a-a1');
    await tapKey(tester, 'export-cels-block-a-a2');
    await tester.runAsync(state.export);
    await tester.pump();

    expect(savesAsked, isEmpty);
    expect(filesWrittenUnder(temp), ['CUT1/B1.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('⛔a file\'s place takes ONE file: a run that finds it writes '
      'more stops before it writes any, and says so', (tester) async {
    asWindows();
    final temp = Directory.systemTemp.createTempSync('qa-cels-one-place');
    deleteAfterSessionEnds(temp);
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    final state = await pumpCels(
      tester,
      session,
      temp,
      // Between the window opening and its answer, every drawing that was
      // off comes back on: the place was asked for one file, and the run
      // that follows writes three.
      askedWhere: () {
        session.repository.updateExportOverrides(
          (_) => ExportProjectOverrides.empty,
        );
        return temp;
      },
    );
    await tapKey(tester, 'export-cels-block-a-a1');
    await tapKey(tester, 'export-cels-block-a-a2');
    await tester.runAsync(state.export);
    await tester.pump();

    expect(
      filesWrittenUnder(temp),
      isEmpty,
      reason: '↩️three cels written to one name, each over the last',
    );
    expect(status(tester), startsWith(AppText.strings.exFailed('').trim()));
    session.playbackRig.prerenderScheduler.cancel();
  });
}
