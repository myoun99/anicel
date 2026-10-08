import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';

/// Host-driven reframing: the panel fits the viewport onto the request's
/// rect exactly once per [CanvasAutoFrameRequest.token] change. The
/// viewport stays fully user-owned while the request is null or its token
/// is stable.
void main() {
  const canvasSize = CanvasSize(width: 2000, height: 12000);

  Future<void> pumpPanel(
    WidgetTester tester, {
    required CanvasViewport viewport,
    required ValueChanged<CanvasViewport> onViewportChanged,
    CanvasAutoFrameRequest? autoFrame,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: null,
            availableFrameKeys: const [],
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            canvasSize: canvasSize,
            viewport: viewport,
            onViewportChanged: onViewportChanged,
            autoFrame: autoFrame,
            contentOverride: (context, viewport) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  testWidgets('a token change reframes once; a stable token never does', (
    tester,
  ) async {
    final changes = <CanvasViewport>[];
    // ⚠️The seed and the callback are DEVICE pixels; `changes` is kept in
    // RENDER units so every assertion below reads in the units it was
    // written in. Converting at the boundary and nowhere else is the point.
    var viewport = seedFromRender(tester, CanvasViewport());
    void onChanged(CanvasViewport next) {
      viewport = next;
      changes.add(renderOf(tester, next));
    }

    await pumpPanel(tester, viewport: viewport, onViewportChanged: onChanged);
    expect(changes, isEmpty);

    const request = CanvasAutoFrameRequest(
      token: 'page-0',
      rect: Rect.fromLTWH(0, 0, 500, 700),
    );
    await pumpPanel(
      tester,
      viewport: viewport,
      onViewportChanged: onChanged,
      autoFrame: request,
    );
    await tester.pump(); // post-frame reframe lands
    expect(changes, hasLength(1));
    // Fit-style: the rect's center maps onto itself under the new viewport
    // only if unchanged — instead verify the whole rect became visible.
    final fitted = changes.single;
    expect(fitted.zoom, lessThan(1.0)); // 700-tall rect shrunk to fit
    expect(fitted, isNot(CanvasViewport()));

    // Same token again → no further reframes, the user owns the viewport.
    await pumpPanel(
      tester,
      viewport: viewport,
      onViewportChanged: onChanged,
      autoFrame: request,
    );
    await tester.pump();
    expect(changes, hasLength(1));

    // New token → exactly one more reframe.
    await pumpPanel(
      tester,
      viewport: viewport,
      onViewportChanged: onChanged,
      autoFrame: const CanvasAutoFrameRequest(
        token: 'page-1',
        rect: Rect.fromLTWH(0, 800, 500, 700),
      ),
    );
    await tester.pump();
    expect(changes, hasLength(2));
  });
}
