import 'package:collection/collection.dart'
    show IterableExtension, compareAsciiLowerCaseNatural;

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
import '../../services/commands/link_mirror.dart'
    show linkCounterpartIn, linkedCutGroupInTrackOrder;
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
    this.listedUnder,
  });

  /// The cut this cel is COMPOSITED in — the one that SHOWS it: its rows
  /// are the [members], its timeline says what each of them contributes,
  /// and its camera and effects are sampled where the cel first shows
  /// there ([celGroupFirstExposure]).
  ///
  /// 🚨F-300 (유저 2026-10-05): in a 겸용 group that is not always the cut
  /// the export window stands on. The cel bank is the GROUP's, so the
  /// window's cut holds cels only a sibling shows; laid from the window's
  /// cut alone, such a cel had no place on the timeline — no paper under
  /// it, a camera and effects read at frame 0 — and which cels those were
  /// changed with the cut that happened to be open (「현재 컷에 BG1이면 용지
  /// 적용되고 현재컷이아닌 BG2쪽은 용지가 빠짐 … 렌더에 현재컷 관련 로직
  /// 있는건 이상하니 근본/구조적으로 해결」).
  final Cut cut;

  /// The bundle's AXIS layer, in [cut]: the base whose frames number the
  /// cels — or the lone free attach row (see the class doc). Its name is
  /// the label on the file.
  final Layer baseLayer;

  /// Where the export WINDOW lists this cel, when that is another cut than
  /// the one it is composited in — a 겸용 group's cel shown by a sibling
  /// (F-300): the cut the plan was laid from and the bundle's axis there.
  /// Null where [cut] and [baseLayer] are those themselves.
  ///
  /// The window thinks in the cut it stands on (유저: 「출력창은 현재컷을
  /// 기준으로 생각하긴한다만」) — its list is one cut's rows, a tick answers
  /// for a row of that cut — and the PICTURE does not: two answers to two
  /// questions, so the task carries both.
  final ({Cut cut, Layer axis})? listedUnder;

  /// The cut the window lists this cel in ([listedUnder]).
  Cut get listedCut => listedUnder?.cut ?? cut;

  /// The row the window lists this cel under, and the one a tick on the
  /// bundle answers for ([listedUnder]).
  Layer get bundleAxis => listedUnder?.axis ?? baseLayer;

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
  /// frame without one is the in-between mark and never becomes a task —
  /// but on a row whose unnamed cel is the layer's own picture it is one,
  /// and this is empty ([_fileCelName]).
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
      byAxis.putIfAbsent(task.bundleAxis.id, () => []).add(task);
      axes[task.bundleAxis.id] = task.bundleAxis;
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
  final firstExposure = firstExposureOf(base, baseFrame.id);
  if (firstExposure == null) {
    // The axis cel never shows on the timeline — an unlinked row has no
    // defined counterpart for it.
    return null;
  }
  return byId(member, exposedFrameIdAt(member.timeline, firstExposure));
}

/// The frame of its cut [frameId] FIRST shows on [axis]'s timeline, or null
/// when it never does. A cel has no time of its own: where it first shows
/// is the honest frame, for what a row with no link to it contributes
/// ([celGroupMemberFrame]) and for the camera and the effects its picture
/// is sampled at ([celGroupFirstExposure]).
///
/// ↩️The planner and the renderer each walked the blocks for themselves.
int? firstExposureOf(Layer axis, FrameId frameId) {
  for (final block in drawingBlocks(axis.timeline)) {
    if (block.frameId == frameId) {
      return block.startIndex;
    }
  }
  return null;
}

/// The frame of [task]'s cut its cel is sampled at: where the cel first
/// shows there — the cut's first frame for a cel no cut shows.
int celGroupFirstExposure(ExportCelGroupTask task) =>
    firstExposureOf(task.baseLayer, task.baseFrame.id) ?? 0;

/// One cut as this export run sees it: the cut itself, the name its files
/// carry (a 겸용 group's joined name), the run's namer and the bundles the
/// user unticked. They travel together because every step of the walk needs
/// all four.
typedef _CutRun = ({
  Cut cut,
  String cutName,
  _NamingRun run,
  Set<LayerId> skipped,
});

