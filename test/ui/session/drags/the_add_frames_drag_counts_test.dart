import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/session/drags/run_frames_add_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// The "+ add frames" drag at a run edge — nothing named it (the audit's
/// untested-file pass, 2026-09-05).
///
/// 🚨Its input is the COUNT of new drawings, absolute like the audio
/// slide's offset rather than a delta: 0 shows the committed state. And the
/// ids it hands out are RESERVED deterministically, so every preview step
/// and the commit agree about which drawing is which.
void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: id);

  Layer row({int blocks = 2}) => Layer(
    id: const LayerId('l'),
    name: 'A',
    frames: [for (var i = 1; i <= blocks; i += 1) frame('frame-$i')],
    timeline: {
      for (var i = 0; i < blocks; i += 1)
        i: TimelineExposure.drawing(FrameId('frame-${i + 1}'), length: 1),
    },
    kind: LayerKind.image,
  );

  List<Track> tracksHolding(Layer layer) => [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'c',
          layers: [layer],
          duration: 12,
          canvasSize: const CanvasSize(width: 100, height: 100),
        ),
      ],
    ),
  ];

  ({
    RunFramesAddDrag? drag,
    ValueNotifier<TimelineDragPreview?> preview,
    List<({Layer before, Layer after})> commits,
  })
  open({
    Layer? layer,
    bool eligible = true,
    int blockStartIndex = 0,
    bool atEnd = true,
  }) {
    final before = layer ?? row();
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    final commits = <({Layer before, Layer after})>[];
    return (
      drag: RunFramesAddDrag.begin(
        layerId: const LayerId('l'),
        blockStartIndex: blockStartIndex,
        atEnd: atEnd,
        blockMoveEligible: (_) => eligible,
        layerById: (_) => before,
        tracksNow: () => tracksHolding(before),
        activeCutFrameCount: () => 12,
        preview: preview,
        commitLayerDrag: ({required before, required after}) =>
            commits.add((before: before, after: after)),
      ),
      preview: preview,
      commits: commits,
    );
  }

  Layer previewLayerOf(ValueNotifier<TimelineDragPreview?> preview) =>
      (preview.value! as ExposureEdgeDragPreview).previewLayer;

  test('⛔a row that stands down gives no object — no object, no drag', () {
    expect(open(eligible: false).drag, isNull);
  });

  test('⛔no run at that index gives no object', () {
    expect(open(blockStartIndex: 99).drag, isNull);
  });

  test('🚨a count of ZERO shows the COMMITTED state — the input is a count, '
      'not a delta', () {
    final session = open();

    session.drag!.update(3);
    expect(session.preview.value, isNotNull);

    session.drag!.update(0);
    expect(session.preview.value, isNull);
  });

  test('a negative count is the same as zero', () {
    // ⚠️Answered twice on purpose-by-accident: the drag returns early and
    // `layerWithNewFramesAtRunEdge` refuses `count < 1` as well, so a
    // mutant on either alone survives. What is pinned here is the
    // BEHAVIOUR, which is what a caller depends on.
    final session = open();

    session.drag!.update(-4);

    expect(session.preview.value, isNull);
  });

  test('the preview grows the run by exactly the count asked for', () {
    final session = open();

    session.drag!.update(3);

    final preview = previewLayerOf(session.preview);
    expect(preview.frames, hasLength(5), reason: '2 + 3');
  });

  test('🚨the ids are RESERVED — the same ordinal resolves the same id on '
      'every step, so the preview and the commit agree about which '
      'drawing is which', () {
    final session = open();

    session.drag!.update(2);
    final firstPass = [
      for (final f in previewLayerOf(session.preview).frames) f.id.value,
    ];
    session.drag!.update(3);
    final secondPass = [
      for (final f in previewLayerOf(session.preview).frames) f.id.value,
    ];

    expect(
      secondPass.take(firstPass.length),
      firstPass,
      reason: 'growing the drag must not renumber what it already showed',
    );
  });

  test('the reserved ids do not collide with ids the project already has', () {
    final session = open();

    session.drag!.update(3);

    final ids = [
      for (final f in previewLayerOf(session.preview).frames) f.id.value,
    ];
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.where((id) => id == 'frame-1'), hasLength(1));
  });

  test('commit lands ONE step carrying both sides', () {
    final session = open();

    session.drag!.update(3);
    session.drag!.commit();

    expect(session.commits, hasLength(1));
    expect(session.commits.single.before.frames, hasLength(2));
    expect(session.commits.single.after.frames, hasLength(5));
    expect(session.preview.value, isNull);
  });

  test('a drag that ends at zero commits nothing', () {
    final session = open();

    session.drag!.update(3);
    session.drag!.update(0);
    session.drag!.commit();

    expect(session.commits, isEmpty);
    expect(session.preview.value, isNull);
  });

  test('cancel drops the preview and touches no history', () {
    final session = open();

    session.drag!.update(3);
    session.drag!.cancel();

    expect(session.commits, isEmpty);
    expect(session.preview.value, isNull);
  });
}
