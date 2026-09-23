import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨I-39: every drag that does not show its subject live hangs ONE chip
/// (`lib/src/ui/widgets/drag_chip.dart`) — the panel tab's and the pool's
/// were copies of it, drifted apart, before there was one to reach for.
///
/// A behaviour test cannot hold this: two chips that happen to look alike
/// today pass it and drift tomorrow. So the source is read — every
/// `feedback:` a `Draggable` is given in lib must BE the chip (or the pool's
/// wrapper, whose only addition is the verdict it listens to), unless it is
/// in the ledger with the reason it is not.
void main() {
  const chips = ['feedback: DragChip(', 'feedback: MediaAssetDragChip('];

  /// A drag whose feedback is its subject, carried live — the user's own
  /// line between the two: 「프레임블록은 애초에 라이브로 보여주니
  /// 필요없음. 라이브로 안보여주는것만 적용」.
  const live = {
    'lib/src/ui/brush/brush_preset_reorder_grid.dart':
        'the preset CELL itself, lifted — the grid shows what moves by '
        'moving it',
  };

  test('every drag feedback in lib is the one chip, or a live subject in '
      'the ledger', () {
    final found = <String, List<String>>{};
    for (final file in dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      for (final line in lines) {
        final text = line.trimLeft();
        if (text.startsWith('//') || !text.startsWith('feedback:')) {
          continue;
        }
        found.putIfAbsent(libPath(file), () => []).add(text);
      }
    }

    // Self-check: the scan sees the shape it is looking for — the three
    // drag sources the app has today.
    expect(found.keys, containsAll(<String>[
      'lib/src/ui/media/media_pool_panel.dart',
      'lib/src/ui/panels/editor_panel_tabs.dart',
      ...live.keys,
    ]));

    final strays = <String>[
      for (final MapEntry(key: path, value: lines) in found.entries)
        if (!live.containsKey(path))
          for (final line in lines)
            if (!chips.any(line.startsWith)) '$path: $line',
    ];
    expect(
      strays,
      isEmpty,
      reason: 'a drag feedback of its own is a copy of the chip — reach for '
          '`DragChip` (or say, in the ledger here, why its subject is live)',
    );
  });
}
