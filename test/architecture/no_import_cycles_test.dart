// A FILE THAT IMPORTS ITSELF THROUGH OTHERS CANNOT BE MOVED ALONE, AND THIS
// IS WHAT KEEPS THAT LIST SHORT.
//
// Round 4 of the audit (2026-09-03) found seven import loops among lib
// files and broke five by giving the shared piece a leaf file of its own:
// `everyLayerMark` moved next to `LayerMark`, `TimelineRunBehavior` left
// `timeline_repeat`, `attachOrganizerBaseOf` moved to the folder it reads,
// `TimelineZoomLimits` took the constants the panel and its cluster both
// read, and the selection shape and affine left `canvas_selection`. The two
// loops in `_ledger` stayed, each for a reason a reader can check.
//
// 2026-09-07 (audit, Round 8): the save lane's loop is gone. Its entry said
// breaking it was that lane's work, which is a note about who does it and
// not a reason it could not be done. The whole loop was ONE function:
// `appRecordingsDirectory` sat in `app_documents.dart` and read the save
// settings, so the folder every other file in that folder reaches for
// imported the settings that reach for the grant that reaches back. It is
// now `AppSave.recordingsRootDirectory`, beside `AppSave.conformRootDirectory`
// — the same law, configured-folder-wins-else-a-default — and
// `app_documents.dart` is the leaf it always described itself as.
//
// Nothing here forbids a new loop — it forbids a SILENT one. Put its files
// in `_ledger` with the reason it could not be broken, and the next reader
// gets your argument instead of a mystery. A ledger entry that stops
// looping fails too: a dead entry is a reason nobody can check any more.
//
// It is an instrument, so here is what it looks like when it lies: edges
// come from `tool/import_graph.dart`, which reads import lines textually —
// a `part` file has no edges of its own, and an import inside a block
// comment still counts.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/import_graph.dart';

typedef _Loop = ({Set<String> files, String why});

/// The loops that may exist today, and why each one is still here.
final _ledger = <_Loop>[
  (
    files: {
      'lib/src/ui/timeline/timeline_grid_tile_store.dart',
      'lib/src/ui/timeline/timeline_row_cells_painter.dart',
    },
    why:
        'Two halves of one raster path (UI-R18 T2): the store rasterizes a '
        'tile through the painter\'s emitter and the painter draws through '
        'the store\'s tiles. Splitting them means a third file that both '
        'read, which is the same loop wearing a hat.',
  ),
];

bool _same(Set<String> files, List<String> loop) =>
    files.length == loop.length && files.containsAll(loop);

void main() {
  test('every import loop among lib files is in the ledger, and no ledger '
      'entry is dead', () {
    final graph = buildImportGraph(roots: const ['lib']);
    final libOnly = <String, Set<String>>{
      for (final entry in graph.entries)
        entry.key: entry.value.where((f) => f.startsWith('lib/')).toSet(),
    };
    final loops = importCycles(libOnly);

    final unknown = loops
        .where((loop) => !_ledger.any((entry) => _same(entry.files, loop)))
        .toList();
    expect(
      unknown,
      isEmpty,
      reason:
          'New import loop(s):\n'
          '${unknown.map((loop) => '  ${loop.join(' <-> ')}').join('\n')}\n'
          'Give the shared piece a leaf file, or add the loop to _ledger '
          'with the reason it has to exist.',
    );

    final dead = _ledger
        .where((entry) => !loops.any((loop) => _same(entry.files, loop)))
        .toList();
    expect(
      dead,
      isEmpty,
      reason:
          'Ledger entries that no longer loop (remove them):\n'
          '${dead.map((e) => '  ${e.files.join(' <-> ')}').join('\n')}',
    );
  });
}
