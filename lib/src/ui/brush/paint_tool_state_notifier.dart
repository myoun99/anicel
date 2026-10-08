import 'package:flutter/foundation.dart';

import '../../models/brush_preset_id.dart';
import 'brush_tool_state.dart';

/// The app's active-tool notifier with PER-PAINT-TOOL memory (R11-④):
/// the brush and the eraser each keep their own stroke settings (size,
/// tip, preset payload…) — switching tools stashes the outgoing paint
/// tool's state and restores the incoming one's, CSP-style. COLOR and the
/// stabilizer stay shared across tools (the color panel and the hand-feel
/// setting are global).
///
/// Non-paint tools (eyedropper, fill, selections) carry the current
/// settings through unchanged — they never stroke, and the shared color
/// keeps working for fill/eyedropper.
class PaintToolStateNotifier extends ValueNotifier<BrushToolState> {
  PaintToolStateNotifier(super.value) {
    _rememberRailTile();
  }

  final Map<CanvasTool, BrushToolState> _paintToolBank =
      <CanvasTool, BrushToolState>{};

  /// The tile each rail GROUP was last on — see [railEntry].
  final Map<CanvasTool, CanvasTool> _railTileByGroup =
      <CanvasTool, CanvasTool>{};

  /// The preset [tool]'s brush came from: the live state's when [tool] is
  /// in hand, the bank's otherwise — null while that tool holds none.
  ///
  /// What a project carries of each paint tool's brush (F-123). A read, not
  /// a second way in: the bank still only changes through the setter below.
  BrushPresetId? presetHeldBy(CanvasTool tool) =>
      tool == value.tool ? value.presetId : _paintToolBank[tool]?.presetId;

  /// Every tile is remembered, the stamp as much as any.
  ///
  /// ↩️The stamp used to be passed through (유저 확정 2026-08-15: 「찍기는
  /// 아예 성질이 다른거니까 그 외만 기억하도록」), so leaving it and pressing
  /// the Cut button handed back the cut tile from before it. 🗣️I-53 (유저
  /// 2026-09-28) retired that: 「잘라내기 도구 선택시 스탬프 선택된 상태면
  /// 다른 잘라내기로 바꾸는 해당로직 싹 삭제. 잔재 삭제. 이제부터는
  /// 잘라내기도구 선택시 마지막 스탬프 선택된상태여도 다른 도구처럼 스탬프
  /// 선택되도록」 — a cut is picked with the lasso cut's own key instead.
  void _rememberRailTile() {
    final tool = value.tool;
    _railTileByGroup[canvasToolRailGroup(tool)] = tool;
  }

  /// The tool an entrance to [group] should arm — the tile that group was
  /// last left on, or the group's default when it has not been used yet.
  ///
  /// 유저 2026-08-15: *"필 툴은 아직도 다른 툴 이동하면 모드 선택한게
  /// 초기화됨. 도대체 왜 다른거랑 공통로직안할까?"* The answer was that
  /// there was no common logic: a group with more than one tile (fill =
  /// bucket + shapes, cut = grab + stamp) only knew "stay if you are
  /// already inside", so leaving it at all threw the choice away and a
  /// shape fill came back as the bucket. The OUTLINE was remembered all
  /// along (`fillShape` lives beside `selectShape` and `cutShape`) — the
  /// VERB was not.
  ///
  /// 🚨It lives HERE rather than in the workspace because a group has more
  /// than one entrance: the rail button, and the tool shortcuts the shell
  /// dispatches — both through `pressTool`. A memory kept beside one of them
  /// would have made
  /// the other disagree, which is the same complaint one door over. This
  /// setter is the funnel every tool change already goes through, so it
  /// cannot miss one.
  ///
  /// Seeded in the constructor as well: this only sees CHANGES, and the
  /// state it is constructed with is already sitting on a tile.
  ///
  /// ⚠️TWO rules, and they are not the same one. Already INSIDE the group
  /// means stay exactly where you are — a press must never move a hand off
  /// the tile it is working on, which is what kept the stamp from being
  /// knocked back to the grab long before there was any memory. Coming
  /// from OUTSIDE is what the memory answers.
  CanvasTool railEntry(CanvasTool group) {
    final current = value.tool;
    if (canvasToolRailGroup(current) == group) {
      return current;
    }
    return _railTileByGroup[group] ?? group;
  }

  // 🪦A tool-switch GUARD (R26 #13) lived on this setter: a refusal message
  // for a tool, the switch blocked and the message announced. Its one
  // installer was the shell's transform-tool refusal, and #971 moved that
  // refusal onto the edit (유저 확정 08-13, 피드백 ⑦ — see home_page). Nothing
  // installed the guard after that, so the seam, its branch and its notice
  // hook ran only in their own tests until they were removed (2026-09-16).

