// A DRAG PREVIEW REBUILT WITH THE SAME CONTENT IS THE SAME PREVIEW — the
// per-track lists (effect chains, cut orders) compare by their elements,
// never by the identity of the list a step happened to allocate.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

void main() {
  const track = TrackId('t');
  LayerEffect blur() =>
      LayerEffect.defaults(id: const EffectId('e'), kind: EffectKind.blur);

  test('a block move with a rebuilt effect chain reads as unchanged', () {
    final a = BlockMoveDragPreview(
      previewLayers: const {},
      previewTrackEffects: {
        track: [blur()],
      },
    );
    final b = BlockMoveDragPreview(
      previewLayers: const {},
      previewTrackEffects: {
        track: [blur()],
      },
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('a block move whose chain differs, or is absent, reads as changed', () {
    final some = BlockMoveDragPreview(
      previewLayers: const {},
      previewTrackEffects: {
        track: [blur()],
      },
    );
    const none = BlockMoveDragPreview(previewLayers: {});
    const empty = BlockMoveDragPreview(
      previewLayers: {},
      previewTrackEffects: {},
    );
    expect(some, isNot(none));
    expect(none, isNot(empty));
    expect(none, const BlockMoveDragPreview(previewLayers: {}));
  });

  test('a cut trim with a rebuilt order list reads as unchanged', () {
    final a = CutTrimDragPreview(
      previewDurations: const {},
      previewOrder: {
        track: [const CutId('a'), const CutId('b')],
      },
    );
    final b = CutTrimDragPreview(
      previewDurations: const {},
      previewOrder: {
        track: [const CutId('a'), const CutId('b')],
      },
    );
    final reordered = CutTrimDragPreview(
      previewDurations: const {},
      previewOrder: {
        track: [const CutId('b'), const CutId('a')],
      },
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(reordered));
  });
}
