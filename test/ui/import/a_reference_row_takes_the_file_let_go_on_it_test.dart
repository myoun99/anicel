import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

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

  /// The app with `old.png` placed as an image row that REFERENCES it — the
  /// placement window's reference road — and `next` in the pool, whose
  /// panel is open. [next] names the pool file; [nextBytes] replaces what a
  /// solid blue picture would write there.
  Future<({EditorSessionManager session, Layer row, String next})> open(
    WidgetTester tester, {
    String next = 'next.png',
    List<int>? nextBytes,
  }) async {
    final paths = (await tester.runAsync(() async {
      final old = await writeSolidPng(tempDir, 'old.png', rgba: red);
      final path = '${tempDir.path}${Platform.pathSeparator}$next';
      if (nextBytes == null) {
        await writeSolidPng(tempDir, next, rgba: blue);
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
              MediaAsset(
                path: paths.next,
                name: 'next',
                kind: mediaAssetKindForPath(paths.next) ?? MediaAssetKind.image,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 3)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final placed = await tester.runAsync(
      () => session.importDoors.importImageFile(
        path: paths.old,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
      ),
    );
    expect(placed, isTrue, reason: 'premise: the reference row is placed');
    await tester.pumpAndSettle();
    final row = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.mediaReference?.assetPath == paths.old,
    );
    return (session: session, row: row, next: paths.next);
  }

  /// The RGBA at the canvas centre of the picture the row's cel holds.
  List<int> centre(EditorSessionManager session, Layer row) {
    final cut = session.requireActiveCut;
    final surface = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      session.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
    )!;
    final x = cut.canvasSize.width ~/ 2;
    final y = cut.canvasSize.height ~/ 2;
    final size = surface.tileSize;
    final tile = surface.tiles.entries
        .firstWhere(
          (entry) => entry.key.x == x ~/ size && entry.key.y == y ~/ size,
        )
        .value;
    final at = ((y % size) * size + (x % size)) * 4;
    return tile.pixels.sublist(at, at + 4);
  }

  bool silhouetteShown(WidgetTester tester) => find
      .byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is TimelineSilhouettePainter,
      )
      .evaluate()
      .isNotEmpty;

  /// Drags [path]'s pool row onto the second cell of [row] and lets go —
  /// answering whether the silhouette stood there while it hovered.
  Future<bool> dragOnto(WidgetTester tester, Layer row, String path) async {
    final target = find.byKey(
      ValueKey<String>('timeline-layer-asset-drop-${row.id}'),
    );
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
    final shown = silhouetteShown(tester);
    await gesture.up();
    await tester.pump();
    return shown;
  }

  /// Lets the swap's read and bake land.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var tries = 0; tries < 100 && !done(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('🎯a still let go on a still reference row: the row shows it — '
      'at once, no window — with its name and its frames as they were, and '
      'ONE undo brings the old picture back', (tester) async {
    final (:session, :row, :next) = await open(tester);
    final old = row.mediaReference!.assetPath;
    expect(centre(session, row), [255, 0, 0, 255]);

    final silhouette = await dragOnto(tester, row, next);
    await settle(
      tester,
      () => session.layerById(row.id)!.mediaReference!.assetPath == next,
    );

    expect(silhouette, isTrue, reason: '「끄는 동안 행 위에 바뀔 블록이 실루엣」');
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
    expect(session.layerById(row.id)!.mediaReference!.assetPath, old);
    expect(centre(session, row), [255, 0, 0, 255]);
  });

  testWidgets('a movie does not stand where a still stands: no silhouette, '
      'and letting go changes nothing', (tester) async {
    final (:session, :row, :next) = await open(tester, next: 'take.mp4',
        nextBytes: const [0, 0, 0, 24]);

    final silhouette = await dragOnto(tester, row, next);
    await tester.pumpAndSettle();

    expect(silhouette, isFalse);
    expect(find.byType(ImportDialog), findsNothing);
    expect(session.layerById(row.id), row);
  });

  testWidgets('a file that will not read changes nothing and says so', (
    tester,
  ) async {
    final (:session, :row, :next) = await open(tester, next: 'broken.png',
        nextBytes: const [1, 2, 3, 4]);

    await dragOnto(tester, row, next);
    await settle(tester, () => find.text('broken.png: could not read the '
        'file.').evaluate().isNotEmpty);

    expect(find.text('broken.png: could not read the file.'), findsOneWidget);
    expect(session.layerById(row.id), row);
    expect(centre(session, row), [255, 0, 0, 255]);
  });

  group('a movie reference row', () {
    Layer movieRow(String path) => Layer(
      id: const LayerId('take-row'),
      name: 'take',
      frames: [
        Frame(id: const FrameId('take-cel'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('take-cel'), length: 6),
      },
      mediaReference: MediaReference(assetPath: path, frameOffset: 3),
    );

    testWidgets('takes a movie let go on it — the reference is all that '
        'moves, where in the file it starts included', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.repository.insertLayer(
        cutId: session.requireActiveCut.id,
        layer: movieRow('/work/take1.mp4'),
      );

      expect(
        session.dropSpotFor(const LayerId('take-row'), 2, '/work/take2.mp4'),
        const ReferenceSwapSpot(LayerId('take-row')),
      );
      expect(
        session.dropSpotFor(const LayerId('take-row'), 2, '/work/still.png'),
        isNull,
      );

      final swapped = await session.importDoors.swapReference(
        layerId: const LayerId('take-row'),
        path: '/work/take2.mp4',
      );

      expect(swapped, isTrue);
      expect(
        session.layerById(const LayerId('take-row'))!.mediaReference,
        MediaReference(assetPath: '/work/take2.mp4', frameOffset: 3),
      );
      session.historyManager.undo();
      expect(
        session.layerById(const LayerId('take-row'))!.mediaReference,
        MediaReference(assetPath: '/work/take1.mp4', frameOffset: 3),
      );
      // The edit's own settling timers, run out on the test's clock.
      await tester.pump(const Duration(minutes: 1));
    });
  });
}
