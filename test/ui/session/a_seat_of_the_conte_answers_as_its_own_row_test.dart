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
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart'
    show projectedLayerInHand;
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️I-73 — the drawn proposal 유저 took on 2026-10-08, of a row riding
/// the conte on the storyboard: 「서면 — 블록」 · 「플립 — 블록 단위」 ·
/// 「코마 — 블록 길이」 · 「타임라인의 자리 = 그 어태치 행」.
///
/// A row of the track's conte group is stood on as a row of its own — the
/// SEAT says which row of the cut under the playhead it is — and what the
/// session answers there is that row's, never the conte's beside it.
void main() {
  const trackId = TrackId('t1');
  final over = LayerRowAddress(trackConteRowId(trackId, seat: 1));
  final conteRow = LayerRowAddress(trackConteRowId(trackId));

  Layer drawn(
    String id, {
    required Map<int, int> blocks,
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
    frames: [
      for (final start in blocks.keys)
        Frame(id: FrameId('$id-$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final entry in blocks.entries)
        entry.key: TimelineExposure.drawing(
          FrameId('$id-${entry.key}'),
          length: entry.value,
        ),
    },
  );

  /// Cuts `a` and `b`, twelve frames each: a conte of two six-frame panels,
  /// a row over it holding two four-frame blocks, a row under it holding
  /// one. Cut `c` has no conte yet.
  Cut conteCut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      drawn('$id-cel', blocks: const {}, kind: LayerKind.animation),
      drawn(
        '$id-under',
        blocks: const {0: 12},
        ridesOn: '$id-conte',
        placement: AttachedPlacement.below,
      ),
      drawn('$id-conte', blocks: const {0: 6, 6: 6}),
      drawn('$id-over', blocks: const {0: 4, 4: 4}, ridesOn: '$id-conte'),
    ],
  );

  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('seats'),
        name: 'Seats',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            cuts: [
              conteCut('a'),
              conteCut('b'),
              Cut(
                id: const CutId('c'),
                name: 'c',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  drawn('c-cel', blocks: const {}, kind: LayerKind.animation),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Cut cutOf(EditorSessionManager session, String id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == CutId(id));

  List<String> blocksOf(EditorSessionManager session, String cut, String id) =>
      [
        for (final entry
            in cutOf(session, cut).layers
                .firstWhere((layer) => layer.id == LayerId(id))
                .timeline
                .entries)
          '${entry.key}+${entry.value.length}',
      ];

  void standAt(EditorSessionManager session, LayerRowAddress row, int frame) {
    session.standOnRow(
      row,
      panel: WorkingPanel.storyboard,
      globalFrameIndex: frame,
    );
    expect(session.storyboardStandingRow, row, reason: 'fixture: standing');
  }

  test('🚨the block under the cursor is that row\'s: a comma is ITS '
      'block\'s length, and the conte\'s panel and the cut keep theirs', () {
    final session = sessionOf();
    // Frame 17 is cut b's sixth: its row over the conte holds [4,8) there,
    // and the conte its first panel.
    standAt(session, over, 17);
    expect(session.activeLayerId, const LayerId('b-over'), reason: 'fixture');

    session.edgeDrag.setCommaForStoryboardCursor(2);

    expect(blocksOf(session, 'b', 'b-over'), ['0+4', '4+2']);
    expect(blocksOf(session, 'b', 'b-conte'), ['0+6', '6+6']);
    expect(cutOf(session, 'b').duration, 12);

    // LIVENESS: on the conte row the same press is the panel's, and the
    // cut's length rides it.
    final onConte = sessionOf();
    standAt(onConte, conteRow, 17);
    onConte.edgeDrag.setCommaForStoryboardCursor(2);
    expect(blocksOf(onConte, 'b', 'b-conte'), ['0+2', '2+6']);
    expect(cutOf(onConte, 'b').duration, 8);
  });

  test('🚨a flip walks that row\'s blocks — the conte\'s panels are another '
      'row\'s', () {
    final session = sessionOf();
    standAt(session, over, 0);

    session.trackAxisWalk.flipTrackRow(over.layerId, forward: true);

    expect(session.editingGlobalFrame, 4, reason: 'its second block');

    final onConte = sessionOf();
    standAt(onConte, conteRow, 0);
    onConte.trackAxisWalk.flipTrackRow(conteRow.layerId, forward: true);
    expect(onConte.editingGlobalFrame, 6, reason: 'LIVENESS: the next panel');
  });

  // I-73 ④: the projection rows lend the timeline's ＋ on their cell, the
  // camera row and a row riding the conte alike (↩️a riding row's ＋ was
  // dark: only the conte's own D28 division answered on this rail).
  test('＋ on a row riding the conte makes what the timeline\'s ＋ makes on '
      'the same cell', () {
    TimelineToolbarPanelContext onTheTimelinesRow(int frame) =>
        TimelineToolbarPanelContext(
          sessionOf()
            ..selectCut(const CutId('a'))
            ..standOnRow(const LayerRowAddress(LayerId('a-over')))
            ..selectFrameIndex(frame),
        );

    // Frame 10: past the row's two blocks, an empty cell.
    final session = sessionOf();
    standAt(session, over, 10);
    final panel = StoryboardToolbarPanelContext(session);
    expect(panel.canCreateInstance, isTrue);
    panel.createInstance();

    final timeline = onTheTimelinesRow(10);
    timeline.createInstance();
    expect(
      blocksOf(session, 'a', 'a-over'),
      isNot(blocksOf(sessionOf(), 'a', 'a-over')),
      reason: 'LIVENESS: something was made',
    );
    expect(
      blocksOf(session, 'a', 'a-over'),
      blocksOf(timeline.session, 'a', 'a-over'),
    );

    // …and at a block's first cell both refuse alike.
    final atAStart = sessionOf();
    standAt(atAStart, over, 4);
    expect(
      StoryboardToolbarPanelContext(atAStart).canCreateInstance,
      onTheTimelinesRow(4).canCreateInstance,
    );
  });

  test('the row in hand at a seat is the cut\'s row there — while it is '
      'the row the session holds', () {
    final a = cutOf(sessionOf(), 'a');
    Layer? inHand(TimelineRowAddress? row, String active) =>
        projectedLayerInHand(
          row: row,
          cut: a,
          activeLayerId: LayerId(active),
        );

    expect(inHand(over, 'a-over')?.id, const LayerId('a-over'));
    expect(inHand(conteRow, 'a-conte')?.id, const LayerId('a-conte'));
    expect(inHand(over, 'a-conte'), isNull, reason: 'another row is held');
    expect(inHand(conteRow, 'a-over'), isNull, reason: 'another row is held');
    expect(
      inHand(const LayerRowAddress(LayerId('a-cel')), 'a-cel'),
      isNull,
      reason: 'no row of the conte group',
    );
    expect(
      projectedLayerInHand(
        row: over,
        cut: cutOf(sessionOf(), 'c'),
        activeLayerId: const LayerId('c-cel'),
      ),
      isNull,
      reason: 'a cut with no row at the seat',
    );
  });

  group('a head pressed while the session stands in another cut', () {
    test('🚨the conte\'s twirl folds its group — the head\'s row is asked '
        'about the stack it stands in', () {
      final session = sessionOf();
      session.selectCut(const CutId('b'));
      session.selectLayer(const LayerId('b-cel'));

      SessionRowButtonPresses(session).toggleGroupFold(
        const LayerId('a-conte'),
      );

      expect(
        session.railView.collapsedAttachBaseIds.value,
        {const LayerId('a-conte'), const LayerId('b-conte')},
      );
    });

    test('🚨a folded conte\'s eye takes the rows folded into it along', () {
      final session = sessionOf();
      session.selectCut(const CutId('b'));
      session.selectLayer(const LayerId('b-cel'));
      final presses = SessionRowButtonPresses(session);
      presses.toggleGroupFold(const LayerId('a-conte'));

      presses.toggleVisibility(const LayerId('a-conte'));

      bool eye(String cut, String id) => cutOf(
        session,
        cut,
      ).layers.firstWhere((layer) => layer.id == LayerId(id)).isVisible;
      expect(
        [
          for (final id in const ['a-conte', 'a-over', 'a-under']) eye('a', id),
        ],
        [false, false, false],
      );
      expect(eye('a', 'a-cel'), isTrue, reason: 'no row of the group');
    });
  });

  group('a row a command just made takes on what its family wears', () {
    Layer bornAt(EditorSessionManager session, int seat) =>
        conteRowAtSeat(cutOf(session, 'c'), seat)!;

    void bearAConteIn(EditorSessionManager session) {
      session.selectCut(const CutId('c'));
      session.selectLayer(const LayerId('c-cel'));
      session.layerStack.addLayerOfKind(LayerKind.storyboard);
    }

    test('🚨a conte born beside a folded group is born folded', () {
      final session = sessionOf();
      SessionRowButtonPresses(session).toggleGroupFold(
        const LayerId('a-conte'),
      );

      bearAConteIn(session);

      expect(
        session.railView.collapsedAttachBaseIds.value,
        contains(bornAt(session, 0).id),
      );
    });

    test('🚨and a row born at a seat whose rows have their lanes open is '
        'born with its own open — its seat\'s, not the conte\'s', () {
      final session = sessionOf();
      session.railView.expandedLaneLayerIds.value = {const LayerId('a-over')};

      bearAConteIn(session);

      expect(
        session.railView.expandedLaneLayerIds.value,
        {
          const LayerId('a-over'),
          const LayerId('b-over'),
          bornAt(session, 1).id,
        },
      );
    });

    test('a family nobody folded stays open', () {
      final session = sessionOf();

      bearAConteIn(session);

      expect(session.railView.collapsedAttachBaseIds.value, isEmpty);
      expect(session.railView.expandedLaneLayerIds.value, isEmpty);
    });
  });
}