/// One task per numbered cel of every bundle the selection touches.
///
/// A bundle exists for every base whose stack holds a selected picture —
/// the base itself, or an attach row riding it (어태치 preset: the base is
/// OFF and its parts are ON). A cel is planned only where some picture
/// member has a frame: 「그림이 존재하는 영역만 출력」 — paper alone is not a
/// picture. Bundles the user unticked in the cel list ([skipped]) are
/// planned but marked, so the list keeps showing them.
Iterable<ExportCelGroupTask> _celGroupTasksFor(
  _CutRun cut,
  ExportCelsSelection selection,
) sync* {
  final unnamedFiled = <String>{};
  for (final bundle in _celBundlesOf(cut.cut, selection)) {
    yield* _bundleTasks(bundle, cut, unnamedFiled: unnamedFiled);
  }
}

/// One bundle before its cels are counted: the layer whose frames number
/// them, the stack slice each cel composites (pictures + applied paper,
/// bottom-up), and which of those members are PICTURES — paper is not one,
/// which is why it cannot keep a cel alive by itself.
typedef _CelBundle = ({
  Layer axis,
  List<Layer> members,
  Set<LayerId> pictureIds,
});

/// Every bundle the selection touches, in stack order: one per base whose
/// own stack — itself or an attach row riding it — holds a selected
/// picture. A base with none is not a bundle at all.
Iterable<_CelBundle> _celBundlesOf(
  Cut cut,
  ExportCelsSelection selection,
) sync* {
  final selectedIds = {for (final layer in selection.celLayers) layer.id};
  final paperIds = {for (final layer in selection.paperLayers) layer.id};
  for (final base in cut.layers) {
    if (!_canOwnABundle(base)) {
      continue;
    }
    final pictures = _bundlePictures(cut, base, selectedIds);
    if (pictures.isEmpty) {
      continue;
    }
    final pictureIds = {for (final layer in pictures) layer.id};
    yield (
      axis: _bundleAxis(pictures, base),
      members: [
        for (final layer in cut.layers)
          if (pictureIds.contains(layer.id) || paperIds.contains(layer.id))
            layer,
      ],
      pictureIds: pictureIds,
    );
  }
}

/// A bundle as ONE cut of its 겸용 group has it: that cut, and the bundle's
/// rows there.
typedef _BundleIn = ({Cut cut, _CelBundle bundle});

/// [bundle] — laid from [from]'s cut — as each cut of that cut's 겸용 group
/// has it, in TRACK order: the cuts a cel of the bundle can be shown by.
/// [from]'s cut alone where it is linked to none.
List<_BundleIn> _bundleAcrossTheGroup(_CutRun from, _CelBundle bundle) => [
  for (final cut in linkedCutGroupInTrackOrder(
    from.run.project,
    cutId: from.cut.id,
  ))
    if (cut.id == from.cut.id)
      (cut: from.cut, bundle: bundle)
    else if (_bundleIn(from, bundle, cut) case final there?)
      (cut: cut, bundle: there),
];

/// [bundle] as [sibling] has it — the stack a cel [sibling] shows is
/// composited in: each picture row's counterpart there (its link), and the
/// paper rows of [sibling]'s OWN. Null when the axis does not reach
/// [sibling].
///
/// WHICH rows are pictures is the window's choice, made on the cut it
/// stands on, and the link carries it over; the paper is no choice — it is
/// whatever the cut that shows the cel lays under it.
_CelBundle? _bundleIn(_CutRun from, _CelBundle bundle, Cut sibling) {
  LayerId? there(LayerId id) => linkCounterpartIn(
    from.run.project,
    cutId: from.cut.id,
    layerId: id,
    targetCutId: sibling.id,
  );
  final axisId = there(bundle.axis.id);
  final axis = sibling.layers.firstWhereOrNull((layer) => layer.id == axisId);
  if (axis == null) {
    return null;
  }
  final pictureIds = {for (final id in bundle.pictureIds) ?there(id)};
  final paperIds = {
    for (final layer in exportPaperRowsOf(sibling, from.run.spec)) layer.id,
  };
  return (
    axis: axis,
    members: [
      for (final layer in sibling.layers)
        if (pictureIds.contains(layer.id) || paperIds.contains(layer.id)) layer,
    ],
    pictureIds: pictureIds,
  );
}

