import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/export/export_cels_selection.dart';

void main() {
  Layer layer(
    String id, {
    String? name,
    LayerKind kind = LayerKind.animation,
    bool isVisible = true,
    bool onTimesheet = true,
    String? attachedTo,
    AttachedMode attachedMode = AttachedMode.synced,
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: name ?? id.toUpperCase(),
    frames: const [],
    kind: kind,
    isVisible: isVisible,
    onTimesheet: onTimesheet,
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: attachedMode,
    folderId: folder == null ? null : LayerId(folder),
  );

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'CUT1',
    duration: 12,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: layers,
  );

  List<String> celIds(ExportCelsSelection selection) => [
    for (final layer in selection.celLayers) layer.id.value,
  ];

  test('defaults: drawing layers in, camera/SE out, instruction rows in', () {
    final selection = resolveExportCelsSelection(
      cut: cut([
        layer('a'),
        layer('bg', kind: LayerKind.image),
        layer('se', kind: LayerKind.se),
        layer('inst', kind: LayerKind.instruction),
        layer('cam', kind: LayerKind.camera),
      ]),
      spec: const CelsExportSpec(),
    );
    expect(celIds(selection), ['a', 'bg']);
    expect(selection.instructionLayers.single.id.value, 'inst');
  });

  test('instruction toggle off empties the instruction list', () {
    final selection = resolveExportCelsSelection(
      cut: cut([layer('a'), layer('inst', kind: LayerKind.instruction)]),
      spec: const CelsExportSpec(includeInstructionLayers: false),
    );
    expect(selection.instructionLayers, isEmpty);
  });

  test('hidden layers and timesheet-only filtering', () {
    final selection = resolveExportCelsSelection(
      cut: cut([
        layer('a'),
        layer('hidden', isVisible: false),
        layer('off-sheet', onTimesheet: false),
      ]),
      spec: const CelsExportSpec(onTimesheetOnly: true),
    );
    expect(celIds(selection), ['a']);
  });

  test('attach gates: synced and free rows follow their toggles', () {
    final layers = [
      layer('base'),
      layer('sync', attachedTo: 'base'),
      layer('free', attachedTo: 'base', attachedMode: AttachedMode.free),
    ];
    expect(
      celIds(
        resolveExportCelsSelection(cut: cut(layers), spec: const CelsExportSpec()),
      ),
      ['base', 'sync', 'free'],
    );
    expect(
      celIds(
        resolveExportCelsSelection(
          cut: cut(layers),
          spec: const CelsExportSpec(includeSyncedAttach: false),
        ),
      ),
      ['base', 'free'],
    );
    expect(
      celIds(
        resolveExportCelsSelection(
          cut: cut(layers),
          spec: const CelsExportSpec(includeFreeAttach: false),
        ),
      ),
      ['base', 'sync'],
    );
  });

  test('folder expansion pulls the rest of an included folder', () {
    final layers = [
      layer('a', folder: 'f'),
      layer('b', folder: 'f', onTimesheet: false),
      createFolderLayer(id: const LayerId('f'), name: 'F'),
      layer('c'),
    ];
    // Without expansion the timesheet filter drops b.
    expect(
      celIds(
        resolveExportCelsSelection(
          cut: cut(layers),
          spec: const CelsExportSpec(onTimesheetOnly: true),
        ),
      ),
      ['a', 'c'],
      reason: 'the folder ROW itself never exports a cel of its own',
    );
    // With expansion b rides its folder back in.
    expect(
      celIds(
        resolveExportCelsSelection(
          cut: cut(layers),
          spec: const CelsExportSpec(
            onTimesheetOnly: true,
            includeFolderMembers: true,
          ),
        ),
      ),
      ['a', 'b', 'c'],
    );
  });

  test('delta wins last: force-exclude a rule pick, force-include a hidden '
      'layer, never a camera/SE row', () {
    final layers = [
      layer('a'),
      layer('hidden', isVisible: false),
      layer('se', kind: LayerKind.se),
    ];
    final delta = ExportCelsCutDelta()
        .withLayerOverride(const LayerId('a'), false)
        .withLayerOverride(const LayerId('hidden'), true)
        .withLayerOverride(const LayerId('se'), true);
    final selection = resolveExportCelsSelection(
      cut: cut(layers),
      spec: const CelsExportSpec(),
      delta: delta,
    );
    expect(celIds(selection), ['hidden']);
  });
}
