part of '../editor_workspace.dart';

/// The BRUSH GROUP a paint tool opens on — F-250's memory, as its own object
/// beside [_WorkspaceBrushPresets], which keeps the brushes themselves — and
/// with it the two PRESSES of a tool's library, a brush's row ([takeUp]) and
/// a group's tab ([openGroup]), and the tab the library shows ([look]).
///
/// 🗣️F-250 (유저 2026-10-01): 「브러시 그룹을 바꿀때(선택하던 뭐던), 해당
/// 그룹의 마지막으로 선택했던걸 기억해서 그거 자동선택되도록」 — the tool
/// rail's `railEntry` law, for brush groups: from outside, back to where it
/// was left; the first time, the group's own first.
class _WorkspaceBrushGroups {
  _WorkspaceBrushGroups(this._state);

  final _EditorWorkspaceState _state;

  /// The brush each paint tool last held in each group, by the tab it shows
  /// in — what opening that tab hands the tool back ([openGroup]).
  ///
  /// 🗣️F-250-group-memory-Q1 (유저 2026-10-01): 「도구마다 따로」 — a tool
  /// keeps its own memory, as it keeps its own brush (R11-④): the eraser
  /// opening a group it has never held anything in takes the group's first,
  /// whatever the brush tool last held there.
  final Map<(CanvasTool, BrushGroupId?), BrushPresetId> _lastInGroup = {};

  /// The tab the tool library is looking into while the hand cannot say it
  /// (F-319) — ONE, for whichever paint tool's panel is on screen, and kept
  /// here beside the hand: settled when a tab is pressed ([openGroup]) and
  /// ended when the hand is another ([followHand]).
  final BrushLibraryLook look = BrushLibraryLook();

  /// The hand [look] was last settled for: the tool, and the brush it holds.
  (CanvasTool, BrushPresetId?)? _hand;

  /// Hears every move of the tool state. A hand that is ANOTHER — another
  /// tool come to hand, another brush taken up, by whatever road — ends the
  /// look: 「브러시는 항상 선택된그룹/브러시 를 보여줌」 (F-319).
  ///
  /// ⚠️A size dragged or a colour picked is the same hand, and a look into
  /// an empty group stands through it.
  void followHand() {
    final state = _state._brushTool.value;
    final hand = (state.tool, state.presetId);
    if (hand != _hand) {
      _hand = hand;
      look.end();
    }
  }

  /// Files [preset] as the last brush [tool] held in the tab it shows in.
  /// Every road a brush is taken up by passes `followBrushTool`, which
  /// calls this.
  void remember(CanvasTool tool, BrushPreset preset) {
    final group = preset.groupShownAmong(_state._presetLibrary.groups);
    _lastInGroup[(tool, group)] = preset.id;
  }

  /// The tab [tool]'s brush shows in — a record, since the root section's
  /// is a null group — or null while it holds no brush the library can
  /// name. The tool in hand's is the live one; another's is what it left
  /// (`PaintToolStateNotifier.presetHeldBy`).
  ({BrushGroupId? group})? _tabHeldBy(CanvasTool tool) {
    final heldId = _state._brushTool.presetHeldBy(tool);
    final held = heldId == null
        ? null
        : _state._brushPresets._presetNamed(heldId);
    return held == null
        ? null
        : (group: held.groupShownAmong(_state._presetLibrary.groups));
  }

