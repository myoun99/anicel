// A MOVIE AT THE PROJECT'S PULLDOWN PARTNER IS NAMED ON IMPORT
// (import-movie-fps-mismatch-notice).
//
// 🗣️유저 10-06: 「알리는게 좋겠어」 · 「셋다 맞고」 — ①a difference that is no
// pair is not named ②a sound alone is not ③taking the movie's rate keeps
// the sound's timing; 10-10: 「1번」 — asked when Import is pressed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/encoded_movie.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';
import '../../helpers/import_span.dart';
import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/os_video_codec.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-movie-rate');
  });

  tearDown(() async {
    debugVideoDecodeBackend = null;
    deleteTempQuietly(tempDir);
  });

  Future<String> write(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}$name');
        await file.writeAsBytes(standInMovieBytes);
        return file.path;
      }))!;

  /// The window on [paths] in a 24 project, its movies read through a
  /// decoder that answers [fps] — 23.976 unless a test says otherwise —
  /// and every sound a hundred seconds long.
  Future<EditorSessionManager> open(
    WidgetTester tester,
    List<String> paths, {
    ({int numerator, int denominator}) fps = (
      numerator: 24000,
      denominator: 1001,
    ),
  }) async {
    debugVideoDecodeBackend = FakeVideoBackend(
      frameCount: 2000,
      fpsNumerator: fps.numerator,
      fpsDenominator: fps.denominator,
    );
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(seconds: 100),
    );
    addTearDown(s.dispose);
    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: paths),
        ),
      ),
    );
    await settleLoadedPages(tester);
    return s;
  }

  final rateDialog = find.byKey(
    const ValueKey<String>('import-movie-rate-dialog'),
  );

  /// Presses Import and waits for the rate question — the movie is read
  /// off the clock before it is asked.
  Future<void> pressImport(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await settleAsync(tester, () => rateDialog.evaluate().isNotEmpty);
    await tester.pump();
  }

  /// The layer [movie] was placed as — null while there is none.
  Layer? placedFrom(EditorSessionManager s, String movie) => s
      .requireActiveCut
      .layers
      .where(
        (layer) =>
            layer.mediaReference?.assetPath == normalizedMediaPath(movie),
      )
      .firstOrNull;

  Future<void> landed(
    WidgetTester tester,
    EditorSessionManager s,
    String movie,
  ) async {
    await settleAsync(tester, () => placedFrom(s, movie) != null);
    await tester.pumpAndSettle();
  }

  TransportRange range(WidgetTester tester) =>
      tester.widget<TransportBar>(find.byType(TransportBar)).range!;

  testWidgets('a 23.976 movie in a 24 project is named when Import is '
      'pressed — and taken, the project runs at its rate and the movie '
      'comes in from where it was placed, both of them ONE undo', (
    tester,
  ) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie]);

    await pressImport(tester);
    expect(rateDialog, findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-take')),
    );
    await pumpPastTheWaitWindow(tester);
    await landed(tester, s, movie);

    expect(
      s.projectSettings.projectFrameRate,
      const ProjectFrameRate.ntsc(24),
    );
    expect(placedFrom(s, movie)!.mediaReference!.frameOffset, 0);

    // F-405: the rate was taken by the press that placed the movie.
    s.undo();
    expect(placedFrom(s, movie), isNull);
    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('taken, a trimmed movie\'s IN and OUT move to the frames that '
      'show the very pictures they stood on', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie]);
    // One-based on screen: IN at frame 500, OUT at 1600 — on the 24 clock
    // they show the movie's pictures 499 and 1598.
    await keepImportSpan(tester, 501, 1601);
    expect((range(tester).inFrame, range(tester).outFrame), (500, 1600));

    await pressImport(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-take')),
    );
    await settleAsync(
      tester,
      () => s.projectSettings.projectFrameRate != ProjectFrameRate.fps24,
    );
    await tester.pump();

    expect(
      (range(tester).inFrame, range(tester).outFrame),
      (499, 1598),
      reason: 'frame for frame with the movie now — ↩️500 · 1600 would be '
          'one and two pictures later',
    );
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('kept, the project stays at 24 and a trimmed movie\'s IN and '
      'OUT stay where they were', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie]);
    await keepImportSpan(tester, 501, 1601);

    await pressImport(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-keep')),
    );
    await tester.pump();
    await tester.pump();

    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
    expect((range(tester).inFrame, range(tester).outFrame), (500, 1600));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('backing out places nothing and leaves the rate — and Import '
      'asks again', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie]);

    await pressImport(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-cancel')),
    );
    await tester.pumpAndSettle();

    expect(rateDialog, findsNothing);
    expect(placedFrom(s, movie), isNull);
    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);

    await pressImport(tester);
    expect(rateDialog, findsOneWidget, reason: 'asked again');
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-cancel')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a movie at the project\'s own rate is not asked about — it '
      'goes straight in', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie], fps: (numerator: 24, denominator: 1));

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await landed(tester, s, movie);

    expect(rateDialog, findsNothing);
    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('an OUT left at the movie\'s end stays at its end — the end '
      'of the movie on the new clock', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie]);
    await tester.tap(find.byKey(const ValueKey<String>('transport-in-edit')));
    await tester.pump();
    await openThePadsKeyboard(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('transport-in-input')),
      '501',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleLoadedPages(tester);
    expect(
      (range(tester).inFrame, range(tester).outFrame),
      (500, 2001),
      reason: '⛔전제: 2000 pictures cover 2002 frames of a 24 project',
    );

    await pressImport(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-take')),
    );
    await settleAsync(
      tester,
      () => s.projectSettings.projectFrameRate != ProjectFrameRate.fps24,
    );
    await tester.pump();

    expect(range(tester).inFrame, 499);
    expect(
      range(tester).outFrame,
      tester.widget<TransportBar>(find.byType(TransportBar)).frameCount - 1,
      reason: 'still at the end, wherever the end is counted',
    );
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a movie that only registers is not asked about — it is asked '
      'when it is placed', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final s = await open(tester, [movie]);
    final into = find.byKey(ValueKey<String>('import-cell-into-$movie'));
    await tester.ensureVisible(into);
    await tester.tap(into);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-into-pool')),
    );
    await settleLoadedPages(tester);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(
      tester,
      () =>
          s.repository.requireProject().mediaAssetByPath(movie) != null,
    );
    await tester.pumpAndSettle();

    expect(rateDialog, findsNothing);
    expect(s.repository.requireProject().mediaAssetByPath(movie), isNotNull);
    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a sound alone is not asked about — a sound has no frames to '
      'line up', (tester) async {
    final sound = await write(tester, 'voice.wav');
    final s = await open(tester, [sound]);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    expect(rateDialog, findsNothing);
    expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a sound beside it keeps its moments — its IN and OUT move to '
      'the frames that begin nearest where they stood', (tester) async {
    final movie = await write(tester, 'take.mp4');
    final sound = await write(tester, 'voice.wav');
    final s = await open(tester, [movie, sound]);
    // The row's NAME: the middle of a row is one of its answer cells, and a
    // press there opens that answer's list over the preview.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('import-row-voice.wav')),
        matching: find.text('voice'),
      ),
    );
    await settleLoadedPages(tester);
    await keepImportSpan(tester, 501, 1601);
    expect((range(tester).inFrame, range(tester).outFrame), (500, 1600));

    await pressImport(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('import-movie-rate-take')),
    );
    await settleAsync(
      tester,
      () => s.projectSettings.projectFrameRate != ProjectFrameRate.fps24,
    );
    await tester.pump();

    expect(
      (range(tester).inFrame, range(tester).outFrame),
      (500, 1598),
      reason: '499.5005 → 500 · 1598.4016 → 1598',
    );
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  // 🗣️F-588 (유저 2026-11-14: 「이 영상만」 — the movie carried in is
  // rewritten at the project's speed; the slot always there, pressed only
  // where it can be, the label in plain words).
  group('fitting the movie to the project', () {
    final fit = find.byKey(const ValueKey<String>('import-movie-rate-fit'));
    final cancel = find.byKey(
      const ValueKey<String>('import-movie-rate-cancel'),
    );

    VoidCallback? fitPress(WidgetTester tester) =>
        tester.widget<ButtonStyleButton>(fit).onPressed;

    Future<void> answer(
      WidgetTester tester,
      String column,
      String path,
      String value,
    ) async {
      final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
      await tester.ensureVisible(cell);
      await settleLoadedPages(tester);
      await tester.tap(cell);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>('import-option-$column-$value')),
      );
      await settleLoadedPages(tester);
    }

    /// The hover [button] wears.
    String tipOf(WidgetTester tester, Finder button) => tester
        .widget<AppTooltip>(
          find.ancestor(of: button, matching: find.byType(AppTooltip)),
        )
        .message;

    /// Six real frames at 23.976, each its own flat red — 20, 50, 80 … —
    /// over a sound; null where this run has no encoder.
    Future<String?> sixFrames(WidgetTester tester) =>
        tester.runAsync<String?>(() async {
          final path = '${tempDir.path}${Platform.pathSeparator}take.mp4';
          return writeEncodedMovie(
                path,
                frames: 6,
                fps: (numerator: 24000, denominator: 1001),
                picture: (frame, _) =>
                    (red: 20 + frame * 30, green: 0, blue: 0),
                sound: (sample) => (sample * 37) % 20000 - 10000,
              )
              ? path
              : null;
        });

    /// Presses Import, fits the movie, and answers where the bytes the
    /// pool carries for [movie] were copied out to, a decoder to open them —
    /// after holding that they are a piece cut from it, the project still
    /// at 24.
    Future<String> fitAndCopyThePiece(
      WidgetTester tester,
      EditorSessionManager s,
      String movie,
    ) async {
      await pressImport(tester);
      await tester.tap(fit);
      await pumpPastTheWaitWindow(tester);
      bool isAMovie(MediaAsset asset) => asset.kind == MediaAssetKind.video;
      await settleAsync(tester, () => s.mediaPool.mediaAssets.any(isAMovie));
      await tester.pumpAndSettle();
      s.playbackRig.prerenderScheduler.cancel();

      expect(s.projectSettings.projectFrameRate, ProjectFrameRate.fps24);
      final entry = s.mediaPool.mediaAssets.singleWhere(isAMovie);
      expect(entry.carried, isTrue);
      expect(
        normalizedMediaPath(entry.sourcePath!),
        normalizedMediaPath(movie),
        reason: 'carried as a piece of its own — kept, the movie would come '
            'in whole',
      );
      return (await tester.runAsync(() async {
        final bytes = await s.projectFile
            .mediaByteSourceFor(entry.path)
            .read();
        final file = File('${tempDir.path}${Platform.pathSeparator}held.mp4');
        await file.writeAsBytes(bytes);
        return file.path;
      }))!;
    }

    testWidgets('carried in, the movie can be fitted; pointed at, the button '
        'stands where it was and cannot be pressed', (tester) async {
      final movie = await write(tester, 'take.mp4');
      await open(tester, [movie]);

      await pressImport(tester);
      expect(
        fitPress(tester),
        isNotNull,
        reason: 'a movie placed is carried in unless answered otherwise',
      );
      expect(
        find.text(
          AppText.strings.imRateFitMovie(ProjectFrameRate.fps24.label),
        ),
        findsOneWidget,
      );
      // The numbers are the hover's (F-588: 「0.1% 같은 숫자는 호버로」).
      expect(
        tipOf(tester, find.byKey(const ValueKey('import-movie-rate-keep'))),
        AppText.strings.imRateKeepTip(42),
        reason: 'a 23.976 take kept in 24 holds a picture every 41.7 s',
      );
      expect(tipOf(tester, fit), AppText.strings.imRateFitTipPictureAndSound);
      expect(
        tipOf(tester, find.byKey(const ValueKey('import-movie-rate-take'))),
        AppText.strings.imRateTakeTip(const ProjectFrameRate.ntsc(24).label),
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      await answer(tester, 'file', movie, 'reference');
      await pressImport(tester);
      expect(fit, findsOneWidget, reason: 'its slot is always there');
      expect(
        fitPress(tester),
        isNull,
        reason: 'pointed at, no bytes are the import\'s own to rewrite',
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();
    });

    testWidgets('bringing its sound alone, the button names the sound — and '
        'its hover says the sound is what is rewritten', (tester) async {
      final movie = await write(tester, 'take.mp4');
      await open(tester, [movie]);
      await answer(tester, 'option', movie, 'sound');

      await pressImport(tester);

      expect(
        find.text(
          AppText.strings.imRateFitSound(ProjectFrameRate.fps24.label),
        ),
        findsOneWidget,
      );
      expect(tipOf(tester, fit), AppText.strings.imRateFitTipSound);
      expect(fitPress(tester), isNotNull);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
    });

    testWidgets('🎯fitted, a 23.976 movie placed in a 24 project is carried '
        'as its piece rewritten at 24 — frame for frame, and the project '
        'stays at 24', (tester) async {
      final movie = await sixFrames(tester);
      if (movie == null) {
        return;
      }
      final s = await open(tester, [movie]);

      final copy = await fitAndCopyThePiece(tester, s, movie);

      final decoder = osVideoDecoderOrSkip();
      if (decoder == null) {
        return;
      }
      final piece = decoder.openDocument(copy)!;
      try {
        expect(piece.info.frameCount, 6, reason: 'one frame for each of its');
        expect(
          piece.info.fpsNumerator / piece.info.fpsDenominator,
          closeTo(24, 1e-3),
        );
      } finally {
        decoder.closeDocument(piece);
      }
    });

    testWidgets('🎯fitted, a trimmed movie keeps the very pictures its IN '
        'and OUT stood on — counted again on the clock it is rewritten on', (
      tester,
    ) async {
      final movie = await sixFrames(tester);
      if (movie == null) {
        return;
      }
      final s = await open(tester, [movie]);
      // One-based on screen: IN at frame 3, OUT at 4 — on the 24 clock they
      // show the movie's pictures 2 and 3.
      await keepImportSpan(tester, 4, 5);

      final copy = await fitAndCopyThePiece(tester, s, movie);

      final decoder = osVideoDecoderOrSkip();
      if (decoder == null) {
        return;
      }
      final piece = decoder.openDocument(copy)!;
      try {
        expect(piece.info.frameCount, 2);
        final reds = [
          for (var frame = 0; frame < 2; frame += 1)
            decoder.frameOf(piece, frame)![0],
        ];
        // Half the step between neighbouring reds: nearer is that picture.
        const shown = [80, 110];
        expect(
          [for (var at = 0; at < 2; at += 1) (reds[at] - shown[at]).abs() < 15],
          [true, true],
          reason: 'pictures 2 and 3 (reds 80 · 110) — the same frame '
              'numbers on the rewritten clock would be pictures 3 and 4; '
              'read $reds',
        );
      } finally {
        decoder.closeDocument(piece);
      }
    });
  });
}
