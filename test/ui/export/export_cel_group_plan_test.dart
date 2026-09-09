import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
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
  // A cel carries its number as the frame name; an unnamed frame is the
  // in-between mark and exports nothing. The fixture ids' digits double as
  // the cel number ('f1' → '1') unless a test names the frame itself, and
  // `unnamed: true` builds the mark on purpose.
  Frame frame(String id, {String? name, bool unnamed = false}) => Frame(
    id: FrameId(id),
    duration: 1,
    strokes: const [],
    name: unnamed ? null : (name ?? id.replaceAll(RegExp('[^0-9]'), '')),
  );

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
    expect(restored.cels.single.members.map((layer) => layer.name), [
      'A',
      'A색',
    ]);
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

  test('the cel number IS the frame name; an unnamed frame is the '
      'in-between mark and has no file', () {
    // 유저 2026-09-09: 「프레임 이름을 그대로 셀 번호로 출력시키고, 이름 없으면
    // 출력 안 하도록 — 이름 없으면 중간나누기 마크인 거니까」. The old plan
    // numbered f2 by its position ('CUT1_A002.png'); the sheet had always
    // printed ○ for it.
    final baseA = base('a', 'A', [
      frame('f1', name: '3'),
      frame('f2', unnamed: true),
      frame('f3', name: '  '),
    ]);
    final plan = buildExportCelGroupPlan(
      project: projectWith([baseA]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(
        naming: ExportCelNaming(includeCutName: true, frameDigits: 3),
      ),
    );
    expect(plan.cels.map((task) => task.fileName), ['CUT1_A003.png']);
    expect(plan.cels.single.baseFrame.id.value, 'f1');
  });

  test('the sheet and the export agree on which drawing is a cel', () {
    // One getter answers both — a blank name is the mark on either side.
    expect(frame('f1', name: '12').celNumber, '12');
    expect(frame('f1', name: ' 12 ').celNumber, '12');
    expect(frame('f1', unnamed: true).celNumber, isNull);
    expect(frame('f1', name: '').celNumber, isNull);
    expect(frame('f1', name: '\t').celNumber, isNull);
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

  /// 🚨A FILE NAME THAT REPEATS IS A FILE THAT DISAPPEARS.
  ///
  /// Two labels can each hold a cel called `1`, and a naming that leaves
  /// the label out puts both in one folder under one name. The bump
  /// (`_2`, `_3`, …) is what the user sees instead of one of the two
  /// cels simply not being written. Nothing checked it until
  /// 2026-09-05: the whole uniqueness loop could be deleted and the
  /// suite stayed green.
  test('🚨two labels holding a cel of the same name get two FILES', () {
    final plan = buildExportCelGroupPlan(
      project: projectWith([
        base('a', 'A', [frame('f1')]),
        base('b', 'B', [frame('g1')]),
      ]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(
        naming: ExportCelNaming(includeLayerName: false),
      ),
    );

    final names = plan.cels.map((task) => task.fileName).toList();
    expect(names, hasLength(2));
    expect(
      names.toSet(),
      hasLength(2),
      reason: 'the second write would have replaced the first: $names',
    );
    expect(names.last, contains('_2'));
  });

  test('🚨the label FOLDER is a folder, not a prefix — a cel of label A '
      'lands under A/', () {
    final plan = buildExportCelGroupPlan(
      project: projectWith([
        base('a', 'A', [frame('f1')]),
      ]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(naming: ExportCelNaming(layerFolder: true)),
    );

    expect(plan.cels.single.fileName, startsWith('A/'));
  });

  test('the cut folder and the label folder nest, cut outside', () {
    final plan = buildExportCelGroupPlan(
      project: projectWith([
        base('a', 'A', [frame('f1')]),
      ]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(
        naming: ExportCelNaming(cutFolder: true, layerFolder: true),
      ),
    );

    expect(plan.cels.single.fileName, startsWith('CUT1/A/'));
  });

  test('🚨an instruction file shares the run\'s names — a camera event and '
      'a cel cannot collide either', () {
    final plan = buildExportCelGroupPlan(
      project: projectWith([
        base('a', 'A', [frame('f1')]),
        Layer(
          id: const LayerId('i'),
          name: 'A',
          kind: LayerKind.instruction,
          frames: const [],
          instructions: {
            0: const InstructionEvent(
              instructionId: 'pan',
              length: 2,
              text: 'PAN',
            ),
          },
        ),
      ]),
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(
        naming: ExportCelNaming(includeLayerName: false),
      ),
    );

    final names = [
      ...plan.cels.map((task) => task.fileName),
      ...plan.instructions.map((task) => task.fileName),
    ];
    expect(names.toSet(), hasLength(names.length), reason: '$names');
  });
}
