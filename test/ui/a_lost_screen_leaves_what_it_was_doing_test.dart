import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/services/diagnostics/gpu_loss_log.dart';
import 'package:anicel/src/services/playback/playback_scope.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/lost_screen_evidence.dart';
import 'package:anicel/src/ui/raster_watch.dart';
import 'package:anicel/src/ui/screen_canary.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️H63 (관제 2026-11-18): the next real reset of the screen's device
/// leaves its own evidence — the moment the shell hears it, before its
/// question and the save after it: each device's word, the playback, and
/// the cut it stood on ([LostScreenEvidence], [GpuLossLog]).
///
/// And so does the thread that draws the screen standing ([RasterWatch] —
/// board a-real-gpu-reset-went-unheard-on-the-main-pc, 2026-11-22), which
/// no device says, and a pixel the screen's context did not say back
/// ([ScreenCanary], Q1 of that card): written, and nothing asked.
void main() {
  late File log;

  setUp(() {
    log = File(GpuLossLog.logPath());
    if (log.existsSync()) {
      log.deleteSync();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          LostScreen.channel,
          // The runner: its watch's device stands, and no button is pressed.
          (call) async => call.method == LostScreen.standsMethod ? true : -1,
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LostScreen.channel, null);
      LostScreen.debugForget();
      LostScreenEvidence.debugForget();
      RasterWatch.debugForget();
      ScreenCanary.debugForget();
      ScreenCanary.debugDrawOverride = null;
      if (log.existsSync()) {
        log.deleteSync();
      }
    });
  });

  Future<EditorSessionManager> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
  }

  test('the log says who said the screen went — the watch by the HRESULT '
      'Windows gave it, the engine by the EGL error its call failed '
      'by', () {
    final seen = DateTime.fromMillisecondsSinceEpoch(1795000000123);
    expect(
      LostScreenEvidence.linesOf((
        reason: 0x887A0006.toSigned(32),
        seenAt: seen,
        by: ScreenGoneBy.watch,
      ), null).first,
      'screen watch 0x887A0006',
    );
    expect(
      LostScreenEvidence.linesOf((
        reason: 0x300E,
        seenAt: seen,
        by: ScreenGoneBy.engine,
      ), null).first,
      "engine's context lost 0x300E",
    );
  });

  testWidgets('the screen gone while a cut plays, the log says each '
      "device's word, the playback and the cut — once a run", (tester) async {
    final session = await pumpShell(tester);
    final cut = session.requireActiveCut;
    final playback = session.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(playback.isPlaying, isTrue, reason: '⛔전제: it plays');
    expect(log.existsSync(), isFalse, reason: '⛔전제: nothing went yet');

    // As the runner says it: the HRESULT as an int32, so negative here, and
    // the moment its watch saw it (H63 ③).
    final seen = DateTime.fromMillisecondsSinceEpoch(1795000000123);
    LostScreen.debugGo(0x887A0006.toSigned(32), seen);
    await tester.pump();
    await tester.pump();
    playback.stop();
    await tester.pump();

    final lines = log.readAsLinesSync();
    expect(lines.first, startsWith(GpuLossLog.opening));
    expect(lines.first, endsWith("the screen's device went"));
    expect(lines, contains('screen watch 0x887A0006'));
    expect(
      lines,
      contains(
        'runner saw it ${seen.toIso8601String()} '
        '(${seen.toUtc().toIso8601String()})',
      ),
    );
    // What submits it had moves on as the shell goes on; its word does not.
    expect(lines, contains(appGpuEngineLossLines.first));
    expect(
      lines.where((line) => line.startsWith('playback ')).single,
      allOf(contains('playing=true'), contains('scope=activeCut')),
    );
    expect(
      lines,
      contains(
        'cut ${cut.name} (${cut.id.value}) '
        '${cut.canvasSize.width}x${cut.canvasSize.height} '
        '${cut.duration} frames, at frame ${session.currentFrameIndex}, '
        '${cut.layers.length} rows, '
        '${cut.layers.where(cut.layers.rowVisible).length} shown',
      ),
    );

    LostScreenEvidence.noteOnce(session);
    expect(
      log.readAsLinesSync().where(
        (line) => line.startsWith(GpuLossLog.opening),
      ),
      hasLength(1),
      reason: 'a run notes its loss once',
    );
  });

  testWidgets('the thread that draws the screen standing while a cut plays, '
      'the log says the frames it was handed, each device\'s word, the '
      'playback and the cut — once a run, nothing asked; and a screen gone '
      'after it is written as well', (tester) async {
    final session = await pumpShell(tester);
    final playback = session.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(log.existsSync(), isFalse, reason: '⛔전제: nothing stood yet');

    List<String> written() => log
        .readAsLinesSync()
        .where((line) => line.startsWith(GpuLossLog.opening))
        .toList();

    RasterWatch.handedOver(41);
    await tester.pump(RasterWatch.patience);
    expect(RasterWatch.stood.value, isNotNull, reason: '⛔전제: it stood');
    await tester.pump();

    final lines = log.readAsLinesSync();
    expect(
      written().single,
      endsWith('the screen draws no frame the app hands it'),
    );
    expect(
      lines,
      containsAllInOrder([
        startsWith('frames said drawn to #-1, handed over to #41 '),
        startsWith('none said drawn since '),
        'screen watch says nothing',
        appGpuEngineLossLines.first,
        allOf(startsWith('playback '), contains('playing=true')),
        startsWith('cut ${session.requireActiveCut.name} '),
      ]),
    );
    expect(LostScreen.hasGone, isFalse, reason: 'written, and no more');

    LostScreenEvidence.noteTheRasterStoodOnce(session);
    expect(written(), hasLength(1), reason: 'once a run');

    LostScreen.debugGo();
    await tester.pump();
    await tester.pump();
    playback.stop();
    await tester.pump();
    expect(written(), hasLength(2), reason: 'each once, neither for both');
    expect(written().last, endsWith("the screen's device went"));
  });

  testWidgets('a pixel the screen\'s context did not say back while a cut '
      'plays, the log says what was asked and what came, each device\'s '
      'word, the playback and the cut — once a run, nothing asked', (
    tester,
  ) async {
    final session = await pumpShell(tester);
    final playback = session.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(log.existsSync(), isFalse, reason: '⛔전제: nothing written yet');

    // As a context whose device went is read to say it: nothing drawn.
    ScreenCanary.debugDrawOverride = (argb) async => Uint8List(4);
    unawaited(ScreenCanary.ask());
    for (var turn = 0; turn < 4; turn += 1) {
      await tester.pump();
    }
    expect(ScreenCanary.notSaid.value, isNotNull, reason: '⛔전제: not said');

    List<String> written() => log
        .readAsLinesSync()
        .where((line) => line.startsWith(GpuLossLog.opening))
        .toList();
    expect(
      written().single,
      endsWith("the screen's context does not draw what it is given"),
    );
    expect(
      log.readAsLinesSync(),
      containsAllInOrder([
        allOf(
          startsWith('a pixel of 3779b1ff asked '),
          endsWith(': read 00000000'),
        ),
        'screen watch says nothing',
        appGpuEngineLossLines.first,
        allOf(startsWith('playback '), contains('playing=true')),
        startsWith('cut ${session.requireActiveCut.name} '),
      ]),
    );
    expect(LostScreen.hasGone, isFalse, reason: 'written, and no more');

    LostScreenEvidence.noteThePixelNotSaidOnce(session);
    expect(written(), hasLength(1), reason: 'once a run');
    playback.stop();
    await tester.pump();
  });
}
