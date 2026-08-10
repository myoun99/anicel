import 'camera_instruction.dart';
import 'cut.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'layer_kind.dart';
import 'timeline_repeat.dart';
import 'timesheet_info.dart';
import 'track_se_window.dart';
import 'transition_geometry.dart';

/// What a timesheet column represents on the paper form.
enum TimesheetColumnKind {
  /// A column of the form's left ACTION block — the animation layers land
  /// here in order, headed by their real names; slots without a backing
  /// layer stay blank handwriting space (no placeholder letters).
  action,

  /// A CELL block form column — blank paper space with no printed letters;
  /// its role (cel re-assignment) is still user-undecided.
  cel,

  /// A dialogue/SE column (the S1/S2 slots between the rail and CELL).
  se,

  /// A camera-instruction column.
  camera,
}

/// One cell of a timesheet column (one frame row).
enum TimesheetCellKind {
  /// Nothing on this row (paper stays blank).
  empty,

  /// First row of an uncovered run inside the playback range — the sheet
  /// "X" cell (same rule as the timeline grids: marks continue a run).
  emptyRunStart,

  /// A drawing exposure starts here; [TimesheetCell.label] carries the cel
  /// number (Frame.name, 1-based position fallback — export naming rule).
  drawing,

  /// Covered by the drawing above (the hold line runs through this row).
  held,

  /// An inbetween mark (drawn as the sheet's ○).
  mark,

  /// First row of a REPEAT ghost chain (UI-R10 #6): the painter prints
  /// the notation-language repeat word here instead of re-listing cel
  /// numbers. Display only — the underlying timeline keeps the expanded
  /// 1,2,3,1,2,3 (XDTS/TDTS read that, never these cells).
  repeatStart,

  /// Inside a repeat ghost chain (the repeat guide line runs through).
  repeatSpan,

  /// First row of an END-hold ghost chain on a layer whose display is ONE
  /// cel held from row 1 (UI-R11 #15): prints the notation hold word
  /// (止め) vertically, like [repeatStart].
  holdStart,

  /// A camera keyframe row (camera column only).
  cameraKey,

  /// Between two camera keyframes (the camera column's motion line).
  cameraSpan,

  /// A camera-work instruction span starts here (instruction CAM columns);
  /// [TimesheetCell.label] carries the writing (event text or vocabulary
  /// name), [TimesheetCell.valueA] the A endpoint.
  instructionStart,

  /// Inside an instruction span (the duration line runs through this row).
  instructionSpan,

  /// The instruction span's last covered row (line end tick + B endpoint).
  instructionEnd,
}

class TimesheetCell {
  const TimesheetCell(
    this.kind, {
    this.label,
    this.spanLength,
    this.spanOffset,
    this.markType,
    this.valueA,
    this.valueB,
    this.seName,
  });

  static const TimesheetCell blank = TimesheetCell(TimesheetCellKind.empty);

  final TimesheetCellKind kind;

  /// Cel number for [TimesheetCellKind.drawing] cells; the writing for
  /// [TimesheetCellKind.instructionStart] cells.
  final String? label;

  /// Rows the span covers. Drawing spans set it on the start cell only
  /// (vertical text fitting); instruction spans set it on EVERY covered
  /// row — the painter re-derives the whole mark per row so spans crossing
  /// page halves keep painting.
  final int? spanLength;

  /// This row's distance from its instruction span's start row (instruction
  /// cells only) — with [spanLength] it places the row inside the span's
  /// mark geometry.
  final int? spanOffset;

  /// The span's mark shape from its def (instruction cells only); null
  /// paints as [CameraInstructionMarkType.bar].
  final CameraInstructionMarkType? markType;

  /// The sheet's A → B endpoint values (instruction start cells only; the
  /// painter prints A at the start and B at the end row).
  final String? valueA;
  final String? valueB;

  /// SE drawing start cells only: the entry's speaker/effect name — method
  /// A prints it across the whole start row (accent box + underline, Toei
  /// style) with the dialogue distributing below.
  final String? seName;
}

/// One sheet column: the printed column header plus one cell per document
/// row. Slots without a backing layer hold blank cells — the paper form
/// always shows them.
class TimesheetColumn {
  const TimesheetColumn({
    required this.kind,
    required this.label,
    required this.cells,
    this.layerName,
    this.layerId,
    this.previewCellsBuilder,
    this.crossesCutEnd = false,
    this.spillsInAtStart = false,
  });

  final TimesheetColumnKind kind;

  /// The printed column header: the backing layer's REAL name for
  /// layer-backed slots, 'S1'/'S2'/camera indices for form slots, and empty
  /// for unbacked slots (nothing prints — no placeholder letters).
  final String label;

