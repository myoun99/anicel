import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';

/// 🗣️I-73-one-head-Q1 (유저 2026-10-09 → `refuse`): 「콘티의 어태치 행은
/// 떼지 못하게 한다」.
///
/// A row riding a cut's conte is never let go: the menu's 어태치 해제 is
/// dark on it, and a drag that would take it out of its group — out on its
/// own, or onto another base — lands nowhere. A row riding any other base
/// is let go as it always was.
///
/// Cut a's stack, bottom first: `cel` (a drawing row) with `inked` riding
/// it, then `conte` with `over` and `over2` riding it, then `top`.
void main() {
  Layer row(
    String id, {
    LayerKind kind = LayerKind.animation,
    String? ridesOn,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: const [],
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
  );

  final stack = [
    row('cel'),
    row('inked', ridesOn: 'cel'),
    row('conte', kind: LayerKind.storyboard),
    row('over', kind: LayerKind.storyboard, ridesOn: 'conte'),
    row('over2', kind: LayerKind.storyboard, ridesOn: 'conte'),
    row('top'),
  ];

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('riders'),
        name: 'Riders',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('a'),
                name: 'a',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: stack,
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectCut(const CutId('a'));
    return session;
  }

  Layer layerIn(EditorSessionManager session, String id) => session
      .repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .byId(LayerId(id))!;

  group('the menu\'s 어태치 해제', () {
    test('is dark on a row riding the conte, and lets nothing go', () {
      final session = open()
        ..standOnRow(const LayerRowAddress(LayerId('over')));

      expect(session.folders.canDetachActiveLayer, isFalse);
      session.folders.detachActiveLayer();

      expect(
        layerIn(session, 'over').attachedToLayerId,
        const LayerId('conte'),
      );
    });

    test('lets a row riding any other base go', () {
      final session = open()
        ..standOnRow(const LayerRowAddress(LayerId('inked')));

      expect(session.folders.canDetachActiveLayer, isTrue);
      session.folders.detachActiveLayer();

      expect(layerIn(session, 'inked').attachedToLayerId, isNull);
    });
  });

  group('a drag', () {
    test('out of the conte\'s group lands nowhere', () {
      expect(
        resolveLayerDrop(
          stack: stack,
          movingId: const LayerId('over'),
          insertAt: stack.length,
        ),
        isNull,
      );
      // LIVENESS: the cel's rider, dragged clear of its group, goes.
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('inked'),
        insertAt: stack.length,
      )!;
      expect(plan.attach.detachIds, {const LayerId('inked')});
    });

    test('onto another base lands nowhere either', () {
      expect(
        resolveLayerDropOnRow(
          stack: stack,
          movingId: const LayerId('over'),
          targetId: const LayerId('cel'),
        ),
        isNull,
      );
      // LIVENESS: the cel's rider goes onto another base.
      final plan = resolveLayerDropOnRow(
        stack: stack,
        movingId: const LayerId('inked'),
        targetId: const LayerId('top'),
      )!;
      expect(plan.attach.mounts.single.baseId, const LayerId('top'));
    });

    test('inside the conte\'s group is an ordinary move', () {
      // `over` nudged one place up, past `over2`: still the group's.
      final plan = resolveLayerDrop(
        stack: stack,
        movingId: const LayerId('over'),
        insertAt: 5,
      )!;
      expect(plan.attach.detachIds, isEmpty);
      expect(plan.attach.mounts, isEmpty);
      expect(plan.order.indexOf(const LayerId('over')), 4);
    });
  });
}
