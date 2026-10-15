import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-322: a storyboard conte row is addressed by its SEAT, so an edit that
/// moves its rows to other seats — made anywhere: a delete in the timeline,
/// an undo — moves what the rail stands on and holds selected with them.
/// ↩️Only the rail's own drag did; a delete that pulled the seats in left
/// both on a seat their rows had left.
///
/// Cuts a and b hold the same group: Under (−1), Conte (0), Over (+1) and
/// High (+2).
void main() {
  const trackId = TrackId('t1');

  LayerRowAddress seat(int seat) =>
      LayerRowAddress(trackConteRowId(trackId, seat: seat));

  Layer drawn(
    String id, {
    LayerKind kind = LayerKind.storyboard,
    String? ridesOn,
    AttachedPlacement placement = AttachedPlacement.above,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    frames: const [],
  );

  Cut cutOf(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      drawn('$id-cel', kind: LayerKind.animation),
      drawn(
        '$id-under',
        ridesOn: '$id-conte',
        placement: AttachedPlacement.below,
      ),
      drawn('$id-conte'),
      drawn('$id-over', ridesOn: '$id-conte'),
      drawn('$id-high', ridesOn: '$id-conte'),
    ],
  );

  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-seat-follow'),
        name: 'Conte seat follow',
        createdAt: DateTime.utc(2026, 10, 10),
        tracks: [
          Track(id: trackId, name: 'V1', cuts: [cutOf('a'), cutOf('b')]),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// A session whose storyboard stands on [row].
  EditorSessionManager standingOn(LayerRowAddress row) {
    final session = sessionOf()
      ..standOnRow(row, panel: WorkingPanel.storyboard, globalFrameIndex: 3);
    expect(session.storyboardStandingRow, row, reason: '⛔전제: standing');
    return session;
  }

  List<Cut> cutsOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.cuts;

  /// Cut a's row [name] deleted in the TIMELINE, the way its delete button
  /// does it — and with it the row on its seat in cut b.
  void deleteInTheTimeline(EditorSessionManager session, String name) {
    session
      ..selectCut(const CutId('a'))
      ..standOnRow(LayerRowAddress(LayerId('a-$name')));
    expect(session.activeLayerId, LayerId('a-$name'), reason: '⛔전제');
    session.layerVerbs.deleteActiveLayer();
    expect(
      [
        for (final cut in cutsOf(session))
          for (final row in cut.layers)
            if (row.id.value.endsWith('-$name')) row.id.value,
      ],
      isEmpty,
      reason: '⛔전제: gone from every cut',
    );
  }

  /// The seats of cut a's group, top first, by name.
  List<String> seatsOf(EditorSessionManager session) => [
    for (final entry in conteGroupOf(cutsOf(session).first))
      '${entry.seat}:${entry.row.name}',
  ];

  group('🚨the stand follows its row', () {
    test('a delete under it pulls High in to seat 1 — the stand goes with '
        'it', () {
      final session = standingOn(seat(2));
      deleteInTheTimeline(session, 'over');

      expect(seatsOf(session), ['1:a-high', '0:a-conte', '-1:a-under']);
      expect(session.storyboardStandingRow, seat(1));
    });

    test('…and an undo takes it back out with the row', () {
      final session = standingOn(seat(2));
      deleteInTheTimeline(session, 'over');
      expect(session.storyboardStandingRow, seat(1), reason: '⛔전제');

      session.undo();

      expect(seatsOf(session), [
        '2:a-high',
        '1:a-over',
        '0:a-conte',
        '-1:a-under',
      ]);
      expect(session.storyboardStandingRow, seat(2));
    });
  });

  group('🚨a stand whose row was deleted is handed on as the timeline\'s '
      'delete hands on, over the group', () {
    test('to the row taking its place: Over gone, High comes down to its '
        'seat', () {
      final session = standingOn(seat(1));
      deleteInTheTimeline(session, 'over');
      expect(session.storyboardStandingRow, seat(1));
    });

    test('to the row above it from the bottom row: Under gone, the conte', () {
      final session = standingOn(seat(-1));
      deleteInTheTimeline(session, 'under');
      expect(session.storyboardStandingRow, seat(0));
    });
  });

  test('🚨the selection follows its rows, and a row deleted leaves it — the '
      'storyboard\'s delete of the row it stands on', () {
    final session = standingOn(seat(1));
    expect(session.activeLayerId, const LayerId('a-over'), reason: '⛔전제');
    session.rowSelection.value = [seat(2), seat(1), seat(-1)];

    session.layerVerbs.deleteActiveLayer();

    expect(seatsOf(session), ['1:a-high', '0:a-conte', '-1:a-under']);
    expect(session.rowSelection.value, [seat(1), seat(-1)]);
  });

  test('🚨working in the storyboard, the row its rail lights follows too — '
      'though the edit moved no layer you draw on', () {
    final session = standingOn(seat(2));
    expect(session.activeLayerId, const LayerId('a-high'), reason: '⛔전제');

    session.cutCommandCoordinator.deleteLayer(
      cutId: const CutId('a'),
      layerId: const LayerId('a-over'),
    );
    session.notifyChanged();

    expect(session.activeLayerId, const LayerId('a-high'), reason: '⛔전제');
    expect(session.standing.currentRowListenable.value, seat(1));
  });

  test('🚨a seat is counted in the project it was written in: a stand '
      'written after an edit, before the edit is announced, stays', () {
    final session = standingOn(seat(0));
    // Over and High trade seats in every cut, unannounced.
    session.repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(
              cuts: [
                for (final cut in track.cuts)
                  cut.copyWith(
                    layers: [
                      ...cut.layers.take(3),
                      cut.layers[4],
                      cut.layers[3],
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
    expect(seatsOf(session), [
      '2:a-over',
      '1:a-high',
      '0:a-conte',
      '-1:a-under',
    ], reason: '⛔전제');

    // High's seat now — written into the project the edit made.
    session.standOnRow(seat(1), panel: WorkingPanel.storyboard);
    session.notifyChanged();

    expect(session.storyboardStandingRow, seat(1));
  });
}
