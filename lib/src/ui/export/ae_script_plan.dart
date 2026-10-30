import '../../models/attached_layer_resolve.dart' show fxCarrierOf;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/timeline_coverage.dart';
import '../../models/transform_track.dart' show resolveOpacityTrackAt;
import '../../services/commands/link_mirror.dart'
    show linkCounterpartIn, linkedCutGroupInTrackOrder;
import '../../services/cut_frame_composite_plan.dart'
    show folderNeedsCompositeBuffer, layerOwnPlacementAt, resolveFolderOpacityAt;
import '../../services/export/ae_script.dart';
import '../canvas/canvas_look.dart' show CanvasCamera;
import 'ae_keyframe_data.dart' show aeCameraSampleOf;
import 'export_cel_group_plan.dart';

/// The After Effects project [plan]'s cels are laid into — the AE Script
/// tab's script (ae-script-export).
///
/// 🗣️ae-script-export-Q1 (유저 2026-10-15): a cut is TWO comps — 「카메라용
/// 컴포지션(카메라 해상도 크기의 컴포지션,그안에 소재 컴포지션있음), 그리고 소재
/// 컴포지션(캔버스 사이즈의 컴포지션. 여기에 원본 그림이 들어감)」. In the
/// canvas comp, a row's cels are ONE layer: a comp of its cels a frame each,
/// shown a cel at a time by Time Remap hold keys where the row's blocks say
/// — 🗣️유저 2026-07-25 「일반적으로 타임리맵」, a layer a block turned down.
/// A folder that passes its rows through is a null they are parented to;
/// one the app composites as one picture ([folderNeedsCompositeBuffer]) is
/// a comp of its own. Q2 「날것으로 — 이펙트 없이」: no effect is carried.
/// Q4 「넣는다 — 앱이 놓은 그대로 WAV 로」: the camera comp sounds the cut.
///
/// A transform is the app's own, AE's order (`layerPoseMatrix`): anchor,
/// scale, turn, position — a folder's over its rows' by parenting. Values
/// are baked a frame each ([AeChannel]) and keyed where they change, the
/// camera's precedent ([aeCameraSampleOf]): AE's own interpolation between
/// the app's keys is not the app's.
///
/// What a row's cel already holds is not laid again: its static opacity
/// and the rows riding it are in its picture (`renderCelGroup`), so its
/// layer carries the transform's animated opacity alone.
///
/// [runOf] is how a cut's comps run ([AeCutRun]). [camera] is the camera
/// the render looks through. The script's name and rate are the caller's
/// ([AeScript]).
List<AeComp> aeCompsOf({
  required Project project,
  required ExportCelGroupPlan plan,
  required CanvasCamera camera,
  required AeCutRun Function(Cut cut) runOf,
}) {
  final comps = <AeComp>[];
  final banks = <CutId, Map<LayerId, _Bank>>{};
  for (final (:listed, :cut) in _laidCuts(project, plan)) {
    final listedBanks = banks.putIfAbsent(
      listed.id,
      () => _banksOf(listed, plan, comps),
    );
    final run = runOf(cut);
    final laying = _CanvasLaying(
      cut: cut,
      frames: run.frames,
      banks: {
        for (final MapEntry(key: axis, value: bank) in listedBanks.entries)
          ?_counterpart(project, listed, axis, cut): bank,
      },
      comps: comps,
    );
    final canvas = AeComp(
      name: '${cut.name} canvas',
      width: cut.canvasSize.width,
      height: cut.canvasSize.height,
      frames: run.frames,
      layers: laying.stack(null),
    );
    comps
      ..add(canvas)
      ..add(_cameraComp(cut, canvas, camera, sound: run.sound));
  }
  return comps;
}

/// A cut as its comps run: [frames] long — its sheet's rows, the のりしろ an
/// O.L asks included, as its XDTS (`cutSheetFrameCount`) — and the sound
/// heard along them: a file beside the script, or null where the cut
/// sounds nothing.
typedef AeCutRun = ({int frames, String? sound});

