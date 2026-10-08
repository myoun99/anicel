import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_size.dart';
import '../models/layer_id.dart';
import 'brush_frame_editing_coordinator.dart';
import 'cache_invalidation_executor.dart';
import 'canvas_selection.dart'
    show
        SelectionMaskOptions,
        SelectionMaskReading,
        selectionMaskOnPasteboard;
import 'canvas_selection_paint_clip.dart' show clipStampDabToSelectionMask;
import 'canvas_selection_region.dart';
import 'cel_pixel_region.dart' show regionInArtworkSpace;
import 'command.dart';
import 'commands/brush_lift_move_history_command.dart';
import 'layer_pose_matrix.dart' show LayerPlacement;

/// WHERE a held picture lands: the cels a press names, where each of their
/// rows stands on the canvas, and the selection it lands through.
///
/// Read at the press, all of it at once — the range, the marquee and its
/// softness all move under an open panel.
class PieceGround {
  const PieceGround({
    required this.cels,
    required this.placementOf,
    this.selection,
    this.options = SelectionMaskOptions.none,
  });

  /// The cels the ladder names: a frame range's whole block, or the cel you
  /// stand on. ⚠️As the ladder spells them — it may name one physical cel
  /// twice, and the landing is what keys them ([pieceLandings]).
  final List<BrushFrameKey> cels;

  /// Where a cel's row stands on the canvas — null for an unplaced row.
  final LayerPlacement? Function(BrushFrameKey key) placementOf;

  /// The selection as it is drawn on the CANVAS, or null with none: the
  /// piece then lands whole (「선택 있으면 그 영역, 없으면 전체」).
  final CanvasSelectionRegion? selection;

  /// The selection's softness — 확장 · 페더 · AA (유저 2026-09-09 「선택의 aa
  /// 따르게」).
  final SelectionMaskOptions options;
}

/// WHAT lands: the picture, how it composites, and what the step is called.
class PieceStamp {
  const PieceStamp({
    required this.onTheRow,
    required this.blend,
    required this.description,
  });

  /// The picture as a row standing at [placement] takes it, in that row's
  /// own artwork — a paste hands every row the same dab, a stamp pressed on
  /// the canvas restates its press on each. Null where the row cannot take
  /// it.
  ///
  /// ⚠️Hand back the SAME dab wherever the answer is the same: the door
  /// cuts one dab through one outline once, however many cels take it.
  final BrushDab? Function(LayerPlacement? placement) onTheRow;

  /// The ORDER it lands in: `color` over what the cel holds, `behind` under
  /// it (위/아래 = 합성순서, 유저 08-10) — or any other mode a stamp wears;
  /// `erase` clears with the picture.
  final BrushBlendMode blend;

  final String description;
}

/// One cel's share of a landing: the dab as it landed there — through the
/// selection, if there is one — and the step that lands it.
typedef PieceLanding = ({BrushDab dab, Command landing});