  /// The backing layer's name (action/SE slots only); null for empty slots.
  final String? layerName;

  /// The backing layer's id (action/SE/instruction slots) — the timeline
  /// drag preview overlay matches its per-layer previews to columns by
  /// this (UI-R9 #7).
  final LayerId? layerId;

  final List<TimesheetCell> cells;

  /// Re-derives this column's cells from a substituted layer — the
  /// timeline drag-preview path (UI-R18 #7): baked at document build so
  /// the painter can preview ANY layer-backed column kind (action, SE,
  /// camera instruction) without knowing each kind's cell recipe. Null
  /// for unbacked slots.
  final List<TimesheetCell> Function(Layer layer)? previewCellsBuilder;

  /// SE columns: whether a sound starting inside this cut runs past its
  /// end — the timeline's `~` continuation mark, printed on the sheet at
  /// the cut-end line (SE globalization round). Pure display.
  final bool crossesCutEnd;

  /// SE columns: whether a sound from an earlier cut spills into row 0 —
  /// the timeline's start-side `~`, printed at the column's first row.
  final bool spillsInAtStart;
}

/// One paper page: [frameCount] rows starting at [startFrame], laid out in
/// two side-by-side halves of [TimesheetDocument.halfFrameCount] rows.
class TimesheetPage {
  const TimesheetPage({
    required this.index,
    required this.startFrame,
    required this.frameCount,
  });

  final int index;
  final int startFrame;
  final int frameCount;
}

/// The timesheet as a pure document view-model: what the sheet painter
/// draws and what the sheet exporters (XDTS, auto-sheet, ...) read. Built
/// from the cut's unified timeline model; carries no widget or session
/// references, so a snapshot can cross windows/isolates later.
///
/// The column set follows the Japanese paper form: the ACTION block carries
/// the onTimesheet animation layers (headed by their real names, leftover
/// slots blank), then the frame rail, S1/S2 dialogue-SE slots, a blank CELL
/// block and the camera columns — fixed slots that stay blank when
/// unbacked, with no placeholder letters anywhere.
class TimesheetDocument {
  TimesheetDocument._({
    required this.title,
    required this.episode,
    required this.scene,
    required this.artist,
    required this.memoText,
    required this.visibleHeaderFields,
    required this.exposureBarThreshold,
    required this.seEmptyFill,
    required this.cutName,
    required this.fps,
    required this.playbackFrameCount,
    this.transitionHandles = CutTransitionHandles.none,
    required this.pageFrameCount,
    required this.columns,
    required this.pages,
  });

