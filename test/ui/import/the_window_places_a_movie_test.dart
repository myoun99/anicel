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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

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
        await file.writeAsBytes(const [0, 0, 0, 24]);
        return file.path;
      }))!;

  /// The window on [paths], placing, over a session whose conform answers
  /// every file as a second of sound, reading movies through [backend].
  Future<EditorSessionManager> open(
    WidgetTester tester,
    List<String> paths, {
    FakeVideoBackend? backend,
    ImportLayerSpot Function(EditorSessionManager session)? droppedOn,
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
          ),
        ),
      ),
    );
    await tester.pump();
    return s;
  }

  /// Real IO and the conform run in `runAsync`; their answers land on the
  /// pumps after.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var tries = 0; tries < 100 && !done(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
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

  testWidgets('a movie row is asked the bake question, starting unbaked — '
      'and pressing Bake leaves its File answer alone', (tester) async {
    final movie = await writeMovie(tester, 'take.mp4');
    await open(tester, [movie]);

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
      reason: 'a press in one column answers that column only',
    );
  });

  testWidgets('「소리」 stands for a movie with a sound, on by default', (
    tester,
  ) async {
    final movie = await writeMovie(tester, 'talk.mp4');
    await open(tester, [movie]);
    await settle(
      tester,
      () => tester.any(
        find.byKey(ValueKey<String>('import-cell-sound-$movie')),
      ),
    );

    expect(cellText(tester, 'sound', movie), AppText.strings.commonOn);
  });

  testWidgets('「소리」 stands for a PICKED movie too — not only one handed in '
      'at the start', (tester) async {
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
          body: ImportDialog(session: s, filePicker: () async => [movie]),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('import-browse-files-button')),
    );
    await settle(
      tester,
      () => tester.any(
        find.byKey(ValueKey<String>('import-cell-sound-$movie')),
      ),
    );

    expect(cellText(tester, 'sound', movie), AppText.strings.commonOn);
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
    await settle(tester, () => frames() == 24);

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
    // The run STARTS on a later pump, so 「Importing…」 is not up yet on
    // the first look — wait for what the run leaves behind, then for the
    // window to say it is done.
    await settle(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
    await settle(tester, () => !tester.any(find.text('Importing…')));
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
    await settle(
      tester,
      () => tester.any(find.byKey(ValueKey<String>('import-cell-sound-$movie'))),
    );
    final cell = find.byKey(ValueKey<String>('import-cell-sound-$movie'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-sound-sound')),
    );
    await tester.pumpAndSettle();
    expect(cellText(tester, 'sound', movie), 'Sound only');
    expect(
      cellText(tester, 'fit', movie),
      '—',
      reason: 'the column stands by the file\'s kind — only its cell went '
          'blank, so nothing pops out when the answer changes',
    );
    await settle(
      tester,
      () => tester.any(
        find.byKey(const ValueKey<String>('import-preview-waveform')),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('import-preview-waveform')),
      findsOneWidget,
      reason: 'the preview shows what lands — the sound',
    );

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await settle(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
    await settle(tester, () => !tester.any(find.text('Importing…')));
    await tester.pumpAndSettle();

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
    final cell = find.byKey(ValueKey<String>('import-cell-sound-$movie'));
    await settle(tester, () => tester.any(cell));

    expect(cellText(tester, 'sound', movie), 'Sound only');
    expect(
      tester.widget<InkWell>(cell).onTap,
      isNull,
      reason: 'the cell answered it — nothing to open',
    );
    expect(cellText(tester, 'bake', movie), '—', reason: 'no picture comes');

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await settle(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
    await settle(tester, () => !tester.any(find.text('Importing…')));
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
    final cell = find.byKey(ValueKey<String>('import-cell-sound-$movie'));
    await settle(tester, () => tester.any(cell));
    expect(cellText(tester, 'sound', movie), 'Off', reason: 'its seed');

    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();

    InkWell option(String value) => tester.widget<InkWell>(
      find.byKey(ValueKey<String>('import-option-sound-$value')),
    );
    expect(option('sound').onTap, isNull);
    expect(option('picture').onTap, isNotNull);
    expect(option('pictureAndSound').onTap, isNotNull);
  });
}
