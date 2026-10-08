import 'package:collection/collection.dart'
    show IterableExtension, compareAsciiLowerCaseNatural;

import '../../models/attached_layer_resolve.dart';
import '../../models/camera_instruction.dart';
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
import '../../services/project_lookup.dart' show cutPositionOf;
import '../envelope/cut_envelope_builder.dart' show cutEnvelopeInkOwner;
import 'export_cels_selection.dart';
import 'export_document_sheet.dart';
import 'export_list_sheet.dart';
import 'export_plan.dart';

export 'export_document_sheet.dart' show ExportDocumentSheet;
export 'export_list_sheet.dart' show ExportCelRefusal, ExportListSheet;

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
    this.overlays = const [],
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

  /// The row the window lists this cel on — the one its block stands on
  /// ([listedUnder]).
  Layer get bundleAxis => listedUnder?.axis ?? baseLayer;

  /// The user turned this drawing off in the list: planned and previewable,
  /// but not written ([ExportCelGroupPlan.writtenCels]). Kept in the plan
  /// rather than dropped so the list still shows its block, hollow.
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
  /// and this is empty ([_fileCelName]). A direction row's drawing is not
  /// numbered: this is what its block SAYS ([directionCelName]).
  final String celName;

  /// Relative to the export directory; may contain `/` subfolders. Empty
  /// on a picture that is no file ([ExportCelSheet.look] of a refusal).
  final String fileName;

  /// The direction drawings laid over this cel, bottom-up, above every
  /// member ([ExportCelsCutDelta.directionOver]).
  final List<ExportCelOverlay> overlays;
}

/// A direction drawing laid over a cel: the direction row's drawing, in the
/// cut it was picked in — the one the window lists the cel in, where its
/// direction rows are.
typedef ExportCelOverlay = ({Cut cut, Layer layer, Frame frame});

/// ONE DRAWING of a listed row, as the plan answers for it: the cel it
/// writes, or why it writes none. The window's list is these, a block each
/// ([ExportListSheet]) — beside the cut's documents ([ExportDocumentSheet]).
///
/// ⛔The plan answers for EVERY drawing — the list does not ask again. A
/// list that worked out for itself which drawings go would be the planner
/// written twice, and the second copy is the one that drifts.
class ExportCelSheet extends ExportListSheet {
  const ExportCelSheet({
    required this.cut,
    required this.row,
    required this.frame,
    required this.celName,
    required this.word,
    required this.look,
    this.refused,
  });

  /// The cut the window lists it in.
  final Cut cut;

  /// The row its block stands on, in [cut]: a base, or a free attach row —
  /// the rows that hold drawings of their own.
  final Layer row;

  /// The row's drawing.
  final Frame frame;

  /// What it is called on its file ([ExportCelGroupTask.celName]): its
  /// number, a direction's whole name (`T.U_A-B`) — or nothing, for a
  /// picture that goes out under its row's name alone.
  final String celName;

  /// What its BLOCK reads: its number, its row's name where it has none,
  /// and of a direction's drawing what its block says alone (`T.U`) — a
  /// block is one cell wide (drawn so in the F-289 mock, and of the band's
  /// buttons 유저 2026-10-06: 「버튼엔 지시이름만 넣자. T.U 이렇게하고
  /// 툴팁으로 T.U_A-B 이렇게」).
  @override
  final String word;

  @override
  String get fullName => celName.isEmpty ? row.name : celName;

  @override
  final ExportCelRefusal? refused;

  /// The picture: the cel that is written, for a planned drawing — or, for
  /// one that is [refused], the drawing by itself over its cut's paper,
  /// which is what the preview shows of a row that is off.
  final ExportCelGroupTask look;

  /// Its picture's own answer, so the list and the run cannot say two
  /// things.
  @override
  bool get skipped => look.skipped;

  @override
  String get fileName => look.fileName;

  @override
  bool get laid => look.overlays.isNotEmpty;

  @override
  String get idValue => frame.id.value;

  /// What the hand did to a drawing is kept with the cut that lists it.
  @override
  CutId get deltaCut => cut.id;

