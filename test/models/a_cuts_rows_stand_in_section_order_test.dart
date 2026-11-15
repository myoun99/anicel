// A CUT'S ROWS STAND IN SECTION ORDER, HOWEVER THEY WERE HANDED IN — THE
// ORDER EVERY ROUTE THAT PAINTS THEM WALKS.
//
// 🗣️F-596 (user, 2026-11-15): 「디렉션레이어는 위치적으로 이거보다 위
// 레이어는 없기때문에 액션란들 그림보다 항상 위에 있어야하는데 그게
// 아닌거같음」.
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  const cutId = CutId('cut');
  Layer drawing(String name) => Layer(
    id: LayerId(name),
    name: name,
    frames: const [],
    timeline: const {},
  );
  final direction = createInstructionLayer(cutId: cutId);
  final camera = createCameraLayer(cutId: cutId);
  List<String> namesOf(List<Layer> layers) => [
    for (final layer in layers) layer.name,
  ];

  test('handed in with drawing rows above the direction row, a cut stands '
      'them under it — and under the camera', () {
    final cut = Cut(
      id: cutId,
      name: 'C1',
      layers: [direction, drawing('A'), camera, drawing('B')],
      duration: 24,
      canvasSize: const CanvasSize(width: 100, height: 100),
    );
    expect(namesOf(cut.layers), [
      'A',
      'B',
      direction.name,
      camera.name,
    ]);

    expect(
      namesOf(
        cut.copyWith(layers: [...cut.layers, drawing('C')]).layers,
      ),
      ['A', 'B', 'C', direction.name, camera.name],
      reason: 'a row added past the camera, as a copy is handed it',
    );

    expect(
      namesOf(
        cut.copyWith(layers: [drawing('A'), camera, direction]).layers,
      ),
      ['A', direction.name, camera.name],
      reason: 'the camera on top of its section, over the direction row '
          '(A5-4) — a list whose sections alone are in order',
    );
  });

  test('a row made with ＋ in a NEW cut — its direction row and camera, '
      'nothing else — stands under the direction row', () {
    final session = EditorSessionManager(initialProject: newUntitledProject());
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    expect(
      session.activeLayer?.kind,
      LayerKind.instruction,
      reason: '⛔premise: a new cut stands on its direction row',
    );

    session.layerStack.addLayerOfKind(LayerKind.animation);
    session.layerStack.addLayerOfKind(LayerKind.animation);

    expect(
      [for (final layer in session.requireActiveCut.layers) layer.kind],
      [
        LayerKind.animation,
        LayerKind.animation,
        LayerKind.instruction,
        LayerKind.camera,
      ],
    );
  });
}
