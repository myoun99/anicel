import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/three_frame_gif.dart';
import '../../helpers/wait_window.dart';

/// 🚨A FILE THE POOL HOLDS IS PLACED WITH ITS PRESET (card 「파일마다 배치
/// 기본값」; 7월 29일 유저안: 「에셋 = 배치 기본값 / 인스턴스 = 실제 값」).
/// The window placing it starts the file's row from the preset — the span
/// and the fit — and a sound's block is born with the preset's name tag and
/// words. Copied as it is placed: the row can still be answered otherwise.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-preset');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// [seconds] of a quiet tone, as a conform only the conform store's
  /// stand-in ([soundConformStore]) reads — all a placement asks.
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
    return normalizedMediaPath(file.path);
  }

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
    );
    addTearDown(s.dispose);
    return s;
  }

  Future<void> openPlacing(
    WidgetTester tester,
    EditorSessionManager s,
    String path,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path], placeOnly: true),
        ),
      ),
    );
    await settleLoadedPages(tester);
  }

  group('a sound', () {
    Future<_Placed> place(
      WidgetTester tester,
      MediaPreset? preset,
    ) async {
      final path = (await tester.runAsync(() => writeSound('door.wav', 1)))!;
      final s = session();
      if (preset != null) {
        s.cutCommandCoordinator.updateMediaAssets([
          MediaAsset(path: path, name: '문', preset: preset),
        ]);
      }
      await openPlacing(tester, s, path);
      TransportBar bar() =>
          tester.widget<TransportBar>(find.byType(TransportBar));
      await settleAsync(tester, () => bar().frameCount != 1);
      final shown = bar().range!;

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      final s1 = s.activeTrack.seLayers.first;
      final block = s1.timeline[s.activeCutGlobalStartFrame]!;
      final frame = s1.frameById(block.frameId!)!;
      expect(
        (block.length, s1.audioClips.single.offsetFrames),
        (shown.outFrame - shown.inFrame + 1, shown.inFrame),
        reason: 'what the window showed is what landed',
      );
      await tester.pumpAndSettle();
      return (
        inFrame: shown.inFrame,
        outFrame: shown.outFrame,
        seName: frame.seName,
        words: frame.name,
      );
    }

    testWidgets('🚨held by the pool, starts at its preset\'s IN/OUT and '
        'lands under its preset\'s name tag and words', (tester) async {
      expect(
        await place(
          tester,
          const MediaPreset(
            inFrame: 2,
            outFrame: 5,
            seName: 'A',
            dialogue: '쾅',
          ),
        ),
        (inFrame: 2, outFrame: 5, seName: 'A', words: '쾅'),
      );
    });

    testWidgets('held with no preset, starts whole and lands as every placed '
        'sound does — 「SE」 with the pool\'s name for its words', (
      tester,
    ) async {
      final placed = await place(tester, const MediaPreset());
      expect(placed.inFrame, 0);
      expect(placed.outFrame, greaterThan(5), reason: 'the whole second');
      expect((placed.seName, placed.words), ('SE', '문'));
    });
  });

  testWidgets('🚨a GIF first placed trimmed is registered as long as the '
      'FILE — so its preset can span all of it', (tester) async {
    final s = session();
    final path = normalizedMediaPath(
      (await tester.runAsync(() => writeThreeFrameGif(tempDir, 'clip.gif')))!,
    );

    final landed = await tester.runAsync(
      () => s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        inFrame: 1,
        outFrame: 2,
      ),
    );

    expect(landed, isTrue);
    expect(
      s.repository.requireProject().mediaAssetByPath(path)?.frameCount,
      3,
      reason: 'two of its three frames placed; the file holds three',
    );
    await tester.pumpAndSettle();
  });

  group('a picture', () {
    Future<String> fitShownFor(WidgetTester tester, MediaPreset? preset) async {
      final path = normalizedMediaPath(
        (await tester.runAsync(
          () => writeSolidPng(tempDir, 'bg.png', rgba: 0xAAAAAAAA),
        ))!,
      );
      final s = session();
      if (preset != null) {
        s.cutCommandCoordinator.updateMediaAssets([
          MediaAsset(
            path: path,
            name: 'bg',
            kind: MediaAssetKind.image,
            preset: preset,
          ),
        ]);
      }
      await openPlacing(tester, s, path);
      final fit = tester
          .widget<ImportFileTable>(find.byType(ImportFileTable))
          .columns
          .singleWhere((column) => column.id == 'fit');
      return fit.cellWordOf(path);
    }

    testWidgets('🚨held by the pool, starts at its preset\'s fit', (
      tester,
    ) async {
      expect(
        await fitShownFor(tester, const MediaPreset(fit: MediaFitMode.stretch)),
        importFitLabel(MediaFitMode.stretch),
      );
    });

    testWidgets('one the pool has not seen starts where every picture does', (
      tester,
    ) async {
      expect(
        await fitShownFor(tester, null),
        importFitLabel(MediaFitMode.born),
      );
    });
  });
}

/// What the window showed of a placed sound, and the block it landed.
typedef _Placed = ({int inFrame, int outFrame, String? seName, String? words});
