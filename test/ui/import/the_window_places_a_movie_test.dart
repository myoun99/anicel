// THE PLACEMENT WINDOW TAKES A MOVIE (미디어 배치 라운드 6): a movie is asked
// the bake question — for a movie, whether it stays a reference — and, when
// it has a sound, the 「소리」 question; pressing one answer never changes
// another; its transport counts the project's frames on the sound's clock;
// and it places.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/encoded_movie.dart';
import '../../helpers/import_span.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-window-movie');
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(tempDir);
  });

  Future<String> writeMovie(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}$name');
        await file.writeAsBytes(standInMovieBytes);
        return file.path;
      }))!;

  /// The window on [paths], placing — or registering, [poolOnly] — over a
  /// session whose conform answers every file as a second of sound, reading
  /// movies through [backend].
  Future<EditorSessionManager> open(
    WidgetTester tester,
    List<String> paths, {
    FakeVideoBackend? backend,
    ImportLayerSpot Function(EditorSessionManager session)? droppedOn,
    bool poolOnly = false,
  }) async {
    debugVideoDecodeBackend = backend ?? FakeVideoBackend();
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            initialPaths: paths,
            spot: droppedOn?.call(s),
            poolOnly: poolOnly,
          ),
        ),
      ),
    );
    await tester.pump();
    return s;
  }

  /// What a cell reads — a button's word, or the dash of a question that
  /// does not apply.
  String cellText(WidgetTester tester, String column, String path) {
    final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
    final widget = tester.widget(cell);
    if (widget is Text) {
      return widget.data!;
    }
    return tester
        .widget<Text>(find.descendant(of: cell, matching: find.byType(Text)))
        .data!;
  }

  group('the rules', () {
    test('a movie is asked whether it bakes — for a movie, the reference '
        'question (「참조 여부 = 배치 창의 굽기 열」)', () {
      expect(
        importBakeAllowed(kind: MediaAssetKind.video, placing: true),
        isTrue,
      );
      expect(
        importBakeAllowed(kind: MediaAssetKind.video, placing: false),
        isFalse,
      );
      expect(
        importBakeAllowed(kind: MediaAssetKind.audio, placing: true),
        isFalse,
      );
    });

    test('「소리」 is asked only of a placed movie that has a sound', () {
      bool asks({
        MediaAssetKind kind = MediaAssetKind.video,
        bool placing = true,
        bool hasSound = true,
      }) => importSoundAllowed(
        kind: kind,
        placing: placing,
        hasSound: hasSound,
      );

      expect(asks(), isTrue);
      expect(asks(hasSound: false), isFalse);
      expect(asks(placing: false), isFalse);
      expect(asks(kind: MediaAssetKind.audio), isFalse);
    });

    test('the seed: a movie starts WITH its sound — without it on a picture '
        'row\'s frames (「프레임 영역 드롭은 끔」)', () {
      expect(seedImportSettings().movieParts, MovieParts.pictureAndSound);
      final onFrames = seedImportSettings(
        spot: const RowFramesSpot(layerId: LayerId('a'), frameIndex: 0),
      );
      expect(onFrames.movieParts, MovieParts.picture);
    });

    test('on an SE row\'s cell the PLACE answers: the sound alone, whatever '
        'the row was answered — what that cell always landed (「SE 행 빈 '
        '칸은 소리만」), back when the column could only say 켬', () {
      const cell = SeCellSpot(
        layerId: LayerId('se'),
        trackFrame: 0,
        shownCell: 0,
      );
      expect(importSoundLocked(cell), isTrue);
      expect(importSoundLocked(null), isFalse);
      ImportFileSettings resolve(ImportLayerSpot? spot, MovieParts parts) =>
          resolvedImportSettings(
            ImportFileSettings(movieParts: parts),
            kind: MediaAssetKind.video,
            isPsd: false,
            placing: true,
            hasActiveCut: true,
            lasting: true,
            spot: spot,
          );
      for (final parts in MovieParts.values) {
        expect(
          resolve(cell, parts).movieParts,
          MovieParts.sound,
          reason: '$parts',
        );
      }
      expect(
        resolve(null, MovieParts.picture).movieParts,
        MovieParts.picture,
        reason: 'anywhere else it is the row\'s own answer',
      );
    });

    test('a bake is a PICTURE\'s answer: a movie brought in as its sound '
        'alone does not bake — and brought with its picture, the bake '
        'pressed before stands', () {
      ImportFileSettings resolve(MovieParts parts, {ImportLayerSpot? spot}) =>
          resolvedImportSettings(
            ImportFileSettings(bake: true, movieParts: parts),
            kind: MediaAssetKind.video,
            isPsd: false,
            placing: true,
            hasActiveCut: true,
            lasting: true,
            spot: spot,
          );
      expect(resolve(MovieParts.sound).bake, isFalse);
      expect(resolve(MovieParts.pictureAndSound).bake, isTrue);
      expect(resolve(MovieParts.picture).bake, isTrue);
      expect(
        resolve(
          MovieParts.pictureAndSound,
          spot: const SeCellSpot(
            layerId: LayerId('se'),
            trackFrame: 0,
            shownCell: 0,
          ),
        ).bake,
        isFalse,
        reason: 'an SE row\'s cell takes the sound alone',
      );
    });

    test('🎯the sound ALONE is the third answer (유저 2026-09-27: 「소리만 '
        '임포트 영상만 임포트도 고를수있게」), and it lands as a sound', () {
      const alone = ImportFileSettings(movieParts: MovieParts.sound);
      expect(
        importLandsAsSound(kind: MediaAssetKind.video, settings: alone),
        isTrue,
      );
      expect(
        importLandsAsSound(
          kind: MediaAssetKind.video,
          settings: const ImportFileSettings(),
        ),
        isFalse,
        reason: 'a movie with its picture places a picture',
      );
      expect(
        importLandsAsSound(kind: MediaAssetKind.image, settings: alone),
        isFalse,
        reason: 'only a movie has parts to leave behind',
      );
      expect(
        importLandsAsSound(
          kind: MediaAssetKind.audio,
          settings: const ImportFileSettings(),
        ),
        isTrue,
      );
    });

    test('what a drop\'s place keeps in stays in: the picture on a picture '
        'row\'s frames, and an SE cell takes the sound alone', () {
      const frames = RowFramesSpot(layerId: LayerId('a'), frameIndex: 0);
      const cell = SeCellSpot(
        layerId: LayerId('se'),
        trackFrame: 0,
        shownCell: 0,
      );
      expect(
        importMovieParts(MovieParts.sound, frames),
        MovieParts.pictureAndSound,
      );
      expect(importMovieParts(MovieParts.picture, frames), MovieParts.picture);
      expect(
        importMovieParts(MovieParts.pictureAndSound, frames),
        MovieParts.pictureAndSound,
      );
      expect(importMovieParts(MovieParts.picture, cell), MovieParts.sound);
      expect(
        importMovieParts(MovieParts.pictureAndSound, cell),
        MovieParts.sound,
      );
      expect(importMovieParts(MovieParts.sound, cell), MovieParts.sound);
      expect(importMovieParts(MovieParts.sound, null), MovieParts.sound);
    });
  });

  testWidgets('a movie row is asked the bake question, starting unbaked — and '
      'baked it is still asked how its file is kept while its sound comes '
      'with it; its picture alone, it keeps no entry (F-282-Q6)', (
    tester,
  ) async {
    final movie = await writeMovie(tester, 'take.mp4');
    await open(tester, [movie]);
    await settleAsync(
      tester,
      () =>
          cellText(tester, 'option', movie) ==
          AppText.strings.imPictureAndSound,
    );
    expect(
      cellText(tester, 'option', movie),
      AppText.strings.imPictureAndSound,
      reason: 'CONTROL: its sound comes with it',
    );

    expect(cellText(tester, 'bake', movie), AppText.strings.commonOff);
    expect(
      cellText(tester, 'file', movie),
      AppText.strings.imModeKeep,
      reason: 'a movie starts where every file starts (유저 2026-09-16)',
    );

    await tester.tap(find.byKey(ValueKey<String>('import-cell-bake-$movie')));
    await tester.pump();

    expect(cellText(tester, 'bake', movie), AppText.strings.commonOn);
    expect(
      cellText(tester, 'file', movie),
      AppText.strings.imModeKeep,
      reason: 'its sound lands beside the baked picture and reads the file, '
          'so the file keeps its entry',
    );

    final option = find.byKey(ValueKey<String>('import-cell-option-$movie'));
    await tester.ensureVisible(option);
    await settleLoadedPages(tester);
    await tester.tap(option);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-option-picture')),
    );
    await tester.pumpAndSettle();
    expect(
      cellText(tester, 'file', movie),
      '—',
      reason: 'baked and silent, nothing reads the file: no entry, so no '
          'question (유저 2026-10-09: 「구우면 풀에 안 남긴다」)',
    );
  });

  testWidgets('「소리」 stands for a movie with a sound, on by default', (
    tester,
  ) async {
    final movie = await writeMovie(tester, 'talk.mp4');
    await open(tester, [movie]);
    await settleAsync(
      tester,
      () => tester.any(
        find.byKey(ValueKey<String>('import-cell-option-$movie')),
      ),
    );

    expect(cellText(tester, 'option', movie), AppText.strings.imPictureAndSound);
  });

  testWidgets('「소리」 stands for a PICKED movie too — one the door hands over '
      'with its grant, not only a path', (tester) async {
    final movie = await writeMovie(tester, 'picked.mp4');
    debugVideoDecodeBackend = FakeVideoBackend();
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            picked: [FolderGrant.granted(path: movie, kind: GrantKind.file)],
          ),
        ),
      ),
    );
    await tester.pump();

    await settleAsync(
      tester,
      () => tester.any(
        find.byKey(ValueKey<String>('import-cell-option-$movie')),
      ),
    );

    expect(cellText(tester, 'option', movie), AppText.strings.imPictureAndSound);
  });

  testWidgets('🎯a movie that BAKES counts its frames into the run\'s % — under '
      'the run\'s one wait window, not one of its own (F-282-Q1)', (
    tester,
  ) async {
    // 유저 2026-10-08: 「파일 수와 각 파일의 진행(동영상 굽기의 프레임 등)으로
    // %를 센다. 동영상 굽기의 창은 따로 뜨지 않고 이 창 하나로 합친다」.
    final movie = await writeMovie(tester, 'take.mp4');
    final s = await open(
      tester,
      [movie],
      // Four frames: a count with a middle is all the % is asked for — 24
      // baked one at a time were 4.3 s of this file's 7.8 (heavy-tests-save).
      backend: FakeVideoBackend(frameCount: 4),
    );
    await tester.tap(find.byKey(ValueKey<String>('import-cell-bake-$movie')));
    await tester.pump();
    expect(cellText(tester, 'bake', movie), AppText.strings.commonOn);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    final counted = watchTheBar(tester);
    final lines = watchTheLine(tester);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppProgressDialog), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-progress-dialog')),
      findsOneWidget,
      reason: 'the run\'s own window, and no second one for the movie',
    );
    await pumpPastTheWaitWindow(tester);

    expect(
      counted.where((fraction) => fraction > 0 && fraction < 1),
      isNotEmpty,
      reason: 'the frames it baked were counted on the way, not only its end',
    );
    // 🗣️F-494: and the window says what it is doing, in the order the door
    // does it — the file its sound reads held, then the frames baked.
    expect(lines, [
      '',
      AppText.strings.imStepCarrying,
      AppText.strings.imStepRasterizing,
      '',
    ]);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('its transport counts PROJECT frames on the sound\'s clock — '
      'a 12 fps take of 12 frames runs 24 in a 24 fps project', (
    tester,
  ) async {
    final movie = await writeMovie(tester, 'twelve.mp4');
    await open(
      tester,
      [movie],
      backend: FakeVideoBackend(frameCount: 12, fpsNumerator: 12),
    );
    final row = find.byKey(const ValueKey<String>('import-row-twelve.mp4'));
    if (tester.any(row)) {
      final rect = tester.getRect(row);
      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await tester.pump();
    }
    int? frames() => tester.any(find.byType(TransportBar))
        ? tester.widget<TransportBar>(find.byType(TransportBar)).frameCount
        : null;
    await settleAsync(tester, () => frames() == 24);

    expect(frames(), 24);
  });

  testWidgets('and it PLACES — a reference layer, ONE pool entry, its sound '
      'on the SE rows', (tester) async {
    final movie = await writeMovie(tester, 'take.mp4');
    final s = await open(
      tester,
      [movie],
      backend: FakeVideoBackend(frameCount: 24),
    );

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    // The run STARTS on a later pump — wait for what the run leaves behind,
    // then for the wait window it stands behind to go.
    await settleAsync(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    final key = normalizedMediaPath(movie);
    expect(
      s.requireActiveCut.layers.any(
        (layer) => layer.mediaReference?.assetPath == key,
      ),
      isTrue,
      reason: 'a movie starts as a reference, and a reference places',
    );
    expect(s.mediaPool.mediaAssets.single.kind, MediaAssetKind.video);
    expect(
      s.activeTrack.seLayers.any(
        (layer) => layer.audioClips.any((clip) => clip.filePath == key),
      ),
      isTrue,
      reason: 'its sound came with it',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯set to its sound ALONE it lands only the sound — on the SE '
      'rows, no picture row, and still ONE pool entry, the movie\'s', (
    tester,
  ) async {
    final movie = await writeMovie(tester, 'take.mp4');
    final s = await open(
      tester,
      [movie],
      backend: FakeVideoBackend(frameCount: 24),
    );
    await settleAsync(
      tester,
      () => tester.any(find.byKey(ValueKey<String>('import-cell-option-$movie'))),
    );
    final cell = find.byKey(ValueKey<String>('import-cell-option-$movie'));
    await tester.ensureVisible(cell);
    await settleLoadedPages(tester);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-option-sound')),
    );
    await tester.pumpAndSettle();
    expect(cellText(tester, 'option', movie), 'Sound only');
    expect(
      cellText(tester, 'fit', movie),
      '—',
      reason: 'the column stands by the file\'s kind — only its cell went '
          'blank, so nothing pops out when the answer changes',
    );
    await settleAsync(
      tester,
      () => tester.any(
        find.byKey(const ValueKey<String>('import-preview-marks')),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('import-preview-marks')),
      findsOneWidget,
      reason: 'the preview shows what lands — the sound',
    );

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    final lines = watchTheLine(tester);
    await settleAsync(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    expect(
      lines,
      ['', AppText.strings.imStepCarrying, ''],
      reason: '🗣️F-494: the movie its sound reads, carried',
    );
    final key = normalizedMediaPath(movie);
    expect(
      s.requireActiveCut.layers.any(
        (layer) => layer.mediaReference?.assetPath == key,
      ),
      isFalse,
      reason: 'no picture came',
    );
    expect(
      s.activeTrack.seLayers.any(
        (layer) => layer.audioClips.any((clip) => clip.filePath == key),
      ),
      isTrue,
      reason: 'the sound came, by a sound\'s own door',
    );
    expect(
      s.mediaPool.mediaAssets.single.kind,
      MediaAssetKind.video,
      reason: 'the pool keeps the MOVIE — one entry for the pair it can '
          'still become',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('let go on an SE row\'s cell the row reads 「소리만」, locked — '
      'the cell\'s answer — and ONLY the sound lands, on that row from that '
      'cell', (tester) async {
    final movie = await writeMovie(tester, 'take.mp4');
    late LayerId seRow;
    late int start;
    final s = await open(
      tester,
      [movie],
      backend: FakeVideoBackend(frameCount: 24),
      droppedOn: (s) {
        seRow = s.activeTrack.seLayers.first.id;
        start = s.activeCutGlobalStartFrame;
        return SeCellSpot(layerId: seRow, trackFrame: start, shownCell: 0);
      },
    );
    final cell = find.byKey(ValueKey<String>('import-cell-option-$movie'));
    await settleAsync(tester, () => tester.any(cell));

    expect(cellText(tester, 'option', movie), 'Sound only');
    expect(
      tester.widget<InkWell>(cell).onTap,
      isNull,
      reason: 'the cell answered it — nothing to open',
    );
    expect(cellText(tester, 'bake', movie), '—', reason: 'no picture comes');

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await settleAsync(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    final key = normalizedMediaPath(movie);
    final row = s.activeTrack.seLayers.firstWhere(
      (layer) => layer.id == seRow,
    );
    expect(row.timeline[start], isNotNull, reason: 'the cell it was let go on');
    expect(row.audioClips.single.filePath, key);
    expect(
      s.requireActiveCut.layers.any(
        (layer) => layer.mediaReference?.assetPath == key,
      ),
      isFalse,
      reason: 'no picture came',
    );
    expect(s.mediaPool.mediaAssets.single.kind, MediaAssetKind.video);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('let go on a picture row\'s frames, 「소리만」 is there and '
      'cannot be pressed — the row takes the picture', (tester) async {
    final movie = await writeMovie(tester, 'take.mp4');
    await open(
      tester,
      [movie],
      backend: FakeVideoBackend(frameCount: 24),
      droppedOn: (s) => RowFramesSpot(
        layerId: s.requireActiveCut.layers.first.id,
        frameIndex: 0,
      ),
    );
    final cell = find.byKey(ValueKey<String>('import-cell-option-$movie'));
    await settleAsync(tester, () => tester.any(cell));
    expect(cellText(tester, 'option', movie), 'Picture only', reason: 'its seed');

    await tester.ensureVisible(cell);
    await settleLoadedPages(tester);
    await tester.tap(cell);
    await tester.pumpAndSettle();

    InkWell option(String value) => tester.widget<InkWell>(
      find.byKey(ValueKey<String>('import-option-option-$value')),
    );
    expect(option('sound').onTap, isNull);
    expect(option('picture').onTap, isNotNull);
    expect(option('pictureAndSound').onTap, isNotNull);
  });

  // 🗣️F-494 (유저 2026-10-28): 「3.4gb의 동영상 … 중간의 2분만 인/아웃으로
  // 설정하고 미디어에 품기로 임포트 누르니, 계속 0%에서 안늘어남」 — the span
  // is encoded again into a piece of its own, a minute for those two, and
  // that encode is what the window now names and counts frame by frame.
  group('a movie carried as a span is cut into its piece', () {
    final skip = nativeEngineLibraryPathOrNull() == null;

    /// Six real frames — the cut reads the file through the engine — while
    /// the preview reads them through [FakeVideoBackend]; null where this
    /// run has no encoder (Linux: the engine is there, the OS encoder is
    /// not), and the test is then skipped, with why, as every other one
    /// writing through [writeEncodedMovie] is.
    Future<String?> sixFrames(WidgetTester tester) =>
        tester.runAsync<String?>(() async {
          final path = '${tempDir.path}${Platform.pathSeparator}take.mp4';
          return writeEncodedMovie(path, frames: 6) ? path : null;
        });

    testWidgets('🎯registered, the window names the encode and counts its '
        'frames, then the piece\'s holding', (tester) async {
      final movie = await sixFrames(tester);
      if (movie == null) {
        return;
      }
      final s = await open(
        tester,
        [movie],
        backend: FakeVideoBackend(frameCount: 6),
        poolOnly: true,
      );
      await keepImportSpan(tester, 2, 4);

      await tester.tap(
        find.byKey(const ValueKey<String>('import-run-button')),
      );
      final lines = watchTheLine(tester);
      final counted = watchTheBar(tester);
      await settleAsync(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
      await pumpPastTheWaitWindow(tester);

      expect(lines, [
        '',
        AppText.strings.imStepRecoding,
        '',
        AppText.strings.imStepCarrying,
        '',
      ]);
      // The cut the first half of the file's share, its three frames
      // each a third of it; the holding the rest.
      expectOneBar(counted, [1 / 6, 1 / 3, 0.5, 1]);
      s.playbackRig.prerenderScheduler.cancel();
    }, skip: skip);

    testWidgets('🎯placed, the window names the encode and counts its frames '
        'before it holds the piece', (tester) async {
      final movie = await sixFrames(tester);
      if (movie == null) {
        return;
      }
      final s = await open(
        tester,
        [movie],
        backend: FakeVideoBackend(frameCount: 6),
      );
      await keepImportSpan(tester, 2, 4);

      await tester.tap(
        find.byKey(const ValueKey<String>('import-run-button')),
      );
      final lines = watchTheLine(tester);
      final counted = watchTheBar(tester);
      await settleAsync(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
      await pumpPastTheWaitWindow(tester);

      expect(lines, [
        '',
        AppText.strings.imStepRecoding,
        AppText.strings.imStepCarrying,
        '',
      ]);
      // The cut the first of a placed file's three stretches.
      expectOneBar(counted, [1 / 9, 2 / 9, 1 / 3, 1]);
      s.playbackRig.prerenderScheduler.cancel();
    }, skip: skip);
  });
}