  ExportCelRef get ref => (row: row.id, cel: frame.id);
}

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
  final overlays = [
    for (final over in task.overlays)
      '${over.cut.id.value}/${over.layer.id.value}/${over.frame.id.value}',
  ].join(',');
  return 'celgroup:${task.cut.id.value}:${task.baseLayer.id.value}:'
      '${task.baseFrame.id.value}:$members:$overlays:$sizeMode:'
      '$backgroundKey:${applyLayerFx ? 'fx' : 'raw'}';
}

class ExportCelGroupPlan {
  ExportCelGroupPlan({required this.sheets, this.documents = const []})
    : cels = [
        for (final sheet in sheets)
          if (sheet.planned) sheet.look,
      ];

  /// Every drawing of every listed row, in the order the walk meets them —
  /// what the window lists.
  final List<ExportCelSheet> sheets;

  /// Every file of the documents the export writes beside the cels — each
  /// cut's timesheet, its cut envelope — in the order the walk meets them:
  /// what the window lists under the rows ([_documentsOf]).
  final List<ExportDocumentSheet> documents;

  /// Every planned cel, on or turned off, in WRITE order — the namer's
  /// de-dup suffix rides on it.
  final List<ExportCelGroupTask> cels;

  /// The cels that will be written: the planned ones that are on.
  List<ExportCelGroupTask> get writtenCels => [
    for (final task in cels)
      if (!task.skipped) task,
  ];

  /// The documents' files that will be written.
  List<ExportDocumentSheet> get writtenDocuments => [
    for (final sheet in documents)
      if (sheet.written) sheet,
  ];

  /// The files the export writes, in WRITE order: the cels, then the
  /// documents.
  List<String> get writtenFileNames => [
    for (final task in writtenCels) task.fileName,
    for (final sheet in writtenDocuments) sheet.fileName,
  ];

