import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// A drag that keeps moving over a cut the canvas is not standing on — the
/// storyboard ruler scrubbing into the next cut — still shows that cut: the
/// compose in flight lands and is shown, and the view then chases the frame
/// that is current.
///
/// 🗣️F-206 (유저 2026-09-28): 「콘티패널 fi의 시작부분에서 스크럽하면 화면이
/// 검정색인채임. 손 때야 정상적으로 보임 … 스크럽하던 뭐던 존재하는게
/// 보여야함」. The view stood every compose down the moment the wanted frame
/// moved on, so a drag faster than one compose never landed a picture: the
/// cut showed its paper and, over an F.I, a screen of black.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  final layout = buildStoryboardTimelineLayout(
    Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: const CanvasSize(width: 4, height: 2),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'One',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'cut',
              layers: const [],
              duration: 8,
              canvasSize: canvasSize,
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  Future<void> pumpView(
    WidgetTester tester,
    _ComposesHeldBack composites,
    ValueNotifier<int?> frame,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CanvasTrackStackView(
          globalFrame: frame,
          positionsOf: (globalFrame) => resolveTrackStackContributions(
            layout: layout,
            spansOf: (_) => const [],
            globalFrameIndex: globalFrame,
          ),
          compositeCache: composites,
          qualityOf: () => PlaybackQuality.full,
          cameraFrameSize: const CanvasSize(width: 4, height: 2),
          cameraViewEnabled: false,
          cameraPoseOf: (cut, frameIndex) =>
              CameraPose(center: CanvasPoint(x: 4, y: 4)),
          pasteboardArgb: 0xff123456,
        ),
      ),
    ),
  );

  ui.Image? shown(WidgetTester tester) {
    for (final paint in tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('canvas-track-stack-frames')),
        matching: find.byType(CustomPaint),
      ),
    )) {
      if (paint.painter case final PlaybackFramePainter painter) {
        return painter.image;
      }
    }
    return null;
  }

  testWidgets('the compose in flight lands and shows although the drag has '
      'moved on, and the view then asks for the frame that is current', (
    tester,
  ) async {
    final composites = _ComposesHeldBack();
    final frame = ValueNotifier<int?>(1);
    addTearDown(frame.dispose);
    await pumpView(tester, composites, frame);
    expect(composites.asked, [1], reason: '⛔premise: frame 1 is composing');

    frame.value = 2;
    await tester.pump();
    expect(composites.asked, [1], reason: 'still one compose at a time');

    final picture = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(picture.dispose);
    composites.finishOldest(picture);
    // The landing runs as a microtask of this frame; the repaint it asks
    // for is the next one.
    await tester.pump();
    await tester.pump();

    expect(shown(tester), isNotNull, reason: 'the cut shows its picture');
    expect(composites.asked, [2], reason: 'and the current frame is next');
  });

  testWidgets('a cut that has left the view stands its compose down', (
    tester,
  ) async {
    final composites = _ComposesHeldBack();
    final frame = ValueNotifier<int?>(1);
    addTearDown(frame.dispose);
    await pumpView(tester, composites, frame);

    frame.value = null;
    await tester.pump();
    final picture = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(picture.dispose);

    expect(composites.finishOldest(picture), isFalse);
  });
}

/// A composite cache whose composes finish only when the test says so, and
/// finish the way the real one does: at the checkpoint it asks
/// `shouldAbort`, and a yes stands the compose down.
class _ComposesHeldBack extends CutFrameCompositeCache {
  _ComposesHeldBack()
    : super(
        layerImages: LayerFrameImageCache(frameStore: _store),
        frameStore: _store,
        frameKeyOf: _key,
      );

  static final _store = BrushFrameStore();

  static BrushFrameKey _key(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

  final _pending =
      <({int frame, bool Function() abort, Completer<ui.Image?> done})>[];
  final _landed = <int, ui.Image>{};

  /// The frames whose composes are in flight, oldest first.
  List<int> get asked => [for (final request in _pending) request.frame];

  /// Finishes the oldest compose; answers whether it landed.
  bool finishOldest(ui.Image picture) {
    final request = _pending.removeAt(0);
    if (request.abort()) {
      request.done.complete(null);
      return false;
    }
    _landed[request.frame] = picture;
    request.done.complete(picture);
    return true;
  }

  @override
  ui.Image? validCompositeOrNull({
    required Cut cut,
    required int frameIndex,
    required PlaybackQuality quality,
  }) => _landed[frameIndex];

  @override
  Future<ui.Image?> prepareCompositeInterruptible({
    required Cut cut,
    required int frameIndex,
    required PlaybackQuality quality,
    required bool Function() shouldAbort,
  }) {
    final done = Completer<ui.Image?>();
    _pending.add((frame: frameIndex, abort: shouldAbort, done: done));
    return done.future;
  }
}
