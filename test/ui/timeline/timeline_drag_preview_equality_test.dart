// A DRAG PREVIEW REBUILT WITH THE SAME CONTENT IS THE SAME PREVIEW — the
// per-track lists (effect chains, cut orders) compare by their elements,
// never by the identity of the list a step happened to allocate.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

void main() {
  const track = TrackId('t');
  LayerEffect blur() =>
      LayerEffect.defaults(id: const EffectId('e'), kind: EffectKind.blur);

  test('a block move with a rebuilt effect chain reads as unchanged', () {
    final a = BlockMoveDragPreview(
      previewLayers: const {},
      previewTrackEffects: {
        track: [blur()],
      },
    );
    final b = BlockMoveDragPreview(
      previewLayers: const {},
      previewTrackEffects: {
        track: [blur()],
      },
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('a block move whose chain differs, or is absent, reads as changed', () {
    final some = BlockMoveDragPreview(
      previewLayers: const {},
      previewTrackEffects: {
        track: [blur()],
      },
    );
    const none = BlockMoveDragPreview(previewLayers: {});
    const empty = BlockMoveDragPreview(
      previewLayers: {},
      previewTrackEffects: {},
    );
    expect(some, isNot(none));
    expect(none, isNot(empty));
    expect(none, const BlockMoveDragPreview(previewLayers: {}));
  });

  test('a cut trim with a rebuilt order list reads as unchanged', () {
    final a = CutTrimDragPreview(
      previewDurations: const {},
      previewOrder: {
        track: [const CutId('a'), const CutId('b')],
      },
    );
    final b = CutTrimDragPreview(
      previewDurations: const {},
      previewOrder: {
        track: [const CutId('a'), const CutId('b')],
      },
    );
    final reordered = CutTrimDragPreview(
      previewDurations: const {},
      previewOrder: {
        track: [const CutId('b'), const CutId('a')],
      },
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(reordered));
  });

  // The camera keys a block move carries ride as the camera's TRACK
  // (F-309) — the lanes as they are, compared as what they hold.
  group('a block move\'s camera track', () {
    const cut = CutId('c');
    TransformTrack positionAt(int frame) => TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        frame,
        CanvasPoint(x: 40, y: 30),
      ),
    );
    BlockMoveDragPreview carrying(TransformTrack track) => BlockMoveDragPreview(
      previewLayers: const {},
      cameraCutId: cut,
      cameraTrack: track,
    );

    test('rebuilt with the same keys it reads as unchanged; with a key a '
        'frame on, as changed', () {
      final a = carrying(positionAt(4));
      final b = carrying(positionAt(4));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(carrying(positionAt(5))));
    });

    test('reaches the project the storyboard and the sheet read, lane for '
        'lane — no key on a lane the drag did not key', () {
      final project = createDefaultProject();
      final open = project.tracks.first.cuts.first;
      final shown = projectWithTimelineDragPreview(
        project,
        BlockMoveDragPreview(
          previewLayers: const {},
          cameraCutId: open.id,
          cameraTrack: positionAt(4),
        ),
      );

      final camera = shown.tracks.first.cuts.first.camera.track;
      expect(camera, positionAt(4));
      expect(camera.scale.keys, isEmpty);
      expect(camera.rotation.keys, isEmpty);
    });
  });
}