  factory TimesheetDocument.fromCut({
    required Cut cut,
    required String projectName,
    required int fps,
    TimesheetInfo info = TimesheetInfo.empty,
    int pageSeconds = 6,
    int actionColumnCount = 8,
    int celColumnCount = 8,
    int seColumnCount = 2,
    int cameraColumnCount = 2,
    CameraInstructionDef? Function(String instructionId)? instructionDefById,
    // TRACK-owned SE rows (global-frame timelines) shown windowed to this
    // cut; [cutStartFrame] is the cut's global start on its track.
    List<Layer> trackSeLayers = const [],
    int cutStartFrame = 0,
    // The track's transition spans on the GLOBAL axis. Only the ones that
    // CROSS one of this cut's boundaries matter, and what they buy the
    // sheet is のりしろ: the frames drawn outside the conte 尺 so the two
    // ramps of an O.L have something to cross-fade.
    List<TransitionSpan> transitionSpans = const [],
    // DATA-sheet cells (UI-R24 #1): print the EXPORT-SOURCE data instead
    // of the notation shorthand — every ghost chain (repeat word, 止め,
    // front-hold relocation) renders verbatim as the concrete per-entry
    // cel labels XDTS/TDTS write. Holds stay holds (labels never tile
    // down held rows).
    bool dataSheet = false,
  }) {
    if (fps <= 0) {
      throw ArgumentError.value(fps, 'fps', 'fps must be positive.');
    }
    if (pageSeconds <= 0) {
      throw ArgumentError.value(
        pageSeconds,
        'pageSeconds',
        'pageSeconds must be positive.',
      );
    }

    final playbackFrameCount = cut.duration < 1 ? 1 : cut.duration;
    // のりしろ. The conte 尺 (and so the cut block, and so the total) never
    // moves — the sheet just has more rows to fill than the cut is long,
    // which is exactly what 「シートは必ずここまで記入する」 asks for.
    //
    // Both sides show it at the TAIL (user's rule): the blue line answers
    // "how much do I draw", not "where does the extra sit", and the mark on
    // the transition row answers where.
    final handles = cutTransitionHandles(
      cutStart: cutStartFrame,
      cutEnd: cutStartFrame + playbackFrameCount,
      spans: transitionSpans,
    );
    final drawnFrameCount = handles.drawnFrames(playbackFrameCount);
    final pageFrameCount = pageSeconds * fps;
    final pageCount =
        ((drawnFrameCount + pageFrameCount - 1) ~/ pageFrameCount).clamp(
          1,
          1 << 20,
        );
    final rowCount = pageCount * pageFrameCount;

    // ACTION-block cel columns: the sheet's kind gate is the one predicate
    // (image rows answer false — a nameless held picture prints nothing).
    final animationLayers = [
      for (final layer in cut.layers)
        if (layer.kind == LayerKind.animation && layer.onTimesheet) layer,
    ];
    // SE rows are track-owned: window their global timelines to this cut
    // (spill-in synthesizes a display block). Cut-owned SE layers remain
    // for legacy fixtures.
    final seWindow = TrackSeWindow(
      cutStartFrame: cutStartFrame,
      cutDurationFrames: cut.duration,
    );
    // The display window is open-ended on the right now (SE globalization
    // — the timeline's runway shows the neighbours' sounds), but a
    // printed page is no runway: entries starting at or past the cut end
    // stay off the sheet, crossing blocks keep their true length and the
    // sheet marks them with the timeline's `~`. One clip for every
    // cut-scoped export ([clipLayerStartsBefore] — the XDTS sheet reads
    // the same projection).
    Layer clipToSheet(Layer displayClone) =>
        clipLayerStartsBefore(displayClone, playbackFrameCount);
    bool crossesCutEnd(Layer clone) {
      for (final entry in clone.timeline.entries) {
        if (entry.value.isDrawing &&
            !entry.value.ghost &&
            entry.key < playbackFrameCount &&
            entry.key + (entry.value.length ?? 1) > playbackFrameCount) {
          return true;
        }
      }
      return false;
    }

    final seSlots = [
      for (final layer in cut.layers)
        if (layer.kind == LayerKind.se && layer.onTimesheet)
          (layer: layer, crosses: crossesCutEnd(layer), spills: false),
      for (final layer in trackSeLayers)
        if (layer.onTimesheet)
          () {
            final clone = clipToSheet(seWindow.displayLayer(layer));
            return (
              layer: clone,
              crosses: crossesCutEnd(clone),
              spills: seWindow.spillInBlock(layer) != null,
            );
          }(),
    ];
    final instructionLayers = [
      for (final layer in cut.layers)
        if (layer.kind == LayerKind.instruction && layer.onTimesheet) layer,
    ];
    // The CAM keyframe column obeys the camera layer's timesheet toggle
    // (unified layer controls); toggled off it stays printed blank form
    // space, like an unbacked slot.
    final cameraOnSheet = cut.layers.cameraLayer?.onTimesheet ?? true;
    // CAM slots: the camera-keyframe column plus one per instruction row.
    final cameraSlotCount = 1 + instructionLayers.length > cameraColumnCount
        ? 1 + instructionLayers.length
        : cameraColumnCount;

    final columns = <TimesheetColumn>[
      // Animation layers fill the ACTION block in order, headed by their
      // real names; unbacked slots stay blank handwriting space.
      for (
        var slot = 0;
        slot < _slotCount(actionColumnCount, animationLayers);
        slot += 1
      )
        TimesheetColumn(
          kind: TimesheetColumnKind.action,
          label: slot < animationLayers.length
              ? animationLayers[slot].name
              : '',
          layerName: slot < animationLayers.length
              ? animationLayers[slot].name
              : null,
          layerId: slot < animationLayers.length
              ? animationLayers[slot].id
              : null,
          cells: slot < animationLayers.length
              ? timesheetLayerCells(
                  layer: animationLayers[slot],
                  rowCount: rowCount,
                  playbackFrameCount: playbackFrameCount,
                  dataSheet: dataSheet,
                )
              : _blankCells(rowCount),
          previewCellsBuilder: slot < animationLayers.length
              ? (layer) => timesheetLayerCells(
                  layer: layer,
                  rowCount: rowCount,
                  playbackFrameCount: playbackFrameCount,
                  dataSheet: dataSheet,
                )
              : null,
        ),
      for (var slot = 0; slot < _slotCount(seColumnCount, seSlots); slot += 1)
        TimesheetColumn(
          kind: TimesheetColumnKind.se,
          // The layer's stored name — the same label the timeline and
          // storyboard rows show (W3 ordering unification).
          label: slot < seSlots.length
              ? seSlots[slot].layer.name
              : 'S${slot + 1}',
          layerName: slot < seSlots.length ? seSlots[slot].layer.name : null,
          layerId: slot < seSlots.length ? seSlots[slot].layer.id : null,
          crossesCutEnd: slot < seSlots.length && seSlots[slot].crosses,
          spillsInAtStart: slot < seSlots.length && seSlots[slot].spills,
          cells: slot < seSlots.length
              ? timesheetLayerCells(
                  layer: seSlots[slot].layer,
                  rowCount: rowCount,
                  playbackFrameCount: playbackFrameCount,
                  // SE columns stay blank between entries on paper — no X;
                  // the speaker name rides along for the method-A name row.
                  markEmptyRuns: false,
                  includeSeNames: true,
                  dataSheet: dataSheet,
                )
              : _blankCells(rowCount),
          // SE drags preview live (UI-R18 #7): the timeline publishes
          // the DISPLAY clone under the same id — open-ended now, so the
          // sheet's own end clip applies before the recipe.
          previewCellsBuilder: slot < seSlots.length
              ? (layer) => timesheetLayerCells(
                  layer: clipToSheet(layer),
                  rowCount: rowCount,
                  playbackFrameCount: playbackFrameCount,
                  markEmptyRuns: false,
                  includeSeNames: true,
                  dataSheet: dataSheet,
                )
              : null,
        ),
      // The CELL block mirrors the ACTION layers' NAMES as its headers
      // (UI-R10 #10) — the cel re-assignment content stays blank
      // handwriting space.
      for (var slot = 0; slot < celColumnCount; slot += 1)
        TimesheetColumn(
          kind: TimesheetColumnKind.cel,
          label: slot < animationLayers.length
              ? animationLayers[slot].name
              : '',
          cells: _blankCells(rowCount),
        ),
      // CAM block: slot 0 keeps the camera transform keyframes; the
      // instruction rows (CAM 2 …) follow in layer order, growing the block
      // past the fixed count when a cut carries more.
      for (var slot = 0; slot < cameraSlotCount; slot += 1)
        TimesheetColumn(
          kind: TimesheetColumnKind.camera,
          label: '${slot + 1}',
          layerName: slot >= 1 && slot - 1 < instructionLayers.length
              ? instructionLayers[slot - 1].name
              : null,
          // Instruction slots carry their layer id so edge drags preview
          // live on the sheet (UI-R18 #7), like action/SE columns.
          layerId: slot >= 1 && slot - 1 < instructionLayers.length
              ? instructionLayers[slot - 1].id
              : null,
          cells: slot == 0
              ? (cameraOnSheet
                    ? _cameraCells(cut: cut, rowCount: rowCount)
                    : _blankCells(rowCount))
              : slot - 1 < instructionLayers.length
              ? _instructionCells(
                  layer: instructionLayers[slot - 1],
                  rowCount: rowCount,
                  defById: instructionDefById,
                )
              : _blankCells(rowCount),
          previewCellsBuilder: slot >= 1 && slot - 1 < instructionLayers.length
              ? (layer) => _instructionCells(
                  layer: layer,
                  rowCount: rowCount,
                  defById: instructionDefById,
                )
              : null,
        ),
    ];

    return TimesheetDocument._(
      title: info.title.isEmpty ? projectName : info.title,
      episode: info.episode,
      scene: info.scene,
      artist: info.artist,
      memoText: cut.metadata.note,
      visibleHeaderFields: List.unmodifiable(info.visibleFields),
      exposureBarThreshold: info.exposureBarThreshold,
      seEmptyFill: info.seEmptyFill,
      cutName: cut.name,
      fps: fps,
      playbackFrameCount: playbackFrameCount,
      transitionHandles: handles,
      pageFrameCount: pageFrameCount,
      columns: List.unmodifiable(columns),
      pages: List.unmodifiable([
        for (var page = 0; page < pageCount; page += 1)
          TimesheetPage(
            index: page,
            startFrame: page * pageFrameCount,
            frameCount: pageFrameCount,
          ),
      ]),
    );
  }