/// The cut of [group] that SHOWS the cel [frameId]: the first, in track
/// order, whose axis has it on its timeline — or null when none does.
///
/// The first in TRACK order, not the cut the window stands on: two
/// siblings showing one cel under different papers would otherwise export
/// a different picture for each cut that happened to be open.
_BundleIn? _shownIn(List<_BundleIn> group, FrameId frameId) => group
    .firstWhereOrNull(
      (there) => firstExposureOf(there.bundle.axis, frameId) != null,
    );

/// Whether a row can be the base a bundle hangs from: an attach row rides
/// someone else's bundle, an instruction row exports its own events, and a
/// row that holds no cel holds no bundle either.
bool _canOwnABundle(Layer layer) =>
    !isAttachedLayer(layer) &&
    layer.kind.exportsCels &&
    layer.kind != LayerKind.instruction;

/// [base]'s own stack, filtered to what the selection keeps: the base
/// itself and the rows attached to it, in cut order.
List<Layer> _bundlePictures(Cut cut, Layer base, Set<LayerId> selectedIds) {
  final riderIds = {
    for (final rider in attachedLayersOf(base.id, cut.layers)) rider.id,
  };
  return [
    for (final layer in cut.layers)
      if (selectedIds.contains(layer.id) &&
          (layer.id == base.id || riderIds.contains(layer.id)))
        layer,
  ];
}

/// The layer whose frames number the bundle's cels: the base — EXCEPT when
/// a FREE attach row is the bundle's only picture, and then it is that row
/// (its own frames, its own name). 유저 2026-09-09: 「여러개 선택되면
/// 기준레이어 따라가고 프리부속 단독이면 단독 기준」.
Layer _bundleAxis(List<Layer> pictures, Layer base) {
  if (pictures.length != 1) {
    return base;
  }
  final lone = pictures.single;
  return isAttachedLayer(lone) && !isSyncedAttachedLayer(lone) ? lone : base;
}

/// One task per numbered cel of [bundle] — the axis frames that carry a
/// cel number AND a picture. [unnamedFiled] holds the labels whose unnamed
/// cel the cut has already filed.
Iterable<ExportCelGroupTask> _bundleTasks(
  _CelBundle bundle,
  _CutRun cut, {
  required Set<String> unnamedFiled,
}) sync* {
  final group = _bundleAcrossTheGroup(cut, bundle);
  for (final axisFrame in _inCelOrder(bundle.axis.frames)) {
    final celName = _fileCelName(bundle.axis, axisFrame);
    if (celName == null) {
      continue;
    }
    // 🚨F-300: the cel is composited in the cut that SHOWS it — a cel no
    // cut shows stays the window's cut's, as a cut alone has it.
    final shown =
        _shownIn(group, axisFrame.id) ?? (cut: cut.cut, bundle: bundle);
    final baseFrame = shown.bundle.axis.frameById(axisFrame.id) ?? axisFrame;
    final frames = [
      for (final member in shown.bundle.members)
        celGroupMemberFrame(
          base: shown.bundle.axis,
          member: member,
          baseFrame: baseFrame,
        ),
    ];
    if (!_holdsAPicture(shown.bundle, frames)) {
      continue;
    }
    // 🗣️유저 2026-09-25: 「같은 이름 레이어가 존재하고 똑같이 이름없는게
    // 존재하면 거기서 순서상 첫 블록만. 하나만 출력되면되」. BOOK rows stack
    // under one name, so their unnamed cels are all `BOOK`: the first the
    // walk meets is the file, and the rest are no cel of this export — not
    // `BOOK_2`, a name nobody gave.
    if (celName.isEmpty && !unnamedFiled.add(bundle.axis.name)) {
      continue;
    }
    yield ExportCelGroupTask(
      cut: shown.cut,
      baseLayer: shown.bundle.axis,
      listedUnder: identical(shown.bundle, bundle)
          ? null
          : (cut: cut.cut, axis: bundle.axis),
      members: shown.bundle.members,
      memberFrames: frames,
      baseFrame: baseFrame,
      celName: celName,
      fileName: cut.run.fileNameFor(
        cutName: cut.cutName,
        labelName: bundle.axis.name,
        celName: celName,
      ),
      skipped: cut.skipped.contains(bundle.axis.id),
    );
  }
}

