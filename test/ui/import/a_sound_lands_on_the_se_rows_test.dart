import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show createDefaultCut;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/placed_sound_conform.dart';

/// 🚨A SOUND ON THE TIMELINE GOES TO THE SE ROWS (유저 2026-09-11, 미디어 배치
/// 라운드 6: 「SE1부터 시작해서 뒤든 앞이든 겹치지 않는, 공간이 존재하는
/// 기존 SE행에 넣으려 하고, 없으면 새 SE행 … 블록의 이름을 SE, 대사를 파일
/// 이름(확장자포함)으로」 — and 「소리파일: 추천대로 통일」: the import menu,
/// the canvas and the layer area all place a sound this way).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-sound-rows');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly.
    }
  });

  /// [seconds] of a quiet tone, written as the conform's own WAV.
  Future<String> writeSound(String name, double seconds) async {
    const rate = 48000;
    final samples = Float32List((rate * seconds).round());
    for (var i = 0; i < samples.length; i += 1) {
      samples[i] = 0.2 * math.sin(i / 20);
    }
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(
      encodeConform(samples: samples, channels: 1, sampleRate: rate),
    );
    return file.path;
  }

  // A second of sound, answered without the isolate a widget test cannot
  // run.
  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    return s;
  }

  /// [row] holding one block from [start] for [length] frames.
  void occupy(EditorSessionManager s, Layer row, int start, int length) {
    final id = FrameId('held-${row.id.value}');
    s.repository.replaceLayer(
      layer: row.copyWith(
        frames: [Frame(id: id, duration: 1, strokes: const [])],
        timeline: {start: TimelineExposure.drawing(id, length: length)},
      ),
    );
  }

  Future<bool?> place(
    WidgetTester tester,
    EditorSessionManager s, {
    int inFrame = 0,
    int? outFrame,
  }) => tester.runAsync(() async {
    final path = await writeSound('door.wav', 1);
    return s.importDoors.importSoundFile(
      path: path,
      copyIntoProject: false,
      inFrame: inFrame,
      outFrame: outFrame,
    );
  });

  testWidgets('a sound lands on S1 from the cut start, tagged 「SE」 with its '
      'name — the file\'s, without the extension — as the dialogue and its '
      'clip linked — and one undo takes block, clip and pool entry back', (
    tester,
  ) async {
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    final fps = s.projectSettings.projectFps;

    expect(await place(tester, s), isTrue);

    final s1 = s.activeTrack.seLayers.first;
    final block = s1.timeline[start];
    expect(block?.length, fps, reason: 'a one-second sound, whole');
    final frame = s1.frameById(block!.frameId!)!;
    expect((frame.name, frame.seName), ('door', 'SE'));
    expect(s1.audioClips.single.frameId, frame.id);
    expect(s.mediaPool.mediaAssets.single.kind, MediaAssetKind.audio);

    s.undo();
    expect(s.activeTrack.seLayers.first.timeline[start], isNull);
    expect(s.mediaPool.mediaAssets, isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('S1 taken where it would start: the sound goes to S2 — SE1 '
      'first, then in order', (tester) async {
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    occupy(s, s.activeTrack.seLayers[0], start, 200);

    expect(await place(tester, s), isTrue);

    expect(s.activeTrack.seLayers[1].timeline[start], isNotNull);
    await tester.pumpAndSettle();
  });

  testWidgets('every row taken: a NEW row after the last, named by the '
      'S-rule — and undo takes the row away again', (tester) async {
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    final rows = s.activeTrack.seLayers;
    for (final row in rows) {
      occupy(s, row, start, 200);
    }
    final names = [for (final row in rows) row.name];

    expect(await place(tester, s), isTrue);

    final after = s.activeTrack.seLayers;
    expect(after, hasLength(rows.length + 1));
    expect(names, isNot(contains(after.last.name)));
    expect(after.last.timeline[start], isNotNull);

    s.undo();
    expect(s.activeTrack.seLayers, hasLength(rows.length));
    await tester.pumpAndSettle();
  });

  testWidgets('the window\'s IN/OUT trims it: the in point is where in the '
      'file the sound starts, the span is the block', (tester) async {
    final s = session();
    final start = s.activeCutGlobalStartFrame;

    expect(await place(tester, s, inFrame: 2, outFrame: 5), isTrue);

    final s1 = s.activeTrack.seLayers.first;
    expect(s1.timeline[start]?.length, 4);
    expect(s1.audioClips.single.offsetFrames, 2);
    await tester.pumpAndSettle();
  });

  testWidgets('in the WINDOW the sound runs over its own frames, and '
      'shortening its IN/OUT there shortens the block (「거기서 가져올 구간을 '
      '줄이면 블록도 그만큼 줄어든다」)', (tester) async {
    final path = await tester.runAsync(() => writeSound('door.wav', 1));
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImportDialog(session: s, initialPaths: [path!])),
      ),
    );
    TransportBar bar() =>
        tester.widget<TransportBar>(find.byType(TransportBar));
    for (var tries = 0; tries < 60 && bar().frameCount == 1; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final peaks = await tester.runAsync(
      () => s.audioConformStore.ensurePeaksFor(path),
    );
    expect(
      bar().frameCount,
      peaks!.durationFrames(s.projectSettings.projectFrameRate),
    );
    expect(bar().showRange, isTrue);

    bar().onRangeChanged(2, 5);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    for (var tries = 0; tries < 60; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (s.activeTrack.seLayers.first.timeline[start] != null) {
        break;
      }
    }

    final s1 = s.activeTrack.seLayers.first;
    expect(s1.timeline[start]?.length, 4);
    expect(s1.audioClips.single.offsetFrames, 2);
    await tester.pumpAndSettle();
  });

  testWidgets('with the SECOND cut open the sound starts at that cut\'s start '
      'on the track — the SE rows are the track\'s, not the cut\'s', (
    tester,
  ) async {
    final s = session();
    final first = s.requireActiveCut;
    final second = createDefaultCut(
      cutId: const CutId('sound-second-cut'),
      name: '2',
      layerId: const LayerId('sound-second-cut-layer'),
      canvasSize: first.canvasSize,
    );
    s.repository.insertCut(trackId: s.activeTrack.id, cut: second);
    s.selectCut(second.id);
    final start = s.activeCutGlobalStartFrame;
    expect(start, first.duration, reason: 'the premise: it starts after cut 1');

    expect(await place(tester, s), isTrue);

    final s1 = s.activeTrack.seLayers.first;
    expect(s1.timeline[start], isNotNull);
    expect(s1.timeline[0], isNull, reason: 'not at the track\'s start');
    await tester.pumpAndSettle();
  });

  testWidgets('in the window a sound\'s Into is the SE rows, locked, and it '
      'asks no fit — pressing Import lands it on S1', (tester) async {
    final path = await tester.runAsync(() => writeSound('door.wav', 1));
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImportDialog(session: s, initialPaths: [path!])),
      ),
    );
    await tester.pump();

    final into = find.byKey(ValueKey<String>('import-cell-into-$path'));
    expect(
      tester
          .widget<Text>(find.descendant(of: into, matching: find.byType(Text)))
          .data,
      AppText.strings.imIntoSeRow,
    );
    expect(
      find.byKey(const ValueKey<String>('import-column-fit')),
      findsNothing,
      reason: 'only a sound in the batch: no fit to ask',
    );

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    for (var tries = 0; tries < 60; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (s.activeTrack.seLayers.first.timeline[start] != null) {
        break;
      }
    }
    expect(s.activeTrack.seLayers.first.timeline[start], isNotNull);
    await tester.pumpAndSettle();
  });

  group('a sound let go on an SE row\'s EMPTY CELL (「SE 행의 빈 칸 → 새 '
      '블록」)', () {
    testWidgets('the drop names a sound\'s spot on an SE row and nothing else '
        'there — and a picture row keeps its own answer', (tester) async {
      final s = session();
      final se = s.activeTrack.seLayers.first;
      final picture = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      expect(
        s.dropSpotFor(se.id, 5, 'door.wav'),
        SeCellSpot(
          layerId: se.id,
          trackFrame: s.activeCutGlobalStartFrame + 5,
          shownCell: 5,
        ),
      );
      expect(s.dropSpotFor(se.id, 5, 'a.png'), isNull);
      expect(
        s.dropSpotFor(picture.id, 5, 'a.png'),
        RowFramesSpot(layerId: picture.id, frameIndex: 5),
      );
      expect(s.dropSpotFor(picture.id, 5, 'door.wav'), isNull);
    });

    testWidgets('it lands on THAT row from THAT cell, and the next block '
        'bounds its length', (tester) async {
      final s = session();
      final start = s.activeCutGlobalStartFrame;
      final s2 = s.activeTrack.seLayers[1];
      occupy(s, s2, start + 8, 4);

      final landed = await tester.runAsync(() async {
        final path = await writeSound('door.wav', 1);
        return s.importDoors.importSoundFile(
          path: path,
          copyIntoProject: false,
          spot: SeCellSpot(
            layerId: s2.id,
            trackFrame: start + 5,
            shownCell: 5,
          ),
        );
      });

      expect(landed, isTrue);
      expect(
        s.activeTrack.seLayers[1].timeline[start + 5]?.length,
        3,
        reason: 'up to the block at 8',
      );
      expect(s.activeTrack.seLayers.first.timeline[start + 5], isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('a cell a block already covers takes no new block', (
      tester,
    ) async {
      final s = session();
      final start = s.activeCutGlobalStartFrame;
      final s1 = s.activeTrack.seLayers.first;
      occupy(s, s1, start + 2, 6);

      final landed = await tester.runAsync(() async {
        final path = await writeSound('door.wav', 1);
        return s.importDoors.importSoundFile(
          path: path,
          copyIntoProject: false,
          spot: SeCellSpot(
            layerId: s1.id,
            trackFrame: start + 4,
            shownCell: 4,
          ),
        );
      });

      expect(landed, isFalse);
      expect(s.mediaPool.mediaAssets, isEmpty);
    });

    testWidgets('with the SECOND cut open the cell is that cut\'s — the row '
        'is the track\'s', (tester) async {
      final s = session();
      final first = s.requireActiveCut;
      final second = createDefaultCut(
        cutId: const CutId('cell-second-cut'),
        name: '2',
        layerId: const LayerId('cell-second-cut-layer'),
        canvasSize: first.canvasSize,
      );
      s.repository.insertCut(trackId: s.activeTrack.id, cut: second);
      s.selectCut(second.id);
      final start = s.activeCutGlobalStartFrame;
      expect(
        start,
        first.duration,
        reason: 'the premise: it starts after cut 1',
      );
      final s1 = s.activeTrack.seLayers.first;

      final landed = await tester.runAsync(() async {
        final path = await writeSound('door.wav', 1);
        return s.importDoors.importSoundFile(
          path: path,
          copyIntoProject: false,
          // The cut-local cell becomes a track frame where the spot is
          // made — the timeline's own drop verb, not a hand-built spot.
          spot: s.dropSpotFor(s1.id, 3, path),
        );
      });

      expect(landed, isTrue);
      expect(s.activeTrack.seLayers.first.timeline[start + 3], isNotNull);
      expect(
        s.activeTrack.seLayers.first.timeline[3],
        isNull,
        reason: 'not cell 3 of the track',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('the window names the row and the cell, locked', (
      tester,
    ) async {
      final path = await tester.runAsync(() => writeSound('door.wav', 1));
      final s = session();
      // Not the first row: the label names THIS row.
      final s2 = s.activeTrack.seLayers[1];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: [path!],
              placeOnly: true,
              spot: SeCellSpot(layerId: s2.id, trackFrame: 5, shownCell: 5),
            ),
          ),
        ),
      );
      await tester.pump();

      final into = find.byKey(ValueKey<String>('import-cell-into-$path'));
      expect(
        tester
            .widget<Text>(
              find.descendant(of: into, matching: find.byType(Text)),
            )
            .data,
        AppText.strings.imIntoRowCell(s2.name, 6),
      );
    });

    testWidgets('a cell on a row this track does not have is refused before '
        'anything is read', (tester) async {
      final s = session();
      final s1 = s.activeTrack.seLayers.first;

      expect(
        s.importLanding.arriveOnSeRows(
          path: 'door.wav',
          spot: const SeCellSpot(
            layerId: LayerId('elsewhere'),
            trackFrame: 0,
            shownCell: 0,
          ),
        ),
        isNull,
      );
      expect(
        s.importLanding.arriveOnSeRows(
          path: 'door.wav',
          spot: SeCellSpot(layerId: s1.id, trackFrame: 0, shownCell: 0),
        ),
        isNotNull,
      );
    });
  });

  group('on the STORYBOARD an SE row\'s empty cell is the track\'s — between '
      'cuts too (유저 2026-09-12: 「타임라인이랑 같은 법으로」)', () {
    /// Two cuts with a 20-frame gap between them, the playhead parked in it.
    EditorSessionManager gapped() {
      final s = session();
      final first = s.requireActiveCut;
      s.repository.insertCut(
        trackId: s.activeTrack.id,
        cut: createDefaultCut(
          cutId: const CutId('after-the-gap'),
          name: '2',
          layerId: const LayerId('after-the-gap-layer'),
          canvasSize: first.canvasSize,
        ).copyWith(leadingGapFrames: 20),
      );
      s.selectGlobalFrame(first.duration + 5);
      expect(
        s.activeCutOrNull,
        isNull,
        reason: 'fixture premise: parked in the gap',
      );
      return s;
    }

    int gapFrameOf(EditorSessionManager s) =>
        s.repository.requireProject().tracks.first.cuts.first.duration + 5;

    testWidgets('the storyboard names the cell by its track frame, and only a '
        'sound lands there', (tester) async {
      final s = gapped();
      final s1 = s.activeTrack.seLayers.first;
      final frame = gapFrameOf(s);
      s.playbackRig.prerenderScheduler.cancel();

      expect(
        s.storyboardDropSpotFor(LayerRowAddress(s1.id), frame, 'door.wav'),
        SeCellSpot(layerId: s1.id, trackFrame: frame, shownCell: frame),
      );
      expect(
        s.storyboardDropSpotFor(LayerRowAddress(s1.id), frame, 'a.png'),
        isNull,
      );
    });

    testWidgets('a sound let go there lands with no cut in hand', (
      tester,
    ) async {
      final s = gapped();
      final s1 = s.activeTrack.seLayers.first;
      final frame = gapFrameOf(s);

      final landed = await tester.runAsync(() async {
        final path = await writeSound('door.wav', 1);
        return s.importDoors.importSoundFile(
          path: path,
          copyIntoProject: false,
          spot: s.storyboardDropSpotFor(LayerRowAddress(s1.id), frame, path),
        );
      });
      s.playbackRig.prerenderScheduler.cancel();

      expect(landed, isTrue);
      expect(s.activeTrack.seLayers.first.timeline[frame], isNotNull);
      expect(s.activeCutOrNull, isNull, reason: 'nothing moved the playhead');
      await tester.pumpAndSettle();
    });
  });
}
