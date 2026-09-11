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
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show createDefaultCut;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

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
      'file name as the dialogue and its clip linked — and one undo takes '
      'block, clip and pool entry back', (tester) async {
    final s = session();
    final start = s.activeCutGlobalStartFrame;
    final fps = s.projectSettings.projectFps;

    expect(await place(tester, s), isTrue);

    final s1 = s.activeTrack.seLayers.first;
    final block = s1.timeline[start];
    expect(block?.length, fps, reason: 'a one-second sound, whole');
    final frame = s1.frameById(block!.frameId!)!;
    expect((frame.name, frame.seName), ('door.wav', 'SE'));
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
}
