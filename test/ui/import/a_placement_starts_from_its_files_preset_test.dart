import '../../helpers/screens_left_of_the_engine.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/media/media_facts.dart' show readMediaFacts;
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindDisplayName;
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_pdf_document.dart';
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
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofALay});
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

  // 🗣️F-429 (유저 2026-10-21): 「1장짜리 그림을 기본 이미지레이어로
  // 자동지정해두지만 같은창에서 애니메이션레이어로 변경가능」 — a cut
  // folder's picture; a file of one picture is the same family. 🗣️유저
  // 2026-11-17 (Q4): 「기본 그림한장은 이미지」, a preset's to say.
  group('a picture\'s kind', () {
    ImportColumn<Object?> optionShown(WidgetTester tester) => tester
        .widget<ImportFileTable>(find.byType(ImportFileTable))
        .columns
        .singleWhere((column) => column.id == 'option');

    Future<ImportColumn<Object?>> optionOf(
      WidgetTester tester,
      EditorSessionManager s,
      String path, {
      bool placeOnly = false,
      Future<void> Function()? onceShown,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: [path],
              placeOnly: placeOnly,
            ),
          ),
        ),
      );
      await settleLoadedPages(tester);
      await onceShown?.call();
      // 🚨ASKED ONCE ITS PICTURES ARE COUNTED: the window answers for ONE
      // picture till its file's facts are read (`_picturesKept(path) ?? 1`),
      // a read of its own beside the preview's — and the preview can land
      // first, as it did under the wide check's load (board
      // a-three-frame-gif-reads-as-one-picture-in-the-wide-check, 11-23).
      // The row's resolution says the facts are in, as
      // each_file_says_its_resolution_test waits for them; [step] lets the
      // window's 200 ms showing of them run.
      expect(
        await settleAsync(
          tester,
          () =>
              tester
                  .widget<Text>(
                    find.byKey(ValueKey<String>('import-resolution-$path')),
                  )
                  .data !=
              '',
          step: const Duration(milliseconds: 200),
        ),
        isTrue,
        reason: "the file's facts were never read",
      );
      return optionShown(tester);
    }

    String said(LayerKind kind) => layerKindDisplayName(kind);

    testWidgets('🚨one picture is asked it — an image until picked; picked '
        '애니메이션, it lands as one cel of an animation layer', (
      tester,
    ) async {
      final s = session();
      final path = normalizedMediaPath(
        (await tester.runAsync(() => writeSolidPng(tempDir, 'bg.png')))!,
      );
      final option = await optionOf(tester, s, path);
      expect(option.cellWordOf(path), said(LayerKind.image));
      expect(option.enabledFor(path, LayerKind.image), isTrue);

      option.onPick([path], LayerKind.animation);
      await tester.pump();
      final picked = tester
          .widget<ImportFileTable>(find.byType(ImportFileTable))
          .columns
          .singleWhere((column) => column.id == 'option');
      expect(picked.cellWordOf(path), said(LayerKind.animation));

      final before = {for (final layer in s.requireActiveCut.layers) layer.id};
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      final landed = s.requireActiveCut.layers.singleWhere(
        (layer) => !before.contains(layer.id),
      );
      expect(landed.kind, LayerKind.animation);
      expect(landed.frames, hasLength(1));
      expect(
        [for (final block in landed.timeline.values) block.length],
        [1],
        reason: 'an animation layer\'s cel is one comma, as a cut folder '
            'lays its rows (F-429)',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('🚨held by the pool, it starts as its preset says', (
      tester,
    ) async {
      final s = session();
      final path = normalizedMediaPath(
        (await tester.runAsync(() => writeSolidPng(tempDir, 'bg.png')))!,
      );
      s.cutCommandCoordinator.updateMediaAssets([
        MediaAsset(
          path: path,
          name: 'bg',
          kind: MediaAssetKind.image,
          preset: const MediaPreset(pictureKind: LayerKind.animation),
        ),
      ]);

      final option = await optionOf(tester, s, path, placeOnly: true);

      expect(option.cellWordOf(path), said(LayerKind.animation));
    });

    testWidgets('a PDF\'s ONE page comes in as its row says — an image held '
        'over the cut, or an animation layer\'s one cel', (tester) async {
      PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
        pageSizes: const [
          ui.Size(100, 50),
          ui.Size(100, 50),
          ui.Size(100, 50),
        ],
      );
      addTearDown(PdfRenderService.debugResetForTests);
      final path = '${tempDir.path}${Platform.pathSeparator}conte.pdf';
      await tester.runAsync(
        () => File(path).writeAsBytes(const [0x25, 0x50, 0x44, 0x46]),
      );
      for (final kind in [LayerKind.image, LayerKind.animation]) {
        final s = session();
        final before = {
          for (final layer in s.requireActiveCut.layers) layer.id,
        };
        final landed = await tester.runAsync(
          () => s.importDoors.importPdfFile(
            path: path,
            destination: ImportDestination.activeCutLayer,
            copyIntoProject: false,
            inFrame: 1,
            outFrame: 1,
            pictureKind: kind,
          ),
        );
        expect(landed, isTrue, reason: '$kind');
        expect(
          s.requireActiveCut.layers
              .singleWhere((layer) => !before.contains(layer.id))
              .kind,
          kind,
        );
      }
      await tester.pumpAndSettle();
    });

    testWidgets('pictures of more than one cannot be an image — they come in '
        'as cels, as a cut folder\'s row of many does', (tester) async {
      final s = session();
      final path = normalizedMediaPath(
        (await tester.runAsync(() => writeThreeFrameGif(tempDir, 'b.gif')))!,
      );

      // The test holds the order the wide check's load once dealt (board
      // a-three-frame-gif-reads-as-one-picture-in-the-wide-check): the
      // preview lands while the file's facts are still held back — so a
      // row asked before its pictures are counted is caught every run, not
      // only under load.
      final held = Completer<void>();
      ImportDialog.readFacts = (kind, file, hold) async {
        await held.future;
        return readMediaFacts(kind, file, hold);
      };
      addTearDown(() => ImportDialog.readFacts = readMediaFacts);

      final option = await optionOf(
        tester,
        s,
        path,
        onceShown: () async {
          expect(
            optionShown(tester).enabledFor(path, LayerKind.image),
            isTrue,
            reason: 'CONTROL: its pictures not yet counted, the row '
                'answers for one',
          );
          held.complete();
        },
      );

      expect(option.enabledFor(path, LayerKind.image), isFalse);
      expect(option.cellWordOf(path), said(LayerKind.animation));
    });
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