  /// Sheet-header text: production title (project name unless overridden),
  /// episode label, scene label and artist name from [TimesheetInfo].
  final String title;
  final String episode;
  final String scene;
  final String artist;

  /// The cut's Direction memo (the cut note) printed in the memo band —
  /// per-cut data, editable in place on the sheet. Instruction shorthand
  /// lines land HERE (auto-written once at creation, R5-⑥) instead of a
  /// derived read-only list.
  final String memoText;

  /// The ACTION hold-bar setting mirrored from [TimesheetInfo]
  /// (null = bars off, N = bars from the (N+1)th comma of N+ holds).
  final int? exposureBarThreshold;

  /// Whether SE columns wash their empty stretches light gray (mirrored
  /// from [TimesheetInfo.seEmptyFill]).
  final bool seEmptyFill;

  /// The header boxes the form prints, in printing order (the user hides
  /// boxes per project via [TimesheetInfo.hiddenFields]).
  final List<TimesheetHeaderField> visibleHeaderFields;

  final String cutName;
  final int fps;

  /// The cut's playback length — its CONTE 尺. Rows beyond
  /// [drawnFrameCount] (page padding) stay blank.
  final int playbackFrameCount;

  /// The のりしろ this cut owes to the transitions that cross its
  /// boundaries. Empty unless a transition span straddles one.
  final CutTransitionHandles transitionHandles;

