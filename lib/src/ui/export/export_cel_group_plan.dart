import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/export_overrides.dart';
import '../../models/export_spec.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/timeline_coverage.dart';
import '../../services/commands/link_mirror.dart' show linkedCutSiblings;
import '../envelope/cut_envelope_builder.dart' show cutEnvelopeInkOwner;
import 'export_cels_selection.dart';
import 'export_plan.dart';

/// The Cels unit: one BUNDLE (a base drawing layer and the parts riding
/// it) × one cel number → ONE composited file. A delivery cel is the stack,
/// not a per-layer piece.
///
/// v3 (유저 2026-09-09): the bundle's frame AXIS is the base layer — every
/// member contributes what it shows at the base cel — with one exception:
/// when a FREE attach row is the bundle's only picture, that row is the
/// axis (its own frames, its own name). 「여럿이면 기준을 따르고, 프리 부속
/// 단독이면 단독 기준」.
class ExportCelGroupTask {
  const ExportCelGroupTask({
    required this.cut,
    required this.baseLayer,
    required this.members,
    required this.memberFrames,
    required this.baseFrame,
    required this.celName,
    required this.fileName,
    this.skipped = false,
  });

  final Cut cut;

  /// The bundle's AXIS layer: the base whose frames number the cels — or
  /// the lone free attach row (see the class doc). Its name is the label
  /// on the file.
  final Layer baseLayer;

  /// The user unticked this bundle in the cel list: planned and previewable,
  /// but not written ([ExportCelGroupPlan.writtenCels]). Kept in the plan
  /// rather than dropped so the list can still show the bundle with its
  /// dot off — a dropped bundle would be 「없다가 생기는 UI」 in reverse.
  final bool skipped;

  /// The stack slice this cel composites, bottom-up in cut order: the
  /// selected pictures of the bundle plus the applied paper rows.
  final List<Layer> members;

  /// The member cel per [members] index; null = that member has nothing
  /// for this cel (a dangling link, a row exposing nothing there).
  final List<Frame?> memberFrames;

  /// The axis frame this cel is numbered by.
  final Frame baseFrame;

  /// The printed cel number — [Frame.celNumber] of [baseFrame]. An axis
  /// frame without one is the in-between mark and never becomes a task.
  final String celName;

  /// Relative to the export directory; may contain `/` subfolders.
  final String fileName;
}

/// One instruction-layer event exporting as an image cel (지시 출력).
class ExportInstructionTask {
  const ExportInstructionTask({
    required this.cut,
    required this.layer,
    required this.startFrame,
    required this.length,
    required this.label,
    required this.fileName,
  });

  final Cut cut;
  final Layer layer;
  final int startFrame;
  final int length;
  final String label;
  final String fileName;
}

/// One bundle as the dialog's cel list shows it: the axis layer and its
/// sheets in frame order.
typedef ExportCelBundle = ({Layer axis, List<ExportCelGroupTask> sheets});

/// The preview cache key for [task]: everything its picture depends on.
///
/// ⛔Not the file name alone. 「원화 上がり」 and 「LO」 both name their cel
/// on base A `A1.png`, and a key of the name handed the first label's
/// picture back for the second (유저 2026-09-09: 「LO로 고르고 나니까
/// 미리보기화면이 갱신안되서 여전히 작감수정그림있던데」). The members and
/// the frame each contributes ARE the picture, so they are the key — with
/// the size, the background and the FX switch the renderer reads.
String celGroupPreviewKey(
  ExportCelGroupTask task, {
  required String sizeMode,
  required int backgroundKey,
  required bool applyLayerFx,
}) {
  final members = [
    for (var i = 0; i < task.members.length; i += 1)
      '${task.members[i].id.value}='
          '${task.memberFrames[i]?.id.value ?? '-'}',
  ].join(',');
  return 'celgroup:${task.cut.id.value}:${task.baseLayer.id.value}:'
      '${task.baseFrame.id.value}:$members:$sizeMode:$backgroundKey:'
      '${applyLayerFx ? 'fx' : 'raw'}';
}

class ExportCelGroupPlan {
  const ExportCelGroupPlan({required this.cels, required this.instructions});

  /// Every planned cel, ticked or not — what the dialog lists and previews.
  final List<ExportCelGroupTask> cels;
  final List<ExportInstructionTask> instructions;

  /// The cels that will be written: the ticked ones.
  List<ExportCelGroupTask> get writtenCels => [
    for (final task in cels)
      if (!task.skipped) task,
  ];

  /// How many files the export writes.
  int get length => writtenCels.length + instructions.length;

  /// [cels] grouped by axis layer, in first-appearance (stack) order.
  List<ExportCelBundle> get bundles {
    final byAxis = <LayerId, List<ExportCelGroupTask>>{};
    final axes = <LayerId, Layer>{};
    for (final task in cels) {
      byAxis.putIfAbsent(task.baseLayer.id, () => []).add(task);
      axes[task.baseLayer.id] = task.baseLayer;
    }
    return [
      for (final entry in byAxis.entries)
        (axis: axes[entry.key]!, sheets: entry.value),
    ];
  }
}

