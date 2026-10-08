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

  /// What the workspace does whenever the tool state moves — four rules, in
  /// this order.
  ///
  /// 0. F-319: a hand that is another — another tool, another brush — ends
  ///    whatever tab the library was looking into
  ///    (`_WorkspaceBrushGroups.followHand`). First, and for every tool: a
  ///    tool that paints nothing coming to hand is a hand changed too.
  /// 1. H36: a painting tool in hand that holds NO brush opens on the
  ///    library's opening preset — the moment a tool is first held is its
  ///    opening moment, for every tool and not only the one the app starts
  ///    on (유저: 「브러시만 되있는데 이상하잖아」). The apply re-enters this
  ///    listener through the assignment and lands in the two rules below.
  /// 2. F-250: the brush is remembered in the tab it shows in, for the tool
  ///    holding it (`_WorkspaceBrushGroups`, which opens a tab on it).
  /// 3. H25: what the hand set is filed under the brush the state is
  ///    holding — [BrushToolState.presetId], read from the SAME state as the
  ///    values, so the two can never name different brushes (H25-again).
  ///
  /// Which preset each paint tool holds is not kept here: it rides in that
  /// tool's state, which `PaintToolStateNotifier` banks per tool (R11-④).
  void followBrushTool() {
    _state._brushGroups.followHand();
    final state = _state._brushTool.value;
    // A tool that puts no brush down carries the brush's state through
    // untouched — nothing it holds is being set by anyone.
    if (!canvasToolPaints(state.tool)) {
      return;
    }
    final presetId = state.presetId;
    if (presetId == null) {
      selectOpeningPreset();
      return;
    }
    // A brush the library cannot name has no file to lay the hand over.
    final preset = _presetNamed(presetId);
    if (preset == null) {
      return;
    }
    // 2. F-250: the group this tool last held a brush in remembers it — for
    //    every road a brush is taken up by, which all pass here.
    _state._brushGroups.remember(state.tool, preset);
    final key = _handKey(state.tool, presetId);
    // The brush's OWN blend rides in its shape — not `activeBlendMode`,
    // which answers 消去 for the eraser tool no matter what the brush says;
    // writing that back would make every eraser preset claim erase as an
    // edit.
    final overlay = brushHandOverlay(
      file: preset.settings,
      hand: state.toBrushSettings(),
      byName: (tip) => _state._tipLibrary.maskFor(tip.id) != null,
    );
    if (jsonEncode(_brushHandSettings[key] ?? const <String, Object?>{}) ==
        jsonEncode(overlay)) {
      return;
    }
    // A brush put back to its own file's values has nothing left to
    // remember: the entry goes, and the file speaks for it again.
    if (overlay.isEmpty) {
      _brushHandSettings.remove(key);
    } else {
      _brushHandSettings[key] = overlay;
    }
    // Debounced: this fires on every slider frame, and the file is the
    // cheapest thing in the app to write too often.
    _brushHandSettingsSave?.cancel();
    _brushHandSettingsSave = Timer(
      const Duration(milliseconds: 400),
      saveHandSettings,
    );
  }

  /// Writes the bank as it stands — where the debounce above, an import and
  /// the workspace's dispose all end.
  void saveHandSettings() => unawaited(
    _brushHandSettingsStore.save(
      Map<String, BrushHandSettings>.of(_brushHandSettings),
    ),
  );

  /// Reads what the hand left on each brush in the last session — giving
  /// way to anything the hand has set since the app opened
  /// ([brushHandSettingsRecalled]).
  Future<void> recallHandSettings() async {
    final saved = await _brushHandSettingsStore.load();
    if (!_state.mounted) {
      return;
    }
    final recalled = brushHandSettingsRecalled(
      live: _brushHandSettings,
      saved: saved,
    );
    _brushHandSettings
      ..clear()
      ..addAll(recalled);
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
    tools.holdBrush(_brushFromPreset(tools.value, preset, tool));
    // The library shows the brush taken up — also when it is the one
    // already in hand, which moves no state for [followBrushTool] to hear:
    // 「브러시 누르면 그룹 바껴야함」 (F-319).
    _state._brushGroups.look.end();
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

  /// [from] holding [preset]'s brush for [tool]. H25: the brush as the hand
  /// last left it with THIS tool, or nothing — in which case the brush's own
  /// file speaks.
  ///
  /// The one road from a preset to a held brush: a press on the library and
  /// a project's resumed tools (F-123) both take it.
  BrushToolState _brushFromPreset(
    BrushToolState from,
    BrushPreset preset,
    CanvasTool tool,
  ) {
    final overlay = _brushHandSettings[_handKey(tool, preset.id)];
    return from.withPreset(
      preset,
      tool: tool,
      held: overlay == null
          ? null
          : brushSettingsUnderHand(
              preset.settings,
              overlay,
              resolveTip: _state._tipLibrary.maskFor,
            ),
    );
  }

  /// When the libraries have landed and the opening brush has been taken
  /// up — what a resumed tool choice waits for (F-123): a brush is named by
  /// its preset, and only a library that has loaded can find it.
  Future<void> libraryLanded = Future<void>.value();

  /// Puts back what the tools held when the project was saved (F-123), once
  /// the library can name the brushes. A preset it no longer has leaves THAT
  /// tool on what it holds; every other part still lands.
  void resumeChoice(ToolChoice choice) => unawaited(
    libraryLanded.then((_) {
      if (!_state.mounted) {
        return;
      }
      resumeToolChoice(_state._brushTool, choice, brushFor: _brushNamed);
    }),
  );

  /// 「초기화」 — the library re-seeded, what the hand left on its brushes
  /// forgotten, and every paint tool holding its brush again from the reset
  /// preset.
  ///
  /// 🗣️F-181 (유저 2026-09-27, `F-181-Q1`: 「pc로는 초기화해도 남아있던데
  /// 폰으로보니 안골라져있음 … 초기화가 제대로 브러시 설정도 기본값으로 초기화
  /// 안하는걸지도」). The reset re-seeded the presets and kept the hand bank,
  /// so picking the G-pen after it laid the paper grain and the old 5%
  /// spacing the bank remembered straight back over the reset defaults. A
  /// reset to defaults forgets the hand too.
  ///
  /// ⚠️The tools are taken up again as well, down the road a project's
  /// resumed tools take ([takeUpBrushes]): a tool left holding the old
  /// settings would file them into the emptied bank at its next move. A tool
  /// whose preset the reset removed — a brush the user made — keeps what it
  /// holds, the answer a resumed project gives a preset it no longer has.
  void resetLibrary() {
    final held = toolChoiceOf(_state._brushTool);
    _state._presetLibrary.resetToDefaults();
    _brushHandSettings.clear();
    saveHandSettings();
    takeUpBrushes(
      _state._brushTool,
      presets: held.presets,
      inHand: held.tool,
      brushFor: _brushNamed,
    );
  }

  /// A preset dragged to a new place or into another group — one undo step
  /// (F-250).
  void arrangePresets(List<BrushPreset> presets) => _arrange(
    brushLibraryArrangementOf(presets, _state._presetLibrary.groups),
  );

  /// A group tab dragged to a new place — one undo step (F-250).
  void arrangeGroups(List<BrushGroup> groups) => _arrange(
    brushLibraryArrangementOf(_state._presetLibrary.presets, groups),
  );

  void _arrange(BrushLibraryArrangement after) {
    final library = _state._presetLibrary;
    final before = library.arrangement;
    if (sameBrushLibraryArrangement(before, after)) {
      return;
    }
    _state.widget.session.historyManager.execute(
      ArrangeBrushLibraryCommand(library, before: before, after: after),
    );
  }

  /// Deletes a preset, and every paint tool that held it takes up the brush
  /// beside it ([BrushPresetLibrary.presetBeside]).
  ///
  /// 🗣️F-250 ③ (유저 2026-10-01): 「브러시 삭제하면 현재 선택된 브러시 ui가
  /// 없어지는데, 제대로 삭제하면 그 외 브러시 선택시키도록」 — a tool left
  /// holding a deleted preset holds a brush the library cannot name, the
  /// F-63 state ([openingPresetFor]).
  void deletePreset(BrushPresetId id) {
    final beside = _state._presetLibrary.presetBeside(id);
    _whileDropping({id}, () => _state._presetLibrary.delete(id), beside);
  }

  /// Deletes a group and its presets; a tool that held one of them takes up
  /// the library's opening preset — nothing is left beside it.
  void deleteGroup(BrushGroupId id) {
    final gone = {
      for (final preset in _state._presetLibrary.presetsInGroup(id)) preset.id,
    };
    _whileDropping(gone, () => _state._presetLibrary.deleteGroup(id), null);
  }

  /// Runs [drop], then hands every paint tool that held one of [gone] the
  /// preset [beside] — or, with none, the library's first, the brush a tool
  /// with no nameable brush opens on (F-63) — down the road a reset and a
  /// resumed project take ([takeUpBrushes]).
  void _whileDropping(
    Set<BrushPresetId> gone,
    void Function() drop,
    BrushPresetId? beside,
  ) {
    final held = toolChoiceOf(_state._brushTool);
    drop();
    final next = beside ?? _state._presetLibrary.presets.firstOrNull?.id;
    if (next == null) {
      return;
    }
    final orphaned = {
      for (final MapEntry(key: tool, value: id) in held.presets.entries)
        if (gone.contains(id)) tool: next,
    };
    if (orphaned.isEmpty) {
      return;
    }
    takeUpBrushes(
      _state._brushTool,
      presets: orphaned,
      inHand: held.tool,
      brushFor: _brushNamed,
    );
  }

  /// [from] holding the brush of the library's preset [id] for [tool] — null
  /// when the library has no such preset.
  BrushToolState? _brushNamed(
    BrushToolState from,
    CanvasTool tool,
    BrushPresetId id,
  ) {
    final preset = _presetNamed(id);
    return preset == null ? null : _brushFromPreset(from, preset, tool);
  }

  /// The library's preset with [id], or null when it holds none.
  BrushPreset? _presetNamed(BrushPresetId id) {
    for (final preset in _state._presetLibrary.presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  /// Where the bank files what [tool] set on [preset].
  ///
  /// The BRUSH tool files under the preset's own id — the key exports carry
  /// and imports hand back (`BrushHandSettingsPort`), so a brush file still
  /// round-trips what the hand set on it. The ERASER files under its own
  /// name: each paint tool keeps its own settings (R11-④), and a size set
  /// while erasing must not come back the next time that brush is picked to
  /// draw with — which one key shared by both tools would do.
  static String _handKey(CanvasTool tool, BrushPresetId preset) =>
      tool == CanvasTool.brush ? preset.value : '${tool.name}:${preset.value}';

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
  /// with it. ⚠️Through [takeUp], not by setting an id — an id alone
  /// would put the highlight on a brush the tool is not holding, which is
  /// the same disagreement pointing the other way.
  ///
  /// ⚠️Silent when the library is empty (a reset that saved nothing) and
  /// when a tool already has a preset — a load that lands after the user has
  /// picked must not overrule them.
  ///
  /// Runs when the library lands, for the tool the app opens on, and from
  /// [followBrushTool] for any painting tool taken up holding nothing (H36).
  void selectOpeningPreset() {
    if (!_state.mounted) {
      return;
    }
    final tool = _state._brushTool.value.tool;
    final preset = openingPresetFor(
      presets: _state._presetLibrary.presets,
      toolPaints: canvasToolPaints(tool),
      alreadyChosen: _state._brushTool.value.presetId != null,
    );
    if (preset == null) {
      return;
    }
    takeUp(tool, preset);
  }

  /// The group the tool's active preset sits in — where a newly saved
  /// preset joins.
  BrushGroupId? _activePresetGroupId() {
    final activeId = _state._brushTool.value.presetId;
    return activeId == null ? null : _presetNamed(activeId)?.groupId;
  }

  /// Saves the brush in hand as a new preset beside the one it came from,
  /// and has the hand hold THAT preset — its settings are exactly the ones in
  /// hand, so this moves the highlight and changes nothing else.
  ///
  /// The library's own doc always said a save "makes it active", and the
  /// highlight never followed: the panel read the workspace's fact while the
  /// save wrote the library's. There is one fact now
  /// ([BrushToolState.presetId]) and the save moves it.
  void saveHeldBrushAsPreset() {
    final state = _state._brushTool.value;
    final saved = _state._presetLibrary.saveCurrent(
      state.toBrushSettings(),
      // A saved variant lands beside the brush it came from rather than at
      // the far end of the list.
      groupId: _activePresetGroupId(),
    );
    _state._brushTool.value = state.withPreset(saved, tool: state.tool);
  }

  /// Runs one of the libraries' file imports and puts its message, if any,
  /// in a notice. Both libraries answer the same contract — a user-facing
  /// message on failure, null on success or a cancelled picker — so which
  /// library is the one value that differs.
  /// The port the library exports and imports hand settings through.
  ///
  /// ⚠️The bank lives HERE, beside the tool state that writes it, so the
  /// library borrows it rather than owning a second copy.
  BrushHandSettingsPort get _handSettingsPort => (
    read: () => brushHandSettingsToCarry(
      _brushHandSettings,
      fileOf: (key) => _presetNamed(BrushPresetId(key))?.settings,
      resolveTip: _state._tipLibrary.maskFor,
    ),
    write: (arrived) {
      _brushHandSettings.addAll(arrived);
      saveHandSettings();
    },
  );

  /// Writes one brush, or a whole group, as a `.anibrush`.
  ///
  /// 🚨유저 (`H25-Q1`, 답 both-by-selection): both buttons exist and the
  /// SELECTION decides which one applies. The library owns the format and
  /// the id bookkeeping; what belongs here is the two things only a widget
  /// can do — ask where to put the file, and say what happened.
  Future<void> _exportAndNotice(List<BrushPreset> presets) async {
    if (presets.isEmpty) {
      await _notice(AppText.strings.brExportNothing);
      return;
    }
    final message = await _state._presetLibrary.exportPresets(
      presets,
      // The door every finished file leaves by: where a save window answers
      // with a path it asks there — the suffix a name typed bare lacks, and
      // the replace question it re-opens, are that window's door's
      // ([pickSaveFileForUser]) — and where none does it writes in the app
      // first and the export window places it. ↩️This appended the suffix
      // itself, at the write, and so wrote over whatever stood at the
      // suffixed name unasked.
      hand: (suggestedName, write) => handWrittenFileToUser(
        _state.context,
        suggestedName: suggestedName,
        acceptedTypeGroups: const [FileTypeGroups.anicelBrush],
        write: write,
      ),
    );
    if (message != null) {
      await _notice(message);
    }
  }

  Future<void> _notice(String message) async {
    if (!_state.mounted) {
      return;
    }
    await showAppNotice(
      _state.context,
      title: AppText.strings.commonNotice,
      message: message,
    );
  }

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
