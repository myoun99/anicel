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

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-window-movie');
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
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
          body: ImportDialog(session: s, initialPaths: paths),
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

    test('the seed: a movie starts as a reference WITH its sound — without '
        'it on a picture row\'s frames (「프레임 영역 드롭은 끔」)', () {
      final free = seedImportSettings(kind: MediaAssetKind.video);
      expect((free.mode, free.sound), (ImportFileMode.reference, true));
      final onFrames = seedImportSettings(
        kind: MediaAssetKind.video,
        spot: const RowFramesSpot(layerId: LayerId('a'), frameIndex: 0),
      );
      expect(onFrames.sound, isFalse);
      expect(
        seedImportSettings(kind: MediaAssetKind.image).mode,
        ImportFileMode.keepInside,
      );
    });

    test('on an SE row\'s cell the sound is the PLACE\'s answer, locked on '
        '(「SE 행 드롭은 켬으로 잠김」)', () {
      const cell = SeCellSpot(layerId: LayerId('se'), frameIndex: 0);
      expect(importSoundLocked(cell), isTrue);
      expect(importSoundLocked(null), isFalse);
      ImportFileSettings resolve(ImportLayerSpot? spot) =>
          resolvedImportSettings(
            const ImportFileSettings(sound: false),
            kind: MediaAssetKind.video,
            isPsd: false,
            placing: true,
            spot: spot,
          );
      expect(resolve(cell).sound, isTrue);
      expect(
        resolve(null).sound,
        isFalse,
        reason: 'anywhere else it is the row\'s own answer',
      );
    });
  });

  testWidgets('a movie row is asked the bake question, starting unbaked — '
      'and pressing Bake leaves its Link alone', (tester) async {
    final movie = await writeMovie(tester, 'take.mp4');
    await open(tester, [movie]);

    expect(cellText(tester, 'bake', movie), AppText.strings.commonOff);
    expect(cellText(tester, 'file', movie), AppText.strings.imModeReference);

    await tester.tap(find.byKey(ValueKey<String>('import-cell-bake-$movie')));
    await tester.pump();

    expect(cellText(tester, 'bake', movie), AppText.strings.commonOn);
    expect(
      cellText(tester, 'file', movie),
      AppText.strings.imModeReference,
      reason:
          '🐛the first answer used to start from the blank default, which '
          'carries',
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
}