/// 🚨★★★**THE PIECE DOOR** — a held picture, landed on every cel a press
/// names. 픽셀 위 / 아래 붙여넣기 (I-55), and the cut tool's stamp by all three
/// of its roads: a press on the canvas, a drag, and 원래 위치에 붙여넣기.
///
/// 🗣️F-293 (유저 2026-10-05): 「잘라내기도구의 스탬프, 여러 프레임 선택해서
/// 여러프레임 붙여넣을수있도록. **색편집의 픽셀붙여넣기랑 법 통일**」 · 「선택
/// 범위로 선택한채로 커서로 붙여넣거나, 원래 위치에 붙여넣기나 동일하게」.
/// 🗣️I-28-paste-in-place-Q1 (유저 2026-10-01): 「같은 문으로 — 범위 전부 ·
/// 페더 따름」.
///
/// ↩️The stamp used to be a STROKE: it went down the pen's funnel, which
/// names the cel you stand on by construction and cuts through a selection's
/// hard outline. So one outline meant two edges and one range meant two
/// sets of cels, by which button held the picture.
///
/// The law, the paste's (유저 08-12 · 10-01):
/// - **every cel the ladder names** — a range's whole block or the cel you
///   stand on, a blank cel too (「변형도구처럼 여러 프레임 선택해서 동시
///   붙여넣기 가능」), and no cel is made (C6);
/// - **one landing per PHYSICAL cel** (C5: 「같은게 두개인곳에 붙여넣으면
///   한번만 발리도록」) — keyed the way everything that lands on cels keys
///   them, `frameStore.canonicalKeyOf`, which resolves links: a linked row
///   is a window onto another's cel, so a range can name one cel under two
///   keys. The first row whose reading leaves something of the piece
///   answers for the cel — stack order is the tiebreak, as it is for a
///   transform's landings;
/// - **through the selection when there is one**, each cel reading it on its
///   own row and at its softness;
/// - **one undo**: the caller folds what comes back into one step. Each cel
///   lands through the transform's multi-cel door
///   ([BrushLiftMoveHistoryCommand]) — one cel or a whole range, the same
///   code answers (절대명령 2).
///
/// Keyed by the physical cel, in the ladder's order. Empty when nothing
/// lands — no cel named, or the selection leaves nothing of the piece.
Map<BrushFrameKey, PieceLanding> pieceLandings({
  required BrushFrameEditingCoordinator coordinator,
  required PieceGround ground,
  required PieceStamp stamp,
  CacheInvalidationSink? cacheInvalidationSink,
}) {
  final store = coordinator.frameStore;
  final through = _SelectionOnTheRows(
    ground,
    // Every surface the coordinator writes is this size.
    coordinator.sessionStore.canvasSize,
  );
  final landed = <BrushFrameKey, PieceLanding>{};
  for (final key in ground.cels) {
    final cel = store.canonicalKeyOf(key);
    // 🚨ONE LANDING PER PHYSICAL CEL, AND THE MAP IS WHAT SAYS SO — the
    // form a transform's landings keep (`_landingsPerCel`); 유저's word for
    // this door is 「변형도구처럼」.
    //
    // ↩️A set of the cels ASKED stood beside the map (the paste's older
    // form: the first key answered for its cel whether or not it landed
    // anything). Two mechanisms for one invariant: a mutant deleted the
    // set's skip with every pin green, the map folding the cel anyway
    // (2026-10-06).
    if (landed.containsKey(cel)) {
      continue;
    }
    final placement = ground.placementOf(key);
    final whole = stamp.onTheRow(placement);
    final inside = whole == null
        ? null
        : through.cut(whole, row: key.layerId, placement: placement);
    if (inside == null) {
      continue;
    }
    // 🚨ERASE rides a flag on the DAB, not the blend mode — the materializer
    // reads `dab.erase` per dab and the erase blend takes the plain path, so
    // passing the mode alone paints the piece instead of clearing with it.
    // The trap was hit three times, a caller each (bucket, shape fill, the
    // stamp); every road a piece lands by passes this line.
    final dab = stamp.blend == BrushBlendMode.erase
        ? inside.copyWith(erase: true)
        : inside;
    landed[cel] = (
      dab: dab,
      landing: BrushLiftMoveHistoryCommand(
        coordinator: coordinator,
        frameKey: key,
        preLiftSurface: coordinator.currentSurfaceOf(key),
        landingDabs: [dab],
        blendMode: stamp.blend,
        description: stamp.description,
        // Without a sink the canvas keeps the old composite until you leave
        // the frame — the pixels change and every cache serves what it had.
        cacheInvalidationSink: cacheInvalidationSink,
      ),
    );
  }
  return landed;
}

/// The selection as each row shows it, read ONCE per distinct outline, and
/// a dab cut through it once per outline.
///
/// A range is mostly one row, and rows are mostly unplaced: without the
/// three memos a feathered marquee over twenty-four cels is rasterized
/// twenty-four times and the piece copied as often.
class _SelectionOnTheRows {
  _SelectionOnTheRows(this._ground, this._canvasSize);

  final PieceGround _ground;
  final CanvasSize _canvasSize;

  /// A row's placement is the row's, whichever of its cels asks.
  final _ofRow = <LayerId, SelectionMaskReading?>{};

  /// An unposed row gets the selection back as the same object, so every
  /// plain row shares one reading.
  final _ofOutline =
      Map<CanvasSelectionRegion, SelectionMaskReading?>.identity();

  final _cuts = Map<BrushDab, Map<SelectionMaskReading, BrushDab?>>.identity();

  /// [dab] through the selection as the row at [placement] shows it — [dab]
  /// itself with nothing selected, null when nothing of it survives.
  BrushDab? cut(
    BrushDab dab, {
    required LayerId row,
    required LayerPlacement? placement,
  }) {
    final selection = _ground.selection;
    if (selection == null) {
      return dab;
    }
    final reading = _ofRow.putIfAbsent(row, () {
      // Drawn on the canvas, read in the row's own artwork: a posed row
      // draws its pixels somewhere else than the marquee was drawn.
      final onTheRow = regionInArtworkSpace(
        region: selection,
        placement: placement,
      );
      return onTheRow == null
          ? null
          : _ofOutline.putIfAbsent(
              onTheRow,
              () => selectionMaskOnPasteboard(
                onTheRow,
                canvasSize: _canvasSize,
                options: _ground.options,
              ),
            );
    });
    if (reading == null) {
      return null;
    }
    return _cuts
        .putIfAbsent(dab, () => {})
        .putIfAbsent(
          reading,
          () => clipStampDabToSelectionMask(
            dab,
            mask: reading.mask,
            box: reading.box,
          ),
        );
  }
}
