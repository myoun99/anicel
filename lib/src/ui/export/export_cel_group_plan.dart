import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/export_overrides.dart';
import '../../models/export_spec.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/timeline_coverage.dart';
import 'export_cels_selection.dart';
import 'export_plan.dart';

/// The v10 Cels unit: one LABEL (a base drawing layer) × one cel number →
/// ONE composited file of the label's gated members (기준+어태치). The
/// old per-layer listing exported pieces; a delivery cel is the stack.
class ExportCelGroupTask {
  const ExportCelGroupTask({
    required this.cut,
    required this.baseLayer,
    required this.members,
    required this.memberFrames,
    required this.baseFrame,
    required this.celName,
    required this.fileName,
  });

  final Cut cut;

  /// The label owner (the un-attached drawing layer whose name IS the
  /// label — A, B, C…).
  final Layer baseLayer;

  /// The stack slice this cel composites, bottom-up in cut order
  /// (below-attach…, base, above-attach…), members the rules/delta kept.
  final List<Layer> members;

  /// The member cel per [members] index; null = that member has nothing
  /// for this cel (a dangling link, a free row exposing nothing there).
  final List<Frame?> memberFrames;

  final Frame baseFrame;

  /// The printed cel number — [Frame.celNumber] of [baseFrame]. A base
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

class ExportCelGroupPlan {
  const ExportCelGroupPlan({required this.cels, required this.instructions});

  final List<ExportCelGroupTask> cels;
  final List<ExportInstructionTask> instructions;

  int get length => cels.length + instructions.length;
}

/// The frame [member] contributes to [baseFrame]'s cel:
/// - a SYNCED attach row follows its cell link (base frame id → own id);
/// - a FREE row has no link — the honest correspondence is whatever it
///   EXPOSES where the base cel first shows (what you see when that cel
///   is up);
/// - the base itself is the frame.
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

  if (isSyncedAttachedLayer(member)) {
    return byId(member, member.baseFrameLinks[baseFrame.id]);
  }
  // Free row: look up what it exposes at the base cel's first exposure.
  var firstExposure = -1;
  for (final block in drawingBlocks(base.timeline)) {
    if (block.frameId == baseFrame.id) {
      firstExposure = block.startIndex;
      break;
    }
  }
  if (firstExposure < 0) {
    // The base cel never shows on the timeline — a free row has no
    // defined counterpart for it.
    return null;
  }
  return byId(member, exposedFrameIdAt(member.timeline, firstExposure));
}

/// The layers that ride [base]'s label, in CUT order — [below…, base,
/// above…] — so the stack order survives the selection's filtering.
///
/// Null when the base is not in the cut's layer list at all: there is
/// then nothing to draw, and a group without its base is not a group.
List<Layer>? _celGroupMembers(
  Layer base, {
  required Cut cut,
  required Set<LayerId> includedIds,
}) {
  final attached = attachedLayersOf(base.id, cut.layers);
  final members = <Layer>[];
  var baseInserted = false;
  for (final layer in cut.layers) {
    if (layer.id == base.id) {
      members.add(layer);
      baseInserted = true;
    } else if (attached.any((candidate) => candidate.id == layer.id) &&
        includedIds.contains(layer.id)) {
      members.add(layer);
    }
  }
  // ⛔UNREACHABLE from the one caller — `resolveExportCelsSelection`
  // draws every cel layer out of `cut.layers`, so the base is always in
  // there. Kept because the guard is the only thing saying so: a members
  // list without its base composites the attachments alone, which is
  // pixels the user never drew. A mutant that removes it survives, and
  // that is the honest state (2026-09-05).
  return baseInserted ? members : null;
}

/// One task per authored cel of every label in [selection].
Iterable<ExportCelGroupTask> _celGroupTasksFor(
  Cut cut, {
  required ExportCelsSelection selection,
  required _NamingRun run,
}) sync* {
  final includedIds = {for (final layer in selection.celLayers) layer.id};
  for (final base in selection.celLayers) {
    if (isAttachedLayer(base)) {
      continue; // members ride their base's label below
    }
    final members = _celGroupMembers(base, cut: cut, includedIds: includedIds);
    if (members == null) {
      continue;
    }
    for (final baseFrame in base.frames) {
      // An unnamed drawing is the in-between mark, not a cel: no file. The
      // sheet prints ○ for the very same frame ([Frame.celNumber] decides
      // for both); numbering it by position here invented a cel the sheet
      // never listed (유저 2026-09-09).
      final celName = baseFrame.celNumber;
      if (celName == null) {
        continue;
      }
      yield ExportCelGroupTask(
        cut: cut,
        baseLayer: base,
        members: members,
        memberFrames: [
          for (final member in members)
            celGroupMemberFrame(
              base: base,
              member: member,
              baseFrame: baseFrame,
            ),
        ],
        baseFrame: baseFrame,
        celName: celName,
        fileName: run.fileNameFor(
          cut: cut,
          labelName: base.name,
          celName: celName,
        ),
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
    required Cut cut,
    required String labelName,
    required String celName,
  }) => namer.uniqueFileName(
    cut: cut,
    layerName: labelName,
    base: celGroupFileBase(
      projectName: project.name,
      cut: cut,
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
          cut: cut,
          labelName: layer.name,
          celName: '$eventIndex',
        ),
      );
    }
  }
}

/// Builds the label-group cel plan for the Cels tab (EX5): rules → delta
/// per cut (the EX1 resolver), labels = included un-attached drawing
/// rows, members = the included attach rows around each base, one task
/// per authored base cel. Instruction layers become per-event tasks.
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
  final cels = <ExportCelGroupTask>[];
  final instructions = <ExportInstructionTask>[];
  for (final cut in resolveExportCuts(
    project: project,
    activeCutId: activeCutId,
    range: spec.scope == ExportScopeKind.project
        ? ExportRange.allCuts
        : ExportRange.activeCut,
  )) {
    if (overrides != null &&
        spec.scope == ExportScopeKind.project &&
        !overrides.cutIncluded(cut.id)) {
      continue;
    }
    final selection = resolveExportCelsSelection(
      cut: cut,
      spec: spec,
      delta: overrides?.deltaFor(cut.id),
    );
    cels.addAll(_celGroupTasksFor(cut, selection: selection, run: run));
    instructions.addAll(
      _instructionTasksFor(cut, selection: selection, run: run),
    );
  }
  return ExportCelGroupPlan(cels: cels, instructions: instructions);
}

/// `[proj_][cut_]<label><cel>[suffix]` — the label-group reading of the
/// CSP naming options ([ExportCelNaming.includeLayerName] switches the
/// LABEL text, the number always prints).
String celGroupFileBase({
  required String projectName,
  required Cut cut,
  required String labelName,
  required String celName,
  required ExportCelNaming naming,
}) {
  final joined = StringBuffer();
  if (naming.includeProjectName) {
    joined.write('${sanitizeExportFileComponent(projectName)}_');
  }
  if (naming.includeCutName) {
    joined.write('${sanitizeExportFileComponent(cut.name)}_');
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
