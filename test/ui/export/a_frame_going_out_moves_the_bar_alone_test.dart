import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/png_sequence_export_service.dart'
    show ExportWriteSummary;
import 'package:anicel/src/ui/export/video_export_service.dart';

import '../../helpers/temp_dir.dart';

/// A video run that goes as far as the test says: it holds the window's own
/// progress callback, and ends when it is told to.
class _HeldVideoRun extends VideoExportService {
  void Function(int completed, int total)? report;
  late Completer<void> _end;

  @override
  Future<ExportWriteSummary> exportVideo({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String outputFilePath,
    required ProjectFrameRate frameRate,
    String? audioMixPath,
    ExportVideoContainer container = ExportVideoContainer.mp4,
    ExportVideoCodec codec = ExportVideoCodec.h264,
    bool alpha = false,
    int bitrateBps = 0,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    report = onProgress;
    // Made here, in the zone the run is awaited in.
    final end = _end = Completer<void>();
    await end.future;
    return (written: count, processed: count);
  }

  void finish() => _end.complete();
}

/// 🚨A FRAME GOING OUT MOVES THE FOOTER'S BAR, AND NOTHING ELSE OF THE
/// WINDOW IS BUILT AGAIN FOR IT (F-289).
///
/// The run's progress was the window's own state: every frame that went out
/// rebuilt the whole window — its settings, its list, its preview — to move
/// one bar. A run that writes a frame in a few milliseconds would spend
/// most of them on that.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('anicel-export-bar');
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    deleteTempQuietly(temp);
  });

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 32, height: 18),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'Cut',
              duration: 4,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('layer'),
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('f1'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                ),
                createCameraLayer(cutId: const CutId('cut')),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  /// The window over [run], and its state.
  Future<ExportDialogState> open(WidgetTester tester, _HeldVideoRun run) async {
    final s = session();
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: s,
            exportDirectoryPicker: () async => temp.path,
            videoExportService: run,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<ExportDialogState>(find.byType(ExportDialog));
  }

  /// Starts [run]ning through [start] and comes back once the run has the
  /// window's progress callback — with the future of the whole of it.
  Future<({Future<void> whole})> begun(
    WidgetTester tester,
    _HeldVideoRun run,
    Future<void> Function() start,
  ) async {
    late Future<void> whole;
    run.report = null;
    await tester.runAsync(() async {
      whole = start();
      while (run.report == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();
    return (whole: whole);
  }

  /// Lets [run] end, and [whole] with it.
  Future<void> ended(
    WidgetTester tester,
    _HeldVideoRun run,
    Future<void> whole,
  ) async {
    await tester.runAsync(() async {
      run.finish();
      await whole;
    });
    await tester.pump();
  }

  LinearProgressIndicator bar(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey<String>('export-progress')),
      );

  testWidgets('the bar moves; the window is not built again', (tester) async {
    final run = _HeldVideoRun();
    final state = await open(tester, run);
    final (whole: exporting) = await begun(tester, run, state.export);
    // The run is under way: the bar is up, at nothing yet.
    expect(bar(tester).value, isNull);

    /// What a frame of the run going out builds again.
    Future<List<Type>> builtBy(void Function() frameOut) async {
      final built = <Type>[];
      debugOnRebuildDirtyWidget = (element, _) =>
          built.add(element.widget.runtimeType);
      frameOut();
      await tester.pump();
      debugOnRebuildDirtyWidget = null;
      return built;
    }

    final first = await builtBy(() => run.report!(1, 4));
    expect(bar(tester).value, 0.25);
    expect(first, isNotEmpty, reason: 'LIVENESS: the bar was built again');
    expect(first, isNot(contains(ExportDialog)));

    final second = await builtBy(() => run.report!(2, 4));
    expect(bar(tester).value, 0.5);
    expect(second, isNot(contains(ExportDialog)));

    await ended(tester, run, exporting);
    expect(
      find.byKey(const ValueKey<String>('export-progress')),
      findsNothing,
      reason: 'the run is over, and the bar with it',
    );

    // The next run starts at nothing, whatever this one reached.
    final (whole: again) = await begun(tester, run, state.export);
    expect(bar(tester).value, isNull);
    await ended(tester, run, again);
  });

  testWidgets('a queued run leaves nothing standing on the bar either', (
    tester,
  ) async {
    final run = _HeldVideoRun();
    final state = await open(tester, run);
    await tester.runAsync(state.addToQueue);
    await tester.pump();

    final (whole: queued) = await begun(tester, run, state.runQueue);
    run.report!(3, 4);
    await tester.pump();
    expect(bar(tester).value, 0.75, reason: 'LIVENESS: the queued run moved it');
    await ended(tester, run, queued);

    final (whole: next) = await begun(tester, run, state.export);
    expect(bar(tester).value, isNull);
    await ended(tester, run, next);
  });
}
