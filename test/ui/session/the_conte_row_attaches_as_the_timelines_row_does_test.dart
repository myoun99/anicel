import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️F-322 (유저 2026-10-09): 「지금 콘티패널에서 콘티행 섰을때 레이어
/// 종류버튼으로 어태치레이어 추가안되니 가능하도록」 — and 「타임라인이랑
/// 완벽통일」.
///
/// Standing on a row of the conte group in the storyboard holds the
/// timeline's own row, so the ＋ menu's attach entries are the timeline's
/// there: the same gate, the same rows made, and the row made is where you
/// stand — on this rail, at its seat.
///
/// Cuts a [0, 12) and b [12, 24) each hold a conte and a row riding over
/// it; four frames of gap; then c [28, 40), which has no conte.
void main() {
  const trackId = TrackId('t1');
  final conteRow = LayerRowAddress(trackConteRowId(trackId));
  final over = LayerRowAddress(trackConteRowId(trackId, seat: 1));

  Layer drawn(
    String id, {
    LayerKind kind = LayerKind.storyboard,
    String? ridesOn,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
    frames: [Frame(id: FrameId('$id-0'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-0'), length: 12)},
  );

  Cut cutOf(String id, {bool conte = true, int gap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    leadingGapFrames: gap,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      drawn('$id-cel', kind: LayerKind.animation),
      if (conte) ...[
        drawn('$id-conte'),
        drawn('$id-over', ridesOn: '$id-conte'),
      ],
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-attach'),
        name: 'Conte attach',
        createdAt: DateTime.utc(2026, 10, 10),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            cuts: [
              cutOf('a'),
              cutOf('b'),
              cutOf('c', conte: false, gap: 4),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  EditorSessionManager standingAt(TimelineRowAddress row, int frame) {
    final session = sessionOf()
      ..standOnRow(row, panel: WorkingPanel.storyboard, globalFrameIndex: frame);
    expect(session.storyboardStandingRow, row, reason: 'fixture: standing');
    return session;
  }

  /// The timeline's own ＋ menu, standing on [layer] of cut a.
  TimelineToolbarPanelContext timelineOn(String layer) =>
      TimelineToolbarPanelContext(
        sessionOf()
          ..selectCut(const CutId('a'))
          ..standOnRow(LayerRowAddress(LayerId(layer))),
      );

  /// Every cut's conte group as the rows a rail draws: seat, name, kind,
  /// placement and timing — the ids are each session's own mint.
  List<String> groupsOf(EditorSessionManager session) => [
    for (final cut in session.repository.requireProject().tracks.single.cuts)
      for (final entry in conteGroupOf(cut))
        '${cut.id.value}@${entry.seat}: ${entry.row.name} '
            '${entry.row.kind.name} ${entry.row.attachedPlacement.name} '
            '${entry.row.attachedMode.name}',
  ];

  group('🚨on the conte row', () {
    test('the attach entries are lit as the timeline\'s are on the same '
        'row', () {
      final storyboard = StoryboardToolbarPanelContext(
        standingAt(conteRow, 3),
      );
      expect(storyboard.canAddAttachedLayer, isTrue);
      expect(
        storyboard.canAddAttachedLayer,
        timelineOn('a-conte').canAddAttachedLayer,
      );
    });

    for (final (placement, mode, seat) in [
      (AttachedPlacement.above, AttachedMode.free, 2),
      (AttachedPlacement.above, AttachedMode.synced, 2),
      (AttachedPlacement.below, AttachedMode.free, -1),
      (AttachedPlacement.below, AttachedMode.synced, -1),
    ]) {
      test('${placement.name} · ${mode.name} makes what the timeline\'s '
          'entry makes, in every cut, and stands at its seat', () {
        final session = standingAt(conteRow, 3);
        final before = groupsOf(session);
        StoryboardToolbarPanelContext(
          session,
        ).addAttachedLayer(placement, mode: mode);

        final timeline = timelineOn('a-conte');
        timeline.addAttachedLayer(placement, mode: mode);

        expect(groupsOf(session), isNot(before), reason: 'LIVENESS: made');
        expect(groupsOf(session), groupsOf(timeline.session));
        expect(
          [
            for (final cut
                in session.repository.requireProject().tracks.single.cuts)
              conteRowAtSeat(cut, seat) != null,
          ],
          [true, true, false],
          reason: 'on the seat in each cut with a conte',
        );

        final made = conteRowAtSeat(
          session.repository.requireProject().tracks.single.cuts.first,
          seat,
        )!;
        expect(session.activeLayerId, made.id, reason: 'the timeline\'s');
        expect(
          session.storyboardStandingRow,
          LayerRowAddress(trackConteRowId(trackId, seat: seat)),
          reason: 'the rail\'s — where it shows the row made',
        );
      });
    }
  });

  test('on a row riding the conte, the new row rides the same conte — as the '
      'timeline\'s entry does from an attach row', () {
    final session = standingAt(over, 15);
    final storyboard = StoryboardToolbarPanelContext(session);
    expect(storyboard.canAddAttachedLayer, isTrue);
    storyboard.addAttachedLayer(AttachedPlacement.above);

    final timeline = TimelineToolbarPanelContext(
      sessionOf()
        ..selectCut(const CutId('b'))
        ..standOnRow(const LayerRowAddress(LayerId('b-over'))),
    )..addAttachedLayer(AttachedPlacement.above);

    expect(groupsOf(session), groupsOf(timeline.session));
    expect(
      session.storyboardStandingRow,
      LayerRowAddress(trackConteRowId(trackId, seat: 2)),
    );
  });

  group('🚨where the row holds no layer of a cut, the entries stay grey', () {
    // ⛔Not the timeline's answer for whatever it holds: standing in a cut
    // with no conte left the timeline on that cut's own row — a drawing
    // row, which carries attach rows.
    test('a cut with no conte', () {
      // The row the timeline stood on before stays seated there
      // (`Standing.layerAProjectionStandSeats`).
      final session = sessionOf()
        ..selectCut(const CutId('c'))
        ..standOnRow(const LayerRowAddress(LayerId('c-cel')))
        ..standOnRow(
          conteRow,
          panel: WorkingPanel.storyboard,
          globalFrameIndex: 30,
        );
      expect(session.storyboardStandingRow, conteRow, reason: '⛔전제');
      expect(
        session.activeLayerId,
        const LayerId('c-cel'),
        reason: '⛔전제: the timeline holds a row that carries them',
      );
      expect(session.folders.canAddAttachedLayerToActive, isTrue);

      final storyboard = StoryboardToolbarPanelContext(session);
      expect(storyboard.canAddAttachedLayer, isFalse);
      final before = groupsOf(session);
      final layers = session.repository.requireProject().tracks.single.cuts
          .last
          .layers
          .length;
      storyboard.addAttachedLayer(AttachedPlacement.above);
      expect(groupsOf(session), before);
      expect(
        session.repository.requireProject().tracks.single.cuts.last.layers,
        hasLength(layers),
        reason: 'nothing was attached to the row the timeline holds',
      );
    });

    test('a gap', () {
      final session = standingAt(conteRow, 26);
      expect(session.activeCutOrNull, isNull, reason: '⛔전제');
      expect(StoryboardToolbarPanelContext(session).canAddAttachedLayer, isFalse);
    });
  });

  test('the cut\'s row and the camera row answer as the timeline does on '
      'what they hold', () {
    expect(
      StoryboardToolbarPanelContext(
        standingAt(const TrackRowAddress(trackId), 3),
      ).canAddAttachedLayer,
      isFalse,
      reason: 'the V row holds the cut, no row of it',
    );
    expect(
      StoryboardToolbarPanelContext(
        standingAt(LayerRowAddress(trackCameraRowId(trackId)), 3),
      ).canAddAttachedLayer,
      timelineOn('a-cam').canAddAttachedLayer,
    );
    expect(
      timelineOn('a-cam').canAddAttachedLayer,
      isFalse,
      reason: '⛔전제: a camera carries none',
    );
  });

  group('🚨the rail is left where it stands', () {
    test('by a row made in the timeline', () {
      final session = standingAt(const TrackRowAddress(trackId), 3);
      final timeline = TimelineToolbarPanelContext(
        session..standOnRow(const LayerRowAddress(LayerId('a-conte'))),
      );
      expect(session.workingPanel, WorkingPanel.timeline, reason: '⛔전제');

      timeline.addAttachedLayer(AttachedPlacement.above);

      expect(session.activeLayerId, isNot(const LayerId('a-conte')));
      expect(session.storyboardStandingRow, const TrackRowAddress(trackId));
    });

    test('by a flip onto a cut, whatever row of it the timeline comes back '
        'on', () {
      // 「컷에 설때는 예전처럼 마지막에 섯던 행에 서있는채로 그대로. 콘티행에
      // 서야 콘티행에 서도록」 (I-73, 유저 2026-10-08).
      final session = sessionOf()
        ..selectCut(const CutId('b'))
        ..standOnRow(const LayerRowAddress(LayerId('b-conte')))
        ..standOnRow(
          const TrackRowAddress(trackId),
          panel: WorkingPanel.storyboard,
          globalFrameIndex: 3,
        );
      expect(session.activeCutId, const CutId('a'), reason: '⛔전제');

      // ⛔Not a second press: a press stores the rail's row after the cut
      // has switched, and would hide a rail moved on the way.
      session.trackAxisWalk.flipCuts(trackId, forward: true);

      expect(session.activeCutId, const CutId('b'), reason: '⛔전제');
      expect(
        session.activeLayerId,
        const LayerId('b-conte'),
        reason: '⛔전제: the row cut b was left on',
      );
      expect(session.storyboardStandingRow, const TrackRowAddress(trackId));
    });
  });
}