  /// How many rows the animator actually fills: the conte 尺 plus のりしろ.
  /// This is the parenthesised number on the sheet — `2+0 (2+12)` — and the
  /// row the blue のりしろ end line is drawn at.
  ///
  /// 撮ま!: 「シートは必ずここまで記入する（止めやリピートでも省略しては
  /// いけない）」. Leaving it at the conte 尺 is the documented way to end up
  /// with 尺変更 retakes.
  int get drawnFrameCount =>
      transitionHandles.drawnFrames(playbackFrameCount);

  /// Rows per paper page (pageSeconds × fps).
  final int pageFrameCount;

  final List<TimesheetColumn> columns;
  final List<TimesheetPage> pages;

  /// Rows per page HALF: the paper page splits into two side-by-side
  /// columns of this many rows (the second half takes any odd remainder).
  int get halfFrameCount => pageFrameCount ~/ 2;

  /// Total document rows (pages × pageFrameCount).
  int get rowCount => pages.length * pageFrameCount;

  /// The cut duration in the sheet's `초+コマ` notation (e.g. '2+12').
  ///
  /// This is the CONTE 尺 — the number that sums to the running time, and
  /// the one 撮ま! insists goes in the 尺 column: 「O.Lの中心までの尺を記入
  /// する（のりしろを含むと総尺計算の際に間違いのもとになる）」.
  String get durationLabel => _frameLabel(playbackFrameCount);

  /// What the animator actually draws, in the same notation — the
  /// parenthesised half of `2+0 (2+12)`. Null when there is no のりしろ, so
  /// a sheet without transitions prints one number as it always did.
  String? get drawnDurationLabel =>
      transitionHandles.isEmpty ? null : _frameLabel(drawnFrameCount);

  String _frameLabel(int frames) => '${frames ~/ fps}+${frames % fps}';

  static int _slotCount(int fixedSlots, List<Object> layers) {
    return layers.length > fixedSlots ? layers.length : fixedSlots;
  }

  static List<TimesheetCell> _blankCells(int rowCount) {
    return List<TimesheetCell>.filled(rowCount, TimesheetCell.blank);
  }

