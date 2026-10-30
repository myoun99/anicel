import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/reference_swap.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart'
    show debugVideoDecodeBackend;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/three_frame_gif.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/rail_group_button.dart';

/// I-47 (유저 2026-09-25): 「이미지 레이어의 프레임영역에 떨구면 참조변경 …
/// 기존의 트랜스폼값같은거 안건들이고 진짜 참조대상만 변경하는느낌」 — and
/// Q1 (2026-09-27): 「창 없이 바로 바꾼다 (언두 하나)」. Driven the way the
/// user would: a pool row dragged onto a reference row's frames.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-i47');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  const red = 0xFF0000FF;
  const blue = 0x0000FFFF;
  const clear = [0, 0, 0, 0];

  /// The app with `old.png` placed as an image row that REFERENCES it — the
  /// placement window's reference road — and [next] in the pool, whose
  /// panel is open. [nextBytes] replaces what a solid blue picture of
  /// [size] would write there; [carryNext] pools it CARRIED and then takes
  /// its original away. With [oldGifFrame] the row is that one frame of a
  /// three-frame GIF instead — a still that is not its file's first picture.
  Future<({EditorSessionManager session, Layer row, String next})> open(
    WidgetTester tester, {
    String next = 'next.png',
    List<int>? nextBytes,
    ({int width, int height}) size = (width: 8, height: 8),
    bool carryNext = false,
    int? oldGifFrame,
  }) async {
    final paths = (await tester.runAsync(() async {
      final old = oldGifFrame == null
          ? await writeSolidPng(
              tempDir,
              'old.png',
              width: size.width,
              height: size.height,
              rgba: red,
            )
          : await writeThreeFrameGif(tempDir, 'old.gif');
      final path = '${tempDir.path}${Platform.pathSeparator}$next';
      if (nextBytes == null) {
        await writeSolidPng(
          tempDir,
          next,
          width: size.width,
          height: size.height,
          rgba: blue,
        );
      } else {
        await File(path).writeAsBytes(nextBytes);
      }
      return (old: normalizedMediaPath(old), next: normalizedMediaPath(path));
    }))!;
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: createDefaultProject().copyWith(
            mediaAssets: [
              if (!carryNext)
                MediaAsset(
                  path: paths.next,
                  name: mediaAssetDefaultName(paths.next),
                  kind:
                      mediaAssetKindForPath(paths.next) ?? MediaAssetKind.image,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      railGroupButton(EditorWorkspace.railGroupId(right: true, slot: 3)),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    await tester.runAsync(() async {
      if (carryNext) {
        await session.mediaPool.importMediaFiles(
          [paths.next],
          copyIntoProject: true,
        );
        await File(paths.next).delete();
      }
      expect(
        await session.importDoors.importImageFile(
          path: paths.old,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
          inFrame: oldGifFrame ?? 0,
          outFrame: oldGifFrame,
        ),
        isTrue,
        reason: 'premise: the reference row is placed',
      );
    });
    await tester.pumpAndSettle();
    final row = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.mediaReference?.assetPath == paths.old,
    );
    return (session: session, row: row, next: paths.next);
  }

  /// The RGBA at ([x], [y]) of the picture the row's cel holds — clear where
  /// no tile holds anything.
  List<int> pixelAt(EditorSessionManager session, Layer row, int x, int y) {
    final cut = session.requireActiveCut;
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
    )!;
    final size = surface.tileSize;
    final tile = surface.tiles.entries
        .where((entry) => entry.key.x == x ~/ size && entry.key.y == y ~/ size)
        .firstOrNull
        ?.value;
    if (tile == null) {
      return clear;
    }
    final at = ((y % size) * size + (x % size)) * 4;
    return tile.pixels.sublist(at, at + 4);
  }

  List<int> centre(EditorSessionManager session, Layer row) {
    final canvas = session.requireActiveCut.canvasSize;
    return pixelAt(session, row, canvas.width ~/ 2, canvas.height ~/ 2);
  }

  /// Drags [path]'s pool row onto the second cell of [row] and lets go —
  /// answering how many frames the silhouette covered while it hovered,
  /// or null when none stood there.
  Future<int?> dragOnto(WidgetTester tester, Layer row, String path) async {
    final target = find.named('timeline-layer-asset-drop-${row.id}');
    final frames = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<TimelineRowCellsPainter>()
        .firstWhere((painter) => painter.layer.id == row.id)
        .geometry
        .value;
    final at =
        tester.getTopLeft(target) +
        Offset(
          frames.edgeAt(1) -
              frames.edgeAt(frames.frameStartIndex) +
              frames.frameCellExtent / 2,
          tester.getSize(target).height / 2,
        );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey<String>('media-asset-row-$path'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();
    final silhouette = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<TimelineSilhouettePainter>()
        .firstOrNull;
    await gesture.up();
    await tester.pump();
    return silhouette?.frames;
  }

  /// Lets the swap's read and bake land.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    await settleAsync(tester, done);
    await tester.pumpAndSettle();
  }

  bool pointsAt(EditorSessionManager session, Layer row, String path) =>
      session.layerById(row.id)!.mediaReference!.assetPath == path;

  testWidgets('🎯a still let go on a still reference row: the row shows it — '
      'at once, no window — with its name and its frames as they were, and '
      'ONE undo brings the old picture back', (tester) async {
    final (:session, :row, :next) = await open(tester);
    final old = row.mediaReference!.assetPath;
    expect(centre(session, row), [255, 0, 0, 255]);
    session.selectLayer(
      session.requireActiveCut.layers.firstWhere((l) => l.id != row.id).id,
    );
    await tester.pumpAndSettle();
    expect(session.activeLayerId, isNot(row.id), reason: 'premise');

    final silhouette = await dragOnto(tester, row, next);
    await settle(tester, () => pointsAt(session, row, next));

    final shown = row.timeline.entries;
    expect(
      silhouette,
      shown.last.key + shown.last.value.length! - shown.first.key,
      reason: '「끄는 동안 행 위에 바뀔 블록이 실루엣」 — all of what it shows',
    );
    expect(find.byType(ImportDialog), findsNothing);
    final swapped = session.layerById(row.id)!;
    expect(swapped.mediaReference!.assetPath, next);
    expect(swapped.name, row.name);
    expect(swapped.timeline, row.timeline);
    expect(swapped.frames, row.frames);
    expect(centre(session, row), [0, 0, 255, 255]);
    expect(session.activeLayerId, row.id, reason: 'the drop stands on it');

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(pointsAt(session, row, old), isTrue);
    expect(centre(session, row), [255, 0, 0, 255]);
  });

  testWidgets('the new picture stands where the old one stood — at the row\'s '
      'reference fx, over its own pixels (I-68)', (tester) async {
    final (:session, :row, :next) = await open(
      tester,
      size: (width: 16, height: 8),
    );
    final top = (
      x: session.requireActiveCut.canvasSize.width ~/ 2,
      y: 2,
    );
    expect(
      pixelAt(session, row, top.x, top.y),
      clear,
      reason: 'premise: a wide picture placed to fit leaves the top open',
    );

    await dragOnto(tester, row, next);
    await settle(tester, () => pointsAt(session, row, next));

    expect(centre(session, row), [0, 0, 255, 255]);
    expect(pixelAt(session, row, top.x, top.y), clear);
  });

  testWidgets('a CARRIED file swaps in from the project\'s own copy — its '
      'original gone', (tester) async {
    final (:session, :row, :next) = await open(tester, carryNext: true);

    await dragOnto(tester, row, next);
    await settle(tester, () => pointsAt(session, row, next));

    expect(centre(session, row), [0, 0, 255, 255]);
  });

  testWidgets('a movie does not stand where a still stands: no silhouette, '
      'and letting go changes nothing', (tester) async {
    final (:session, :row, :next) = await open(
      tester,
      next: 'take.mp4',
      nextBytes: standInMovieBytes,
    );

    final silhouette = await dragOnto(tester, row, next);
    await tester.pumpAndSettle();

    expect(silhouette, isNull);
    expect(find.byType(ImportDialog), findsNothing);
    expect(session.layerById(row.id), row);
  });

  testWidgets('a file that will not read changes nothing and says so', (
    tester,
  ) async {
    final (:session, :row, :next) = await open(
      tester,
      next: 'broken.png',
      nextBytes: const [1, 2, 3, 4],
    );
    // Named as the pool names it (F-376).
    const said = 'broken: could not read the file.';

    await dragOnto(tester, row, next);
    await settle(tester, () => find.text(said).evaluate().isNotEmpty);

    expect(find.text(said), findsOneWidget);
    expect(session.layerById(row.id), row);
    expect(centre(session, row), [255, 0, 0, 255]);
  });

  // ⓐ (I-68 「가」, 유저 2026-10-10 「추천대로가자」): a swap keeps the
  // number of the picture a cel shows, as a move of the fx does.
  testWidgets('🎯a still that is a GIF\'s 2nd frame looks for the 2nd picture '
      'of what is let go on it: a PNG has none, so nothing changes — and the '
      'drop says THAT, not that the file did not read', (tester) async {
    final (:session, :row, :next) = await open(tester, oldGifFrame: 1);
    expect(row.frames.single.filePicture, 1, reason: 'premise');
    const said = 'next: the file has no picture 2.';

    await dragOnto(tester, row, next);
    await settle(tester, () => find.text(said).evaluate().isNotEmpty);

    expect(find.text(said), findsOneWidget);
    expect(find.text('next: could not read the file.'), findsNothing);
    expect(session.layerById(row.id), row);
  });

  group('what a swap says', () {
    tearDown(() => AppText.settings.value = const AppLanguageSettings());

    test('nothing when the file came in or the row was left as it was — a '
        'row that changed while the file was read included; the file and '
        'why when it did not', () {
      final project = createDefaultProject();
      expect(
        referenceSwapWords(const ReferenceLaid(), '/w/bg.png', project),
        isNull,
      );
      expect(
        referenceSwapWords(const ReferenceLeftAlone(), '/w/bg.png', project),
        isNull,
        reason: '↩️it said 「could not read the file」',
      );
      expect(
        referenceSwapWords(const ReferenceUnreadable(), '/w/bg.png', project),
        AppText.strings.imUnreadable('bg.png'),
      );
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
        notationLanguage: AppLanguage.ko,
      );
      expect(
        referenceSwapWords(
          const ReferenceLacksPicture(1),
          '/w/bg.png',
          project,
        ),
        'bg.png: 이 파일에는 2번째 그림이 없습니다.',
        reason: 'counted from 1 where a person reads it',
      );
    });

    test('F-376: a file the pool holds is named as the pool names it — a '
        'name given in the pool, not the file\'s', () {
      final project = createDefaultProject().copyWith(
        mediaAssets: [
          MediaAsset(
            path: '/w/bg.png',
            name: '거리',
            kind: MediaAssetKind.image,
          ),
        ],
      );
      expect(
        referenceSwapWords(const ReferenceUnreadable(), '/w/bg.png', project),
        AppText.strings.imUnreadable('거리'),
      );
      expect(
        referenceSwapWords(
          const ReferenceLacksPicture(0),
          '/w/bg.png',
          project,
        ),
        AppText.strings.imLacksPicture('거리', 1),
      );
    });

    test('every language names the file and the picture it lacks', () {
      for (final language in AppLanguage.values) {
        final words = AppStrings.of(language).imLacksPicture('bg.png', 7);
        expect(
          words,
          allOf(contains('bg.png'), contains('7')),
          reason: '$language',
        );
        expect(words, isNot(contains('{')), reason: '$language');
      }
    });
  });

  testWidgets('the swap tidies up as every edit that moves the document does '
      '— a frame range goes, as the swap\'s undo takes it — and leaves the '
      'standing to the door', (tester) async {
    final (:session, :row, :next) = await open(tester);
    final other = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.id != row.id,
    );
    session.selectLayer(other.id);
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: other.id,
      startIndex: 0,
      endIndexExclusive: 1,
    );

    final swapped = await tester.runAsync(
      () => session.importDoors.swapReference(layerId: row.id, path: next),
    );
    await tester.pumpAndSettle();

    expect(swapped, isA<ReferenceLaid>());
    expect(session.frameRangeSelection.value, isNull);
    expect(session.activeLayerId, other.id);
  });

  testWidgets('a row that changes while its new picture is read is left as it '
      'is — the swap was aimed at the row as it stood', (tester) async {
    final (:session, :row, :next) = await open(tester);

    final swapped = await tester.runAsync(() async {
      final swapping = session.importDoors.swapReference(
        layerId: row.id,
        path: next,
      );
      session.layerVerbs.renameLayer(row.id, 'renamed');
      return swapping;
    });
    await tester.pumpAndSettle();

    expect(swapped, isA<ReferenceLeftAlone>());
    expect(pointsAt(session, row, row.mediaReference!.assetPath), isTrue);
    expect(centre(session, row), [255, 0, 0, 255]);
  });

  group('a movie reference row', () {
    const takeRow = LayerId('take-row');

    /// [path] from its 4th frame on, standing where its reference fx says —
    /// a pose of its own, which no fit of the canvas would give.
    MediaReference shows(String path) => MediaReference(
      assetPath: path,
      frameOffset: 3,
      pose: TransformPose(
        center: CanvasPoint(x: 700, y: 500),
        scaleX: 1.5,
        scaleY: 1.5,
        rotationDegrees: 10,
      ),
      pictureSize: const CanvasSize(width: 640, height: 360),
    );

    Layer movieRow(String path) => Layer(
      id: takeRow,
      name: 'take',
      frames: [
        Frame(id: const FrameId('take-cel'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('take-cel'), length: 6),
      },
      mediaReference: shows(path),
    );

    testWidgets('takes a movie let go on it — the reference is all that '
        'moves, where in the file it starts and where it stands included — '
        'and nothing else', (tester) async {
      debugVideoDecodeBackend = FakeVideoBackend(width: 1280, height: 720);
      addTearDown(() => debugVideoDecodeBackend = null);
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.repository.insertLayer(
        cutId: session.requireActiveCut.id,
        layer: movieRow('/work/take1.mp4'),
      );

      expect(
        session.dropSpotFor(takeRow, 2, '/work/take2.mp4'),
        const ReferenceSwapSpot(takeRow),
      );
      expect(session.dropSpotFor(takeRow, 2, '/work/still.png'), isNull);
      expect(
        await session.importDoors.swapReference(
          layerId: takeRow,
          path: '/work/still.png',
        ),
        isA<ReferenceLeftAlone>(),
        reason: 'the door asks the same question the drop does',
      );

      final swapped = await tester.runAsync(
        () => session.importDoors.swapReference(
          layerId: takeRow,
          path: '/work/take2.mp4',
        ),
      );

      expect(swapped, isA<ReferenceLaid>());
      expect(
        session.layerById(takeRow)!.mediaReference,
        shows('/work/take2.mp4').copyWith(
          pictureSize: const CanvasSize(width: 1280, height: 720),
        ),
        reason:
            'the same pose over the new movie\'s own frame — I-68: '
            '「해상도가 달라도 같은크기로 겹치지않게」',
      );
      session.historyManager.undo();
      expect(
        session.layerById(takeRow)!.mediaReference,
        shows('/work/take1.mp4'),
      );
      // The edit's own settling timers, run out on the test's clock.
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a movie that does not open is a file that does not read — '
        'nothing changes, and the drop says so', (tester) async {
      debugVideoDecodeBackend = FakeVideoBackend(
        refusal: 'could not open the container',
      );
      addTearDown(() => debugVideoDecodeBackend = null);
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.repository.insertLayer(
        cutId: session.requireActiveCut.id,
        layer: movieRow('/work/take1.mp4'),
      );
      final row = session.layerById(takeRow);

      final answer = await tester.runAsync(
        () => session.importDoors.swapReference(
          layerId: takeRow,
          path: '/work/take2.mp4',
        ),
      );

      expect(answer, isA<ReferenceUnreadable>());
      expect(session.layerById(takeRow), row);
      expect(
        referenceSwapWords(
          answer!,
          '/work/take2.mp4',
          session.repository.requireProject(),
        ),
        AppText.strings.imUnreadable('take2.mp4'),
      );
    });
  });
}