  /// [group]'s TAB PRESSED in [tool]'s library — tapped, or by its key, the
  /// one press (F-319: 「그냥 브러시 그룹 바꾸는거로하면 더 만들것도 없고
  /// 쉬울텐데. 법 이상한거 있으면 통일」).
  ///
  /// [tool] comes to hand, holding the brush it last held in that tab, or
  /// the tab's first ([BrushPresetLibrary.presetEntering]) — unless its
  /// brush already shows there, which stays exactly as it is (`railEntry`:
  /// 안에 있으면 그대로). Then the tab shows: the hand says it, or — a group
  /// with no brush to take up — it is looked into ([look]).
  ///
  /// ↩️The tool was whichever paint tool was in hand, and the brush tool
  /// when none was (`_toolTakingUpABrush`): 「A group's KEY can be pressed
  /// with any tool (I-56) — then the hand is outside, and comes in: the
  /// brush tool is armed」. 🗣️F-319 (유저 2026-10-08): 「브러시 그룹은 도구가
  /// 두곳에 있으니까 두 곳 나눠서 지정하도록. 브러시도구의 브러시그룹/브러시
  /// 변경. 지우개도구의 브러시그룹/브러시변경」 — a press names its tool, and
  /// the tab of a library names the tool it is the library of.
  ///
  /// ⚠️That it BRINGS the tool to hand when another is, is this session's
  /// reading of that sentence (board F-319-Q1) — a key that changed what a
  /// tool not in hand holds would do nothing anyone could see.
  void openGroup(CanvasTool tool, BrushGroupId? group) {
    final presets = _state._brushPresets;
    final inside = _tabHeldBy(tool) == (group: group);
    final entering = inside
        ? null
        : _state._presetLibrary.presetEntering(
            group,
            remembered: _lastInGroup[(tool, group)],
          );
    final preset = entering == null ? null : presets._presetNamed(entering);
    if (preset != null) {
      takeUp(tool, preset);
    } else {
      // Inside already, or a tab with no brush to hand it: the tool comes
      // to hand holding what it holds.
      final tools = _state._brushTool;
      tools.value = tools.value.copyWith(tool: tool);
    }
    look.settle(group, held: _tabHeldBy(tool));
  }

  /// [tool] comes to hand holding [preset]'s brush — the brush row's press
  /// in that tool's library, and the one road every press of a brush takes:
  /// a tap on the row, the brush's key, a group's tab handing back what was
  /// last held there, the opening brush.
  ///
  /// 🗣️F-319 (유저 2026-10-08): 「브러시 그룹은 도구가 두곳에 있으니까 두 곳
  /// 나눠서 지정하도록. 브러시도구의 브러시그룹/브러시 변경. 지우개도구의
  /// 브러시그룹/브러시변경」 — the press says whose brush it is.
  /// ↩️It did not, and a rule stood in for it (`_toolTakingUpABrush`):
  /// 「Applying a preset KEEPS the active painting tool (R11-④: the eraser
  /// owns its own preset choice); from a non-painting tool it arms the
  /// brush」. The eraser still owns its own choice — its library's rows and
  /// its keys are its own now, and name it.
  ///
  /// Which settings survive the swap is the state's own rule
  /// ([BrushToolState.withPreset]). ⚠️Taken up WHOLE
  /// ([PaintToolStateNotifier.holdBrush]): a tool brought to hand by this
  /// holds THIS brush, though it equal the brush of the tool it replaces —
  /// which a plain assignment reads as a switch back to what it had banked
  /// (F-181).
  void takeUp(CanvasTool tool, BrushPreset preset) {
    final tools = _state._brushTool;
    tools.holdBrush(
      _state._brushPresets._brushFromPreset(tools.value, preset, tool),
    );
    // The library shows the brush taken up — also when it is the one
    // already in hand, which moves no state for [followHand] to hear:
    // 「브러시 누르면 그룹 바껴야함」 (F-319).
    look.end();
  }

  /// The brush row's press in each paint tool's library, for that tool's
  /// panel to call with the brush — [takeUp] with the tool said.
  ///
  /// ⚠️ONE closure a tool, made once: the panel keeps its grid as built
  /// while what it is built from is the same (H40), and a closure made in a
  /// build is never the same.
  late final Map<CanvasTool, ValueChanged<BrushPreset>> rowPressOf = {
    for (final tool in CanvasTool.values)
      if (canvasToolPaints(tool)) tool: (preset) => takeUp(tool, preset),
  };

  /// A tab's press in each paint tool's library, for that tool's panel to
  /// call with the tab — [openGroup] with the tool said.
  late final Map<CanvasTool, ValueChanged<BrushGroupId?>> tabPressOf = {
    for (final tool in CanvasTool.values)
      if (canvasToolPaints(tool)) tool: (group) => openGroup(tool, group),
  };

  void dispose() => look.dispose();
}
