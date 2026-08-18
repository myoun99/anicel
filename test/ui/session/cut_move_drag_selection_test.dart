import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/session/drags/cut_move_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// D17's band on the cut axis, at the drag's own seam: the published span
/// follows the run's LANDED extent, not a rigid shift of its old width.
///
/// A reorder re-keys interior position gaps (the gaps stay with positions),
/// so a multi-cut run's extent can change when the rank flips — a band that
/// keeps its old width then overlaps a neighbour the user never selected,
/// and the frames × layout derivation hands that neighbour to the delete
/// verbs.
void main() {
  const trackId = TrackId('band-track');
  const a = CutId('a');
  const b = CutId('b');
  const c = CutId('c');
  const d = CutId('d');

  Cut cut(CutId id, {required int gap, required int duration}) => Cut(
    id: id,
    name: id.value,
    duration: duration,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: LayerId('${id.value}-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );

  /// A[0,10) — B[14,24) glued 4 behind A — C[24,34) — D[34,44): the run
  /// [A,B] carries a 4-frame interior gap, and D stands right behind the
  /// seat the run will land in.
  Track sparseTrack() => Track(
    id: trackId,
    name: 'V',
    cuts: [
      cut(a, gap: 0, duration: 10),
      cut(b, gap: 4, duration: 10),
      cut(c, gap: 0, duration: 10),
      cut(d, gap: 0, duration: 10),
    ],
  );

  ({
    CutMoveDrag? drag,
    List<TrackFrameRangeSelection?> published,
    List<({List<CutId> order, Map<CutId, int> afterGaps})> orderCommits,
  })
  begin({required TrackFrameRangeSelection? selection}) {
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    final published = <TrackFrameRangeSelection?>[];
    final orderCommits =
        <({List<CutId> order, Map<CutId, int> afterGaps})>[];
    final drag = CutMoveDrag.begin(
      cutId: a,
      tracks: [sparseTrack()],
      selectedCutIds: const [a, b],
      preview: preview,
      selection: selection,
      publishSelection: published.add,
      commitOrder:
          ({
            required trackId,
            required order,
            required beforeGaps,
            required afterGaps,
          }) => orderCommits.add((order: order, afterGaps: afterGaps)),
      commitGaps: ({required beforeGaps, required afterGaps}) {},
    );
    return (drag: drag, published: published, orderCommits: orderCommits);
  }

  /// The cut-row selection covering exactly the run [A,B] = [0,24).
  TrackFrameRangeSelection runSelection() => const TrackFrameRangeSelection(
    trackId: trackId,
    anchorRow: TrackRowAddress(trackId),
    startFrame: 0,
    endFrameExclusive: 24,
  );

  test('the band follows the LANDED extent through a reorder — never its '
      'old width over a neighbour that did not move', () {
    final log = begin(selection: runSelection());

    // +14 reaches the seat past C: order [C,A,B,D], the run's interior
    // gap re-keys 4→0, so the run lands as A[14,24) B[24,34) — 20 frames
    // where it left as 24.
    log.drag!.update(14);
    final midDrag = log.published.last!;
    expect(midDrag.startFrame, 14);
    expect(
      midDrag.endFrameExclusive,
      34,
      reason: 'a rigid shift would say 38 and overlap D[34,44) — the '
          'frames × layout derivation would then hand D to the delete verbs',
    );

    log.drag!.commit();
    expect(log.orderCommits.single.order, [c, a, b, d]);
    expect(log.orderCommits.single.afterGaps, {a: 4, b: 0});
    final landed = log.published.last!;
    expect(landed.startFrame, 14);
    expect(landed.endFrameExclusive, 34);
    expect(landed.anchorRow, const TrackRowAddress(trackId));
  });

  test('cancel puts the band back exactly where the drag found it', () {
    final log = begin(selection: runSelection());

    log.drag!.update(14);
    log.drag!.cancel();

    final restored = log.published.last!;
    expect(restored.startFrame, 0);
    expect(restored.endFrameExclusive, 24);
  });

  test('an SE-row selection merely overlapping the frames does NOT ride — '
      'a cut move moves no SE content', () {
    final log = begin(
      selection: const TrackFrameRangeSelection(
        trackId: trackId,
        anchorRow: LayerRowAddress(LayerId('se-row')),
        startFrame: 0,
        endFrameExclusive: 24,
      ),
    );

    log.drag!.update(14);
    log.drag!.commit();

    expect(
      log.published,
      isEmpty,
      reason: 'only the CUT ROW\'s own selection is the run\'s band',
    );
  });
}