/// The frame [member] contributes to the cel numbered by [baseFrame] of
/// the axis layer [base]:
/// - the axis itself is the frame;
/// - a SYNCED attach row riding the axis follows its cell link (axis frame
///   id → own id);
/// - anything else — a FREE attach row, an applied paper row — has no link,
///   so the honest correspondence is whatever it EXPOSES where the axis cel
///   first shows (what you see when that cel is up). 유저 2026-09-09: 「1이랑
///   2에는 프리 부속 레이어의 같은 그림이 적용되있도록」.
Frame? celGroupMemberFrame({
  required Layer base,
  required Layer member,
  required Frame baseFrame,
}) {
  if (identical(member, base) || member.id == base.id) {
    return baseFrame;
  }
  Frame? byId(Layer layer, FrameId? id) {
    if (id == null) {
      return null;
    }
    return layer.frameById(id);
  }

  if (isSyncedAttachedLayer(member) && member.attachedToLayerId == base.id) {
    return byId(member, member.baseFrameLinks[baseFrame.id]);
  }
  var firstExposure = -1;
  for (final block in drawingBlocks(base.timeline)) {
    if (block.frameId == baseFrame.id) {
      firstExposure = block.startIndex;
      break;
    }
  }
  if (firstExposure < 0) {
    // The axis cel never shows on the timeline — an unlinked row has no
    // defined counterpart for it.
    return null;
  }
  return byId(member, exposedFrameIdAt(member.timeline, firstExposure));
}

/// One task per numbered cel of every bundle the selection touches.
///
/// A bundle exists for every base whose stack holds a selected picture —
/// the base itself, or an attach row riding it (부속 preset: the base is
/// OFF and its parts are ON). A cel is planned only where some picture
/// member has a frame: 「그림이 존재하는 영역만 출력」 — paper alone is not a
/// picture. Bundles the user unticked in the cel list ([skipped]) are
/// planned but marked, so the list keeps showing them.
Iterable<ExportCelGroupTask> _celGroupTasksFor(
  Cut cut, {
  required ExportCelsSelection selection,
  required _NamingRun run,
  required String cutName,
  required Set<LayerId> skipped,
}) sync* {
  final selectedIds = {for (final layer in selection.celLayers) layer.id};
  final paperIds = {for (final layer in selection.paperLayers) layer.id};
  for (final base in cut.layers) {
    if (isAttachedLayer(base) ||
        !base.kind.exportsCels ||
        base.kind == LayerKind.instruction) {
      continue;
    }
    final riderIds = {
      for (final rider in attachedLayersOf(base.id, cut.layers)) rider.id,
    };
    final pictures = [
      for (final layer in cut.layers)
        if ((layer.id == base.id || riderIds.contains(layer.id)) &&
            selectedIds.contains(layer.id))
          layer,
    ];
    if (pictures.isEmpty) {
      continue;
    }
    final lone = pictures.length == 1 ? pictures.single : null;
    final axis = lone != null && isAttachedLayer(lone) && !isSyncedAttachedLayer(lone)
        ? lone
        : base;
    final pictureIds = {for (final layer in pictures) layer.id};
    final members = [
      for (final layer in cut.layers)
        if (pictureIds.contains(layer.id) || paperIds.contains(layer.id)) layer,
    ];
    for (final axisFrame in axis.frames) {
      // An unnamed drawing is the in-between mark, not a cel: no file. The
      // sheet prints ○ for the very same frame ([Frame.celNumber] decides
      // for both); numbering it by position here invented a cel the sheet
      // never listed (유저 2026-09-09).
      final celName = axisFrame.celNumber;
      if (celName == null) {
        continue;
      }
      final frames = [
        for (final member in members)
          celGroupMemberFrame(base: axis, member: member, baseFrame: axisFrame),
      ];
      var hasPicture = false;
      for (var i = 0; i < members.length; i += 1) {
        if (pictureIds.contains(members[i].id) && frames[i] != null) {
          hasPicture = true;
          break;
        }
      }
      if (!hasPicture) {
        continue;
      }
      yield ExportCelGroupTask(
        cut: cut,
        baseLayer: axis,
        members: members,
        memberFrames: frames,
        baseFrame: axisFrame,
        celName: celName,
        fileName: run.fileNameFor(
          cutName: cutName,
          labelName: axis.name,
          celName: celName,
        ),
        skipped: skipped.contains(axis.id),
      );
    }
  }
}

/// One export RUN's naming: the shared [ExportCelFileNamer] plus the two
/// things a label's base name is derived from. A record rather than a
/// class of its own — the uniqueness law lives in the namer, and this is
/// only what the group planner has to carry alongside it.
typedef _NamingRun = ({
  Project project,
  CelsExportSpec spec,
  ExportCelFileNamer namer,
});

