import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/export/ae_script.dart';
import 'package:anicel/src/ui/export/ae_script_plan.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';

void main() {
  const key = LayerMark(process: LayerProcess.key);
  const canvas = CanvasSize(width: 8, height: 8);

  /// Row [row]'s cel [name] — its id the row's own.
  Frame frame(String row, String name) =>
      Frame(
        id: FrameId('$row-$name'),
        duration: 1,
        strokes: const [],
        name: name,
      );

  /// A key row whose [blocks] show its cels: start → (cel, length).
  Layer row(
    String id, {
    required Map<int, (String, int)> blocks,
    String? folder,
    TransformTrack? transformTrack,
    LayerBlendMode blend = LayerBlendMode.normal,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    mark: key,
    frames: [
      for (final cel in {for (final (cel, _) in blocks.values) cel})
        frame(id, cel),
    ],
    timeline: {
      for (final MapEntry(key: start, value: (cel, length)) in blocks.entries)
        start: TimelineExposure.drawing(
          FrameId('$id-$cel'),
          length: length,
        ),
    },
    folderId: folder == null ? null : LayerId(folder),
    transformTrack: transformTrack,
    blendMode: blend,
  );

  Layer folder(
    String id, {
    LayerBlendMode blend = LayerBlendMode.passThrough,
    TransformTrack? transformTrack,
  }) => createFolderLayer(id: LayerId(id), name: id.toUpperCase()).copyWith(
    blendMode: blend,
    transformTrack: transformTrack,
  );

  Project projectWith(List<Layer> layers) => Project(
    id: const ProjectId('project'),
    name: 'Project',
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: const CutId('cut'),
            name: 'C1',
            duration: 6,
            canvasSize: canvas,
            layers: [...layers, createCameraLayer(cutId: const CutId('cut'))],
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  AeScript scriptOf(
    List<Layer> layers, {
    CameraPose Function(Cut cut, int frame)? cameraPoseAt,
  }) {
    final project = projectWith(layers);
    return buildAeScript(
      project: project,
      plan: buildExportCelGroupPlan(
        project: project,
        activeCutId: const CutId('cut'),
        spec: const AeScriptExportSpec().written,
      ),
      name: 'C1',
      cameraFrameSize: const CanvasSize(width: 4, height: 2),
      framesOf: (cut) => cut.duration,
      cameraPoseAt:
          cameraPoseAt ??
          (_, _) => CameraPose(center: CanvasPoint(x: 4, y: 4)),
    );
  }

  AeComp compNamed(AeScript script, String name) =>
      script.comps.singleWhere((comp) => comp.name == name);

  AeLayer layerNamed(AeComp comp, String name) =>
      comp.layers.singleWhere((layer) => layer.name == name);

  test('a cut is a canvas comp inside a camera comp, after the cel comps it '
      'shows', () {
    final script = scriptOf([
      row('a', blocks: {0: ('1', 2)}),
    ]);
    expect([for (final comp in script.comps) comp.name], [
      'A cels',
      'C1 canvas',
      'C1',
    ]);
    final canvasComp = compNamed(script, 'C1 canvas');
    expect((canvasComp.width, canvasComp.height, canvasComp.frames), (8, 8, 6));
    final camera = compNamed(script, 'C1');
    expect((camera.width, camera.height, camera.frames), (4, 2, 6));
    expect(
      (camera.layers.single.source as AeCompSource).comp,
      same(canvasComp),
    );
  });

  test('a row is ONE layer: its cels a frame each, held where its blocks '
      'show them — and nothing where none does', () {
    final script = scriptOf([
      row('a', blocks: {0: ('1', 2), 3: ('2', 2)}),
    ]);
    final bank = compNamed(script, 'A cels');
    expect(bank.frames, 3, reason: 'two cels and an empty frame');
    expect([
      for (final layer in bank.layers) (layer.source as AeStill).frame,
    ], [0, 1]);
    final a = layerNamed(compNamed(script, 'C1 canvas'), 'A');
    expect((a.source as AeCompSource).comp, same(bank));
    expect(a.timeRemap, [
      (frame: 0, source: 0),
      (frame: 2, source: 2),
      (frame: 3, source: 1),
      (frame: 5, source: 2),
    ]);
  });

  test('a row\'s transform is its own pose, AE\'s values', () {
    final script = scriptOf([
      row(
        'a',
        blocks: {0: ('1', 6)},
        transformTrack: TransformTrack(
          keyframes: {
            0: TransformPose(
              center: CanvasPoint(x: 2, y: 3),
              scaleX: 2,
              scaleY: 0.5,
              rotationDegrees: 30,
            ),
          },
        ),
      ),
    ]);
    final transform = layerNamed(compNamed(script, 'C1 canvas'), 'A')
        .transform!;
    expect(transform.anchor.value, [4, 4], reason: 'the canvas centre');
    expect(transform.position.value, [2, 3]);
    expect(transform.scale.value, [200, 50]);
    expect(transform.rotation.value, [30]);
    expect(transform.opacity.value, [100]);
  });

  test('a pose that moves is a value a frame', () {
    final script = scriptOf([
      row(
        'a',
        blocks: {0: ('1', 6)},
        transformTrack: TransformTrack(
          keyframes: {
            0: TransformPose(center: CanvasPoint(x: 0, y: 4)),
            5: TransformPose(center: CanvasPoint(x: 5, y: 4)),
          },
        ),
      ),
    ]);
    final position = layerNamed(compNamed(script, 'C1 canvas'), 'A')
        .transform!
        .position;
    expect(position.frames, hasLength(6));
    expect(position.frames!.first, [0, 4]);
    expect(position.frames!.last, [5, 4]);
  });

  test('a folder that passes its rows through is a null they hang on, on '
      'which its pose stands', () {
    final script = scriptOf([
      row('a', blocks: {0: ('1', 6)}, folder: 'f'),
      folder(
        'f',
        transformTrack: TransformTrack(
          keyframes: {
            0: TransformPose(
              center: CanvasPoint(x: 1, y: 1),
              scaleX: 3,
            ),
          },
        ),
      ),
    ]);
    final canvasComp = compNamed(script, 'C1 canvas');
    final f = layerNamed(canvasComp, 'F');
    expect(f.source, isA<AeNullSource>());
    expect(f.transform!.scale.value, [300, 100]);
    expect(f.transform!.position.value, [1, 1]);
    expect(layerNamed(canvasComp, 'A').parent, same(f));
    expect(
      canvasComp.layers.indexOf(f),
      lessThan(canvasComp.layers.indexOf(layerNamed(canvasComp, 'A'))),
      reason: 'a parent is made before what hangs on it',
    );
  });

  test('a folder the app composites as one picture is a comp of its own, '
      'at its blend', () {
    final script = scriptOf([
      row('b', blocks: {0: ('1', 6)}),
      row('a', blocks: {0: ('1', 6)}, folder: 'm'),
      folder('m', blend: LayerBlendMode.multiply),
    ]);
    final canvasComp = compNamed(script, 'C1 canvas');
    expect([for (final layer in canvasComp.layers) layer.name], ['B', 'M']);
    final m = layerNamed(canvasComp, 'M');
    expect(m.blend, LayerBlendMode.multiply);
    final inner = (m.source as AeCompSource).comp;
    expect(inner.tucked, isTrue);
    expect([for (final layer in inner.layers) layer.name], ['A']);
    expect(
      script.comps.indexOf(inner),
      lessThan(script.comps.indexOf(canvasComp)),
      reason: 'a comp is made before the comp that shows it',
    );
  });

  test('the camera comp looks at the canvas where the camera stands', () {
    final script = scriptOf(
      [
        row('a', blocks: {0: ('1', 6)}),
      ],
      cameraPoseAt: (_, frame) => CameraPose(
        center: CanvasPoint(x: 2.0 + frame, y: 4),
        zoom: 2,
        rotationDegrees: 10,
      ),
    );
    final look = compNamed(script, 'C1').layers.single.transform!;
    expect(look.anchor.frames!.first, [2, 4]);
    expect(look.anchor.frames!.last, [7, 4]);
    expect(look.position.value, [2, 1], reason: 'the camera comp\'s centre');
    expect(look.scale.value, [200, 200]);
    expect(look.rotation.value, [-10]);
  });
}
