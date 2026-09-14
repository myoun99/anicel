import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cel_bank_lanes.dart';
import 'package:anicel/src/models/drawing_block_move.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/session/drags/drawing_block_move_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import '../../../helpers/run_edge_fixtures.dart';

/// The drawing-block move drag — nothing named it (the audit's
/// untested-file pass, 2026-09-05).
///
/// 🚨Two refusals that are NOT the same: an ineligible row says so out
/// loud, and everything else ("no such row", "no entry at the grip", a
/// GHOST repeat instance whose timing belongs to the region rather than to
/// a drag) is simply "nothing here". A test that lumped them together
/// would let the notice go missing.
void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: id);

  Layer row(String id, {Map<int, TimelineExposure>? timeline}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [frame('$id-1')],
    timeline:
        timeline ?? {0: TimelineExposure.drawing(FrameId('$id-1'), length: 2)},
    kind: LayerKind.image,
  );

  ({
    DrawingBlockMoveDrag? drag,
    ValueNotifier<TimelineDragPreview?> preview,
    List<({DrawingBlockMovePlan plan, Layer source})> landings,
    List<LayerId> notices,
  })
  open({
    Layer? source,
    Layer? other,
    int blockStartIndex = 0,
    Set<String> ineligible = const {},
  }) {
    final from = source ?? row('a');
    final to = other ?? row('b');
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    final landings = <({DrawingBlockMovePlan plan, Layer source})>[];
    final notices = <LayerId>[];
    return (
      drag: DrawingBlockMoveDrag.begin(
        layerId: from.id,
        blockStartIndex: blockStartIndex,
        layerById: (id) => id == from.id ? from : (id == to.id ? to : null),
        isEligibleRow: (id) => !ineligible.contains(id.value),
        noticeIneligible: notices.add,
        bankOf: (_) => CelBankLanes.unshared,
        cutFrameCount: () => 12,
        preview: preview,
        land: (plan, source) => landings.add((plan: plan, source: source)),
      ),
      preview: preview,
      landings: landings,
      notices: notices,
    );
  }

  Map<LayerId, Layer> previewLayersOf(
    ValueNotifier<TimelineDragPreview?> preview,
  ) => (preview.value! as BlockMoveDragPreview).previewLayers;

  test('🚨an INELIGIBLE row is refused OUT LOUD — that is a different '
      'refusal from "nothing here"', () {
    final session = open(ineligible: const {'a'});

    expect(session.drag, isNull);
    expect(session.notices, [const LayerId('a')]);
  });

  test('⛔no entry at the grip is simply nothing here — no object, and no '
      'notice', () {
    final session = open(blockStartIndex: 7);

    expect(session.drag, isNull);
    expect(session.notices, isEmpty);
  });

  test('⛔a GHOST repeat instance is not draggable — it is derived, and its '
      'timing belongs to the region', () {
    final session = open(
      source: row(
        'a',
        timeline: {
          0: const TimelineExposure.drawing(
            FrameId('a-1'),
            length: 2,
            ghostOf: endHoldGhost,
          ),
        },
      ),
    );

    expect(session.drag, isNull);
    expect(session.notices, isEmpty);
  });

  test('a plain slide previews the source row alone', () {
    final session = open();

    session.drag!.update(frameDelta: 3);

    expect(previewLayersOf(session.preview).keys, [const LayerId('a')]);
    expect(session.landings, isEmpty, reason: 'nothing lands mid-drag');
  });

  test('a CROSS-ROW move previews both rows', () {
    final session = open();

    session.drag!.update(frameDelta: 0, targetLayerId: const LayerId('b'));

    expect(
      previewLayersOf(session.preview).keys,
      containsAll(<LayerId>[const LayerId('a'), const LayerId('b')]),
    );
  });

  test('🚨a target row that is INELIGIBLE plans nothing — the pointer may '
      'pass over any row, and only a legal landing previews', () {
    final session = open(ineligible: const {'b'});

    session.drag!.update(frameDelta: 0, targetLayerId: const LayerId('b'));

    expect(session.preview.value, isNull);
  });

  test('commit lands ONE step carrying the plan and the SOURCE row', () {
    final session = open();

    session.drag!.update(frameDelta: 3);
    session.drag!.commit();

    expect(session.landings, hasLength(1));
    expect(session.landings.single.source.id, const LayerId('a'));
    expect(session.preview.value, isNull);
  });

  test('🚨a drag that ends on an ILLEGAL landing lands nothing — the commit '
      'reads the stored plan, never the preview channel', () {
    final session = open(ineligible: const {'b'});

    session.drag!.update(frameDelta: 3);
    session.drag!.update(frameDelta: 0, targetLayerId: const LayerId('b'));
    session.drag!.commit();

    expect(session.landings, isEmpty);
    expect(session.preview.value, isNull);
  });

  test('cancel drops the plan and the preview, and touches no history', () {
    final session = open();

    session.drag!.update(frameDelta: 3);
    session.drag!.cancel();
    session.drag!.commit();

    expect(session.landings, isEmpty);
    expect(session.preview.value, isNull);
  });
}
