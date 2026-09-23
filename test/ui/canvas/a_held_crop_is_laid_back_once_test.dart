import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/static_composite_bake.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★A HELD CROP IS LAID BACK ONCE, HOWEVER OFTEN ITS SLOTS ARE RECORDED
/// (유저 2026-09-24 「성능적인 면은 아주 중요하니까 철저하게 하자」).
///
/// A row stored as its ink and drawn other than texel for texel — its image
/// is at another level than the display's — is drawn from the whole image
/// laid back ([LaidBackWhole]). 🔬On the user's project on the Windows app,
/// crossing 50% while the new level's images were still coming, the stack
/// recorded its slots again on every frame the zoom moved the buffer and
/// every record laid every crop back again: 111 whole images for 8 rows over
/// one pinch, frames at p95 75–104ms against 15–27ms with whole images kept.
///
/// ⚠️The images of the level the display asks for are held back
/// ([_OnlyTheFullLevel]) — that is the state a real zoom crosses into, and
/// the only one where a held crop lands resampled.
void main() {
  const tile = 16;
  const canvasSize = CanvasSize(width: 150, height: 101);
  const view = Size(60, 40);

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  // Ink in a corner of each cel, so each is stored as its ink.
  const cels = <String, List<(double, double)>>{
    'interior': [(60, 44), (72, 52)],
    'leftTop': [(4, 5), (18, 3)],
    'rightBottom': [(147, 98), (131, 90)],
    'active': [(40, 70)],
  };
  const inkRows = ['interior', 'leftTop', 'rightBottom'];

  BrushFrameStore storeWithCels() {
    final store = BrushFrameStore();
    for (final MapEntry(key: id, value: points) in cels.entries) {
      BrushFrameEditingCoordinator(
        initialFrameKey: key(id),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: tile,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          for (final (i, (x, y)) in points.indexed)
            BrushDab(
              center: CanvasPoint(x: x, y: y),
              color: 0xFF2040C0,
              size: 9,
              opacity: 1,
              flow: 1,
              hardness: 0.4,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: i,
            ),
        ],
      );
    }
    return store;
  }

  final nodes = <CompositeNode<CanvasStackRow>>[
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: key('interior'), opacity: 1),
    ),
    CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: key('active')),
    ),
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: key('leftTop'), opacity: 0.8),
    ),
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: key('rightBottom'), opacity: 1),
    ),
  ];

  /// The stack at the full level holding every row's ink, then zoomed to
  /// 45% — a level below — before any of that level's images can come.
  Future<
    ({
      _OnlyTheFullLevel images,
      ValueNotifier<CanvasViewport> viewport,
      StaticCompositeBake bake,
    })
  >
  crossedALevel(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = storeWithCels();
    final images = _OnlyTheFullLevel(frameStore: store);
    addTearDown(images.dispose);
    for (final id in inkRows) {
      final held = await tester.runAsync(
        () => images.prepare(
          key: key(id),
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: const [],
          inkSuffices: true,
        ),
      );
      expect(held!.isInk, isTrue, reason: 'fixture: $id is stored as ink');
    }
    final viewport = ValueNotifier(CanvasViewport());
    addTearDown(viewport.dispose);
    final active = BitmapSurfacePainter(
      surface: BrushFrameDisplayCacheService(
        frameStore: store,
        canvasSize: canvasSize,
      ).prepareFramePreview(key('active')).previewSurface,
      showTransparentBackground: false,
      lineage: 'a-held-crop',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: view.width,
              height: view.height,
              child: ValueListenableBuilder<CanvasViewport>(
                valueListenable: viewport,
                builder: (context, value, _) => CanvasLayerStackView(
                  nodes: nodes,
                  imageCache: images,
                  canvasSize: canvasSize,
                  viewport: value,
                  activeSurfacePainter: active,
                  paintPaper: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      debugKeptWholes,
      0,
      reason: 'anchor: at their own level the crops land texel for texel',
    );
    viewport.value = CanvasViewport(zoom: 0.45);
    await tester.pump();
    final bake =
        // ignore: avoid_dynamic_calls
        (tester.state(find.byType(CanvasLayerStackView)) as dynamic).debugBake
            as StaticCompositeBake;
    return (images: images, viewport: viewport, bake: bake);
  }

  setUp(() {
    debugWholesLaidBack = 0;
    debugKeptWholes = 0;
  });

  testWidgets('a crop drawn off its level is laid back once, however often '
      'the moving view records its slots again', (tester) async {
    final (:images, :viewport, :bake) = await crossedALevel(tester);
    final recorded = bake.recordCount;
    for (var step = 1; step <= 6; step += 1) {
      viewport.value = CanvasViewport(
        zoom: 0.45,
        panX: -3.0 * step,
        panY: -2.0 * step,
      );
      await tester.pump();
    }
    expect(
      bake.recordCount - recorded,
      greaterThanOrEqualTo(6),
      reason: 'fixture: every step moved the buffer and recorded the slots '
          'again — a replay would lay nothing back either way',
    );
    expect(
      debugWholesLaidBack,
      inkRows.length,
      reason: 'one whole per held crop: a crop\'s whole is the same bytes '
          'every time, and laying it back per record was 111 wholes for 8 '
          'rows over one pinch on the Windows app',
    );
    expect(debugKeptWholes, inkRows.length);
  });

  testWidgets('the kept whole goes when its crop does — when the level it '
      'waited for comes, and with the stack', (tester) async {
    final (:images, :viewport, bake: _) = await crossedALevel(tester);
    expect(
      debugKeptWholes,
      inkRows.length,
      reason: 'anchor: the crops are drawn from their wholes',
    );

    // The level the display asks for arrives: each row takes its image, and
    // lets the crop it held go — with the whole laid back from it, which is
    // a whole cel image resident for nothing.
    images.everyLevel = true;
    for (final id in inkRows) {
      await tester.runAsync(
        () => images.prepare(
          key: key(id),
          canvasSize: canvasSize,
          quality: PlaybackQuality.half,
          sourceEffects: const [],
          inkSuffices: true,
        ),
      );
    }
    viewport.value = CanvasViewport(zoom: 0.45, panX: -1);
    await tester.pump();
    expect(debugKeptWholes, 0, reason: 'the held crops went, and so must '
        'their wholes');

    // Off its level again, then the stack goes while the crops are held.
    images.everyLevel = false;
    viewport.value = CanvasViewport(zoom: 0.2);
    await tester.pump();
    expect(
      debugKeptWholes,
      inkRows.length,
      reason: 'anchor: half-level crops drawn into a quarter buffer',
    );
    await tester.pumpWidget(const SizedBox());
    expect(debugKeptWholes, 0, reason: 'the stack took its wholes with it');
  });
}

/// A cache that has only the level it was warmed at — full — and keeps any
/// other level waiting until [everyLevel], the way a zoom crosses into a
/// level whose images are still being made.
class _OnlyTheFullLevel extends LayerFrameImageCache {
  _OnlyTheFullLevel({required super.frameStore});

  bool everyLevel = false;

  bool _serves(PlaybackQuality quality) =>
      everyLevel || quality == PlaybackQuality.full;

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    required bool makePictures,
    bool inkSuffices = false,
  }) => _serves(quality)
      ? super.prepareSyncOrNull(
          key: key,
          canvasSize: canvasSize,
          quality: quality,
          sourceEffects: sourceEffects,
          makePictures: makePictures,
          inkSuffices: inkSuffices,
        )
      : null;

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
  }) => _serves(quality)
      ? super.prepare(
          key: key,
          canvasSize: canvasSize,
          quality: quality,
          sourceEffects: sourceEffects,
          shouldAbort: shouldAbort,
          inkSuffices: inkSuffices,
        )
      // Still being made: the stack keeps what it holds.
      : Completer<LayerFrameImage?>().future;
}
