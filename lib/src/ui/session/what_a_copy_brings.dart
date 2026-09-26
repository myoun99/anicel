import '../../models/camera_instruction.dart';
import '../../models/exposure_instruction.dart';
import '../../models/media_asset.dart';
import '../../models/project.dart';
import '../../models/timeline_exposure.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/persistence/media_staging_store.dart';
import 'session_roles.dart';

/// 🚨I-7 — WHAT A COPY NAMES in the project it came from, besides its own
/// ids: the pool entries of the media it plays or shows (an SE block's
/// sound, a reference row's movie), the instruction terms its blocks and
/// spans spell — and where that project keeps those media's bytes.
///
/// A paste at home needs none of it: the project already holds them. A
/// paste into ANOTHER project (유저 2026-09-26: 「탭사이에 복사나 붙여넣기
/// 뭐든 가능」) brings them — or the pasted row names a medium the pool does
/// not list, and a term that sheet cannot print or, worse, prints as another
/// word: custom terms are numbered per project (`custom-1`, …), so one id in
/// two vocabularies can be two different terms.
///
/// Read at the COPY ([namesOfACopy]), for the board's reason (F-161): the
/// paste may come after the source was edited, or closed.
class CopiedNames {
  const CopiedNames({
    this.assets = const {},
    this.terms = const {},
    this.bytesOf = MediaFileBytes.new,
  });

  /// The pool entries of the media the copy names, by pool path.
  final Map<String, MediaAsset> assets;

  /// The terms the copy spells, by id — as the source spells them.
  final Map<String, CameraInstructionDef> terms;

  /// Where the source keeps a medium's bytes NOW
  /// (`ProjectFile.mediaByteSourceFor`), asked when a paste carries it.
  final MediaByteSource Function(String poolPath) bytesOf;
}

/// The names a copy of [media] (pool paths) and [terms] (term ids) makes in
/// [project], whose bytes [bytesOf] finds.
CopiedNames namesOfACopy({
  required Project project,
  required Iterable<String> media,
  required Iterable<String> terms,
  required MediaByteSource Function(String poolPath) bytesOf,
}) {
  final pool = {for (final asset in project.mediaAssets) asset.path: asset};
  final vocabulary = project.cameraInstructions;
  return CopiedNames(
    assets: {for (final path in media) path: ?pool[path]},
    terms: {for (final id in terms) id: ?vocabulary.defById(id)},
    bytesOf: bytesOf,
  );
}

/// The term ids [exposures] and [spans] spell.
Set<String> termsSpelledBy(
  Iterable<TimelineExposure> exposures, [
  Iterable<InstructionEvent> spans = const [],
]) => {
  for (final exposure in exposures)
    if (exposure.instruction case final instruction?)
      instruction.instructionId,
  for (final span in spans) span.instructionId,
};

/// What a paste of a copy lands WITH in a project: the pool entries it
/// records, the vocabulary it leaves (null when it needs no word the
/// project lacks), and how the copy's term ids are spelled there.
typedef Arrival = ({
  List<MediaAsset> assets,
  CameraInstructionSet? vocabulary,
  Map<String, String> respell,
});

/// The [Arrival] of [names] in [project].
///
/// A medium the pool already lists stays the pool's (the landings' law —
/// its bytes are the ones this project keeps). A referenced one arrives as
/// it is. A CARRIED one arrives only as [held] brought it — a carry of this
/// project's own, its bytes already staged ([holdCarriedMediaOf]); without
/// that it is not recorded, because a pool entry that says 「carried」 is
/// the promise that the project holds the bytes.
///
/// A term the vocabulary lacks is added. One it has under the same id is
/// the same term when the id is a STANDARD one — the id is the term, the
/// name only its label (「never renamed」) — and, for a custom id, when it
/// reads the same; a custom id that reads otherwise here is another term,
/// added under a free `custom-<n>` and respelled on the way in.
Arrival arrivalOf(
  CopiedNames names,
  Project project, {
  List<MediaAsset> held = const [],
}) {
  final known = {for (final asset in project.mediaAssets) asset.path};
  final heldByPath = {for (final asset in held) asset.path: asset};
  final assets = <MediaAsset>[
    for (final asset in names.assets.values)
      if (!known.contains(asset.path))
        if (!asset.carried) asset else ?heldByPath[asset.path],
  ];
  var vocabulary = project.cameraInstructions;
  var grew = false;
  final respell = <String, String>{};
  for (final term in names.terms.values) {
    final mine = vocabulary.defById(term.id);
    if (mine != null && _sameTerm(mine, term)) {
      continue;
    }
    final id = mine == null ? term.id : vocabulary.freeCustomId();
    vocabulary = CameraInstructionSet(
      defs: [...vocabulary.defs, _spelledAs(term, id)],
    );
    grew = true;
    if (id != term.id) {
      respell[term.id] = id;
    }
  }
  return (
    assets: assets,
    vocabulary: grew ? vocabulary : null,
    respell: respell,
  );
}

