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
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';
import '../../helpers/import_span.dart';
import '../../helpers/number_pad_keyboard.dart';

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
}
