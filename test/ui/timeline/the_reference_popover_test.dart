// THE REFERENCE POPOVER (유저 2026-09-11, 미디어 배치 라운드 3~6): the file
// button does not bake — it opens this. Its first line is the file beside
// its POOL state, or 「선택한 레이어」 when the press acts on several rows.
// And the rasterize of reference rows its one button ran — the reference
// header's RASTERIZE's now (I-120-Q11 「하나만 남기도록」): a movie decoded
// behind the wait window, one bar for the batch, as ONE undo.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/media/media_asset_pool_state.dart';
import 'package:anicel/src/ui/timeline/layer_reference_popover.dart';
import 'package:anicel/src/ui/timeline/rasterize_reference_rows.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-reference-pop');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A session with one linked reference row per file, by file name.
  Future<(EditorSessionManager, Map<String, LayerId>)> sessionWith(
    WidgetTester tester,
    List<String> files,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final rows = <String, LayerId>{};
    await tester.runAsync(() async {
      for (final name in files) {
        await s.importDoors.importImageFile(
          path: await writeSolidPng(tempDir, name),
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
        );
        rows[name] = s.requireActiveCut.layers
            .firstWhere(
              (layer) =>
                  layer.mediaReference != null &&
                  !rows.containsValue(layer.id),
            )
            .id;
      }
    });
    return (s, rows);
  }

  Layer current(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  Future<void> openOn(
    WidgetTester tester,
    EditorSessionManager s,
    LayerId pressed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLayerReferencePopover(
                context,
                session: s,
                layerId: pressed,
              ),
              child: const Text('file button'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('file button'));
    await tester.pumpAndSettle();
    expect(popover, findsOneWidget, reason: 'the premise: it opened');
  }

  String sourceLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('layer-reference-source')))
      .data!;

  /// A session with a [frameCount]-frame take placed as a reference from
  /// [inFrame] — its block is what is left of the file — and the playback
  /// warmer held, so the only decoding is the bake's own.
  Future<(EditorSessionManager, LayerId)> movieSession(
    WidgetTester tester, {
    int frameCount = 24,
    int inFrame = 4,
  }) async {
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: frameCount);
    addTearDown(() => debugVideoDecodeBackend = null);
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    await tester.runAsync(() async {
      final path = '${tempDir.path}${Platform.pathSeparator}take.mov';
      await File(path).writeAsBytes(standInMovieBytes);
      await s.importDoors.importVideoFile(
        path: path,
        settings: ImportFileSettings(
          mode: ImportFileMode.reference,
          movieParts: MovieParts.picture,
          inFrame: inFrame,
        ),
      );
    });
    return (s, s.requireActiveCut.layers.firstWhere(isMovieReference).id);
  }

  final shortLine = find.byKey(
    const ValueKey<String>('layer-reference-source-short'),
  );

  /// Lets the hydrator OPEN the cut's movie rows and answer what they are —
  /// the decoder's frame count is what the warning line counts against, and
  /// it lands asynchronously.
  Future<void> learnTheFile(WidgetTester tester, EditorSessionManager s) async {
    await tester.runAsync(() => s.movieCels.hydrate(s.requireActiveCut, 0));
    await tester.pump();
  }

  testWidgets('⛔a row its file can cover says nothing, and the window is '
      'the plain one — the premise', (tester) async {
    final (s, rowId) = await movieSession(tester, frameCount: 24, inFrame: 4);
    await learnTheFile(tester, s);

    await openOn(tester, s, rowId);
    expect(shortLine, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('🚨a row dragged PAST the end of its file says by how much, as '
      'one more item of the popover the red button opens (유저 2026-09-12: '
      '「팝오버 항목중 하나로 내용 띄우도록」)', (tester) async {
    final (s, rowId) = await movieSession(tester, frameCount: 24, inFrame: 4);
    // The TAIL edge is deliberately uncapped where the head is capped by the
    // in point ([clampExposureEdgeDelta]), so this is how a row comes to ask
    // for film its file does not hold — a placed take that was 20 frames
    // becomes 26, and the last 6 have nothing behind them.
    s.activeCutControllers.timelineController.shiftExposureEdge(
      layerId: rowId,
      blockStartIndex: 0,
      edge: TimelineBlockEdge.end,
      delta: 6,
    );
    await learnTheFile(tester, s);

    await openOn(tester, s, rowId);
    expect(shortLine, findsOneWidget);
    expect(
      tester.widget<Text>(shortLine).data,
      'Runs 6 frames past the source',
      reason: 'the number is project frames, the unit the row is drawn in',
    );
    // 🚨THE PIN IS OVERFLOW, NOT A NUMBER. What can actually go wrong is a
    // window sized without the line and then asked to draw it; a hand-copied
    // pixel count would only ever re-state the constant back to itself.
    expect(
      tester.takeException(),
      isNull,
      reason: '자리는 예약하고 내용만 바꾼다 — the window made room for it',
    );
  });

  /// The decode runs in `runAsync`; its answers land on the pumps after —
  /// which carry the clock too, so the window's own timers run out.
  Future<void> settle(WidgetTester tester, bool Function() done) =>
      settleAsync(tester, done, step: const Duration(milliseconds: 20));

  testWidgets('one row: its file beside its POOL state '
      '(「bg_street.png · 참조」)', (tester) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    await openOn(tester, s, rows['bg_street.png']!);

    final asset = s.mediaPool.mediaAssets.single;
    expect(asset.name, contains('bg_street'), reason: 'the premise');
    expect(
      sourceLine(tester),
      '${asset.name} · Linked',
      reason: 'linked, not carried — the file stayed where it was',
    );
  });

  testWidgets('pressed INSIDE the selection it speaks of every selected '
      'reference row — 「선택한 레이어」', (tester) async {
    final (s, rows) = await sessionWith(tester, [
      'bg_street.png',
      'bg_night.png',
    ]);
    final street = rows['bg_street.png']!;
    final night = rows['bg_night.png']!;
    s.rowSelection.value = [LayerRowAddress(street), LayerRowAddress(night)];
    await openOn(tester, s, street);

    expect(sourceLine(tester), 'Selected layers');
  });

  testWidgets('a selected row that points at NO file is not one of them — '
      'one file, so the line names it', (tester) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    final street = rows['bg_street.png']!;
    final plain = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.mediaReference == null,
    );
    s.rowSelection.value = [LayerRowAddress(street), LayerRowAddress(plain.id)];
    await openOn(tester, s, street);

    expect(sourceLine(tester), endsWith(' · Linked'));
  });

  testWidgets('pressed OUTSIDE the selection it names that row alone', (
    tester,
  ) async {
    final (s, rows) = await sessionWith(tester, [
      'bg_street.png',
      'bg_night.png',
    ]);
    final street = rows['bg_street.png']!;
    final night = rows['bg_night.png']!;
    s.rowSelection.value = [LayerRowAddress(night)];
    await openOn(tester, s, street);

    expect(sourceLine(tester), contains('bg_street'));
  });

  /// A context under an app, for a verb that puts a window up.
  Future<BuildContext> hostedContext(WidgetTester tester) async {
    late BuildContext hosted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hosted = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return hosted;
  }

  testWidgets('rasterizing a movie puts the decode behind the WAIT WINDOW, '
      'and the row comes back as cels', (tester) async {
    final (s, movie) = await movieSession(tester, frameCount: 6, inFrame: 0);
    final menuContext = await hostedContext(tester);

    // ⛔Not awaited HERE: the decode needs the pumps below to run, and a
    // test body waiting on it is a test body not pumping.
    unawaited(rasterizeReferenceRows(menuContext, s, [current(s, movie)]));
    await tester.pump();
    expect(
      waitWindow,
      findsOneWidget,
      reason: 'the one window heavy work waits behind',
    );

    await settle(
      tester,
      () =>
          waitWindow.evaluate().isEmpty &&
          current(s, movie).mediaReference == null,
    );
    expect(current(s, movie).frames, hasLength(6));
    await tester.pumpAndSettle();
  });

  testWidgets('two rows baked in one press fill ONE bar — each its own half, '
      'the second from where the first ends', (tester) async {
    final (s, _) = await movieSession(tester, frameCount: 6, inFrame: 0);
    await tester.runAsync(() async {
      final path = '${tempDir.path}${Platform.pathSeparator}second.mov';
      await File(path).writeAsBytes(standInMovieBytes);
      await s.importDoors.importVideoFile(
        path: path,
        settings: const ImportFileSettings(
          mode: ImportFileMode.reference,
          movieParts: MovieParts.picture,
        ),
      );
    });
    final rows = [
      for (final layer in s.requireActiveCut.layers)
        if (isMovieReference(layer)) layer.id,
    ];
    expect(rows, hasLength(2), reason: 'the premise: two takes placed');
    final menuContext = await hostedContext(tester);

    final told = watchTheBar(tester);
    unawaited(
      rasterizeReferenceRows(menuContext, s, [
        for (final row in rows) current(s, row),
      ]),
    );
    await settle(
      tester,
      () =>
          waitWindow.evaluate().isEmpty &&
          rows.every((row) => current(s, row).mediaReference == null),
    );

    // Six cels a row: the first row's third is a quarter of the bar.
    expectOneBar(told, [0.25, 0.5, 0.75, 1]);
    await tester.pumpAndSettle();
  });

  /// [rowId]'s paper squashed by its own transform under a [turn] of its
  /// fx's — a move the row's transform cannot carry (F-374-Q7 ③).
  void sheared(
    EditorSessionManager s,
    LayerId rowId,
    PropertyTrack<double> turn,
  ) => s.cutCommandCoordinator
    ..updateLayerTransformTrack(
      cutId: s.requireActiveCut.id,
      layerId: rowId,
      transformTrack: TransformTrack.empty().copyWith(
        scale: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 1, y: 0.5),
        ),
      ),
    )
    ..updateLayerReferenceFx(
      layerId: rowId,
      fx: TransformTrack.empty().copyWith(rotation: turn),
    );

  testWidgets('a still its transform cannot carry the move of goes behind '
      'the window too, and comes back baked in its own cel (F-374-Q7)', (
    tester,
  ) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    final street = rows['bg_street.png']!;
    sheared(s, street, PropertyTrack<double>().withKey(0, 30));
    final cel = current(s, street).frames.single.id;
    final menuContext = await hostedContext(tester);

    unawaited(rasterizeReferenceRows(menuContext, s, [current(s, street)]));
    await tester.pump();
    expect(waitWindow, findsOneWidget);

    await settle(
      tester,
      () =>
          waitWindow.evaluate().isEmpty &&
          current(s, street).mediaReference == null,
    );
    expect(current(s, street).mediaReference, isNull);
    expect(current(s, street).frames.single.id, cel, reason: 'in place');
    await tester.pumpAndSettle();
  });

  testWidgets('🎯a still its fx MOVES where its transform cannot carry it '
      'goes behind the window and comes back an animation layer — a cel '
      'wherever the move changes, the first with its cel\'s name — as ONE '
      'undo (I-120-Q5: 「애니메이션 레이어로, 움직이는 프레임마다 한 장」)', (
    tester,
  ) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    final street = rows['bg_street.png']!;
    sheared(
      s,
      street,
      PropertyTrack<double>().withKey(0, 30).withKey(12, 60),
    );
    final before = current(s, street);
    final length = drawingBlocks(
      before.timeline,
    ).fold(0, (sum, block) => sum + block.length);
    expect(length, greaterThan(13), reason: 'the premise');
    final menuContext = await hostedContext(tester);

    unawaited(rasterizeReferenceRows(menuContext, s, [before]));
    await tester.pump();
    expect(waitWindow, findsOneWidget);

    await settle(
      tester,
      () =>
          waitWindow.evaluate().isEmpty &&
          current(s, street).mediaReference == null,
    );
    final baked = current(s, street);
    expect(baked.kind, LayerKind.animation);
    // A turn a frame over 0..12, then held: thirteen pictures.
    expect(baked.frames, hasLength(13));
    expect(baked.frames.first.name, before.frames.single.name);
    expect(
      [
        for (var frame = 0; frame < length; frame += 1)
          exposedFrameIdAt(baked.timeline, frame),
      ],
      [
        for (final cel in baked.frames) cel.id,
        for (var at = 13; at < length; at += 1) baked.frames.last.id,
      ],
    );

    s.undo();
    expect(current(s, street), before);
    await tester.pumpAndSettle();
  });

  testWidgets('🎯a 겸용 copy no key carries the move of, showing the picture '
      'elsewhere, goes behind the window with its row — each use its own '
      'cel, an animation layer — as ONE undo (🗣️I-120-Q22 「링크를 둔 채 '
      '셀을 나눠 굽는다」 — ↩️F-374-Q11 left it a reference and said why)', (
    tester,
  ) async {
    final (s, rows) = await sessionWith(tester, ['bg_street.png']);
    final street = rows['bg_street.png']!;
    final copy = s.cutCommandCoordinator.linkDuplicateLayer(
      cutId: s.requireActiveCut.id,
      layerId: street,
      insertionIndex: 0,
    );
    sheared(s, copy, PropertyTrack<double>().withKey(0, 30));
    final before = [current(s, street), current(s, copy)];
    final menuContext = await hostedContext(tester);

    unawaited(rasterizeReferenceRows(menuContext, s, [before.first]));
    await tester.pump();
    expect(waitWindow, findsOneWidget);

    await settle(
      tester,
      () =>
          waitWindow.evaluate().isEmpty &&
          current(s, street).mediaReference == null,
    );
    final baked = current(s, street);
    final bakedCopy = current(s, copy);
    expect(bakedCopy.mediaReference, isNull);
    expect([baked.kind, bakedCopy.kind], [
      LayerKind.animation,
      LayerKind.animation,
    ]);
    expect(baked.frames, hasLength(2));
    expect(
      exposedFrameIdAt(baked.timeline, 0),
      isNot(exposedFrameIdAt(bakedCopy.timeline, 0)),
    );

    s.undo();
    expect([current(s, street), current(s, copy)], before);
    await tester.pumpAndSettle();
  });

  testWidgets('🎯rows of one press — one its transform carries, two baked '
      'behind the window — come back with ONE undo (I-120 ⑥-③: two rows '
      'baked, three undos)', (tester) async {
    final (s, rows) = await sessionWith(tester, [
      'bg_street.png',
      'bg_night.png',
      'bg_park.png',
    ]);
    final pressed = [
      rows['bg_street.png']!,
      rows['bg_night.png']!,
      rows['bg_park.png']!,
    ];
    for (final row in pressed.skip(1)) {
      sheared(s, row, PropertyTrack<double>().withKey(0, 30).withKey(4, 60));
    }
    final before = [for (final row in pressed) current(s, row)];
    final menuContext = await hostedContext(tester);

    unawaited(rasterizeReferenceRows(menuContext, s, before));
    await settle(
      tester,
      () =>
          waitWindow.evaluate().isEmpty &&
          pressed.every((row) => current(s, row).mediaReference == null),
    );
    expect(
      current(s, pressed.last).kind,
      LayerKind.animation,
      reason: '⛔premise: a moving row was baked a cel a frame',
    );

    s.undo();
    expect([for (final row in pressed) current(s, row)], before);
    await tester.pumpAndSettle();
  });

  test('the pool state is where the file\'s bytes live — carried or linked',
      () {
    final linked = MediaAsset(
      path: 'bg.png',
      name: 'bg.png',
      kind: MediaAssetKind.image,
    );
    expect(mediaAssetPoolState(linked), 'Linked');
    expect(
      mediaAssetPoolState(
        linked.copyWith(carriedAs: mediaCarryNamed(linked.path, 'c1')),
      ),
      'In the project',
    );
  });
}

final popover = find.byKey(const ValueKey<String>('layer-reference-popover'));

/// The one window heavy work waits behind, as a rasterize puts it up.
final waitWindow = find.byKey(
  const ValueKey<String>('reference-rasterize-progress'),
);
