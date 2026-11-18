import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/services/diagnostics/gpu_loss_log.dart';
import 'package:anicel/src/services/playback/playback_scope.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/lost_screen_evidence.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️H63 (관제 2026-11-18): the next real reset of the screen's device
/// leaves its own evidence — the moment the shell hears it, before its
/// question and the save after it: each device's word, the playback, and
/// the cut it stood on ([LostScreenEvidence], [GpuLossLog]).
void main() {
  late File log;

  setUp(() {
    log = File(GpuLossLog.logPath());
    if (log.existsSync()) {
      log.deleteSync();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LostScreen.channel, (call) async => -1);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LostScreen.channel, null);
      LostScreen.debugForget();
      LostScreenEvidence.debugForget();
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

  testWidgets('the screen gone while a cut plays, the log says each '
      "device's word, the playback and the cut — once a run", (tester) async {
    final session = await pumpShell(tester);
    final cut = session.requireActiveCut;
    final playback = session.playbackRig.playback;
    playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    expect(playback.isPlaying, isTrue, reason: '⛔전제: it plays');
    expect(log.existsSync(), isFalse, reason: '⛔전제: nothing went yet');

    LostScreen.debugGo(0x887A0006);
    await tester.pump();
    await tester.pump();
    playback.stop();
    await tester.pump();

    final lines = log.readAsLinesSync();
    expect(lines.first, startsWith(GpuLossLog.opening));
    expect(lines.first, endsWith("the screen's device went"));
    expect(lines, contains('screen watch 0x887A0006'));
    expect(lines, contains('engine gone=false went=unsaid'));
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
        '${cut.layers.where((row) => row.isVisible).length} shown',
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
}
