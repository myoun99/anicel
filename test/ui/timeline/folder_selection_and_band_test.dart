import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/session/folder_bands.dart';
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
    // ↩️The clone was built by hand here, so this asked the test what the
    // test had written; it asks the builder the session's cache calls.
    final band = folderBandOf(folderRow, [member('a'), member('b')]);
    expect(band.timeline.keys, [0]);
    expect(band.timeline[0]!.length, 4);
    expect(
      band.id,
      folderRow.id,
      reason: 'the clone stays the FOLDER — the tile bake keys on the id',
    );
  });

  // 🪦R28 #11's grey — 「다른곳에서 해당위치에 그림그려진 하얀 블록 존재하면
  // 하얗게」 — stood here as a rule the test wrote for itself (a closure over
  // two fake members, asserted against its own answers), which is why the
  // session's arm could read a member's bare cells as drawn and nothing went
  // red (F-311). It is pinned against the session and the painter now:
  // `session/a_folder_block_is_what_its_rows_hold_test.dart`.
}