/// The cuts [aeCompsOf] lays a camera comp for, in its order — the ones a
/// caller writes a sound for.
Iterable<Cut> aeCutsOf(Project project, ExportCelGroupPlan plan) => [
  for (final (:cut, listed: _) in _laidCuts(project, plan)) cut,
];

/// Each cut the plan lists cels in, then the cuts linked to it in track
/// order, each once — with the listed cut whose cels it shows.
Iterable<({Cut listed, Cut cut})> _laidCuts(
  Project project,
  ExportCelGroupPlan plan,
) sync* {
  final laid = <CutId>{};
  for (final listed in _listedCuts(plan)) {
    for (final cut in linkedCutGroupInTrackOrder(project, cutId: listed.id)) {
      if (laid.add(cut.id)) {
        yield (listed: listed, cut: cut);
      }
    }
  }
}

/// The cuts the plan lists cels in, in its order.
Iterable<Cut> _listedCuts(ExportCelGroupPlan plan) {
  final seen = <CutId>{};
  return [
    for (final sheet in plan.sheets)
      if (seen.add(sheet.cut.id)) sheet.cut,
  ];
}

/// [axis] of [listed] as [cut] has it: itself, or its link there.
LayerId? _counterpart(Project project, Cut listed, LayerId axis, Cut cut) =>
    cut.id == listed.id
    ? axis
    : linkCounterpartIn(
        project,
        cutId: listed.id,
        layerId: axis,
        targetCutId: cut.id,
      );

/// One row's cels as a comp: each written cel a frame, in the order the
/// list meets them, and a last frame of nothing for where none shows.
typedef _Bank = ({AeComp comp, Map<FrameId, int> frameOf});

/// The cel comp of every row [listed] lists cels on — made into [comps]
/// as they are met. A row with no cel written has none.
Map<LayerId, _Bank> _banksOf(
  Cut listed,
  ExportCelGroupPlan plan,
  List<AeComp> comps,
) {
  final cels = <LayerId, List<ExportCelSheet>>{};
  final rows = <LayerId, Layer>{};
  for (final sheet in plan.sheets) {
    if (sheet.cut.id != listed.id || !sheet.written) {
      continue;
    }
    rows[sheet.row.id] = sheet.row;
    cels.putIfAbsent(sheet.row.id, () => []).add(sheet);
  }
  return {
    for (final MapEntry(key: id, value: sheets) in cels.entries)
      id: _bank(listed, rows[id]!, sheets, comps),
  };
}

_Bank _bank(
  Cut listed,
  Layer row,
  List<ExportCelSheet> sheets,
  List<AeComp> comps,
) {
  final comp = AeComp(
    name: '${row.name} cels',
    width: listed.canvasSize.width,
    height: listed.canvasSize.height,
    frames: sheets.length + 1,
    tucked: true,
    layers: [
      for (var frame = 0; frame < sheets.length; frame += 1)
        AeLayer(
          name: sheets[frame].fullName,
          source: AeStill(path: sheets[frame].fileName, frame: frame),
        ),
    ],
  );
  comps.add(comp);
  return (
    comp: comp,
    frameOf: {
      for (var frame = 0; frame < sheets.length; frame += 1)
        sheets[frame].frame.id: frame,
    },
  );
}

/// [cut]'s camera comp: the camera's frame, looking at [canvas] where the
/// camera stands — anchored at its centre, turned against it and scaled
/// by its zoom ([aeCameraSampleOf]) — over the cut's [sound], if it has one.
AeComp _cameraComp(
  Cut cut,
  AeComp canvas,
  CanvasCamera camera, {
  required String? sound,
}) {
  final frameSize = camera.frameSize;
  final samples = [
    for (var frame = 0; frame < canvas.frames; frame += 1)
      aeCameraSampleOf(frame, camera.poseOf(cut, frame)),
  ];
  return AeComp(
    name: cut.name,
    width: frameSize.width,
    height: frameSize.height,
    frames: canvas.frames,
    layers: [
      if (sound != null) AeLayer(name: sound, source: AeSound(sound)),
      AeLayer(
        name: canvas.name,
        source: AeCompSource(canvas),
        transform: AeTransform(
          anchor: AeChannel.sampled(
            samples.length,
            (frame) => [samples[frame].anchorX, samples[frame].anchorY],
          ),
          position: AeChannel.still([
            frameSize.width / 2,
            frameSize.height / 2,
          ]),
          scale: AeChannel.sampled(
            samples.length,
            (frame) => [
              samples[frame].scalePercent,
              samples[frame].scalePercent,
            ],
          ),
          rotation: AeChannel.sampled(
            samples.length,
            (frame) => [samples[frame].rotationDegrees],
          ),
          opacity: const AeChannel.still([100]),
        ),
      ),
    ],
  );
}

