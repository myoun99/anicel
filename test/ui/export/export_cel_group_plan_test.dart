import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_overrides.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/export_cel_naming.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';

void main() {
  Frame frame(String id, {String? name}) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer base(String id, String name, List<Frame> frames) =>
      Layer(id: LayerId(id), name: name, frames: frames);

  Project projectWith(List<Layer> layers, {CameraInstructionSet? defs}) =>
      Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraInstructions: defs,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'CUT1',
                duration: 4,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  ...layers,
                  createCameraLayer(cutId: const CutId('cut')),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      );

  test('a label composites its synced members through the cell links', () {
    final baseA = base('a', 'A', [frame('f1'), frame('f2')]);
    final sync = Layer(
      id: const LayerId('a-color'),
      name: 'A색',
      frames: [frame('c1'), frame('c2')],
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {
        const FrameId('f1'): const FrameId('c1'),
        const FrameId('f2'): const FrameId('c2'),
      },
    );
    final plan = buildExportCelGroupPlan(
      project: projectWith([baseA, sync]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(),
    );

    expect(plan.cels, hasLength(2));
    final first = plan.cels.first;
    expect(first.members.map((layer) => layer.name), ['A', 'A색']);
    expect(first.memberFrames.map((frame) => frame?.id.value), ['f1', 'c1']);
    expect(first.fileName, 'A1.png');
    expect(plan.cels.last.memberFrames.last?.id.value, 'c2');
  });

  test('the sync gate removes the member; the delta puts it back', () {
    final baseA = base('a', 'A', [frame('f1')]);
    final sync = Layer(
      id: const LayerId('a-color'),
      name: 'A색',
      frames: [frame('c1')],
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.synced,
      baseFrameLinks: {const FrameId('f1'): const FrameId('c1')},
    );
    final project = projectWith([baseA, sync]);

    final gated = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(includeSyncedAttach: false),
    );
    expect(gated.cels.single.members.map((layer) => layer.name), ['A']);

    final restored = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(includeSyncedAttach: false),
      overrides: ExportProjectOverrides().withCelsDelta(
        const CutId('cut'),
        ExportCelsCutDelta().withLayerOverride(const LayerId('a-color'), true),
      ),
    );
    expect(
      restored.cels.single.members.map((layer) => layer.name),
      ['A', 'A색'],
    );
  });

  test('a FREE member maps through what it exposes at the base cel', () {
    final baseA = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [frame('f1'), frame('f2')],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
        2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
      },
    );
    final free = Layer(
      id: const LayerId('shadow'),
      name: 'A影',
      frames: [frame('s1'), frame('s2')],
      attachedToLayerId: const LayerId('a'),
      attachedMode: AttachedMode.free,
      timeline: {
        0: const TimelineExposure.drawing(FrameId('s1'), length: 3),
        3: const TimelineExposure.drawing(FrameId('s2'), length: 1),
      },
    );
    final plan = buildExportCelGroupPlan(
      project: projectWith([baseA, free]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(),
    );
    // Base cel f1 first shows at 0 → the free row exposes s1 there; f2
    // first shows at 2 → still s1 (its own block runs to 3).
    expect(plan.cels[0].memberFrames.last?.id.value, 's1');
    expect(plan.cels[1].memberFrames.last?.id.value, 's1');
  });

  test('cel numbering honors Frame.name and the naming options', () {
    final baseA = base('a', 'A', [frame('f1', name: '3'), frame('f2')]);
    final plan = buildExportCelGroupPlan(
      project: projectWith([baseA]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(
        naming: ExportCelNaming(includeCutName: true, frameDigits: 3),
      ),
    );
    expect(plan.cels.map((task) => task.fileName), [
      'CUT1_A003.png',
      'CUT1_A002.png',
    ]);
  });

  test('instruction layers export per event with the row text', () {
    final baseA = base('a', 'A', [frame('f1')]);
    final instruction = Layer(
      id: const LayerId('inst'),
      name: 'Camera',
      frames: const [],
      kind: LayerKind.instruction,
      instructions: {
        0: const InstructionEvent(
          instructionId: 'pan',
          length: 12,
          text: 'PAN',
        ),
      },
    );
    final plan = buildExportCelGroupPlan(
      project: projectWith([baseA, instruction]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(),
    );
    expect(plan.instructions, hasLength(1));
    expect(plan.instructions.single.label, 'PAN');
    expect(plan.instructions.single.length, 12);
    expect(plan.instructions.single.fileName, 'Camera1.png');

    final off = buildExportCelGroupPlan(
      project: projectWith([baseA, instruction]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(includeInstructionLayers: false),
    );
    expect(off.instructions, isEmpty);
  });

  test('project scope honors the cut checks', () {
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            for (final id in ['c1', 'c2'])
              Cut(
                id: CutId(id),
                name: id.toUpperCase(),
                duration: 2,
                canvasSize: const CanvasSize(width: 8, height: 8),
                layers: [
                  Layer(
                    id: LayerId('$id-a'),
                    name: 'A',
                    frames: [frame('$id-f1')],
                  ),
                  createCameraLayer(cutId: CutId(id)),
                ],
              ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    );
    final plan = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('c1'),
      spec: const CelsExportSpec(scope: ExportScopeKind.project),
      overrides: ExportProjectOverrides().withCutIncluded(
        const CutId('c2'),
        false,
      ),
    );
    expect(plan.cels.map((task) => task.cut.id.value).toSet(), {'c1'});
  });
}