  /// How many files the export writes.
  int get length => writtenCels.length + writtenDocuments.length;
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
/// shows there. A planned cel is always shown by its cut ([_axisSheets]),
/// so the fallback is for a task built by hand.
int celGroupFirstExposure(ExportCelGroupTask task) =>
    firstExposureOf(task.baseLayer, task.baseFrame.id) ?? 0;

/// One cut as this export run sees it: the cut itself, the name its files
/// carry (a 겸용 group's joined name), the run's namer and what the hand
/// did to this cut. They travel together because every step of the walk
/// needs all four.
typedef _CutRun = ({
  Cut cut,
  String cutName,
  _NamingRun run,
  ExportCelsCutDelta? delta,
});

/// One sheet per drawing of every listed row of [cut].
///
/// A bundle exists for every base whose stack holds a selected picture —
/// the base itself, or an attach row riding it (어태치 preset: the base is
/// OFF and its parts are ON). A cel is planned only where some picture
/// member has a frame: 「그림이 존재하는 영역만 출력」 — paper alone is not a
/// picture. A drawing that is not planned is still answered for, with why
/// ([ExportCelRefusal]).
Iterable<ExportCelSheet> _celSheetsFor(
  _CutRun cut,
  ExportCelsSelection selection,
) sync* {
  final unnamedFiled = <String>{};
  for (final stack in _celStacksOf(cut, selection)) {
    final bundle = stack.bundle;
    for (final row in stack.rows) {
      if (bundle != null && row.id == bundle.axis.id) {
        yield* _axisSheets(bundle, cut, unnamedFiled: unnamedFiled);
      } else {
        yield* _sheetsBesideTheAxis(row, bundle, cut);
      }
    }
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

/// One listed base's stack: the rows of it that hold drawings of their own
/// — the base and the FREE attach rows riding it (a synced one follows the
/// base's cels) — and the bundle the selection makes of it, or null where
/// it keeps no picture of the stack at all.
typedef _CelStack = ({List<Layer> rows, _CelBundle? bundle});

/// Every listed base's stack, in stack order. A base of a kind the export
/// does not write is not listed, so it is not here ([exportCelsListsRow]).
Iterable<_CelStack> _celStacksOf(
  _CutRun cut,
  ExportCelsSelection selection,
) sync* {
  final layers = cut.cut.layers;
  final selectedIds = {for (final layer in selection.celLayers) layer.id};
  final paperIds = {for (final layer in selection.paperLayers) layer.id};
  for (final base in layers) {
    if (!_canOwnABundle(base) ||
        !exportCelsListsRow(base, layers, cut.run.spec)) {
      continue;
    }
    final pictures = _bundlePictures(cut.cut, base, selectedIds);
    yield (
      rows: [
        base,
        for (final rider in attachedLayersOf(base.id, layers))
          if (!isSyncedAttachedLayer(rider) &&
              exportCelsListsRow(rider, layers, cut.run.spec))
            rider,
      ],
      bundle: pictures.isEmpty
          ? null
          : _bundleOf(cut.cut, _bundleAxis(pictures, base), {
              for (final layer in pictures) layer.id,
            }, paperIds),
    );
  }
}

/// The bundle numbered by [axis] whose pictures are [pictureIds], over the
/// paper rows [paperIds], bottom-up in [cut]'s order.
_CelBundle _bundleOf(
  Cut cut,
  Layer axis,
  Set<LayerId> pictureIds,
  Set<LayerId> paperIds,
) => (
  axis: axis,
  members: [
    for (final layer in cut.layers)
      if (pictureIds.contains(layer.id) || paperIds.contains(layer.id)) layer,
  ],
  pictureIds: pictureIds,
);

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
/// someone else's bundle, and a row that holds no cel holds no bundle
/// either.
bool _canOwnABundle(Layer layer) =>
    !isAttachedLayer(layer) && layer.kind.exportsCels;

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

/// The drawings of [axis] that are cels, each with what it is called on its
/// file, in the order they are listed and written.
///
/// A DIRECTION row's are its blocks' drawings, in the order the timeline
/// shows them, each called by what its block says ([directionCelName]) —
/// 🗣️F-289 (유저 2026-10-05): 「디렉션레이어 출력시, 그림이 디렉션레이어의
/// 지시인데, 그게아니라 그림 그릴수있는 레이어니 거기 있는 그림 출력하도록」.
/// A drawing two blocks show is one cel, called by the first.
///
/// Every other row's are its NUMBERED frames ([_fileCelName]), by number
/// ([_inCelOrder]).
Iterable<_RowCel> _celsOf(Layer axis, CameraInstructionSet terms) sync* {
  if (axis.kind != LayerKind.instruction) {
    for (final frame in _inCelOrder(axis.frames)) {
      if (_fileCelName(axis, frame) case final celName?) {
        yield (
          row: axis,
          frame: frame,
          celName: celName,
          word: celName.isEmpty ? axis.name : celName,
        );
      }
    }
    return;
  }
  for (final (:frame, :says) in _directedDrawingsOf(axis)) {
    yield (
      row: axis,
      frame: frame,
      celName: directionCelName(says, terms),
      word: says == null ? axis.name : _directionWord(says, terms),
    );
  }
}

/// ONE DRAWING of a row that is a cel: the row its block stands on, the
/// drawing, what it is called on its file and what its block reads
/// ([_celsOf]). They travel together because a sheet is made of all four.
typedef _RowCel = ({Layer row, Frame frame, String celName, String word});

/// A direction row's drawings in the order the timeline shows them, each
/// with what its block says — null where it says nothing. A drawing two
/// blocks show is one drawing, called by the first.
Iterable<({Frame frame, InstructionEvent? says})> _directedDrawingsOf(
  Layer row,
) sync* {
  final listed = <FrameId>{};
  for (final block in drawingBlocks(row.timeline)) {
    // A ghost shows again what its own block already listed, and says
    // nothing of its own.
    if (block.entry.ghost) {
      continue;
    }
    final frame = row.frameById(block.frameId);
    if (frame == null || !listed.add(frame.id)) {
      continue;
    }
    yield (frame: frame, says: row.instructions[block.startIndex]);
  }
}

/// A direction row's drawing as the window offers it to be laid over a cel:
/// which it is, what its button reads — what its block says (유저
/// 2026-10-06: 「버튼엔 지시이름만 넣자. T.U 이렇게하고 툴팁으로 T.U_A-B
/// 이렇게」), its row's name where the block says nothing — and its whole
/// name.
typedef ExportDirectionDrawing = ({
  ExportCelRef ref,
  String name,
  String fullName,
});

/// Every drawing of [cut]'s direction rows, in the order the cut stacks the
/// rows and each row's timeline shows its drawings.
List<ExportDirectionDrawing> exportDirectionDrawingsOf(
  Cut cut,
  CameraInstructionSet terms,
) => [
  for (final row in cut.layers)
    if (row.kind == LayerKind.instruction)
      for (final drawing in _celsOf(row, terms))
        (
          ref: (row: row.id, cel: drawing.frame.id),
          name: drawing.word,
          fullName: drawing.celName.isEmpty ? row.name : drawing.celName,
        ),
];

/// What a direction's block says: the name of what it directs.
String _directionWord(InstructionEvent says, CameraInstructionSet terms) =>
    says.displayLabel(terms.defById(says.instructionId));

/// What a direction row's drawing is called: what its block says and the
/// two ends it runs between — `T.U_A-B` — or nothing for a block that says
/// nothing, whose file wears the row's name alone.
///
/// 🗣️유저 2026-10-06: 「디렉션 프레임 이름은 지시명으로 … 첫이름이 A고
/// 끝이름이 B고 지시이름이 T.U면, T.U_A-B」. An end that is not written is
/// left out, the dash with it when only one is.
String directionCelName(InstructionEvent? says, CameraInstructionSet terms) {
  if (says == null) {
    return '';
  }
  final ends = [
    for (final end in [says.valueA, says.valueB])
      if (end != null && end.trim().isNotEmpty) end.trim(),
  ].join('-');
  final name = _directionWord(says, terms);
  return ends.isEmpty ? name : '${name}_$ends';
}

/// A drawing of a bundle where a cut of its 겸용 group SHOWS it: that cut's
/// bundle, the drawing as that cut's axis holds it, and what each member
/// contributes to it there.
typedef _PlacedCel = ({_BundleIn shown, Frame baseFrame, List<Frame?> frames});

/// [axisFrame] of the bundle [group] is of, where it is shown — or null
/// when no cut of the group shows it.
///
/// 🚨F-300: the cel is composited in the cut that SHOWS it.
_PlacedCel? _placedIn(List<_BundleIn> group, Frame axisFrame) {
  final shown = _shownIn(group, axisFrame.id);
  if (shown == null) {
    return null;
  }
  final baseFrame = shown.bundle.axis.frameById(axisFrame.id) ?? axisFrame;
  return (
    shown: shown,
    baseFrame: baseFrame,
    frames: [
      for (final member in shown.bundle.members)
        celGroupMemberFrame(
          base: shown.bundle.axis,
          member: member,
          baseFrame: baseFrame,
        ),
    ],
  );
}

/// One sheet per cel of [bundle]'s axis ([_celsOf]): the task that writes
/// it, or why none does. [unnamedFiled] holds the labels whose unnamed cel
/// the cut has already filed.
Iterable<ExportCelSheet> _axisSheets(
  _CelBundle bundle,
  _CutRun cut, {
  required Set<String> unnamedFiled,
}) sync* {
  final group = _bundleAcrossTheGroup(cut, bundle);
  for (final drawing in _celsOf(
    bundle.axis,
    cut.run.project.cameraInstructions,
  )) {
    final placed = _placedIn(group, drawing.frame);
    // 🗣️F-289 ⑥ (유저 2026-10-06): 「애초에 타임라인에 안놓은 셀은 출력에
    // 포함하지않음」 — a cel no cut of the group shows is no cel of this
    // export. ↩️It went out from the window's cut with nothing under it:
    // an unshown cel has no place on the timeline for the paper or a free
    // rider to answer at ([celGroupMemberFrame]).
    if (placed == null) {
      yield _refusedSheet(drawing, cut, ExportCelRefusal.notPlaced);
      continue;
    }
    final refused = !_holdsAPicture(placed.shown.bundle, placed.frames)
        ? ExportCelRefusal.noPicture
        : _unnamedIsFiledAlready(bundle.axis, drawing.celName, unnamedFiled)
        ? ExportCelRefusal.sameName
        : null;
    if (refused != null) {
      yield _refusedSheet(drawing, cut, refused);
      continue;
    }
    yield _sheet(
      drawing,
      cut,
      look: _cel(
        placed,
        cut,
        drawing,
        fileName: cut.run.fileNameFor(
          // A bundle is listed — so it has a kind: its axis's
          // ([exportCelKindOf]; a lone attach row answers with its base's).
          kind: exportCelKindOf(bundle.axis, cut.cut.layers)!,
          cutName: cut.cutName,
          labelName: bundle.axis.name,
          celName: drawing.celName,
        ),
      ),
    );
  }
}

/// [drawing] as [cut]'s list holds it: what it looks like, and why it is no
/// file where it is none.
ExportCelSheet _sheet(
  _RowCel drawing,
  _CutRun cut, {
  required ExportCelGroupTask look,
  ExportCelRefusal? refused,
}) => ExportCelSheet(
  cut: cut.cut,
  row: drawing.row,
  frame: drawing.frame,
  celName: drawing.celName,
  word: drawing.word,
  refused: refused,
  look: look,
);

/// The drawings of [row] — a row of a listed stack that is NOT its bundle's
/// axis — none of them a file: its base's cels carry it ([bundle] holds it
/// as a picture), or it is off.
Iterable<ExportCelSheet> _sheetsBesideTheAxis(
  Layer row,
  _CelBundle? bundle,
  _CutRun cut,
) sync* {
  final why = bundle != null && bundle.pictureIds.contains(row.id)
      ? ExportCelRefusal.ridesBase
      : ExportCelRefusal.rowOff;
  for (final drawing in _celsOf(row, cut.run.project.cameraInstructions)) {
    yield _refusedSheet(drawing, cut, why);
  }
}

/// [drawing] as one the export does not write: [why], and what it looks
/// like by itself — its row alone over the paper of the cut that shows it,
/// laid by the same steps a written cel is ([_placedIn]). A drawing no cut
/// shows is the bare drawing.
ExportCelSheet _refusedSheet(
  _RowCel drawing,
  _CutRun cut,
  ExportCelRefusal why,
) {
  final (:row, :frame, celName: _, word: _) = drawing;
  final alone = _bundleOf(cut.cut, row, {row.id}, {
    for (final paper in exportPaperRowsOf(cut.cut, cut.run.spec)) paper.id,
  });
  final placed =
      _placedIn(_bundleAcrossTheGroup(cut, alone), frame) ??
      (
        shown: (cut: cut.cut, bundle: _bundleOf(cut.cut, row, {row.id}, {})),
        baseFrame: frame,
        frames: <Frame?>[frame],
      );
  return _sheet(
    drawing,
    cut,
    refused: why,
    look: _cel(placed, cut, drawing, fileName: ''),
  );
}

/// The cel [placed] is, listed as [listed] in [cut]'s cut: whether the hand
/// turned it off there, and what is laid over it.
ExportCelGroupTask _cel(
  _PlacedCel placed,
  _CutRun cut,
  _RowCel listed, {
  required String fileName,
}) => ExportCelGroupTask(
  cut: placed.shown.cut,
  baseLayer: placed.shown.bundle.axis,
  listedUnder: placed.shown.cut.id == cut.cut.id
      ? null
      : (cut: cut.cut, axis: listed.row),
  members: placed.shown.bundle.members,
  memberFrames: placed.frames,
  baseFrame: placed.baseFrame,
  celName: listed.celName,
  fileName: fileName,
  skipped: _turnedOff(cut, listed.row, listed.frame),
  overlays: _overlaysOn(cut, listed.row, listed.frame),
);

/// Whether the hand turned [frame] of [row] off in [cut]'s list.
bool _turnedOff(_CutRun cut, Layer row, Frame frame) =>
    cut.delta?.skippedCels.contains((row: row.id, cel: frame.id)) ?? false;

/// The direction drawings laid over [frame] of [row]
/// ([ExportCelsCutDelta.directionOver]), in the order [cut]'s cut stacks
/// its direction rows and each row holds its drawings. A direction that is
/// no longer in the cut is not laid — and nothing is laid over a direction
/// row's own drawing.
List<ExportCelOverlay> _overlaysOn(_CutRun cut, Layer row, Frame frame) {
  final laid = cut.delta?.directionsOver((row: row.id, cel: frame.id));
  if (laid == null || laid.isEmpty || row.kind == LayerKind.instruction) {
    return const [];
  }
  return [
    for (final layer in cut.cut.layers)
      if (layer.kind == LayerKind.instruction)
        for (final drawing in layer.frames)
          if (laid.contains((row: layer.id, cel: drawing.id)))
            (cut: cut.cut, layer: layer, frame: drawing),
  ];
}

/// Whether [axis]'s unnamed cel — one called [celName], empty — is one the
/// cut has filed before; [filed] holds the labels that have, and takes this
/// one the first time it is asked.
///
/// 🗣️유저 2026-09-25: 「같은 이름 레이어가 존재하고 똑같이 이름없는게 존재하면
/// 거기서 순서상 첫 블록만. 하나만 출력되면되」. BOOK rows stack under one
/// name, so their unnamed cels are all `BOOK`: the first the walk meets is
/// the file, and the rest are no cel of this export — not `BOOK_2`, a name
/// nobody gave.
///
/// ⛔Not a direction row's: each of its drawings that says nothing is a cel
/// of its own, and the namer tells them apart (`Direction` ·
/// `Direction_2`).
bool _unnamedIsFiledAlready(Layer axis, String celName, Set<String> filed) =>
    axis.kind != LayerKind.instruction &&
    celName.isEmpty &&
    !filed.add(axis.name);

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
    required ExportCelKind kind,
    required String cutName,
    required String labelName,
    required String celName,
  }) => namer.uniqueFileName(
    projectName: project.name,
    cutName: cutName,
    layerName: labelName,
    base: celGroupFileBase(
      kind: kind,
      projectName: project.name,
      cutName: cutName,
      labelName: labelName,
      celName: celName,
      naming: spec.naming,
    ),
  );
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
/// sheet per drawing of every listed row — a task where it is a cel that
/// has a picture, a refusal where it is not ([_celSheetsFor]). Under the
/// project scope a 겸용 group is walked once, from its owner cut.
ExportCelGroupPlan buildExportCelGroupPlan({
  required Project project,
  required CutId activeCutId,
  required CelsExportSpec spec,
  ExportProjectOverrides? overrides,
  String fileExtension = 'png',
  int Function(Cut cut)? sheetPagesOf,
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
  final sheets = <ExportCelSheet>[];
  final documents = <ExportDocumentSheet>[];
  for (final cut in exportCutsInScope(
    project: project,
    activeCutId: activeCutId,
    scope: spec.scope,
    overrides: overrides,
  )) {
    if (projectScope && cutEnvelopeInkOwner(project, cut.id) != cut.id) {
      continue;
    }
    final delta = overrides?.deltaFor(cut.id);
    final selection = resolveExportCelsSelection(
      cut: cut,
      spec: spec,
      delta: delta,
    );
    final entry = (
      cut: cut,
      cutName: celGroupCutName(project, cut),
      run: run,
      delta: delta,
    );
    sheets.addAll(_celSheetsFor(entry, selection));
    documents.addAll(
      _documentsOf(entry, overrides, sheetPagesOf ?? (cut) => 1),
    );
  }
  return ExportCelGroupPlan(sheets: sheets, documents: documents);
}

/// One of a cut's documents before its files are counted: which, the cut it
/// is of, and how many files it is written as.
typedef _Document = ({ExportCelKind kind, Cut of, int pages});

/// The documents the export writes beside the cels of [entry]'s cut
/// (F-289, 유저 2026-10-05: 「타임시트 탭을 그냥 셀 탭의 내부로 편입.
/// 컷봉투탭도 셀 내부로 편입 … 기존의 범위는 셀의 범위 규칙 따라가고」): the
/// timesheet of every cut the entry stands for, and the cut envelope — ONE
/// for a 겸용 group, which shares it ([cutEnvelopeInkOwner]).
///
/// A timesheet is a file a page ([sheetPagesOf]) as pictures, and one file
/// as the digital sheet.
Iterable<ExportDocumentSheet> _documentsOf(
  _CutRun entry,
  ExportProjectOverrides? overrides,
  int Function(Cut cut) sheetPagesOf,
) sync* {
  final (:project, :spec, namer: _) = entry.run;
  if (spec.kinds.contains(ExportCelKind.timesheet)) {
    final oneFile = spec.sheetFormat == ExportTimesheetFormat.xdts;
    for (final of in _cutsOf(entry)) {
      yield* _filesOf(
        (
          kind: ExportCelKind.timesheet,
          of: of,
          pages: oneFile ? 1 : sheetPagesOf(of),
        ),
        entry,
        overrides,
      );
    }
  }
  if (spec.kinds.contains(ExportCelKind.envelope)) {
    final owner = cutEnvelopeInkOwner(project, entry.cut.id);
    yield* _filesOf(
      (
        kind: ExportCelKind.envelope,
        of: cutPositionOf(project, owner)?.cut ?? entry.cut,
        pages: 1,
      ),
      entry,
      overrides,
    );
  }
}

/// The cuts [entry] stands for: its own under the cut scope — and under the
/// project scope every cut of its 겸용 group, in track order (the group is
/// walked once, from its owner, and each of its cuts keeps a timesheet of
/// its own).
List<Cut> _cutsOf(_CutRun entry) =>
    entry.run.spec.scope == ExportScopeKind.project
    ? linkedCutGroupInTrackOrder(entry.run.project, cutId: entry.cut.id)
    : [entry.cut];

/// The files of [document], listed in [entry]'s cut. Each answers to the
/// delta of the cut the document is OF: its row switched off there, or the
/// file itself turned off.
Iterable<ExportDocumentSheet> _filesOf(
  _Document document,
  _CutRun entry,
  ExportProjectOverrides? overrides,
) sync* {
  final (:kind, :of, :pages) = document;
  final delta = overrides?.deltaFor(of.id);
  final off = delta?.documentsOff.contains(kind) ?? false;
  for (var page = 0; page < pages; page += 1) {
    yield ExportDocumentSheet(
      kind: kind,
      listedIn: entry.cut,
      of: of,
      page: page,
      pageCount: pages,
      skipped:
          delta?.skippedPages.contains((document: kind, page: page)) ?? false,
      refused: off ? ExportCelRefusal.rowOff : null,
      // A file that is not written takes no name from the run.
      fileName: off
          ? ''
          : entry.run.namer.uniqueDocumentName(
              projectName: entry.run.project.name,
              cutName: entry.cutName,
              base:
                  '${entry.run.spec.naming.prefixOf(kind)}'
                  '${exportDocumentBase(kind, of, page, pages)}',
              extension: exportDocumentExtension(kind, entry.run.spec),
            ),
    );
  }
}

/// `[prefix][proj_][cut_]<label><cel>[suffix]` — the bundle reading of the
/// CSP naming options ([ExportCelNaming.includeLayerName] switches the LABEL
/// text, the number always prints; a cel with no number keeps its label),
/// led by what [kind]'s files start with ([ExportCelNaming.prefixOf] —
/// `_BG1`).
///
/// A DIRECTION drawing is named, not numbered ([directionCelName]): the
/// name stands off the label by an underscore and is never padded —
/// `Direction_T.U_A-B` (유저 2026-10-06: 「디렉션레이어는 프레임이름이랑
/// 레이어이름사이에 _ 넣고, 지시랑 첫/끝이름 사이에 _ 넣는거지」).
String celGroupFileBase({
  required ExportCelKind kind,
  required String projectName,
  required String cutName,
  required String labelName,
  required String celName,
  required ExportCelNaming naming,
}) {
  final joined = StringBuffer(naming.prefixOf(kind));
  if (naming.includeProjectName) {
    joined.write('${sanitizeExportFileComponent(projectName)}_');
  }
  if (naming.includeCutName) {
    joined.write('${sanitizeExportFileComponent(cutName)}_');
  }
  // An unnamed image cel has no number to print: the layer's name is its
  // whole name (유저 2026-09-25: 「이름없이 BOOK 그대로 출력」), so it prints
  // with the label switched off too — else the file would have no name.
  final labelled = naming.includeLayerName || celName.isEmpty;
  if (labelled) {
    joined.write(sanitizeExportFileComponent(labelName));
  }
  if (kind != ExportCelKind.direction) {
    joined.write(padFrameNumber(celName, naming.frameDigits));
  } else if (celName.isNotEmpty) {
    joined
      ..write(labelled ? '_' : '')
      ..write(sanitizeExportFileComponent(celName));
  }
  if (naming.suffix.isNotEmpty) {
    joined.write(naming.suffix);
  }
  return joined.toString();
}