  /// Derives one layer's column cells from the unified timeline model:
  /// drawing starts carry the cel number, covered rows hold, block-owned
  /// inbetween dots (breakdownOffsets) show ● on their held rows, and the
  /// FIRST row of each uncovered run inside the playback range gets the X
  /// (same rule as the timeline grids). Public as [timesheetLayerCells]
  /// so the drag preview overlay derives one column from a preview layer
  /// without rebuilding the document (UI-R9 #7).
  static List<TimesheetCell> _layerCells({
    required Layer layer,
    required int rowCount,
    required int playbackFrameCount,
    bool markEmptyRuns = true,
    bool includeSeNames = false,
    bool dataSheet = false,
  }) {
    final cells = List<TimesheetCell>.filled(rowCount, TimesheetCell.blank);

    final labelsByFrameId = <FrameId, String>{
      // The sheet writes the frame NAME verbatim; unnamed cels print the
      // in-between division mark — never an invented number (R5-④, same
      // glyph the mark rows use).
      for (final frame in layer.frames) frame.id: frame.name ?? '○',
    };
    final seNamesByFrameId = <FrameId, String?>{
      if (includeSeNames)
        for (final frame in layer.frames) frame.id: frame.seName,
    };

    // Drawing coverage straight from the timeline entries; the block's
    // breakdown offsets overlay their held rows as ● cells. GHOST chains
    // print simplified (UI-R10 #6/#11): repeat = the notation repeat word
    // once + a guide line, END holds print nothing, FRONT holds print the
    // held cel on their first row only — the timeline keeps the expanded
    // data (XDTS/TDTS export reads that, never these display cells).
    final covered = List<bool>.filled(rowCount, false);
    final entries = layer.timeline.entries.toList(growable: false);
    // The 止め condition (UI-R11 #15): the layer DISPLAYS as one cel held
    // from row 1 — a single authored block whose visual start is frame 0
    // (its own start, or a front-hold lead-in reaching 0).
    var authoredBlockCount = 0;
    for (final entry in entries) {
      if (!entry.value.ghost) {
        authoredBlockCount += 1;
      }
    }
    final displaysFromRowZero = entries.isNotEmpty && entries.first.key == 0;
    final singleCelDisplay = authoredBlockCount == 1 && displaysFromRowZero;
    // Front-hold relocation (UI-R11 #6 → UI-R12 #17): the sheet's DATA
    // moves the cel to the chain's first row FOR REAL — chain + anchor
    // block fuse into ONE run, and the block's own start stops being a
    // drawing cell entirely (XDTS-style output reads these cells; the
    // TIMELINE keeps the authored position untouched).
    final mergedBlockStarts = <int>{};
    for (var index = 0; index < entries.length; index += 1) {
      final start = entries[index].key;
      if (start >= rowCount) {
        continue;
      }
      final exposure = entries[index].value;

      // DATA sheet (UI-R24 #1): ghost REPEAT chains skip the notation
      // shorthand and fall through to the plain-block path below — every
      // derived entry prints its concrete cel label at its own start,
      // the value-change data XDTS/TDTS write.
      //
      // HOLD chains do NOT (R26 #26): a hold is the SAME cel exposed
      // longer, so its real data is one drawing at the run's first row
      // and held rows after it. Printing the label again per ghost entry
      // made one cel look like two (or three, with a front + end hold).
      final ghostHold =
          exposure.ghost &&
          runBehaviorOwningGhostAt(layer, start)?.mode ==
              TimelineRunEdgeMode.hold;
      if (exposure.ghost && (!dataSheet || ghostHold)) {
        // The contiguous chain the same behavior owns.
        final ownerId = exposure.ghostOwnerId;
        var chainEndExclusive = start + exposure.length!;
        var last = index;
        while (last + 1 < entries.length &&
            entries[last + 1].value.ghost &&
            entries[last + 1].value.ghostOwnerId == ownerId &&
            entries[last + 1].key == chainEndExclusive) {
          last += 1;
          chainEndExclusive = entries[last].key + entries[last].value.length!;
        }
        final rowsEnd = chainEndExclusive.clamp(0, rowCount);
        for (var row = start; row < rowsEnd; row += 1) {
          covered[row] = true; // Ghost coverage suppresses the X run.
        }
        final behavior = runBehaviorOwningGhostAt(layer, start);
        if (behavior?.mode == TimelineRunEdgeMode.hold) {
          if (behavior!.side == TimelineRunEdgeSide.start) {
            // Front hold: the cel moves to the first row FOR REAL
            // (UI-R12 #17) — one run from here through the anchor
            // block's last frame, held straight across the authored
            // position (breakdown ● keep their absolute rows).
            final blockIndex = entries.indexWhere(
              (entry) => !entry.value.ghost && entry.key == chainEndExclusive,
            );
            final block = blockIndex == -1 ? null : entries[blockIndex].value;
            final mergedEndExclusive = block == null
                ? rowsEnd
                : (chainEndExclusive + block.length!).clamp(0, rowCount);
            final runLength = mergedEndExclusive - start;
            cells[start] = TimesheetCell(
              TimesheetCellKind.drawing,
              label: labelsByFrameId[exposure.frameId] ?? '?',
              spanLength: runLength,
            );
            for (var row = start + 1; row < mergedEndExclusive; row += 1) {
              final blockOffset = row - chainEndExclusive;
              cells[row] = TimesheetCell(
                block != null &&
                        blockOffset >= 0 &&
                        block.hasBreakdownAt(blockOffset)
                    ? TimesheetCellKind.mark
                    : TimesheetCellKind.held,
                spanLength: runLength,
                spanOffset: row - start,
              );
              covered[row] = true;
            }
            if (block != null) {
              mergedBlockStarts.add(chainEndExclusive);
            }
          } else if (dataSheet) {
            // END hold, DATA sheet (R26 #26): no second cel — the owning
            // run simply runs longer. Find the drawing cell that owns
            // these rows (a front-hold merge may have relocated it) and
            // stretch its span across the held rows.
            var runStart = start - 1;
            while (runStart > 0 &&
                cells[runStart].kind != TimesheetCellKind.drawing) {
              runStart -= 1;
            }
            if (cells[runStart].kind != TimesheetCellKind.drawing) {
              runStart = start;
            }
            final runLength = rowsEnd - runStart;
            final owner = cells[runStart];
            if (owner.kind == TimesheetCellKind.drawing) {
              cells[runStart] = TimesheetCell(
                TimesheetCellKind.drawing,
                label: owner.label,
                spanLength: runLength,
                seName: owner.seName,
              );
            }
            for (var row = runStart + 1; row < rowsEnd; row += 1) {
              final prior = cells[row];
              cells[row] = TimesheetCell(
                // Breakdown dots already written for the block's own
                // rows keep their glyph; the hold rows are plain holds.
                row < start && prior.kind == TimesheetCellKind.mark
                    ? TimesheetCellKind.mark
                    : TimesheetCellKind.held,
                spanLength: runLength,
                spanOffset: row - runStart,
              );
              covered[row] = true;
            }
          } else if (singleCelDisplay) {
            // One cel held from row 1: the hold word prints RIGHT AFTER
            // the cel's first row (UI-R25 #1) — 1止め, never 1--止め: the
            // word's span swallows the block's own held rows (already
            // written by the block pass; row order puts the block first)
            // and runs to the cut end, the rest staying blank paper.
            const wordStart = 1;
            if (wordStart < rowsEnd) {
              cells[wordStart] = TimesheetCell(
                TimesheetCellKind.holdStart,
                spanLength: rowsEnd - wordStart,
              );
              for (var row = wordStart + 1; row < rowsEnd; row += 1) {
                cells[row] = TimesheetCell.blank;
              }
            }
          }
        } else if (behavior?.side == TimelineRunEdgeSide.start) {
          // FRONT repeats write their GHOST FRAMES verbatim (UI-R14 #3):
          // the repeat word never notates a front repeat — the lead-in
          // prints its expanded cel numbers exactly like authored cells.
          for (var chainIndex = index; chainIndex <= last; chainIndex += 1) {
            final ghostStart = entries[chainIndex].key;
            if (ghostStart >= rowCount) {
              continue;
            }
            final ghostExposure = entries[chainIndex].value;
            final ghostEnd = (ghostStart + ghostExposure.length!).clamp(
              0,
              rowCount,
            );
            cells[ghostStart] = TimesheetCell(
              TimesheetCellKind.drawing,
              label: labelsByFrameId[ghostExposure.frameId] ?? '?',
              spanLength: ghostEnd - ghostStart,
            );
            for (var row = ghostStart + 1; row < ghostEnd; row += 1) {
              cells[row] = TimesheetCell(
                ghostExposure.hasBreakdownAt(row - ghostStart)
                    ? TimesheetCellKind.mark
                    : TimesheetCellKind.held,
                spanLength: ghostEnd - ghostStart,
                spanOffset: row - ghostStart,
              );
            }
          }
        } else {
          cells[start] = TimesheetCell(
            TimesheetCellKind.repeatStart,
            // The convention (UI-R13 #4): the repeat's first row writes
            // the CEL it restarts on; the word begins on the next row.
            label: labelsByFrameId[exposure.frameId] ?? '?',
            spanLength: rowsEnd - start,
          );
          for (var row = start + 1; row < rowsEnd; row += 1) {
            cells[row] = TimesheetCell(
              TimesheetCellKind.repeatSpan,
              spanLength: rowsEnd - start,
              spanOffset: row - start,
            );
          }
        }
        index = last;
        continue;
      }

      // A front-hold merge already wrote this block's rows as the tail of
      // its relocated run (UI-R12 #17) — no second drawing start.
      if (mergedBlockStarts.contains(start)) {
        continue;
      }

      final endExclusive = (start + exposure.length!).clamp(0, rowCount);
      cells[start] = TimesheetCell(
        TimesheetCellKind.drawing,
        label: labelsByFrameId[exposure.frameId] ?? '?',
        spanLength: endExclusive - start,
        seName: seNamesByFrameId[exposure.frameId],
      );
      covered[start] = true;
      for (var row = start + 1; row < endExclusive; row += 1) {
        // Held rows know their place in the span so the painter can gate
        // the ACTION hold bar per the exposure-bar setting (drawn from the
        // (N+1)th comma of N+ holds only).
        cells[row] = TimesheetCell(
          exposure.hasBreakdownAt(row - start)
              ? TimesheetCellKind.mark
              : TimesheetCellKind.held,
          spanLength: endExclusive - start,
          spanOffset: row - start,
        );
        covered[row] = true;
      }
    }

    // X only at the first uncovered row of each run, only inside the
    // playback range.
    if (!markEmptyRuns) {
      return cells;
    }
    var inEmptyRun = false;
    for (var row = 0; row < playbackFrameCount && row < rowCount; row += 1) {
      if (covered[row]) {
        inEmptyRun = false;
        continue;
      }
      if (!inEmptyRun) {
        cells[row] = const TimesheetCell(TimesheetCellKind.emptyRunStart);
        inEmptyRun = true;
      }
    }

    return cells;
  }

