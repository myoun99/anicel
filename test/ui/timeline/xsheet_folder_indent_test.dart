import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// UI-R5 #18, transposed: a COLUMN spells its folder nesting too.
///
/// The rail indents along a row's long axis, where the name keeps whatever
/// width is left. A column indents along the very run the name is written
/// down, so every level costs the name directly — which is why the depth
/// it spells out is capped, and why the name clips instead of ellipsing.
void main() {
  Layer cel(String id, {LayerId? folderId}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: const {},
    folderId: folderId,
  );

  // top · f1 > inner1 · f1 > f2 > inner2 · f1 > f2 > f3 > inner3
  final layers = <Layer>[
    cel('top'),
    createFolderLayer(id: const LayerId('f1'), name: 'F1'),
    cel('inner1', folderId: const LayerId('f1')),
    createFolderLayer(
      id: const LayerId('f2'),
      name: 'F2',
    ).copyWith(folderId: const LayerId('f1')),
    cel('inner2', folderId: const LayerId('f2')),
    createFolderLayer(
      id: const LayerId('f3'),
      name: 'F3',
    ).copyWith(folderId: const LayerId('f2')),
    cel('inner3', folderId: const LayerId('f3')),
  ];

  Future<void> pumpXSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayerId: const LayerId('top'),
            frameCursor: ValueNotifier<int>(0),
            playbackFrameCount: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.vertical,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double nameRun(WidgetTester tester, String id) => tester
      .getSize(find.byKey(ValueKey<String>('xsheet-layer-name-$id')))
      .height;

  testWidgets('nesting eats the name\'s own run, and stops eating at the cap', (
    tester,
  ) async {
    await pumpXSheet(tester);

    final flat = nameRun(tester, 'top');
    final one = nameRun(tester, 'inner1');
    final two = nameRun(tester, 'inner2');
    final three = nameRun(tester, 'inner3');

    expect(
      one,
      lessThan(flat),
      reason: 'one level of nesting costs the name one slot',
    );
    expect(two, lessThan(one), reason: 'and the second costs another');
    expect(
      three,
      moreOrLessEquals(two),
      reason:
          'past the cap the arrow alone says "nested" — the name must not '
          'clip to nothing on a deep tree',
    );
    expect(
      three,
      greaterThan(0),
      reason: 'a column that cannot show its name cannot be identified',
    );
  });
}
