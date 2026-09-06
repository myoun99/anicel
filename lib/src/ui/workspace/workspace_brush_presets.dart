part of '../editor_workspace.dart';

/// The BRUSH PRESETS AND TIPS, as the workspace keeps them — applying a
/// preset, the opening preset, the hand settings remembered per tool, a
/// cut piece registered as a tip and the stamp armed on a fresh cut,
/// renaming and deleting a tip, importing a tip image or a brush file —
/// as their own object.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP cut,
/// 2026-09-02). It reaches the State through `_state` and rebuilds
/// through `_rebuild`.
class _WorkspaceBrushPresets {
  _WorkspaceBrushPresets(this._state);

  final _EditorWorkspaceState _state;

  int _registeredCutTipSequence = 0;

  /// Rename a library tip. The model has had this since the library
  /// landed; what it never had was anywhere to be called from.
  ///
  /// Through [AppPromptDialog] — the one "type a short string" window —
  /// so trim, Enter-submits and cancel are decided once, not here.
  Future<void> _renameTip(BrushTipEntry tip) async {
    final name = await showDialog<String>(
      context: _state.context,
      builder: (_) => AppPromptDialog(
        windowKey: const ValueKey<String>('rename-tip-dialog'),
        title: AppText.strings.brRenameTip,
        fieldLabel: AppText.strings.commonNameField,
        initialValue: tip.name,
        confirmLabel: AppText.strings.commonRename,
        fieldKey: const ValueKey<String>('rename-tip-name-field'),
      ),
    );
    if (name != null && name.isNotEmpty) {
      _state._tipLibrary.rename(tip.id, name);
    }
  }