/// One cut's canvas comp as it is laid: the cut, how long it runs, the cel
/// comp of each of its rows that has one, and the script's comps, which a
/// folder's comp joins.
class _CanvasLaying {
  _CanvasLaying({
    required this.cut,
    required this.frames,
    required this.banks,
    required this.comps,
  });

  final Cut cut;
  final int frames;
  final Map<LayerId, _Bank> banks;
  final List<AeComp> comps;

  final Map<LayerId, bool> _isolates = {};

  /// Whether [folder] is a picture of its own — the app composites it as
  /// one at any frame of the comp.
  bool _isolated(Layer folder) => _isolates.putIfAbsent(
    folder.id,
    () => Iterable<int>.generate(frames).any(
      (frame) => folderNeedsCompositeBuffer(
        cut: cut,
        folder: folder,
        frameIndex: frame,
      ),
    ),
  );

  /// The folders between [row] and the comp it is laid in, nearest first:
  /// the ones that pass it through, up to the first that does not — or to
  /// the top.
  List<Layer> _passedBy(Layer row) {
    final passed = <Layer>[];
    for (final folder in cut.layers.ancestryOf(row.folderId)) {
      if (_isolated(folder)) {
        break;
      }
      passed.add(folder);
    }
    return passed;
  }

  /// The folder whose comp [row] is laid in — its nearest ancestor that is
  /// a picture of its own — or null for the canvas comp.
  LayerId? _homeOf(Layer row) {
    for (final folder in cut.layers.ancestryOf(row.folderId)) {
      if (_isolated(folder)) {
        return folder.id;
      }
    }
    return null;
  }

  /// The layers of the comp [home] is — the canvas comp for null — bottom-up:
  /// the nulls of the folders that pass rows through first (AE moves them
  /// on top), then each row with cels here and each folder comp, where the
  /// cut stacks them.
  List<AeLayer> stack(LayerId? home) {
    final shown = <(Layer, AeLayer Function(Map<LayerId, AeLayer>))>[];
    for (final row in cut.layers) {
      if (_homeOf(row) != home) {
        continue;
      }
      if (row.kind.groupsLayers) {
        if (_isolated(row)) {
          final inner = stack(row.id);
          if (inner.isNotEmpty) {
            final comp = AeComp(
              name: row.name,
              width: cut.canvasSize.width,
              height: cut.canvasSize.height,
              frames: frames,
              tucked: true,
              layers: inner,
            );
            comps.add(comp);
            shown.add((row, (nulls) => _folderLayer(row, comp, nulls)));
          }
        }
        continue;
      }
      final bank = banks[row.id];
      if (bank != null) {
        final holds = _holdsOf(row, bank);
        if (holds != null) {
          shown.add((row, (nulls) => _celLayer(row, bank, holds, nulls)));
        }
      }
    }
    final nulls = <LayerId, AeLayer>{};
    final nullOrder = <AeLayer>[];
    for (final (row, _) in shown) {
      for (final folder in _passedBy(row).reversed) {
        if (!nulls.containsKey(folder.id)) {
          final made = _nullOf(folder, nulls);
          nulls[folder.id] = made;
          nullOrder.add(made);
        }
      }
    }
    return [
      ...nullOrder,
      for (final (_, lay) in shown) lay(nulls),
    ];
  }

  /// A folder that passes its rows through: a null carrying its transform.
  AeLayer _nullOf(Layer folder, Map<LayerId, AeLayer> nulls) => AeLayer(
    name: folder.name,
    source: const AeNullSource(),
    parent: nulls[folder.folderId],
    transform: _transformOf(folder, opacity: (_) => 1),
  );