  /// An instruction row's CAM column: each event prints its writing (free
  /// text, vocabulary-name fallback) at the start with the A endpoint, its
  /// def's mark through the covered rows (straight duration line, FI/FO
  /// wedge or O.L bowtie) and the B endpoint on the last one — the paper
  /// sheet's camera-work notation. Every covered row carries the span's
  /// mark geometry so the painter can re-derive it row by row.
  static List<TimesheetCell> _instructionCells({
    required Layer layer,
    required int rowCount,
    CameraInstructionDef? Function(String instructionId)? defById,
  }) {
    final cells = List<TimesheetCell>.filled(rowCount, TimesheetCell.blank);
    for (final entry in layer.instructions.entries) {
      final start = entry.key;
      if (start >= rowCount) {
        continue;
      }
      final event = entry.value;
      final endExclusive = (start + event.length).clamp(0, rowCount);
      final spanLength = endExclusive - start;
      final markType = defById?.call(event.instructionId)?.markType;
      cells[start] = TimesheetCell(
        TimesheetCellKind.instructionStart,
        label: event.displayLabel(defById?.call(event.instructionId)),
        spanLength: spanLength,
        spanOffset: 0,
        markType: markType,
        valueA: event.valueA,
        valueB: event.valueB,
      );
      for (var row = start + 1; row < endExclusive; row += 1) {
        cells[row] = TimesheetCell(
          row == endExclusive - 1
              ? TimesheetCellKind.instructionEnd
              : TimesheetCellKind.instructionSpan,
          // The writing rides EVERY covered row (like the mark geometry):
          // the painter prints it on the span's middle row, which may sit
          // in another page half than the start.
          label: cells[start].label,
          spanLength: spanLength,
          spanOffset: row - start,
          markType: markType,
          valueB: row == endExclusive - 1 ? event.valueB : null,
        );
      }
    }
    return cells;
  }

