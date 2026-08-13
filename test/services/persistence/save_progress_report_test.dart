import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🔑 The percentage has to be REAL.
///
/// A bar driven by a timer would satisfy every screenshot and answer none
/// of the question — the user's complaint is that they cannot tell what the
/// app is doing, and a number that was never connected to the write is just
/// a prettier silence.
///
/// The write happens inside `Isolate.run`, which hands back a value and no
/// port. What makes this possible at all is that the closure it sends may
/// CAPTURE a `SendPort`: the caller opens the `ReceivePort`, the isolate
/// talks into the port it was closed over. These tests exist because that
/// is a load-bearing trick — if it ever stops working, the reports simply
/// stop arriving and nothing else fails.
void main() {
  late Directory directory;
  late String projectPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-save-progress-');
    projectPath = '${directory.path.replaceAll('\\', '/')}/scene.anicel';
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  void drawOnCurrentFrame(EditorSessionManager s) {
    s.createDrawingAtCurrentFrame();
    final selection = s.activeBrushEditorSelection!;
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        s.requireActiveCut,
        selection.layerId,
        selection.frameId,
      ),
      frameStore: s.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: s.requireActiveCut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 10, y: 10),
          color: 0xFF000000,
          size: 4,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

  test('a FULL save reports its way to 1.0', () async {
    final s = session();
    for (var i = 0; i < 3; i += 1) {
      s.createCut();
      drawOnCurrentFrame(s);
    }

    final reports = <double>[];
    await s.saveProjectToFile(projectPath, onProgress: reports.add);

    expect(reports, isNotEmpty, reason: 'nothing crossed the port at all');
    expect(
      reports.last,
      1.0,
      reason: 'a finished save that stops at 99% is the doubt this replaces',
    );
    expect(
      reports,
      everyElement(allOf(greaterThanOrEqualTo(0.0), lessThanOrEqualTo(1.0))),
    );
  });

  test('and an INCREMENTAL one does too — the common Ctrl+S', () async {
    // The two save paths are different code with different denominators.
    // Instrumenting one and trusting the other is how the fast path ends
    // up showing a window that never moves.
    final s = session();
    s.createCut();
    drawOnCurrentFrame(s);
    await s.saveProjectToFile(projectPath);
    final sizeAfterFirst = File(projectPath).lengthSync();

    s.createCut();
    drawOnCurrentFrame(s);
    final reports = <double>[];
    await s.saveProjectToFile(projectPath, onProgress: reports.add);

    expect(
      File(projectPath).lengthSync(),
      greaterThan(sizeAfterFirst),
      reason: 'an append, not a rewrite — otherwise this tests the wrong path',
    );
    expect(reports, isNotEmpty);
    expect(reports.last, 1.0);
  });

  test('every asset is reported on — the second does not pass in silence', () async {
    // Two numbers share this one fraction: whole entries, and the part of a
    // streaming entry already read. Get the hand-off between them wrong and
    // the second asset restarts BELOW where the first ended.
    //
    // That never shows up as a bar running backwards — a report that dips
    // is dropped rather than sent, so the bar simply says NOTHING for the
    // length of a whole asset and then arrives at the end. Which is why the
    // test is comparative: adding an asset to a project has to add reports
    // about it. A count is the only thing that can tell "streamed quietly"
    // apart from "streamed".
    Future<List<double>> saveWithAssets(String tag, int assets) async {
      final s = session();
      drawOnCurrentFrame(s);
      for (var i = 0; i < assets; i += 1) {
        final path = '${directory.path}/$tag-$i.wav';
        File(path)
          ..createSync()
          ..writeAsBytesSync(List<int>.filled(900 * 1024, 7));
        s.importMediaFiles([path], copyIntoProject: true);
      }
      final reports = <double>[];
      await s.saveProjectToFile(
        '${directory.path.replaceAll('\\', '/')}/$tag.anicel',
        onProgress: reports.add,
      );
      // Monotone as well: a fraction that goes back reads as work undone.
      for (var i = 1; i < reports.length; i += 1) {
        expect(
          reports[i],
          greaterThanOrEqualTo(reports[i - 1]),
          reason: '$tag report $i dipped: ${reports[i - 1]} → ${reports[i]}',
        );
      }
      return reports;
    }

    final one = await saveWithAssets('one', 1);
    final two = await saveWithAssets('two', 2);

    expect(one.length, greaterThan(2), reason: 'the one asset was reported on');
    expect(
      two.length,
      greaterThan(one.length),
      reason: 'the second asset went by without a word — the bar would sit '
          'still through it and then jump to the end',
    );
  });

  test('an EMPTY asset does not leave the count short of the end', () async {
    // A zero-byte file is never read from, so it never reports itself
    // finished the way every other entry does — it is counted in the
    // denominator and never lands in the numerator. Real enough to guard: a
    // recording that captured nothing, or an import cut off part way.
    final s = session();
    drawOnCurrentFrame(s);
    File('${directory.path}/빈소리.wav').createSync();
    s.importMediaFiles(['${directory.path}/빈소리.wav'], copyIntoProject: true);

    final reports = <double>[];
    await s.saveProjectToFile(projectPath, onProgress: reports.add);

    expect(reports.last, 1.0);
  });

  test('🚨 a WATCHED save still writes the asset byte for byte', () async {
    // The counting wraps `readInto` — the callback the writer pulls media
    // through, chunk by chunk. Wrapping the actual byte path is the one
    // place this feature could damage a file rather than merely mislead
    // about one, so it is checked against the source rather than against
    // another save (two sessions do not produce identical archives, and a
    // length comparison between them measures that instead of this).
    final source = File('${directory.path}/대사.wav')
      ..createSync()
      ..writeAsBytesSync([
        for (var i = 0; i < 900 * 1024; i += 1) (i * 31 + 7) % 251,
      ]);
    final s = session();
    drawOnCurrentFrame(s);
    s.importMediaFiles(['${directory.path}/대사.wav'], copyIntoProject: true);
    await s.saveProjectToFile(projectPath, onProgress: (_) {});

    final archive = ZipDecoder().decodeBytes(File(projectPath).readAsBytesSync());
    final stored = [
      for (final entry in archive.files)
        if (entry.name != 'project.json' && !entry.name.endsWith('.celz'))
          entry,
    ];
    expect(stored, hasLength(1), reason: 'the one imported asset');
    expect(stored.single.readBytes(), source.readAsBytesSync());
  });
}
