@Tags(['gc'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';

import '../helpers/collect_garbage.dart';
import '../helpers/draw_on_current_frame.dart';
import '../helpers/native_engine_path.dart';
import '../helpers/settle_async.dart';

/// 🗣️F-505 (유저 2026-10-29): 「프로젝트 2개연상태서 하나 무거운거, 하나
/// 초기프로젝트면 무거운거 닫으면 언두기록도 안되니 초기프로젝트분만큼만 메모리
/// 존재해야하는데 무거운 프로젝트의 메모리가 아직 남아있는듯함. 닫았는데도
/// 1700메가사용중.그중 엔진폰트항목이 1300, 묘화엔진 타일풀이 413임」.
///
/// 🔬Measured here before the fix (a tab of thirty full cels closed beside an
/// empty one, two collections after): the closed session disposed and still
/// reached — its store holding 3,262MB the panel read as 「엔진·폰트·
/// 프레임워크」, and the engine's parking filled to its cap with blocks no
/// tab would ask for. After: 557MB for the process, nothing parked.
void main() {
  final enginePath = nativeEngineLibraryPathOrNull();

  testWidgets('a closed project lets go of its pictures and its history, the '
      'app\'s timeline tiles go with them, and the engine gives back what '
      'it parked of them', (tester) async {
    debugQaEngineLibraryPathOverride = enginePath;
    addTearDown(() => debugQaEngineLibraryPathOverride = null);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;

    Future<void> tapKey(String key) async {
      final target = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tapKey('top-strip-project-button');
    await tapKey('menu-file-new');
    final heavy = projects.active;
    drawCels(heavy, 4);
    heavy.cutVerbs.createCut();
    heavy.cutVerbs.createCut();
    heavy.historyManager.undo();
    await tester.pumpAndSettle();
    // The timeline's tiles are baked on the engine, off the test's clock.
    await settleAsync(
      tester,
      () =>
          !TimelineGridTileStore.instance.debugBusy &&
          TimelineGridTileStore.instance.tileImageBytes > 0,
    );
    final store = heavy.renderCaches.brushFrameStore;
    final engine = QaNativeEngine.instance!;
    expect(store.hotBakedBytes, greaterThan(0), reason: 'CONTROL');
    expect(heavy.historyManager.canUndo, isTrue, reason: 'CONTROL');
    expect(heavy.historyManager.canRedo, isTrue, reason: 'CONTROL');
    expect(
      TimelineGridTileStore.instance.tileImageBytes,
      greaterThan(0),
      reason: 'CONTROL: the timeline baked its rows',
    );

    await tapKey('project-tab-close-1');
    await tester.tap(find.byKey(const ValueKey<String>('system-exit-close')));
    // It goes after the frame that stops showing it (`_letGo`) — and the
    // wait leaves on that frame, before real time could land the tab on
    // screen's tiles again.
    await settleAsync(tester, () => heavy.disposed);
    expect(heavy.disposed, isTrue);
    expect(
      TimelineGridTileStore.instance.tileImageBytes,
      0,
      reason: 'the app\'s timeline tiles went with it — the tab on screen '
          'bakes its own again',
    );
    await tester.pumpAndSettle();
    expect(store.hotBakedBytes, 0, reason: 'its pictures');
    expect(heavy.historyManager.canUndo, isFalse, reason: 'its history');
    expect(heavy.historyManager.canRedo, isFalse, reason: 'its history');

    await tester.runAsync(
      () => collectGarbageUntil(() => engine.tilePoolParkedBytes == 0),
    );
    expect(
      engine.tilePoolParkedBytes,
      0,
      reason: 'what came back of its tiles is not kept for reuse',
    );
  }, skip: enginePath == null);
}

/// [count] cels of ink on [s]'s first layer, each a dab across some tiles.
void drawCels(EditorSessionManager s, int count) {
  s.createDrawingAtCurrentFrame();
  final selection = s.editingCanvas.activeBrushEditorSelection!;
  final cut = s.requireActiveCut;
  final first = s.brushFrameKeyForCut(
    cut,
    selection.layerId,
    selection.frameId,
  );
  for (var index = 0; index < count; index += 1) {
    inkCel(
      s,
      BrushFrameKey(
        projectId: first.projectId,
        trackId: first.trackId,
        cutId: first.cutId,
        layerId: first.layerId,
        frameId: FrameId('cel-$index'),
      ),
      canvasSize: cut.canvasSize,
      at: CanvasPoint(x: 300, y: 300),
      size: 400,
    );
  }
}