  /// The first camera column: keyframe rows with motion lines between
  /// successive keyframes.
  static List<TimesheetCell> _cameraCells({
    required Cut cut,
    required int rowCount,
  }) {
    final cells = List<TimesheetCell>.filled(rowCount, TimesheetCell.blank);
    final keyframeRows = [
      for (final frame in cut.camera.keyframes.keys)
        if (frame < rowCount) frame,
    ];
    for (var index = 0; index < keyframeRows.length; index += 1) {
      final row = keyframeRows[index];
      cells[row] = TimesheetCell(
        TimesheetCellKind.cameraKey,
        label: '${index + 1}',
      );
      if (index + 1 < keyframeRows.length) {
        final nextRow = keyframeRows[index + 1];
        for (var span = row + 1; span < nextRow; span += 1) {
          cells[span] = const TimesheetCell(TimesheetCellKind.cameraSpan);
        }
      }
    }
    return cells;
  }
}

/// One memo-band line for an instruction event — the sheet shorthand the
/// user writes by hand: `<A><mark><B> <name> <memo>`, e.g. 'A⋈ O.L' or
/// 'C⋈D O.L カットO.L' (a single space before the memo — R4 dropped the
/// parentheses). The mark glyph mirrors the def's markType (⋈ = the O.L
/// bowtie, → = the bar); blank parts simply drop out.
String timesheetMemoInstructionLine(
  InstructionEvent event,
  CameraInstructionDef? def,
) {
  final markGlyph =
      (def?.markType ?? CameraInstructionMarkType.bar) ==
          CameraInstructionMarkType.ol
      ? '⋈'
      : '→';
  final endpoints = '${event.valueA ?? ''}$markGlyph${event.valueB ?? ''}';
  final memo = event.memo;
  final label =
      '${event.displayLabel(def)}${memo == null || memo.isEmpty ? '' : ' $memo'}';
  return label.isEmpty ? endpoints : '$endpoints $label';
}

/// One layer's sheet-column cells, derived straight from the (possibly
/// PREVIEW) layer — the drag overlay's per-column source (UI-R9 #7). The
/// same derivation [TimesheetDocument.fromCut] uses for its action/SE
/// columns.
List<TimesheetCell> timesheetLayerCells({
  required Layer layer,
  required int rowCount,
  required int playbackFrameCount,
  bool markEmptyRuns = true,
  bool includeSeNames = false,
  bool dataSheet = false,
}) {
  return TimesheetDocument._layerCells(
    layer: layer,
    rowCount: rowCount,
    playbackFrameCount: playbackFrameCount,
    markEmptyRuns: markEmptyRuns,
    includeSeNames: includeSeNames,
    dataSheet: dataSheet,
  );
}
