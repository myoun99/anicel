import '../../models/app_input_settings.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/new_row_placement.dart';
import '../../models/storyboard_coverage.dart' show storyboardDivisionKeys;
import '../../models/timeline_repeat.dart' show rederiveRunBehaviors;
import '../../services/commands/cut_command_input_planner.dart'
    show plannedAddLayerCommand;
import '../../services/editing/default_layer_helpers.dart'
    show bornRowOfKind, coveringCelFor;
import '../../services/command.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../services/project_repository.dart'
    show cutWithLayerInserted;
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'frame_verbs.dart';
import 'layer_id_mint.dart';
import '../storyboard_layer_policy.dart' show storyboardLayerForCut;

/// The AUTO FRAME FOR A STROKE — a stroke landing on an empty cell makes
/// the drawing the stroke needs, and the frame it made is taken or flushed
/// when the stroke ends — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and five
/// session members touched. It names the roles it needs in its constructor.
class AutoFrameForStroke {
  AutoFrameForStroke({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required LayerIdMint layerIds,
    required ActiveCutControllers controllers,
    required FrameVerbs frameVerbs,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _layerIds = layerIds,
       _controllers = controllers,
       _frameVerbs = frameVerbs;

  final FrameVerbs _frameVerbs;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final LayerIdMint _layerIds;
  final ActiveCutControllers _controllers;

  /// Whether a stroke on an empty cell makes what it needs — the canvas's
  /// 「프레임 자동 생성」, which the conte's pictures follow too (유저 답
  /// conte-drawing-target-Q2 「토글을 따른다 (캔버스와 한 법)」).
  bool get autoCreates => AppInput.settings.value.autoCreateFrameOnDraw;

  /// 🚨THE CEL A PICTURE'S FIRST STROKE WOULD MAKE on [cut]'s conte, named
  /// before it exists — [frameIdForNextCel], said of a conte cell with no
  /// block. A conte picture draws into its block's cel, and such a cell has
  /// none: a cut with no conte row, or one whose row lost every block
  /// (유저 답 conte-drawing-target-Q2: 「콘티 레이어(없으면) · 블록이 생기고
  /// 그대로 그려진다」). Its picture draws into the cel this names, and the
  /// stroke's landing makes it ([addConteCel]) — so the pen that heard the
  /// press already stands on the cel it makes.
  ///
  /// [cut] is what the picture draws through: with the row it makes, when
  /// it has none — the live stroke stands in the composite where that row
  /// will; as it is, when its row is there to stand in.
  ///
  /// Null when [cut] has a block to draw on.
  ({Cut cut, Layer layer, FrameId frameId})? conteCelFor(Cut cut) {
    final plan = _conteCelPlan(cut);
    if (plan == null) {
      return null;
    }
    final (:layer, :index) = plan;
    return (
      cut: index == null ? cut : cutWithLayerInserted(cut, layer, index),
      layer: layer,
      frameId: frameIdForNextCel(layer.id),
    );
  }

  /// The conte row a first stroke on [cut] leaves, and where it goes in the
  /// stack — null [index] for the row [cut] has, covered in place.
  ///
  /// A cut with no row gets one on top, where a row made with nothing
  /// selected goes ([newRowPlacement]): [cut] is not the cut the canvas
  /// stands on, so it has no active row to go above. A row with no block
  /// is covered by one cel, as a row is born ([coveringCelFor]).
  ({Layer layer, int? index})? _conteCelPlan(Cut cut) {
    final row = storyboardLayerForCut(cut);
    if (row == null) {
      final layerId = _nextConteRow.putIfAbsent(cut.id, _layerIds.mint);
      final placement = newRowPlacement(cut.layers, cut.layers.length);
      final born = bornRowOfKind(
        LayerKind.storyboard,
        layerId: layerId,
        coveringFrameId: () => frameIdForNextCel(layerId),
        cut: cut,
      );
      return (
        layer: placement.folderId == null
            ? born
            : born.copyWith(folderId: placement.folderId),
        index: placement.index,
      );
    }
    if (storyboardDivisionKeys(
      timeline: row.timeline,
      cutDuration: cut.duration,
    ).isNotEmpty) {
      return null;
    }
    final cel = coveringCelFor(
      frameId: frameIdForNextCel(row.id),
      cutDuration: cut.duration,
    );
    return (
      layer: row.copyWith(
        frames: [...row.frames, cel.frame],
        timeline: cel.timeline,
      ),
      index: null,
    );
  }

  final Map<CutId, LayerId> _nextConteRow = <CutId, LayerId>{};

  /// Makes the cel [conteCelFor] names on [cut] — its own undo step, until
  /// the stroke that made it folds it in with the stroke's.
  ///
  /// ⛔It selects nothing: the cel joins a cut the canvas may not stand on,
  /// and a drawing on the conte moves no focus (conte-drawing-target ①).
  void addConteCel(Cut cut) {
    final plan = _conteCelPlan(cut);
    if (plan == null) {
      return;
    }
    final (:layer, :index) = plan;
    _nextConteRow.remove(cut.id);
    _nextCel.remove(layer.id);
    _project.historyManager.execute(switch (index) {
      null => UpdateLayerTimelineCommand(
        repository: _project.repository,
        before: storyboardLayerForCut(cut)!,
        after: rederiveRunBehaviors(layer, cutFrameCount: cut.duration),
      ),
      final index => plannedAddLayerCommand(
        repository: _project.repository,
        cutId: cut.id,
        layer: layer,
        insertionIndex: index,
      ),
    });
    _changes.notifyChanged();
  }

  /// 🚨I-10 — THE BLOCK A PEN-DOWN MADE, waiting to be undone WITH the
  /// stroke it was made for.
  ///
  /// 유저 2026-08-30, on the undo boundary: 「답은 추천대로」 = **merged**.
  /// One stroke on an empty cell is ONE undo, and both halves go together.
  ///
  /// ⛔It is held rather than pushed because the two halves happen at
  /// different MOMENTS — see `createDrawingFrameCommandForLayer`. Nothing
  /// else may push history between the down and the up, or this lands in
  /// the wrong place; the brush host is the only caller and it holds the
  /// pointer for that whole time.
  Command? _autoFrameForStroke;

  /// Whether a press on the cell under the playhead would MAKE a block
  /// rather than be refused (I-10).
  ///
  /// ⛔Asks `canCreateDrawingAtCurrentFrame`, which already knows about
  /// synced attaches, single-cel rows and media references — the auto path
  /// must refuse everywhere the manual button does, or the toggle becomes a
  /// second answer to 「can this row take a cel」.
  bool get canAutoCreateFrameForStroke =>
      autoCreates &&
      _autoFrameForStroke == null &&
      _frameVerbs.canCreateDrawingAtCurrentFrame;

  /// 🚨F-171 — THE CEL A PRESS ON [layerId] WOULD MAKE, named before it
  /// exists.
  ///
  /// 유저 (F-171): 「앱의 초기값 상태에서 프레임 자동생성 버튼 누르고 선
  /// 그으면 그 가장 처음 상태만 선이 안그어짐. 블록은 생기는데. … 다른 규칙
  /// 두지말고 법 완벽통일」.
  ///
  /// The canvas can only draw a press it heard, and it hears a press only
  /// while its editing view is mounted — which needs an editing stack keyed
  /// to a cel. Before anything was ever drawn there is no cel to key it to,
  /// so the host stands the stack on THIS name, and the press makes exactly
  /// this cel: the view that heard the press is already standing on it.
  /// ↩️Until then the host fell back to a blank canvas, and the one press
  /// made before any stack existed made its block and drew nothing — the
  /// exception I-10 wrote down instead of closing.
  FrameId frameIdForNextCel(LayerId layerId) =>
      _nextCel.putIfAbsent(layerId, () => _frameIds.mintFrameId(layerId));

  final Map<LayerId, FrameId> _nextCel = <LayerId, FrameId>{};

  /// Makes the block a stroke is about to be drawn into, and HOLDS its
  /// command. Returns false when nothing was made.
  bool beginAutoFrameForStroke() {
    // A block from a press that never became a stroke is settled here
    // rather than left to be swept into THIS press's undo entry.
    flushAutoFrameForStroke();
    final layer = _selection.activeLayer;
    if (layer == null || !canAutoCreateFrameForStroke) {
      return false;
    }
    final command = _controllers.timelineController
        .createDrawingFrameCommandForLayer(
          layerId: layer.id,
          frameId: _nextCel.remove(layer.id) ?? _frameIds.mintFrameId(layer.id),
        );
    command.execute();
    _autoFrameForStroke = command;
    _changes.notifyChanged();
    return true;
  }

  /// Hands the held block command to whoever is pushing the stroke, so the
  /// two land as one entry. Null when this press made no block.
  Command? takeAutoFrameForStroke() {
    final command = _autoFrameForStroke;
    _autoFrameForStroke = null;
    return command;
  }

  /// 🚨A BLOCK THAT NO STROKE CLAIMED KEEPS ITS OWN UNDO.
  ///
  /// ⛔I very nearly made this DISCARD the block — 「a press that drew
  /// nothing leaves nothing」 sounded obviously right and was mine, not the
  /// user's. What they said is 「**빈 칸에서 펜다운하면 블록이 생기고**
  /// 그대로 그려진다」: the pen-DOWN makes it. A tap that makes a block is
  /// the feature, not a leak.
  ///
  /// ⚠️What WOULD be a bug is the block outliving its command. Held and
  /// never composed, it sits in the project with no history entry at all —
  /// unundoable. So an unclaimed one is pushed on its own, exactly as the
  /// manual 「add frame」 button would have left it.
  ///
  /// ⛔Safe in either order, which is why there is no race to reason about:
  /// if the stroke already took it this is a no-op, and if it has not, the
  /// block is undoable either way.
  void flushAutoFrameForStroke() {
    final command = _autoFrameForStroke;
    if (command == null) {
      return;
    }
    _autoFrameForStroke = null;
    // Already executed at pen-down; this records it without re-running
    // anything that matters (the layer edit holds its own before/after).
    _project.historyManager.execute(command);
    _changes.notifyChanged();
  }
}
