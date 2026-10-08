@Tags(['benchmark'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/project_scratch_folder.dart';

/// 🚨F-304 (유저 2026-10-06): 「무거운 상태에서 저장버튼누르면 화면이 멈추고,
/// 그 상태에서 시간 지나면 저장창 뜨는데 … 멈추는게 아니라 뭔가 하고있다
/// 라는걸 제대로 표시하기위해」.
///
/// ⛔**NOT a correctness test** — it prints numbers. Run it with
/// `--run-skipped --tags benchmark`; `F304_CELS` (default 20) is how many
/// whole-canvas cels the save carries, `F304_MODE` is `append` (the common
/// Ctrl+S onto the file the project is in — the default) or `full`.
///
/// What it reads is the longest stretch the main isolate could not answer a
/// timer that asks every 2ms — what a person sees as the screen standing
/// still, the spinner with it — beside when the first report arrived and
/// when the save ended.
void main() {
  test('READING: how long a heavy save holds the main isolate', () async {
    final cels = int.parse(Platform.environment['F304_CELS'] ?? '20');
    final append = (Platform.environment['F304_MODE'] ?? 'append') == 'append';
    final folder = Directory.systemTemp.createTempSync('f304-heavy-save');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll(r'\', '/')}/heavy.anicel';
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final keys = <BrushFrameKey>[];
    for (var i = 0; i < cels; i += 1) {
      s.cutVerbs.createCut();
      s.createDrawingAtCurrentFrame();
      final selection = s.editingCanvas.activeBrushEditorSelection!;
      keys.add(
        s.brushFrameKeyForCut(
          s.requireActiveCut,
          selection.layerId,
          selection.frameId,
        ),
      );
      _inkTheWholeCel(s, keys.last, shade: i);
    }
    expect(keys.toSet(), hasLength(cels), reason: '⛔premise: one cel each');
    if (append) {
      await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
      for (final (index, key) in keys.indexed) {
        _inkTheWholeCel(s, key, shade: index + 1);
      }
    }

    final watch = Stopwatch()..start();
    var last = 0;
    var longest = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 2), (_) {
      final now = watch.elapsedMilliseconds;
      longest = math.max(longest, now - last);
      last = now;
    });
    int? firstReport;
    await s.projectDoor.saveProjectToFile(
      path,
      asked: SaveAsked.byAPerson,
      onProgress: (_) => firstReport ??= watch.elapsedMilliseconds,
    );
    ticker.cancel();
    final total = watch.elapsedMilliseconds;
    longest = math.max(longest, total - last);

    // ignore: avoid_print — a benchmark's reading IS its output.
    print(
      '[f304] cels=$cels mode=${append ? 'append' : 'full'} '
      'longest=${longest}ms firstReport=${firstReport}ms total=${total}ms',
    );
    expect(firstReport, isNotNull, reason: '⛔premise: the save reported');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Covers [key]'s whole canvas with one stroke of overlapping dabs, so every
/// tile of the cel holds pixels — the weight a heavy session's save carries.
void _inkTheWholeCel(
  EditorSessionManager s,
  BrushFrameKey key, {
  required int shade,
}) {
  final size = s.requireActiveCut.canvasSize;
  var sequence = 0;
  BrushFrameEditingCoordinator(
    initialFrameKey: key,
    frameStore: s.renderCaches.brushFrameStore,
    sessionStore: BrushFrameEditSessionStore(canvasSize: size, tileSize: 256),
    historyPolicy: const BrushHistoryPolicy(),
  ).commitSourceStroke(
    sourceDabs: [
      for (var y = 0; y < size.height + 128; y += 128)
        for (var x = 0; x < size.width + 128; x += 128)
          BrushDab(
            center: CanvasPoint(x: x.toDouble(), y: y.toDouble()),
            color: 0xFF000000 | ((shade * 37) & 0xFF) << 16 | (x & 0xFF) << 8,
            size: 200,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: sequence++,
          ),
    ],
  );
}