/// What [frame] of [axis] is called on its file, or null when it writes no
/// file at all.
///
/// An unnamed drawing is the in-between mark, not a cel: no file. The sheet
/// prints the mark for the very same frame ([Frame.celNumber] decides for
/// both); numbering it by position here invented a cel the sheet never
/// listed (유저 2026-09-09).
///
/// 🗣️EXCEPT where the unnamed cel is the layer's own picture
/// ([LayerKind.unnamedCelIsTheLayer]) — 유저 2026-09-25: 「이름없어도 출력은
/// 이 규칙은 이미지레이어에만 적용. 애니메이션레이어는 이름없으면 출력안함」,
/// 「이름없이 BOOK 그대로 출력」. Its cel name is empty, so the file wears the
/// layer's name alone ([celGroupFileBase]).
///
/// ⚠️THE ONE THE ROW SHOWS, not any unnamed cel of its BANK (F-98, 유저
/// 2026-09-12: 「이름 안정해지면 별개것임」): the bank is the link group's
/// and holds every 겸용 cut's unnamed picture of the row — each of them 「the
/// layer」 in its own cut, and no cel of this one.
String? _fileCelName(Layer axis, Frame frame) =>
    frame.celNumber ??
    (axis.kind.unnamedCelIsTheLayer &&
            authoredBlockOf(axis)?.frameId == frame.id
        ? ''
        : null);

/// [frames] in the order their cels are listed and written: by cel number,
/// the way a file browser orders names — digits by value, letters without
/// case.
///
/// 🚨F-177 (유저 2026-09-22): 「셀 출력시 미리보기의 셀 정렬, 지금 C1,2,3이
/// 있다면 C2,3,1 이런식으로 되있거나 A1,2,2a,3 이렇게 됬으면하는게
/// A1,2,3,4,5,6,7,8,9,2a 이렇게 됨. 즉 정렬을 윈도우 기준? 으로 해줬으면함」.
/// The bank's order is the order the drawings were MADE in — 2a, drawn last,
/// came after 9.
///
/// ⚠️Stable where two names are equal: the namer hands out `A1` and `A1_2`
/// in the order it meets them, and the bank's order still decides that.
List<Frame> _inCelOrder(List<Frame> frames) {
  final indexed = [for (var i = 0; i < frames.length; i += 1) (frames[i], i)]
    ..sort((a, b) {
      final byName = compareAsciiLowerCaseNatural(
        a.$1.celNumber ?? '',
        b.$1.celNumber ?? '',
      );
      return byName != 0 ? byName : a.$2.compareTo(b.$2);
    });
  return [for (final (frame, _) in indexed) frame];
}

/// Whether this cel has anything to draw: 「그림이 존재하는 영역만 출력」.
/// Applied paper does not count — a cel of paper alone is not a cel.
bool _holdsAPicture(_CelBundle bundle, List<Frame?> frames) {
  for (var i = 0; i < bundle.members.length; i += 1) {
    if (bundle.pictureIds.contains(bundle.members[i].id) && frames[i] != null) {
      return true;
    }
  }
  return false;
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
  final group = linkedCutGroupInTrackOrder(project, cutId: cut.id);
  return group.length <= 1
      ? cut.name
      : [for (final sibling in group) sibling.name].join('-');
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
      _celGroupTasksFor((
        cut: cut,
        cutName: cutName,
        run: run,
        skipped: delta?.skippedBases ?? const {},
      ), selection),
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
/// text, the number always prints; a cel with no number keeps its label).
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
  // An unnamed image cel has no number to print: the layer's name is its
  // whole name (유저 2026-09-25: 「이름없이 BOOK 그대로 출력」), so it prints
  // with the label switched off too — else the file would have no name.
  if (naming.includeLayerName || celName.isEmpty) {
    joined.write(sanitizeExportFileComponent(labelName));
  }
  joined.write(padFrameNumber(celName, naming.frameDigits));
  if (naming.suffix.isNotEmpty) {
    joined.write(naming.suffix);
  }
  return joined.toString();
}