extension _NamingRunFiles on _NamingRun {
  String fileNameFor({
    required String cutName,
    required String labelName,
    required String celName,
  }) => namer.uniqueFileName(
    projectName: project.name,
    cutName: cutName,
    layerName: labelName,
    base: celGroupFileBase(
      projectName: project.name,
      cutName: cutName,
      labelName: labelName,
      celName: celName,
      naming: spec.naming,
    ),
  );
}

/// One task per EVENT on every instruction row in [selection]. The cel
/// name is the event's position in its row, counted from one.
Iterable<ExportInstructionTask> _instructionTasksFor(
  Cut cut, {
  required ExportCelsSelection selection,
  required _NamingRun run,
  required String cutName,
}) sync* {
  for (final layer in selection.instructionLayers) {
    var eventIndex = 0;
    for (final entry in layer.instructions.entries) {
      eventIndex += 1;
      final def = run.project.cameraInstructions.defById(
        entry.value.instructionId,
      );
      yield ExportInstructionTask(
        cut: cut,
        layer: layer,
        startFrame: entry.key,
        length: entry.value.length,
        label: entry.value.displayLabel(def),
        fileName: run.fileNameFor(
          cutName: cutName,
          labelName: layer.name,
          celName: '$eventIndex',
        ),
      );
    }
  }
}

/// The cut's name on files and folders.
///
/// 겸용 cuts are ONE cut to the export (유저 2026-09-09: 「겸용컷은 하나라는
/// 느낌이야 … 겸용컷 비포함이란게 불가능하도록」): the whole link group's
/// names join with '-' in track order — `C012-015` — and the group exports
/// once, from its owner cut (the envelope's rule, [cutEnvelopeInkOwner]).
String celGroupCutName(Project project, Cut cut) {
  final siblings = {cut.id, ...linkedCutSiblings(project, cutId: cut.id)};
  if (siblings.length == 1) {
    return cut.name;
  }
  return [
    for (final track in project.tracks)
      for (final candidate in track.cuts)
        if (siblings.contains(candidate.id)) candidate.name,
  ].join('-');
}

/// Builds the bundle cel plan for the Cels tab: rules → delta per cut (the
/// resolver), one bundle per base whose stack holds a selected picture, one
/// task per numbered axis cel that has a picture. Instruction layers become
/// per-event tasks. Under the project scope a 겸용 group is walked once,
/// from its owner cut.
ExportCelGroupPlan buildExportCelGroupPlan({
  required Project project,
  required CutId activeCutId,
  required CelsExportSpec spec,
  ExportProjectOverrides? overrides,
  String fileExtension = 'png',
}) {
  final run = (
    project: project,
    spec: spec,
    namer: ExportCelFileNamer(
      naming: spec.naming,
      fileExtension: fileExtension,
    ),
  );
  final projectScope = spec.scope == ExportScopeKind.project;
  final cels = <ExportCelGroupTask>[];
  final instructions = <ExportInstructionTask>[];
  for (final cut in resolveExportCuts(
    project: project,
    activeCutId: activeCutId,
    range: projectScope ? ExportRange.allCuts : ExportRange.activeCut,
  )) {
    if (projectScope &&
        (cutEnvelopeInkOwner(project, cut.id) != cut.id ||
            (overrides != null && !overrides.cutIncluded(cut.id)))) {
      continue;
    }
    final delta = overrides?.deltaFor(cut.id);
    final selection = resolveExportCelsSelection(
      cut: cut,
      spec: spec,
      delta: delta,
    );
    final cutName = celGroupCutName(project, cut);
    cels.addAll(
      _celGroupTasksFor(
        cut,
        selection: selection,
        run: run,
        cutName: cutName,
        skipped: delta?.skippedBases ?? const {},
      ),
    );
    instructions.addAll(
      _instructionTasksFor(
        cut,
        selection: selection,
        run: run,
        cutName: cutName,
      ),
    );
  }
  return ExportCelGroupPlan(cels: cels, instructions: instructions);
}

/// `[proj_][cut_]<label><cel>[suffix]` — the bundle reading of the CSP
/// naming options ([ExportCelNaming.includeLayerName] switches the LABEL
/// text, the number always prints).
String celGroupFileBase({
  required String projectName,
  required String cutName,
  required String labelName,
  required String celName,
  required ExportCelNaming naming,
}) {
  final joined = StringBuffer();
  if (naming.includeProjectName) {
    joined.write('${sanitizeExportFileComponent(projectName)}_');
  }
  if (naming.includeCutName) {
    joined.write('${sanitizeExportFileComponent(cutName)}_');
  }
  if (naming.includeLayerName) {
    joined.write(sanitizeExportFileComponent(labelName));
  }
  joined.write(padFrameNumber(celName, naming.frameDigits));
  if (naming.suffix.isNotEmpty) {
    joined.write(naming.suffix);
  }
  return joined.toString();
}
