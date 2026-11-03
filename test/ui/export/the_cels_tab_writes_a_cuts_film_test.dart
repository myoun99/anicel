import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_size_mode.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
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
import 'package:anicel/src/ui/export/export_preview_document.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/export_cels_board_probe.dart';
import '../../helpers/export_format_pick.dart';
import '../../helpers/export_preview_probe.dart';
import '../../helpers/files_written_under.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🗣️I-151 (유저 2026-11-03): 「출력창, 셀 탭에 영상도 출력하는 기능 추가.
/// 내보낼 종류에 동영상 넣고, 오른쪽 옵션에도 동영상 형식 넣고. 동영상
/// 출력이랑 똑같이 재사용할것들 재사용. 왠만한건 시퀀스의 출력이랑 똑같음.
/// 다만 범위 대상은 프로젝트로 하더라도 셀은 컷마다 출력이니까 컷마다 영상
/// 출력하는것임. 동영상 내보낼종류에 넣으면 내보낼행에 똑같이 추가. 누르면
/// 미리보기창이 영상 미리보기로 바뀌는등 ui도 대응」.
///
/// The cut's FILM is one of its documents: a row at the foot of the list, a
/// block a cut, written as the Sequence tab writes that cut.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const size = CanvasSize(width: 8, height: 8);

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Cut cut(String id, String name) => Cut(
    id: CutId(id),
    name: name,
    duration: 2,
    canvasSize: size,
    layers: [
      Layer(
        id: LayerId('$id-a'),
        name: 'A',
        frames: [frame('$id-a1', '1'), frame('$id-a2', '2')],
        mark: const LayerMark(process: LayerProcess.key),
      ),
      createCameraLayer(cutId: CutId(id)),
    ],
  );

  /// Cuts 301 and 302, each a KEY row A with two cels.
  EditorSessionManager film() => inkEveryCel(
    EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: const CanvasSize(width: 32, height: 18),
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cut('c1', '301'), cut('c2', '302')],
          ),
        ],
      ),
    ),
  );

  /// A black dot on each of A's cels, so the run has pictures to write.
  void draw(EditorSessionManager session) {
    for (final id in ['c1', 'c2']) {
      final shot = session.cutById(CutId(id))!;
      final pixels = Uint8List(8 * 8 * 4)..[3] = 255;
      for (final cel in ['$id-a1', '$id-a2']) {
        session.renderCaches.brushFrameStore.storeBakedSurface(
          session.brushFrameKeyForCut(shot, LayerId('$id-a'), FrameId(cel)),
          BitmapSurface(
            canvasSize: size,
            tileSize: 8,
            tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
          ),
        );
      }
    }
  }

  const gif = ExportFormatSelection(
    container: ExportVideoContainer.gif,
    videoCodec: ExportVideoCodec.gif,
  );

  Future<ExportDialogState> pumpCels(
    WidgetTester tester,
    EditorSessionManager session, {
    required CelsExportSpec spec,
    Directory? into,
    Size surface = const Size(1280, 720),
  }) async {
    AppExport.settings.value = AppExportSettings(
      lastSpecs: ExportTabSpecs(cels: spec),
    );
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: into == null ? null : () async => into.path,
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

  Finder keyed(String value) => find.byKey(ValueKey<String>(value));

  Future<void> press(WidgetTester tester, String key) async {
    await tester.ensureVisible(keyed(key));
    await tester.pump();
    await tester.tap(keyed(key), warnIfMissed: false);
    await tester.pump();
  }

  /// The files the list says it writes: its bright blocks', top to bottom.
  List<String> listed(WidgetTester tester) => [
    for (final row in tester.celsBoard.rows)
      for (final sheet in row.sheets)
        if (sheet.written) sheet.fileName,
  ];

  Directory scratch() {
    final temp = Directory.systemTemp.createTempSync('qa-cels-film');
    deleteAfterSessionEnds(temp);
    return temp;
  }

  testWidgets('동영상 is a kind of the cut\'s documents: its row closes the '
      'list, its block named as a document and by its format', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.cel, ExportCelKind.video},
      ),
    );
    expect(listed(tester), ['A1.png', 'A2.png', '_CUT301.mp4']);

    await pickFromExportList(
      tester,
      'export-film-format-file',
      'export-film-format-container-gif',
    );
    expect(state.debugSpecs.cels.videoFormat, gif);
    expect(listed(tester), ['A1.png', 'A2.png', '_CUT301.gif']);

    await press(tester, 'export-cels-kind-video');
    expect(listed(tester), ['A1.png', 'A2.png']);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨ONE run writes the cels and the cut\'s film — the film as '
      'the Sequence tab writes the cut, at the tab\'s size', (tester) async {
    final temp = scratch();
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.cel, ExportCelKind.video},
        videoFormat: gif,
      ),
      into: temp,
    );
    final steps = <(int, int)>[];
    state.debugOnProgress = (done, total) => steps.add((done, total));

    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), ['A1.png', 'A2.png', '_CUT301.gif']);
    expect(
      {for (final (_, total) in steps) total},
      {4},
      reason: 'the bar counts the two cels and the film\'s two frames',
    );
    expect(steps, containsAllInOrder([(2, 4), (3, 4), (4, 4)]));
    expect(steps.last, (4, 4));
    final movie = img.decodeGif(
      File('${temp.path}/_CUT301.gif').readAsBytesSync(),
    )!;
    expect(
      (movie.width, movie.height),
      (size.width, size.height),
      reason: 'the tab\'s size: the canvas',
    );
    expect(
      [for (final picture in movie.frames) picture.frameDuration ~/ 10]
          .fold(0, (sum, each) => sum + each),
      8,
      reason: 'two frames of 24 fps: 8.33 hundredths',
    );
    expect(
      tester.widget<Text>(keyed('export-status')).data,
      'Exported 3 files.',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨a run stopped inside the film is a stopped run: the film '
      'keeps the frames it got to, and is no film done', (tester) async {
    final temp = scratch();
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.cel, ExportCelKind.video},
        videoFormat: gif,
      ),
      into: temp,
    );
    // The film's first frame: the two cels and one frame of four steps.
    state.debugOnProgress = (done, _) {
      if (done == 3) {
        state.cancelExport();
      }
    };

    await tester.runAsync(state.export);
    await tester.pump();

    expect(filesWrittenUnder(temp), ['A1.png', 'A2.png', '_CUT301.gif']);
    expect(
      img.decodeGif(File('${temp.path}/_CUT301.gif').readAsBytesSync())!
          .frames,
      hasLength(1),
    );
    expect(
      tester.widget<Text>(keyed('export-status')).data,
      AppText.strings.exCancelledAfter(AppText.strings.exFileCount(3)),
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️a film is written as its format asks it of a GIF — how '
      'many times it plays, and whether the ground it leaves is clear '
      '(I-152: 「색처리든 뭐든 gif에대한 세부설정가능한거 두고싶어」)', (
    tester,
  ) async {
    final session = film();
    addTearDown(session.dispose);
    draw(session);

    /// The cut's film, written as [format] asks.
    Future<Uint8List> filmOf(ExportFormatSelection format) async {
      // A window of its own: the one before keeps its own choice.
      await tester.pumpWidget(const SizedBox.shrink());
      final temp = scratch();
      final state = await pumpCels(
        tester,
        session,
        spec: CelsExportSpec(
          kinds: const {ExportCelKind.video},
          videoFormat: format,
        ),
        into: temp,
      );
      await tester.runAsync(state.export);
      await tester.pump();
      return File('${temp.path}/_CUT301.gif').readAsBytesSync();
    }

    final once = await filmOf(
      gif.copyWith(gif: const ExportGifSettings(plays: 1)),
    );
    expect(
      String.fromCharCodes(once),
      isNot(contains('NETSCAPE2.0')),
      reason: 'played once: no loop block',
    );
    expect(
      img.decodeGif(once)!.any((pixel) => pixel.a == 0),
      isTrue,
      reason: 'RGBA: the ground the cels leave is the clear colour',
    );

    final opaque = await filmOf(gif.copyWith(channels: ExportChannels.rgb));
    expect(
      String.fromCharCodes(opaque),
      contains('NETSCAPE2.0'),
      reason: 'LIVENESS — forever is a loop block',
    );
    expect(
      img.decodeGif(opaque)!.any((pixel) => pixel.a == 0),
      isFalse,
      reason: 'RGB: the white ground of every movie',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the film is as large as the tab\'s size says: through the '
      'camera, the camera\'s', (tester) async {
    final temp = scratch();
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.video},
        videoFormat: gif,
        sizeMode: ExportSizeMode.camera,
      ),
      into: temp,
    );

    await tester.runAsync(state.export);
    await tester.pump();

    final movie = img.decodeGif(
      File('${temp.path}/_CUT301.gif').readAsBytesSync(),
    )!;
    expect((movie.width, movie.height), (32, 18));
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️under the project scope too, a film a CUT: 「셀은 컷마다 '
      '출력이니까 컷마다 영상 출력하는것임」', (tester) async {
    final temp = scratch();
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.video},
        videoFormat: gif,
        scope: ExportScopeKind.project,
      ),
      into: temp,
      // The project scope holds the cut's folder, whose column (I-153)
      // widens the Cels list past what a 1280 screen leaves it.
      surface: const Size(1600, 720),
    );

    await tester.runAsync(state.export);
    await tester.pump();

    // Each in its cut's folder, which the project scope holds (I-153).
    expect(
      filesWrittenUnder(temp),
      containsAll(['301/_CUT301.gif', '302/_CUT302.gif']),
    );
    expect(
      [for (final name in filesWrittenUnder(temp)) if (name.endsWith('.gif')) name],
      hasLength(2),
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️standing on the film, the preview RUNS it: 「누르면 '
      '미리보기창이 영상 미리보기로 바뀌는등」', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(
        kinds: {ExportCelKind.cel, ExportCelKind.video},
      ),
    );

    await press(tester, 'export-cels-stand-c1-a');
    expect(tester.exportPreviewDocument!.shape, ExportPreviewShape.single);
    expect(tester.exportTransportBar, findsNothing);

    await press(tester, 'export-cels-stand-document-video');
    final document = tester.exportPreviewDocument!;
    expect(document.shape, ExportPreviewShape.runs);
    expect(document.pageCount, 2, reason: 'the cut\'s two frames');
    expect(tester.exportTransportBar, findsOneWidget);
    expect(tester.exportPreviewName, '_CUT301.mp4');
    await tester.settleExportPreview();
    expect(tester.exportPreviewImage, isNotNull);

    await tester.seekExportPreview(1);
    expect(
      tester.exportTransport.currentFrame,
      1,
      reason: 'a hand on its transport moves the film, not the list',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the film\'s sound is asked where its format has room for it: '
      'an MP4\'s, and no GIF\'s', (tester) async {
    final session = film();
    addTearDown(session.dispose);
    final state = await pumpCels(
      tester,
      session,
      spec: const CelsExportSpec(kinds: {ExportCelKind.video}),
    );
    final sound = find.byWidgetPredicate(
      (widget) =>
          widget is ExportAccordion && widget.title == AppText.strings.exAudio,
    );
    expect(sound, findsOneWidget);
    expect(keyed('export-film-format-bitrate'), findsOneWidget);
    expect(state.debugSpecs.cels.videoAudio, isTrue);
    expect(
      keyed('export-film-format-kind'),
      findsNothing,
      reason: 'a film is a movie: no 동영상 · 이미지 to pick between',
    );

    await pickFromExportList(
      tester,
      'export-film-format-file',
      'export-film-format-container-gif',
    );
    expect(sound, findsNothing);
    expect(
      keyed('export-film-format-codec'),
      findsNothing,
      reason: 'one way of packing: no codec to pick',
    );
    expect(keyed('export-film-format-bitrate'), findsNothing);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️the Sequence tab offers the same movies, GIF among them '
      '(I-152: 「새 형식이니까 다른 대응하는곳에서도 필요하면 등장하게」) — '
      'written by the one film writer, asking no codec, bitrate or sound',
      (tester) async {
    final temp = scratch();
    final session = film();
    addTearDown(session.dispose);
    draw(session);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            exportDirectoryPicker: () async => temp.path,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(keyed('export-tab-sequence'));
    await tester.pump();
    final sound = find.byWidgetPredicate(
      (widget) =>
          widget is ExportAccordion && widget.title == AppText.strings.exAudio,
    );
    expect(sound, findsOneWidget, reason: 'LIVENESS — an MP4 asks it');
    expect(
      keyed('export-format-kind'),
      findsOneWidget,
      reason: 'LIVENESS — the Sequence tab writes movies and stills',
    );

    await pickExportContainer(tester, ExportVideoContainer.gif);
    final state = tester.state<ExportDialogState>(find.byType(ExportDialog));
    expect(state.debugSpecs.sequence.format, gif);
    expect(sound, findsNothing);
    expect(keyed('export-format-codec'), findsNothing);
    expect(keyed('export-format-bitrate'), findsNothing);

    await tester.runAsync(state.export);
    await tester.pump();

    final [name] = filesWrittenUnder(temp);
    expect(name, endsWith('.gif'));
    final movie = img.decodeGif(File('${temp.path}/$name').readAsBytesSync())!;
    expect((movie.width, movie.height), (32, 18), reason: 'the camera\'s');
    session.playbackRig.prerenderScheduler.cancel();
  });
}
