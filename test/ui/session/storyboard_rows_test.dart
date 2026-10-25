import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/storyboard_rows.dart';

/// THE STORYBOARD'S NEXT CUT — the walk along the track in storyboard
/// order.
///
/// ⚠️Nothing named it. `storyboardSelectedCutIds` has its pins in
/// `storyboard_cut_range_test`; the next-cut walk had none, and it is the
/// sort of law that reads as correct in every direction until a step goes
/// the wrong way on a device.
///
/// ↩️This file also pinned the order of a list of the rail's rows the
/// session kept for a cross-row drag to walk (feedback #14 — leading with
/// the cut row inverted every drag). A sweep now walks the rows the panel
/// draws, lanes and all, and the list is gone
/// (conte-sweep-leaves-the-lanes-out).
void main() {
  const trackId = TrackId('rail-track');
  const seLow = LayerId('rail-s0');
  const seHigh = LayerId('rail-s1');

  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: const CanvasSize(width: 320, height: 180),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const [], timeline: {}),
    ],
  );

  Layer se(LayerId id, String name) =>
      Layer(id: id, name: name, kind: LayerKind.se, frames: const [], timeline: {});

  /// Three cuts on one track, and TWO SE slots — slot 0 sits just above the
  /// cut row on screen, slot 1 above that.
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('rail'),
        name: 'Rail',
        createdAt: DateTime.utc(2026, 9, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'Video',
            cuts: [cut('cut-1', 6), cut('cut-2', 6), cut('cut-3', 6)],
            seLayers: [se(seLow, 'S1'), se(seHigh, 'S2')],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  StoryboardRows railOf(EditorSessionManager s) => s.storyboardRows;

  test('the next cut in STORYBOARD order is the next one along the track, '
      'and the last cut has none', () {
    final s = session();
    final rail = railOf(s);

    expect(rail.nextCutIdInStoryboardOrder(const CutId('cut-1')),
        const CutId('cut-2'));
    expect(rail.nextCutIdInStoryboardOrder(const CutId('cut-2')),
        const CutId('cut-3'));
    expect(
      rail.nextCutIdInStoryboardOrder(const CutId('cut-3')),
      isNull,
      reason: 'the end of the film is an honest nothing, not a wrap to the '
          'first cut',
    );
  });

  test('a cut id the layout does not hold has no next cut either', () {
    final s = session();

    expect(
      railOf(s).nextCutIdInStoryboardOrder(const CutId('no-such-cut')),
      isNull,
    );
  });
}