  /// A folder that is a picture of its own: its comp, at its transform,
  /// strength and blend.
  AeLayer _folderLayer(
    Layer folder,
    AeComp comp,
    Map<LayerId, AeLayer> nulls,
  ) => AeLayer(
    name: folder.name,
    source: AeCompSource(comp),
    parent: nulls[folder.folderId],
    blend: folder.blendMode,
    enabled: cut.layers.rowVisible(folder),
    transform: _transformOf(
      folder,
      opacity: (frame) =>
          resolveFolderOpacityAt(folder: folder, frameIndex: frame) *
          _passedStrength(folder, frame),
    ),
  );

  /// A row's cels: its cel comp a frame at a time where [holds] says.
  AeLayer _celLayer(
    Layer row,
    _Bank bank,
    List<({int frame, int source})> holds,
    Map<LayerId, AeLayer> nulls,
  ) {
    final carrier = fxCarrierOf(row, cut.layers) ?? row;
    return AeLayer(
      name: row.name,
      source: AeCompSource(bank.comp),
      timeRemap: holds,
      parent: nulls[row.folderId],
      blend: row.blendMode,
      enabled: cut.layers.rowVisible(row),
      transform: _transformOf(
        carrier,
        opacity: (frame) =>
            (carrier.transformEnabled
                ? resolveOpacityTrackAt(carrier.transformTrack.opacity, frame)
                : 1.0) *
            _passedStrength(row, frame),
      ),
    );
  }

  /// The strength the folders passing [row] through lend it at [frame] —
  /// a null has none to give, so each row takes it on.
  double _passedStrength(Layer row, int frame) => _passedBy(row).fold(
    1.0,
    (strength, folder) =>
        strength * resolveFolderOpacityAt(folder: folder, frameIndex: frame),
  );

  /// [carrier]'s own transform over the comp, at [opacity] (0–1) a frame.
  AeTransform _transformOf(
    Layer carrier, {
    required double Function(int frame) opacity,
  }) {
    final canvas = cut.canvasSize;
    final samples = [
      for (var frame = 0; frame < frames; frame += 1)
        layerOwnPlacementAt(
          carrier: carrier,
          space: canvas,
          frameIndex: frame,
        ),
    ];
    return AeTransform(
      anchor: AeChannel.sampled(frames, (frame) {
        final anchor = samples[frame]?.anchorPoint;
        return [anchor?.x ?? canvas.width / 2, anchor?.y ?? canvas.height / 2];
      }),
      position: AeChannel.sampled(frames, (frame) {
        final center = samples[frame]?.pose.center;
        return [center?.x ?? canvas.width / 2, center?.y ?? canvas.height / 2];
      }),
      scale: AeChannel.sampled(frames, (frame) {
        final pose = samples[frame]?.pose;
        return [(pose?.scaleX ?? 1) * 100, (pose?.scaleY ?? 1) * 100];
      }),
      rotation: AeChannel.sampled(
        frames,
        (frame) => [samples[frame]?.pose.rotationDegrees ?? 0],
      ),
      opacity: AeChannel.sampled(
        frames,
        (frame) => [(opacity(frame) * 100).clamp(0.0, 100.0)],
      ),
    );
  }

  /// Where [row]'s blocks show which of its cels: a hold at every frame the
  /// shown cel changes, the cel comp's last, empty frame where none of its
  /// cels shows. Null when none ever shows in the comp.
  List<({int frame, int source})>? _holdsOf(Layer row, _Bank bank) {
    final blank = bank.comp.frames - 1;
    final holds = <({int frame, int source})>[];
    void hold(int frame, int source) {
      if (frame >= frames) {
        return;
      }
      if (holds.isNotEmpty && holds.last.frame == frame) {
        holds.removeLast();
      }
      if (holds.isEmpty || holds.last.source != source) {
        holds.add((frame: frame, source: source));
      }
    }

    hold(0, blank);
    for (final block in drawingBlocks(row.timeline)) {
      hold(block.startIndex, bank.frameOf[block.frameId] ?? blank);
      hold(block.endIndexExclusive, blank);
    }
    return holds.any((each) => each.source != blank) ? holds : null;
  }
}
