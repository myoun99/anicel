import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cel_bank_lanes.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// F-136's orphan law, asked by every edit that takes blocks off a row —
/// the delete, the splice and a lead edge sweeping blocks away (I-179):
/// [layerLeavingWhatItOrphaned].
void main() {
  Frame cel(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  List<String> celsOf(Layer row) => [
    for (final frame in row.frames) frame.id.value,
  ];

  final before = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: [cel('shown'), cel('unshown')],
    timeline: const {
      0: TimelineExposure.drawing(FrameId('shown'), length: 2),
    },
  );

  test('a cel the edit stopped showing leaves; one no block showed before '
      'the edit stays — an edit elsewhere never empties the bank', () {
    final left = layerLeavingWhatItOrphaned(
      before,
      before.copyWith(timeline: const {}),
      bank: CelBankLanes.unshared,
    );

    expect(celsOf(left), ['unshown']);
  });

  test('a cel another lane of the bank still shows stays', () {
    final left = layerLeavingWhatItOrphaned(
      before,
      before.copyWith(timeline: const {}),
      bank: const CelBankLanes([
        {4: TimelineExposure.drawing(FrameId('shown'), length: 1)},
      ]),
    );

    expect(celsOf(left), ['shown', 'unshown']);
  });
}
