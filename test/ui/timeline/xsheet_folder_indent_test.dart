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
  testWidgets('🆕nesting costs the name a GUIDE per level, and there is no '
      'cap because there is no run to cap', (tester) async {
    // 🪦This used to assert a two-level cap: depth was cells in the leading
    // run, which on a column runs down the very length the name is written
    // in, so a third level left nothing. 2026-08-29 moved depth into the
    // name as an 8px guide per level — the same move the rail made — and
    // the cap went with the run.
    await pumpXSheet(tester);

    final flat = nameRun(tester, 'top');
    final one = nameRun(tester, 'inner1');
    final two = nameRun(tester, 'inner2');
    final three = nameRun(tester, 'inner3');

    expect(one, lessThan(flat), reason: '한 겹이 가이드 하나만큼 먹는다');
    expect(two, lessThan(one), reason: '두 겹째도 같은 만큼');
    expect(
      three,
      lessThan(two),
      reason: '🚨cap 이 없다 — 세 겹째도 계속 먹는다',
    );
    expect(
      flat - one,
      moreOrLessEquals(two - three, epsilon: 0.5),
      reason: '한 겹의 값은 어느 깊이에서나 같다',
    );
    expect(
      three,
      greaterThan(0),
      reason: '이름을 못 보이는 열은 식별할 수 없다',
    );
  });
}