final Set<String> _standardTermIds = {
  for (final term in CameraInstructionSet.standard.defs) term.id,
};

bool _sameTerm(CameraInstructionDef mine, CameraInstructionDef theirs) =>
    _standardTermIds.contains(theirs.id) ||
    (mine.name == theirs.name &&
        mine.iconKey == theirs.iconKey &&
        mine.colorValue == theirs.colorValue &&
        mine.markType == theirs.markType);

CameraInstructionDef _spelledAs(CameraInstructionDef term, String id) =>
    CameraInstructionDef(
      id: id,
      name: term.name,
      iconKey: term.iconKey,
      colorValue: term.colorValue,
      markType: term.markType,
    );

/// ONE DOOR for the bytes a paste from another project carries: each
/// carried medium the copy names that [project]'s pool lacks becomes a carry
/// of THIS project's own — minted here, 「one that arrives is new by
/// definition」 — staged from where the source keeps it now. Answers the
/// pool entries whose bytes came; a medium that would not read is left out
/// ([arrivalOf] then records nothing for it).
///
/// Before the paste records anything, as every door that records a carry
/// holds its bytes first ([MediaStagingStore.stageCarriedBytes]'s law).
Future<List<MediaAsset>> holdCarriedMediaOf(
  CopiedNames names,
  Project project,
  MediaStagingStore staging,
) async {
  final known = {for (final asset in project.mediaAssets) asset.path};
  final arriving = [
    for (final asset in names.assets.values)
      if (asset.carried && !known.contains(asset.path))
        asset.copyWith(carriedAs: mintMediaCarry(asset.path)),
  ];
  if (arriving.isEmpty) {
    return const [];
  }
  final staged = await staging.stageCarriedBytesFrom({
    for (final asset in arriving) asset.carry!: names.bytesOf(asset.path),
  });
  final came = {for (final one in staged) one.carry};
  return [
    for (final asset in arriving)
      if (came.contains(asset.carry)) asset,
  ];
}

/// What a wait held for the next paste of ONE copy: the carried media it
/// staged as this project's own ([holdCarriedMediaOf]). A board's next copy
/// makes it stale — it answers for the copy it was held for, and nothing
/// else.
///
/// One per board per project: the frame board's and the layer board's
/// pastes both hold and land through it.
class HeldArrival {
  Object? _copy;
  List<MediaAsset> _media = const [];

  /// What was held for [copy] — nothing, for any other.
  List<MediaAsset> forCopy(Object copy) =>
      identical(_copy, copy) ? _media : const [];

  /// Whether a paste of [copy] into [project] has carried media to hold
  /// first — what the UI puts its wait window up for (F-53).
  bool mustHold(Object copy, CopiedNames names, Project project) {
    if (identical(_copy, copy)) {
      return false;
    }
    final known = {for (final asset in project.mediaAssets) asset.path};
    return names.assets.values.any(
      (asset) => asset.carried && !known.contains(asset.path),
    );
  }

  /// Holds them, for the next paste of [copy].
  Future<void> hold(
    Object copy,
    CopiedNames names,
    Project project,
    MediaStagingStore staging,
  ) async {
    final media = await holdCarriedMediaOf(names, project, staging);
    _copy = copy;
    _media = media;
  }
}

/// Records [arrival] in [project] — its pool entries, its vocabulary — as
/// commands of the step the paste runs in, so one undo takes the paste and
/// what it brought.
void landArrival(ProjectAccess project, Arrival arrival) {
  if (arrival.assets.isNotEmpty) {
    project.cutCommandCoordinator.updateMediaAssets([
      ...project.repository.requireProject().mediaAssets,
      ...arrival.assets,
    ], description: 'Paste media');
  }
  if (arrival.vocabulary case final vocabulary?) {
    project.cutCommandCoordinator.updateCameraInstructionSet(vocabulary);
  }
}

/// [exposure], its instruction spelled as [respell] says.
TimelineExposure respelledExposure(
  TimelineExposure exposure,
  Map<String, String> respell,
) {
  final instruction = exposure.instruction;
  final id = instruction == null ? null : respell[instruction.instructionId];
  if (instruction == null || id == null) {
    return exposure;
  }
  return exposure.copyWith(
    instruction: () => ExposureInstruction(
      instructionId: id,
      text: instruction.text,
      valueA: instruction.valueA,
      valueB: instruction.valueB,
      memo: instruction.memo,
    ),
  );
}

/// [span], spelled as [respell] says.
InstructionEvent respelledSpan(
  InstructionEvent span,
  Map<String, String> respell,
) => switch (respell[span.instructionId]) {
  final id? => span.copyWith(instructionId: id),
  null => span,
};