  /// Delete a library tip, behind a confirm.
  ///
  /// The confirm is not a general "are you sure" habit — this app's rule is
  /// that explanatory notices are noise — but deleting is destructive and
  /// unlike a stroke it has no undo behind it. Photoshop and Clip Studio
  /// both ask here too.
  Future<void> _deleteTip(BrushTipEntry tip) async {
    final confirmed = await showDialog<bool>(
      context: _state.context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('delete-tip-dialog'),
        title: Text(AppText.strings.brDeleteTip),
        content: Text('“${tip.name}” will be removed from the library.'),
        actions: [
          ControlPressClaim(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: TextButton(
              onPressed: silentPress(
                () => Navigator.of(dialogContext).pop(false),
              ),
              child: Text(AppText.strings.commonCancel),
            ),
          ),
          FilledButton(
            key: const ValueKey<String>('delete-tip-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppText.strings.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _state._tipLibrary.delete(tip.id);
    }
  }

  /// The id the stamp was last armed for, so a POSE change is not mistaken
  /// for a fresh cut (the slot notifies for both).
  String? _armedCutPieceId;

  /// TS8-adjacent (TS2): a finished cut arms the STAMP.
  ///
  /// 유저: *"잘라내고 나면 찍기로 모드전환"* — cutting is how you get
  /// something to stamp, so the tool that stamps it is where the hand is
  /// going next. TVPaint's cutting tool hands over to its custom brush the
  /// same way.
  ///
  /// It hangs off the SLOT rather than the cut gesture on purpose: the slot
  /// is only ever filled by a cut that actually lifted pixels (scraping an
  /// empty area deliberately leaves the held piece alone), so "a stray
  /// scrape switched my tool" cannot happen without an extra guard. The
  /// pose knobs notify through here too, hence [_armedCutPieceId] — ids are
  /// minted per cut and survive `copyWith`.
  ///
  /// Tool changes are view state, not history: this is one write, and undo
  /// never sees it.
  void armStampOnFreshCut() {
    final piece = _state._cutPieceSlot.piece;
    if (piece == null || piece.image.id == _armedCutPieceId) {
      return;
    }
    _armedCutPieceId = piece.image.id;
    if (_state._brushTool.value.tool == CanvasTool.cutStamp) {
      return;
    }
    _state._brushTool.value = _state._brushTool.value.copyWith(
      tool: CanvasTool.cutStamp,
    );
  }

  /// Promotes the held piece into the brush tip library.
  ///
  /// Explicit, and it asks for a name — which is the whole reason cutting
  /// does NOT do this by itself. Photoshop and Clip Studio both make
  /// library registration a separate named command, and TVPaint's Tool
  /// History is the counter-example: it accumulates unnamed near-duplicates
  /// automatically and its own users gave up on it as a store. The user's
  /// objection to the first design was exactly that ("잘라낼 때마다 팁
  /// 라이브러리 늘리는 거 딱히 마음에 안 드는데").
  ///
  /// One field, like Photoshop's. Our tip library has no groups to file
  /// into — that is the preset library — so a second field would be asking
  /// about a place that does not exist.
  Future<void> _registerCutPieceAsTip() async {
    final piece = _state._cutPieceSlot.piece;
    if (piece == null) {
      return;
    }
    _registeredCutTipSequence += 1;
    final name = await showDialog<String>(
      context: _state.context,
      builder: (_) => AppPromptDialog(
        windowKey: const ValueKey<String>('register-cut-tip-dialog'),
        title: AppText.strings.tipRegisterTitle,
        fieldLabel: AppText.strings.commonNameField,
        initialValue: 'Cut $_registeredCutTipSequence',
        confirmLabel: AppText.strings.commonRegister,
        fieldKey: const ValueKey<String>('register-cut-tip-name-field'),
        confirmKey: const ValueKey<String>('register-cut-tip-confirm'),
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    final id = sanitizeBrushTipId(
      nextUserBrushTipId(sequence: _registeredCutTipSequence),
    );
    await _state._tipLibrary.register(
      cutPieceToTipMask(piece, id: id),
      name: name,
    );
  }

  /// Which preset is highlighted PER painting tool (R11-④: the brush and
  /// the eraser keep separate selections; their settings live in
  /// [PaintToolStateNotifier]'s bank).
  final Map<CanvasTool, BrushPresetId?> _activePresetByTool = {};

  /// 🚨H25 — WHAT THE HAND LAST SET ON EACH BRUSH.
  ///
  /// 유저 2026-08-23: 「브러시 고르고 브러시크기 설정하면 다음에 같은 브러시
  /// 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」. A brush with no
  /// entry here reads the size baked into its own file — the other half of the
  /// answer, and the reason this is a bank and not a rewrite of the preset.
  ///
  /// ⛔The preset FILE is not touched (Q-brush-store): a slider drag must not
  /// write a document to disk. Persisted beside the app's other editor state.
  final Map<String, BrushHandSettings> _brushHandSettings = {};

  final BrushHandSettingsStore _brushHandSettingsStore =
      BrushHandSettingsStore();

  Timer? _brushHandSettingsSave;

  /// Records the live size/opacity against the ACTIVE preset.
  ///
  /// ⚠️Reads the state's own tool, never the notifier's last-known one: the
  /// eraser carries its own preset (R11-④), so recording under the wrong tool
  /// would give two brushes one memory.
  void rememberBrushHandSettings() {
    final state = _state._brushTool.value;
    final presetId = _activePresetByTool[state.tool];
    if (presetId == null) {
      return;
    }
    final next = (size: state.size, opacity: state.activeOpacity);
    if (_brushHandSettings[presetId.value] == next) {
      return;
    }
    _brushHandSettings[presetId.value] = next;
    // Debounced: this fires on every slider frame, and the file is the
    // cheapest thing in the app to write too often.
    _brushHandSettingsSave?.cancel();
    _brushHandSettingsSave = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        _brushHandSettingsStore.save(
          Map<String, BrushHandSettings>.of(_brushHandSettings),
        ),
      );
    });
  }

  void _applyPreset(BrushPreset preset) {
    // Applying a preset KEEPS the active painting tool (R11-④: the eraser
    // owns its own preset choice); from a non-painting tool it arms the
    // brush. Which settings survive the swap is the state's own rule —
    // see [BrushToolState.withPresetSettings].
    final current = _state._brushTool.value;
    final targetTool = canvasToolPaints(current.tool)
        ? current.tool
        : CanvasTool.brush;
    _state._brushTool.value = current.withPresetSettings(
      preset.settings,
      tool: targetTool,
      // H25: what the hand last set on THIS brush, or nothing — in which case
      // the brush's own baked size wins.
      handSet: _brushHandSettings[preset.id.value],
    );
    _activePresetByTool[targetTool] = preset.id;
    _state._presetLibrary.markActive(preset.id);
  }

  /// 🚨★★★THE LIBRARY OPENS SHOWING THE BRUSH THAT IS IN HAND.
  ///
  /// 유저 (F-63): 「브러시/지우개에서, 브러시 라이브러리에서 **초기값이
  /// 아무것도 선택안된 UI**인데, 브러시는 그려지는거 보니 **초기 브러시자체는
  /// 정해져있는거같음.** 그게 ui에도 연동되있도록」.
  ///
  /// ⛔They are exactly right, and the cause is that there were TWO facts:
  /// `PaintToolStateNotifier` opened with baked-in settings while
  /// `_activePresetByTool` opened EMPTY, so the app drew with a brush the
  /// library could not name. Nothing was persisted either way — the map is
  /// not saved — so no remembered choice is being overwritten here.
  ///
  /// ⇒ Applying a preset makes them ONE fact: the tool takes its settings,
  /// the panel highlights it, and H25's per-brush size/opacity comes back
  /// with it. ⚠️Through `_applyPreset`, not by writing the map — writing
  /// only the id would put the highlight on a brush the tool is not holding,
  /// which is the same disagreement pointing the other way.
  ///
  /// ⚠️Silent when the library is empty (a reset that saved nothing) and
  /// when a tool already has a preset — a load that lands after the user has
  /// picked must not overrule them.
  void selectOpeningPreset() {
    if (!_state.mounted) {
      return;
    }
    final tool = _state._brushTool.value.tool;
    final preset = openingPresetFor(
      presets: _state._presetLibrary.presets,
      toolPaints: canvasToolPaints(tool),
      alreadyChosen: _activePresetByTool[tool] != null,
    );
    if (preset == null) {
      return;
    }
    _applyPreset(preset);
  }

  /// The group the tool's active preset sits in — where a newly saved
  /// preset joins.
  BrushGroupId? _activePresetGroupId(CanvasTool tool) {
    final activeId = _activePresetByTool[tool];
    if (activeId == null) {
      return null;
    }
    for (final preset in _state._presetLibrary.presets) {
      if (preset.id == activeId) {
        return preset.groupId;
      }
    }
    return null;
  }

  /// Runs one of the libraries' file imports and puts its message, if any,
  /// in a notice. Both libraries answer the same contract — a user-facing
  /// message on failure, null on success or a cancelled picker — so which
  /// library is the one value that differs.
  Future<void> _importAndNotice(
    Future<String?> Function() importFromFile,
  ) async {
    final message = await importFromFile();
    if (message == null || !_state.mounted) {
      return;
    }
    unawaited(
      showAppNotice(
        _state.context,
        title: AppText.strings.commonNotice,
        message: message,
      ),
    );
  }
}
