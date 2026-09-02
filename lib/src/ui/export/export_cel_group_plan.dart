import '../../models/attached_layer_resolve.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/export_overrides.dart';
import '../../models/export_spec.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
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

  /// The printed cel number (`Frame.name`, 1-based position fallback).
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
  final cuts = resolveExportCuts(
    project: project,
    activeCutId: activeCutId,
    range: spec.scope == ExportScopeKind.project
        ? ExportRange.allCuts
        : ExportRange.activeCut,
  );
  final cels = <ExportCelGroupTask>[];
  final instructions = <ExportInstructionTask>[];
  final usedNames = <String>{};

  String uniqueName(String prefix, String base) {
    var fileName = '$prefix$base.$fileExtension';
    var bump = 2;
    while (!usedNames.add(fileName)) {
      fileName = '$prefix${base}_$bump.$fileExtension';
      bump += 1;
    }
    return fileName;
  }

  for (final cut in cuts) {
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
    final includedIds = {
      for (final layer in selection.celLayers) layer.id,
    };

    for (final base in selection.celLayers) {
      if (isAttachedLayer(base)) {
        continue; // members ride their base's label below
      }
      final attached = attachedLayersOf(base.id, cut.layers);
      final members = <Layer>[];
      var baseInserted = false;
      // Cut order = [below…, base, above…]; walk the cut list so the
      // stack order survives filtering.
      for (final layer in cut.layers) {
        final isBase = layer.id == base.id;
        final isMember =
            attached.any((candidate) => candidate.id == layer.id) &&
            includedIds.contains(layer.id);
        if (isBase) {
          members.add(layer);
          baseInserted = true;
        } else if (isMember) {
          members.add(layer);
        }
      }
      if (!baseInserted) {
        continue;
      }
      for (var index = 0; index < base.frames.length; index += 1) {
        final baseFrame = base.frames[index];
        final celName = baseFrame.name ?? '${index + 1}';
        final fileBase = celGroupFileBase(
          projectName: project.name,
          cut: cut,
          labelName: base.name,
          celName: celName,
          naming: spec.naming,
        );
        final folder = [
          if (spec.naming.cutFolder) sanitizeExportFileComponent(cut.name),
          if (spec.naming.layerFolder) sanitizeExportFileComponent(base.name),
        ].join('/');
        final prefix = folder.isEmpty ? '' : '$folder/';
        cels.add(
          ExportCelGroupTask(
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
            fileName: uniqueName(prefix, fileBase),
          ),
        );
      }
    }

    for (final layer in selection.instructionLayers) {
      var eventIndex = 0;
      for (final entry in layer.instructions.entries) {
        eventIndex += 1;
        final def =
            project.cameraInstructions.defById(entry.value.instructionId);
        final label = entry.value.displayLabel(def);
        final fileBase = celGroupFileBase(
          projectName: project.name,
          cut: cut,
          labelName: layer.name,
          celName: '$eventIndex',
          naming: spec.naming,
        );
        final folder = [
          if (spec.naming.cutFolder) sanitizeExportFileComponent(cut.name),
          if (spec.naming.layerFolder)
            sanitizeExportFileComponent(layer.name),
        ].join('/');
        final prefix = folder.isEmpty ? '' : '$folder/';
        instructions.add(
          ExportInstructionTask(
            cut: cut,
            layer: layer,
            startFrame: entry.key,
            length: entry.value.length,
            label: label,
            fileName: uniqueName(prefix, fileBase),
          ),
        );
      }
    }
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
