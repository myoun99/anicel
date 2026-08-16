import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import 'timeline_cell_probe.dart';

/// THE RESIZE LAW (device report 2026-08-17: open a project in a SMALL
/// window, then enlarge it — the blocks in the newly exposed width never
/// render; only a cut round-trip healed them).
///
/// The row painters' request set — the frame window paint() draws and
/// requests substrate tiles for — must derive from the CURRENT viewport
/// geometry. The broken shape: the row memo
/// ([TimelineFrameRowsScrollBody]) kept handing back rows whose painters
/// froze the viewport extent they were BUILT with, so a wider viewport
/// kept computing yesterday's narrower window — cells the user could see
/// were outside every row's paint window, nothing requested their spans,
/// and no amount of waiting could fill them.
void main() {
  final dllPath =
      '${Directory.current.path}\\build\\native_standalone\\Release\\qa_engine.dll';
  final dllAvailable = File(dllPath).existsSync();

  const cellWidth = 24.0;

  Future<EditorSessionManager> pumpTimeline(
    WidgetTester tester,
    ValueNotifier<double> zoom, {
    required Size physicalSize,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // A cut long enough that the content runs well past even the enlarged
    // viewport.
    for (var frame = 0; frame < 300; frame += 4) {
      session.selectFrameIndex(frame);
      if (session.canCreateDrawingAtCurrentFrame) {
        session.createDrawingAtCurrentFrame();
      }
    }
    session.selectFrameIndex(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: zoom.value,
              pixelsPerFrameListenable: zoom,
              onPixelsPerFrameChanged: (value) => zoom.value = value,
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  String animationLayerIdOf(EditorSessionManager session) => session.layers
      .firstWhere((layer) => layer.kind == LayerKind.animation)
      .id
      .value;

  /// A span-aligned frame index that the ENLARGED viewport shows but the
  /// small-window request set never covered — kept clear of the small
  /// window's one-span prefetch too, so under the broken shape nothing
  /// has ever requested it.
  int newlyExposedSpanStart(
    ({int startIndex, int endIndexExclusive}) smallWindow,
  ) {
    final span = timelineFrameWindowSpanFor(cellWidth);
    final clearOfPrefetch = smallWindow.endIndexExclusive + 2 * span;
    return ((clearOfPrefetch + span - 1) ~/ span) * span;
  }

  testWidgets('enlarging the window widens every row\'s paint window: a '
      'cell the resize exposed is INSIDE the request set', (tester) async {
    final zoom = ValueNotifier<double>(cellWidth);
    addTearDown(zoom.dispose);
    final session = await pumpTimeline(
      tester,
      zoom,
      physicalSize: const Size(800, 900),
    );
    final layerId = animationLayerIdOf(session);

    final smallWindow = timelineRowCellsPainterFor(
      tester,
      layerId,
    ).visibleFrameWindow();
    expect(
      smallWindow.endIndexExclusive,
      greaterThan(0),
      reason: 'sanity: the small window painted something',
    );

    // ---- the resize: same session, same scroll offset, wider glass ----
    tester.view.physicalSize = const Size(1600, 900);
    await tester.pumpAndSettle();

    final probeFrame = newlyExposedSpanStart(smallWindow);
    final viewportRect = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
    );
    final cellRect = timelineCellGlobalRect(tester, layerId, probeFrame);
    expect(
      cellRect.right,
      lessThan(viewportRect.right),
      reason:
          'sanity: frame $probeFrame is on screen in the enlarged window '
          '(the scenario is real only if the resize exposed it)',
    );

    expect(
      timelineCellInWindow(tester, layerId, probeFrame),
      isTrue,
      reason:
          'frame $probeFrame is visible after the resize, so it must be '
          'inside the row\'s paint window — the request set derives from '
          'the CURRENT viewport, not the one the row was built under',
    );
  });

  testWidgets('the spans the resize exposed actually get substrate tiles',
      (tester) async {
    if (!dllAvailable) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    TimelineGridTileStore.instance.clear();
    addTearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugForceDartFallback = false;
      TimelineGridTileStore.instance.clear();
    });

    final zoom = ValueNotifier<double>(cellWidth);
    addTearDown(zoom.dispose);
    final session = await pumpTimeline(
      tester,
      zoom,
      physicalSize: const Size(800, 900),
    );
    final layerId = animationLayerIdOf(session);
    final smallWindow = timelineRowCellsPainterFor(
      tester,
      layerId,
    ).visibleFrameWindow();

    tester.view.physicalSize = const Size(1600, 900);
    await tester.pumpAndSettle();

    // Let the raster drains converge: a landing repaints the rows, which
    // re-request whatever the capped queue dropped — pump and wait until
    // the landings go quiet.
    final store = TimelineGridTileStore.instance;
    for (var round = 0; round < 40; round += 1) {
      final before = store.revision.value;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (store.revision.value == before && round > 1) {
        break;
      }
    }

    // ⚠️ Probed ONCE, after quiescence: tileFor ENQUEUES on a miss, so a
    // second ask after another drain would hand the broken shape the very
    // tile this asserts on. One cold ask answers null and proves the
    // resize never requested the span.
    final painter = timelineRowCellsPainterFor(tester, layerId);
    final span = timelineFrameWindowSpanFor(cellWidth);
    final spanStart = newlyExposedSpanStart(smallWindow);
    final spanEnd = spanStart + span > painter.frameEndIndexExclusive
        ? painter.frameEndIndexExclusive
        : spanStart + span;
    expect(
      store.tileFor(
        painter: painter,
        spanStartIndex: spanStart,
        spanEndIndexExclusive: spanEnd,
        devicePixelRatio: 1.0,
      ),
      isNotNull,
      reason:
          'the newly exposed span [$spanStart, $spanEnd) must have been '
          'requested and rastered by the resize itself — the user watched '
          'these blocks stay blank until a cut round-trip',
    );
  });
}