  /// True while [holdBrush] is assigning — the one assignment the setter
  /// must not read as a pure switch.
  bool _holding = false;

  /// [next] taken up WHOLE — its tool and the brush it holds — through the
  /// one setter below, even when its settings happen to equal the tool it
  /// replaces.
  ///
  /// 🚨F-181 (2026-09-27): the setter reads a switch that changes nothing
  /// but the tool as a PURE switch and hands the incoming tool its banked
  /// brush. A brush taken up again from its preset can equal the brush
  /// beside it exactly — two paint tools on one preset, nothing set by hand
  /// — and then that tool's OLD banked brush came back in its place: a
  /// library reset left the brush holding the size the hand had set.
  /// Equality answered two questions (「did the caller change anything
  /// else?」 and 「should the bank win?」), so the caller says which.
  void holdBrush(BrushToolState next) {
    _holding = true;
    try {
      value = next;
    } finally {
      _holding = false;
    }
  }

  /// Puts the brush [previous] held back in its owner's place, as it was
  /// left: a painting tool's own, and — through the shape tool — the brush
  /// tool's ([canvasToolBrushOwner]). A tool that holds no brush of anyone's
  /// banks nothing.
  void _bankBrushHeldBy(BrushToolState previous) {
    final owner = canvasToolBrushOwner(previous.tool);
    if (owner != null) {
      _paintToolBank[owner] = previous;
    }
  }

  /// The banked brush [tool] takes up — its owner's — or null when it holds
  /// none, or none has been banked for it yet.
  BrushToolState? _brushBankedFor(CanvasTool tool) =>
      switch (canvasToolBrushOwner(tool)) {
        null => null,
        final owner => _paintToolBank[owner],
      };

  @override
  set value(BrushToolState next) {
    final previous = value;
    if (next.tool != previous.tool) {
      _bankBrushHeldBy(previous);
      // Restore ONLY on a pure tool switch (the caller changed nothing but
      // the tool) — an assignment that also carries new settings (a preset
      // application landing on the brush) must win over the bank, and so
      // must a brush taken up whole ([holdBrush]).
      final pureToolSwitch =
          !_holding && next.copyWith(tool: previous.tool) == previous;
      final stored = pureToolSwitch ? _brushBankedFor(next.tool) : null;
      if (stored != null) {
        // 🚨★★★ 유저 #14 (2026-08-14): 「선택툴에서 올가미 선택하고 브러시가면
        // 초기화되는거」 — ⛔THE LIST RUNS THE OTHER WAY NOW.
        //
        // This restored `stored` WHOLE and carved out the two shared values
        // (`color`, `stabilizerStrength`). Everything not named was
        // therefore REVERTED — and the state carries other tools' fields:
        // `selectShape` / `cutShape` / `fillShape` (유저: 도형은 동사별로
        // 기억) plus the fill's and the stamp's blends. Pick the lasso, tap
        // the brush, and a snapshot from before the pick put the box back.
        // From the very first frame, because the app starts on the brush.
        //
        // 🚨★★Third time this round a hand-written carry list went stale as
        // fields were added (`withMask` passed three and reset the shapes;
        // `withPreset` dropped them). The DIRECTION is what makes
        // this one safe: build from the LIVE state and pull back only what
        // the bank exists to remember — this paint tool's own brush and its
        // blend. A field added tomorrow is then shared by default, a mild
        // wrong; under the old direction it silently reverted, which is the
        // bug.
        //
        // ⚠️`color` is re-asserted on top because it rides INSIDE the shape
        // — swapping the brush swaps its colour with it, and the colour is
        // shared across tools. That is the order `copyWith` documents: the
        // individual arguments win over the shape laid down beneath them.
        // `stabilizerStrength` needs no such line; it is its own field, so
        // building from `next` already keeps the live one.
        //
        // ⛔The blend needed a line of its own until 2026-09-08. It does not
        // any more: it rides in the shape now (see [BrushBlendMode]), so
        // `shape: stored.shape` restores it the way it restores the size.
        //
        // 🚨And the PRESET that brush came from travels with it (H25-again,
        // H36). `copyWith(shape:)` alone kept the OUTGOING tool's preset id,
        // so the eraser came back holding its own brush under the brush
        // tool's name — see [BrushToolState.carryingBrushOf].
        next = next.carryingBrushOf(stored);
      }
    }
    super.value = next;
    _rememberRailTile();
  }
}
