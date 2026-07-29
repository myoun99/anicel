import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R6-④: the brush only lands on drawing-section layers — SE cels are
/// timing/dialogue data and instruction/camera rows are notation, so they
/// never produce an editable brush target (their existing cels still
/// composite read-only in the editing canvas stack).
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  test('the brush-input policy bans SE, instruction and camera kinds', () {
    expect(layerKindAcceptsBrushInput(LayerKind.animation), isTrue);
    expect(layerKindAcceptsBrushInput(LayerKind.storyboard), isTrue);
    expect(layerKindAcceptsBrushInput(LayerKind.image), isTrue);
    expect(layerKindAcceptsBrushInput(LayerKind.se), isFalse);
    expect(layerKindAcceptsBrushInput(LayerKind.instruction), isFalse);
    expect(layerKindAcceptsBrushInput(LayerKind.camera), isFalse);
  });

  test('a media-REFERENCE layer refuses the brush at LAYER level while '
      'its kind still allows it (§6-z23: the field is the predicate)', () {
    final drawn = Layer(
      id: const LayerId('img'),
      name: '_BG',
      kind: LayerKind.image,
      frames: const [],
      timeline: const {},
    );
    expect(layerAcceptsBrushInput(drawn), isTrue);

    final referenced = drawn.copyWith(
      mediaReference: const MediaReference(assetPath: 'C:/bg.png'),
    );
    expect(layerAcceptsBrushInput(referenced), isFalse);

    // RASTERIZE = null the field, nothing else — drawing comes back.
    final rasterized = referenced.copyWith(mediaReference: null);
    expect(rasterized.kind, LayerKind.image, reason: 'kind never changes');
    expect(layerAcceptsBrushInput(rasterized), isTrue);
  });

  test('an active SE layer yields NO brush editor selection even with a '
      'selected entry, while a drawing layer still does', () {
    // Sanity: the default active drawing layer edits normally.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    expect(session.activeBrushEditorSelection, isNotNull);

    // The SE fixture layer: create an entry, land the selection on it.
    final seLayer = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.se,
    );
    session.selectLayer(seLayer.id);
    session.selectFrameIndex(0);
    session.createSeEntryAtCurrentFrame(name: '쿵');
    expect(session.selectedFrame, isNotNull, reason: 'entry exists');
    expect(
      session.activeBrushEditorSelection,
      isNull,
      reason: 'SE cels are data rows — the pen must not land on them',
    );
  });

  test('a brush-banned active layer still composites read-only in the '
      'editing canvas stack', () {
    final seLayer = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.se,
    );
    session.selectLayer(seLayer.id);
    session.selectFrameIndex(0);
    session.createSeEntryAtCurrentFrame(name: '쿵');

    final stackLayerIds = [
      for (final node in session.editingCanvasStack.nodes)
        if (node is CanvasLayerImageNode) node.request.frameKey.layerId,
    ];
    expect(
      stackLayerIds,
      contains(seLayer.id),
      reason: 'the active-but-banned layer draws like any stack layer',
    );
  });
}
