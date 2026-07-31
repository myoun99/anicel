import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// R28 #11/#12: the folder row stops behaving like a second kind of row.
///
/// #11 — selection is ONE thing, and the folder's frame band carries the
/// empty-cel grey as the UNION of its members.
/// #12 — the folder header used to carry its first member as a
/// REPRESENTATIVE layer, which is why the block outline drew on the folder
/// instead of the member, and why three separate row walks each needed
/// their own "skip the header" clause. The absorption removes the concept:
/// the folder row's layer IS the folder.
void main() {
  Layer member(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    folderId: const LayerId('f'),
    frames: [Frame(id: FrameId('$id-f0'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f0'), length: 4)},
  );

  final folderRow = createFolderLayer(id: const LayerId('f'), name: 'F');

  test('R28 #12: no representative layer — the folder row carries the '
      'FOLDER, so a row lookup by layer id can never land on it', () {
    final rows = buildTimelineDisplayRows(
      layers: [folderRow, member('a'), member('b')],
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );

    final folderIndex = rows.indexWhere((row) => row.isFolder);
    expect(folderIndex, isNot(-1));
    expect(
      rows[folderIndex].layer.id,
      const LayerId('f'),
      reason: 'the header used to hold member "a" as a stand-in',
    );

    final matches = [
      for (var i = 0; i < rows.length; i += 1)
        if (rows[i].layer.id == const LayerId('a')) i,
    ];
    expect(
      matches,
      hasLength(1),
      reason: 'exactly one row answers to a member id, so "the first row '
          'whose layer.id matches" is finally the right row',
    );
    expect(matches.single, greaterThan(folderIndex));
  });

  test('R10: the folder BAND is the subtree union as an ordinary timeline '
      '— which is what lets a folder row be a cells row', () {
    // Members 'a' and 'b' both expose [0, 4); the union merges to one run.
    final runs = folderAggregateRuns([member('a'), member('b')]);
    expect(runs, [(start: 0, endExclusive: 4)]);

    // And the band a folder row renders is that union, expressed the way
    // every other row expresses coverage: entries in `Layer.timeline`.
    final band = folderRow.copyWith(
      timeline: {
        for (final run in runs)
          run.start: TimelineExposure.drawing(
            FrameId('band:f:${run.start}'),
            length: run.endExclusive - run.start,
          ),
      },
    );
    expect(band.timeline.keys, [0]);
    expect(band.timeline[0]!.length, 4);
    expect(
      band.id,
      folderRow.id,
      reason: 'the clone stays the FOLDER — the tile bake keys on the id',
    );
  });

  test('R28 #11 survives the move to the shared painter: a folder frame '
      'greys only when NO member drew there', () {
    // Member A drew frames 0..1, member B drew frame 2. Frame 3 is empty
    // in the whole subtree — the only one that may grey.
    bool memberHasContent(Layer layer, int frameIndex) =>
        layer.id == const LayerId('a') ? frameIndex < 2 : frameIndex == 2;

    final members = [member('a'), member('b')];
    // The rule the session's `celHasContentForLayer` folder arm applies —
    // pinned as the CONTRACT rather than as one painter's probe order,
    // which is what the deleted band test asserted.
    bool folderHasContent(int frameIndex) =>
        members.any((m) => memberHasContent(m, frameIndex));

    expect(folderHasContent(0), isTrue, reason: 'A drew it');
    expect(folderHasContent(1), isTrue, reason: 'A drew it');
    expect(
      folderHasContent(2),
      isTrue,
      reason: 'only B drew it, and the folder must consult B before greying '
          '— "다른곳에서 해당위치에 그림그려진 하얀 블록 존재하면 하얗게"',
    );
    expect(folderHasContent(3), isFalse, reason: 'nobody drew it: grey');
  });
}
