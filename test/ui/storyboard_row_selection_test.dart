import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The storyboard's rail mixes TRACK rows (V) with LAYER rows (S), and the
/// two used to light from unrelated states — the V row from "the active cut
/// lives on this track", the S rows from the active layer — so both could
/// read as selected at once. `selectedRow` is the one answer.
///
/// The rail's only layer rows are the track-SE rows, so the active layer
/// names a row here only while it IS one: every other layer lives inside a
/// cut, and the row that owns it is the track row.
void main() {
  const trackId = TrackId('track-a');
  const seLayerId = LayerId('track-a-se-1');

  Project projectWithTwoCuts() {
    final cutA = createDefaultCut(
      cutId: const CutId('cut-a'),
      name: 'cut-a',
      layerId: defaultLayerIdForSequence(1),
    );
    final cutB = createDefaultCut(
      cutId: const CutId('cut-b'),
      name: 'cut-b',
      // Far from cut A's sequence on purpose: a layer ADDED to cut A must
      // not collide with a layer cut B already has, or "the cut does not
      // have that layer" stops being testable.
      layerId: defaultLayerIdForSequence(9),
    );
    return Project(
      id: const ProjectId('row-selection-project'),
      name: 'Row selection',
      createdAt: DateTime.utc(2026, 7, 26),
      tracks: [
        Track(
          id: trackId,
          name: 'V1',
          // A leading gap on cut B gives the track a real GAP address to
          // park in — where the session drops the active cut entirely.
          cuts: [cutA, cutB.copyWith(leadingGapFrames: 4)],
          seLayers: [createTrackSeLayer(trackId: trackId, slot: 1)],
        ),
      ],
    );
  }

  EditorSessionManager sessionFor(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  /// A second drawing layer on the active cut, so "the layer the cut was
  /// left on" has somewhere to be that is not the top row.
  LayerId addSecondDrawingLayer(EditorSessionManager session) {
    final before = {for (final layer in session.layers) layer.id};
    session.addLayer();
    return session.layers
        .firstWhere((layer) => !before.contains(layer.id))
        .id;
  }

  group('selectedRow', () {
    test('a fresh session is on the TRACK row: the active layer is a '
        'drawing cel, which is not a rail row of its own', () {
      final session = sessionFor(projectWithTwoCuts());

      expect(session.selectedRow, const TrackRowAddress(trackId));
    });

    test('picking an S row moves the rail to it', () {
      final session = sessionFor(projectWithTwoCuts());

      session.selectRow(const LayerRowAddress(seLayerId));

      expect(session.selectedRow, const LayerRowAddress(seLayerId));
    });

    test('picking the V row takes the rail back off the S row — even with '
        'the same cut still active, which changes nothing else', () {
      final session = sessionFor(projectWithTwoCuts());
      session.selectRow(const LayerRowAddress(seLayerId));
      final activeCutBefore = session.activeCutId;

      session.selectRow(const TrackRowAddress(trackId));

      expect(session.selectedRow, const TrackRowAddress(trackId));
      expect(session.activeCutId, activeCutBefore);
    });

    test('NEITHER kind moves the drawing target: the rail\'s row and the '
        "CUT's row are separate selections", () {
      final session = sessionFor(projectWithTwoCuts());
      final drawingLayerId = session.activeLayerId;

      session.selectRow(const LayerRowAddress(seLayerId));
      expect(session.activeLayerId, drawingLayerId);

      session.selectRow(const TrackRowAddress(trackId));
      expect(session.activeLayerId, drawingLayerId);
    });

    test("selecting a LAYER leaves the rail's row alone — that is the cut's "
        'row selection, not this one', () {
      final session = sessionFor(projectWithTwoCuts());
      session.selectRow(const LayerRowAddress(seLayerId));

      session.selectLayer(defaultLayerIdForSequence(1));

      expect(session.selectedRow, const LayerRowAddress(seLayerId));
    });

    test('picking a V row announces, so the rail repaints even when the '
        'active cut does not move', () {
      final session = sessionFor(projectWithTwoCuts());
      session.selectRow(const LayerRowAddress(seLayerId));
      var notifications = 0;
      session.addListener(() => notifications++);

      session.selectRow(const TrackRowAddress(trackId));

      expect(notifications, greaterThan(0));
    });

    test('re-picking the row already selected stays silent', () {
      final session = sessionFor(projectWithTwoCuts());
      session.selectRow(const LayerRowAddress(seLayerId));
      var notifications = 0;
      session.addListener(() => notifications++);

      session.selectRow(const LayerRowAddress(seLayerId));

      expect(notifications, 0);
    });
  });

  group('per-cut layer memory', () {
    test('an SE row is remembered like any other: what the timeline shows '
        'for it is a cut-local projection of the track layer', () {
      final session = sessionFor(projectWithTwoCuts());
      session.selectLayer(seLayerId);

      session.selectCut(const CutId('cut-b'));
      session.selectCut(const CutId('cut-a'));

      expect(session.activeLayerId, seLayerId);
    });

    test('a cut comes back on the layer it was left on', () {
      final session = sessionFor(projectWithTwoCuts());
      final secondLayerId = addSecondDrawingLayer(session);
      session.selectLayer(secondLayerId);

      session.selectCut(const CutId('cut-b'));
      session.selectCut(const CutId('cut-a'));

      expect(session.activeLayerId, secondLayerId);
    });

    test('a cut never visited still lands on its top row', () {
      final session = sessionFor(projectWithTwoCuts());
      final secondLayerId = addSecondDrawingLayer(session);
      session.selectLayer(secondLayerId);

      session.selectCut(const CutId('cut-b'));

      expect(session.activeLayerId, session.layers.first.id);
      expect(session.activeLayerId, isNot(secondLayerId));
    });

    test('parking in a gap and coming back keeps the layer: leaving for the '
        'void records the row too', () {
      final session = sessionFor(projectWithTwoCuts());
      final secondLayerId = addSecondDrawingLayer(session);
      session.selectLayer(secondLayerId);
      final gapFrame =
          session.trackFrameAxis().entryFor(const CutId('cut-b'))!.startFrame -
          1;

      // A gap park deselects the cut ENTIRELY (UI-R9 #3) — the layer has
      // to be recorded on the way out, not only on a cut-to-cut switch.
      session.selectGlobalFrame(gapFrame);
      expect(session.activeCutId, isNull);

      session.selectCut(const CutId('cut-a'));

      expect(session.activeLayerId, secondLayerId);
    });

    test('a remembered layer that the cut no longer has falls back to the '
        'top row instead of throwing', () {
      final session = sessionFor(projectWithTwoCuts());
      final secondLayerId = addSecondDrawingLayer(session);
      session.selectLayer(secondLayerId);
      // Leave, then UNDO the add from the other cut: the memory now holds
      // an id cut A no longer has — the case no cleanup pass guards.
      session.selectCut(const CutId('cut-b'));
      session.undo();

      session.selectCut(const CutId('cut-a'));

      expect(
        session.layers.map((Layer layer) => layer.id),
        isNot(contains(secondLayerId)),
      );
      expect(session.activeLayerId, session.layers.first.id);
    });
  });
}
