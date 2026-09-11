import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/new_row_placement.dart';

/// 🚨ONE answer for where a new row joins the stack — Add Layer, a file let
/// go on the canvas, a file let go between two rail rows. The canvas drop
/// used to take only Add Layer's index, so a picture dropped with a folder
/// member active landed inside the folder's run without belonging to it.
void main() {
  Layer row(
    String id, {
    LayerKind kind = LayerKind.animation,
    String? folder,
    String? ridesOn,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: kind,
    folderId: folder == null ? null : LayerId(folder),
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
  );

  test('between two plain rows it lands where it was aimed, at top level', () {
    final stack = [row('A'), row('B')];

    expect(newRowPlacement(stack, 1), (index: 1, folderId: null));
    expect(newRowPlacement(stack, 2), (index: 2, folderId: null));
    expect(newRowPlacement(stack, 0), (index: 0, folderId: null));
  });

  test('inside a folder\'s run it joins that folder — the folder of the row '
      'below — and above the folder row it is the folder\'s sibling', () {
    final stack = [
      row('m1', folder: 'F'),
      row('m2', folder: 'F'),
      row('F', kind: LayerKind.folder),
      row('C'),
    ];

    expect(newRowPlacement(stack, 1), (index: 1, folderId: const LayerId('F')));
    expect(newRowPlacement(stack, 2), (index: 2, folderId: const LayerId('F')));
    expect(newRowPlacement(stack, 3), (index: 3, folderId: null));
    final joined = [
      ...stack.sublist(0, 1),
      row('new', folder: 'F'),
      ...stack.sublist(1),
    ];
    expect(folderStructureProblem(joined), isNull);
  });

  test('aimed inside an attach group it lands past the whole group — above '
      'riders and below riders alike', () {
    final above = [row('X'), row('B'), row('R', ridesOn: 'B'), row('Y')];
    expect(newRowPlacement(above, 2), (index: 3, folderId: null));
    expect(
      newRowPlacement(above, 1),
      (index: 1, folderId: null),
      reason: 'under the base is outside its group',
    );

    final below = [row('RB', ridesOn: 'B'), row('B'), row('Y')];
    expect(newRowPlacement(below, 1), (index: 2, folderId: null));
  });

  test('an aim past either end is the end', () {
    final stack = [row('A')];

    expect(newRowPlacement(stack, 5), (index: 1, folderId: null));
    expect(newRowPlacement(stack, -2), (index: 0, folderId: null));
  });
}
