import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/session/drags/row_order_drag.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';

/// The row-order drag's TRACK arm — nothing named the file (2026-09-05).
///
/// 🚨The channel carries the DRAWN state (subject, caret, legality) while
/// the COMMIT reads only the object's own fields, so the release does not
/// resolve the landing a second time and the drawn `legal` cannot disagree
/// with the committed plan.
///
/// 🚨R5 #9: the caret is a SLOT (between rows) and the model wants an
/// INDEX — landing after yourself means one fewer position once you are
/// lifted out, which is the off-by-one every reorder has.
void main() {
  Track track(String id) => Track(
    id: TrackId(id),
    name: 'track $id',
    cuts: [
      Cut(
        id: CutId('cut-$id'),
        name: 'c',
        layers: const [],
        duration: 12,
        canvasSize: const CanvasSize(width: 64, height: 64),
      ),
    ],
  );

  ({
    RowOrderDrag drag,
    ValueNotifier<LayerRowDragState?> channel,
    List<({int from, int to, String name})> reorders,
  })
  open({String subjectTrack = 'b'}) {
    final channel = ValueNotifier<LayerRowDragState?>(null);
    addTearDown(channel.dispose);
    final reorders = <({int from, int to, String name})>[];
    final tracks = [track('a'), track('b'), track('c')];
    return (
      drag: RowOrderDrag(
        subject: TrackRowSubject(TrackId(subjectTrack)),
        channel: channel,
        tracksNow: () => tracks,
        effectChainOf: (_) => const <LayerEffect>[],
        trackSeAnywhere: (_) => null,
        activeCutOrNull: () => null,
        isTrackSeLayerId: (_) => false,
        rowSelectionCarriedBy: (id) => {id},
        trackIdOfTransformLaneCarrier: (_) => null,
        mountModeFor: ({required cutId, required layerId, required baseId}) =>
            AttachedMode.synced,
        commitTrackReorder:
            ({required fromIndex, required toIndex, required trackName}) =>
                reorders.add((from: fromIndex, to: toIndex, name: trackName)),
        commitTrackEffects: (_, _) {},
        commitLayerEffects:
            ({required cutId, required layerId, required effects}) {},
        commitSeOrder: ({required trackId, required order}) {},
        commitPlacement:
            ({
              required cutId,
              required plan,
              required subjectLayerId,
              required movedIds,
            }) {},
      ),
      channel: channel,
      reorders: reorders,
    );
  }

  test('🚨constructing it ARMS the channel with an illegal caret — the row '
      'is lifted and nothing is a landing yet', () {
    final session = open();

    expect(session.channel.value, isNotNull);
    expect(session.channel.value!.caretSlot, -1);
    expect(session.channel.value!.legal, isFalse);
  });

  test('a caret move draws a legal landing', () {
    final session = open();

    session.drag.updateTrackRow(2);

    expect(session.channel.value!.caretSlot, 2);
    expect(session.channel.value!.legal, isTrue);
  });

  test('⛔the caret CLAMPS to the run — there is no slot past the last row', () {
    final session = open();

    session.drag.updateTrackRow(99);
    expect(session.channel.value!.caretSlot, 3, reason: 'three tracks');

    session.drag.updateTrackRow(-5);
    expect(session.channel.value!.caretSlot, 0);
  });

  test('🚨a SLOT after yourself becomes one index less — you are lifted out '
      'before you land, which is the off-by-one every reorder has', () {
    final session = open();

    session.drag.updateTrackRow(3);
    session.drag.commit();

    expect(session.reorders.single.from, 1);
    expect(session.reorders.single.to, 2);
  });

  test('a slot BEFORE yourself keeps its index', () {
    final session = open();

    session.drag.updateTrackRow(0);
    session.drag.commit();

    expect(session.reorders.single, (from: 1, to: 0, name: 'track b'));
  });

  test('⛔landing where you already are commits NOTHING', () {
    final session = open();

    for (final slot in [1, 2]) {
      final fresh = open();
      fresh.drag.updateTrackRow(slot);
      fresh.drag.commit();
      expect(fresh.reorders, isEmpty, reason: 'slot $slot is a no-op');
    }
    session.drag.cancel();
  });

  test('⛔a commit with no caret move does nothing', () {
    final session = open();

    session.drag.commit();

    expect(session.reorders, isEmpty);
  });

  test('🚨both closers clear the channel — a caret left drawn after the '
      'release is a row that looks like it is still moving', () {
    final committed = open()
      ..drag.updateTrackRow(0)
      ..drag.commit();
    expect(committed.channel.value, isNull);

    final cancelled = open()
      ..drag.updateTrackRow(0)
      ..drag.cancel();
    expect(cancelled.channel.value, isNull);
    expect(cancelled.reorders, isEmpty);
  });

  test('⛔a subject that is not a track row ignores the track caret', () {
    final channel = ValueNotifier<LayerRowDragState?>(null);
    addTearDown(channel.dispose);
    final drag = RowOrderDrag(
      subject: const LayerRowSubject(LayerId('l')),
      channel: channel,
      tracksNow: () => [track('a')],
      effectChainOf: (_) => const <LayerEffect>[],
      trackSeAnywhere: (_) => null,
      activeCutOrNull: () => null,
      isTrackSeLayerId: (_) => false,
      rowSelectionCarriedBy: (id) => {id},
      trackIdOfTransformLaneCarrier: (_) => null,
      mountModeFor: ({required cutId, required layerId, required baseId}) =>
          AttachedMode.synced,
      commitTrackReorder:
          ({required fromIndex, required toIndex, required trackName}) {},
      commitTrackEffects: (_, _) {},
      commitLayerEffects:
          ({required cutId, required layerId, required effects}) {},
      commitSeOrder: ({required trackId, required order}) {},
      commitPlacement:
          ({
            required cutId,
            required plan,
            required subjectLayerId,
            required movedIds,
          }) {},
    );

    drag.updateTrackRow(2);

    expect(channel.value!.caretSlot, -1, reason: 'still the armed caret');
  });
}
