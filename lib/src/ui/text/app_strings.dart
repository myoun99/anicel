import 'package:flutter/foundation.dart';

import '../../models/app_language.dart';

/// The LIVE program/notation languages, app-wide — the same shape
/// [AppColors.accentSettings] uses, and for the same reason: widgets deep
/// in the canvas have no session to ask, and a string that ignores the
/// language setting is a bug wherever it appears.
///
/// The session restores and persists this; it is never disposed, because
/// it outlives any one session (tests build several).
abstract final class AppText {
  static final ValueNotifier<AppLanguageSettings> settings =
      ValueNotifier<AppLanguageSettings>(const AppLanguageSettings());

  /// The PROGRAM-language table, read at call time.
  static AppStrings get strings =>
      AppStrings.of(settings.value.programLanguage);

  /// The PROGRAM language itself — for the vocabularies that localize
  /// through their own `labelFor` (blend modes, effect kinds) instead of
  /// through a string key.
  static AppLanguage get language => settings.value.programLanguage;
}

/// PROGRAM-language strings (UI-R10 #7): what the app chrome reads in.
/// Coverage rolls out incrementally — panels adopt entries as they get
/// touched; untabled strings simply stay English in the widgets.
enum AppStrings {
  _en._(_enValues),
  _ja._(_jaValues),
  _ko._(_koValues),
  _fr._(_frValues),
  _zhHans._(_zhHansValues);

  const AppStrings._(this._values);

  /// This language's OWN entries. A key absent here falls back to English,
  /// which is what makes a PARTIAL translation legal: the previous table
  /// required every language to answer every string before the app would
  /// compile, so adding one string meant editing six places and coverage
  /// stalled at 77 entries while the app carried some four hundred.
  final Map<String, String> _values;

  String _s(String key) => _values[key] ?? _enValues[key]!;

  /// The shortcut registry's action label. The registry is `const`, so it
  /// cannot hold a translated string — it holds the id and its own English
  /// wording, and that wording IS the English row: no entry is tabled for
  /// `en`, which is why this falls back to [fallback] rather than to
  /// [_enValues]. Keeps the app's action names in exactly one place.
  String shortcutLabel(String actionId, String fallback) =>
      _values['shortcutAction.$actionId'] ?? fallback;

  /// Same contract for the registry's category headings.
  String shortcutCategory(String category, String fallback) =>
      _values['shortcutCategory.$category'] ?? fallback;

  /// A menu entry's wording, by the stable id the menu bar already keys its
  /// widgets with. Same fallback contract as [shortcutLabel]: English lives
  /// at the call site, the other languages here. An id left untabled — the
  /// play/pause entry, whose label flips with playback state — simply keeps
  /// the label it was given.
  String menuLabel(String id, String fallback) =>
      _values['menuAction.$id'] ?? fallback;

  /// The rasterize verb's ONE name: the timeline menu's entry and the
  /// reference popover's button say the same word for the same verb.
  String get layerRasterizeLabel =>
      menuLabel('layer-rasterize', 'Rasterize layer');

  /// 색 라벨의 공정·수정 이름과 축약어(I-4).
  ///
  /// 🚨★★★Same contract as [menuLabel]: the ENGLISH wording lives at the call
  /// site — here, the enum in `models/` — and the other languages live in
  /// these tables. It has to work that way round: `models` may not import
  /// `ui/` (the dependency-direction test enforces it), so the model holds
  /// the stable key and its own words, and translation is a lookup by key.
  ///
  /// 유저 2026-08-28: 「프로그램 언어에따라 **로컬라이즈 안되니까** 해주고」 —
  /// the names were hardcoded Korean, so a Japanese UI read 「ラベルなし」
  /// next to 「용지」.
  String layerProcessName(String key, String fallback) =>
      _values['layerProcess.$key'] ?? fallback;

  String layerProcessAbbrev(String key, String fallback) =>
      _values['layerProcessAbbrev.$key'] ?? fallback;

  String layerReviseName(String key, String fallback) =>
      _values['layerRevise.$key'] ?? fallback;

  String layerReviseAbbrev(String key, String fallback) =>
      _values['layerReviseAbbrev.$key'] ?? fallback;

  String get languageSettingsTitle => _s('languageSettingsTitle');
  String get programLanguageLabel => _s('programLanguageLabel');
  String get notationLanguageLabel => _s('notationLanguageLabel');
  String get programLanguageHelp => _s('programLanguageHelp');
  String get notationLanguageHelp => _s('notationLanguageHelp');

  /// The timeline/timesheet gap empty state.
  String get noCutSelected => _s('noCutSelected');

  /// The timesheet panel-frame position label: page view prints
  /// '`<pageLabel>` N'.
  String get pageLabel => _s('pageLabel');

  /// The continuous-view position label.
  String get continuousLabel => _s('continuousLabel');

  /// R26 #35/#13 — the shared CURSOR NOTICES: every refused action says
  /// why, right where the user is looking.
  String get noticeNoFrameHere => _s('noticeNoFrameHere');

  /// R27 #16: the refusal is about the LAYER, not the section — the CAM
  /// section is no longer uniformly undrawable in the user's model.
  String get noticeLayerNotDrawable => _s('noticeLayerNotDrawable');

  /// Synced attach rows look like blocks but own no timing — a grab
  /// redirects to the owner (the synced-block UI's cursor guidance).
  String get noticeEditAttachOwner => _s('noticeEditAttachOwner');

  /// Shared dialog verbs — tabled once, reused by every dialog that
  /// adopts localization.
  String get commonCancel => _s('commonCancel');
  String get commonApply => _s('commonApply');
  String get commonRefresh => _s('commonRefresh');
  String get commonClose => _s('commonClose');

  /// The disclosure heading over the files a notice is about (유저
  /// 2026-08-29: 「해당 파일들이라는 항목으로 접기 펼치기 가능하게」).
  String get commonAffectedFiles => _s('commonAffectedFiles');

  /// F-10: the title of the shared notice window that replaced the
  /// bottom-of-screen message strip.
  String get commonNotice => _s('commonNotice');

  /// The shared pill's deselect button — the tablet's Esc.
  String get tlSharedDeselect => _s('tlSharedDeselect');

  String get tlSharedColourEdit => _s('tlSharedColourEdit');

  /// R27 #31: the export window's empty state — the project has no cuts
  /// at all (standing in a GAP is not this; that anchors on the first cut).
  String get exportNoCuts => _s('exportNoCuts');

  // --- The audio program's UI (Preferences ▸ Audio, 2D + AUDIO-PRO R4) ---
  String get audioOffsetTitle => _s('audioOffsetTitle');
  String get audioOffsetHelp => _s('audioOffsetHelp');
  String get audioOffsetLabel => _s('audioOffsetLabel');

  /// The A/V offset unit dropdown's frame entry ('ms' is universal).
  String get audioUnitFrames => _s('audioUnitFrames');
  String get audioDevicesTitle => _s('audioDevicesTitle');
  String get audioDevicesHelp => _s('audioDevicesHelp');
  String get audioOutputLabel => _s('audioOutputLabel');
  String get audioInputLabel => _s('audioInputLabel');
  String get audioSystemDefault => _s('audioSystemDefault');

  /// Appended to a device name: '{name}{suffix}'.
  String get audioDeviceDefaultSuffix => _s('audioDeviceDefaultSuffix');
  String get audioDeviceMissingSuffix => _s('audioDeviceMissingSuffix');
  String get audioSyncInspectorTitle => _s('audioSyncInspectorTitle');

  // --- Guide voice recording (AUDIO-PRO R5) ---
  String get recordVoiceTooltip => _s('recordVoiceTooltip');
  String get recordVoiceStopTooltip => _s('recordVoiceStopTooltip');
  String get recordMicOpenFailed => _s('recordMicOpenFailed');
  String get recordMicPermissionDenied => _s('recordMicPermissionDenied');

  /// REC1-B: the armed-track refusal — recording needs an SE lane active.
  String get recordSelectSeLane => _s('recordSelectSeLane');

  // --- Capture chain (REC1-D) ---
  String get recordTakeClipped => _s('recordTakeClipped');
  String get recordClipMarkerTooltip => _s('recordClipMarkerTooltip');

  /// D26: the crossing-fade refusal warning (red corner marker's hover
  /// text) — the sanctioned exception to the no-explanatory-UI rule.
  String get tlTransitionCrossingWarning => _s('tlTransitionCrossingWarning');
  String get audioMicGainLabel => _s('audioMicGainLabel');
  String get audioInputChannelLabel => _s('audioInputChannelLabel');
  String get audioInputChannelDevice => _s('audioInputChannelDevice');
  String get audioInputChannelMonoMix => _s('audioInputChannelMonoMix');
  String get audioInputChannelLeft => _s('audioInputChannelLeft');
  String get audioInputChannelRight => _s('audioInputChannelRight');
  String get audioClippingNoticeLabel => _s('audioClippingNoticeLabel');

  /// The RNNoise toggle (voice-only by design: dialogue ON, foley OFF).
  String get audioDenoiseLabel => _s('audioDenoiseLabel');
  String get audioInputMeterLabel => _s('audioInputMeterLabel');
  String get audioTestSoundLabel => _s('audioTestSoundLabel');

  // --- ADR cueing (REC1-E) ---
  String get audioCountInLabel => _s('audioCountInLabel');
  String get audioCueBeepsLabel => _s('audioCueBeepsLabel');
  String get audioStreamerLabel => _s('audioStreamerLabel');
  String get recordNothingRecording => _s('recordNothingRecording');
  String get recordTakeEmpty => _s('recordTakeEmpty');
  String get recordPlacementFailed => _s('recordPlacementFailed');

  /// '{count}' is replaced with the dropped-frame count.
  String get recordDroppedFramesTemplate => _s('recordDroppedFramesTemplate');

  // --- Mix controls (AUDIO-PRO R1; the SE mixer, R10 R3) ---
  String get layerAudioTitle => _s('layerAudioTitle');
  String get audioGainLabel => _s('audioGainLabel');
  String get audioPanLabel => _s('audioPanLabel');
  String get layerAudioPanHelp => _s('layerAudioPanHelp');
  String get audioMute => _s('audioMute');
  String get audioSolo => _s('audioSolo');

  // --- The fps-change audio notice (EXPORT-AUDIO ④) ---
  /// '{from}'/'{to}' are replaced with the rate labels.
  String get fpsAudioTitleTemplate => _s('fpsAudioTitleTemplate');
  String get fpsAudioBody => _s('fpsAudioBody');
  String get fpsAudioKeep => _s('fpsAudioKeep');
  String get fpsAudioPull => _s('fpsAudioPull');

  // --- The pending selection-move prompt (R17-①) ---
  String get selectionMoveConfirmTitle => _s('selectionMoveConfirmTitle');
  String get selectionMoveConfirmBody => _s('selectionMoveConfirmBody');
  String get selectionMoveRevert => _s('selectionMoveRevert');
  String get selectionMoveApply => _s('selectionMoveApply');

  /// Closes an open polygon outline. A tablet has no Enter key, so the
  /// confirm has to be reachable as a button too (the same reason the
  /// deselect button exists).
  String get selectionClosePolygon => _s('selectionClosePolygon');

  // --- Shared window verbs (the AppWindow action row) ---
  String get commonSave => _s('commonSave');
  String get commonDelete => _s('commonDelete');
  String get commonRename => _s('commonRename');
  String get commonLink => _s('commonLink');
  String get commonPreview => _s('commonPreview');

  // --- The rename family (AppPromptDialog) ---
  String get renameLayerTitle => _s('renameLayerTitle');
  String get renameLayerField => _s('renameLayerField');
  String get renameLayerEmpty => _s('renameLayerEmpty');
  String get renameCutTitle => _s('renameCutTitle');
  String get renameCutField => _s('renameCutField');
  String get renameCutEmpty => _s('renameCutEmpty');
  String get renameFrameTitle => _s('renameFrameTitle');
  String get renameFrameField => _s('renameFrameField');

  /// A KEY's name is a link, exactly as a frame's is: same name, same
  /// value. The wording stays parallel because the flow is the same one.
  String get renameKeyTitle => _s('renameKeyTitle');
  String get renameKeyField => _s('renameKeyField');

  /// A drawing guide's name — the label the overlay paints over its axis,
  /// so an empty one has nothing to draw and is refused.
  String get renameGuideTitle => _s('renameGuideTitle');
  String get renameGuideField => _s('renameGuideField');
  String get renameGuideEmpty => _s('renameGuideEmpty');

  /// The cut's note — empty is allowed, it CLEARS the note.
  String get cutNoteTitle => _s('cutNoteTitle');
  String get cutNoteField => _s('cutNoteField');

  // --- Confirmations ---
  String get deleteLayerTitle => _s('deleteLayerTitle');

  /// '{name}' is replaced with the layer name.
  String get deleteLayerMessageTemplate => _s('deleteLayerMessageTemplate');
  String get frameNameConflictTitle => _s('frameNameConflictTitle');
  String get frameNameConflictBody => _s('frameNameConflictBody');

  // --- The instance editors ---
  String get seInstanceNewTitle => _s('seInstanceNewTitle');
  String get seInstanceEditTitle => _s('seInstanceEditTitle');
  String get seNameLabel => _s('seNameLabel');
  String get seDialogueLabel => _s('seDialogueLabel');
  String get seLinkedAudioLabel => _s('seLinkedAudioLabel');
  String get seLinkedAudioNone => _s('seLinkedAudioNone');
  String get seUnlinkAudio => _s('seUnlinkAudio');

  /// '{frame}' is replaced with the 1-based frame number.
  String get keyInterpolationLinear => _s('keyInterpolationLinear');
  String get keyInterpolationHold => _s('keyInterpolationHold');

  // --- Convert to linked cut ---
  String get convertLinkedCutTitle => _s('convertLinkedCutTitle');

  /// '{cut}' is replaced with the origin cut's name.
  String get convertLinkedCutBodyTemplate => _s('convertLinkedCutBodyTemplate');
  String get convertLinkedCutTargetLabel => _s('convertLinkedCutTargetLabel');

  /// '{names}' is the comma-joined layer list.
  String get convertLinkedCutLinksTemplate =>
      _s('convertLinkedCutLinksTemplate');

  /// '{count}' drawings, '{cut}' the target cut. The origin's picture wins
  /// each same-name conflict (원본 승리) — announced up front.
  String get convertLinkedCutReplacedTemplate =>
      _s('convertLinkedCutReplacedTemplate');

  /// '{count}' is the joining drawing count.
  String get convertLinkedCutJoiningTemplate =>
      _s('convertLinkedCutJoiningTemplate');

  /// '{cut}' gains '{names}'.
  String get convertLinkedCutTargetGainsTemplate =>
      _s('convertLinkedCutTargetGainsTemplate');

  /// '{names}' join THIS cut.
  String get convertLinkedCutOriginGainsTemplate =>
      _s('convertLinkedCutOriginGainsTemplate');
  String get convertLinkedCutNothing => _s('convertLinkedCutNothing');
  String get convertLinkedCutUndoNote => _s('convertLinkedCutUndoNote');
  String get convertLinkedCutResizeFirst => _s('convertLinkedCutResizeFirst');

  // Drawing guides (symmetry / perspective).
  String get guideKindSymmetry => _s('guideKindSymmetry');
  String get guideKindPerspective => _s('guideKindPerspective');
  String get guideAdd => _s('guideAdd');
  String get guideDelete => _s('guideDelete');
  String get guideShow => _s('guideShow');
  String get guideActsOn => _s('guideActsOn');
  String get guideActsOff => _s('guideActsOff');
  String get guideLibraryEmpty => _s('guideLibraryEmpty');
  String get guideSelectPrompt => _s('guideSelectPrompt');
  String get guideLineCount => _s('guideLineCount');
  String get guideMirrorMode => _s('guideMirrorMode');
  String get guideMirrorModeOn => _s('guideMirrorModeOn');
  String get guideMirrorModeOff => _s('guideMirrorModeOff');
  String get guideEyeLevelShow => _s('guideEyeLevelShow');
  String get guideConstrainToEyeLevel => _s('guideConstrainToEyeLevel');
  String get guideConstrainToEyeLevelNote => _s('guideConstrainToEyeLevelNote');
  String get guideVanishingPoint => _s('guideVanishingPoint');
  String get guideVanishingPointAtInfinity =>
      _s('guideVanishingPointAtInfinity');
  String get guideAddVanishingPoint => _s('guideAddVanishingPoint');
  String get guideMakeVertical => _s('guideMakeVertical');

  // --- Project lifecycle confirmations ---
  String get closeProjectTitle => _s('closeProjectTitle');
  String get closeProjectBody => _s('closeProjectBody');
  String get closeProjectVanishedBody => _s('closeProjectVanishedBody');
  String get commonSaveAs => _s('commonSaveAs');

  /// The window a manual save puts in front of itself, running and finished.
  ///
  /// The finished line is the point of the pair. The running one only says
  /// what is happening; this one is the answer to "did it save?", which is
  /// a question the app never used to answer at all.
  String get saveProgressRunning => _s('saveProgressRunning');
  String get saveProgressDone => _s('saveProgressDone');
  String get savePrepareRunning => _s('savePrepareRunning');
  String get savePrepareDone => _s('savePrepareDone');
  String get openProgressRunning => _s('openProgressRunning');
  String get openProgressDone => _s('openProgressDone');

  /// '{sec}' is whole seconds waited. Names the CLOUD as the one doing
  /// the work — the app is not slow, the file is not here yet.
  String get openWaitingCloudTemplate => _s('openWaitingCloudTemplate');

  /// '{sec}' is whole seconds waited. Said once the wait is long enough
  /// to be worth a decision; the window's cancel is the decision.
  String get openWaitingStalledTemplate => _s('openWaitingStalledTemplate');
  String get resizeProgressRunning => _s('resizeProgressRunning');
  String get resizeProgressDone => _s('resizeProgressDone');

  /// The wait window over a bake — a movie's frames into cels, at placement
  /// or by the reference button's rasterize.
  String get bakeProgressRunning => _s('bakeProgressRunning');
  String get bakeProgressDone => _s('bakeProgressDone');
  String get unsavedAutosaveTitle => _s('unsavedAutosaveTitle');
  String get unsavedAutosaveBody => _s('unsavedAutosaveBody');
  String get commonNotNow => _s('commonNotNow');

  // --- The menu bar's own headings and its one stateful entry ---
  /// The top strip's two buttons (the menu bar's successor).
  String get topStripProject => _s('topStripProject');
  String get topStripSettings => _s('topStripSettings');

  String get menuBarFile => _s('menuBarFile');
  String get menuBarEdit => _s('menuBarEdit');
  String get menuBarCut => _s('menuBarCut');
  String get menuBarLayer => _s('menuBarLayer');
  String get menuBarPlayback => _s('menuBarPlayback');
  String get menuBarWindow => _s('menuBarWindow');
  String get menuBarHelp => _s('menuBarHelp');
  String get menuPlay => _s('menuPlay');
  String get menuPause => _s('menuPause');

  // --- Project files ---
  String get fileOpenTitle => _s('fileOpenTitle');
  String get fileSaveTitle => _s('fileSaveTitle');
  String get fileStorageOffNotice => _s('fileStorageOffNotice');
  String get fileOpenSettings => _s('fileOpenSettings');
  String get fileNameLabel => _s('fileNameLabel');
  String get fileCloudNoticeOpen => _s('fileCloudNoticeOpen');
  String get replaceFileTitle => _s('replaceFileTitle');

  /// '{name}' is the colliding file name.
  String get replaceFileMessageTemplate => _s('replaceFileMessageTemplate');
  String get commonReplace => _s('commonReplace');

  // --- The native folder pickers (PICK-2) ---
  String get folderNoPathTitle => _s('folderNoPathTitle');
  String get folderStorageOffTitle => _s('folderStorageOffTitle');
  String get folderPickUnavailable => _s('folderPickUnavailable');

  /// PICK-6: shown once per session when a FOLDER pick comes back cancelled
  /// on Apple. Google Drive greys out Open in folder mode, and the app
  /// cannot tell that apart from a real cancel — the delegate is never
  /// called — so this is the only moment left to say it.
  String get folderPickDriveNotice => _s('folderPickDriveNotice');
  String get projectChooserEmpty => _s('projectChooserEmpty');
  String get fileNameEmpty => _s('fileNameEmpty');
  String get recentProjectsTitle => _s('recentProjectsTitle');
  String get recentReconnect => _s('recentReconnect');
  String get sortByName => _s('sortByName');
  String get sortByModified => _s('sortByModified');
  String get sortBySize => _s('sortBySize');
  String get sortAscending => _s('sortAscending');
  String get sortDescending => _s('sortDescending');

  // --- Canvas size ---
  String get canvasSizeTitle => _s('canvasSizeTitle');
  String get cameraSizeTitle => _s('cameraSizeTitle');
  String get canvasWidthLabel => _s('canvasWidthLabel');
  String get canvasHeightLabel => _s('canvasHeightLabel');

  /// '{min}'/'{max}' are the dimension bounds.
  String get canvasAnchorHelpTemplate => _s('canvasAnchorHelpTemplate');
  String get canvasPresetDefault => _s('canvasPresetDefault');
  String get commonResize => _s('commonResize');

  // --- Alpha preview ---
  String get menuAlphaPreview => _s('menuAlphaPreview');

  // --- Input settings ---
  String get inputTitle => _s('inputTitle');
  String get inputPressureHeading => _s('inputPressureHeading');
  String get inputPressureSoftHard => _s('inputPressureSoftHard');
  String get inputPressureLinear => _s('inputPressureLinear');
  String get inputSpeedHeading => _s('inputSpeedHeading');
  String get inputSpeedReference => _s('inputSpeedReference');
  String get inputCanvasHeading => _s('inputCanvasHeading');
  String get inputRightClick => _s('inputRightClick');
  String get inputWheelClick => _s('inputWheelClick');
  String get inputPenTail => _s('inputPenTail');
  String get inputCanvasTouchHeading => _s('inputCanvasTouchHeading');
  String get inputDragOneFinger => _s('inputDragOneFinger');
  String get inputDragTwoFingers => _s('inputDragTwoFingers');
  String get inputDragThreeFingers => _s('inputDragThreeFingers');
  String get inputExtraFinger => _s('inputExtraFinger');
  String get inputExtraFingerHelp => _s('inputExtraFingerHelp');
  String get inputFlipHaptics => _s('inputFlipHaptics');
  String get inputFlipHapticsHelp => _s('inputFlipHapticsHelp');
  String get inputTwoFingerRotation => _s('inputTwoFingerRotation');
  String get inputTwoFingerRotationHelp => _s('inputTwoFingerRotationHelp');
  String get inputRotationLock => _s('inputRotationLock');
  String get inputRotationLockHelp => _s('inputRotationLockHelp');
  String get inputRotationSnap => _s('inputRotationSnap');
  String get inputZoomSnaps => _s('inputZoomSnaps');
  String get inputBrushSizeSnaps => _s('inputBrushSizeSnaps');
  String get inputTabletHeading => _s('inputTabletHeading');
  String get inputTabletStandard => _s('inputTabletStandard');
  String get inputTabletStandardHelp => _s('inputTabletStandardHelp');
  String get inputTabletWintab => _s('inputTabletWintab');
  String get inputTabletWintabHelp => _s('inputTabletWintabHelp');
  String get inputTabletAutoDemoted => _s('inputTabletAutoDemoted');
  String get dragActionFlip => _s('dragActionFlip');
  String get dragActionScreen => _s('dragActionScreen');
  String get dragActionBrushSize => _s('dragActionBrushSize');
  String get dragActionDraw => _s('dragActionDraw');
  String get commonNone => _s('commonNone');
  String get mapEyedropper => _s('mapEyedropper');
  String get mapEraser => _s('mapEraser');
  String get mapPan => _s('mapPan');
  String get mapUndo => _s('mapUndo');
  String get mapRedo => _s('mapRedo');
  String get holdReturnToTool => _s('holdReturnToTool');
  String get holdKeep => _s('holdKeep');

  // --- Preferences ---
  String get prefsTitle => _s('prefsTitle');
  String get prefsInput => _s('prefsInput');
  String get prefsAutosave => _s('prefsAutosave');
  String get prefsAudio => _s('prefsAudio');
  String get prefsLanguage => _s('prefsLanguage');
  String get prefsAccent => _s('prefsAccent');
  String get prefsDisplay => _s('prefsDisplay');
  String get prefsSystem => _s('prefsSystem');
  String get prefsMemory => _s('prefsMemory');
  String get memoryProcessTotal => _s('memoryProcessTotal');
  String get memoryTracked => _s('memoryTracked');
  String get memoryUntracked => _s('memoryUntracked');
  String get memoryAvailable => _s('memoryAvailable');
  String get memoryPinned => _s('memoryPinned');
  String get memoryDeviceTotal => _s('memoryDeviceTotal');
  String get memoryAllowance => _s('memoryAllowance');
  String get memoryAllowanceAutomatic => _s('memoryAllowanceAutomatic');
  String get memoryItemDrawings => _s('memoryItemDrawings');
  String get memoryItemSheetInk => _s('memoryItemSheetInk');
  String get memoryItemUndo => _s('memoryItemUndo');
  String get memoryItemPlaybackFrames => _s('memoryItemPlaybackFrames');
  String get memoryItemLayerImages => _s('memoryItemLayerImages');
  String get memoryItemBrushTips => _s('memoryItemBrushTips');
  String get memoryItemPanelRasters => _s('memoryItemPanelRasters');
  String get memoryItemViewerPages => _s('memoryItemViewerPages');
  String get memoryItemImageCache => _s('memoryItemImageCache');
  String get memoryItemStoryboardThumbnails =>
      _s('memoryItemStoryboardThumbnails');
  String get memoryItemMoviePictures => _s('memoryItemMoviePictures');
  String get memoryItemTileImages => _s('memoryItemTileImages');
  String get memoryItemEngineBuffers => _s('memoryItemEngineBuffers');
  String get containerAreaSettings => _s('containerAreaSettings');
  String get containerAreaDiagnostics => _s('containerAreaDiagnostics');
  String get containerAreaSessionScratch => _s('containerAreaSessionScratch');
  String get containerTotal => _s('containerTotal');
  String get saveCelsLostTemplate => _s('saveCelsLostTemplate');

  /// The fold over the drawings a save could not carry (C-save-percent) —
  /// drawings, not the files [commonAffectedFiles] heads.
  String get saveCelsLostHeading => _s('saveCelsLostHeading');

  /// A line of that fold for a picture the project holds no place for.
  String get saveCelsLostGone => _s('saveCelsLostGone');
  String get projectFileVanished => _s('projectFileVanished');

  // --- Display (R11) ---
  String get uiScaleLabel => _s('uiScaleLabel');

  // --- Accent colours ---
  String get accentTitle => _s('accentTitle');
  String get accent1Label => _s('accent1Label');
  String get accent1Help => _s('accent1Help');

  // --- Sheet info ---
  String get sheetInfoTitle => _s('sheetInfoTitle');
  String get sheetFieldTitle => _s('sheetFieldTitle');
  String get sheetFieldEpisode => _s('sheetFieldEpisode');
  String get sheetFieldScene => _s('sheetFieldScene');
  String get sheetFieldCut => _s('sheetFieldCut');
  String get sheetFieldTime => _s('sheetFieldTime');
  String get sheetFieldName => _s('sheetFieldName');
  String get sheetFieldSheet => _s('sheetFieldSheet');
  String get sheetTitleHint => _s('sheetTitleHint');
  String get sheetArtist => _s('sheetArtist');
  String get sheetStaffByProcess => _s('sheetStaffByProcess');
  String get sheetVisibleBoxes => _s('sheetVisibleBoxes');
  String get sheetStampPick => _s('sheetStampPick');
  String get sheetStampClear => _s('sheetStampClear');
  String get sheetNotation => _s('sheetNotation');
  String get sheetExposureBar => _s('sheetExposureBar');
  String get sheetExposureBarHelp => _s('sheetExposureBarHelp');
  String get sheetExposureBarN => _s('sheetExposureBarN');
  String get sheetSeEmptyFill => _s('sheetSeEmptyFill');

  // --- The instruction vocabulary and its events ---
  String get instructionsTitle => _s('instructionsTitle');
  String get instructionEditTooltip => _s('instructionEditTooltip');
  String get instructionDeleteTooltip => _s('instructionDeleteTooltip');
  String get instructionAddButton => _s('instructionAddButton');
  String get instructionDefTitle => _s('instructionDefTitle');
  String get instructionDefNameLabel => _s('instructionDefNameLabel');
  String get instructionEventEditTitle => _s('instructionEventEditTitle');
  String get instructionEventAddTitle => _s('instructionEventAddTitle');
  String get instructionMarkLabel => _s('instructionMarkLabel');
  String get instructionNameLabel => _s('instructionNameLabel');
  String get instructionStartLabel => _s('instructionStartLabel');
  String get instructionEndLabel => _s('instructionEndLabel');
  String get instructionMemoLabel => _s('instructionMemoLabel');
  String get instructionEditSetButton => _s('instructionEditSetButton');
  String get instructionEditorIcon => _s('instructionEditorIcon');
  String get instructionEditorColor => _s('instructionEditorColor');
  String get instructionEditorMark => _s('instructionEditorMark');
  String get systemStatusHelp => _s('systemStatusHelp');

  // --- The timeline action toolbar and its flyouts ---
  String get tlAddLayerHeader => _s('tlAddLayerHeader');
  String get tlNoLayers => _s('tlNoLayers');
  String get tlLegendLayer => _s('tlLegendLayer');
  String get tlAllDisplayedOpacity => _s('tlAllDisplayedOpacity');
  String get tlLinkedLayerTooltip => _s('tlLinkedLayerTooltip');

  /// The reference row's file button — its tooltip, the button being an
  /// icon only — and its popover's first line when the press acts on
  /// several rows (미디어 배치 라운드 3).
  String get tlLayerReference => _s('tlLayerReference');
  String get tlSelectedLayers => _s('tlSelectedLayers');

  /// The reference popover's warning line: the row runs [frames] PROJECT
  /// frames past the end of the file it points at (유저 2026-09-12).
  ///
  /// ⚠️A METHOD, so the reader table above does not list it — that table is
  /// built by scanning this file for `String get`, and a key taking `{n}`
  /// has no getter to scan. `exCelCount` is the same shape for the same
  /// reason; ADDING a line for this one turns the table's own check red.
  String tlReferenceSourceShort(int frames) =>
      _s('tlReferenceSourceShort').replaceFirst('{n}', '$frames');

  String get tlAudioLane => _s('tlAudioLane');
  String get tlNameTagGroup => _s('tlNameTagGroup');
  String get tlTransformGroup => _s('tlTransformGroup');
  String get tlRunEdgeNone => _s('tlRunEdgeNone');
  String get tlRunEdgeHold => _s('tlRunEdgeHold');
  String get tlSelectedFrameRange => _s('tlSelectedFrameRange');
  String get tlSelectedLaneRange => _s('tlSelectedLaneRange');
  String get tlSelectedCell => _s('tlSelectedCell');
  String get tlSelectedPanelRange => _s('tlSelectedPanelRange');
  String get semLayer => _s('semLayer');
  String get semSelectedLayer => _s('semSelectedLayer');
  String get semTrack => _s('semTrack');
  String get semSelectedTrack => _s('semSelectedTrack');
  String get sbVideoTrack => _s('sbVideoTrack');
  String get noticeFillRegionOpen => _s('noticeFillRegionOpen');
  String get noticeCameraKeysCopied => _s('noticeCameraKeysCopied');
  String get tlSameAsSelected => _s('tlSameAsSelected');
  String get tlKindAnimation => _s('tlKindAnimation');
  String get tlKindStoryboard => _s('tlKindStoryboard');
  String get tlKindImage => _s('tlKindImage');
  String get tlKindText => _s('tlKindText');
  String get tlKindAdjustment => _s('tlKindAdjustment');
  String get tlKindFolder => _s('tlKindFolder');
  String get tlKindSe => _s('tlKindSe');
  String get tlKindTransition => _s('tlKindTransition');
  String get tlKindCamera => _s('tlKindCamera');

  /// A row's kind said as a SCREEN-READER label: '{kind}' is the kind name.
  ///
  /// ⚠️A template rather than a suffix, because the suffix is not a suffix
  /// in every language — fr puts the noun first and ja/zh take no space.
  /// Building this by appending ' layer' was the reason the rail's labels
  /// could never be translated at all.
  String get tlKindSemanticTemplate => _s('tlKindSemanticTemplate');

  // --- The text cel editor (R5) ---
  String get textCelNewTitle => _s('textCelNewTitle');
  String get textCelEditTitle => _s('textCelEditTitle');
  String get textCelTextLabel => _s('textCelTextLabel');
  String get textCelFontLabel => _s('textCelFontLabel');
  String get textCelFontSystem => _s('textCelFontSystem');
  String get textCelSizeLabel => _s('textCelSizeLabel');
  String get textCelAlignLabel => _s('textCelAlignLabel');
  String get textCelAlignLeft => _s('textCelAlignLeft');
  String get textCelAlignCenter => _s('textCelAlignCenter');
  String get textCelAlignRight => _s('textCelAlignRight');
  String get textCelColorLabel => _s('textCelColorLabel');
  String get textCelBoldLabel => _s('textCelBoldLabel');
  String get seNameTagShowLineLabel => _s('seNameTagShowLineLabel');
  String get seNameTagLineInkLabel => _s('seNameTagLineInkLabel');

  /// The name-tag preview's FIXED samples (R5 #7) — it shows the look, not
  /// the block's own text, so these never change with the playhead.
  String get seNameTagPreviewName => _s('seNameTagPreviewName');
  String get seNameTagPreviewLine => _s('seNameTagPreviewLine');
  String get textCelOutlineLabel => _s('textCelOutlineLabel');
  String get textCelBackgroundLabel => _s('textCelBackgroundLabel');
  String get textCelPositionLabel => _s('textCelPositionLabel');

  // --- The SE name tag editor (R5b) ---
  String get seNameTagTitle => _s('seNameTagTitle');
  String get seNameTagHint => _s('seNameTagHint');
  String get seNameTagPositionLabel => _s('seNameTagPositionLabel');
  String get seNameTagBoxLabel => _s('seNameTagBoxLabel');
  String get seNameTagSampleName => _s('seNameTagSampleName');
  String get seNameTagSampleLine => _s('seNameTagSampleLine');
  String get seNameTagReset => _s('seNameTagReset');

  /// The cut-scoped camera row's DISPLAY name: "Direction layer". The code
  /// kind stays [LayerKind.instruction] (save compatibility) — only the word
  /// the user reads changed, so the camera section can name its three types
  /// apart: camera, direction layer, transition layer.
  String get tlKindInstruction => _s('tlKindInstruction');

  /// The WORD for the drawn-past-the-end margin, spelled across the handle in
  /// the ruler. The ruler prefixes it with the TERM that asked for the margin
  /// — "O.L のりしろ", "O.L 여백" — so the length says what caused it.
  ///
  /// Japanese keeps the trade word のりしろ; every other language says its own
  /// word for MARGIN, because のりしろ is not borrowed outside Japanese.
  String get tlNoriShiro => _s('tlNoriShiro');
  String get tlAttachFreeAbove => _s('tlAttachFreeAbove');
  String get tlAttachFreeBelow => _s('tlAttachFreeBelow');
  String get tlAttachSyncedAbove => _s('tlAttachSyncedAbove');
  String get tlAttachSyncedBelow => _s('tlAttachSyncedBelow');
  String get tlLayerCommands => _s('tlLayerCommands');
  String get tlFrameCommands => _s('tlFrameCommands');
  String get tlLayer => _s('tlLayer');
  String get tlFrame => _s('tlFrame');
  String get tlDuplicateLayer => _s('tlDuplicateLayer');
  String get tlSelectRowSpan => _s('tlSelectRowSpan');
  String get tlLinkDuplicateLayer => _s('tlLinkDuplicateLayer');
  String get tlUnlinkLayer => _s('tlUnlinkLayer');
  String get tlResetGroup => _s('tlResetGroup');
  String get tlRenameLayer => _s('tlRenameLayer');
  String get tlCopyLayer => _s('tlCopyLayer');
  String get tlDeleteLayer => _s('tlDeleteLayer');
  String get tlEffects => _s('tlEffects');
  String get tlAddEffectTemplate => _s('tlAddEffectTemplate');
  String get tlRemoveEffectTemplate => _s('tlRemoveEffectTemplate');
  String get tlDropIntoFolderTemplate => _s('tlDropIntoFolderTemplate');
  String get tlDropOutOfFolder => _s('tlDropOutOfFolder');
  String get tlDropAttachSyncedTemplate => _s('tlDropAttachSyncedTemplate');
  String get tlDropAttachFreeTemplate => _s('tlDropAttachFreeTemplate');
  String get tlDropDetachAttach => _s('tlDropDetachAttach');

  /// ⑦: the one landing a folder attach has no home for — an organizer
  /// folder is FLAT, so a folder carrying a folder cannot become one.

  String get tlDetachLayer => _s('tlDetachLayer');

  /// 폴더가 어태치가 될 때 fx 를 잃는다는 확인창(유저 2026-08-29). ⚠️「fx」는
  /// **fx 를 펼쳐서 보이는 전부**다 — 네임태그·트랜스폼·추가 fx. 그래서 문장도
  /// 나눠 쓰지 않고 「fx」 하나로 말한다.
  String get tlAttachDropsFxTitle => _s('tlAttachDropsFxTitle');
  String get tlAttachDropsFxBody => _s('tlAttachDropsFxBody');

  /// ⛔No trailing '…' on a BAR BUTTON's writing (B9, 유저 2026-08-17:
  /// 「심플하게 編集」) — this one and [tlSetCommasN] wore it and read as
  /// ellipsized labels on device. The '…' convention belongs to menu
  /// ENTRIES that open a dialog, not to the buttons themselves.
  String get tlSharedEdit => _s('tlSharedEdit');
  String get tlAdd => _s('tlAdd');
  String get tlBlankX => _s('tlBlankX');
  String get tlMark => _s('tlMark');

  /// 🚨F-61 — it used to be `brAutoCreateFrame`, in the brush panel. 유저:
  /// 「프레임 자동생성 버튼 툴 설정에 있는데, **왜 이딴식으로 결정한거지?**
  /// … 프레임 알약 안, 중간나누기 버튼 오른쪽에 두도록」. The key follows the
  /// control: this is a timeline string now, and the `br` prefix would have
  /// pointed the next reader at a panel it no longer lives in.
  String get tlAutoFrame => _s('tlAutoFrame');

  /// Design D: the rigid shove as a verb. PUSH opens frames at the anchor
  /// and everything after travels with its spacing; PULL closes them and
  /// stops where the first affected row runs out of room.
  String get tlPush => _s('tlPush');
  String get tlPull => _s('tlPull');
  String get tlSetCommasN => _s('tlSetCommasN');

  /// Refused: a cut holds at most one storyboard row.
  String get sbOneStoryboardRowPerCut => _s('sbOneStoryboardRowPerCut');

  /// The conte sheet panel.
  String get cnActionColumn => _s('cnActionColumn');
  String get cnConte => _s('cnConte');

  /// '{n}' is the comma count.
  String get tlSetCommaTemplate => _s('tlSetCommaTemplate');
  String get tlProjectAudioRate => _s('tlProjectAudioRate');
  String get tlCustom => _s('tlCustom');
  String get tlShowSeRows => _s('tlShowSeRows');
  String get tlShowCameraRows => _s('tlShowCameraRows');
  String get tlStoryboardLayer => _s('tlStoryboardLayer');

  // --- The cut command group ---
  /// The cut PILL's name cell — the noun itself, beside [tlLayer] and
  /// [tlFrame]. The pill's first cell writes the noun out (유저 확정: 컷 ·
  /// 레이어 · 프레임은 아이콘 말고 텍스트), so all three need a short word.
  String get tlCut => _s('tlCut');
  String get cutCommands => _s('cutCommands');
  String get cutAddCut => _s('cutAddCut');
  String get cutNewCut => _s('cutNewCut');
  String get cutDuplicateCut => _s('cutDuplicateCut');
  String get cutDuplicateActive => _s('cutDuplicateActive');
  String get cutRename => _s('cutRename');
  String get cutEditNote => _s('cutEditNote');
  String get cutMoveLeft => _s('cutMoveLeft');
  String get cutMoveRight => _s('cutMoveRight');
  String get cutDelete => _s('cutDelete');

  // --- The media pool ---
  String get mediaActions => _s('mediaActions');
  String get mediaImportAudio => _s('mediaImportAudio');
  String get mediaRename => _s('mediaRename');

  /// The pool row's way onto the timeline for a hand that would rather
  /// not drag — and the only way at all until the drop targets land.
  String get mediaPlace => _s('mediaPlace');

  String get mediaRelink => _s('mediaRelink');

  /// RELINK-2: the loss banner. `{n}` is replaced with the count rather
  /// than concatenated at the call site, because the number sits in a
  /// different place in each language ("3 files not found" vs "못 찾은
  /// 파일 3개").
  String get mediaMissingCount => _s('mediaMissingCount');
  String get mediaFindInFolder => _s('mediaFindInFolder');

  /// The batch-relink preview. `{m}` of `{n}` — shown BEFORE anything is
  /// applied, because a folder that matches almost nothing is the signal
  /// that the wrong folder was picked.
  String get mediaRelinkFound => _s('mediaRelinkFound');

  /// While the candidate folder is being read — which on a cloud folder
  /// means every same-size candidate is being fetched.
  String get mediaRelinkScanning => _s('mediaRelinkScanning');
  String get mediaRelinkScanned => _s('mediaRelinkScanned');
  String get mediaRemove => _s('mediaRemove');

  /// F-118: removing a pool file something still uses — the question, and
  /// the heading over the list of uses that it and the in-use mark's window
  /// both show.
  String get mediaRemoveInUse => _s('mediaRemoveInUse');
  String get mediaUsesHeading => _s('mediaUsesHeading');
  String get mediaRegisterInProject => _s('mediaRegisterInProject');
  String get mediaExportWav => _s('mediaExportWav');
  String get mediaExportWavNoAudio => _s('mediaExportWavNoAudio');
  String get mediaCarriedState => _s('mediaCarriedState');
  String get mediaReferencedState => _s('mediaReferencedState');

  /// Shown on opening a project written by a build that kept its media in
  /// a sibling folder. `{name}` is that folder.
  ///
  /// It says the folder is dead and what makes it collectable, and stops
  /// there: the app does not delete the user's files. It reappears on
  /// every open until they do, which is honest — the folder is still
  /// there, and the media inside it is still the only copy until a save
  /// takes it in.
  String get projectLegacyAssetsFolder => _s('projectLegacyAssetsFolder');
  String get mediaOpenInViewer => _s('mediaOpenInViewer');
  String get mediaOpenInSubViewer => _s('mediaOpenInSubViewer');

  // --- The media viewer (R4, §6-h) ---
  String get mediaViewerEmpty => _s('mediaViewerEmpty');
  String get mediaViewerOpenFile => _s('mediaViewerOpenFile');
  String get mediaViewerLoadFailed => _s('mediaViewerLoadFailed');
  String get mediaViewerCutTooLarge => _s('mediaViewerCutTooLarge');
  String get mediaViewerCannotDisplay => _s('mediaViewerCannotDisplay');
  String get mediaViewerNoPdfRenderer => _s('mediaViewerNoPdfRenderer');
  String get mediaViewerNoVideoDecoder => _s('mediaViewerNoVideoDecoder');

  /// Sound the viewer cannot read. ⚠️Its own sentence rather than the
  /// generic 「이 종류는 표시할 수 없다」, for the reason the video one has
  /// its own: a missing decoder is a different BUILD, which is something
  /// the reader can act on.
  String get mediaViewerNoAudioDecoder => _s('mediaViewerNoAudioDecoder');

  /// 🚨★★★EVERY PICKER SHOWS EVERY FILE — 유저 2026-08-29: 「픽커는 어떤
  /// 플랫폼이든 어떤 확장자던 선택할수 있게하고, 대응만 지원안되는
  /// 확장자면 그 때 해당 파일 지원안된다고 안내창 띄우게」. This is that
  /// notice.
  String get unsupportedFileTitle => _s('unsupportedFileTitle');

  /// '{name}' is the picked file's name, '{kinds}' the extensions this
  /// particular opening accepts.
  String get unsupportedFileMessageTemplate =>
      _s('unsupportedFileMessageTemplate');

  /// The gear on every canvas pill. Not "view settings" — the host puts its
  /// own verbs in the same list (유저 확정 2026-08-13: 등록·맞바꾸기는 ⚙ 안으로).
  String get panelSettings => _s('panelSettings');
  String get mediaViewerSwap => _s('mediaViewerSwap');
  String get mediaViewerRegisterAsset => _s('mediaViewerRegisterAsset');

  // --- Workspace panel names ---
  String get panelCanvas => _s('panelCanvas');
  String get panelColorWheel => _s('panelColorWheel');
  String get panelColorRgb => _s('panelColorRgb');
  String get panelColorPalette => _s('panelColorPalette');
  String get transportIn => _s('transportIn');
  String get transportOut => _s('transportOut');
  String get transportLoop => _s('transportLoop');
  String get transportPrevFrame => _s('transportPrevFrame');
  String get transportNextFrame => _s('transportNextFrame');
  String get colorRecent => _s('colorRecent');
  String get colorBackgroundSwap => _s('colorBackgroundSwap');
  String get penPressureTitle => _s('penPressureTitle');
  String get penPressureAxis => _s('penPressureAxis');
  String get brushDynamicsTitle => _s('brushDynamicsTitle');
  String get curveSourcePressure => _s('curveSourcePressure');
  String get curveSourceTilt => _s('curveSourceTilt');
  String get curveSourceSpeed => _s('curveSourceSpeed');
  String get onionCurrentDrawing => _s('onionCurrentDrawing');
  String get audioLevelMeter => _s('audioLevelMeter');
  String get panelMedia => _s('panelMedia');
  String get panelMediaViewer => _s('panelMediaViewer');
  String get panelMediaViewerSub => _s('panelMediaViewerSub');
  String get panelOnionSkin => _s('panelOnionSkin');
  String get panelToolSize => _s('panelToolSize');
  String get panelStoryboard => _s('panelStoryboard');
  String get panelTimeline => _s('panelTimeline');
  String get panelTimesheet => _s('panelTimesheet');
  String get panelConte => _s('panelConte');
  String get panelEnvelope => _s('panelEnvelope');
  String get commonRegister => _s('commonRegister');
  String get commonNameField => _s('commonNameField');
  String get tipRegisterTitle => _s('tipRegisterTitle');
  String get panelToolLibrary => _s('panelToolLibrary');
  String get panelCollapseRegion => _s('panelCollapseRegion');
  String get panelNewGroup => _s('panelNewGroup');
  String get panelRegionWidth => _s('panelRegionWidth');
  String get panelExpandRegion => _s('panelExpandRegion');
  String get panelToolSettings => _s('panelToolSettings');
  String get panelTools => _s('panelTools');

  // --- The onion skin panel ---
  String get onionBefore => _s('onionBefore');
  String get onionAfter => _s('onionAfter');
  String get onionBeforeTint => _s('onionBeforeTint');
  String get onionAfterTint => _s('onionAfterTint');
  String get onionGhostColorHelp => _s('onionGhostColorHelp');
  String get onionPegCountHelp => _s('onionPegCountHelp');

  // --- The shortcut editor ---
  String get shortcutTitle => _s('shortcutTitle');
  String get shortcutResetAll => _s('shortcutResetAll');
  String get shortcutResetToDefault => _s('shortcutResetToDefault');
  String get shortcutRecordNew => _s('shortcutRecordNew');
  String get shortcutTouch => _s('shortcutTouch');
  String get shortcutSearch => _s('shortcutSearch');
  String get shortcutConflictBanner => _s('shortcutConflictBanner');
  String get shortcutRecordingHint => _s('shortcutRecordingHint');

  // --- Playback transport and the sheet page rail ---
  String get playbackQuality => _s('playbackQuality');
  String get playbackStop => _s('playbackStop');
  String get playbackToStart => _s('playbackToStart');
  String get sheetPreviousPage => _s('sheetPreviousPage');
  String get sheetNextPage => _s('sheetNextPage');
  String get sheetPageDrag => _s('sheetPageDrag');

  // --- Autosave settings ---
  String get autosaveTitle => _s('autosaveTitle');
  String get autosaveEvery => _s('autosaveEvery');
  String get autosaveSectionHelp => _s('autosaveSectionHelp');
  String get autosaveSwitchHelp => _s('autosaveSwitchHelp');
  String get appContainerTitle => _s('appContainerTitle');
  String get appContainerHelp => _s('appContainerHelp');
  String get containerEmpty => _s('containerEmpty');
  String get commonMinutesShort => _s('commonMinutesShort');

  // --- The export window ---
  String get exExport => _s('exExport');
  String get exAddToQueue => _s('exAddToQueue');
  String get exImage => _s('exImage');
  String get exVideo => _s('exVideo');
  String get exCels => _s('exCels');
  String get exSheetPng => _s('exSheetPng');
  String get exFormat => _s('exFormat');
  String get exOptions => _s('exOptions');
  String get exNaming => _s('exNaming');
  String get exScope => _s('exScope');
  String get exQuality => _s('exQuality');
  String get exCodec => _s('exCodec');
  String get exBitrate => _s('exBitrate');
  String get exChannels => _s('exChannels');
  String get exAudio => _s('exAudio');
  String get exBrowse => _s('exBrowse');
  String get exSavePreset => _s('exSavePreset');
  String get exPresetNameEmpty => _s('exPresetNameEmpty');
  String get exBaseName => _s('exBaseName');
  String get exSuffix => _s('exSuffix');
  String get exDigits => _s('exDigits');
  String get exApplyLayerFx => _s('exApplyLayerFx');
  String get exApplyLayerFxHelp => _s('exApplyLayerFxHelp');
  String get exMuxSeMix => _s('exMuxSeMix');
  String get exLabel => _s('exLabel');
  String get exApply => _s('exApply');
  String get exAdd => _s('exAdd');
  String get exSelect => _s('exSelect');
  String get exSelBase => _s('exSelBase');
  String get exSelAttach => _s('exSelAttach');
  String get exSelSheet => _s('exSelSheet');
  String get exSelDirection => _s('exSelDirection');
  String get exSelCustom => _s('exSelCustom');
  String get exPaperLabel => _s('exPaperLabel');
  String get exArtLabel => _s('exArtLabel');
  String get exTakeLatest => _s('exTakeLatest');
  String get exFolders => _s('exFolders');
  String get exNameParts => _s('exNameParts');
  String get exTarget => _s('exTarget');
  String get exLayer => _s('exLayer');
  String exCelCount(int count) =>
      (count == 1 ? exCelCountOne : _s('exCelCount'))
          .replaceFirst('{n}', '$count');

  /// [exCelCount]'s singular: one picture is the reference popover's
  /// commonest count, and 「1 cels」 is what it would have said.
  String get exCelCountOne => _s('exCelCountOne');
  String get exProject => _s('exProject');
  String get exCut => _s('exCut');
  String get exWhite => _s('exWhite');
  String get exBlack => _s('exBlack');
  String get exBackground => _s('exBackground');
  String get exChooseLocation => _s('exChooseLocation');
  String get exNoCels => _s('exNoCels');
  String get exNoCuts => _s('exNoCuts');
  String get exPresets => _s('exPresets');
  String get exQueue => _s('exQueue');
  String get exSize => _s('exSize');

  /// The cut envelope's own words: its form (서식), the paper it prints on
  /// and the layers it paints.
  String get exForm => _s('exForm');
  String get exCutSize => _s('exCutSize');
  String get exRealSheet => _s('exRealSheet');
  String get exWidth => _s('exWidth');
  String get exSheetLayers => _s('exSheetLayers');
  String get exContent => _s('exContent');
  String get exInk => _s('exInk');
  String get exFiles => _s('exFiles');
  String get exOneImage => _s('exOneImage');
  String get exOnePerLayer => _s('exOnePerLayer');

  /// The import window's own words. ⚠️Cancel · Resize · Name · Timeline are
  /// NOT here — they are `commonCancel`, `commonResize`, `commonNameField`
  /// and `panelTimeline`, which already say them.
  String get imImport => _s('imImport');
  String get imPool => _s('imPool');
  String get imFile => _s('imFile');
  String get imFiles => _s('imFiles');
  String get imInto => _s('imInto');
  String get imFit => _s('imFit');
  String get imRevisions => _s('imRevisions');
  String get imFilesButton => _s('imFilesButton');
  String get imCutFolderButton => _s('imCutFolderButton');

  /// The file table's columns — 「size」 here is a file's BYTES, which is a
  /// different question from the export's pixel [exSize].
  String get imModified => _s('imModified');
  String get imSize => _s('imSize');
  String get imArchivedProcesses => _s('imArchivedProcesses');
  String get imMultiCutFolders => _s('imMultiCutFolders');

  /// The interpretation table's row names — what the window recognised in
  /// what was picked. ⚠️Cut · Layer and the cel count are `exCut`,
  /// `exLayer` and `exCelCount`; a file's KIND is `exAudio`/`exImage`/
  /// `exVideo`, which is what the export window already calls them.
  String get imProcess => _s('imProcess');
  String get imPicture => _s('imPicture');
  String get imReference => _s('imReference');
  String get imExcluded => _s('imExcluded');
  String get imIgnored => _s('imIgnored');
  String get imMultiCutMark => _s('imMultiCutMark');
  String get imPickToSee => _s('imPickToSee');

  /// A note that names a few files and counts the rest — '{n}' is how many
  /// names were not listed.
  String imAndMore(int count) =>
      _s('imAndMore').replaceFirst('{n}', '$count');

  /// The placement strip and the window's title when it places one file, and
  /// the words for a pill that cannot be used from where the window opened.
  String get imPlaceLabel => _s('imPlaceLabel');
  String imPlaceTitle(String name) =>
      _s('imPlaceTitleTemplate').replaceAll('{name}', name);
  String get imPoolOnlyTooltip => _s('imPoolOnlyTooltip');
  String get imAlreadyPooledTooltip => _s('imAlreadyPooledTooltip');

  /// The file table's answers. The file column is the POOL's question
  /// (carry or link) and bake is the LAYER's (user 2026-09-11, round 5).
  String get imModeKeep => _s('imModeKeep');
  String get imModeReference => _s('imModeReference');
  String get imBake => _s('imBake');
  String get imSound => _s('imSound');
  String get commonOn => _s('commonOn');
  String get commonOff => _s('commonOff');
  String get imFitContain => _s('imFitContain');
  String get imFitStretch => _s('imFitStretch');
  String get imIntoNewLayer => _s('imIntoNewLayer');
  String get imIntoSeRow => _s('imIntoSeRow');
  String imIntoRowCell(String row, int frame) => _s('imIntoRowCellTemplate')
      .replaceAll('{row}', row)
      .replaceAll('{frame}', '$frame');
  String get imIntoNewCut => _s('imIntoNewCut');
  String get imPsdMerge => _s('imPsdMerge');
  String get imPsdExpand => _s('imPsdExpand');

  /// What the window says about its source and its run.
  String get imNoSource => _s('imNoSource');
  String imFileCount(int count) =>
      _s('imFileCountTemplate').replaceAll('{n}', '$count');
  String get imStatusImporting => _s('imStatusImporting');
  String get imStatusNothing => _s('imStatusNothing');
  String get imFolderGone => _s('imFolderGone');
  String imFolderUnreadable(String reason) =>
      _s('imFolderUnreadableTemplate').replaceAll('{reason}', reason);
  String get imCutFolderUnreadable => _s('imCutFolderUnreadable');
  String imUnreadable(String name) =>
      _s('imUnreadableTemplate').replaceAll('{name}', name);
  String imCorrupt(String name) =>
      _s('imCorruptTemplate').replaceAll('{name}', name);
  String imPagesFailed(String name, int count) => _s(
    'imPagesFailedTemplate',
  ).replaceAll('{name}', name).replaceAll('{n}', '$count');
  String imFramesFailed(String name, int count) => _s(
    'imFramesFailedTemplate',
  ).replaceAll('{name}', name).replaceAll('{n}', '$count');
  String imNoPdfRenderer(String name) =>
      _s('imNoPdfRendererTemplate').replaceAll('{name}', name);
  String imCouldNotImport(String name) =>
      _s('imCouldNotImportTemplate').replaceAll('{name}', name);
  String imPsdNoLayers(String name) =>
      _s('imPsdNoLayersTemplate').replaceAll('{name}', name);
  String imRenderingPdf(int done, int total) => _s(
    'imRenderingPdfTemplate',
  ).replaceAll('{done}', '$done').replaceAll('{total}', '$total');

  /// The size warning — a WARNING, so it may be a sentence. '{files}' is the
  /// named files and '{more}' the [imAndMore] tail.
  String imLargeCarry(String total, String files, String more) =>
      _s('imLargeCarryTemplate')
          .replaceAll('{total}', total)
          .replaceAll('{files}', files)
          .replaceAll('{more}', more);

  /// The cut-folder column's words.
  String get imKeepExplain => _s('imKeepExplain');
  String get imReferenceExplain => _s('imReferenceExplain');
  String get imCutFolderBakes => _s('imCutFolderBakes');
  String get imRevLatest => _s('imRevLatest');
  String get imRevAll => _s('imRevAll');
  String get imRevOriginals => _s('imRevOriginals');

  /// The media pool's states and its rename prompt.
  String get mpFileMissing => _s('mpFileMissing');
  String get mpInUseOnTimeline => _s('mpInUseOnTimeline');
  String get mpNameEmpty => _s('mpNameEmpty');

  /// '{w}'/'{h}' are the camera frame's pixel dimensions.
  String get exCameraTemplate => _s('exCameraTemplate');

  /// '{name}' is the current layer-group label.

  // --- Tools, the brush library and its settings ---
  String get toolBrush => _s('toolBrush');
  String get toolEraser => _s('toolEraser');
  String get toolEyedropper => _s('toolEyedropper');
  String get toolFill => _s('toolFill');
  String get toolSelect => _s('toolSelect');
  String get toolTransform => _s('toolTransform');
  String get toolShapeFill => _s('toolShapeFill');
  String get toolCutHint => _s('toolCutHint');
  String get toolCutNothingHeld => _s('toolCutNothingHeld');
  String get toolCutPasteAtOrigin => _s('toolCutPasteAtOrigin');
  String get toolCutFlipHorizontal => _s('toolCutFlipHorizontal');
  String get toolCutFlipVertical => _s('toolCutFlipVertical');
  String get toolCutRegisterTip => _s('toolCutRegisterTip');
  String get toolEyedropperReference => _s('toolEyedropperReference');
  String get brushSettingsTitle => _s('brushSettingsTitle');
  String get toolShapeRect => _s('toolShapeRect');
  String get toolShapeEllipse => _s('toolShapeEllipse');
  String get toolShapeLasso => _s('toolShapeLasso');
  String get toolShapePolygon => _s('toolShapePolygon');
  String get toolShapeSelectTemplate => _s('toolShapeSelectTemplate');
  String get toolShapeCutTemplate => _s('toolShapeCutTemplate');
  String get toolShapeFillTemplate => _s('toolShapeFillTemplate');
  String get brBrushesTitle => _s('brBrushesTitle');
  String get brGroupNameField => _s('brGroupNameField');
  String get brCreate => _s('brCreate');
  String get brRenameBrush => _s('brRenameBrush');
  String get brBrushNameField => _s('brBrushNameField');
  String get brGroupNameEmpty => _s('brGroupNameEmpty');
  String get brBrushNameEmpty => _s('brBrushNameEmpty');
  String get brResetLibraryBody => _s('brResetLibraryBody');
  String get brSize => _s('brSize');
  String get brOpacity => _s('brOpacity');
  String get brFlow => _s('brFlow');
  String get brMixing => _s('brMixing');
  String get brPaintAmount => _s('brPaintAmount');
  String get brPaintDensity => _s('brPaintDensity');
  String get brColorStretch => _s('brColorStretch');
  String get brHardness => _s('brHardness');
  String get stepUp => _s('stepUp');
  String get stepDown => _s('stepDown');
  String get brEdge => _s('brEdge');
  String get brEdgeNone => _s('brEdgeNone');
  String get brSpacing => _s('brSpacing');
  String get brAngle => _s('brAngle');
  String get brRoundness => _s('brRoundness');
  String get brScale => _s('brScale');
  String get brSizeJitter => _s('brSizeJitter');
  String get brOpacityJitter => _s('brOpacityJitter');
  String get brAngleJitter => _s('brAngleJitter');
  String get brRoundnessJitter => _s('brRoundnessJitter');
  String get brSpacingJitter => _s('brSpacingJitter');
  String get brScatter => _s('brScatter');
  String get brScatterCount => _s('brScatterCount');
  String get brScatterBothAxes => _s('brScatterBothAxes');
  String get brBrushTip => _s('brBrushTip');
  String get brTipNone => _s('brTipNone');
  String get brDualTip => _s('brDualTip');
  String get brTexture => _s('brTexture');
  String get brTextureDensity => _s('brTextureDensity');
  String get brTextureInvert => _s('brTextureInvert');
  String get brTextureBrightness => _s('brTextureBrightness');
  String get brTextureContrast => _s('brTextureContrast');
  String get brAddTipImage => _s('brAddTipImage');
  String get brRenameTip => _s('brRenameTip');
  String get brDeleteTip => _s('brDeleteTip');
  String get brTipRotation => _s('brTipRotation');
  String get brRotationFixed => _s('brRotationFixed');
  String get brRotationDirection => _s('brRotationDirection');
  String get brStabilizer => _s('brStabilizer');

  String get brBlend => _s('brBlend');
  String get brBlendMode => _s('brBlendMode');
  String get brDualBlend => _s('brDualBlend');
  String get brEditGroup => _s('brEditGroup');
  String get brFolderIcon => _s('brFolderIcon');
  String get brFolderName => _s('brFolderName');
  String get brFeather => _s('brFeather');
  String get brTolerance => _s('brTolerance');
  String get brGapClose => _s('brGapClose');
  String get brGrowShrink => _s('brGrowShrink');
  String get brAntiAlias => _s('brAntiAlias');
  String get brAntiAliasEdge => _s('brAntiAliasEdge');
  String get brTransformPreserveColors => _s('brTransformPreserveColors');
  String get brTransformPreserveColorsHint =>
      _s('brTransformPreserveColorsHint');
  String get brFillBeyondCanvas => _s('brFillBeyondCanvas');
  String get brOpenRegionsRefuse => _s('brOpenRegionsRefuse');
  String get brName => _s('brName');
  String get brDisplay => _s('brDisplay');
  String get brTipIcon => _s('brTipIcon');
  String get brStrokePreview => _s('brStrokePreview');
  String get brBrushOptions => _s('brBrushOptions');
  String get brGroupOptions => _s('brGroupOptions');
  String get brNewGroup => _s('brNewGroup');
  String get brRenameGroup => _s('brRenameGroup');
  String get brDeleteGroup => _s('brDeleteGroup');
  String get brRenameSelected => _s('brRenameSelected');
  String get brDeleteSelected => _s('brDeleteSelected');
  String get brSaveAsPreset => _s('brSaveAsPreset');
  String get brImportBrushes => _s('brImportBrushes');
  String get brResetLibrary => _s('brResetLibrary');
  String get brExportSelected => _s('brExportSelected');
  String get brExportGroup => _s('brExportGroup');
  String get brExportNothing => _s('brExportNothing');
  String get brExpand => _s('brExpand');
  String get trFlipHorizontal => _s('trFlipHorizontal');
  String get trFlipVertical => _s('trFlipVertical');
  String get trAnchor => _s('trAnchor');
  String get trAnchorOpposite => _s('trAnchorOpposite');
  String get trAnchorCenter => _s('trAnchorCenter');
  String get trMeshColumns => _s('trMeshColumns');
  String get trMeshRows => _s('trMeshRows');
  String get commonReset => _s('commonReset');
  String get commonFill => _s('commonFill');

  // --- Canvas view controls ---
  String get viewFitToView => _s('viewFitToView');
  String get viewResetView => _s('viewResetView');
  String get viewRotateLeft => _s('viewRotateLeft');
  String get viewRotateRight => _s('viewRotateRight');
  String get viewFlipHorizontal => _s('viewFlipHorizontal');
  String get viewFlipVertical => _s('viewFlipVertical');
  String get viewStraighten => _s('viewStraighten');
  String get viewZoomDrag => _s('viewZoomDrag');
  String get viewAngleDrag => _s('viewAngleDrag');
  String get viewDragDoubleTap => _s('viewDragDoubleTap');
  String get viewCanvasColor => _s('viewCanvasColor');
  String get viewPasteboardColor => _s('viewPasteboardColor');
  String get viewBackdropColor => _s('viewBackdropColor');
  String get colorUseCurrent => _s('colorUseCurrent');
  String get colorNone => _s('colorNone');

  // --- The layer-controls header (column toggles, solo, section fold) ---
  String get tlSections => _s('tlSections');
  String get tlAllDisplayedLayers => _s('tlAllDisplayedLayers');
  String get tlShowAll => _s('tlShowAll');
  String get tlHideAll => _s('tlHideAll');
  String get tlSoloKind => _s('tlSoloKind');
  String get tlSoloColor => _s('tlSoloColor');
  String get tlSoloFillReferences => _s('tlSoloFillReferences');
  String get tlSoloFxOnRows => _s('tlSoloFxOnRows');
  String get tlSoloSheetOnRows => _s('tlSoloSheetOnRows');
  String get tlApplyAllFx => _s('tlApplyAllFx');
  String get tlBypassAllFx => _s('tlBypassAllFx');
  String get tlAllOnTimesheet => _s('tlAllOnTimesheet');
  String get tlAllOffTimesheet => _s('tlAllOffTimesheet');
  String get tlClearAllMarks => _s('tlClearAllMarks');
  String get tlClearAllFillRefs => _s('tlClearAllFillRefs');
  String get tlColVisibility => _s('tlColVisibility');
  String get tlColLayerKind => _s('tlColLayerKind');
  String get tlColOnionSkin => _s('tlColOnionSkin');
  String get tlColOpacity => _s('tlColOpacity');
  String get tlColBlendMode => _s('tlColBlendMode');
  String get tlColFx => _s('tlColFx');
  String get tlColMark => _s('tlColMark');
  String get tlColFillReference => _s('tlColFillReference');
  String get tlColTimesheet => _s('tlColTimesheet');
  String get tlOpenOnionPanel => _s('tlOpenOnionPanel');
  String get tlLayerMark => _s('tlLayerMark');

  /// 색 라벨이 안 붙은 상태. ⚠️「수정 없음」이 아니라 라벨 자체가 없는 것 —
  /// 그 공정의 작업본은 「소재」다.
  String get tlLayerMarkNone => _s('tlLayerMarkNone');

  /// 上がり — 그 공정의 작업본. 유저 2026-08-27: 「제일 위에 수정없음말고
  /// 上がり 라고 하자 … 한국어로 **소재**로 가자. 영어도 그거 번역한걸로」.
  String get tlLayerMarkSource => _s('tlLayerMarkSource');

  /// 테이크 라벨(I-5) — 리테이크 몇 번째 판인가.
  String get tlLayerTake => _s('tlLayerTake');

  /// 팝오버에 풀어 쓰는 이름. 라벨에는 T1·T2 로 줄여 보인다.
  String tlLayerTakeNumber(int take) =>
      _s('tlLayerTakeNumber').replaceFirst('{n}', '$take');
  String get tlRepeat => _s('tlRepeat');
  String get tlRepeatSelection => _s('tlRepeatSelection');

  /// '{name}' is the speaker/effect name.
  String get tlSeNameTemplate => _s('tlSeNameTemplate');

  // --- Timeline toolbar prompts ---
  String get setCommasTitle => _s('setCommasTitle');
  String get setCommasField => _s('setCommasField');
  String get projectFpsTitle => _s('projectFpsTitle');
  String get projectFpsField => _s('projectFpsField');

  static AppStrings of(AppLanguage language) => switch (language) {
    AppLanguage.en => _en,
    AppLanguage.ja => _ja,
    AppLanguage.ko => _ko,
    AppLanguage.fr => _fr,
    AppLanguage.zhHans => _zhHans,
  };

  static const _enValues = <String, String>{
    'languageSettingsTitle': 'Language Settings',
    'programLanguageLabel': 'Program language',
    'notationLanguageLabel': 'Notation language',
    'programLanguageHelp': 'Menus, panels and labels.',
    'notationLanguageHelp': 'What prints on the timesheet and exports.',
    'noCutSelected': 'No cut selected',
    'pageLabel': 'Page',
    'continuousLabel': 'Continuous',
    'noticeNoFrameHere': 'No frame here',
    'noticeLayerNotDrawable': 'This layer cannot be drawn on',
    'noticeEditAttachOwner': 'Edit the owner layer',
    'commonCancel': 'Cancel',
    'commonApply': 'Apply',
    'commonRefresh': 'Refresh',
    'commonClose': 'Close',
    'commonAffectedFiles': 'Affected files',
    'commonNotice': 'Notice',
    'tlSharedDeselect': 'Deselect',
    'tlSharedColourEdit': 'Color Edit',
    'exportNoCuts': 'This project has no cuts to export yet.',
    'audioOffsetTitle': 'A/V offset',
    'audioOffsetHelp':
        'Fine-tunes when the picture is shown relative to the sound. The measurable part of the delay is corrected automatically; this removes what remains — wireless headphones commonly sit 150–300 ms behind and report nothing. Positive shows the picture LATER (sound arriving late is the common case).',
    'audioOffsetLabel': 'Offset',
    'audioUnitFrames': 'frames',
    'audioDevicesTitle': 'Devices',
    'audioDevicesHelp':
        'Which speaker playback uses and which microphone recording will use. Changes apply from the next playback run; a device that is no longer attached falls back to the system default.',
    'audioOutputLabel': 'Output',
    'audioInputLabel': 'Input',
    'audioSystemDefault': 'System default',
    'audioDeviceDefaultSuffix': ' (default)',
    'audioDeviceMissingSuffix': ' (missing)',
    'audioSyncInspectorTitle': 'Sync inspector',
    'recordVoiceTooltip': 'Record voice at the playhead',
    'recordVoiceStopTooltip': 'Stop recording (places the take)',
    'recordMicOpenFailed':
        'Could not open the microphone — check Preferences ▸ Audio and the OS microphone permission.',
    'recordMicPermissionDenied': 'Microphone permission was not granted.',
    'recordSelectSeLane':
        'Recording lands on the selected SE track — select one first.',
    'recordTakeClipped': 'The take clipped — the red corner marks the block.',
    'recordClipMarkerTooltip': 'This take clipped (recorded too hot)',
    'tlTransitionCrossingWarning': 'Crosses the cut boundary — not applied',
    'audioMicGainLabel': 'Mic gain (dB)',
    'audioInputChannelLabel': 'Input channels',
    'audioInputChannelDevice': 'As device',
    'audioInputChannelMonoMix': 'Mono mix',
    'audioInputChannelLeft': 'Left only',
    'audioInputChannelRight': 'Right only',
    'audioClippingNoticeLabel': 'Clipping warnings (toast + block marker)',
    'audioDenoiseLabel': 'Noise suppression (voice only — turn off for foley)',
    'audioInputMeterLabel': 'Input level',
    'audioTestSoundLabel': 'Test sound',
    'audioCountInLabel': 'Count-in (seconds)',
    'audioCueBeepsLabel': 'Cue beeps (ADR 3-beep)',
    'audioStreamerLabel': 'Streamer (punch-in wipe)',
    'recordNothingRecording': 'Nothing was recording.',
    'recordTakeEmpty': 'The take was empty — nothing to place.',
    'recordPlacementFailed': 'The recording could not be placed.',
    'recordDroppedFramesTemplate':
        'Recorded, but {count} frames were dropped (the machine could not keep up) — check the take.',
    'layerAudioTitle': 'Layer Audio',
    'audioGainLabel': 'Gain',
    'audioPanLabel': 'Pan',
    'layerAudioPanHelp':
        'Pan applies on the device mixer path (equal-power law).',
    'audioMute': 'Mute',
    'audioSolo': 'Solo',
    'fpsAudioTitleTemplate': '{from} → {to}: what happens to sound?',
    'fpsAudioBody':
        'These two rates differ by 0.1% in real speed, and audio exists in real seconds — it cannot stay both frame-exact and time-exact.\n\n• Keep audio timing: sounds keep their real seconds; their frame positions drift by 0.1% (about one frame every 42 seconds).\n\n• Pull audio 0.1%: sounds are resampled by the exact pulldown ratio (an inaudible pitch change — the standard telecine conform) so every sound keeps its exact frame span.',
    'fpsAudioKeep': 'Keep audio timing',
    'fpsAudioPull': 'Pull audio 0.1%',
    'selectionMoveConfirmTitle': 'Commit move',
    'selectionMoveConfirmBody': 'Commit the selection move?',
    'selectionMoveRevert': 'Revert',
    'selectionMoveApply': 'Commit',
    'selectionClosePolygon': 'Close shape',
    'commonSave': 'Save',
    'commonDelete': 'Delete',
    'commonRename': 'Rename',
    'commonLink': 'Link',
    'commonPreview': 'Preview',
    'renameLayerTitle': 'Rename layer',
    'renameLayerField': 'Layer name',
    'renameLayerEmpty': 'Layer name cannot be empty.',
    'renameCutTitle': 'Rename cut',
    'renameCutField': 'Cut name',
    'renameCutEmpty': 'Cut name cannot be empty.',
    'renameFrameTitle': 'Rename frame',
    'renameFrameField': 'Frame name',
    'renameKeyTitle': 'Rename key',
    'renameKeyField': 'Key name',
    'renameGuideTitle': 'Rename guide',
    'renameGuideField': 'Guide name',
    'renameGuideEmpty': 'Guide name cannot be empty.',
    'cutNoteTitle': 'Edit cut note',
    'cutNoteField': 'Cut note',
    'deleteLayerTitle': 'Delete layer',
    'deleteLayerMessageTemplate': 'Delete layer "{name}"?',
    'frameNameConflictTitle': 'Frame name already exists',
    'frameNameConflictBody':
        'This name is already used by another frame in this layer. Link to '
        'the existing named frame so the same name shares the same material?',
    'seInstanceNewTitle': 'New SE',
    'seInstanceEditTitle': 'Edit SE',
    'seNameLabel': 'Name (speaker — blank hides the box)',
    'seDialogueLabel': 'Dialogue',
    'seLinkedAudioLabel': 'Linked audio',
    'seLinkedAudioNone': 'None',
    'seUnlinkAudio': 'Unlink',
    'keyInterpolationLinear': 'Linear',
    'keyInterpolationHold': 'Hold',
    'convertLinkedCutTitle': 'Convert to linked cut',
    'convertLinkedCutBodyTemplate':
        'Link "{cut}" (origin) with another cut. Layers with the SAME NAME '
        'become one shared picture.',
    'convertLinkedCutTargetLabel': 'Link with cut',
    'convertLinkedCutLinksTemplate': 'Links {names}.',
    'convertLinkedCutReplacedTemplate':
        '{count} same-name drawing(s) in "{cut}" will be replaced by the '
        "origin's (원본 승리).",
    'convertLinkedCutJoiningTemplate':
        '{count} drawing(s) join the shared set.',
    'convertLinkedCutTargetGainsTemplate': '"{cut}" gains: {names}.',
    'convertLinkedCutOriginGainsTemplate': 'This cut gains: {names}.',
    'convertLinkedCutNothing':
        'Nothing to link — the cuts are already fully linked or share no '
        'drawing layers.',
    'convertLinkedCutUndoNote': 'Undo restores both cuts.',
    'convertLinkedCutResizeFirst':
        'These cuts have different canvas sizes. Linked cuts share one '
        'canvas, so this cut will be resized to the origin\'s size. Undo '
        'restores it.',
    'guideKindSymmetry': 'Symmetry',
    'guideKindPerspective': 'Perspective',
    'guideAdd': 'Add',
    'guideDelete': 'Delete',
    'guideShow': 'Show on canvas',
    'guideActsOn': 'Acting on strokes',
    'guideActsOff': 'Not acting',
    'guideLibraryEmpty': 'No guides in this cut yet.',
    'guideSelectPrompt': 'Pick a guide to edit its settings.',
    'guideLineCount': 'Copies',
    'guideMirrorMode': 'Line symmetry',
    'guideMirrorModeOn': 'Copies alternate handedness (a true mirror).',
    'guideMirrorModeOff': 'Copies are rotations — nothing is mirrored.',
    'guideEyeLevelShow': 'Show eye level',
    'guideConstrainToEyeLevel': 'Hold vanishing points on the eye level',
    'guideConstrainToEyeLevelNote':
        'Binds the next drag; it does not move what is already placed.',
    'guideVanishingPoint': 'Vanishing point',
    'guideVanishingPointAtInfinity': 'Parallel (at infinity)',
    'guideAddVanishingPoint': 'Add vanishing point',
    'guideMakeVertical': 'Make exactly vertical',
    'closeProjectTitle': 'Close project?',
    'closeProjectBody': 'Your changes are not saved. Close anyway?',
    'closeProjectVanishedBody':
        "This project's file is gone. Closing now takes the drawings that "
        'live only inside it. Save As writes what is still open to a new '
        'file.',
    'commonSaveAs': 'Save as…',
    'saveProgressRunning': 'Saving…',
    'saveProgressDone': 'Saved',
    'savePrepareRunning': 'Preparing…',
    'savePrepareDone': 'Ready',
    'openProgressRunning': 'Opening…',
    'openProgressDone': 'Opened',
    'openWaitingCloudTemplate': 'Downloading from the cloud · {sec}s',
    'openWaitingStalledTemplate': 'Nothing has arrived for {sec}s',
    'resizeProgressRunning': 'Resizing…',
    'resizeProgressDone': 'Resized',
    'bakeProgressRunning': 'Rasterizing…',
    'bakeProgressDone': 'Rasterized',
    'unsavedAutosaveTitle': 'Save your project',
    'unsavedAutosaveBody':
        'This project has never been saved, so autosave has nowhere to '
        'write. Pick a file and autosave will guard it from then on.',
    'commonNotNow': 'Not now',
    'topStripProject': 'Project',
    'topStripSettings': 'Settings',
    'menuBarFile': 'File',
    'menuBarEdit': 'Edit',
    'menuBarCut': 'Cut',
    'menuBarLayer': 'Layer',
    'menuBarPlayback': 'Playback',
    'menuBarWindow': 'Window',
    'menuBarHelp': 'Help',
    'menuPlay': 'Play',
    'menuPause': 'Pause',
    'fileOpenTitle': 'Open project',
    'fileSaveTitle': 'Save project',
    'fileStorageOffNotice':
        'Storage access is off — projects outside the app folder need the '
        'All-Files permission.',
    'fileOpenSettings': 'Open settings',
    'fileNameLabel': 'File name',
    'fileCloudNoticeOpen':
        'Cloud services (Google Drive, Dropbox …): use a sync app (Autosync, '
        'FolderSync …) and open its mirror folder here — direct cloud '
        'documents are not supported.',
    'replaceFileTitle': 'Replace file?',
    'replaceFileMessageTemplate': '{name} already exists here.',
    'commonReplace': 'Replace',
    'folderNoPathTitle': 'This location has no folder path',
    'folderStorageOffTitle': 'Storage access is off',
    'folderPickUnavailable': 'The folder picker could not be opened.',
    'folderPickDriveNotice':
        'Google Drive cannot hand over a folder. Use iCloud Drive, Dropbox, '
        'or this device.',
    'projectChooserEmpty': 'No Anicel projects in this folder.',
    'fileNameEmpty': 'File name cannot be empty.',
    'recentProjectsTitle': 'Recent projects',
    'recentReconnect': 'Reconnect',
    'sortByName': 'Name',
    'sortByModified': 'Modified',
    'sortBySize': 'Size',
    'sortAscending': 'Ascending',
    'sortDescending': 'Descending',
    'canvasSizeTitle': 'Canvas size',
    'cameraSizeTitle': 'Camera size',
    'canvasWidthLabel': 'Width (px)',
    'canvasHeightLabel': 'Height (px)',
    'canvasAnchorHelpTemplate':
        'Anchor: existing artwork stays pinned here. Cropped strokes are '
        'kept and reappear if the canvas grows again. ({min}–{max} px)',
    'canvasPresetDefault': 'Default',
    'commonResize': 'Resize',
    'menuAlphaPreview': 'Alpha preview',
    'inputTitle': 'Input settings',
    'inputPressureHeading': 'Pen pressure response',
    'inputPressureSoftHard': 'Soft ↔ Hard',
    'inputPressureLinear': 'Linear',
    'inputSpeedHeading': 'Pen speed response',
    'inputSpeedReference': 'Full speed at',
    'inputCanvasHeading': 'Canvas',
    'inputRightClick': 'Right click / pen side button',
    'inputWheelClick': 'Wheel click / pen upper button',
    'inputPenTail': 'Pen tail (turn the pen over)',
    'inputCanvasTouchHeading': 'Canvas touch',
    'inputDragOneFinger': '1-finger drag',
    'inputDragTwoFingers': '2-finger drag',
    'inputDragThreeFingers': '3-finger drag',
    'inputExtraFinger': 'Extra-finger modifier',
    'inputExtraFingerHelp':
        'A finger added DURING a gesture constrains it — snap '
        'zoom/rotation/size, fine frame steps.',
    'inputFlipHaptics': 'Flip haptics',
    'inputFlipHapticsHelp':
        'A tick each time the flip lands on a different drawing. Silent '
        'over empty space, and on devices without a motor.',
    'inputTwoFingerRotation': 'Two-finger rotation',
    'inputTwoFingerRotationHelp':
        'OFF: the navigate gesture pans and zooms only (the rotate '
        'buttons/shortcut stay).',
    'inputRotationLock': 'Modifier locks rotation',
    'inputRotationLockHelp':
        'ON: the extra finger FREEZES the angle (pure pan + snapped zoom). '
        'OFF (default): it snaps the angle.',
    'inputRotationSnap': 'Rotation snap (°)',
    'inputZoomSnaps': 'Zoom snaps (%)',
    'inputBrushSizeSnaps': 'Brush size snaps (px)',
    'inputTabletHeading': 'Tablet service',
    'inputTabletStandard': 'Standard (default)',
    'inputTabletStandardHelp':
        'The OS pointer pipeline (Windows Ink) — right for up-to-date '
        'drivers and built-in pens.',
    'inputTabletWintab': 'Wintab',
    'inputTabletWintabHelp':
        'Reads pressure straight from the tablet driver — the escape hatch '
        'when the pen arrives without pressure or as touch/mouse.',
    'inputTabletAutoDemoted':
        'Switched back to Standard: on the Wintab path the pen stopped '
        'reaching the window at all.',
    'dragActionFlip': 'Flip (frames / layers)',
    'dragActionScreen': 'Screen (pan · zoom · rotate)',
    'dragActionBrushSize': 'Brush size',
    'dragActionDraw': 'Touch drawing',
    'commonNone': 'None',
    'mapEyedropper': 'Eyedropper',
    'mapEraser': 'Eraser',
    'mapPan': 'Pan',
    'mapUndo': 'Undo',
    'mapRedo': 'Redo',
    'holdReturnToTool': 'Return to tool',
    'holdKeep': 'Keep',
    'prefsTitle': 'Preferences',
    'prefsInput': 'Input',
    'prefsAutosave': 'Autosave',
    'prefsAudio': 'Audio',
    'prefsLanguage': 'Language',
    'prefsAccent': 'Accent colors',
    'prefsDisplay': 'Display',
    'prefsSystem': 'System',
    'prefsMemory': 'Memory',
    'memoryProcessTotal': 'This app, in RAM',
    'memoryTracked': 'Accounted for',
    'memoryUntracked': 'Engine, fonts and framework',
    'memoryAvailable': 'Still available',
    'memoryPinned': 'held for playback',
    'memoryDeviceTotal': 'Device memory',
    'memoryAllowance': 'App allowance',
    'memoryAllowanceAutomatic': 'Back to the automatic allowance',
    'memoryItemDrawings': 'Drawings',
    'memoryItemSheetInk': 'Sheet handwriting',
    'memoryItemUndo': 'Undo history',
    'memoryItemPlaybackFrames': 'Playback frames',
    'memoryItemLayerImages': 'Layer images',
    'memoryItemBrushTips': 'Brush tips',
    'memoryItemPanelRasters': 'Panel rasters',
    'memoryItemViewerPages': 'Viewer pages',
    'memoryItemImageCache': 'Image cache',
    'memoryItemStoryboardThumbnails': 'Storyboard thumbnails',
    'memoryItemMoviePictures': 'Reference movies',
    'memoryItemTileImages': 'Canvas tile images',
    'memoryItemEngineBuffers': 'Drawing engine buffers',
    'containerAreaSettings': 'Settings',
    'containerAreaDiagnostics': 'Diagnostics log',
    'containerAreaSessionScratch': 'Session scratch',
    'containerTotal': 'Total',
    'saveCelsLostTemplate':
        'Saved, but {count} drawing(s) could not be included: the project '
        'file they were stored in was removed while the project was open.',
    'saveCelsLostHeading': 'Affected drawings',
    'saveCelsLostGone': 'A drawing the project no longer has',
    'projectFileVanished':
        // 🚨The old wording ended 「…and saving would lose them」. That was a
        // PREDICTION, and it stopped being true on one of the two platforms
        // the moment the session started holding the file open: on POSIX an
        // `unlink` leaves our handle readable, a save reads every cel into
        // its temp file before it renames, so saving RESCUES those drawings.
        // On Windows the file can only vanish while nothing is held, and
        // there it does lose them. No sentence is true both ways — and the
        // app already reports the MEASURED answer after the save, by count,
        // in [saveCelsLostTemplate]. The prediction goes; the measurement
        // stays.
        "This project's file is no longer there — deleted or moved. Restore "
        'it now if it is still in a trash: the drawings already saved live '
        'only inside that file.',
    'uiScaleLabel': 'Interface scale',
    'accentTitle': 'Accent colors',
    'accent1Label': 'Accent 1',
    'accent1Help': 'Selection, playhead, active toggles.',
    'sheetInfoTitle': 'Sheet info',
    'sheetFieldTitle': 'Title',
    'sheetFieldEpisode': 'Episode',
    'sheetFieldScene': 'Scene',
    'sheetFieldCut': 'Cut',
    'sheetFieldTime': 'Time',
    'sheetFieldName': 'Name',
    'sheetFieldSheet': 'Sheet',
    'sheetTitleHint': 'Project name when empty',
    'sheetArtist': 'Artist',
    'sheetStaffByProcess': 'Staff by process',
    'sheetVisibleBoxes': 'Visible boxes',
    'sheetStampPick': 'Choose stamp',
    'sheetStampClear': 'Remove stamp',
    'sheetNotation': 'Notation',
    'sheetExposureBar': 'Exposure hold bar',
    'sheetExposureBarHelp':
        'Draw the hold bar from the (N+1)th comma of N+ holds',
    'sheetExposureBarN': 'N (industry standard 3)',
    'sheetSeEmptyFill': 'Gray out empty SE stretches',
    'instructionsTitle': 'Instructions',
    'instructionEditTooltip': 'Edit instruction',
    'instructionDeleteTooltip': 'Delete instruction',
    'instructionAddButton': 'Add instruction',
    'instructionDefTitle': 'Instruction',
    'instructionDefNameLabel': 'Name (FI, PAN, …)',
    'instructionEventEditTitle': 'Edit instruction',
    'instructionEventAddTitle': 'Add instruction',
    'instructionMarkLabel': 'Instruction (mark)',
    'instructionNameLabel': 'Name (blank = instruction name)',
    'instructionStartLabel': 'Start name (A)',
    'instructionEndLabel': 'End name (B)',
    'instructionMemoLabel': 'Memo (timesheet memo band)',
    'instructionEditSetButton': 'Edit instructions…',
    'instructionEditorIcon': 'Icon',
    'instructionEditorColor': 'Color',
    'instructionEditorMark': 'Mark',
    'systemStatusHelp':
        'Which implementation each subsystem is running right now. Fallback paths keep the app working but usually run slower — the names are searchable if you want the details.',
    'cutCommands': 'Cut commands',
    'cutAddCut': 'Add cut',
    'cutNewCut': 'New cut',
    'cutDuplicateCut': 'Duplicate cut',
    'cutDuplicateActive': 'Duplicate active cut',
    'cutRename': 'Rename cut…',
    'cutEditNote': 'Edit cut note…',
    'cutMoveLeft': 'Move cut left',
    'cutMoveRight': 'Move cut right',
    'cutDelete': 'Delete cut',
    'mediaActions': 'Media actions',
    'mediaImportAudio': 'Import audio',
    'mediaRename': 'Rename media',
    'mediaPlace': 'Place…',
    'mediaRelink': 'Relink…',
    'mediaMissingCount': '{n} media files not found',
    'mediaFindInFolder': 'Find in folder…',
    'mediaRelinkFound': 'Found {m} of {n}. Relink them?',
    'mediaRelinkScanning': 'Reading that folder…',
    'mediaRelinkScanned': 'Folder read',
    'mediaRemove': 'Remove',
    'mediaRegisterInProject': 'Keep inside the project file',
    'mediaExportWav': 'Export as WAV',
    'mediaExportWavNoAudio': 'This asset has no audio to export.',
    'mediaCarriedState': 'In the project',
    'mediaReferencedState': 'Linked',
    'projectLegacyAssetsFolder':
        'This project still has a {name} folder beside it. Nothing writes '
        'there any more — save once and its media moves inside the project '
        'file, and then the folder can go.',
    'mediaRemoveInUse':
        'It is in use. Remove it anyway? The layers and frames placed from '
        'it will be deleted.',
    'mediaUsesHeading': 'Where it is used',
    'mediaOpenInViewer': 'Open in Viewer',
    'mediaOpenInSubViewer': 'Open in Sub Viewer',
    'mediaViewerEmpty':
        'Nothing to view yet.\nDouble-click a file in the media pool, '
        'or open one with the folder button above.',
    'mediaViewerOpenFile': 'Open File…',
    'mediaViewerLoadFailed': 'Could not read this file.',
    'mediaViewerCutTooLarge':
        'Too large to cut at full size within the memory allowance.',
    'mediaViewerCannotDisplay': 'This media kind has no viewer yet.',
    'mediaViewerNoPdfRenderer':
        'No PDF renderer in this build — PDF pages cannot be shown.',
    'mediaViewerNoVideoDecoder':
        'No video decoder in this build — movies cannot be shown.',
    'mediaViewerNoAudioDecoder':
        'This sound could not be read — no waveform to show.',
    'unsupportedFileTitle': 'Unsupported file',
    'unsupportedFileMessageTemplate':
        '"{name}" cannot be opened here. Usable formats: {kinds}.',
    'mediaViewerSwap': 'Swap with the other viewer',
    'mediaViewerRegisterAsset': 'Add to Media',
    'panelMediaViewer': 'Viewer',
    'panelMediaViewerSub': 'Sub Viewer',
    'panelCanvas': 'Canvas',
    'panelColorWheel': 'Colour wheel',
    'transportIn': 'In',
    'transportOut': 'Out',
    'transportLoop': 'Loop',
    'transportPrevFrame': 'Previous frame',
    'transportNextFrame': 'Next frame',
    'colorRecent': 'Recent',
    'colorBackgroundSwap': 'Background colour (tap to swap)',
    'penPressureTitle': 'Pen pressure',
    'penPressureAxis': 'Pressure →',
    'brushDynamicsTitle': 'Response',
    'curveSourcePressure': 'Pressure',
    'curveSourceTilt': 'Tilt',
    'curveSourceSpeed': 'Speed',
    'onionCurrentDrawing': 'Current drawing',
    'audioLevelMeter': 'audio level meter',
    'panelColorRgb': 'RGB',
    'panelColorPalette': 'Palette',
    'panelMedia': 'Media',
    'panelOnionSkin': 'Onion skin',
    'panelToolSize': 'Tool size',
    'panelStoryboard': 'Storyboard',
    'panelTimeline': 'Timeline',
    'panelTimesheet': 'Timesheet',
    'panelConte': 'Conte',
    'panelEnvelope': 'Envelope',
    'commonRegister': 'Register',
    'commonNameField': 'Name',
    'tipRegisterTitle': 'Register as Tip',
    'panelToolLibrary': 'Tool library',
    'panelCollapseRegion': 'Collapse',
    'panelNewGroup': 'New panel group',
    'panelRegionWidth': 'Region width',
    'panelExpandRegion': 'Expand',
    'panelToolSettings': 'Tool settings',
    'panelTools': 'Tools',
    'onionBefore': 'Before',
    'onionAfter': 'After',
    'onionBeforeTint': 'Before tint',
    'onionAfterTint': 'After tint',
    'onionGhostColorHelp': 'How the ghosts are colored',
    'onionPegCountHelp': 'What one peg counts',
    'shortcutTitle': 'Keyboard shortcuts',
    'shortcutResetAll': 'Reset all',
    'shortcutResetToDefault': 'Reset to default',
    'shortcutRecordNew': 'Record new shortcut',
    'shortcutTouch': 'Touch shortcut',
    'shortcutSearch': 'Search actions',
    'shortcutConflictBanner':
        'Some actions share the same key — the highlighted bindings collide.',
    'shortcutRecordingHint': 'Press keys… (Esc cancels)',
    'playbackQuality': 'Playback quality',
    'playbackStop': 'Stop',
    'playbackToStart': 'To start',
    'sheetPreviousPage': 'Previous page',
    'sheetNextPage': 'Next page',
    'sheetPageDrag': 'Page (drag / double-tap)',
    'autosaveTitle': 'Autosave',
    'autosaveEvery': 'Every',
    'autosaveSectionHelp':
        'Saves the project every so often, so a crash or a flat battery costs at most that much work.',
    'autosaveSwitchHelp':
        'Off means the project only changes when you save it, and a crash costs everything since.',
    'appContainerTitle': 'App container',
    'appContainerHelp':
        'What the app keeps outside your project files: settings and brush tips, media and audio an import brought in that no save has absorbed yet, and a diagnostics log.',
    'containerEmpty': 'Empty',
    'commonMinutesShort': ' min',
    'exExport': 'Export',
    'exAddToQueue': 'Add to queue',
    'exImage': 'Image',
    'exVideo': 'Video',
    'exCels': 'Cels',
    'exSheetPng': 'Sheet PNG',
    'exFormat': 'Format',
    'exOptions': 'Options',
    'exNaming': 'Naming',
    'exScope': 'Scope',
    'exQuality': 'Quality',
    'exCodec': 'Codec',
    'exBitrate': 'Bitrate',
    'exChannels': 'Channels',
    'exAudio': 'Audio',
    'exBrowse': 'Browse…',
    'exSavePreset': 'Save preset',
    'exPresetNameEmpty': 'Preset name cannot be empty.',
    'exBaseName': 'Base name',
    'exSuffix': 'Suffix',
    'exDigits': 'Digits',
    'exApplyLayerFx': 'Apply layer FX',
    'exApplyLayerFxHelp': 'Apply layer FX (transforms and animated opacity)',
    'exMuxSeMix': 'Mux the SE mix into the video',
    'exLabel': 'Label',
    'exApply': 'Apply',
    'exAdd': 'Add',
    'exSelect': 'Select',
    'exSelBase': 'Base',
    'exSelAttach': 'Attach',
    'exSelSheet': 'Sheet',
    'exSelDirection': 'Direction',
    'exSelCustom': 'Custom',
    'exPaperLabel': 'Paper',
    'exArtLabel': 'Art',
    'exTakeLatest': 'Latest',
    'exFolders': 'Folders',
    'exNameParts': 'Name',
    'exTarget': 'Target',
    'exLayer': 'Layer',
    'exCelCount': '{n} cels',
    'exCelCountOne': '{n} cel',
    'exProject': 'Project',
    'exCut': 'Cut',
    'exWhite': 'White',
    'exBlack': 'Black',
    'exBackground': 'BG',
    'exChooseLocation': 'Choose a location to enable Export.',
    'exNoCels': '(no cels)',
    'exNoCuts': '(no cuts)',
    'exPresets': 'Presets',
    'exQueue': 'Queue',
    'exSize': 'Size',
    'exForm': 'Form',
    'exCutSize': 'Cut size',
    'exRealSheet': 'Real sheet',
    'exWidth': 'Width',
    'exSheetLayers': 'Layers',
    'exContent': 'Content',
    'exInk': 'Ink',
    'exFiles': 'Files',
    'exOneImage': 'One image',
    'exOnePerLayer': 'One per layer',
    'imImport': 'Import',
    'imPool': 'Pool',
    'imFile': 'File',
    'imFiles': 'Files',
    'imInto': 'Into',
    'imFit': 'Fit',
    'imRevisions': 'Revisions',
    'imFilesButton': 'Files…',
    'imCutFolderButton': 'Cut folder…',
    'imModified': 'Modified',
    'imSize': 'Size',
    'imArchivedProcesses': 'Archived processes (LO/, GEN/…)',
    'imMultiCutFolders': 'Multi-cut folders (兼用)',
    'imProcess': 'Process',
    'imPicture': 'Picture',
    'imReference': 'Reference',
    'imExcluded': 'Excluded',
    'imIgnored': 'Ignored',
    'imMultiCutMark': '(multi-cut)',
    'imAndMore': ' and {n} more',
    'imPickToSee': 'Pick files or a cut folder to see the interpretation.',
    'imPlaceLabel': 'Place',
    'imPlaceTitleTemplate': 'Place — {name}',
    'imPoolOnlyTooltip': 'The media pool registers; place from the timeline.',
    'imAlreadyPooledTooltip': 'Already in the media pool.',
    'imModeKeep': 'Keep',
    'imModeReference': 'Link',
    'imBake': 'Rasterize',
    'imSound': 'Sound',
    'commonOn': 'On',
    'commonOff': 'Off',
    'imFitContain': 'Keep aspect',
    'imFitStretch': 'Stretch',
    'imIntoNewLayer': 'New layer',
    'imIntoSeRow': 'SE row',
    'imIntoRowCellTemplate': '{row} · frame {frame}',
    'imIntoNewCut': 'New cut',
    'imPsdMerge': 'Merge',
    'imPsdExpand': 'Expand',
    'imNoSource': 'No source selected',
    'imFileCountTemplate': '{n} files',
    'imStatusImporting': 'Importing…',
    'imStatusNothing': 'Nothing imported.',
    'imFolderGone': 'That folder is gone.',
    'imFolderUnreadableTemplate': 'Could not read the folder: {reason}',
    'imCutFolderUnreadable': 'Could not read that folder.',
    'imUnreadableTemplate': '{name}: could not read the file.',
    'imCorruptTemplate':
        '{name} could not be opened — corrupt or password-locked.',
    'imPagesFailedTemplate':
        '{name}: {n} page(s) failed to render — their cels stay empty.',
    'imFramesFailedTemplate':
        '{name}: {n} frame(s) failed to decode — their cels stay empty.',
    'imNoPdfRendererTemplate': '{name}: no PDF renderer in this build.',
    'imCouldNotImportTemplate': 'Could not import {name}.',
    'imPsdNoLayersTemplate':
        '{name}: no layers to expand — import it merged instead.',
    'imRenderingPdfTemplate': 'Rendering PDF page {done}/{total}…',
    'imLargeCarryTemplate':
        '{total} goes inside the project file — {files}{more}. Keeping compresses each file as it comes in, so the project grows by less than that. Linking leaves the originals where they are.',
    'imKeepExplain':
        'The project file holds these, compressed; the originals are left alone.',
    'imReferenceExplain':
        'The files stay where they are and the project points at them.',
    'imCutFolderBakes':
        'Cut folders always bake their cels; scans and movies stay linked.',
    'imRevLatest': 'Latest',
    'imRevAll': 'All',
    'imRevOriginals': 'Originals',
    'mpFileMissing': 'File missing — relink it',
    'mpInUseOnTimeline': 'In use on the timeline',
    'mpNameEmpty': 'Media name cannot be empty.',
    'exCameraTemplate': 'Camera {w}×{h}',
    'toolBrush': 'Brush',
    'toolEraser': 'Eraser',
    'toolEyedropper': 'Eyedropper',
    'toolFill': 'Fill',
    'toolSelect': 'Select',
    'toolTransform': 'Transform',
    'toolShapeFill': 'Shape Fill',
    'toolCutHint':
        'Cut copies the pixels under the drag — the original stays.\nPick Stamp to place the piece you are holding.',
    'toolCutNothingHeld':
        'Nothing held yet.\nCut a piece with the rectangle or lasso tile first.',
    'toolCutPasteAtOrigin': 'Paste at original position',
    'toolCutFlipHorizontal': 'Flip horizontal',
    'toolCutFlipVertical': 'Flip vertical',
    'toolCutRegisterTip': 'Register as Tip…',
    'toolEyedropperReference': 'Reference',
    'brushSettingsTitle': 'Brush Settings',
    'toolShapeRect': 'Rectangle',
    'toolShapeEllipse': 'Ellipse',
    'toolShapeLasso': 'Lasso',
    'toolShapePolygon': 'Polygon',
    'toolShapeSelectTemplate': '{shape} Select',
    'toolShapeCutTemplate': '{shape} Cut',
    'toolShapeFillTemplate': '{shape} Fill',
    'brBrushesTitle': 'Brushes',
    'brGroupNameField': 'Group name',
    'brCreate': 'Create',
    'brRenameBrush': 'Rename brush',
    'brBrushNameField': 'Brush name',
    'brGroupNameEmpty': 'Group name cannot be empty.',
    'brBrushNameEmpty': 'Brush name cannot be empty.',
    'brResetLibraryBody':
        'Replace the whole library — every group, imported pack and saved brush — with the built-in brushes?',
    'brSize': 'Size',
    'brOpacity': 'Opacity',
    'brFlow': 'Flow',
    'brMixing': 'Mix with ground colour',
    'brPaintAmount': 'Paint amount',
    'brPaintDensity': 'Paint density',
    'brColorStretch': 'Colour stretch',
    'brHardness': 'Hardness',
    'stepUp': 'Step up',
    'stepDown': 'Step down',
    'brEdge': 'Edge',
    'brEdgeNone': 'None',
    'brSpacing': 'Spacing',
    'brAngle': 'Angle',
    'brRoundness': 'Roundness',
    'brScale': 'Scale',
    'brSizeJitter': 'Size Jitter',
    'brOpacityJitter': 'Opacity Jitter',
    'brAngleJitter': 'Angle Jitter',
    'brRoundnessJitter': 'Roundness Jitter',
    'brSpacingJitter': 'Spacing Jitter',
    'brScatter': 'Scatter',
    'brScatterCount': 'Count',
    'brScatterBothAxes': 'Both Axes',
    'brTipRotation': 'Rotation',
    'brRotationFixed': 'Fixed',
    'brRotationDirection': 'Direction',
    'brBrushTip': 'Brush Tip',
    'brTipNone': 'None',
    'brDualTip': 'Dual Tip',
    'brTexture': 'Texture',
    'brTextureDensity': 'Density',
    'brTextureInvert': 'Invert',
    'brTextureBrightness': 'Brightness',
    'brTextureContrast': 'Contrast',
    'brAddTipImage': 'Add a tip from an image',
    'brRenameTip': 'Rename tip',
    'brDeleteTip': 'Delete tip',
    'brStabilizer': 'Stabilizer',
    'tlAutoFrame': 'Make a frame where there is none',
    'brBlend': 'Blend',
    'brBlendMode': 'Brush blend mode',
    'brDualBlend': 'Dual blend',
    'brEditGroup': 'Edit group',
    'brFolderIcon': 'Folder icon',
    'brFolderName': 'Folder name',
    'brFeather': 'Feather',
    'brTolerance': 'Tolerance',
    'brGapClose': 'Gap Close',
    'brGrowShrink': 'Grow/Shrink',
    'brAntiAlias': 'Anti-alias',
    'brAntiAliasEdge': 'Anti-alias edge',
    'brTransformPreserveColors': 'Preserve exact colours',
    'brTransformPreserveColorsHint':
        'Transform without making in-between '
        'colours',
    'brFillBeyondCanvas': 'Fill Beyond Canvas',
    'brOpenRegionsRefuse': 'Open regions refuse to fill',
    'brName': 'Name',
    'brDisplay': 'Display',
    'brTipIcon': 'Tip icon',
    'brStrokePreview': 'Stroke preview',
    'brBrushOptions': 'Brush options',
    'brGroupOptions': 'Group options',
    'brNewGroup': 'New group',
    'brRenameGroup': 'Rename group',
    'brDeleteGroup': 'Delete group',
    'brRenameSelected': 'Rename selected brush',
    'brDeleteSelected': 'Delete selected brush',
    'brSaveAsPreset': 'Save current settings as preset',
    'brImportBrushes': 'Import brushes (.abr, .sut, .sutg)',
    'brResetLibrary': 'Reset brush library',
    'brExportSelected': 'Export brush',
    'brExportGroup': 'Export brush group',
    'brExportNothing': 'There is nothing to export here.',
    'brExpand': 'Expand',
    'trFlipHorizontal': 'Flip Horizontal',
    'trFlipVertical': 'Flip Vertical',
    'trAnchor': 'Anchor',
    'trAnchorOpposite': 'Opposite corner',
    'trAnchorCenter': 'Center',
    'trMeshColumns': 'Columns',
    'trMeshRows': 'Rows',
    'commonReset': 'Reset',
    'commonFill': 'Fill',
    'viewFitToView': 'Fit to View',
    'viewResetView': 'Reset View (100%)',
    'panelSettings': 'Settings',
    'viewRotateLeft': 'Rotate View Left',
    'viewRotateRight': 'Rotate View Right',
    'viewFlipHorizontal': 'Flip View Horizontal',
    'viewFlipVertical': 'Flip View Vertical',
    'viewStraighten': 'Straighten View (0°)',
    'viewZoomDrag': 'Zoom (drag / double-tap)',
    'viewAngleDrag': 'View angle (drag / double-tap)',
    'viewDragDoubleTap': 'Drag / double-tap',
    'viewCanvasColor': 'Canvas color',
    'viewPasteboardColor': 'Pasteboard color',
    'viewBackdropColor': 'Backdrop color',
    'colorUseCurrent': 'Use current color',
    'colorNone': 'None',
    'tlSections': 'Sections',
    'tlAllDisplayedLayers': 'All displayed layers',
    'tlShowAll': 'Show all',
    'tlHideAll': 'Hide all',
    'tlSoloKind': 'Solo kind',
    'tlSoloColor': 'Solo color',
    'tlSoloFillReferences': 'Solo fill references',
    'tlSoloFxOnRows': 'Solo fx-on rows',
    'tlSoloSheetOnRows': 'Solo sheet-on rows',
    'tlApplyAllFx': 'Apply all fx',
    'tlBypassAllFx': 'Bypass all fx',
    'tlAllOnTimesheet': 'All on timesheet',
    'tlAllOffTimesheet': 'All off timesheet',
    'tlClearAllMarks': 'Clear all marks',
    'tlClearAllFillRefs': 'Clear all fill references',
    'tlColVisibility': 'Visibility column',
    'tlColLayerKind': 'Layer kind column',
    'tlColOnionSkin': 'Onion skin column',
    'tlColOpacity': 'Opacity column',
    'tlColBlendMode': 'Blend mode column',
    'tlColFx': 'FX column',
    'tlColMark': 'Mark column',
    'tlColFillReference': 'Fill reference column',
    'tlColTimesheet': 'Timesheet column',
    'tlOpenOnionPanel': 'Open onion skin panel',
    'tlLayerMark': 'Layer mark',
    'tlLayerMarkNone': 'No label',
    'tlLayerMarkSource': 'Material',
    'tlLayerTake': 'Take',
    'tlLayerTakeNumber': 'Take {n}',
    'tlRepeat': 'Repeat',
    'tlRepeatSelection': 'Repeat selection',
    'tlSeNameTemplate': 'SE name {name}',
    'tlAddLayerHeader': 'Add layer',
    'tlNoLayers': 'No layers',
    'tlLegendLayer': 'LAYER',
    'tlAllDisplayedOpacity': 'All displayed layers opacity',
    'tlLinkedLayerTooltip': 'Linked layer — pictures are shared',
    'tlLayerReference': 'Reference',
    'tlReferenceSourceShort': 'Runs {n} frames past the source',
    'tlSelectedLayers': 'Selected layers',
    'tlAudioLane': 'Audio',
    'tlNameTagGroup': 'Name Tag',
    'tlTransformGroup': 'Transform',
    'tlRunEdgeNone': 'None',
    'tlRunEdgeHold': 'Hold',
    'tlSelectedFrameRange': 'selected frame range',
    'tlSelectedLaneRange': 'selected lane range',
    'tlSelectedCell': 'selected cell',
    'tlSelectedPanelRange': 'selected panel range',
    'semLayer': 'layer',
    'semSelectedLayer': 'selected layer',
    'semTrack': 'track',
    'semSelectedTrack': 'selected track',
    'sbVideoTrack': 'Video track',
    'noticeFillRegionOpen':
        'Region is not closed — nothing filled (Fill Beyond Canvas needs an enclosed area).',
    'noticeCameraKeysCopied': 'Camera keyframes copied for After Effects.',
    'tlSameAsSelected': 'Same as selected',
    'tlKindAnimation': 'Animation',
    'tlKindStoryboard': 'Storyboard',
    'tlKindImage': 'Image',
    'tlKindText': 'Text',
    'tlKindAdjustment': 'Adjustment',
    'tlKindFolder': 'Folder',
    'tlKindSe': 'SE',
    'tlKindTransition': 'Transition',
    'tlKindCamera': 'Camera',
    'tlKindSemanticTemplate': '{kind} layer',
    'tlKindInstruction': 'Direction',
    'tlNoriShiro': 'MARGIN',
    'textCelNewTitle': 'New Text',
    'textCelEditTitle': 'Edit Text',
    'textCelTextLabel': 'Text',
    'textCelFontLabel': 'Font',
    'textCelFontSystem': 'System',
    'textCelSizeLabel': 'Size',
    'textCelAlignLabel': 'Align',
    'textCelAlignLeft': 'Left',
    'textCelAlignCenter': 'Center',
    'textCelAlignRight': 'Right',
    'textCelColorLabel': 'Ink',
    'textCelBoldLabel': 'Bold',
    'seNameTagShowLineLabel': 'Show dialogue',
    'seNameTagLineInkLabel': 'Dialogue ink',
    'seNameTagPreviewName': 'Name',
    'seNameTagPreviewLine': 'Line',
    'textCelOutlineLabel': 'Outline (white)',
    'textCelBackgroundLabel': 'Box (red)',
    'textCelPositionLabel': 'Position',
    'seNameTagTitle': 'SE Name Tag',
    'seNameTagHint':
        'Where this row\'s speaker label sits on the picture. The text is '
        'the block\'s own name and dialogue; the row\'s eye shows or hides '
        'the tag.',
    'seNameTagPositionLabel': 'Position',
    'seNameTagBoxLabel': 'Box',
    'seNameTagSampleName': 'Name',
    'seNameTagSampleLine': 'dialogue',
    'seNameTagReset': 'Reset',
    'tlAttachFreeAbove': 'Attach free layer above',
    'tlAttachFreeBelow': 'Attach free layer below',
    'tlAttachSyncedAbove': 'Attach synced layer above',
    'tlAttachSyncedBelow': 'Attach synced layer below',
    'tlLayerCommands': 'Layer commands',
    'tlFrameCommands': 'Frame commands',
    'tlCut': 'Cut',
    'tlLayer': 'Layer',
    'tlFrame': 'Frame',
    'tlDuplicateLayer': 'Duplicate layer',
    'tlSelectRowSpan': 'Select whole row',
    'tlLinkDuplicateLayer': 'Link duplicate layer',
    'tlUnlinkLayer': 'Unlink layer',
    'tlResetGroup': 'Reset (keeps keys)',
    'tlRenameLayer': 'Rename layer…',
    'tlCopyLayer': 'Copy layer',
    'tlDeleteLayer': 'Delete layer',
    'tlEffects': 'Effects',
    'tlAddEffectTemplate': 'Add {name}',
    'tlRemoveEffectTemplate': 'Remove {name}',
    'tlDropIntoFolderTemplate': 'into {name}',
    'tlDropOutOfFolder': 'out of the folder',
    'tlDropAttachSyncedTemplate': 'attach to {name} (synced)',
    'tlDropAttachFreeTemplate': 'attach to {name} (free)',
    'tlDropDetachAttach': 'detach',
    'tlDetachLayer': 'Detach from base',
    'tlAttachDropsFxTitle': 'Attaching drops its fx',
    'tlAttachDropsFxBody':
        'An attached layer keeps no fx of its own. Continuing discards the existing fx. Continue?',
    'tlSharedEdit': 'Edit',
    'tlAdd': 'Add',
    'tlPush': 'Push (open frames)',
    'tlPull': 'Pull (close frames)',
    'sbOneStoryboardRowPerCut':
        'This cut already has a storyboard row. A cut can hold only one.',
    'cnActionColumn': 'Action',
    'cnConte': 'Conte',
    'tlBlankX': 'Blank / X',
    'tlMark': 'Mark ●',
    'tlSetCommasN': 'Set N commas',
    'tlSetCommaTemplate': 'Set {n} comma exposure',
    'tlProjectAudioRate': 'Project audio sample rate',
    'tlCustom': 'Custom…',
    'tlShowSeRows': 'Show SE rows',
    'tlShowCameraRows': 'Show camera rows',
    'tlStoryboardLayer': 'Storyboard layer',
    'setCommasTitle': 'Set commas',
    'setCommasField': 'Exposure frames',
    'projectFpsTitle': 'Project frame rate',
    'projectFpsField': 'Frames per second',
  };

  static const _jaValues = <String, String>{
    'languageSettingsTitle': '言語設定',
    'programLanguageLabel': 'プログラム言語',
    'notationLanguageLabel': '表記言語',
    'programLanguageHelp': 'メニュー・パネル・ラベルの言語。',
    'notationLanguageHelp': 'タイムシートなど提出物に印字される言語。',
    'noCutSelected': 'カット未選択',
    'pageLabel': 'ページ',
    'continuousLabel': '連続表示',
    'noticeNoFrameHere': 'フレームがありません',
    'noticeLayerNotDrawable': 'このレイヤーには描けません',
    'noticeEditAttachOwner': '親レイヤーを編集してください',
    'commonCancel': 'キャンセル',
    'commonApply': '適用',
    'commonRefresh': '更新',
    'commonClose': '閉じる',
    'commonAffectedFiles': '該当ファイル',
    'commonNotice': 'お知らせ',
    'tlSharedDeselect': '選択解除',
    'tlSharedColourEdit': '色編集',
    'exportNoCuts': 'このプロジェクトには書き出せるカットがありません。',
    'audioOffsetTitle': 'A/Vオフセット',
    'audioOffsetHelp':
        '音に対して絵をいつ表示するかを微調整します。測定できる遅延は自動補正され、これは残りを取り除くための設定です — ワイヤレスイヤホンは150〜300ms遅れているのに何も報告しないのが普通です。正の値で絵が遅く表示されます（音が遅れて届くのが一般的なケース）。',
    'audioOffsetLabel': 'オフセット',
    'audioUnitFrames': 'コマ',
    'audioDevicesTitle': 'デバイス',
    'audioDevicesHelp':
        '再生に使うスピーカーと録音に使うマイクの選択。変更は次の再生から適用されます。取り外されたデバイスはシステム既定にフォールバックします。',
    'audioOutputLabel': '出力',
    'audioInputLabel': '入力',
    'audioSystemDefault': 'システム既定',
    'audioDeviceDefaultSuffix': '（既定）',
    'audioDeviceMissingSuffix': '（未接続）',
    'audioSyncInspectorTitle': '同期インスペクタ',
    'recordVoiceTooltip': '再生ヘッド位置にボイスを録音',
    'recordVoiceStopTooltip': '録音を停止（テイクを配置）',
    'recordMicOpenFailed': 'マイクを開けませんでした — 環境設定▸オーディオとOSのマイク権限を確認してください。',
    'recordMicPermissionDenied': 'マイクの権限が許可されませんでした。',
    'recordSelectSeLane': '録音は選択中のSEトラックに配置されます — 先にSEトラックを選択してください。',
    'recordTakeClipped': 'テイクがクリッピングしました — ブロックの赤い角が目印です。',
    'recordClipMarkerTooltip': 'このテイクはクリッピングしています（入力過大）',
    'tlTransitionCrossingWarning': 'カット境界を越えています — 適用されません',
    'audioMicGainLabel': 'マイクゲイン（dB）',
    'audioInputChannelLabel': '入力チャンネル',
    'audioInputChannelDevice': '装置のまま',
    'audioInputChannelMonoMix': 'モノラルミックス',
    'audioInputChannelLeft': '左のみ',
    'audioInputChannelRight': '右のみ',
    'audioClippingNoticeLabel': 'クリッピング警告（トースト＋ブロックマーカー）',
    'audioDenoiseLabel': 'ノイズ抑制（音声専用 — 効果音はオフに）',
    'audioInputMeterLabel': '入力レベル',
    'audioTestSoundLabel': 'テスト音を再生',
    'audioCountInLabel': 'カウントイン（秒）',
    'audioCueBeepsLabel': 'キュービープ（ADR式3ビープ）',
    'audioStreamerLabel': 'ストリーマー（パンチイン・ワイプ）',
    'recordNothingRecording': '録音中ではありません。',
    'recordTakeEmpty': 'テイクが空でした — 配置するものがありません。',
    'recordPlacementFailed': '録音を配置できませんでした。',
    'recordDroppedFramesTemplate':
        '録音しましたが{count}フレームが欠落しました（処理が追いつきませんでした）— テイクを確認してください。',
    'layerAudioTitle': 'レイヤーオーディオ',
    'audioGainLabel': 'ゲイン',
    'audioPanLabel': 'パン',
    'layerAudioPanHelp': 'パンはデバイスミキサー経路で適用されます（等パワー則）。',
    'audioMute': 'ミュート',
    'audioSolo': 'ソロ',
    'fpsAudioTitleTemplate': '{from} → {to}：音はどうしますか？',
    'fpsAudioBody':
        'この2つのレートは実速度が0.1%異なり、音は実時間で存在します — コマ厳密と時間厳密を両立することはできません。\n\n• 音のタイミングを維持：音は実時間を保ち、コマ位置が0.1%ずれます（約42秒ごとに1コマ）。\n\n• 音を0.1%プル：正確なプルダウン比でリサンプルします（聴き取れないピッチ変化 — テレシネの標準コンフォーム）。全ての音がコマ範囲を維持します。',
    'fpsAudioKeep': '音のタイミングを維持',
    'fpsAudioPull': '音を0.1%プル',
    'selectionMoveConfirmTitle': '移動の確定',
    'selectionMoveConfirmBody': '選択範囲の移動を確定しますか？',
    'selectionMoveRevert': '元に戻す',
    'selectionMoveApply': '確定',
    'selectionClosePolygon': '形を閉じる',
    'commonSave': '保存',
    'commonDelete': '削除',
    'commonRename': '名前を変更',
    'commonLink': 'リンク',
    'commonPreview': 'プレビュー',
    'renameLayerTitle': 'レイヤー名の変更',
    'renameLayerField': 'レイヤー名',
    'renameLayerEmpty': 'レイヤー名を空にはできません。',
    'renameCutTitle': 'カット名の変更',
    'renameCutField': 'カット名',
    'renameCutEmpty': 'カット名を空にはできません。',
    'renameFrameTitle': 'フレーム名の変更',
    'renameFrameField': 'フレーム名',
    'renameKeyTitle': 'キー名の変更',
    'renameKeyField': 'キー名',
    'renameGuideTitle': 'ガイド名の変更',
    'renameGuideField': 'ガイド名',
    'renameGuideEmpty': 'ガイド名を空にはできません。',
    'cutNoteTitle': 'カットメモの編集',
    'cutNoteField': 'カットメモ',
    'deleteLayerTitle': 'レイヤーの削除',
    'deleteLayerMessageTemplate': 'レイヤー「{name}」を削除しますか？',
    'frameNameConflictTitle': '同じフレーム名が既にあります',
    'frameNameConflictBody':
        'この名前はこのレイヤーの別のフレームで既に使われています。同じ名前が'
        '同じ素材を共有するよう、既存のフレームにリンクしますか？',
    'seInstanceNewTitle': 'SEの新規作成',
    'seInstanceEditTitle': 'SEの編集',
    'seNameLabel': '名前（話者 — 空欄でボックス非表示）',
    'seDialogueLabel': 'セリフ',
    'seLinkedAudioLabel': 'リンクされた音声',
    'seLinkedAudioNone': 'なし',
    'seUnlinkAudio': 'リンクを解除',
    'keyInterpolationLinear': 'リニア',
    'keyInterpolationHold': 'ホールド',
    'convertLinkedCutTitle': 'リンクカットに変換',
    'convertLinkedCutBodyTemplate':
        '「{cut}」（原本）を別のカットとリンクします。同じ名前のレイヤーが'
        '1枚の共有画になります。',
    'convertLinkedCutTargetLabel': 'リンクするカット',
    'convertLinkedCutLinksTemplate': '{names} をリンクします。',
    'convertLinkedCutReplacedTemplate':
        '「{cut}」の同名作画 {count} 枚が原本のもので置き換わります（原本優先）。',
    'convertLinkedCutJoiningTemplate': '作画 {count} 枚が共有セットに加わります。',
    'convertLinkedCutTargetGainsTemplate': '「{cut}」に追加：{names}。',
    'convertLinkedCutOriginGainsTemplate': 'このカットに追加：{names}。',
    'convertLinkedCutNothing':
        'リンクするものがありません — 既に完全にリンク済みか、共有できる'
        '作画レイヤーがありません。',
    'convertLinkedCutUndoNote': '元に戻すと両方のカットが復元されます。',
    'convertLinkedCutResizeFirst':
        'キャンバスサイズが異なります。兼用カットはキャンバスを共有するため'
        'このカットは元のカットのサイズに変更されます。元に戻すと復元されます。',
    'guideKindSymmetry': '対称',
    'guideKindPerspective': 'パース',
    'guideAdd': '追加',
    'guideDelete': '削除',
    'guideShow': 'キャンバスに表示',
    'guideActsOn': '線に効いている',
    'guideActsOff': '効いていない',
    'guideLibraryEmpty': 'このカットにはまだガイドがありません。',
    'guideSelectPrompt': '設定するガイドを選んでください。',
    'guideLineCount': '線の数',
    'guideMirrorMode': '線対称',
    'guideMirrorModeOn': 'コピーが左右反転します（本当の鏡）。',
    'guideMirrorModeOff': 'コピーは回転のみ — 反転しません。',
    'guideEyeLevelShow': 'アイレベルを表示',
    'guideConstrainToEyeLevel': '消失点をアイレベル上に固定',
    'guideConstrainToEyeLevelNote': '次のドラッグに効きます。すでに置いたものは動きません。',
    'guideVanishingPoint': '消失点',
    'guideVanishingPointAtInfinity': '平行（無限遠）',
    'guideAddVanishingPoint': '消失点を追加',
    'guideMakeVertical': '完全な垂直にする',
    'closeProjectTitle': 'プロジェクトを閉じますか？',
    'closeProjectBody': '変更は保存されていません。閉じますか？',
    'closeProjectVanishedBody':
        'このプロジェクトのファイルがなくなっています。このまま閉じると、その中にしか'
        'ない絵も一緒に失われます。「名前を付けて保存」なら、今開いているものを新しい'
        'ファイルに書き出せます。',
    'commonSaveAs': '名前を付けて保存…',
    'saveProgressRunning': '保存中…',
    'saveProgressDone': '保存しました',
    'savePrepareRunning': '準備中…',
    'savePrepareDone': '準備完了',
    'openProgressRunning': '読み込み中…',
    'openProgressDone': '読み込みました',
    'openWaitingCloudTemplate': 'クラウドから受信中 · {sec}秒',
    'openWaitingStalledTemplate': '{sec}秒間、まだ届いていません',
    'resizeProgressRunning': 'サイズ変更中…',
    'resizeProgressDone': 'サイズ変更しました',
    'bakeProgressRunning': 'ラスタライズ中…',
    'bakeProgressDone': 'ラスタライズしました',
    'unsavedAutosaveTitle': 'プロジェクトを保存',
    'unsavedAutosaveBody':
        'このプロジェクトはまだ一度も保存されていないため、自動保存の書き込み'
        '先がありません。ファイルを選べば、以降は自動保存が守ります。',
    'commonNotNow': '後で',
    'topStripProject': 'プロジェクト',
    'topStripSettings': '設定',
    'menuBarFile': 'ファイル',
    'menuBarEdit': '編集',
    'menuBarCut': 'カット',
    'menuBarLayer': 'レイヤー',
    'menuBarPlayback': '再生',
    'menuBarWindow': 'ウィンドウ',
    'menuBarHelp': 'ヘルプ',
    'menuPlay': '再生',
    'menuPause': '一時停止',
    'menuAction.file-open': '開く…',
    'menuAction.file-import': '読み込み／配置…',
    'menuAction.file-export': '書き出し…',
    'menuAction.edit-undo': '元に戻す',
    'menuAction.edit-redo': 'やり直す',
    'menuAction.edit-copy-frame': 'フレームをコピー',
    'menuAction.edit-paste-linked-frame': 'リンクフレームを貼り付け',
    'menuAction.edit-new-drawing': 'このフレームに新規作画',
    'menuAction.edit-delete-cell': 'セルを削除',
    'menuAction.edit-cut-exposure': '露光をカット',
    'menuAction.edit-toggle-mark': 'マークの切り替え',
    'menuAction.edit-keyboard-shortcuts': 'キーボードショートカット…',
    'menuAction.edit-preferences': '環境設定…',
    'menuAction.cut-new': 'カットを新規作成',
    'menuAction.cut-duplicate': 'カットを複製',
    'menuAction.cut-create-linked': 'リンクカットを作成',
    'menuAction.cut-convert-linked': 'リンクカットに変換…',
    'menuAction.cut-rename': 'カット名を変更…',
    'menuAction.cut-canvas-size': 'カンバスサイズ…',
    'menuAction.cut-move-left': 'カットを左へ',
    'menuAction.cut-move-right': 'カットを右へ',
    'menuAction.cut-copy-ae-camera': 'カメラのAEキーフレームをコピー',
    'menuAction.cut-delete': 'カットを削除',
    'menuAction.layer-add': 'レイヤーを追加',
    'menuAction.layer-add-attach-free-above': '上にフリーの付属レイヤーを追加',
    'menuAction.layer-add-attach-free-below': '下にフリーの付属レイヤーを追加',
    'menuAction.layer-add-attach-above': '上に同期の付属レイヤーを追加',
    'menuAction.layer-add-attach-below': '下に同期の付属レイヤーを追加',
    'menuAction.layer-duplicate': 'レイヤーを複製',
    'menuAction.layer-link-duplicate': 'リンクして複製',
    'menuAction.layer-unlink': 'リンクを解除',
    'menuAction.layer-group-into-folder': 'フォルダにまとめる',
    'menuAction.layer-group-attach-into-folder': '付属フォルダを作成',
    'menuAction.layer-rename': 'レイヤー名を変更…',
    'menuAction.layer-rasterize': 'ラスタライズ',
    'menuAction.layer-se-name-tag': 'SE ネームタグ…',
    'menuAction.layer-copy': 'レイヤーをコピー',
    'menuAction.layer-paste': 'レイヤーを貼り付け',
    'menuAction.layer-delete': 'レイヤーを削除…',
    'menuAction.playback-stop': '停止',
    'menuAction.playback-play-all': '全カットを再生',
    'menuAction.window-tool-rail-right': 'ツールバーを右端に',
    'menuAction.window-region-on-top': 'タイムライン領域を上に',
    'menuAction.window-reset-layout': 'ワークスペース配置をリセット',
    'menuAction.edit-input-inspector': '入力インスペクタ',
    'menuAction.edit-frame-timing-overlay': 'フレームタイミングのオーバーレイ',
    'menuAction.edit-frame-stats': 'フレーム統計',
    'menuAction.edit-show-repaints': '再描画を表示',
    'menuAction.edit-bake-panels': '静的パネルをラスタライズ',
    'menuAction.edit-knee-at-one': '画面解像度バッファ',
    'menuAction.edit-show-unpainted-tiles': '描画されなかったタイルを表示',
    'menuAction.help-about': 'Anicel について',
    'fileOpenTitle': 'プロジェクトを開く',
    'fileSaveTitle': 'プロジェクトを保存',
    'fileStorageOffNotice':
        'ストレージへのアクセスがオフです — アプリフォルダの外にある'
        'プロジェクトには「すべてのファイル」の権限が必要です。',
    'fileOpenSettings': '設定を開く',
    'fileNameLabel': 'ファイル名',
    'fileCloudNoticeOpen':
        'クラウドサービス（Google ドライブ、Dropbox など）：同期アプリ'
        '（Autosync、FolderSync など）を使い、そのミラーフォルダをここで'
        '開いてください — クラウド上のドキュメントを直接扱うことはできません。',
    'replaceFileTitle': 'ファイルを置き換えますか？',
    'replaceFileMessageTemplate': '{name} はここに既にあります。',
    'commonReplace': '置き換え',
    'folderNoPathTitle': 'この場所にはフォルダーパスがありません',
    'folderStorageOffTitle': 'ストレージへのアクセスがオフです',
    'folderPickUnavailable': 'フォルダー選択を開けませんでした。',
    'folderPickDriveNotice':
        'Google ドライブはフォルダーを渡せません。iCloud Drive・Dropbox・'
        'この端末をお使いください。',
    'projectChooserEmpty': 'このフォルダーにAnicelプロジェクトがありません。',
    'fileNameEmpty': 'ファイル名を入力してください。',
    'recentProjectsTitle': '最近使ったプロジェクト',
    'recentReconnect': '再接続',
    'sortByName': '名前',
    'sortByModified': '更新日時',
    'sortBySize': 'サイズ',
    'sortAscending': '昇順',
    'sortDescending': '降順',
    'canvasSizeTitle': 'カンバスサイズ',
    'cameraSizeTitle': 'カメラサイズ',
    'canvasWidthLabel': '幅（px）',
    'canvasHeightLabel': '高さ（px）',
    'canvasAnchorHelpTemplate':
        '基準：既存の絵はここに固定されます。切り取られた線は保持され、'
        'カンバスを広げれば再び現れます。（{min}〜{max} px）',
    'canvasPresetDefault': '既定',
    'commonResize': 'サイズ変更',
    'menuAlphaPreview': 'アルファプレビュー',
    'inputTitle': '入力設定',
    'inputPressureHeading': '筆圧カーブ',
    'inputPressureSoftHard': '柔らかい ↔ 硬い',
    'inputPressureLinear': 'リニア',
    'inputSpeedHeading': '速度カーブ',
    'inputSpeedReference': '最高速度',
    'inputCanvasHeading': 'カンバス',
    'inputRightClick': '右クリック / ペンのサイドボタン',
    'inputWheelClick': 'ホイールクリック / ペンの上ボタン',
    'inputPenTail': 'ペンのお尻（ペンを裏返す）',
    'inputCanvasTouchHeading': 'カンバスのタッチ',
    'inputDragOneFinger': '1本指ドラッグ',
    'inputDragTwoFingers': '2本指ドラッグ',
    'inputDragThreeFingers': '3本指ドラッグ',
    'inputExtraFinger': '追加指モディファイア',
    'inputExtraFingerHelp':
        'ジェスチャーの途中で指を足すと動作が制限されます — ズーム・回転・'
        'サイズのスナップ、フレームの微送り。',
    'inputFlipHaptics': 'フリップの触覚フィードバック',
    'inputFlipHapticsHelp':
        'フリップが別の絵に着地するたびに小さく振動します。空白の上では'
        '鳴らず、振動子のない機器では何も起きません。',
    'inputTwoFingerRotation': '2本指の回転',
    'inputTwoFingerRotationHelp':
        'OFF：ナビゲートは移動とズームのみになります（回転ボタンと'
        'ショートカットは残ります）。',
    'inputRotationLock': 'モディファイアで回転をロック',
    'inputRotationLockHelp':
        'ON：追加指が角度を固定します（移動＋スナップズームのみ）。'
        'OFF（既定）：角度をスナップします。',
    'inputRotationSnap': '回転スナップ（°）',
    'inputZoomSnaps': 'ズームスナップ（%）',
    'inputBrushSizeSnaps': 'ブラシサイズのスナップ（px）',
    'inputTabletHeading': 'タブレットサービス',
    'inputTabletStandard': '標準（既定）',
    'inputTabletStandardHelp': 'OSのポインタ経路（Windows Ink）— 最新ドライバや内蔵ペンに適します。',
    'inputTabletWintab': 'Wintab',
    'inputTabletWintabHelp':
        'タブレットドライバから直接筆圧を読みます — ペンが筆圧なし、または'
        'タッチ／マウスとして届くときの逃げ道です。',
    'inputTabletAutoDemoted':
        'Standard に戻しました：Wintab 経路ではペンがウィンドウに'
        '届かなくなっていました。',
    'dragActionFlip': 'めくり（フレーム / レイヤー）',
    'dragActionScreen': '画面（移動・ズーム・回転）',
    'dragActionBrushSize': 'ブラシサイズ',
    'dragActionDraw': 'タッチで描画',
    'commonNone': 'なし',
    'mapEyedropper': 'スポイト',
    'mapEraser': '消しゴム',
    'mapPan': '手のひら',
    'mapUndo': '元に戻す',
    'mapRedo': 'やり直す',
    'holdReturnToTool': 'ツールに戻る',
    'holdKeep': '保持',
    'prefsTitle': '環境設定',
    'prefsInput': '入力',
    'prefsAutosave': '自動保存',
    'prefsAudio': 'オーディオ',
    'prefsLanguage': '言語',
    'prefsAccent': 'アクセントカラー',
    'prefsDisplay': '表示',
    'prefsSystem': 'システム',
    'prefsMemory': 'メモリ',
    'memoryProcessTotal': 'このアプリのRAM使用量',
    'memoryTracked': '内訳がわかる分',
    'memoryUntracked': 'エンジン・フォント・フレームワーク',
    'memoryAvailable': 'まだ使える分',
    'memoryPinned': '再生のため保持中',
    'memoryDeviceTotal': 'デバイスのメモリ',
    'memoryAllowance': 'アプリの割り当て',
    'memoryAllowanceAutomatic': '自動の割り当てに戻す',
    'memoryItemDrawings': '作画',
    'memoryItemSheetInk': '用紙の手書き',
    'memoryItemUndo': '取り消し履歴',
    'memoryItemPlaybackFrames': '再生フレーム',
    'memoryItemLayerImages': 'レイヤー画像',
    'memoryItemBrushTips': 'ブラシ先端',
    'memoryItemPanelRasters': 'パネルのラスター',
    'memoryItemViewerPages': 'ビューアのページ',
    'memoryItemImageCache': '画像キャッシュ',
    'memoryItemStoryboardThumbnails': '絵コンテのサムネイル',
    'memoryItemMoviePictures': '参照動画',
    'memoryItemTileImages': 'キャンバスのタイル画像',
    'memoryItemEngineBuffers': '描画エンジンのバッファ',
    'containerAreaSettings': '設定',
    'containerAreaDiagnostics': '診断ログ',
    'containerAreaSessionScratch': 'セッション作業領域',
    'containerTotal': '合計',
    'saveCelsLostTemplate':
        '保存しましたが、{count} 枚の絵を含められませんでした。それらが入っていたプロジェクトファイルが、開いている間に削除されました。',
    'saveCelsLostHeading': '該当する絵',
    'saveCelsLostGone': 'プロジェクトにもう無い絵',
    'projectFileVanished':
        'このプロジェクトのファイルが見つかりません — 削除か移動された可能性があります。ゴミ箱に残っていれば今すぐ戻してください。保存済みの絵はそのファイルの中にしかありません。',
    'uiScaleLabel': 'UIの大きさ',
    'accentTitle': 'アクセントカラー',
    'accent1Label': 'アクセント1',
    'accent1Help': '選択・再生ヘッド・オンの状態に使われます。',
    'sheetInfoTitle': 'シート情報',
    'sheetFieldTitle': 'タイトル',
    'sheetFieldEpisode': '話数',
    'sheetFieldScene': 'シーン',
    'sheetFieldCut': 'カット',
    'sheetFieldTime': 'タイム',
    'sheetFieldName': '作画者',
    'sheetFieldSheet': 'シート',
    'sheetTitleHint': '空欄ならプロジェクト名',
    'sheetArtist': '作画者',
    'sheetStaffByProcess': '工程ごとの担当',
    'sheetVisibleBoxes': '表示する枠',
    'sheetStampPick': 'ハンコを選ぶ',
    'sheetStampClear': 'ハンコを外す',
    'sheetNotation': '表記',
    'sheetExposureBar': '止めの引き伸ばし線',
    'sheetExposureBarHelp': 'N コマ以上の止めで (N+1) コマ目から線を引く',
    'sheetExposureBarN': 'N（業界標準は3）',
    'sheetSeEmptyFill': 'セリフのない区間をグレーで塗る',
    'instructionsTitle': '指示記号',
    'instructionEditTooltip': '指示記号を編集',
    'instructionDeleteTooltip': '指示記号を削除',
    'instructionAddButton': '指示記号を追加',
    'instructionDefTitle': '指示記号',
    'instructionDefNameLabel': '名前（FI、PAN など）',
    'instructionEventEditTitle': '指示の編集',
    'instructionEventAddTitle': '指示の追加',
    'instructionMarkLabel': '指示（記号）',
    'instructionNameLabel': '名前（空欄なら記号名）',
    'instructionStartLabel': '始点名（A）',
    'instructionEndLabel': '終点名（B）',
    'instructionMemoLabel': 'メモ（タイムシートのメモ欄）',
    'instructionEditSetButton': '指示記号を編集…',
    'instructionEditorIcon': 'アイコン',
    'instructionEditorColor': '色',
    'instructionEditorMark': '記号',
    'systemStatusHelp':
        '各サブシステムが今どの実装で動いているかです。フォールバック経路でもアプリは動きますが、たいていは遅くなります — 詳しく知りたいときは名前で検索できます。',
    'shortcutCategory.Navigation': 'ナビゲーション',
    'shortcutCategory.Playback': '再生',
    'shortcutCategory.Edit': '編集',
    'shortcutCategory.Tools': 'ツール',
    'shortcutCategory.Selection': '選択',
    'shortcutCategory.View': '表示',
    'shortcutCategory.Timeline': 'タイムライン',
    'shortcutCategory.File': 'ファイル',
    'shortcutAction.frame-previous': '前のフレーム',
    'shortcutAction.frame-next': '次のフレーム',
    'shortcutAction.frame-walk-left': '左へ一歩',
    'shortcutAction.frame-walk-right': '右へ一歩',
    'shortcutAction.frame-walk-up': '上へ一歩',
    'shortcutAction.frame-walk-down': '下へ一歩',
    'shortcutAction.drawing-previous': '前の作画',
    'shortcutAction.drawing-next': '次の作画',
    'shortcutAction.playback-toggle': '再生 / 一時停止',
    'shortcutAction.canvas-pan-hold': '移動（押している間）',
    'shortcutAction.voice-record-toggle': '音声収録（開始/停止）',
    'shortcutAction.edit-undo': '元に戻す',
    'shortcutAction.edit-redo': 'やり直す',
    'shortcutAction.tool-brush': 'ブラシツール',
    'shortcutAction.tool-eraser': '消しゴムツール',
    'shortcutAction.tool-eyedropper': 'スポイトツール',
    'shortcutAction.tool-fill': '塗りつぶしツール',
    'shortcutAction.tool-fill-bucket': '塗りつぶし',
    'shortcutAction.tool-guide': 'ガイドツール',
    'shortcutAction.tool-select': '選択ツール',
    'shortcutAction.tool-transform': '変形ツール',
    'shortcutAction.tool-transform-normal': '通常変形',
    'shortcutAction.tool-transform-free': '自由変形',
    'shortcutAction.tool-transform-mesh': 'メッシュワープ',
    'shortcutAction.tool-cut': '切り抜きツール',
    'shortcutAction.tool-cut-stamp': 'スタンプ',
    'shortcutAction.selection-deselect': '選択解除',
    'shortcutAction.selection-nudge-up': '選択 / レイヤーを上へ微調整',
    'shortcutAction.selection-nudge-down': '選択 / レイヤーを下へ微調整',
    'shortcutAction.selection-transform-commit': '変形を確定',
    'shortcutAction.selection-transform-cancel': '変形をキャンセル',
    'shortcutAction.onion-skin-toggle': 'オニオンスキンの切り替え',
    'shortcutAction.canvas-rotate-ccw': 'カンバス表示を左に回転',
    'shortcutAction.canvas-rotate-cw': 'カンバス表示を右に回転',
    'shortcutAction.canvas-flip-horizontal': 'カンバス表示を左右反転',
    'shortcutAction.timeline-comma-1': '1コマに設定',
    'shortcutAction.timeline-comma-2': '2コマに設定',
    'shortcutAction.timeline-comma-3': '3コマに設定',
    'shortcutAction.timeline-comma-4': '4コマに設定',
    'shortcutAction.timeline-comma-n': 'Nコマに設定…',
    'shortcutAction.frame-new-drawing': '新規作画',
    'shortcutAction.frame-blank-exposure': '中割なし / ×',
    'shortcutAction.frame-toggle-mark': 'マークを切り替え',
    'shortcutAction.timeline-push-blocks': '押し出し（コマを開ける）',
    'shortcutAction.timeline-pull-blocks': '詰め（コマを詰める）',
    'shortcutAction.edit-cut': '切り取り',
    'shortcutAction.edit-copy': 'コピー',
    'shortcutAction.edit-paste-linked': 'リンクして貼り付け',
    'shortcutAction.edit-paste-independent': '独立して貼り付け',
    'shortcutAction.edit-delete': '削除',
    'shortcutAction.edit-replace-colour': '色変換',
    'shortcutAction.edit-clear-pixels': 'ピクセル消去',
    'shortcutAction.edit-delete-colour': '色削除',
    'shortcutAction.edit-keep-colour': '色残し',
    'shortcutAction.file-save': '保存',
    'shortcutAction.file-save-as': '名前を付けて保存…',
    'shortcutAction.layer-visibility-solo': 'アクティブレイヤーをソロ',
    'shortcutAction.canvas-zoom-in': 'ズームイン',
    'shortcutAction.canvas-zoom-out': 'ズームアウト',
    'cutCommands': 'カット操作',
    'cutAddCut': 'カットを追加',
    'cutNewCut': 'カットを新規作成',
    'cutDuplicateCut': 'カットを複製',
    'cutDuplicateActive': 'アクティブなカットを複製',
    'cutRename': 'カット名を変更…',
    'cutEditNote': 'カットメモを編集…',
    'cutMoveLeft': 'カットを左へ',
    'cutMoveRight': 'カットを右へ',
    'cutDelete': 'カットを削除',
    'mediaActions': 'メディア操作',
    'mediaImportAudio': '音声を読み込み',
    'mediaRename': 'メディア名を変更',
    'mediaPlace': '配置…',
    'mediaRelink': '再リンク…',
    'mediaMissingCount': '見つからないファイル {n} 個',
    'mediaFindInFolder': 'フォルダーから探す…',
    'mediaRelinkFound': '{n} 件中 {m} 件が見つかりました。再リンクしますか？',
    'mediaRelinkScanning': 'フォルダーを読み込み中…',
    'mediaRelinkScanned': '読み込みました',
    'mediaRemove': '削除',
    'mediaRegisterInProject': 'プロジェクトファイルに取り込む',
    'mediaExportWav': 'WAVで書き出す',
    'mediaExportWavNoAudio': 'この素材には書き出せる音声がありません。',
    'mediaCarriedState': 'プロジェクト内',
    'mediaReferencedState': 'リンク',
    'projectLegacyAssetsFolder':
        'このプロジェクトの隣にまだ {name} フォルダーがあります。'
        'もう使われません — 一度保存すると中のメディアはプロジェクト'
        'ファイルに入り、そのあとフォルダーは削除できます。',
    'mediaRemoveInUse': '使用中です。削除しますか？配置したレイヤー/フレームが削除されます。',
    'mediaUsesHeading': '使用箇所',
    'mediaOpenInViewer': 'ビューアで開く',
    'mediaOpenInSubViewer': 'サブビューアで開く',
    'mediaViewerEmpty':
        '表示するものがありません。\nメディアプールのファイルをダブルクリックするか、'
        '上のボタンからファイルを開いてください。',
    'mediaViewerOpenFile': 'ファイルを開く…',
    'mediaViewerLoadFailed': 'このファイルを読み込めませんでした。',
    'mediaViewerCutTooLarge': 'メモリ許容量に収まらないため、原寸で切り取れません。',
    'mediaViewerCannotDisplay': 'この種類のメディアはまだ表示できません。',
    'mediaViewerNoPdfRenderer': 'このビルドにはPDFレンダラーがありません — PDFページを表示できません。',
    'mediaViewerNoVideoDecoder': 'このビルドには動画デコーダーがありません — 動画を表示できません。',
    'mediaViewerNoAudioDecoder': 'この音声を読み込めませんでした — 波形を表示できません。',
    'mediaViewerSwap': 'もう一方のビューアと入れ替え',
    'unsupportedFileTitle': 'サポートされていないファイル',
    'unsupportedFileMessageTemplate': '「{name}」はここでは開けません。使用できる形式: {kinds}。',
    'mediaViewerRegisterAsset': 'メディアに登録',
    'panelMediaViewer': 'ビューア',
    'panelMediaViewerSub': 'サブビューア',
    'panelCanvas': 'カンバス',
    'panelColorWheel': 'カラーホイール',
    'transportIn': 'イン',
    'transportOut': 'アウト',
    'transportLoop': 'ループ',
    'transportPrevFrame': '前のフレーム',
    'transportNextFrame': '次のフレーム',
    'colorRecent': '最近',
    'colorBackgroundSwap': '背景色（タップで入れ替え）',
    'penPressureTitle': '筆圧',
    'penPressureAxis': '筆圧 →',
    'brushDynamicsTitle': '入り抜き',
    'curveSourcePressure': '筆圧',
    'curveSourceTilt': '傾き',
    'curveSourceSpeed': '速度',
    'onionCurrentDrawing': '現在の絵',
    'audioLevelMeter': '音声レベルメーター',
    'panelColorRgb': 'RGB',
    'panelColorPalette': 'パレット',
    'panelMedia': 'メディア',
    'panelOnionSkin': 'オニオンスキン',
    'panelToolSize': 'ツールサイズ',
    'panelStoryboard': '絵コンテ',
    'panelTimeline': 'タイムライン',
    'panelTimesheet': 'タイムシート',
    'panelConte': 'コンテ',
    'panelEnvelope': 'エンベロープ',
    'commonRegister': '登録',
    'commonNameField': '名前',
    'tipRegisterTitle': '先端として登録',
    'panelToolLibrary': 'ツールライブラリ',
    'panelCollapseRegion': '折りたたむ',
    'panelNewGroup': '新しいパネルグループ',
    'panelRegionWidth': '領域の幅',
    'panelExpandRegion': '広げる',
    'panelToolSettings': 'ツール設定',
    'panelTools': 'ツール',
    'onionBefore': '前',
    'onionAfter': '後',
    'onionBeforeTint': '前の色',
    'onionAfterTint': '後の色',
    'onionGhostColorHelp': 'ゴーストの色付け方',
    'onionPegCountHelp': '1段が数えるもの',
    'shortcutTitle': 'キーボードショートカット',
    'shortcutResetAll': 'すべてリセット',
    'shortcutResetToDefault': '既定に戻す',
    'shortcutRecordNew': '新しいショートカットを記録',
    'shortcutTouch': 'タッチショートカット',
    'shortcutSearch': 'アクションを検索',
    'shortcutConflictBanner':
        '同じキーを共有しているアクションがあります — 強調された割り当てが'
        '衝突しています。',
    'shortcutRecordingHint': 'キーを押してください…（Escで中止）',
    'playbackQuality': '再生品質',
    'playbackStop': '停止',
    'playbackToStart': '先頭へ',
    'sheetPreviousPage': '前のページ',
    'sheetNextPage': '次のページ',
    'sheetPageDrag': 'ページ（ドラッグ / ダブルタップ）',
    'autosaveTitle': '自動保存',
    'autosaveEvery': '間隔',
    'autosaveSectionHelp':
        '一定間隔でプロジェクトを保存するので、クラッシュや電池切れで失う作業は最大でもその間隔ぶんです。',
    'autosaveSwitchHelp': 'オフにすると、プロジェクトは保存したときだけ変わり、クラッシュすればそれ以降の作業はすべて失われます。',
    'appContainerTitle': 'アプリコンテナ',
    'appContainerHelp':
        'プロジェクトファイルの外にアプリが持つもの — 設定とブラシ先端、読み込みが取り込んだまままだどの保存にも吸収されていないメディアと音声、そして診断ログです。',
    'containerEmpty': '空',
    'commonMinutesShort': ' 分',
    'exExport': '書き出し',
    'exAddToQueue': 'キューに追加',
    'exImage': '画像',
    'exVideo': '動画',
    'exCels': 'セル',
    'exSheetPng': 'シートPNG',
    'exFormat': '形式',
    'exOptions': 'オプション',
    'exNaming': '命名',
    'exScope': '範囲',
    'exQuality': '画質',
    'exCodec': 'コーデック',
    'exBitrate': 'ビットレート',
    'exChannels': 'チャンネル',
    'exAudio': '音声',
    'exBrowse': '参照…',
    'exSavePreset': 'プリセットを保存',
    'exPresetNameEmpty': 'プリセット名を空にはできません。',
    'exBaseName': 'ベース名',
    'exSuffix': '接尾辞',
    'exDigits': '桁数',
    'exApplyLayerFx': 'レイヤーFXを適用',
    'exApplyLayerFxHelp': 'レイヤーFXを適用（変形とアニメーション不透明度）',
    'exMuxSeMix': 'SEミックスを動画に多重化',
    'exLabel': 'ラベル',
    'exApply': '適用',
    'exAdd': '追加',
    'exSelect': '選択',
    'exSelBase': '基準',
    'exSelAttach': '付属',
    'exSelSheet': 'シート',
    'exSelDirection': 'ディレクション',
    'exSelCustom': 'カスタム',
    'exPaperLabel': '用紙',
    'exArtLabel': '美術',
    'exTakeLatest': '最新',
    'exFolders': 'フォルダ作成',
    'exNameParts': '名前指定',
    'exTarget': '対象',
    'exLayer': 'レイヤー',
    'exCelCount': '{n}枚',
    'exCelCountOne': '{n}枚',
    'exProject': 'プロジェクト',
    'exCut': 'カット',
    'exWhite': '白',
    'exBlack': '黒',
    'exBackground': '背景',
    'exChooseLocation': '保存先を選ぶと書き出せます。',
    'exNoCels': '（セルなし）',
    'exNoCuts': '（カットなし）',
    'exPresets': 'プリセット',
    'exQueue': 'キュー',
    'exSize': 'サイズ',
    'exForm': '書式',
    'exCutSize': 'カットサイズ',
    'exRealSheet': '実寸用紙',
    'exWidth': '幅',
    'exSheetLayers': 'レイヤー',
    'exContent': '内容',
    'exInk': '線画',
    'exFiles': 'ファイル',
    'exOneImage': '画像1枚',
    'exOnePerLayer': 'レイヤーごとに1枚',
    'imImport': 'インポート',
    'imPool': 'プール',
    'imFile': 'ファイル',
    'imFiles': 'ファイル',
    'imInto': '配置先',
    'imFit': 'フィット',
    'imRevisions': 'リビジョン',
    'imFilesButton': 'ファイル…',
    'imCutFolderButton': 'カットフォルダ…',
    'imModified': '更新日時',
    'imSize': 'サイズ',
    'imArchivedProcesses': '格納済み工程（LO/・GEN/…）',
    'imMultiCutFolders': '兼用カットのフォルダ',
    'imProcess': '工程',
    'imPicture': '画像',
    'imReference': '参考',
    'imExcluded': '除外',
    'imIgnored': '無視',
    'imMultiCutMark': '（兼用）',
    'imAndMore': ' ほか{n}件',
    'imPickToSee': 'ファイルかカットフォルダを選ぶと解釈が出ます。',
    'imPlaceLabel': '配置',
    'imPlaceTitleTemplate': '配置 — {name}',
    'imPoolOnlyTooltip': 'メディアプールは登録だけです。配置はタイムラインから行います。',
    'imAlreadyPooledTooltip': 'すでにメディアプールにあります。',
    'imModeKeep': '埋め込み',
    'imModeReference': 'リンク',
    'imBake': 'ラスタライズ',
    'imSound': '音',
    'commonOn': 'オン',
    'commonOff': 'オフ',
    'imFitContain': 'アスペクト維持',
    'imFitStretch': '引き伸ばし',
    'imIntoNewLayer': '新規レイヤー',
    'imIntoSeRow': 'SE行',
    'imIntoRowCellTemplate': '{row} · {frame}コマ目',
    'imIntoNewCut': '新規カット',
    'imPsdMerge': '統合',
    'imPsdExpand': '展開',
    'imNoSource': 'ソースが選ばれていません',
    'imFileCountTemplate': '{n}個のファイル',
    'imStatusImporting': 'インポート中…',
    'imStatusNothing': '何もインポートされませんでした。',
    'imFolderGone': 'そのフォルダーは見つかりません。',
    'imFolderUnreadableTemplate': 'フォルダーを読めませんでした: {reason}',
    'imCutFolderUnreadable': 'そのフォルダーを読めませんでした。',
    'imUnreadableTemplate': '{name}: ファイルを読めませんでした。',
    'imCorruptTemplate':
        '{name} を開けませんでした — 破損しているか、パスワードで保護されています。',
    'imPagesFailedTemplate':
        '{name}: {n}ページを描画できませんでした — そのセルは空のままです。',
    'imFramesFailedTemplate':
        '{name}: {n}フレームをデコードできませんでした — そのセルは空のままです。',
    'imNoPdfRendererTemplate': '{name}: このビルドには PDF レンダラーがありません。',
    'imCouldNotImportTemplate': '{name} をインポートできませんでした。',
    'imPsdNoLayersTemplate':
        '{name}: 展開するレイヤーがありません — 統合で読み込んでください。',
    'imRenderingPdfTemplate': 'PDF ページを描画中 {done}/{total}…',
    'imLargeCarryTemplate':
        '{total} がプロジェクトファイルに入ります — {files}{more}。埋め込むときにファイルごとに圧縮するので、プロジェクトの増加はそれより小さくなります。リンクは元のファイルをその場所に残します。',
    'imKeepExplain': 'プロジェクトファイルが圧縮して持ちます。元のファイルはそのままです。',
    'imReferenceExplain': 'ファイルはその場所に残り、プロジェクトはそれを指します。',
    'imCutFolderBakes':
        'カットフォルダーのセルは常にラスタライズされます。スキャンと動画はリンクのままです。',
    'imRevLatest': '最新',
    'imRevAll': 'すべて',
    'imRevOriginals': '元の版',
    'mpFileMissing': 'ファイルが見つかりません — リンクし直してください',
    'mpInUseOnTimeline': 'タイムラインで使用中',
    'mpNameEmpty': 'メディア名を入力してください。',
    'exCameraTemplate': 'カメラ {w}×{h}',
    'toolBrush': 'ブラシ',
    'toolEraser': '消しゴム',
    'toolEyedropper': 'スポイト',
    'toolFill': '塗りつぶし',
    'toolSelect': '選択',
    'toolTransform': '変形',
    // TVPaint's own term for this verb in Japanese studios.
    'toolShapeFill': '図形の塗り',
    'toolCutHint': 'カットはドラッグした範囲のピクセルを複製します — 元は残ります。\n持っている断片を置くにはスタンプを選びます。',
    'toolCutNothingHeld': 'まだ何も持っていません。\nまず矩形か投げ縄のタイルで断片をカットします。',
    'toolCutPasteAtOrigin': '元の位置に貼り付け',
    'toolCutFlipHorizontal': '左右反転',
    'toolCutFlipVertical': '上下反転',
    'toolCutRegisterTip': '先端として登録…',
    'toolEyedropperReference': '参照',
    'brushSettingsTitle': 'ブラシ設定',
    'toolShapeRect': '矩形',
    'toolShapeEllipse': '楕円',
    'toolShapeLasso': '投げ縄',
    'toolShapePolygon': '多角形',
    'toolShapeSelectTemplate': '{shape}選択',
    'toolShapeCutTemplate': '{shape}カット',
    'toolShapeFillTemplate': '{shape}塗り',
    'brBrushesTitle': 'ブラシ',
    'brGroupNameField': 'グループ名',
    'brCreate': '作成',
    'brRenameBrush': 'ブラシ名を変更',
    'brBrushNameField': 'ブラシ名',
    'brGroupNameEmpty': 'グループ名は空にできません。',
    'brBrushNameEmpty': 'ブラシ名は空にできません。',
    'brResetLibraryBody':
        'ライブラリ全体 — すべてのグループ、読み込んだパック、保存したブラシ — を組み込みのブラシで置き換えますか？',
    'brSize': 'サイズ',
    'brOpacity': '不透明度',
    'brFlow': '流量',
    'brMixing': '下地混色',
    'brPaintAmount': '絵の具量',
    'brPaintDensity': '絵の具濃度',
    'brColorStretch': '色延び',
    'brHardness': '硬さ',
    'stepUp': '1目盛り上げる',
    'stepDown': '1目盛り下げる',
    'brEdge': 'エッジ',
    'brEdgeNone': 'なし',
    'brSpacing': '間隔',
    'brAngle': '角度',
    'brRoundness': '真円率',
    'brScale': '拡大率',
    'brSizeJitter': 'サイズのランダム',
    'brOpacityJitter': '不透明度のランダム',
    'brAngleJitter': '角度のランダム',
    'brRoundnessJitter': '真円率のランダム',
    'brSpacingJitter': '間隔のランダム',
    'brScatter': '散布',
    'brScatterCount': '個数',
    'brScatterBothAxes': '両軸',
    'brTipRotation': '回転',
    'brRotationFixed': '固定',
    'brRotationDirection': '進行方向',
    'brBrushTip': 'ブラシ先端',
    'brTipNone': 'なし',
    'brDualTip': 'デュアル先端',
    'brTexture': '質感',
    'brTextureDensity': '濃度',
    'brTextureInvert': '濃度反転',
    'brTextureBrightness': '明るさ',
    'brTextureContrast': 'コントラスト',
    'brAddTipImage': '画像から先端を追加',
    'brRenameTip': '先端の名前を変更',
    'brDeleteTip': '先端を削除',
    'brStabilizer': '手ブレ補正',
    'tlAutoFrame': '空のセルに描いたらフレームを作る',
    'brBlend': '合成',
    'brBlendMode': 'ブラシの合成モード',
    'brDualBlend': 'デュアルの合成',
    'brEditGroup': 'グループを編集',
    'brFolderIcon': 'フォルダーのアイコン',
    'brFolderName': 'フォルダー名',
    'brFeather': 'ぼかし',
    'brTolerance': '許容値',
    'brGapClose': '隙間閉じ',
    'brGrowShrink': '拡張 / 収縮',
    'brAntiAlias': 'アンチエイリアス',
    'brAntiAliasEdge': '縁のアンチエイリアス',
    'brTransformPreserveColors': '元の色を保持',
    'brTransformPreserveColorsHint': '変形しても中間色を作りません',
    'brFillBeyondCanvas': 'カンバス外も塗る',
    'brOpenRegionsRefuse': '開いた領域は塗られません',
    'brName': '名前',
    'brDisplay': '表示',
    'brTipIcon': '先端アイコン',
    'brStrokePreview': 'ストロークのプレビュー',
    'brBrushOptions': 'ブラシオプション',
    'brGroupOptions': 'グループオプション',
    'brNewGroup': 'グループを新規作成',
    'brRenameGroup': 'グループ名を変更',
    'brDeleteGroup': 'グループを削除',
    'brRenameSelected': '選択中のブラシ名を変更',
    'brDeleteSelected': '選択中のブラシを削除',
    'brSaveAsPreset': '現在の設定をプリセットとして保存',
    'brImportBrushes': 'ブラシを読み込み（.abr、.sut、.sutg）',
    'brResetLibrary': 'ブラシライブラリをリセット',
    'brExportSelected': 'ブラシを書き出し',
    'brExportGroup': 'ブラシグループを書き出し',
    'brExportNothing': '書き出すブラシがありません。',
    'brExpand': '展開',
    'trFlipHorizontal': '左右反転',
    'trFlipVertical': '上下反転',
    'trAnchor': '基準点',
    'trAnchorOpposite': '対角',
    'trAnchorCenter': '中心',
    'trMeshColumns': '横のマス',
    'trMeshRows': '縦のマス',
    'commonReset': 'リセット',
    'commonFill': '塗りつぶし',
    'viewFitToView': '画面に合わせる',
    'viewResetView': '表示をリセット（100%）',
    'panelSettings': '設定',
    'viewRotateLeft': '表示を左に回転',
    'viewRotateRight': '表示を右に回転',
    'viewFlipHorizontal': '表示を左右反転',
    'viewFlipVertical': '表示を上下反転',
    'viewStraighten': '傾きをリセット（0°）',
    'viewZoomDrag': 'ズーム（ドラッグ / ダブルタップ）',
    'viewAngleDrag': '表示角度（ドラッグ / ダブルタップ）',
    'viewDragDoubleTap': 'ドラッグ / ダブルタップ',
    'viewCanvasColor': 'カンバスの色',
    'viewPasteboardColor': 'ペーストボードの色',
    'viewBackdropColor': '背景の色',
    'colorUseCurrent': '現在の色を適用',
    'colorNone': 'なし',
    'tlSections': 'セクション',
    'tlAllDisplayedLayers': '表示中の全レイヤー',
    'tlShowAll': 'すべて表示',
    'tlHideAll': 'すべて隠す',
    'tlSoloKind': '種類をソロ',
    'tlSoloColor': '色をソロ',
    'tlSoloFillReferences': '塗り参照をソロ',
    'tlSoloFxOnRows': 'FXオンの行をソロ',
    'tlSoloSheetOnRows': 'シートオンの行をソロ',
    'tlApplyAllFx': 'FXをすべて適用',
    'tlBypassAllFx': 'FXをすべてバイパス',
    'tlAllOnTimesheet': 'すべてシートに載せる',
    'tlAllOffTimesheet': 'すべてシートから外す',
    'tlClearAllMarks': 'マークをすべて消去',
    'tlClearAllFillRefs': '塗り参照をすべて解除',
    'tlColVisibility': '表示列',
    'tlColLayerKind': 'レイヤー種類列',
    'tlColOnionSkin': 'オニオンスキン列',
    'tlColOpacity': '不透明度列',
    'tlColBlendMode': '合成モード列',
    'tlColFx': 'FX列',
    'tlColMark': 'マーク列',
    'tlColFillReference': '塗り参照列',
    'tlColTimesheet': 'タイムシート列',
    'tlOpenOnionPanel': 'オニオンスキンパネルを開く',
    'tlLayerMark': 'レイヤーマーク',
    'tlLayerMarkNone': 'ラベルなし',
    'tlLayerMarkSource': '上がり',
    'tlLayerTake': 'テイク',
    'layerProcess.paper': '用紙',
    'layerProcess.conte': 'コンテ',
    'layerProcess.art': '美術',
    'layerProcess.layout': 'レイアウト',
    'layerProcess.rough-key': 'ラフ原',
    'layerProcess.key': '原画',
    'layerProcess.inbetween': '動画',
    'layerProcess.finish': '仕上げ',
    'layerProcessAbbrev.paper': '用紙',
    'layerProcessAbbrev.conte': 'コンテ',
    'layerProcessAbbrev.art': '美術',
    'layerProcessAbbrev.layout': 'LO',
    'layerProcessAbbrev.rough-key': 'ラフ原',
    'layerProcessAbbrev.key': '原画',
    'layerProcessAbbrev.inbetween': '動画',
    'layerProcessAbbrev.finish': '仕上',
    'layerRevise.direction': '演出',
    'layerRevise.animation-director': '作画監督',
    'layerRevise.chief-animation-director': '総作画監督',
    'layerRevise.director': '監督',
    'layerRevise.chief-director': '総監督',
    'layerRevise.action-animation-director': 'アクション作画監督',
    'layerRevise.inbetween-check': '動画検査',
    'layerRevise.cell-check': 'セル検査',
    'layerReviseAbbrev.direction': '演出',
    'layerReviseAbbrev.animation-director': '作監',
    'layerReviseAbbrev.chief-animation-director': '総作監',
    'layerReviseAbbrev.director': '監督',
    'layerReviseAbbrev.chief-director': '総監督',
    'layerReviseAbbrev.action-animation-director': 'アク作',
    'layerReviseAbbrev.inbetween-check': '動検',
    'layerReviseAbbrev.cell-check': 'セル検',
    'tlLayerTakeNumber': 'テイク{n}',
    'tlRepeat': 'リピート',
    'tlRepeatSelection': '選択範囲をリピート',
    'tlSeNameTemplate': 'SE名 {name}',
    'tlAddLayerHeader': 'レイヤーを追加',
    'tlNoLayers': 'レイヤーがありません',
    'tlLegendLayer': 'レイヤー',
    'tlAllDisplayedOpacity': '表示中レイヤー全体の不透明度',
    'tlLinkedLayerTooltip': 'リンクレイヤー — 絵を共有しています',
    'tlLayerReference': '参照',
    'tlReferenceSourceShort': '素材より{n}フレーム長い',
    'tlSelectedLayers': '選択したレイヤー',
    'tlAudioLane': '音声',
    'tlNameTagGroup': 'ネームタグ',
    'tlTransformGroup': 'トランスフォーム',
    'tlRunEdgeNone': 'なし',
    'tlRunEdgeHold': 'ホールド',
    'tlSelectedFrameRange': '選択中のフレーム範囲',
    'tlSelectedLaneRange': '選択中のレーン範囲',
    'tlSelectedCell': '選択中のセル',
    'tlSelectedPanelRange': '選択中のコマ範囲',
    'semLayer': 'レイヤー',
    'semSelectedLayer': '選択中のレイヤー',
    'semTrack': 'トラック',
    'semSelectedTrack': '選択中のトラック',
    'sbVideoTrack': '映像トラック',
    'noticeFillRegionOpen': '領域が閉じていないため塗りつぶせません（キャンバス外まで塗るには囲まれた領域が必要です）。',
    'noticeCameraKeysCopied': 'カメラのキーフレームを After Effects 用にコピーしました。',
    'tlSameAsSelected': '選択中と同じ種類',
    'tlKindAnimation': '動画',
    'tlKindStoryboard': '絵コンテ',
    'tlKindImage': '画像',
    'tlKindText': 'テキスト',
    'tlKindAdjustment': '調整レイヤー',
    'tlKindFolder': 'フォルダー',
    'tlKindSe': 'SE',
    'tlKindTransition': 'トランジション',
    'tlKindCamera': 'カメラ',
    'tlKindSemanticTemplate': '{kind}レイヤー',
    'textCelNewTitle': '新規テキスト',
    'textCelEditTitle': 'テキストを編集',
    'textCelTextLabel': 'テキスト',
    'textCelFontLabel': 'フォント',
    'textCelFontSystem': 'システム',
    'textCelSizeLabel': 'サイズ',
    'textCelAlignLabel': '揃え',
    'textCelAlignLeft': '左',
    'textCelAlignCenter': '中央',
    'textCelAlignRight': '右',
    'textCelColorLabel': 'インク',
    'textCelBoldLabel': '太字',
    'seNameTagShowLineLabel': 'セリフを表示',
    'seNameTagLineInkLabel': 'セリフの色',
    'seNameTagPreviewName': '名前',
    'seNameTagPreviewLine': 'セリフ',
    'textCelOutlineLabel': 'フチ（白）',
    'textCelBackgroundLabel': 'ボックス（赤）',
    'textCelPositionLabel': '位置',
    'seNameTagTitle': 'SE ネームタグ',
    'seNameTagHint':
        'この行の話者ラベルを画面のどこに出すか。文字はブロックの名前とセリフ、'
        '表示・非表示は行の目で切り替えます。',
    'seNameTagPositionLabel': '位置',
    'seNameTagBoxLabel': 'ボックス',
    'seNameTagSampleName': '名前',
    'seNameTagSampleLine': 'セリフ',
    'seNameTagReset': '既定に戻す',
    'tlKindInstruction': 'ディレクション',
    'tlNoriShiro': 'のりしろ',
    'tlAttachFreeAbove': '上にフリーの付属レイヤー',
    'tlAttachFreeBelow': '下にフリーの付属レイヤー',
    'tlAttachSyncedAbove': '上に同期の付属レイヤー',
    'tlAttachSyncedBelow': '下に同期の付属レイヤー',
    'tlLayerCommands': 'レイヤー操作',
    'tlFrameCommands': 'フレーム操作',
    'tlCut': 'カット',
    'tlLayer': 'レイヤー',
    'tlFrame': 'フレーム',
    'tlDuplicateLayer': 'レイヤーを複製',
    'tlSelectRowSpan': '行全体を選択',
    'tlLinkDuplicateLayer': 'リンクして複製',
    'tlUnlinkLayer': 'リンクを解除',
    'tlResetGroup': 'リセット（キーは残す）',
    'tlRenameLayer': 'レイヤー名を変更…',
    'tlCopyLayer': 'レイヤーをコピー',
    'tlDeleteLayer': 'レイヤーを削除',
    'tlEffects': 'エフェクト',
    'tlAddEffectTemplate': '{name}を追加',
    'tlRemoveEffectTemplate': '{name}を削除',
    'tlDropIntoFolderTemplate': '{name} の中へ',
    'tlDropOutOfFolder': 'フォルダの外へ',
    'tlDropAttachSyncedTemplate': '{name} に付属（同期）',
    'tlDropAttachFreeTemplate': '{name} に付属（フリー）',
    'tlDropDetachAttach': '付属を解除',
    'tlDetachLayer': '付属を解除',
    'tlAttachDropsFxTitle': '付属すると fx が失われます',
    'tlAttachDropsFxBody': '付属レイヤーは自分の fx を持ちません。続けると既存の fx は失われます。実行しますか？',
    'tlSharedEdit': '編集',
    'tlAdd': '追加',
    'tlPush': '押し出し（コマを開ける）',
    'tlPull': '詰め（コマを詰める）',
    'sbOneStoryboardRowPerCut': 'このカットには既に絵コンテレイヤーがあります。カットにつき1つだけです。',
    'cnActionColumn': 'アクション',
    'cnConte': '絵コンテ',
    'tlBlankX': '中割なし / ×',
    'tlMark': 'マーク ●',
    'tlSetCommasN': 'Nコマに設定',
    'tlSetCommaTemplate': '{n}コマに設定',
    'tlProjectAudioRate': 'プロジェクトの音声サンプルレート',
    'tlCustom': 'カスタム…',
    'tlShowSeRows': 'SE行を表示',
    'tlShowCameraRows': 'カメラ行を表示',
    'tlStoryboardLayer': '絵コンテレイヤー',
    'setCommasTitle': 'コマ数の設定',
    'setCommasField': '露光フレーム数',
    'projectFpsTitle': 'プロジェクトのフレームレート',
    'projectFpsField': '1秒あたりのフレーム数',
  };

  static const _koValues = <String, String>{
    'languageSettingsTitle': '언어 설정',
    'programLanguageLabel': '프로그램 언어',
    'notationLanguageLabel': '표기용 언어',
    'programLanguageHelp': '메뉴·패널·라벨의 언어.',
    'notationLanguageHelp': '타임시트 등 제출물에 인쇄되는 언어.',
    'noCutSelected': '선택된 컷 없음',
    'pageLabel': '페이지',
    'continuousLabel': '콘티너스',
    'noticeNoFrameHere': '프레임이 존재하지 않습니다',
    'noticeLayerNotDrawable': '드로잉이 허용되지 않은 레이어입니다',
    'noticeEditAttachOwner': '주인 레이어를 편집하세요',
    'commonCancel': '취소',
    'commonApply': '적용',
    'commonRefresh': '새로고침',
    'commonClose': '닫기',
    'commonAffectedFiles': '해당 파일들',
    'commonNotice': '알림',
    'tlSharedDeselect': '선택 해제',
    'tlSharedColourEdit': '색 편집',
    'exportNoCuts': '이 프로젝트에는 출력할 컷이 없습니다.',
    'audioOffsetTitle': 'A/V 오프셋',
    'audioOffsetHelp':
        '소리에 대해 그림을 언제 표시할지 미세 조정합니다. 측정 가능한 지연은 자동 보정되며, 이 설정은 그 잔차를 제거합니다 — 무선 이어폰은 150~300ms 늦으면서 아무것도 보고하지 않는 게 보통입니다. 양수면 그림이 더 늦게 표시됩니다(소리가 늦게 도착하는 경우가 일반적).',
    'audioOffsetLabel': '오프셋',
    'audioUnitFrames': '프레임',
    'audioDevicesTitle': '장치',
    'audioDevicesHelp':
        '재생에 쓸 스피커와 녹음에 쓸 마이크. 변경은 다음 재생부터 적용되며, 분리된 장치는 시스템 기본값으로 대체됩니다.',
    'audioOutputLabel': '출력',
    'audioInputLabel': '입력',
    'audioSystemDefault': '시스템 기본값',
    'audioDeviceDefaultSuffix': ' (기본)',
    'audioDeviceMissingSuffix': ' (미연결)',
    'audioSyncInspectorTitle': '싱크 인스펙터',
    'recordVoiceTooltip': '플레이헤드 위치에 보이스 녹음',
    'recordVoiceStopTooltip': '녹음 정지(테이크 배치)',
    'recordMicOpenFailed': '마이크를 열 수 없습니다 — 환경설정▸오디오와 OS 마이크 권한을 확인하세요.',
    'recordMicPermissionDenied': '마이크 권한이 허용되지 않았습니다.',
    'recordSelectSeLane': '녹음은 선택된 SE 트랙에 배치됩니다 — 먼저 SE 트랙을 선택하세요.',
    'recordTakeClipped': '테이크에 클리핑이 감지되었습니다 — 블록의 빨간 모서리가 표시입니다.',
    'recordClipMarkerTooltip': '이 테이크는 클리핑되었습니다(입력 과대)',
    'tlTransitionCrossingWarning': '컷 경계를 넘어 적용되지 않습니다',
    'audioMicGainLabel': '마이크 게인(dB)',
    'audioInputChannelLabel': '입력 채널',
    'audioInputChannelDevice': '장치 그대로',
    'audioInputChannelMonoMix': '모노 믹스',
    'audioInputChannelLeft': '왼쪽만',
    'audioInputChannelRight': '오른쪽만',
    'audioClippingNoticeLabel': '클리핑 주의 안내(토스트+블록 마커)',
    'audioDenoiseLabel': '잡음 제거(음성 전용 — 효과음 녹음 시 끄기)',
    'audioInputMeterLabel': '입력 레벨',
    'audioTestSoundLabel': '테스트 사운드',
    'audioCountInLabel': '카운트인(초)',
    'audioCueBeepsLabel': '큐 비프(ADR식 3비프)',
    'audioStreamerLabel': '스트리머(펀치인 와이프)',
    'recordNothingRecording': '녹음 중이 아닙니다.',
    'recordTakeEmpty': '테이크가 비어 있어 배치할 것이 없습니다.',
    'recordPlacementFailed': '녹음을 배치하지 못했습니다.',
    'recordDroppedFramesTemplate':
        '녹음됐지만 {count}프레임이 유실됐습니다(처리가 따라가지 못함) — 테이크를 확인하세요.',
    'layerAudioTitle': '레이어 오디오',
    'audioGainLabel': '게인',
    'audioPanLabel': '팬',
    'layerAudioPanHelp': '팬은 장치 믹서 경로에서 적용됩니다(등파워 법칙).',
    'audioMute': '음소거',
    'audioSolo': '솔로',
    'fpsAudioTitleTemplate': '{from} → {to}: 소리는 어떻게 할까요?',
    'fpsAudioBody':
        '두 레이트는 실제 속도가 0.1% 다르고, 소리는 실시간으로 존재합니다 — 프레임 정확과 시간 정확을 동시에 지킬 수 없습니다.\n\n• 오디오 타이밍 유지: 소리는 실시간을 지키고, 프레임 위치가 0.1% 어긋납니다(약 42초마다 1프레임).\n\n• 오디오 0.1% 당김: 정확한 풀다운 비율로 리샘플합니다(들리지 않는 피치 변화 — 텔레시네 표준 컨폼). 모든 소리가 프레임 범위를 유지합니다.',
    'fpsAudioKeep': '오디오 타이밍 유지',
    'fpsAudioPull': '오디오 0.1% 당김',
    'selectionMoveConfirmTitle': '이동 확정',
    'selectionMoveConfirmBody': '선택 영역 이동을 확정하시겠습니까?',
    'selectionMoveRevert': '되돌리기',
    'selectionMoveApply': '확정',
    'selectionClosePolygon': '도형 닫기',
    'commonSave': '저장',
    'commonDelete': '삭제',
    'commonRename': '이름 변경',
    'commonLink': '링크',
    'commonPreview': '미리보기',
    'renameLayerTitle': '레이어 이름 변경',
    'renameLayerField': '레이어 이름',
    'renameLayerEmpty': '레이어 이름은 비울 수 없습니다.',
    'renameCutTitle': '컷 이름 변경',
    'renameCutField': '컷 이름',
    'renameCutEmpty': '컷 이름은 비울 수 없습니다.',
    'renameFrameTitle': '프레임 이름 변경',
    'renameFrameField': '프레임 이름',
    'renameKeyTitle': '키 이름 변경',
    'renameKeyField': '키 이름',
    'renameGuideTitle': '가이드 이름 변경',
    'renameGuideField': '가이드 이름',
    'renameGuideEmpty': '가이드 이름은 비울 수 없습니다.',
    'cutNoteTitle': '컷 메모 편집',
    'cutNoteField': '컷 메모',
    'deleteLayerTitle': '레이어 삭제',
    'deleteLayerMessageTemplate': '레이어 "{name}"을(를) 삭제할까요?',
    'frameNameConflictTitle': '같은 프레임 이름이 이미 있습니다',
    'frameNameConflictBody':
        '이 이름은 이 레이어의 다른 프레임이 이미 쓰고 있습니다. 같은 이름이 '
        '같은 원화를 공유하도록 기존 프레임에 링크할까요?',
    'seInstanceNewTitle': '새 SE',
    'seInstanceEditTitle': 'SE 편집',
    'seNameLabel': '이름 (화자 — 비우면 박스 숨김)',
    'seDialogueLabel': '대사',
    'seLinkedAudioLabel': '링크된 오디오',
    'seLinkedAudioNone': '없음',
    'seUnlinkAudio': '링크 해제',
    'keyInterpolationLinear': '리니어',
    'keyInterpolationHold': '홀드',
    'convertLinkedCutTitle': '링크 컷으로 변환',
    'convertLinkedCutBodyTemplate':
        '"{cut}"(원본)을 다른 컷과 링크합니다. 이름이 같은 레이어끼리 '
        '한 장의 공유 그림이 됩니다.',
    'convertLinkedCutTargetLabel': '링크할 컷',
    'convertLinkedCutLinksTemplate': '{names}을(를) 링크합니다.',
    'convertLinkedCutReplacedTemplate':
        '"{cut}"의 같은 이름 원화 {count}장이 원본 것으로 대체됩니다'
        '(원본 승리).',
    'convertLinkedCutJoiningTemplate': '원화 {count}장이 공유 세트에 합류합니다.',
    'convertLinkedCutTargetGainsTemplate': '"{cut}"에 추가: {names}.',
    'convertLinkedCutOriginGainsTemplate': '이 컷에 추가: {names}.',
    'convertLinkedCutNothing':
        '링크할 것이 없습니다 — 이미 완전히 링크됐거나 공유할 그리기 '
        '레이어가 없습니다.',
    'convertLinkedCutUndoNote': '실행 취소하면 두 컷 모두 복원됩니다.',
    'convertLinkedCutResizeFirst':
        '두 컷의 캔버스 크기가 다릅니다. 겸용컷은 캔버스를 함께 쓰므로 '
        '이 컷이 원본 컷의 크기로 바뀝니다. 실행 취소하면 되돌아갑니다.',
    'guideKindSymmetry': '대칭',
    'guideKindPerspective': '퍼스',
    'guideAdd': '추가',
    'guideDelete': '삭제',
    'guideShow': '캔버스에 표시',
    'guideActsOn': '획에 작용 중',
    'guideActsOff': '작용 안 함',
    'guideLibraryEmpty': '이 컷에는 아직 가이드가 없습니다.',
    'guideSelectPrompt': '설정할 가이드를 고르세요.',
    'guideLineCount': '선 수',
    'guideMirrorModeOn': '사본이 좌우로 뒤집힙니다(진짜 거울).',
    'guideMirrorMode': '선대칭',
    'guideMirrorModeOff': '사본은 회전일 뿐 — 뒤집히지 않습니다.',
    'guideEyeLevelShow': '아이레벨 표시',
    'guideConstrainToEyeLevel': '소실점을 아이레벨에 고정',
    'guideConstrainToEyeLevelNote': '다음 드래그부터 적용됩니다. 이미 놓인 것은 움직이지 않습니다.',
    'guideVanishingPoint': '소실점',
    'guideVanishingPointAtInfinity': '평행(무한대)',
    'guideAddVanishingPoint': '소실점 추가',
    'guideMakeVertical': '정확히 수직으로',
    'closeProjectTitle': '프로젝트를 닫을까요?',
    'closeProjectBody': '변경 사항이 저장되지 않았습니다. 그래도 닫을까요?',
    'closeProjectVanishedBody':
        '이 프로젝트의 파일이 사라졌습니다. 지금 닫으면 그 안에만 있던 그림도 함께 '
        '사라집니다. 「다른 이름으로 저장」하면 지금 열려 있는 것을 새 파일로 '
        '옮길 수 있습니다.',
    'commonSaveAs': '다른 이름으로 저장…',
    'saveProgressRunning': '저장 중…',
    'saveProgressDone': '저장 완료',
    'savePrepareRunning': '준비 중…',
    'savePrepareDone': '준비 완료',
    'openProgressRunning': '여는 중…',
    'openProgressDone': '열기 완료',
    'openWaitingCloudTemplate': '클라우드에서 내려받는 중 · {sec}초',
    'openWaitingStalledTemplate': '{sec}초째 도착하지 않았습니다',
    'resizeProgressRunning': '크기 변경 중…',
    'resizeProgressDone': '크기 변경 완료',
    'bakeProgressRunning': '래스터라이즈 중…',
    'bakeProgressDone': '래스터라이즈 완료',
    'unsavedAutosaveTitle': '프로젝트 저장',
    'unsavedAutosaveBody':
        '이 프로젝트는 한 번도 저장된 적이 없어서 자동 저장이 쓸 곳이 '
        '없습니다. 파일을 지정하면 그때부터 자동 저장이 지켜줍니다.',
    'commonNotNow': '나중에',
    'topStripProject': '프로젝트',
    'topStripSettings': '설정',
    'menuBarFile': '파일',
    'menuBarEdit': '편집',
    'menuBarCut': '컷',
    'menuBarLayer': '레이어',
    'menuBarPlayback': '재생',
    'menuBarWindow': '창',
    'menuBarHelp': '도움말',
    'menuPlay': '재생',
    'menuPause': '일시정지',
    'menuAction.file-open': '열기…',
    'menuAction.file-import': '가져오기/배치…',
    'menuAction.file-export': '내보내기…',
    'menuAction.edit-undo': '실행 취소',
    'menuAction.edit-redo': '다시 실행',
    'menuAction.edit-copy-frame': '프레임 복사',
    'menuAction.edit-paste-linked-frame': '링크 프레임 붙여넣기',
    'menuAction.edit-new-drawing': '이 프레임에 새 원화',
    'menuAction.edit-delete-cell': '셀 삭제',
    'menuAction.edit-cut-exposure': '노출 잘라내기',
    'menuAction.edit-toggle-mark': '마크 켜기/끄기',
    'menuAction.edit-keyboard-shortcuts': '키보드 단축키…',
    'menuAction.edit-preferences': '환경설정…',
    'menuAction.cut-new': '새 컷',
    'menuAction.cut-duplicate': '컷 복제',
    'menuAction.cut-create-linked': '링크 컷 만들기',
    'menuAction.cut-convert-linked': '링크 컷으로 변환…',
    'menuAction.cut-rename': '컷 이름 변경…',
    'menuAction.cut-canvas-size': '캔버스 크기…',
    'menuAction.cut-move-left': '컷 왼쪽으로',
    'menuAction.cut-move-right': '컷 오른쪽으로',
    'menuAction.cut-copy-ae-camera': '카메라 AE 키프레임 복사',
    'menuAction.cut-delete': '컷 삭제',
    'menuAction.layer-add': '레이어 추가',
    'menuAction.layer-add-attach-free-above': '위에 프리 부속 레이어 추가',
    'menuAction.layer-add-attach-free-below': '아래에 프리 부속 레이어 추가',
    'menuAction.layer-add-attach-above': '위에 동기 부속 레이어 추가',
    'menuAction.layer-add-attach-below': '아래에 동기 부속 레이어 추가',
    'menuAction.layer-duplicate': '레이어 복제',
    'menuAction.layer-link-duplicate': '링크해서 복제',
    'menuAction.layer-unlink': '링크 해제',
    'menuAction.layer-group-into-folder': '폴더로 묶기',
    'menuAction.layer-group-attach-into-folder': '부속 폴더 만들기',
    'menuAction.layer-rename': '레이어 이름 변경…',
    'menuAction.layer-rasterize': '래스터라이즈',
    'menuAction.layer-se-name-tag': 'SE 이름표…',
    'menuAction.layer-copy': '레이어 복사',
    'menuAction.layer-paste': '레이어 붙여넣기',
    'menuAction.layer-delete': '레이어 삭제…',
    'menuAction.playback-stop': '정지',
    'menuAction.playback-play-all': '모든 컷 재생',
    'menuAction.window-tool-rail-right': '툴 바를 오른쪽에',
    'menuAction.window-region-on-top': '타임라인 영역을 위로',
    'menuAction.window-reset-layout': '작업공간 배치 초기화',
    'menuAction.edit-input-inspector': '입력 인스펙터',
    'menuAction.edit-frame-timing-overlay': '프레임 타이밍 오버레이',
    'menuAction.edit-frame-stats': '프레임 통계',
    'menuAction.edit-show-repaints': '다시 그리기 표시',
    'menuAction.edit-bake-panels': '정적 패널 굽기',
    'menuAction.edit-knee-at-one': '화면 해상도 버퍼',
    'menuAction.edit-show-unpainted-tiles': '그려지지 않은 타일 표시',
    'menuAction.help-about': 'Anicel 정보',
    'fileOpenTitle': '프로젝트 열기',
    'fileSaveTitle': '프로젝트 저장',
    'fileStorageOffNotice':
        '저장소 접근이 꺼져 있습니다 — 앱 폴더 바깥의 프로젝트에는 '
        '모든 파일 권한이 필요합니다.',
    'fileOpenSettings': '설정 열기',
    'fileNameLabel': '파일 이름',
    'fileCloudNoticeOpen':
        '클라우드 서비스(Google 드라이브, Dropbox 등): 동기화 앱'
        '(Autosync, FolderSync 등)을 쓰고 그 미러 폴더를 여기서 여세요 — '
        '클라우드 문서를 직접 다루는 건 지원하지 않습니다.',
    'replaceFileTitle': '파일을 바꿀까요?',
    'replaceFileMessageTemplate': '{name}이(가) 여기 이미 있습니다.',
    'commonReplace': '바꾸기',
    'folderNoPathTitle': '이 위치에는 폴더 경로가 없습니다',
    'folderStorageOffTitle': '저장소 접근이 꺼져 있습니다',
    'folderPickUnavailable': '폴더 선택 창을 열지 못했습니다.',
    'folderPickDriveNotice':
        '구글 드라이브는 폴더를 넘겨주지 못합니다. iCloud Drive·Dropbox·'
        '이 기기를 사용하세요.',
    'projectChooserEmpty': '이 폴더에 Anicel 프로젝트가 없습니다.',
    'fileNameEmpty': '파일 이름을 입력하세요.',
    'recentProjectsTitle': '최근 프로젝트',
    'recentReconnect': '다시 연결',
    'sortByName': '이름',
    'sortByModified': '수정일시',
    'sortBySize': '크기',
    'sortAscending': '오름차순',
    'sortDescending': '내림차순',
    'canvasSizeTitle': '캔버스 크기',
    'cameraSizeTitle': '카메라 크기',
    'canvasWidthLabel': '너비 (px)',
    'canvasHeightLabel': '높이 (px)',
    'canvasAnchorHelpTemplate':
        '기준점: 기존 그림이 여기에 고정됩니다. 잘린 획은 보존되며 캔버스를 '
        '다시 넓히면 되살아납니다. ({min}~{max} px)',
    'canvasPresetDefault': '기본',
    'commonResize': '크기 변경',
    'menuAlphaPreview': '알파 미리보기',
    'inputTitle': '입력 설정',
    'inputPressureHeading': '필압 곡선',
    'inputPressureSoftHard': '부드럽게 ↔ 단단하게',
    'inputPressureLinear': '리니어',
    'inputSpeedHeading': '속도 곡선',
    'inputSpeedReference': '최고 속도',
    'inputCanvasHeading': '캔버스',
    'inputRightClick': '우클릭 / 펜 사이드 버튼',
    'inputWheelClick': '휠 클릭 / 펜 위쪽 버튼',
    'inputPenTail': '펜 엉덩이(펜을 뒤집기)',
    'inputCanvasTouchHeading': '캔버스 터치',
    'inputDragOneFinger': '한 손가락 드래그',
    'inputDragTwoFingers': '두 손가락 드래그',
    'inputDragThreeFingers': '세 손가락 드래그',
    'inputExtraFinger': '손가락 추가 모디파이어',
    'inputExtraFingerHelp':
        '제스처 도중에 손가락을 더하면 동작이 제한됩니다 — 줌·회전·크기 '
        '스냅, 프레임 미세 이동.',
    'inputFlipHaptics': '플립 진동',
    'inputFlipHapticsHelp':
        '플립이 다른 그림에 착지할 때마다 짧게 울립니다. 빈 공간에서는 '
        '울리지 않고, 진동자가 없는 기기에서는 아무 일도 없습니다.',
    'inputTwoFingerRotation': '두 손가락 회전',
    'inputTwoFingerRotationHelp': 'OFF: 내비게이트가 이동과 줌만 합니다(회전 버튼과 단축키는 유지).',
    'inputRotationLock': '모디파이어가 회전을 잠금',
    'inputRotationLockHelp':
        'ON: 추가 손가락이 각도를 고정합니다(순수 이동 + 스냅 줌). '
        'OFF(기본): 각도를 스냅합니다.',
    'inputRotationSnap': '회전 스냅 (°)',
    'inputZoomSnaps': '줌 스냅 (%)',
    'inputBrushSizeSnaps': '브러시 크기 스냅 (px)',
    'inputTabletHeading': '태블릿 서비스',
    'inputTabletStandard': '표준 (기본)',
    'inputTabletStandardHelp': 'OS 포인터 경로(Windows Ink) — 최신 드라이버와 내장 펜에 적합합니다.',
    'inputTabletWintab': 'Wintab',
    'inputTabletWintabHelp':
        '태블릿 드라이버에서 필압을 직접 읽습니다 — 펜이 필압 없이, 또는 '
        '터치/마우스로 들어올 때의 탈출구입니다.',
    'inputTabletAutoDemoted':
        'Standard로 되돌렸습니다: Wintab 경로에서는 펜이 창에 '
        '아예 도달하지 못했습니다.',
    'dragActionFlip': '넘기기 (프레임 / 레이어)',
    'dragActionScreen': '화면 (이동·줌·회전)',
    'dragActionBrushSize': '브러시 크기',
    'dragActionDraw': '터치로 그리기',
    'commonNone': '없음',
    'mapEyedropper': '스포이트',
    'mapEraser': '지우개',
    'mapPan': '손바닥',
    'mapUndo': '실행 취소',
    'mapRedo': '다시 실행',
    'holdReturnToTool': '도구로 복귀',
    'holdKeep': '유지',
    'prefsTitle': '환경설정',
    'prefsInput': '입력',
    'prefsAutosave': '자동 저장',
    'prefsAudio': '오디오',
    'prefsLanguage': '언어',
    'prefsAccent': '강조 색상',
    'prefsDisplay': '화면',
    'prefsSystem': '시스템',
    'prefsMemory': '메모리',
    'memoryProcessTotal': '이 앱이 쓰는 RAM',
    'memoryTracked': '내역을 아는 만큼',
    'memoryUntracked': '엔진·폰트·프레임워크',
    'memoryAvailable': '아직 쓸 수 있는 양',
    'memoryPinned': '재생용으로 붙잡힘',
    'memoryDeviceTotal': '기기 메모리',
    'memoryAllowance': '앱 허용치',
    'memoryAllowanceAutomatic': '자동 허용치로 되돌리기',
    'memoryItemDrawings': '그림',
    'memoryItemSheetInk': '용지 손글씨',
    'memoryItemUndo': '실행취소 기록',
    'memoryItemPlaybackFrames': '재생 프레임',
    'memoryItemLayerImages': '레이어 이미지',
    'memoryItemBrushTips': '브러시 팁',
    'memoryItemPanelRasters': '패널 래스터',
    'memoryItemViewerPages': '뷰어 페이지',
    'memoryItemImageCache': '이미지 캐시',
    'memoryItemStoryboardThumbnails': '콘티 썸네일',
    'memoryItemMoviePictures': '참조 동영상',
    'memoryItemTileImages': '캔버스 타일 이미지',
    'memoryItemEngineBuffers': '그리기 엔진 버퍼',
    'containerAreaSettings': '설정',
    'containerAreaDiagnostics': '진단 로그',
    'containerAreaSessionScratch': '세션 작업 공간',
    'containerTotal': '합계',
    'saveCelsLostTemplate':
        '저장했지만 그림 {count}장을 담지 못했습니다. 그 그림들이 들어 있던 프로젝트 파일이 열려 있는 동안 삭제되었습니다.',
    'saveCelsLostHeading': '해당 그림들',
    'saveCelsLostGone': '프로젝트에 더는 없는 그림',
    'projectFileVanished':
        '이 프로젝트의 파일이 사라졌습니다 — 지워졌거나 옮겨졌습니다. 휴지통에 아직 있다면 지금 되살리세요. 이미 저장했던 그림들은 그 파일 안에만 있습니다.',
    'uiScaleLabel': 'UI 크기',
    'accentTitle': '강조 색상',
    'accent1Label': '강조색 1',
    'accent1Help': '선택·플레이헤드·켜진 토글에 쓰입니다.',
    'sheetInfoTitle': '시트 정보',
    'sheetFieldTitle': '제목',
    'sheetFieldEpisode': '화수',
    'sheetFieldScene': '씬',
    'sheetFieldCut': '컷',
    'sheetFieldTime': '타임',
    'sheetFieldName': '작화자',
    'sheetFieldSheet': '시트',
    'sheetTitleHint': '비우면 프로젝트 이름',
    'sheetArtist': '작화자',
    'sheetStaffByProcess': '공정별 담당자',
    'sheetVisibleBoxes': '표시할 칸',
    'sheetStampPick': '도장 고르기',
    'sheetStampClear': '도장 지우기',
    'sheetNotation': '표기',
    'sheetExposureBar': '止め 늘림 선',
    'sheetExposureBarHelp': 'N코마 이상 止め에서 (N+1)번째 코마부터 선을 긋기',
    'sheetExposureBarN': 'N (업계 표준 3)',
    'sheetSeEmptyFill': '대사 없는 구간을 회색으로 채우기',
    'instructionsTitle': '지시 기호',
    'instructionEditTooltip': '지시 기호 편집',
    'instructionDeleteTooltip': '지시 기호 삭제',
    'instructionAddButton': '지시 기호 추가',
    'instructionDefTitle': '지시 기호',
    'instructionDefNameLabel': '이름 (FI, PAN 등)',
    'instructionEventEditTitle': '지시 편집',
    'instructionEventAddTitle': '지시 추가',
    'instructionMarkLabel': '지시 (기호)',
    'instructionNameLabel': '이름 (비우면 기호 이름)',
    'instructionStartLabel': '시작 이름 (A)',
    'instructionEndLabel': '끝 이름 (B)',
    'instructionMemoLabel': '메모 (타임시트 메모 칸)',
    'instructionEditSetButton': '지시 기호 편집…',
    'instructionEditorIcon': '아이콘',
    'instructionEditorColor': '색',
    'instructionEditorMark': '기호',
    'systemStatusHelp':
        '각 서브시스템이 지금 어떤 구현으로 돌고 있는지입니다. 폴백 경로에서도 앱은 동작하지만 대개 더 느립니다 — 자세히 알고 싶으면 이름으로 검색할 수 있습니다.',
    'shortcutCategory.Navigation': '이동',
    'shortcutCategory.Playback': '재생',
    'shortcutCategory.Edit': '편집',
    'shortcutCategory.Tools': '도구',
    'shortcutCategory.Selection': '선택',
    'shortcutCategory.View': '보기',
    'shortcutCategory.Timeline': '타임라인',
    'shortcutCategory.File': '파일',
    'shortcutAction.frame-previous': '이전 프레임',
    'shortcutAction.frame-next': '다음 프레임',
    'shortcutAction.frame-walk-left': '왼쪽으로 한 걸음',
    'shortcutAction.frame-walk-right': '오른쪽으로 한 걸음',
    'shortcutAction.frame-walk-up': '위로 한 걸음',
    'shortcutAction.frame-walk-down': '아래로 한 걸음',
    'shortcutAction.drawing-previous': '이전 원화',
    'shortcutAction.drawing-next': '다음 원화',
    'shortcutAction.playback-toggle': '재생 / 일시정지',
    'shortcutAction.canvas-pan-hold': '이동(누르는 동안)',
    'shortcutAction.voice-record-toggle': '음성 녹음 (시작/정지)',
    'shortcutAction.edit-undo': '실행 취소',
    'shortcutAction.edit-redo': '다시 실행',
    'shortcutAction.tool-brush': '브러시 도구',
    'shortcutAction.tool-eraser': '지우개 도구',
    'shortcutAction.tool-eyedropper': '스포이트 도구',
    'shortcutAction.tool-fill': '채우기 도구',
    'shortcutAction.tool-fill-bucket': '채우기',
    'shortcutAction.tool-guide': '가이드 도구',
    'shortcutAction.tool-select': '선택 도구',
    'shortcutAction.tool-transform': '변형 도구',
    'shortcutAction.tool-transform-normal': '일반 변형',
    'shortcutAction.tool-transform-free': '자유 변형',
    'shortcutAction.tool-transform-mesh': '메시 워프',
    'shortcutAction.tool-cut': '잘라내기 도구',
    'shortcutAction.tool-cut-stamp': '스탬프',
    'shortcutAction.selection-deselect': '선택 해제',
    'shortcutAction.selection-nudge-up': '선택 / 레이어 위로 미세 이동',
    'shortcutAction.selection-nudge-down': '선택 / 레이어 아래로 미세 이동',
    'shortcutAction.selection-transform-commit': '변형 확정',
    'shortcutAction.selection-transform-cancel': '변형 취소',
    'shortcutAction.onion-skin-toggle': '어니언 스킨 켜기/끄기',
    'shortcutAction.canvas-rotate-ccw': '캔버스 보기 왼쪽 회전',
    'shortcutAction.canvas-rotate-cw': '캔버스 보기 오른쪽 회전',
    'shortcutAction.canvas-flip-horizontal': '캔버스 보기 좌우 반전',
    'shortcutAction.timeline-comma-1': '1코마로 설정',
    'shortcutAction.timeline-comma-2': '2코마로 설정',
    'shortcutAction.timeline-comma-3': '3코마로 설정',
    'shortcutAction.timeline-comma-4': '4코마로 설정',
    'shortcutAction.timeline-comma-n': 'N코마로 설정…',
    'shortcutAction.frame-new-drawing': '새 그림',
    'shortcutAction.frame-blank-exposure': '중간 없음 / ×',
    'shortcutAction.frame-toggle-mark': '마크 토글',
    'shortcutAction.timeline-push-blocks': '밀기(칸 열기)',
    'shortcutAction.timeline-pull-blocks': '당기기(칸 닫기)',
    'shortcutAction.edit-cut': '잘라내기',
    'shortcutAction.edit-copy': '복사',
    'shortcutAction.edit-paste-linked': '링크 붙여넣기',
    'shortcutAction.edit-paste-independent': '독립 붙여넣기',
    'shortcutAction.edit-delete': '삭제',
    'shortcutAction.edit-replace-colour': '색 변환',
    'shortcutAction.edit-clear-pixels': '픽셀 비우기',
    'shortcutAction.edit-delete-colour': '색 삭제',
    'shortcutAction.edit-keep-colour': '색 남기기',
    'shortcutAction.file-save': '저장',
    'shortcutAction.file-save-as': '다른 이름으로 저장…',
    'shortcutAction.layer-visibility-solo': '활성 레이어 솔로',
    'shortcutAction.canvas-zoom-in': '확대',
    'shortcutAction.canvas-zoom-out': '축소',
    'cutCommands': '컷 명령',
    'cutAddCut': '컷 추가',
    'cutNewCut': '새 컷',
    'cutDuplicateCut': '컷 복제',
    'cutDuplicateActive': '활성 컷 복제',
    'cutRename': '컷 이름 변경…',
    'cutEditNote': '컷 메모 편집…',
    'cutMoveLeft': '컷 왼쪽으로',
    'cutMoveRight': '컷 오른쪽으로',
    'cutDelete': '컷 삭제',
    'mediaActions': '미디어 작업',
    'mediaImportAudio': '오디오 불러오기',
    'mediaRename': '미디어 이름 변경',
    'mediaPlace': '배치…',
    'mediaRelink': '다시 연결…',
    'mediaMissingCount': '못 찾은 파일 {n}개',
    'mediaFindInFolder': '폴더에서 찾기…',
    'mediaRelinkFound': '{n}개 중 {m}개를 찾았습니다. 다시 연결할까요?',
    'mediaRelinkScanning': '폴더를 읽는 중…',
    'mediaRelinkScanned': '폴더를 읽었습니다',
    'mediaRemove': '제거',
    'mediaRegisterInProject': '프로젝트 파일에 품기',
    'mediaExportWav': 'WAV로 내보내기',
    'mediaExportWavNoAudio': '이 소재에는 내보낼 오디오가 없습니다.',
    'mediaCarriedState': '품음',
    'mediaReferencedState': '참조',
    'projectLegacyAssetsFolder':
        '이 프로젝트 옆에 아직 {name} 폴더가 있습니다. 이제 쓰지 않습니다 — '
        '한 번 저장하면 안의 미디어가 프로젝트 파일로 들어가고, 그 뒤엔 폴더를 지워도 됩니다.',
    'mediaRemoveInUse': '사용 중인데 제거하겠습니까? 배치한 레이어/프레임이 삭제됩니다.',
    'mediaUsesHeading': '쓰는 곳',
    'mediaOpenInViewer': '뷰어에서 열기',
    'mediaOpenInSubViewer': '서브 뷰어에서 열기',
    'mediaViewerEmpty':
        '표시할 것이 없습니다.\n미디어 풀의 파일을 더블클릭하거나 '
        '위 버튼으로 파일을 여세요.',
    'mediaViewerOpenFile': '파일 열기…',
    'mediaViewerLoadFailed': '이 파일을 읽지 못했습니다.',
    'mediaViewerCutTooLarge': '메모리 허용치 안에 들어가지 않아 원본 크기로 잘라낼 수 없습니다.',
    'mediaViewerCannotDisplay': '이 종류의 미디어는 아직 표시할 수 없습니다.',
    'mediaViewerNoPdfRenderer': '이 빌드에는 PDF 렌더러가 없습니다 — PDF 페이지를 표시할 수 없습니다.',
    'mediaViewerNoVideoDecoder': '이 빌드에는 비디오 디코더가 없습니다 — 동영상을 표시할 수 없습니다.',
    'mediaViewerNoAudioDecoder': '이 소리를 읽지 못했습니다 — 파형을 표시할 수 없습니다.',
    'mediaViewerSwap': '반대쪽 뷰어와 맞바꾸기',
    'unsupportedFileTitle': '지원하지 않는 파일',
    'unsupportedFileMessageTemplate':
        '「{name}」은(는) 여기서 열 수 없습니다. 사용 가능한 형식: {kinds}.',
    'mediaViewerRegisterAsset': '미디어에 등록',
    'panelMediaViewer': '뷰어',
    'panelMediaViewerSub': '서브 뷰어',
    'panelCanvas': '캔버스',
    'panelColorWheel': '컬러 휠',
    'transportIn': '인',
    'transportOut': '아웃',
    'transportLoop': '루프',
    'transportPrevFrame': '이전 프레임',
    'transportNextFrame': '다음 프레임',
    'colorRecent': '최근',
    'colorBackgroundSwap': '배경색 (눌러서 교체)',
    'penPressureTitle': '필압',
    'penPressureAxis': '필압 →',
    'brushDynamicsTitle': '반응',
    'curveSourcePressure': '필압',
    'curveSourceTilt': '기울기',
    'curveSourceSpeed': '속도',
    'onionCurrentDrawing': '현재 그림',
    'audioLevelMeter': '오디오 레벨 미터',
    'panelColorRgb': 'RGB',
    'panelColorPalette': '팔레트',
    'panelMedia': '미디어',
    'panelOnionSkin': '어니언 스킨',
    'panelToolSize': '툴 사이즈',
    'panelStoryboard': '콘티',
    'panelTimeline': '타임라인',
    'panelTimesheet': '타임시트',
    'panelConte': '콘티',
    'panelEnvelope': '엔벨로프',
    'commonRegister': '등록',
    'commonNameField': '이름',
    'tipRegisterTitle': '팁으로 등록',
    'panelToolLibrary': '도구 라이브러리',
    'panelCollapseRegion': '접기',
    'panelNewGroup': '새 패널 그룹',
    'panelRegionWidth': '영역 너비',
    'panelExpandRegion': '펼치기',
    'panelToolSettings': '도구 설정',
    'panelTools': '도구',
    'onionBefore': '이전',
    'onionAfter': '이후',
    'onionBeforeTint': '이전 색',
    'onionAfterTint': '이후 색',
    'onionGhostColorHelp': '고스트에 색을 입히는 방식',
    'onionPegCountHelp': '한 칸이 세는 단위',
    'shortcutTitle': '키보드 단축키',
    'shortcutResetAll': '모두 초기화',
    'shortcutResetToDefault': '기본값으로',
    'shortcutRecordNew': '새 단축키 기록',
    'shortcutTouch': '터치 단축키',
    'shortcutSearch': '동작 검색',
    'shortcutConflictBanner': '같은 키를 쓰는 동작이 있습니다 — 강조된 할당이 충돌합니다.',
    'shortcutRecordingHint': '키를 누르세요… (Esc로 취소)',
    'playbackQuality': '재생 품질',
    'playbackStop': '정지',
    'playbackToStart': '처음으로',
    'sheetPreviousPage': '이전 페이지',
    'sheetNextPage': '다음 페이지',
    'sheetPageDrag': '페이지 (드래그 / 더블탭)',
    'autosaveTitle': '자동 저장',
    'autosaveEvery': '주기',
    'autosaveSectionHelp':
        '일정 주기로 프로젝트를 저장합니다. 크래시나 배터리 방전으로 잃는 작업이 최대 그 주기만큼으로 줄어듭니다.',
    'autosaveSwitchHelp': '끄면 프로젝트는 저장할 때만 바뀌고, 크래시가 나면 그 이후 작업이 전부 사라집니다.',
    'appContainerTitle': '앱 컨테이너',
    'appContainerHelp':
        '프로젝트 파일 바깥에 앱이 두는 것 — 설정과 브러시 팁, 가져오기가 들여왔지만 아직 어떤 저장에도 흡수되지 않은 미디어와 오디오, 그리고 진단 로그입니다.',
    'containerEmpty': '비어 있음',
    'commonMinutesShort': '분',
    'exExport': '내보내기',
    'exAddToQueue': '큐에 추가',
    'exImage': '이미지',
    'exVideo': '동영상',
    'exCels': '셀',
    'exSheetPng': '시트 PNG',
    'exFormat': '형식',
    'exOptions': '옵션',
    'exNaming': '이름 규칙',
    'exScope': '범위',
    'exQuality': '품질',
    'exCodec': '코덱',
    'exBitrate': '비트레이트',
    'exChannels': '채널',
    'exAudio': '오디오',
    'exBrowse': '찾아보기…',
    'exSavePreset': '프리셋 저장',
    'exPresetNameEmpty': '프리셋 이름은 비울 수 없습니다.',
    'exBaseName': '기본 이름',
    'exSuffix': '접미사',
    'exDigits': '자릿수',
    'exApplyLayerFx': '레이어 FX 적용',
    'exApplyLayerFxHelp': '레이어 FX 적용 (변형과 애니메이션 불투명도)',
    'exMuxSeMix': 'SE 믹스를 영상에 먹싱',
    'exLabel': '라벨',
    'exApply': '적용',
    'exAdd': '추가',
    'exSelect': '선택',
    'exSelBase': '기준',
    'exSelAttach': '부속',
    'exSelSheet': '시트',
    'exSelDirection': '디렉션',
    'exSelCustom': '커스텀',
    'exPaperLabel': '용지',
    'exArtLabel': '미술',
    'exTakeLatest': '최신',
    'exFolders': '폴더 생성',
    'exNameParts': '이름 지정',
    'exTarget': '대상',
    'exLayer': '레이어',
    'exCelCount': '{n}장',
    'exCelCountOne': '{n}장',
    'exProject': '프로젝트',
    'exCut': '컷',
    'exWhite': '흰색',
    'exBlack': '검정',
    'exBackground': '배경',
    'exChooseLocation': '위치를 고르면 내보낼 수 있습니다.',
    'exNoCels': '(셀 없음)',
    'exNoCuts': '(컷 없음)',
    'exPresets': '프리셋',
    'exQueue': '대기열',
    'exSize': '크기',
    'exForm': '서식',
    'exCutSize': '컷 크기',
    'exRealSheet': '실측 용지',
    'exWidth': '너비',
    'exSheetLayers': '레이어',
    'exContent': '내용',
    'exInk': '선화',
    'exFiles': '파일',
    'exOneImage': '이미지 한 장',
    'exOnePerLayer': '레이어마다 한 장',
    'imImport': '임포트',
    'imPool': '풀',
    'imFile': '파일',
    'imFiles': '파일',
    'imInto': '넣을 곳',
    'imFit': '맞춤',
    'imRevisions': '리비전',
    'imFilesButton': '파일…',
    'imCutFolderButton': '컷 폴더…',
    'imModified': '수정일',
    'imSize': '크기',
    'imArchivedProcesses': '보관된 공정 (LO/, GEN/…)',
    'imMultiCutFolders': '겸용 컷 폴더',
    'imProcess': '공정',
    'imPicture': '그림',
    'imReference': '참고',
    'imExcluded': '제외',
    'imIgnored': '무시',
    'imMultiCutMark': '(겸용)',
    'imAndMore': ' 외 {n}개',
    'imPickToSee': '파일이나 컷 폴더를 고르면 해석이 나옵니다.',
    'imPlaceLabel': '배치',
    'imPlaceTitleTemplate': '배치 — {name}',
    'imPoolOnlyTooltip': '미디어 풀은 등록만 합니다. 배치는 타임라인에서 합니다.',
    'imAlreadyPooledTooltip': '이미 미디어 풀에 있습니다.',
    'imModeKeep': '품기',
    'imModeReference': '참조',
    'imBake': '굽기',
    'imSound': '소리',
    'commonOn': '켬',
    'commonOff': '끔',
    'imFitContain': '비율 유지',
    'imFitStretch': '늘이기',
    'imIntoNewLayer': '새 레이어',
    'imIntoSeRow': 'SE 행',
    'imIntoRowCellTemplate': '{row} · {frame}번 칸',
    'imIntoNewCut': '새 컷',
    'imPsdMerge': '합치기',
    'imPsdExpand': '펼치기',
    'imNoSource': '고른 소스가 없습니다',
    'imFileCountTemplate': '파일 {n}개',
    'imStatusImporting': '임포트하는 중…',
    'imStatusNothing': '임포트된 것이 없습니다.',
    'imFolderGone': '그 폴더가 없어졌습니다.',
    'imFolderUnreadableTemplate': '폴더를 읽지 못했습니다: {reason}',
    'imCutFolderUnreadable': '그 폴더를 읽지 못했습니다.',
    'imUnreadableTemplate': '{name}: 파일을 읽지 못했습니다.',
    'imCorruptTemplate': '{name}: 열 수 없습니다 — 손상됐거나 암호로 잠겨 있습니다.',
    'imPagesFailedTemplate': '{name}: {n}쪽을 그리지 못했습니다 — 그 셀은 비어 있습니다.',
    'imFramesFailedTemplate':
        '{name}: {n}프레임을 디코드하지 못했습니다 — 그 셀은 비어 있습니다.',
    'imNoPdfRendererTemplate': '{name}: 이 빌드에는 PDF 렌더러가 없습니다.',
    'imCouldNotImportTemplate': '{name}: 임포트하지 못했습니다.',
    'imPsdNoLayersTemplate': '{name}: 펼칠 레이어가 없습니다 — 합치기로 가져오세요.',
    'imRenderingPdfTemplate': 'PDF 쪽을 그리는 중 {done}/{total}…',
    'imLargeCarryTemplate':
        '{total} 가 프로젝트 파일 안에 들어갑니다 — {files}{more}. 품을 때 파일마다 압축하므로 프로젝트는 그보다 덜 커집니다. 참조는 원본을 그 자리에 둡니다.',
    'imKeepExplain': '프로젝트 파일이 압축해서 품습니다. 원본은 그대로 둡니다.',
    'imReferenceExplain': '파일은 그 자리에 두고 프로젝트가 가리킵니다.',
    'imCutFolderBakes': '컷 폴더의 셀은 항상 굽습니다. 스캔과 동영상은 참조로 남습니다.',
    'imRevLatest': '최신',
    'imRevAll': '전부',
    'imRevOriginals': '원본',
    'mpFileMissing': '파일이 없습니다 — 다시 연결하세요',
    'mpInUseOnTimeline': '타임라인에서 쓰는 중',
    'mpNameEmpty': '미디어 이름을 비울 수 없습니다.',
    'exCameraTemplate': '카메라 {w}×{h}',
    'toolBrush': '브러시',
    'toolEraser': '지우개',
    'toolEyedropper': '스포이트',
    'toolFill': '채우기',
    'toolSelect': '선택',
    'toolTransform': '변형',
    'toolShapeFill': '도형 채우기',
    'toolCutHint':
        '잘라내기는 끈 자리의 픽셀을 복사합니다 — 원본은 남습니다.\n들고 있는 조각을 놓으려면 스탬프를 고르세요.',
    'toolCutNothingHeld': '아직 든 것이 없습니다.\n먼저 사각형이나 올가미 타일로 조각을 잘라내세요.',
    'toolCutPasteAtOrigin': '원래 위치에 붙여넣기',
    'toolCutFlipHorizontal': '좌우 반전',
    'toolCutFlipVertical': '상하 반전',
    'toolCutRegisterTip': '팁으로 등록…',
    'toolEyedropperReference': '참조',
    'brushSettingsTitle': '브러시 설정',
    'toolShapeRect': '사각형',
    'toolShapeEllipse': '타원',
    'toolShapeLasso': '올가미',
    'toolShapePolygon': '다각형',
    'toolShapeSelectTemplate': '{shape} 선택',
    'toolShapeCutTemplate': '{shape} 잘라내기',
    'toolShapeFillTemplate': '{shape} 채우기',
    'brBrushesTitle': '브러시',
    'brGroupNameField': '그룹 이름',
    'brCreate': '만들기',
    'brRenameBrush': '브러시 이름 변경',
    'brBrushNameField': '브러시 이름',
    'brGroupNameEmpty': '그룹 이름은 비워 둘 수 없습니다.',
    'brBrushNameEmpty': '브러시 이름은 비워 둘 수 없습니다.',
    'brResetLibraryBody': '라이브러리 전체 — 모든 그룹, 가져온 팩, 저장한 브러시 — 를 기본 브러시로 바꿀까요?',
    'brSize': '크기',
    'brOpacity': '불투명도',
    'brFlow': '흐름',
    'brMixing': '밑바탕 혼색',
    'brPaintAmount': '물감량',
    'brPaintDensity': '물감 농도',
    'brColorStretch': '색 늘이기',
    'brHardness': '경도',
    'stepUp': '한 걸음 올리기',
    'stepDown': '한 걸음 내리기',
    'brEdge': '가장자리',
    'brEdgeNone': '없음',
    'brSpacing': '간격',
    'brAngle': '각도',
    'brRoundness': '원형률',
    'brScale': '배율',
    'brSizeJitter': '크기 랜덤',
    'brOpacityJitter': '불투명도 랜덤',
    'brAngleJitter': '각도 랜덤',
    'brRoundnessJitter': '원형률 랜덤',
    'brSpacingJitter': '간격 랜덤',
    'brScatter': '살포',
    'brScatterCount': '개수',
    'brScatterBothAxes': '양축',
    'brTipRotation': '회전',
    'brRotationFixed': '고정',
    'brRotationDirection': '진행방향',
    'brBrushTip': '브러시 끝',
    'brTipNone': '없음',
    'brDualTip': '듀얼 끝',
    'brTexture': '질감',
    'brTextureDensity': '농도',
    'brTextureInvert': '농도 반전',
    'brTextureBrightness': '밝기',
    'brTextureContrast': '대비',
    'brAddTipImage': '이미지에서 끝 추가',
    'brRenameTip': '끝 이름 변경',
    'brDeleteTip': '끝 삭제',
    'brStabilizer': '손떨림 보정',
    'tlAutoFrame': '빈 칸에 그리면 프레임 자동 생성',
    'brBlend': '합성',
    'brBlendMode': '브러시 합성 모드',
    'brDualBlend': '듀얼 합성',
    'brEditGroup': '그룹 편집',
    'brFolderIcon': '폴더 아이콘',
    'brFolderName': '폴더 이름',
    'brFeather': '페더',
    'brTolerance': '허용치',
    'brGapClose': '틈 메우기',
    'brGrowShrink': '확장 / 축소',
    'brAntiAlias': '앤티에일리어스',
    'brAntiAliasEdge': '가장자리 앤티에일리어스',
    'brTransformPreserveColors': '원본 색 보존',
    'brTransformPreserveColorsHint': '변형해도 중간색을 만들지 않습니다',
    'brFillBeyondCanvas': '캔버스 밖도 채우기',
    'brOpenRegionsRefuse': '열린 영역은 채워지지 않습니다',
    'brName': '이름',
    'brDisplay': '표시',
    'brTipIcon': '팁 아이콘',
    'brStrokePreview': '스트로크 미리보기',
    'brBrushOptions': '브러시 옵션',
    'brGroupOptions': '그룹 옵션',
    'brNewGroup': '새 그룹',
    'brRenameGroup': '그룹 이름 변경',
    'brDeleteGroup': '그룹 삭제',
    'brRenameSelected': '선택한 브러시 이름 변경',
    'brDeleteSelected': '선택한 브러시 삭제',
    'brSaveAsPreset': '현재 설정을 프리셋으로 저장',
    'brImportBrushes': '브러시 가져오기 (.abr, .sut, .sutg)',
    'brResetLibrary': '브러시 라이브러리 초기화',
    'brExportSelected': '브러시 내보내기',
    'brExportGroup': '브러시 그룹 내보내기',
    'brExportNothing': '내보낼 브러시가 없습니다.',
    'brExpand': '펼치기',
    'trFlipHorizontal': '좌우 반전',
    'trFlipVertical': '상하 반전',
    'trAnchor': '기준점',
    'trAnchorOpposite': '반대 모서리',
    'trAnchorCenter': '중심',
    'trMeshColumns': '가로 칸',
    'trMeshRows': '세로 칸',
    'commonReset': '초기화',
    'commonFill': '채우기',
    'viewFitToView': '화면에 맞추기',
    'viewResetView': '보기 초기화 (100%)',
    'panelSettings': '설정',
    'viewRotateLeft': '보기 왼쪽 회전',
    'viewRotateRight': '보기 오른쪽 회전',
    'viewFlipHorizontal': '보기 좌우 반전',
    'viewFlipVertical': '보기 상하 반전',
    'viewStraighten': '기울기 초기화 (0°)',
    'viewZoomDrag': '줌 (드래그 / 더블탭)',
    'viewAngleDrag': '보기 각도 (드래그 / 더블탭)',
    'viewDragDoubleTap': '드래그 / 더블탭',
    'viewCanvasColor': '캔버스 색',
    'viewPasteboardColor': '페이스트보드 색',
    'viewBackdropColor': '배경 색',
    'colorUseCurrent': '현재 색 반영',
    'colorNone': '없음',
    'tlSections': '섹션',
    'tlAllDisplayedLayers': '표시 중인 모든 레이어',
    'tlShowAll': '모두 표시',
    'tlHideAll': '모두 숨기기',
    'tlSoloKind': '종류 솔로',
    'tlSoloColor': '색 솔로',
    'tlSoloFillReferences': '채색 참조 솔로',
    'tlSoloFxOnRows': 'FX 켜진 행 솔로',
    'tlSoloSheetOnRows': '시트 켜진 행 솔로',
    'tlApplyAllFx': 'FX 모두 적용',
    'tlBypassAllFx': 'FX 모두 우회',
    'tlAllOnTimesheet': '모두 시트에 올리기',
    'tlAllOffTimesheet': '모두 시트에서 내리기',
    'tlClearAllMarks': '마크 모두 지우기',
    'tlClearAllFillRefs': '채색 참조 모두 해제',
    'tlColVisibility': '표시 열',
    'tlColLayerKind': '레이어 종류 열',
    'tlColOnionSkin': '어니언 스킨 열',
    'tlColOpacity': '불투명도 열',
    'tlColBlendMode': '블렌드 모드 열',
    'tlColFx': 'FX 열',
    'tlColMark': '마크 열',
    'tlColFillReference': '채색 참조 열',
    'tlColTimesheet': '타임시트 열',
    'tlOpenOnionPanel': '어니언 스킨 패널 열기',
    'tlLayerMark': '레이어 마크',
    'tlLayerMarkNone': '라벨 없음',
    'tlLayerMarkSource': '소재',
    'tlLayerTake': '테이크',
    'layerProcess.paper': '용지',
    'layerProcess.conte': '콘티',
    'layerProcess.art': '미술',
    'layerProcess.layout': '레이아웃',
    'layerProcess.rough-key': '러프원화',
    'layerProcess.key': '원화',
    'layerProcess.inbetween': '동화',
    'layerProcess.finish': '시아게',
    'layerProcessAbbrev.paper': '용지',
    'layerProcessAbbrev.conte': '콘티',
    'layerProcessAbbrev.art': '미술',
    'layerProcessAbbrev.layout': 'LO',
    'layerProcessAbbrev.rough-key': '러프원',
    'layerProcessAbbrev.key': '원화',
    'layerProcessAbbrev.inbetween': '동화',
    'layerProcessAbbrev.finish': '시아게',
    'layerRevise.direction': '연출',
    'layerRevise.animation-director': '작화감독',
    'layerRevise.chief-animation-director': '총작화감독',
    'layerRevise.director': '감독',
    'layerRevise.chief-director': '총감독',
    'layerRevise.action-animation-director': '액션작화감독',
    'layerRevise.inbetween-check': '동화검사',
    'layerRevise.cell-check': '셀검사',
    'layerReviseAbbrev.direction': '연출',
    'layerReviseAbbrev.animation-director': '작감',
    'layerReviseAbbrev.chief-animation-director': '총작감',
    'layerReviseAbbrev.director': '감독',
    'layerReviseAbbrev.chief-director': '총감독',
    'layerReviseAbbrev.action-animation-director': '액션',
    'layerReviseAbbrev.inbetween-check': '동검',
    'layerReviseAbbrev.cell-check': '셀검',
    'tlLayerTakeNumber': '테이크 {n}',
    'tlRepeat': '반복',
    'tlRepeatSelection': '선택 영역 반복',
    'tlSeNameTemplate': 'SE 이름 {name}',
    'tlAddLayerHeader': '레이어 추가',
    'tlNoLayers': '레이어 없음',
    'tlLegendLayer': '레이어',
    'tlAllDisplayedOpacity': '표시 중인 레이어 전체 불투명도',
    'tlLinkedLayerTooltip': '링크 레이어 — 그림을 공유합니다',
    'tlLayerReference': '참조',
    'tlReferenceSourceShort': '원본보다 {n}프레임 깁니다',
    'tlSelectedLayers': '선택한 레이어',
    'tlAudioLane': '오디오',
    'tlNameTagGroup': '네임태그',
    'tlTransformGroup': '트랜스폼',
    'tlRunEdgeNone': '없음',
    'tlRunEdgeHold': '홀드',
    'tlSelectedFrameRange': '선택된 프레임 범위',
    'tlSelectedLaneRange': '선택된 레인 범위',
    'tlSelectedCell': '선택된 칸',
    'tlSelectedPanelRange': '선택된 컷 범위',
    'semLayer': '레이어',
    'semSelectedLayer': '선택된 레이어',
    'semTrack': '트랙',
    'semSelectedTrack': '선택된 트랙',
    'sbVideoTrack': '영상 트랙',
    'noticeFillRegionOpen':
        '영역이 닫혀 있지 않아 채우지 못했습니다 (캔버스 밖까지 채우려면 둘러싸인 영역이 필요합니다).',
    'noticeCameraKeysCopied': '카메라 키프레임을 After Effects 용으로 복사했습니다.',
    'tlSameAsSelected': '선택한 것과 같은 종류',
    'tlKindAnimation': '동화',
    'tlKindStoryboard': '콘티',
    'tlKindImage': '이미지',
    'tlKindText': '텍스트',
    'tlKindAdjustment': '조정 레이어',
    'tlKindFolder': '폴더',
    'tlKindSe': 'SE',
    'tlKindTransition': '트랜지션',
    'tlKindCamera': '카메라',
    'tlKindSemanticTemplate': '{kind} 레이어',
    'textCelNewTitle': '새 텍스트',
    'textCelEditTitle': '텍스트 편집',
    'textCelTextLabel': '텍스트',
    'textCelFontLabel': '폰트',
    'textCelFontSystem': '시스템',
    'textCelSizeLabel': '크기',
    'textCelAlignLabel': '정렬',
    'textCelAlignLeft': '왼쪽',
    'textCelAlignCenter': '가운데',
    'textCelAlignRight': '오른쪽',
    'textCelColorLabel': '잉크',
    'textCelBoldLabel': '굵게',
    'seNameTagShowLineLabel': '대사 표시',
    'seNameTagLineInkLabel': '대사 잉크',
    'seNameTagPreviewName': '이름',
    'seNameTagPreviewLine': '대사',
    'textCelOutlineLabel': '외곽선(흰색)',
    'textCelBackgroundLabel': '박스(빨강)',
    'textCelPositionLabel': '위치',
    'seNameTagTitle': 'SE 이름표',
    'seNameTagHint':
        '이 행의 화자 이름표가 화면 어디에 놓일지. 글자는 블록의 이름과 대사이고, '
        '표시 여부는 행의 눈으로 켜고 끕니다.',
    'seNameTagPositionLabel': '위치',
    'seNameTagBoxLabel': '박스',
    'seNameTagSampleName': '이름',
    'seNameTagSampleLine': '대사',
    'seNameTagReset': '기본값으로',
    'tlKindInstruction': '디렉션',
    'tlNoriShiro': '여백',
    'tlAttachFreeAbove': '위에 프리 부속 레이어',
    'tlAttachFreeBelow': '아래에 프리 부속 레이어',
    'tlAttachSyncedAbove': '위에 동기 부속 레이어',
    'tlAttachSyncedBelow': '아래에 동기 부속 레이어',
    'tlLayerCommands': '레이어 명령',
    'tlFrameCommands': '프레임 명령',
    'tlCut': '컷',
    'tlLayer': '레이어',
    'tlFrame': '프레임',
    'tlDuplicateLayer': '레이어 복제',
    'tlSelectRowSpan': '행 전체 선택',
    'tlLinkDuplicateLayer': '링크해서 복제',
    'tlUnlinkLayer': '링크 해제',
    'tlResetGroup': '리셋 (키는 유지)',
    'tlRenameLayer': '레이어 이름 변경…',
    'tlCopyLayer': '레이어 복사',
    'tlDeleteLayer': '레이어 삭제',
    'tlEffects': '이펙트',
    'tlAddEffectTemplate': '{name} 추가',
    'tlRemoveEffectTemplate': '{name} 제거',
    'tlDropIntoFolderTemplate': '{name} 안으로',
    'tlDropOutOfFolder': '폴더 밖으로',
    'tlDropAttachSyncedTemplate': '{name}에 장착 (동기)',
    'tlDropAttachFreeTemplate': '{name}에 장착 (프리)',
    'tlDropDetachAttach': '어태치 해제',
    'tlDetachLayer': '어태치 해제',
    'tlAttachDropsFxTitle': '어태치하면 fx 가 사라집니다',
    'tlAttachDropsFxBody':
        '어태치된 레이어는 자기 fx 를 갖지 않습니다. 계속하면 기존 fx 가 사라집니다. 실행하겠습니까?',
    'tlSharedEdit': '편집',
    'tlAdd': '추가',
    'tlPush': '밀기(칸 열기)',
    'tlPull': '당기기(칸 닫기)',
    'sbOneStoryboardRowPerCut': '이 컷에는 이미 스토리보드 레이어가 있습니다. 컷당 하나만 가능합니다.',
    'cnActionColumn': '액션',
    'cnConte': '콘티',
    'tlBlankX': '중간 없음 / ×',
    'tlMark': '마크 ●',
    'tlSetCommasN': 'N코마로 설정',
    'tlSetCommaTemplate': '{n}코마로 설정',
    'tlProjectAudioRate': '프로젝트 오디오 샘플레이트',
    'tlCustom': '사용자 지정…',
    'tlShowSeRows': 'SE 행 표시',
    'tlShowCameraRows': '카메라 행 표시',
    'tlStoryboardLayer': '콘티 레이어',
    'setCommasTitle': '코마 수 설정',
    'setCommasField': '노출 프레임 수',
    'projectFpsTitle': '프로젝트 프레임레이트',
    'projectFpsField': '초당 프레임 수',
  };

  static const _frValues = <String, String>{
    'languageSettingsTitle': 'Paramètres de langue',
    'programLanguageLabel': 'Langue du programme',
    'notationLanguageLabel': 'Langue de notation',
    'programLanguageHelp': 'Menus, panneaux et libellés.',
    'notationLanguageHelp': 'Ce qui s\'imprime sur la feuille d\'exposition.',
    'noCutSelected': 'Aucun plan sélectionné',
    'pageLabel': 'Page',
    'continuousLabel': 'Continu',
    'noticeNoFrameHere': 'Aucune image ici',
    'noticeLayerNotDrawable': 'Ce calque n\'accepte pas le dessin',
    'noticeEditAttachOwner': 'Modifiez le calque parent',
    'commonCancel': 'Annuler',
    'commonApply': 'Appliquer',
    'commonRefresh': 'Actualiser',
    'commonClose': 'Fermer',
    'commonAffectedFiles': 'Fichiers concernés',
    'commonNotice': 'Avis',
    'tlSharedDeselect': 'Désélectionner',
    'tlSharedColourEdit': 'Édition couleur',
    'exportNoCuts': 'Ce projet ne contient aucun plan à exporter.',
    'audioOffsetTitle': 'Décalage A/V',
    'audioOffsetHelp':
        'Ajuste finement le moment où l\'image s\'affiche par rapport au son. La part mesurable du retard est corrigée automatiquement ; ce réglage retire le reste — les écouteurs sans fil ont souvent 150 à 300 ms de retard sans rien signaler. Une valeur positive affiche l\'image PLUS TARD (le son en retard est le cas courant).',
    'audioOffsetLabel': 'Décalage',
    'audioUnitFrames': 'images',
    'audioDevicesTitle': 'Périphériques',
    'audioDevicesHelp':
        'Le haut-parleur utilisé en lecture et le micro utilisé en enregistrement. Les changements s\'appliquent à la prochaine lecture ; un périphérique débranché retombe sur le choix système.',
    'audioOutputLabel': 'Sortie',
    'audioInputLabel': 'Entrée',
    'audioSystemDefault': 'Défaut système',
    'audioDeviceDefaultSuffix': ' (défaut)',
    'audioDeviceMissingSuffix': ' (absent)',
    'audioSyncInspectorTitle': 'Inspecteur de synchro',
    'recordVoiceTooltip': 'Enregistrer la voix à la tête de lecture',
    'recordVoiceStopTooltip': 'Arrêter l\'enregistrement (place la prise)',
    'recordMicOpenFailed':
        'Impossible d\'ouvrir le micro — vérifiez Préférences ▸ Audio et l\'autorisation micro du système.',
    'recordMicPermissionDenied': 'L\'autorisation micro a été refusée.',
    'recordSelectSeLane':
        'L\'enregistrement se place sur la piste SE sélectionnée — sélectionnez-en une d\'abord.',
    'recordTakeClipped': 'La prise a saturé — le coin rouge marque le bloc.',
    'recordClipMarkerTooltip': 'Prise saturée (niveau trop fort)',
    'tlTransitionCrossingWarning': 'Dépasse la limite du plan — non appliqué',
    'audioMicGainLabel': 'Gain micro (dB)',
    'audioInputChannelLabel': 'Canaux d\'entrée',
    'audioInputChannelDevice': 'Tel quel',
    'audioInputChannelMonoMix': 'Mixage mono',
    'audioInputChannelLeft': 'Gauche seul',
    'audioInputChannelRight': 'Droit seul',
    'audioClippingNoticeLabel': 'Alertes de saturation (toast + marqueur)',
    'audioDenoiseLabel':
        'Réduction de bruit (voix — désactiver pour le bruitage)',
    'audioInputMeterLabel': 'Niveau d\'entrée',
    'audioTestSoundLabel': 'Son de test',
    'audioCountInLabel': 'Décompte (secondes)',
    'audioCueBeepsLabel': 'Bips de repère (3 bips ADR)',
    'audioStreamerLabel': 'Streamer (balayage punch-in)',
    'recordNothingRecording': 'Aucun enregistrement en cours.',
    'recordTakeEmpty': 'La prise était vide — rien à placer.',
    'recordPlacementFailed': 'La prise n\'a pas pu être placée.',
    'recordDroppedFramesTemplate':
        'Enregistré, mais {count} trames ont été perdues (la machine n\'a pas suivi) — vérifiez la prise.',
    'layerAudioTitle': 'Audio du calque',
    'audioGainLabel': 'Gain',
    'audioPanLabel': 'Panoramique',
    'layerAudioPanHelp':
        'Le panoramique s\'applique sur la voie du mixeur natif (loi à puissance constante).',
    'audioMute': 'Muet',
    'audioSolo': 'Solo',
    'fpsAudioTitleTemplate': '{from} → {to} : que faire du son ?',
    'fpsAudioBody':
        'Ces deux cadences diffèrent de 0,1 % en vitesse réelle, et le son existe en secondes réelles — il ne peut pas rester à la fois exact à l\'image et exact au temps.\n\n• Garder le timing audio : les sons gardent leurs secondes réelles ; leurs positions d\'image dérivent de 0,1 % (environ une image toutes les 42 secondes).\n\n• Tirer l\'audio de 0,1 % : les sons sont rééchantillonnés au rapport de pulldown exact (variation de hauteur inaudible — la conformation télécinéma standard) et chaque son garde sa plage d\'images exacte.',
    'fpsAudioKeep': 'Garder le timing audio',
    'fpsAudioPull': 'Tirer l\'audio de 0,1 %',
    'selectionMoveConfirmTitle': 'Valider le déplacement',
    'selectionMoveConfirmBody': 'Valider le déplacement de la sélection ?',
    'selectionMoveRevert': 'Rétablir',
    'selectionMoveApply': 'Valider',
    'selectionClosePolygon': 'Fermer la forme',
    'commonSave': 'Enregistrer',
    'commonDelete': 'Supprimer',
    'commonRename': 'Renommer',
    'commonLink': 'Lier',
    'commonPreview': 'Aperçu',
    'renameLayerTitle': 'Renommer le calque',
    'renameLayerField': 'Nom du calque',
    'renameLayerEmpty': 'Le nom du calque ne peut pas être vide.',
    'renameCutTitle': 'Renommer le plan',
    'renameCutField': 'Nom du plan',
    'renameCutEmpty': 'Le nom du plan ne peut pas être vide.',
    'renameFrameTitle': "Renommer l'image",
    'renameFrameField': "Nom de l'image",
    'renameKeyTitle': 'Renommer la clé',
    'renameKeyField': 'Nom de la clé',
    'renameGuideTitle': 'Renommer le repère',
    'renameGuideField': 'Nom du repère',
    'renameGuideEmpty': 'Le nom du repère ne peut pas être vide.',
    'cutNoteTitle': 'Modifier la note du plan',
    'cutNoteField': 'Note du plan',
    'deleteLayerTitle': 'Supprimer le calque',
    'deleteLayerMessageTemplate': 'Supprimer le calque « {name} » ?',
    'frameNameConflictTitle': "Ce nom d'image existe déjà",
    'frameNameConflictBody':
        'Ce nom est déjà utilisé par une autre image de ce calque. Lier à '
        "l'image existante pour que le même nom partage le même dessin ?",
    'seInstanceNewTitle': 'Nouveau SE',
    'seInstanceEditTitle': 'Modifier le SE',
    'seNameLabel': 'Nom (locuteur — vide masque le cadre)',
    'seDialogueLabel': 'Dialogue',
    'seLinkedAudioLabel': 'Audio lié',
    'seLinkedAudioNone': 'Aucun',
    'seUnlinkAudio': 'Dissocier',
    'keyInterpolationLinear': 'Linéaire',
    'keyInterpolationHold': 'Maintien',
    'convertLinkedCutTitle': 'Convertir en plan lié',
    'convertLinkedCutBodyTemplate':
        'Lier « {cut} » (origine) à un autre plan. Les calques de MÊME NOM '
        'deviennent un seul dessin partagé.',
    'convertLinkedCutTargetLabel': 'Lier au plan',
    'convertLinkedCutLinksTemplate': 'Lie {names}.',
    'convertLinkedCutReplacedTemplate':
        '{count} dessin(s) de même nom dans « {cut} » seront remplacés par '
        "ceux de l'origine (원본 승리).",
    'convertLinkedCutJoiningTemplate':
        "{count} dessin(s) rejoignent l'ensemble partagé.",
    'convertLinkedCutTargetGainsTemplate': '« {cut} » gagne : {names}.',
    'convertLinkedCutOriginGainsTemplate': 'Ce plan gagne : {names}.',
    'convertLinkedCutNothing':
        'Rien à lier — les plans sont déjà entièrement liés ou ne partagent '
        'aucun calque de dessin.',
    'convertLinkedCutUndoNote': 'Annuler restaure les deux plans.',
    'convertLinkedCutResizeFirst':
        'Ces plans ont des tailles de canevas différentes. Les plans liés '
        'partagent une seule image, donc la taille du plan d\'origine '
        'l\'emporte — il est conseillé d\'harmoniser les tailles d\'abord.',
    'guideKindSymmetry': 'Symétrie',
    'guideKindPerspective': 'Perspective',
    'guideAdd': 'Ajouter',
    'guideDelete': 'Supprimer',
    'guideShow': 'Afficher sur le canevas',
    'guideActsOn': 'Agit sur les traits',
    'guideActsOff': 'N\'agit pas',
    'guideLibraryEmpty': 'Aucun repère dans ce plan.',
    'guideSelectPrompt': 'Choisissez un repère pour régler ses options.',
    'guideLineCount': 'Copies',
    'guideMirrorMode': 'Symétrie axiale',
    'guideMirrorModeOn': 'Les copies sont inversées (un vrai miroir).',
    'guideMirrorModeOff':
        'Les copies sont des rotations — rien n\'est inversé.',
    'guideEyeLevelShow': 'Afficher la ligne d\'horizon',
    'guideConstrainToEyeLevel': 'Garder les points de fuite sur l\'horizon',
    'guideConstrainToEyeLevelNote':
        'S\'applique au prochain déplacement ; ne bouge pas l\'existant.',
    'guideVanishingPoint': 'Point de fuite',
    'guideVanishingPointAtInfinity': 'Parallèle (à l\'infini)',
    'guideAddVanishingPoint': 'Ajouter un point de fuite',
    'guideMakeVertical': 'Rendre exactement vertical',
    'closeProjectTitle': 'Fermer le projet ?',
    'closeProjectBody':
        'Vos modifications ne sont pas enregistrées. Fermer quand même ?',
    'closeProjectVanishedBody':
        'Le fichier de ce projet a disparu. Fermer maintenant emporte les '
        "dessins qui n'existent que dedans. « Enregistrer sous » écrit dans "
        'un nouveau fichier ce qui est encore ouvert.',
    'commonSaveAs': 'Enregistrer sous…',
    'saveProgressRunning': 'Enregistrement…',
    'saveProgressDone': 'Enregistré',
    'savePrepareRunning': 'Préparation…',
    'savePrepareDone': 'Prêt',
    'resizeProgressRunning': 'Redimensionnement…',
    'resizeProgressDone': 'Redimensionné',
    'bakeProgressRunning': 'Pixellisation…',
    'bakeProgressDone': 'Pixellisé',
    'unsavedAutosaveTitle': 'Enregistrez votre projet',
    'unsavedAutosaveBody':
        "Ce projet n'a jamais été enregistré : la sauvegarde automatique "
        "n'a nulle part où écrire. Choisissez un fichier et elle le "
        'protégera ensuite.',
    'commonNotNow': 'Plus tard',
    'topStripProject': 'Projet',
    'topStripSettings': 'Paramètres',
    'menuBarFile': 'Fichier',
    'menuBarEdit': 'Édition',
    'menuBarCut': 'Plan',
    'menuBarLayer': 'Calque',
    'menuBarPlayback': 'Lecture',
    'menuBarWindow': 'Fenêtre',
    'menuBarHelp': 'Aide',
    'menuPlay': 'Lire',
    'menuPause': 'Pause',
    'menuAction.file-open': 'Ouvrir…',
    'menuAction.file-import': 'Importer / Placer…',
    'menuAction.file-export': 'Exporter…',
    'menuAction.edit-undo': 'Annuler',
    'menuAction.edit-redo': 'Rétablir',
    'menuAction.edit-copy-frame': "Copier l'image",
    'menuAction.edit-paste-linked-frame': "Coller l'image liée",
    'menuAction.edit-new-drawing': 'Nouveau dessin sur cette image',
    'menuAction.edit-delete-cell': 'Supprimer la case',
    'menuAction.edit-cut-exposure': "Couper l'exposition",
    'menuAction.edit-toggle-mark': 'Basculer le repère',
    'menuAction.edit-keyboard-shortcuts': 'Raccourcis clavier…',
    'menuAction.edit-preferences': 'Préférences…',
    'menuAction.cut-new': 'Nouveau plan',
    'menuAction.cut-duplicate': 'Dupliquer le plan',
    'menuAction.cut-create-linked': 'Créer un plan lié',
    'menuAction.cut-convert-linked': 'Convertir en plan lié…',
    'menuAction.cut-rename': 'Renommer le plan…',
    'menuAction.cut-canvas-size': 'Taille du canevas…',
    'menuAction.cut-move-left': 'Déplacer le plan à gauche',
    'menuAction.cut-move-right': 'Déplacer le plan à droite',
    'menuAction.cut-copy-ae-camera': 'Copier les clés AE de la caméra',
    'menuAction.cut-delete': 'Supprimer le plan',
    'menuAction.layer-add': 'Ajouter un calque',
    'menuAction.layer-add-attach-free-above':
        'Ajouter un calque attaché libre au-dessus',
    'menuAction.layer-add-attach-free-below':
        'Ajouter un calque attaché libre en dessous',
    'menuAction.layer-add-attach-above':
        'Ajouter un calque attaché synchronisé au-dessus',
    'menuAction.layer-add-attach-below':
        'Ajouter un calque attaché synchronisé en dessous',
    'menuAction.layer-duplicate': 'Dupliquer le calque',
    'menuAction.layer-link-duplicate': 'Dupliquer en liant',
    'menuAction.layer-unlink': 'Délier le calque',
    'menuAction.layer-group-into-folder': 'Grouper dans un dossier',
    'menuAction.layer-group-attach-into-folder': 'Nouveau dossier attaché',
    'menuAction.layer-rename': 'Renommer le calque…',
    'menuAction.layer-rasterize': 'Pixelliser le calque',
    'menuAction.layer-se-name-tag': 'Étiquette SE…',
    'menuAction.layer-copy': 'Copier le calque',
    'menuAction.layer-paste': 'Coller le calque',
    'menuAction.layer-delete': 'Supprimer le calque…',
    'menuAction.playback-stop': 'Arrêter',
    'menuAction.playback-play-all': 'Lire tous les plans',
    'menuAction.window-tool-rail-right': "Barre d'outils à droite",
    'menuAction.window-region-on-top': 'Zone de timeline en haut',
    'menuAction.window-reset-layout': "Réinitialiser l'espace de travail",
    'menuAction.edit-input-inspector': "Inspecteur d'entrée",
    'menuAction.edit-frame-timing-overlay': 'Superposition du minutage des images',
    'menuAction.edit-frame-stats': 'Statistiques des images',
    'menuAction.edit-show-repaints': 'Afficher les redessins',
    'menuAction.edit-bake-panels': 'Pixelliser les panneaux statiques',
    'menuAction.edit-knee-at-one': "Tampon à la résolution de l'écran",
    'menuAction.edit-show-unpainted-tiles': 'Afficher les tuiles non peintes',
    'menuAction.help-about': 'À propos de Anicel',
    'fileOpenTitle': 'Ouvrir un projet',
    'fileSaveTitle': 'Enregistrer le projet',
    'fileStorageOffNotice':
        "L'accès au stockage est désactivé — les projets hors du dossier de "
        "l'application exigent l'autorisation Tous les fichiers.",
    'fileOpenSettings': 'Ouvrir les réglages',
    'fileNameLabel': 'Nom du fichier',
    'fileCloudNoticeOpen':
        'Services cloud (Google Drive, Dropbox …) : utilisez une app de '
        'synchronisation (Autosync, FolderSync …) et ouvrez son dossier '
        'miroir ici — les documents cloud directs ne sont pas pris en charge.',
    'replaceFileTitle': 'Remplacer le fichier ?',
    'replaceFileMessageTemplate': '{name} existe déjà ici.',
    'commonReplace': 'Remplacer',
    'folderNoPathTitle': "Cet emplacement n'a pas de chemin de dossier",
    'folderStorageOffTitle': "L'accès au stockage est désactivé",
    'folderPickUnavailable': "Impossible d'ouvrir le sélecteur de dossier.",
    'folderPickDriveNotice':
        'Google Drive ne peut pas fournir de dossier. Utilisez iCloud Drive, '
        'Dropbox ou cet appareil.',
    'projectChooserEmpty': 'Aucun projet Anicel dans ce dossier.',
    'fileNameEmpty': 'Le nom de fichier ne peut pas être vide.',
    'recentProjectsTitle': 'Projets récents',
    'recentReconnect': 'Reconnecter',
    'sortByName': 'Nom',
    'sortByModified': 'Modifié',
    'sortBySize': 'Taille',
    'sortAscending': 'Croissant',
    'sortDescending': 'Décroissant',
    'canvasSizeTitle': 'Taille du canevas',
    'cameraSizeTitle': 'Taille de la caméra',
    'canvasWidthLabel': 'Largeur (px)',
    'canvasHeightLabel': 'Hauteur (px)',
    'canvasAnchorHelpTemplate':
        'Ancrage : le dessin existant reste fixé ici. Les traits rognés sont '
        'conservés et réapparaissent si le canevas est agrandi. '
        '({min}–{max} px)',
    'canvasPresetDefault': 'Par défaut',
    'commonResize': 'Redimensionner',
    'menuAlphaPreview': 'Aperçu alpha',
    'inputTitle': 'Paramètres de saisie',
    'inputPressureHeading': 'Réponse à la pression',
    'inputPressureSoftHard': 'Doux ↔ Dur',
    'inputPressureLinear': 'Linéaire',
    'inputSpeedHeading': 'Réponse à la vitesse',
    'inputSpeedReference': 'Vitesse maximale',
    'inputCanvasHeading': 'Canevas',
    'inputRightClick': 'Clic droit / bouton latéral du stylet',
    'inputWheelClick': 'Clic molette / bouton supérieur du stylet',
    'inputPenTail': 'Talon du stylet (retourner le stylet)',
    'inputCanvasTouchHeading': 'Toucher sur le canevas',
    'inputDragOneFinger': 'Glissement à 1 doigt',
    'inputDragTwoFingers': 'Glissement à 2 doigts',
    'inputDragThreeFingers': 'Glissement à 3 doigts',
    'inputExtraFinger': 'Modificateur au doigt supplémentaire',
    'inputExtraFingerHelp':
        'Un doigt ajouté PENDANT un geste le contraint — zoom, rotation et '
        'taille par crans, avance image par image fine.',
    'inputFlipHaptics': 'Retour haptique du feuilletage',
    'inputFlipHapticsHelp':
        'Une pulsation à chaque fois que le feuilletage arrive sur un autre '
        'dessin. Silencieux sur le vide et sans moteur haptique.',
    'inputTwoFingerRotation': 'Rotation à deux doigts',
    'inputTwoFingerRotationHelp':
        'DÉSACTIVÉ : le geste de navigation ne fait que déplacer et zoomer '
        '(les boutons et le raccourci de rotation restent).',
    'inputRotationLock': 'Le modificateur verrouille la rotation',
    'inputRotationLockHelp':
        "ACTIVÉ : le doigt supplémentaire FIGE l'angle (déplacement pur + "
        "zoom par crans). DÉSACTIVÉ (par défaut) : il aligne l'angle.",
    'inputRotationSnap': 'Cran de rotation (°)',
    'inputZoomSnaps': 'Crans de zoom (%)',
    'inputBrushSizeSnaps': 'Crans de taille de pinceau (px)',
    'inputTabletHeading': 'Service tablette',
    'inputTabletStandard': 'Standard (par défaut)',
    'inputTabletStandardHelp':
        "Le pipeline de pointeur de l'OS (Windows Ink) — adapté aux pilotes "
        'à jour et aux stylets intégrés.',
    'inputTabletWintab': 'Wintab',
    'inputTabletWintabHelp':
        'Lit la pression directement depuis le pilote de la tablette — la '
        'solution de secours quand le stylet arrive sans pression ou comme '
        'toucher/souris.',
    'inputTabletAutoDemoted':
        'Retour à Standard : sur le chemin Wintab, le stylet n\'atteignait '
        'plus du tout la fenêtre.',
    'dragActionFlip': 'Feuilleter (images / calques)',
    'dragActionScreen': 'Écran (déplacer · zoomer · pivoter)',
    'dragActionBrushSize': 'Taille du pinceau',
    'dragActionDraw': 'Dessin au toucher',
    'commonNone': 'Aucun',
    'mapEyedropper': 'Pipette',
    'mapEraser': 'Gomme',
    'mapPan': 'Main',
    'mapUndo': 'Annuler',
    'mapRedo': 'Rétablir',
    'holdReturnToTool': "Revenir à l'outil",
    'holdKeep': 'Conserver',
    'prefsTitle': 'Préférences',
    'prefsInput': 'Saisie',
    'prefsAutosave': 'Sauvegarde auto',
    'prefsAudio': 'Audio',
    'prefsLanguage': 'Langue',
    'prefsAccent': "Couleurs d'accent",
    'prefsSystem': 'Système',
    'prefsMemory': 'Mémoire',
    'memoryProcessTotal': 'Cette application, en RAM',
    'memoryTracked': 'Détail connu',
    'memoryUntracked': 'Moteur, polices et framework',
    'memoryAvailable': 'Encore disponible',
    'memoryPinned': 'retenu pour la lecture',
    'memoryDeviceTotal': "Mémoire de l'appareil",
    'memoryAllowance': "Allocation de l'app",
    'memoryAllowanceAutomatic': "Revenir à l'allocation automatique",
    'memoryItemDrawings': 'Dessins',
    'memoryItemSheetInk': 'Écriture sur feuille',
    'memoryItemUndo': "Historique d'annulation",
    'memoryItemPlaybackFrames': 'Images de lecture',
    'memoryItemLayerImages': 'Images de calque',
    'memoryItemBrushTips': 'Pointes de brosse',
    'memoryItemPanelRasters': 'Rasters de panneau',
    'memoryItemViewerPages': 'Pages de la visionneuse',
    'memoryItemImageCache': "Cache d'images",
    'memoryItemStoryboardThumbnails': 'Vignettes du storyboard',
    'memoryItemMoviePictures': 'Vidéos de référence',
    'memoryItemTileImages': 'Images des tuiles du canevas',
    'memoryItemEngineBuffers': 'Tampons du moteur de dessin',
    'containerAreaSettings': 'Réglages',
    'containerAreaDiagnostics': 'Journal de diagnostic',
    'containerAreaSessionScratch': 'Espace de session',
    'containerTotal': 'Total',
    'saveCelsLostTemplate':
        'Enregistré, mais {count} dessin(s) manquent : le fichier de projet '
        'qui les contenait a été supprimé pendant que le projet était '
        'ouvert.',
    'saveCelsLostHeading': 'Dessins concernés',
    'saveCelsLostGone': 'Dessin absent du projet',
    'projectFileVanished':
        "Le fichier de ce projet n'est plus là — supprimé ou déplacé. "
        "Restaurez-le maintenant s'il est encore dans une corbeille : les "
        'dessins déjà enregistrés ne vivent que dans ce fichier.',
    'accentTitle': "Couleurs d'accent",
    'accent1Label': 'Accent 1',
    'accent1Help': 'Sélection, tête de lecture, bascules actives.',
    'sheetInfoTitle': 'Infos de la feuille',
    'sheetFieldTitle': 'Titre',
    'sheetFieldEpisode': 'Épisode',
    'sheetFieldScene': 'Scène',
    'sheetFieldCut': 'Plan',
    'sheetFieldTime': 'Durée',
    'sheetFieldName': 'Animateur',
    'sheetFieldSheet': 'Feuille',
    'sheetTitleHint': 'Nom du projet si vide',
    'sheetArtist': 'Animateur',
    'sheetStaffByProcess': 'Équipe par étape',
    'sheetVisibleBoxes': 'Cases visibles',
    'sheetStampPick': 'Choisir le tampon',
    'sheetStampClear': 'Retirer le tampon',
    'sheetNotation': 'Notation',
    'sheetExposureBar': 'Trait de maintien',
    'sheetExposureBarHelp':
        'Tracer le trait à partir du (N+1)e comma des maintiens de N+',
    'sheetExposureBarN': 'N (standard du métier : 3)',
    'sheetSeEmptyFill': 'Griser les plages sans dialogue',
    'instructionsTitle': 'Indications',
    'instructionEditTooltip': "Modifier l'indication",
    'instructionDeleteTooltip': "Supprimer l'indication",
    'instructionAddButton': 'Ajouter une indication',
    'instructionDefTitle': 'Indication',
    'instructionDefNameLabel': 'Nom (FI, PAN, …)',
    'instructionEventEditTitle': "Modifier l'indication",
    'instructionEventAddTitle': 'Ajouter une indication',
    'instructionMarkLabel': 'Indication (repère)',
    'instructionNameLabel': "Nom (vide = nom de l'indication)",
    'instructionStartLabel': 'Nom de début (A)',
    'instructionEndLabel': 'Nom de fin (B)',
    'instructionMemoLabel': 'Mémo (bande mémo de la feuille)',
    'instructionEditSetButton': 'Modifier les indications…',
    'instructionEditorIcon': 'Icône',
    'instructionEditorColor': 'Couleur',
    'instructionEditorMark': 'Repère',
    'systemStatusHelp':
        'Quelle implémentation chaque sous-système exécute en ce moment. Les chemins de repli gardent l\'application fonctionnelle mais tournent en général plus lentement — les noms sont cherchables si vous voulez les détails.',
    'shortcutCategory.Navigation': 'Navigation',
    'shortcutCategory.Playback': 'Lecture',
    'shortcutCategory.Edit': 'Édition',
    'shortcutCategory.Tools': 'Outils',
    'shortcutCategory.Selection': 'Sélection',
    'shortcutCategory.View': 'Affichage',
    'shortcutCategory.Timeline': 'Timeline',
    'shortcutCategory.File': 'Fichier',
    'shortcutAction.frame-previous': 'Image précédente',
    'shortcutAction.frame-next': 'Image suivante',
    'shortcutAction.frame-walk-left': 'Un pas à gauche',
    'shortcutAction.frame-walk-right': 'Un pas à droite',
    'shortcutAction.frame-walk-up': 'Un pas vers le haut',
    'shortcutAction.frame-walk-down': 'Un pas vers le bas',
    'shortcutAction.drawing-previous': 'Dessin précédent',
    'shortcutAction.drawing-next': 'Dessin suivant',
    'shortcutAction.playback-toggle': 'Lecture / Pause',
    'shortcutAction.canvas-pan-hold': 'Déplacer (maintenir)',
    'shortcutAction.voice-record-toggle':
        'Enregistrer la voix (démarrer/arrêter)',
    'shortcutAction.edit-undo': 'Annuler',
    'shortcutAction.edit-redo': 'Rétablir',
    'shortcutAction.tool-brush': 'Outil pinceau',
    'shortcutAction.tool-eraser': 'Outil gomme',
    'shortcutAction.tool-eyedropper': 'Outil pipette',
    'shortcutAction.tool-fill': 'Outil remplissage',
    'shortcutAction.tool-fill-bucket': 'Pot de peinture',
    'shortcutAction.tool-guide': 'Outil repère',
    'shortcutAction.tool-select': 'Outil sélection',
    'shortcutAction.tool-transform': 'Outil transformation',
    'shortcutAction.tool-transform-normal': 'Transformation normale',
    'shortcutAction.tool-transform-free': 'Transformation libre',
    'shortcutAction.tool-transform-mesh': 'Déformation par grille',
    'shortcutAction.tool-cut': 'Outil découpe',
    'shortcutAction.tool-cut-stamp': 'Tampon',
    'shortcutAction.selection-deselect': 'Désélectionner',
    'shortcutAction.selection-nudge-up':
        'Décaler la sélection / le calque vers le haut',
    'shortcutAction.selection-nudge-down':
        'Décaler la sélection / le calque vers le bas',
    'shortcutAction.selection-transform-commit': 'Valider la transformation',
    'shortcutAction.selection-transform-cancel': 'Annuler la transformation',
    'shortcutAction.onion-skin-toggle': "Activer/désactiver la pelure d'oignon",
    'shortcutAction.canvas-rotate-ccw': 'Pivoter la vue à gauche',
    'shortcutAction.canvas-rotate-cw': 'Pivoter la vue à droite',
    'shortcutAction.canvas-flip-horizontal': 'Miroir horizontal de la vue',
    'shortcutAction.timeline-comma-1': 'Régler sur 1 comma',
    'shortcutAction.timeline-comma-2': 'Régler sur 2 commas',
    'shortcutAction.timeline-comma-3': 'Régler sur 3 commas',
    'shortcutAction.timeline-comma-4': 'Régler sur 4 commas',
    'shortcutAction.timeline-comma-n': 'Régler sur N commas…',
    'shortcutAction.frame-new-drawing': 'Nouveau dessin',
    'shortcutAction.frame-blank-exposure': 'Vide / X',
    'shortcutAction.frame-toggle-mark': 'Basculer le repère',
    'shortcutAction.timeline-push-blocks': 'Pousser (ouvrir des images)',
    'shortcutAction.timeline-pull-blocks': 'Tirer (fermer des images)',
    'shortcutAction.edit-cut': 'Couper',
    'shortcutAction.edit-copy': 'Copier',
    'shortcutAction.edit-paste-linked': 'Coller lié',
    'shortcutAction.edit-paste-independent': 'Coller indépendant',
    'shortcutAction.edit-delete': 'Supprimer',
    'shortcutAction.edit-replace-colour': 'Remplacer la couleur',
    'shortcutAction.edit-clear-pixels': 'Effacer les pixels',
    'shortcutAction.edit-delete-colour': 'Supprimer la couleur',
    'shortcutAction.edit-keep-colour': 'Conserver la couleur',
    'shortcutAction.file-save': 'Enregistrer',
    'shortcutAction.file-save-as': 'Enregistrer sous…',
    'shortcutAction.layer-visibility-solo': 'Solo du calque actif',
    'shortcutAction.canvas-zoom-in': 'Zoom avant',
    'shortcutAction.canvas-zoom-out': 'Zoom arrière',
    'cutCommands': 'Commandes de plan',
    'cutAddCut': 'Ajouter un plan',
    'cutNewCut': 'Nouveau plan',
    'cutDuplicateCut': 'Dupliquer le plan',
    'cutDuplicateActive': 'Dupliquer le plan actif',
    'cutRename': 'Renommer le plan…',
    'cutEditNote': 'Modifier la note du plan…',
    'cutMoveLeft': 'Déplacer le plan à gauche',
    'cutMoveRight': 'Déplacer le plan à droite',
    'cutDelete': 'Supprimer le plan',
    'mediaActions': 'Actions média',
    'mediaImportAudio': "Importer de l'audio",
    'mediaRename': 'Renommer le média',
    'mediaPlace': 'Placer…',
    'mediaRelink': 'Relier…',
    'mediaMissingCount': '{n} fichiers multimédias introuvables',
    'mediaFindInFolder': 'Chercher dans un dossier…',
    'mediaRelinkFound': '{m} sur {n} trouvés. Les relier ?',
    'mediaRemove': 'Retirer',
    'mediaRegisterInProject': 'Conserver dans le fichier de projet',
    'mediaExportWav': 'Exporter en WAV',
    'mediaExportWavNoAudio': "Cet élément n'a pas d'audio à exporter.",
    'mediaCarriedState': 'Dans le projet',
    'mediaReferencedState': 'Lié',
    'projectLegacyAssetsFolder':
        "Ce projet a encore un dossier {name} à côté de lui. Plus rien n'y "
        'est écrit — enregistrez une fois et ses médias passent dans le '
        'fichier de projet, ensuite le dossier peut être supprimé.',
    'mediaOpenInViewer': 'Ouvrir dans la visionneuse',
    'mediaOpenInSubViewer': 'Ouvrir dans la visionneuse secondaire',
    'mediaViewerEmpty':
        'Rien à afficher.\nDouble-cliquez un fichier du pool de '
        'médias, ou ouvrez-en un avec le bouton ci-dessus.',
    'mediaViewerOpenFile': 'Ouvrir un fichier…',
    'mediaViewerLoadFailed': 'Impossible de lire ce fichier.',
    'mediaViewerCutTooLarge':
        'Trop grand pour être découpé en taille réelle dans la mémoire autorisée.',
    'mediaViewerCannotDisplay':
        'Ce type de média ne peut pas encore être affiché.',
    'mediaViewerNoPdfRenderer':
        'Pas de moteur PDF dans cette version — les pages PDF ne peuvent '
        'pas être affichées.',
    'mediaViewerNoVideoDecoder':
        'Pas de décodeur vidéo dans cette version — les films ne peuvent '
        'pas être affichés.',
    'mediaViewerNoAudioDecoder':
        'Ce son n\'a pas pu être lu — aucune forme d\'onde à afficher.',
    'unsupportedFileTitle': 'Fichier non pris en charge',
    'unsupportedFileMessageTemplate':
        '« {name} » ne peut pas être ouvert ici. Formats acceptés : '
        '{kinds}.',
    'mediaViewerSwap': "Échanger avec l'autre visionneuse",
    'mediaViewerRegisterAsset': 'Ajouter aux médias',
    'panelMediaViewer': 'Visionneuse',
    'panelMediaViewerSub': 'Visionneuse secondaire',
    'mediaRemoveInUse':
        'Ce média est utilisé. Le retirer quand même ? Les calques et '
        'images placés seront supprimés.',
    'mediaUsesHeading': 'Utilisations',
    'panelCanvas': 'Canevas',
    'panelColorWheel': 'Roue chromatique',
    'transportIn': 'Entrée',
    'transportOut': 'Sortie',
    'transportLoop': 'Boucle',
    'transportPrevFrame': 'Image précédente',
    'transportNextFrame': 'Image suivante',
    'colorRecent': 'Récentes',
    'colorBackgroundSwap': 'Couleur de fond (toucher pour échanger)',
    'penPressureTitle': 'Pression du stylet',
    'penPressureAxis': 'Pression →',
    'brushDynamicsTitle': 'Réponse',
    'curveSourcePressure': 'Pression',
    'curveSourceTilt': 'Inclinaison',
    'curveSourceSpeed': 'Vitesse',
    'onionCurrentDrawing': 'Dessin actuel',
    'audioLevelMeter': 'vumètre audio',
    'panelColorRgb': 'RVB',
    'panelColorPalette': 'Palette',
    'panelMedia': 'Médias',
    'panelOnionSkin': "Pelure d'oignon",
    'panelToolSize': 'Taille de l\'outil',
    'panelStoryboard': 'Storyboard',
    'panelTimeline': 'Timeline',
    'panelTimesheet': 'Feuille de temps',
    'panelConte': 'Conte',
    'panelEnvelope': 'Enveloppe',
    'commonRegister': 'Enregistrer',
    'commonNameField': 'Nom',
    'tipRegisterTitle': 'Enregistrer comme pointe',
    'panelToolLibrary': "Bibliothèque d'outils",
    'panelCollapseRegion': 'Réduire',
    'panelNewGroup': 'Nouveau groupe de panneaux',
    'panelRegionWidth': 'Largeur de la zone',
    'panelExpandRegion': 'Développer',
    'panelToolSettings': "Réglages de l'outil",
    'panelTools': 'Outils',
    'onionBefore': 'Avant',
    'onionAfter': 'Après',
    'onionBeforeTint': 'Teinte avant',
    'onionAfterTint': 'Teinte après',
    'onionGhostColorHelp': 'Comment les fantômes sont colorés',
    'onionPegCountHelp': 'Ce que compte un cran',
    'shortcutTitle': 'Raccourcis clavier',
    'shortcutResetAll': 'Tout réinitialiser',
    'shortcutResetToDefault': 'Rétablir le défaut',
    'shortcutRecordNew': 'Enregistrer un nouveau raccourci',
    'shortcutTouch': 'Raccourci tactile',
    'shortcutSearch': 'Rechercher une action',
    'shortcutConflictBanner':
        'Certaines actions partagent la même touche — les assignations '
        'surlignées entrent en conflit.',
    'shortcutRecordingHint': 'Appuyez sur des touches… (Échap annule)',
    'playbackQuality': 'Qualité de lecture',
    'playbackStop': 'Arrêter',
    'playbackToStart': 'Au début',
    'sheetPreviousPage': 'Page précédente',
    'sheetNextPage': 'Page suivante',
    'sheetPageDrag': 'Page (glisser / double-tap)',
    'autosaveTitle': 'Sauvegarde automatique',
    'autosaveEvery': 'Toutes les',
    'autosaveSectionHelp':
        'Enregistre le projet à intervalle régulier : un plantage ou une batterie vide ne coûte au plus que cet intervalle de travail.',
    'autosaveSwitchHelp':
        'Désactivé, le projet ne change qu\'à l\'enregistrement, et un plantage coûte tout ce qui a suivi.',
    'appContainerTitle': 'Conteneur de l\'application',
    'appContainerHelp':
        'Ce que l\'application garde en dehors de vos fichiers de projet : réglages et pointes de brosse, les médias et l\'audio qu\'un import a apportés et qu\'aucun enregistrement n\'a encore absorbés, et un journal de diagnostic.',
    'containerEmpty': 'Vide',
    'commonMinutesShort': ' min',
    'exExport': 'Exporter',
    'exAddToQueue': 'Ajouter à la file',
    'exImage': 'Image',
    'exVideo': 'Vidéo',
    'exCels': 'Cellulos',
    'exSheetPng': 'Feuille PNG',
    'exFormat': 'Format',
    'exOptions': 'Options',
    'exNaming': 'Nommage',
    'exScope': 'Portée',
    'exQuality': 'Qualité',
    'exCodec': 'Codec',
    'exBitrate': 'Débit',
    'exChannels': 'Canaux',
    'exAudio': 'Audio',
    'exBrowse': 'Parcourir…',
    'exSavePreset': 'Enregistrer le préréglage',
    'exPresetNameEmpty': 'Le nom du préréglage ne peut pas être vide.',
    'exBaseName': 'Nom de base',
    'exSuffix': 'Suffixe',
    'exDigits': 'Chiffres',
    'exApplyLayerFx': 'Appliquer les FX de calque',
    'exApplyLayerFxHelp':
        'Appliquer les FX de calque (transformations et opacité animée)',
    'exMuxSeMix': 'Intégrer le mixage SE dans la vidéo',
    'exLabel': 'Étiquette',
    'exApply': 'Appliquer',
    'exAdd': 'Ajouter',
    'exSelect': 'Sélection',
    'exSelBase': 'Base',
    'exSelAttach': 'Attaches',
    'exSelSheet': 'Feuille',
    'exSelDirection': 'Direction',
    'exSelCustom': 'Personnalisé',
    'exPaperLabel': 'Papier',
    'exArtLabel': 'Décor',
    'exTakeLatest': 'Dernière',
    'exFolders': 'Dossiers',
    'exNameParts': 'Nom',
    'exTarget': 'Cible',
    'exLayer': 'Calque',
    'exCelCount': '{n} cellulos',
    'exCelCountOne': '{n} cellulo',
    'exProject': 'Projet',
    'exCut': 'Plan',
    'exWhite': 'Blanc',
    'exBlack': 'Noir',
    'exBackground': 'Fond',
    'exChooseLocation': 'Choisissez un emplacement pour exporter.',
    'exNoCels': '(aucun cellulo)',
    'exNoCuts': '(aucun plan)',
    'exPresets': 'Préréglages',
    'exQueue': 'File d\'attente',
    'exSize': 'Taille',
    'exForm': 'Formulaire',
    'exCutSize': 'Taille du plan',
    'exRealSheet': 'Feuille réelle',
    'exWidth': 'Largeur',
    'exSheetLayers': 'Calques',
    'exContent': 'Contenu',
    'exInk': 'Encre',
    'exFiles': 'Fichiers',
    'exOneImage': 'Une image',
    'exOnePerLayer': 'Une par calque',
    'imImport': 'Importer',
    'imPool': 'Réserve',
    'imFile': 'Fichier',
    'imFiles': 'Fichiers',
    'imInto': 'Vers',
    'imFit': 'Ajuster',
    'imRevisions': 'Révisions',
    'imFilesButton': 'Fichiers…',
    'imCutFolderButton': 'Dossier de plan…',
    'imModified': 'Modifié',
    'imSize': 'Taille',
    'imArchivedProcesses': 'Étapes archivées (LO/, GEN/…)',
    'imMultiCutFolders': 'Dossiers multi-plans (兼用)',
    'imProcess': 'Étape',
    'imPicture': 'Image',
    'imReference': 'Référence',
    'imExcluded': 'Exclu',
    'imIgnored': 'Ignoré',
    'imMultiCutMark': '(multi-plan)',
    'imAndMore': ' et {n} de plus',
    'imPickToSee':
        'Choisissez des fichiers ou un dossier de plan pour voir '
        'l\'interprétation.',
    'imPlaceLabel': 'Placer',
    'imPlaceTitleTemplate': 'Placer — {name}',
    'imPoolOnlyTooltip':
        'Le pool de médias enregistre ; placez depuis la timeline.',
    'imAlreadyPooledTooltip': 'Déjà dans le pool de médias.',
    'imModeKeep': 'Intégrer',
    'imModeReference': 'Lier',
    'imBake': 'Pixelliser',
    'imSound': 'Son',
    'commonOn': 'Oui',
    'commonOff': 'Non',
    'imFitContain': 'Proportions',
    'imFitStretch': 'Étirer',
    'imIntoNewLayer': 'Nouveau calque',
    'imIntoSeRow': 'Ligne SE',
    'imIntoRowCellTemplate': '{row} · image {frame}',
    'imIntoNewCut': 'Nouveau plan',
    'imPsdMerge': 'Fusionner',
    'imPsdExpand': 'Développer',
    'imNoSource': 'Aucune source',
    'imFileCountTemplate': '{n} fichiers',
    'imStatusImporting': 'Importation…',
    'imStatusNothing': 'Rien n’a été importé.',
    'imFolderGone': 'Ce dossier n’existe plus.',
    'imFolderUnreadableTemplate': 'Impossible de lire le dossier : {reason}',
    'imCutFolderUnreadable': 'Impossible de lire ce dossier.',
    'imUnreadableTemplate': '{name} : impossible de lire le fichier.',
    'imCorruptTemplate':
        '{name} n’a pas pu être ouvert — fichier corrompu ou protégé par mot de passe.',
    'imPagesFailedTemplate':
        '{name} : {n} page(s) non rendue(s) — elles restent vides.',
    'imFramesFailedTemplate':
        '{name} : {n} image(s) non décodée(s) — elles restent vides.',
    'imNoPdfRendererTemplate': '{name} : pas de moteur PDF dans cette version.',
    'imCouldNotImportTemplate': 'Impossible d’importer {name}.',
    'imPsdNoLayersTemplate':
        '{name} : aucun calque à développer — importez-le fusionné.',
    'imRenderingPdfTemplate': 'Rendu de la page PDF {done}/{total}…',
    'imLargeCarryTemplate':
        '{total} entrent dans le fichier du projet — {files}{more}. L’intégration compresse chaque fichier à l’arrivée : le projet grossit donc de moins. Lier laisse les originaux où ils sont.',
    'imKeepExplain':
        'Le fichier du projet les contient, compressés ; les originaux restent intacts.',
    'imReferenceExplain':
        'Les fichiers restent où ils sont et le projet pointe vers eux.',
    'imCutFolderBakes':
        'Les dossiers de plan pixellisent toujours leurs images ; scans et vidéos restent liés.',
    'imRevLatest': 'Dernière',
    'imRevAll': 'Toutes',
    'imRevOriginals': 'Originaux',
    'mpFileMissing': 'Fichier introuvable — reliez-le',
    'mpInUseOnTimeline': 'Utilisé dans la timeline',
    'mpNameEmpty': 'Le nom du média ne peut pas être vide.',
    'exCameraTemplate': 'Caméra {w}×{h}',
    'toolBrush': 'Pinceau',
    'toolEraser': 'Gomme',
    'toolEyedropper': 'Pipette',
    'toolFill': 'Remplissage',
    'toolSelect': 'Sélection',
    'toolTransform': 'Transformation',
    'toolShapeFill': 'Remplissage de forme',
    'toolCutHint':
        'La découpe copie les pixels sous le glissement — l\'original reste.\nChoisissez Tampon pour poser le morceau que vous tenez.',
    'toolCutNothingHeld':
        'Rien en main pour l\'instant.\nDécoupez d\'abord un morceau avec la tuile rectangle ou lasso.',
    'toolCutPasteAtOrigin': 'Coller à la position d\'origine',
    'toolCutFlipHorizontal': 'Miroir horizontal',
    'toolCutFlipVertical': 'Miroir vertical',
    'toolCutRegisterTip': 'Enregistrer comme pointe…',
    'toolEyedropperReference': 'Référence',
    'brushSettingsTitle': 'Réglages de brosse',
    'toolShapeRect': 'Rectangle',
    'toolShapeEllipse': 'Ellipse',
    'toolShapeLasso': 'Lasso',
    'toolShapePolygon': 'Polygone',
    'toolShapeSelectTemplate': 'Sélection {shape}',
    'toolShapeCutTemplate': 'Découpe {shape}',
    'toolShapeFillTemplate': 'Remplissage {shape}',
    'brBrushesTitle': 'Brosses',
    'brGroupNameField': 'Nom du groupe',
    'brCreate': 'Créer',
    'brRenameBrush': 'Renommer la brosse',
    'brBrushNameField': 'Nom de la brosse',
    'brGroupNameEmpty': 'Le nom du groupe ne peut pas être vide.',
    'brBrushNameEmpty': 'Le nom de la brosse ne peut pas être vide.',
    'brResetLibraryBody':
        'Remplacer toute la bibliothèque — chaque groupe, pack importé et brosse enregistrée — par les brosses intégrées ?',
    'brSize': 'Taille',
    'brOpacity': 'Opacité',
    'brFlow': 'Débit',
    'brMixing': 'Mélanger au fond',
    'brPaintAmount': 'Quantité de peinture',
    'brPaintDensity': 'Densité de peinture',
    'brColorStretch': 'Étirement de la couleur',
    'brHardness': 'Dureté',
    'stepUp': 'Monter d’un cran',
    'stepDown': 'Baisser d’un cran',
    'brEdge': 'Bord',
    'brEdgeNone': 'Aucun',
    'brSpacing': 'Espacement',
    'brAngle': 'Angle',
    'brRoundness': 'Rondeur',
    'brScale': 'Échelle',
    'brSizeJitter': 'Variation de taille',
    'brOpacityJitter': "Variation d'opacité",
    'brAngleJitter': "Variation d'angle",
    'brRoundnessJitter': 'Variation de rondeur',
    'brSpacingJitter': "Variation d'espacement",
    'brScatter': 'Dispersion',
    'brScatterCount': 'Nombre',
    'brScatterBothAxes': 'Deux axes',
    'brTipRotation': 'Rotation',
    'brRotationFixed': 'Fixe',
    'brRotationDirection': 'Direction',
    'brBrushTip': 'Pointe',
    'brTipNone': 'Aucune',
    'brDualTip': 'Pointe double',
    'brTexture': 'Texture',
    'brTextureDensity': 'Densité',
    'brAddTipImage': 'Ajouter une pointe depuis une image',
    'brRenameTip': 'Renommer la pointe',
    'brDeleteTip': 'Supprimer la pointe',
    'brStabilizer': 'Stabilisateur',
    'tlAutoFrame': "Créer une image là où il n'y en a pas",
    'brBlend': 'Fusion',
    'brBlendMode': 'Mode de fusion du pinceau',
    'brEditGroup': 'Modifier le groupe',
    'brFolderIcon': 'Icône du dossier',
    'brFolderName': 'Nom du dossier',
    'brFeather': 'Contour progressif',
    'brTolerance': 'Tolérance',
    'brGapClose': 'Fermeture des trous',
    'brGrowShrink': 'Étendre / Réduire',
    'brAntiAlias': 'Anticrénelage',
    'brAntiAliasEdge': 'Anticrénelage du bord',
    'brTransformPreserveColors': 'Préserver les couleurs exactes',
    'brTransformPreserveColorsHint':
        'Transformer sans créer de couleurs '
        'intermédiaires',
    'trFlipHorizontal': 'Miroir horizontal',
    'trFlipVertical': 'Miroir vertical',
    'trAnchor': 'Point de référence',
    'trAnchorOpposite': 'Coin opposé',
    'trAnchorCenter': 'Centre',
    'trMeshColumns': 'Colonnes',
    'trMeshRows': 'Lignes',
    'brFillBeyondCanvas': 'Remplir au-delà du canevas',
    'brOpenRegionsRefuse': 'Les zones ouvertes ne se remplissent pas',
    'brName': 'Nom',
    'brDisplay': 'Affichage',
    'brTipIcon': 'Icône de pointe',
    'brStrokePreview': 'Aperçu du tracé',
    'brBrushOptions': 'Options du pinceau',
    'brGroupOptions': 'Options du groupe',
    'brNewGroup': 'Nouveau groupe',
    'brRenameGroup': 'Renommer le groupe',
    'brDeleteGroup': 'Supprimer le groupe',
    'brRenameSelected': 'Renommer le pinceau sélectionné',
    'brDeleteSelected': 'Supprimer le pinceau sélectionné',
    'brSaveAsPreset': 'Enregistrer les réglages comme préréglage',
    'brImportBrushes': 'Importer des pinceaux (.abr, .sut, .sutg)',
    'brResetLibrary': 'Réinitialiser la bibliothèque',
    'brExportSelected': 'Exporter la brosse',
    'brExportGroup': 'Exporter le groupe',
    'brExportNothing': 'Aucune brosse à exporter ici.',
    'brExpand': 'Déplier',
    'commonReset': 'Réinitialiser',
    'commonFill': 'Remplir',
    'viewFitToView': 'Ajuster à la fenêtre',
    'viewResetView': 'Réinitialiser la vue (100 %)',
    'panelSettings': 'Paramètres',
    'viewRotateLeft': 'Pivoter la vue à gauche',
    'viewRotateRight': 'Pivoter la vue à droite',
    'viewFlipHorizontal': 'Miroir horizontal',
    'viewFlipVertical': 'Miroir vertical',
    'viewStraighten': 'Redresser la vue (0°)',
    'viewZoomDrag': 'Zoom (glisser / double-tap)',
    'viewAngleDrag': 'Angle de vue (glisser / double-tap)',
    'viewDragDoubleTap': 'Glisser / double-tap',
    'viewCanvasColor': 'Couleur du canevas',
    'viewPasteboardColor': 'Couleur du fond',
    'viewBackdropColor': 'Couleur de l\'arrière-plan',
    'colorUseCurrent': 'Utiliser la couleur actuelle',
    'colorNone': 'Aucune',
    'tlSections': 'Sections',
    'tlAllDisplayedLayers': 'Tous les calques affichés',
    'tlShowAll': 'Tout afficher',
    'tlHideAll': 'Tout masquer',
    'tlSoloKind': 'Solo par type',
    'tlSoloColor': 'Solo par couleur',
    'tlSoloFillReferences': 'Solo des références de remplissage',
    'tlSoloFxOnRows': 'Solo des lignes avec FX',
    'tlSoloSheetOnRows': 'Solo des lignes sur la feuille',
    'tlApplyAllFx': 'Appliquer tous les FX',
    'tlBypassAllFx': 'Contourner tous les FX',
    'tlAllOnTimesheet': 'Tout mettre sur la feuille',
    'tlAllOffTimesheet': 'Tout retirer de la feuille',
    'tlClearAllMarks': 'Effacer tous les repères',
    'tlClearAllFillRefs': 'Effacer toutes les références de remplissage',
    'tlColVisibility': 'Colonne visibilité',
    'tlColLayerKind': 'Colonne type de calque',
    'tlColOnionSkin': "Colonne pelure d'oignon",
    'tlColOpacity': 'Colonne opacité',
    'tlColBlendMode': 'Colonne mode de fusion',
    'tlColFx': 'Colonne FX',
    'tlColMark': 'Colonne repère',
    'tlColFillReference': 'Colonne référence de remplissage',
    'tlColTimesheet': 'Colonne feuille de temps',
    'tlOpenOnionPanel': "Ouvrir le panneau pelure d'oignon",
    'tlLayerMark': 'Repère de calque',
    'tlLayerMarkNone': 'Aucune étiquette',
    'tlLayerMarkSource': 'Matériel',
    'tlLayerTake': 'Prise',
    'layerProcess.paper': 'Papier',
    'layerProcess.conte': 'Storyboard',
    'layerProcess.art': 'Décors',
    'layerProcess.layout': 'Layout',
    'layerProcess.rough-key': 'Clé brute',
    'layerProcess.key': 'Animation clé',
    'layerProcess.inbetween': 'Intervalles',
    'layerProcess.finish': 'Finition',
    'layerRevise.direction': 'Mise en scène',
    'layerRevise.animation-director': 'Directeur d\'animation',
    'layerRevise.chief-animation-director': 'Directeur d\'animation en chef',
    'layerRevise.director': 'Réalisateur',
    'layerRevise.chief-director': 'Réalisateur en chef',
    'layerRevise.action-animation-director': 'Directeur d\'animation action',
    'layerRevise.inbetween-check': 'Contrôle intervalles',
    'layerRevise.cell-check': 'Contrôle cellulos',
    'tlLayerTakeNumber': 'Prise {n}',
    'tlRepeat': 'Répéter',
    'tlRepeatSelection': 'Répéter la sélection',
    'tlSeNameTemplate': 'Nom SE {name}',
    'tlAddLayerHeader': 'Ajouter un calque',
    'tlNoLayers': 'Aucun calque',
    'tlLegendLayer': 'CALQUE',
    'tlAllDisplayedOpacity': 'Opacité de tous les calques affichés',
    'tlLinkedLayerTooltip': 'Calque lié — les images sont partagées',
    'tlLayerReference': 'Référence',
    'tlReferenceSourceShort': 'Dépasse la source de {n} images',
    'tlSelectedLayers': 'Calques sélectionnés',
    'tlAudioLane': 'Audio',
    'tlNameTagGroup': 'Cartouche',
    'tlTransformGroup': 'Transformation',
    'tlRunEdgeNone': 'Aucun',
    'tlRunEdgeHold': 'Maintien',
    'tlSelectedFrameRange': 'plage d\'images sélectionnée',
    'tlSelectedLaneRange': 'plage de piste sélectionnée',
    'tlSelectedCell': 'cellule sélectionnée',
    'tlSelectedPanelRange': 'plage de cases sélectionnée',
    'semLayer': 'calque',
    'semSelectedLayer': 'calque sélectionné',
    'semTrack': 'piste',
    'semSelectedTrack': 'piste sélectionnée',
    'sbVideoTrack': 'Piste vidéo',
    'noticeFillRegionOpen':
        'La zone n\'est pas fermée — rien n\'a été rempli (le remplissage hors toile exige une zone close).',
    'noticeCameraKeysCopied':
        'Images clés de caméra copiées pour After Effects.',
    'tlSameAsSelected': 'Comme la sélection',
    'tlKindAnimation': 'Animation',
    'tlKindStoryboard': 'Storyboard',
    'tlKindImage': 'Image',
    'tlKindText': 'Texte',
    'tlKindAdjustment': 'Calque de réglage',
    'tlKindFolder': 'Dossier',
    'tlKindSe': 'SE',
    'tlKindTransition': 'Transition',
    'tlKindCamera': 'Camera',
    'tlKindSemanticTemplate': 'Calque {kind}',
    'tlKindInstruction': 'Direction',
    'tlNoriShiro': 'MARGE',
    'textCelNewTitle': 'Nouveau texte',
    'textCelEditTitle': 'Modifier le texte',
    'textCelTextLabel': 'Texte',
    'textCelFontLabel': 'Police',
    'textCelFontSystem': 'Système',
    'textCelSizeLabel': 'Taille',
    'textCelAlignLabel': 'Alignement',
    'textCelAlignLeft': 'Gauche',
    'textCelAlignCenter': 'Centre',
    'textCelAlignRight': 'Droite',
    'textCelColorLabel': 'Encre',
    'textCelBoldLabel': 'Gras',
    'seNameTagShowLineLabel': 'Afficher le dialogue',
    'seNameTagLineInkLabel': 'Encre du dialogue',
    'seNameTagPreviewName': 'Nom',
    'seNameTagPreviewLine': 'Réplique',
    'textCelOutlineLabel': 'Contour (blanc)',
    'textCelBackgroundLabel': 'Boîte (rouge)',
    'textCelPositionLabel': 'Position',
    'seNameTagTitle': 'Étiquette SE',
    'seNameTagHint':
        'Où se place l\'étiquette du locuteur sur l\'image. Le texte vient '
        'du bloc (nom et dialogue) ; l\'œil de la ligne l\'affiche ou la '
        'masque.',
    'seNameTagPositionLabel': 'Position',
    'seNameTagBoxLabel': 'Boîte',
    'seNameTagSampleName': 'Nom',
    'seNameTagSampleLine': 'dialogue',
    'seNameTagReset': 'Réinitialiser',
    'tlAttachFreeAbove': 'Calque attaché libre au-dessus',
    'tlAttachFreeBelow': 'Calque attaché libre en dessous',
    'tlAttachSyncedAbove': 'Calque attaché synchronisé au-dessus',
    'tlAttachSyncedBelow': 'Calque attaché synchronisé en dessous',
    'tlLayerCommands': 'Commandes de calque',
    'tlFrameCommands': "Commandes d'image",
    'tlCut': 'Plan',
    'tlLayer': 'Calque',
    'tlFrame': 'Image',
    'tlDuplicateLayer': 'Dupliquer le calque',
    'tlSelectRowSpan': 'Sélectionner toute la ligne',
    'tlLinkDuplicateLayer': 'Dupliquer en liant',
    'tlUnlinkLayer': 'Délier le calque',
    'tlResetGroup': 'Réinitialiser (garde les clés)',
    'tlRenameLayer': 'Renommer le calque…',
    'tlCopyLayer': 'Copier le calque',
    'tlDeleteLayer': 'Supprimer le calque',
    'tlEffects': 'Effets',
    'tlAddEffectTemplate': 'Ajouter {name}',
    'tlRemoveEffectTemplate': 'Supprimer {name}',
    'tlDropIntoFolderTemplate': 'dans {name}',
    'tlDropOutOfFolder': 'hors du dossier',
    'tlDropAttachSyncedTemplate': 'attacher à {name} (synchronisé)',
    'tlDropAttachFreeTemplate': 'attacher à {name} (libre)',
    'tlDropDetachAttach': 'détacher',
    'tlDetachLayer': 'Détacher de la base',
    'tlAttachDropsFxTitle': 'Le fx sera perdu',
    'tlAttachDropsFxBody':
        'Une couche attachée ne garde pas son propre fx. Continuer supprimera le fx existant. Continuer ?',
    'tlSharedEdit': 'Modifier',
    'tlAdd': 'Ajouter',
    'tlPush': 'Pousser (ouvrir des images)',
    'tlPull': 'Tirer (fermer des images)',
    'sbOneStoryboardRowPerCut':
        'Ce plan a déjà un calque storyboard. Un seul par plan.',
    'cnPreviousPage': 'Page précédente',
    'cnNextPage': 'Page suivante',
    'cnActionColumn': 'Action',
    'cnConte': 'Storyboard',
    'tlBlankX': 'Vide / X',
    'tlMark': 'Repère ●',
    'tlSetCommasN': 'Régler sur N commas',
    'tlSetCommaTemplate': 'Régler sur {n} comma',
    'tlProjectAudioRate': "Fréquence d'échantillonnage du projet",
    'tlCustom': 'Personnalisé…',
    'tlShowSeRows': 'Afficher les lignes SE',
    'tlShowCameraRows': 'Afficher les lignes caméra',
    'tlStoryboardLayer': 'Calque storyboard',
    'setCommasTitle': 'Définir les commas',
    'setCommasField': "Images d'exposition",
    'projectFpsTitle': 'Fréquence du projet',
    'projectFpsField': 'Images par seconde',
  };

  static const _zhHansValues = <String, String>{
    'languageSettingsTitle': '语言设置',
    'programLanguageLabel': '程序语言',
    'notationLanguageLabel': '标注语言',
    'programLanguageHelp': '菜单、面板与标签的语言。',
    'notationLanguageHelp': '打印在摄影表等提交物上的语言。',
    'noCutSelected': '未选择镜头',
    'pageLabel': '页',
    'continuousLabel': '连续视图',
    'noticeNoFrameHere': '此处没有帧',
    'noticeLayerNotDrawable': '该图层不可绘制',
    'noticeEditAttachOwner': '请编辑父图层',
    'commonCancel': '取消',
    'commonApply': '应用',
    'commonRefresh': '刷新',
    'commonClose': '关闭',
    'commonAffectedFiles': '相关文件',
    'commonNotice': '提示',
    'tlSharedDeselect': '取消选择',
    'tlSharedColourEdit': '颜色编辑',
    'exportNoCuts': '此项目暂无可导出的镜头。',
    'audioOffsetTitle': 'A/V 偏移',
    'audioOffsetHelp':
        '微调画面相对声音的显示时机。可测量的延迟会自动校正，此设置用于消除剩余部分 — 无线耳机通常落后 150~300 毫秒且不作任何报告。正值让画面更晚显示（声音迟到是常见情况）。',
    'audioOffsetLabel': '偏移',
    'audioUnitFrames': '帧',
    'audioDevicesTitle': '设备',
    'audioDevicesHelp': '播放使用的扬声器与录音使用的麦克风。更改自下次播放起生效；已拔出的设备将回退到系统默认。',
    'audioOutputLabel': '输出',
    'audioInputLabel': '输入',
    'audioSystemDefault': '系统默认',
    'audioDeviceDefaultSuffix': '（默认）',
    'audioDeviceMissingSuffix': '（未连接）',
    'audioSyncInspectorTitle': '同步检查器',
    'recordVoiceTooltip': '在播放头位置录制语音',
    'recordVoiceStopTooltip': '停止录音（放置素材）',
    'recordMicOpenFailed': '无法打开麦克风 — 请检查首选项▸音频以及系统麦克风权限。',
    'recordMicPermissionDenied': '麦克风权限未被授予。',
    'recordSelectSeLane': '录音将放置到所选SE轨道 — 请先选择一个SE轨道。',
    'recordTakeClipped': '录音发生削波 — 块上的红角为标记。',
    'recordClipMarkerTooltip': '该录音已削波（电平过高）',
    'tlTransitionCrossingWarning': '超出镜头边界 — 未应用',
    'audioMicGainLabel': '麦克风增益（dB）',
    'audioInputChannelLabel': '输入声道',
    'audioInputChannelDevice': '按设备',
    'audioInputChannelMonoMix': '单声道混合',
    'audioInputChannelLeft': '仅左声道',
    'audioInputChannelRight': '仅右声道',
    'audioClippingNoticeLabel': '削波警告（提示+块标记）',
    'audioDenoiseLabel': '降噪（仅人声 — 录拟音时请关闭）',
    'audioInputMeterLabel': '输入电平',
    'audioTestSoundLabel': '测试声音',
    'audioCountInLabel': '倒数（秒）',
    'audioCueBeepsLabel': '提示音（ADR三响）',
    'audioStreamerLabel': '光带（切入扫过）',
    'recordNothingRecording': '当前没有在录音。',
    'recordTakeEmpty': '录音为空 — 没有可放置的内容。',
    'recordPlacementFailed': '录音未能放置。',
    'recordDroppedFramesTemplate': '已录音，但丢失了 {count} 帧（机器未能跟上）— 请检查这条录音。',
    'layerAudioTitle': '图层音频',
    'audioGainLabel': '增益',
    'audioPanLabel': '声像',
    'layerAudioPanHelp': '声像在原生混音器路径上生效（等功率法则）。',
    'audioMute': '静音',
    'audioSolo': '独奏',
    'fpsAudioTitleTemplate': '{from} → {to}：声音怎么办？',
    'fpsAudioBody':
        '这两个帧率的实际速度相差 0.1%，而声音存在于真实时间中 — 无法同时保持帧精确与时间精确。\n\n• 保持音频时间：声音保持真实秒数；帧位置漂移 0.1%（约每 42 秒一帧）。\n\n• 拉伸音频 0.1%：按精确的 pulldown 比例重采样（听不出的音高变化 — 电视电影的标准做法），每个声音保持其精确的帧范围。',
    'fpsAudioKeep': '保持音频时间',
    'fpsAudioPull': '拉伸音频 0.1%',
    'selectionMoveConfirmTitle': '确认移动',
    'selectionMoveConfirmBody': '要确认选区的移动吗？',
    'selectionMoveRevert': '还原',
    'selectionMoveApply': '确认',
    'selectionClosePolygon': '闭合形状',
    'commonSave': '保存',
    'commonDelete': '删除',
    'commonRename': '重命名',
    'commonLink': '链接',
    'commonPreview': '预览',
    'renameLayerTitle': '重命名图层',
    'renameLayerField': '图层名称',
    'renameLayerEmpty': '图层名称不能为空。',
    'renameCutTitle': '重命名镜头',
    'renameCutField': '镜头名称',
    'renameCutEmpty': '镜头名称不能为空。',
    'renameFrameTitle': '重命名帧',
    'renameFrameField': '帧名称',
    'renameKeyTitle': '重命名关键帧',
    'renameKeyField': '关键帧名称',
    'renameGuideTitle': '重命名参考线',
    'renameGuideField': '参考线名称',
    'renameGuideEmpty': '参考线名称不能为空。',
    'cutNoteTitle': '编辑镜头备注',
    'cutNoteField': '镜头备注',
    'deleteLayerTitle': '删除图层',
    'deleteLayerMessageTemplate': '要删除图层“{name}”吗？',
    'frameNameConflictTitle': '帧名称已存在',
    'frameNameConflictBody':
        '该名称已被此图层中的另一帧使用。是否链接到已有的同名帧，'
        '让相同名称共用同一张原画？',
    'seInstanceNewTitle': '新建 SE',
    'seInstanceEditTitle': '编辑 SE',
    'seNameLabel': '名称（说话者 — 留空则隐藏名条）',
    'seDialogueLabel': '台词',
    'seLinkedAudioLabel': '已链接音频',
    'seLinkedAudioNone': '无',
    'seUnlinkAudio': '解除链接',
    'keyInterpolationLinear': '线性',
    'keyInterpolationHold': '保持',
    'convertLinkedCutTitle': '转换为链接镜头',
    'convertLinkedCutBodyTemplate': '将“{cut}”（原本）与另一个镜头链接。同名图层会合并为一张共用画面。',
    'convertLinkedCutTargetLabel': '链接的镜头',
    'convertLinkedCutLinksTemplate': '链接 {names}。',
    'convertLinkedCutReplacedTemplate': '“{cut}”中 {count} 张同名原画将被原本的替换（원본 승리）。',
    'convertLinkedCutJoiningTemplate': '{count} 张原画加入共用集合。',
    'convertLinkedCutTargetGainsTemplate': '“{cut}”新增：{names}。',
    'convertLinkedCutOriginGainsTemplate': '本镜头新增：{names}。',
    'convertLinkedCutNothing':
        '没有可链接的内容 — 两个镜头已完全链接，'
        '或没有可共用的绘制图层。',
    'convertLinkedCutUndoNote': '撤销会同时还原两个镜头。',
    'convertLinkedCutResizeFirst':
        '两个镜头的画布尺寸不同。共用镜头共享同一张画，因此以原镜头的尺寸为准 '
        '— 建议先统一尺寸再进行更改。',
    'guideKindSymmetry': '对称',
    'guideKindPerspective': '透视',
    'guideAdd': '添加',
    'guideDelete': '删除',
    'guideShow': '在画布上显示',
    'guideActsOn': '正在作用于笔画',
    'guideActsOff': '未作用',
    'guideLibraryEmpty': '此镜头还没有参考线。',
    'guideSelectPrompt': '选择一条参考线以调整其设置。',
    'guideLineCount': '份数',
    'guideMirrorMode': '轴对称',
    'guideMirrorModeOn': '副本左右翻转（真正的镜像）。',
    'guideMirrorModeOff': '副本只是旋转 — 不会翻转。',
    'guideEyeLevelShow': '显示视平线',
    'guideConstrainToEyeLevel': '将消失点固定在视平线上',
    'guideConstrainToEyeLevelNote': '对下一次拖动生效；不会移动已放置的。',
    'guideVanishingPoint': '消失点',
    'guideVanishingPointAtInfinity': '平行（无穷远）',
    'guideAddVanishingPoint': '添加消失点',
    'guideMakeVertical': '设为完全垂直',
    'closeProjectTitle': '关闭项目？',
    'closeProjectBody': '你的更改尚未保存。仍要关闭吗？',
    'closeProjectVanishedBody':
        '此项目的文件已不在。现在关闭会一并失去只存在于该文件中的画稿。'
        '使用「另存为」可将当前仍打开的内容写入新文件。',
    'commonSaveAs': '另存为…',
    'saveProgressRunning': '正在保存…',
    'saveProgressDone': '已保存',
    'savePrepareRunning': '正在准备…',
    'savePrepareDone': '准备完成',
    'resizeProgressRunning': '正在调整尺寸…',
    'resizeProgressDone': '已调整尺寸',
    'bakeProgressRunning': '正在栅格化…',
    'bakeProgressDone': '栅格化完成',
    'unsavedAutosaveTitle': '保存你的项目',
    'unsavedAutosaveBody':
        '此项目从未保存过，自动保存没有可写入的位置。选择一个文件后，'
        '自动保存就会开始守护它。',
    'commonNotNow': '暂不',
    'topStripProject': '项目',
    'topStripSettings': '设置',
    'menuBarFile': '文件',
    'menuBarEdit': '编辑',
    'menuBarCut': '镜头',
    'menuBarLayer': '图层',
    'menuBarPlayback': '播放',
    'menuBarWindow': '窗口',
    'menuBarHelp': '帮助',
    'menuPlay': '播放',
    'menuPause': '暂停',
    'menuAction.file-open': '打开…',
    'menuAction.file-import': '导入/放置…',
    'menuAction.file-export': '导出…',
    'menuAction.edit-undo': '撤销',
    'menuAction.edit-redo': '重做',
    'menuAction.edit-copy-frame': '复制帧',
    'menuAction.edit-paste-linked-frame': '粘贴链接帧',
    'menuAction.edit-new-drawing': '在此帧新建原画',
    'menuAction.edit-delete-cell': '删除单元格',
    'menuAction.edit-cut-exposure': '剪切曝光',
    'menuAction.edit-toggle-mark': '切换标记',
    'menuAction.edit-keyboard-shortcuts': '键盘快捷键…',
    'menuAction.edit-preferences': '偏好设置…',
    'menuAction.cut-new': '新建镜头',
    'menuAction.cut-duplicate': '复制镜头',
    'menuAction.cut-create-linked': '创建链接镜头',
    'menuAction.cut-convert-linked': '转换为链接镜头…',
    'menuAction.cut-rename': '重命名镜头…',
    'menuAction.cut-canvas-size': '画布尺寸…',
    'menuAction.cut-move-left': '镜头左移',
    'menuAction.cut-move-right': '镜头右移',
    'menuAction.cut-copy-ae-camera': '复制摄影机 AE 关键帧',
    'menuAction.cut-delete': '删除镜头',
    'menuAction.layer-add': '添加图层',
    'menuAction.layer-add-attach-free-above': '在上方添加自由附属图层',
    'menuAction.layer-add-attach-free-below': '在下方添加自由附属图层',
    'menuAction.layer-add-attach-above': '在上方添加同步附属图层',
    'menuAction.layer-add-attach-below': '在下方添加同步附属图层',
    'menuAction.layer-duplicate': '复制图层',
    'menuAction.layer-link-duplicate': '链接复制图层',
    'menuAction.layer-unlink': '取消图层链接',
    'menuAction.layer-group-into-folder': '编组到文件夹',
    'menuAction.layer-group-attach-into-folder': '新建附属文件夹',
    'menuAction.layer-rename': '重命名图层…',
    'menuAction.layer-rasterize': '栅格化图层',
    'menuAction.layer-se-name-tag': 'SE 名字条…',
    'menuAction.layer-copy': '复制图层',
    'menuAction.layer-paste': '粘贴图层',
    'menuAction.layer-delete': '删除图层…',
    'menuAction.playback-stop': '停止',
    'menuAction.playback-play-all': '播放所有镜头',
    'menuAction.window-tool-rail-right': '工具条在右侧',
    'menuAction.window-region-on-top': '时间轴区域置顶',
    'menuAction.window-reset-layout': '重置工作区布局',
    'menuAction.edit-input-inspector': '输入检查器',
    'menuAction.edit-frame-timing-overlay': '帧时序叠加',
    'menuAction.edit-frame-stats': '帧统计',
    'menuAction.edit-show-repaints': '显示重绘',
    'menuAction.edit-bake-panels': '栅格化静态面板',
    'menuAction.edit-knee-at-one': '屏幕分辨率缓冲区',
    'menuAction.edit-show-unpainted-tiles': '显示未绘制的图块',
    'menuAction.help-about': '关于 Anicel',
    'fileOpenTitle': '打开项目',
    'fileSaveTitle': '保存项目',
    'fileStorageOffNotice': '存储访问已关闭 — 应用文件夹之外的项目需要"所有文件"权限。',
    'fileOpenSettings': '打开设置',
    'fileNameLabel': '文件名',
    'fileCloudNoticeOpen':
        '云服务（Google 云端硬盘、Dropbox 等）：请使用同步应用'
        '（Autosync、FolderSync 等），并在此打开它的镜像文件夹 — '
        '不支持直接打开云端文档。',
    'replaceFileTitle': '替换文件？',
    'replaceFileMessageTemplate': '{name} 已存在于此处。',
    'commonReplace': '替换',
    'folderNoPathTitle': '此位置没有文件夹路径',
    'folderStorageOffTitle': '存储访问已关闭',
    'folderPickUnavailable': '无法打开文件夹选择器。',
    'folderPickDriveNotice':
        'Google 云端硬盘无法提供文件夹。请使用 iCloud Drive、Dropbox 或本设备。',
    'projectChooserEmpty': '此文件夹中没有 Anicel 项目。',
    'fileNameEmpty': '文件名不能为空。',
    'recentProjectsTitle': '最近的项目',
    'recentReconnect': '重新连接',
    'sortByName': '名称',
    'sortByModified': '修改时间',
    'sortBySize': '大小',
    'sortAscending': '升序',
    'sortDescending': '降序',
    'canvasSizeTitle': '画布尺寸',
    'cameraSizeTitle': '摄影机尺寸',
    'canvasWidthLabel': '宽度（px）',
    'canvasHeightLabel': '高度（px）',
    'canvasAnchorHelpTemplate':
        '锚点：已有画面固定在此处。被裁掉的笔画会保留，画布再放大时会重新出现。'
        '（{min}–{max} px）',
    'canvasPresetDefault': '默认',
    'commonResize': '调整尺寸',
    'menuAlphaPreview': '透明度预览',
    'inputTitle': '输入设置',
    'inputPressureHeading': '压感曲线',
    'inputPressureSoftHard': '软 ↔ 硬',
    'inputPressureLinear': '线性',
    'inputSpeedHeading': '速度曲线',
    'inputSpeedReference': '最高速度',
    'inputCanvasHeading': '画布',
    'inputRightClick': '右键 / 笔侧键',
    'inputWheelClick': '滚轮点击 / 笔上键',
    'inputPenTail': '笔尾（把笔倒过来）',
    'inputCanvasTouchHeading': '画布触摸',
    'inputDragOneFinger': '单指拖动',
    'inputDragTwoFingers': '双指拖动',
    'inputDragThreeFingers': '三指拖动',
    'inputExtraFinger': '加指修饰键',
    'inputExtraFingerHelp': '手势进行中再加一根手指会约束它 — 缩放/旋转/笔刷大小吸附，逐帧微调。',
    'inputFlipHaptics': '翻页震动',
    'inputFlipHapticsHelp': '每当翻页落到另一张画上时轻震一下。空白处不震动，没有马达的设备也不会。',
    'inputTwoFingerRotation': '双指旋转',
    'inputTwoFingerRotationHelp': '关闭：导航手势只做平移和缩放（旋转按钮与快捷键保留）。',
    'inputRotationLock': '修饰键锁定旋转',
    'inputRotationLockHelp': '开启：额外的手指会冻结角度（纯平移 + 吸附缩放）。关闭（默认）：吸附角度。',
    'inputRotationSnap': '旋转吸附（°）',
    'inputZoomSnaps': '缩放吸附（%）',
    'inputBrushSizeSnaps': '笔刷大小吸附（px）',
    'inputTabletHeading': '数位板服务',
    'inputTabletStandard': '标准（默认）',
    'inputTabletStandardHelp': '系统指针通道（Windows Ink）— 适合新版驱动和内置笔。',
    'inputTabletWintab': 'Wintab',
    'inputTabletWintabHelp': '直接从数位板驱动读取压感 — 当笔没有压感或被识别为触摸/鼠标时的退路。',
    'inputTabletAutoDemoted': '已切回 Standard：在 Wintab 通道下，笔完全无法到达窗口。',
    'dragActionFlip': '翻页（帧 / 图层）',
    'dragActionScreen': '画面（平移·缩放·旋转）',
    'dragActionBrushSize': '笔刷大小',
    'dragActionDraw': '触摸绘制',
    'commonNone': '无',
    'mapEyedropper': '吸管',
    'mapEraser': '橡皮',
    'mapPan': '抓手',
    'mapUndo': '撤销',
    'mapRedo': '重做',
    'holdReturnToTool': '返回原工具',
    'holdKeep': '保持',
    'prefsTitle': '偏好设置',
    'prefsInput': '输入',
    'prefsAutosave': '自动保存',
    'prefsAudio': '音频',
    'prefsLanguage': '语言',
    'prefsAccent': '强调色',
    'prefsSystem': '系统',
    'prefsMemory': '内存',
    'memoryProcessTotal': '本应用占用的内存',
    'memoryTracked': '已知明细',
    'memoryUntracked': '引擎、字体与框架',
    'memoryAvailable': '尚可使用',
    'memoryPinned': '播放占用中',
    'memoryDeviceTotal': '设备内存',
    'memoryAllowance': '应用配额',
    'memoryAllowanceAutomatic': '恢复自动配额',
    'memoryItemDrawings': '画稿',
    'memoryItemSheetInk': '纸面手写',
    'memoryItemUndo': '撤销记录',
    'memoryItemPlaybackFrames': '播放帧',
    'memoryItemLayerImages': '图层图像',
    'memoryItemBrushTips': '笔尖',
    'memoryItemPanelRasters': '面板栅格',
    'memoryItemViewerPages': '查看器页面',
    'memoryItemImageCache': '图像缓存',
    'memoryItemStoryboardThumbnails': '分镜缩略图',
    'memoryItemMoviePictures': '引用视频',
    'memoryItemTileImages': '画布图块图像',
    'memoryItemEngineBuffers': '绘图引擎缓冲区',
    'containerAreaSettings': '设置',
    'containerAreaDiagnostics': '诊断日志',
    'containerAreaSessionScratch': '会话暂存区',
    'containerTotal': '合计',
    'saveCelsLostTemplate': '已保存，但有 {count} 张画面未能包含：存放它们的项目文件在项目打开期间被删除了。',
    'saveCelsLostHeading': '相关画面',
    'saveCelsLostGone': '项目中已不存在的画面',
    'projectFileVanished':
        '此项目的文件已不在原处 — 可能被删除或移动了。若还能从回收站恢复，请现在恢复：已保存过的画面只存在于该文件中。',
    'accentTitle': '强调色',
    'accent1Label': '强调色 1',
    'accent1Help': '用于选区、播放头和已启用的开关。',
    'sheetInfoTitle': '摄影表信息',
    'sheetFieldTitle': '标题',
    'sheetFieldEpisode': '集数',
    'sheetFieldScene': '场',
    'sheetFieldCut': '镜头',
    'sheetFieldTime': '时长',
    'sheetFieldName': '作画',
    'sheetFieldSheet': '表号',
    'sheetTitleHint': '留空则用项目名',
    'sheetArtist': '作画',
    'sheetStaffByProcess': '各工序负责人',
    'sheetVisibleBoxes': '显示的栏位',
    'sheetStampPick': '选择印章',
    'sheetStampClear': '移除印章',
    'sheetNotation': '标注',
    'sheetExposureBar': '保持延长线',
    'sheetExposureBarHelp': '在 N 格以上的保持中，从第 (N+1) 格开始画线',
    'sheetExposureBarN': 'N（行业标准为 3）',
    'sheetSeEmptyFill': '将无台词区间置灰',
    'instructionsTitle': '指示记号',
    'instructionEditTooltip': '编辑指示记号',
    'instructionDeleteTooltip': '删除指示记号',
    'instructionAddButton': '添加指示记号',
    'instructionDefTitle': '指示记号',
    'instructionDefNameLabel': '名称（FI、PAN 等）',
    'instructionEventEditTitle': '编辑指示',
    'instructionEventAddTitle': '添加指示',
    'instructionMarkLabel': '指示（记号）',
    'instructionNameLabel': '名称（留空则用记号名）',
    'instructionStartLabel': '起点名称（A）',
    'instructionEndLabel': '终点名称（B）',
    'instructionMemoLabel': '备注（摄影表备注栏）',
    'instructionEditSetButton': '编辑指示记号…',
    'instructionEditorIcon': '图标',
    'instructionEditorColor': '颜色',
    'instructionEditorMark': '记号',
    'systemStatusHelp': '每个子系统当前运行的是哪一种实现。回退路径仍能让应用正常工作，但通常更慢 — 想了解细节可以按名称搜索。',
    'shortcutCategory.Navigation': '导航',
    'shortcutCategory.Playback': '播放',
    'shortcutCategory.Edit': '编辑',
    'shortcutCategory.Tools': '工具',
    'shortcutCategory.Selection': '选区',
    'shortcutCategory.View': '视图',
    'shortcutCategory.Timeline': '时间轴',
    'shortcutCategory.File': '文件',
    'shortcutAction.frame-previous': '上一帧',
    'shortcutAction.frame-next': '下一帧',
    'shortcutAction.frame-walk-left': '向左一步',
    'shortcutAction.frame-walk-right': '向右一步',
    'shortcutAction.frame-walk-up': '向上一步',
    'shortcutAction.frame-walk-down': '向下一步',
    'shortcutAction.drawing-previous': '上一张原画',
    'shortcutAction.drawing-next': '下一张原画',
    'shortcutAction.playback-toggle': '播放 / 暂停',
    'shortcutAction.canvas-pan-hold': '移动（按住）',
    'shortcutAction.voice-record-toggle': '录音（开始/停止）',
    'shortcutAction.edit-undo': '撤销',
    'shortcutAction.edit-redo': '重做',
    'shortcutAction.tool-brush': '画笔工具',
    'shortcutAction.tool-eraser': '橡皮工具',
    'shortcutAction.tool-eyedropper': '吸管工具',
    'shortcutAction.tool-fill': '填充工具',
    'shortcutAction.tool-fill-bucket': '油漆桶',
    'shortcutAction.tool-guide': '参考线工具',
    'shortcutAction.tool-select': '选择工具',
    'shortcutAction.tool-transform': '变换工具',
    'shortcutAction.tool-transform-normal': '普通变换',
    'shortcutAction.tool-transform-free': '自由变换',
    'shortcutAction.tool-transform-mesh': '网格变形',
    'shortcutAction.tool-cut': '裁剪工具',
    'shortcutAction.tool-cut-stamp': '图章',
    'shortcutAction.selection-deselect': '取消选择',
    'shortcutAction.selection-nudge-up': '选区 / 图层上移微调',
    'shortcutAction.selection-nudge-down': '选区 / 图层下移微调',
    'shortcutAction.selection-transform-commit': '确认变换',
    'shortcutAction.selection-transform-cancel': '取消变换',
    'shortcutAction.onion-skin-toggle': '切换洋葱皮',
    'shortcutAction.canvas-rotate-ccw': '画布视图向左旋转',
    'shortcutAction.canvas-rotate-cw': '画布视图向右旋转',
    'shortcutAction.canvas-flip-horizontal': '画布视图水平翻转',
    'shortcutAction.timeline-comma-1': '设为 1 格',
    'shortcutAction.timeline-comma-2': '设为 2 格',
    'shortcutAction.timeline-comma-3': '设为 3 格',
    'shortcutAction.timeline-comma-4': '设为 4 格',
    'shortcutAction.timeline-comma-n': '设为 N 格…',
    'shortcutAction.frame-new-drawing': '新建画稿',
    'shortcutAction.frame-blank-exposure': '空 / ×',
    'shortcutAction.frame-toggle-mark': '切换标记',
    'shortcutAction.timeline-push-blocks': '推出（空出帧）',
    'shortcutAction.timeline-pull-blocks': '拉回（收拢帧）',
    'shortcutAction.edit-cut': '剪切',
    'shortcutAction.edit-copy': '复制',
    'shortcutAction.edit-paste-linked': '粘贴链接',
    'shortcutAction.edit-paste-independent': '粘贴独立',
    'shortcutAction.edit-delete': '删除',
    'shortcutAction.edit-replace-colour': '替换颜色',
    'shortcutAction.edit-clear-pixels': '清空像素',
    'shortcutAction.edit-delete-colour': '删除颜色',
    'shortcutAction.edit-keep-colour': '保留颜色',
    'shortcutAction.file-save': '保存',
    'shortcutAction.file-save-as': '另存为…',
    'shortcutAction.layer-visibility-solo': '独奏当前图层',
    'shortcutAction.canvas-zoom-in': '放大',
    'shortcutAction.canvas-zoom-out': '缩小',
    'cutCommands': '镜头命令',
    'cutAddCut': '添加镜头',
    'cutNewCut': '新建镜头',
    'cutDuplicateCut': '复制镜头',
    'cutDuplicateActive': '复制当前镜头',
    'cutRename': '重命名镜头…',
    'cutEditNote': '编辑镜头备注…',
    'cutMoveLeft': '镜头左移',
    'cutMoveRight': '镜头右移',
    'cutDelete': '删除镜头',
    'mediaActions': '媒体操作',
    'mediaImportAudio': '导入音频',
    'mediaRename': '重命名媒体',
    'mediaPlace': '放置…',
    'mediaRelink': '重新链接…',
    'mediaMissingCount': '找不到 {n} 个媒体文件',
    'mediaFindInFolder': '在文件夹中查找…',
    'mediaRelinkFound': '在 {n} 个中找到 {m} 个。要重新链接吗？',
    'mediaRemove': '移除',
    'mediaRegisterInProject': '收入项目文件',
    'mediaExportWav': '导出为 WAV',
    'mediaExportWavNoAudio': '此素材没有可导出的音频。',
    'mediaCarriedState': '在项目内',
    'mediaReferencedState': '链接',
    'projectLegacyAssetsFolder':
        '此项目旁边仍有 {name} 文件夹。它已不再被写入 — 保存一次后，'
        '其中的媒体会进入项目文件，之后即可删除该文件夹。',
    'mediaRemoveInUse': '正在使用中。仍要移除吗？放置的图层/帧将被删除。',
    'mediaUsesHeading': '使用位置',
    'mediaOpenInViewer': '在查看器中打开',
    'mediaOpenInSubViewer': '在副查看器中打开',
    'mediaViewerEmpty': '暂无可查看的内容。\n双击媒体池中的文件，或用上方按钮打开文件。',
    'mediaViewerOpenFile': '打开文件…',
    'mediaViewerLoadFailed': '无法读取此文件。',
    'mediaViewerCutTooLarge': '超出内存允许量，无法按原尺寸裁切。',
    'mediaViewerCannotDisplay': '此类媒体暂时无法查看。',
    'mediaViewerNoPdfRenderer': '此版本没有 PDF 渲染器 — 无法显示 PDF 页面。',
    'mediaViewerNoVideoDecoder': '此版本没有视频解码器 — 无法显示影片。',
    'mediaViewerNoAudioDecoder': '无法读取此声音 — 没有可显示的波形。',
    'mediaViewerSwap': '与另一个查看器互换',
    'unsupportedFileTitle': '不支持的文件',
    'unsupportedFileMessageTemplate': '无法在此处打开「{name}」。可用格式：{kinds}。',
    'mediaViewerRegisterAsset': '添加到媒体',
    'panelMediaViewer': '查看器',
    'panelMediaViewerSub': '副查看器',
    'panelCanvas': '画布',
    'panelColorWheel': '色轮',
    'transportIn': '入点',
    'transportOut': '出点',
    'transportLoop': '循环',
    'transportPrevFrame': '上一帧',
    'transportNextFrame': '下一帧',
    'colorRecent': '最近',
    'colorBackgroundSwap': '背景色（点按交换）',
    'penPressureTitle': '笔压',
    'penPressureAxis': '笔压 →',
    'brushDynamicsTitle': '响应',
    'curveSourcePressure': '笔压',
    'curveSourceTilt': '倾斜',
    'curveSourceSpeed': '速度',
    'onionCurrentDrawing': '当前画面',
    'audioLevelMeter': '音频电平表',
    'panelColorRgb': 'RGB',
    'panelColorPalette': '色板',
    'panelMedia': '媒体',
    'panelOnionSkin': '洋葱皮',
    'panelToolSize': '工具大小',
    'panelStoryboard': '分镜',
    'panelTimeline': '时间轴',
    'panelTimesheet': '摄影表',
    'panelConte': '分镜稿',
    'panelEnvelope': '包络',
    'commonRegister': '注册',
    'commonNameField': '名称',
    'tipRegisterTitle': '注册为笔尖',
    'panelToolLibrary': '工具库',
    'panelCollapseRegion': '折叠',
    'panelNewGroup': '新建面板组',
    'panelRegionWidth': '区域宽度',
    'panelExpandRegion': '展开',
    'panelToolSettings': '工具设置',
    'panelTools': '工具',
    'onionBefore': '之前',
    'onionAfter': '之后',
    'onionBeforeTint': '之前色调',
    'onionAfterTint': '之后色调',
    'onionGhostColorHelp': '残影的着色方式',
    'onionPegCountHelp': '一格所计的单位',
    'shortcutTitle': '键盘快捷键',
    'shortcutResetAll': '全部重置',
    'shortcutResetToDefault': '恢复默认',
    'shortcutRecordNew': '录制新快捷键',
    'shortcutTouch': '触摸快捷方式',
    'shortcutSearch': '搜索动作',
    'shortcutConflictBanner': '有动作共用同一按键 — 高亮的绑定发生冲突。',
    'shortcutRecordingHint': '请按键…（Esc 取消）',
    'playbackQuality': '播放质量',
    'playbackStop': '停止',
    'playbackToStart': '回到开头',
    'sheetPreviousPage': '上一页',
    'sheetNextPage': '下一页',
    'sheetPageDrag': '页面（拖动 / 双击）',
    'autosaveTitle': '自动保存',
    'autosaveEvery': '间隔',
    'autosaveSectionHelp':
        '每隔一段时间保存项目，崩溃或电量耗尽最多只损失这段时间的工作。',
    'autosaveSwitchHelp': '关闭后，项目只在保存时才会改变；一旦崩溃，此后的工作将全部丢失。',
    'appContainerTitle': '应用容器',
    'appContainerHelp':
        '应用保存在项目文件之外的内容：设置与笔尖、导入时带进来且尚未被任何一次保存吸收的媒体与音频，以及一份诊断日志。',
    'containerEmpty': '空',
    'commonMinutesShort': ' 分钟',
    'exExport': '导出',
    'exAddToQueue': '加入队列',
    'exImage': '图像',
    'exVideo': '视频',
    'exCels': '赛璐珞',
    'exSheetPng': '摄影表 PNG',
    'exFormat': '格式',
    'exOptions': '选项',
    'exNaming': '命名',
    'exScope': '范围',
    'exQuality': '质量',
    'exCodec': '编解码器',
    'exBitrate': '码率',
    'exChannels': '声道',
    'exAudio': '音频',
    'exBrowse': '浏览…',
    'exSavePreset': '保存预设',
    'exPresetNameEmpty': '预设名称不能为空。',
    'exBaseName': '基础名称',
    'exSuffix': '后缀',
    'exDigits': '位数',
    'exApplyLayerFx': '应用图层 FX',
    'exApplyLayerFxHelp': '应用图层 FX（变换与动画不透明度）',
    'exMuxSeMix': '将 SE 混音封装进视频',
    'exLabel': '标签',
    'exApply': '应用',
    'exAdd': '添加',
    'exSelect': '选择',
    'exSelBase': '基准',
    'exSelAttach': '附属',
    'exSelSheet': '律表',
    'exSelDirection': '指示',
    'exSelCustom': '自定义',
    'exPaperLabel': '用纸',
    'exArtLabel': '美术',
    'exTakeLatest': '最新',
    'exFolders': '创建文件夹',
    'exNameParts': '命名',
    'exTarget': '对象',
    'exLayer': '图层',
    'exCelCount': '{n}张',
    'exCelCountOne': '{n}张',
    'exProject': '项目',
    'exCut': '镜头',
    'exWhite': '白色',
    'exBlack': '黑色',
    'exBackground': '背景',
    'exChooseLocation': '选择位置后即可导出。',
    'exNoCels': '（无赛璐珞）',
    'exNoCuts': '（无镜头）',
    'exPresets': '预设',
    'exQueue': '队列',
    'exSize': '尺寸',
    'exForm': '表单',
    'exCutSize': '镜头尺寸',
    'exRealSheet': '实际纸张',
    'exWidth': '宽度',
    'exSheetLayers': '图层',
    'exContent': '内容',
    'exInk': '线稿',
    'exFiles': '文件',
    'exOneImage': '单张图片',
    'exOnePerLayer': '每图层一张',
    'imImport': '导入',
    'imPool': '素材池',
    'imFile': '文件',
    'imFiles': '文件',
    'imInto': '放入',
    'imFit': '适配',
    'imRevisions': '修订',
    'imFilesButton': '文件…',
    'imCutFolderButton': '镜头文件夹…',
    'imModified': '修改时间',
    'imSize': '大小',
    'imArchivedProcesses': '已归档工序（LO/、GEN/…）',
    'imMultiCutFolders': '兼用镜头文件夹',
    'imProcess': '工序',
    'imPicture': '图片',
    'imReference': '参考',
    'imExcluded': '已排除',
    'imIgnored': '已忽略',
    'imMultiCutMark': '（兼用）',
    'imAndMore': ' 等{n}个',
    'imPickToSee': '选择文件或镜头文件夹即可查看解析。',
    'imPlaceLabel': '放置',
    'imPlaceTitleTemplate': '放置 — {name}',
    'imPoolOnlyTooltip': '媒体池只登记；请从时间轴放置。',
    'imAlreadyPooledTooltip': '已在媒体池中。',
    'imModeKeep': '内嵌',
    'imModeReference': '链接',
    'imBake': '栅格化',
    'imSound': '声音',
    'commonOn': '开',
    'commonOff': '关',
    'imFitContain': '保持比例',
    'imFitStretch': '拉伸',
    'imIntoNewLayer': '新图层',
    'imIntoSeRow': 'SE 行',
    'imIntoRowCellTemplate': '{row} · 第{frame}格',
    'imIntoNewCut': '新镜头',
    'imPsdMerge': '合并',
    'imPsdExpand': '展开',
    'imNoSource': '未选择来源',
    'imFileCountTemplate': '{n} 个文件',
    'imStatusImporting': '正在导入…',
    'imStatusNothing': '没有导入任何内容。',
    'imFolderGone': '该文件夹已不存在。',
    'imFolderUnreadableTemplate': '无法读取文件夹：{reason}',
    'imCutFolderUnreadable': '无法读取该文件夹。',
    'imUnreadableTemplate': '{name}：无法读取文件。',
    'imCorruptTemplate': '无法打开 {name} — 文件已损坏或受密码保护。',
    'imPagesFailedTemplate': '{name}：{n} 页渲染失败 — 这些页保持空白。',
    'imFramesFailedTemplate': '{name}：{n} 帧解码失败 — 这些格保持空白。',
    'imNoPdfRendererTemplate': '{name}：此版本没有 PDF 渲染器。',
    'imCouldNotImportTemplate': '无法导入 {name}。',
    'imPsdNoLayersTemplate': '{name}：没有可展开的图层 — 请以合并方式导入。',
    'imRenderingPdfTemplate': '正在渲染 PDF 页面 {done}/{total}…',
    'imLargeCarryTemplate':
        '{total} 将放入项目文件 — {files}{more}。内嵌时会逐个压缩，所以项目增加的大小会更小。链接会让原文件留在原处。',
    'imKeepExplain': '项目文件以压缩方式保存这些文件；原文件保持不变。',
    'imReferenceExplain': '文件保留在原处，项目指向它们。',
    'imCutFolderBakes': '镜头文件夹中的图像总是栅格化；扫描和视频保持链接。',
    'imRevLatest': '最新',
    'imRevAll': '全部',
    'imRevOriginals': '原件',
    'mpFileMissing': '文件缺失 — 请重新链接',
    'mpInUseOnTimeline': '在时间线中使用',
    'mpNameEmpty': '媒体名称不能为空。',
    'exCameraTemplate': '摄影机 {w}×{h}',
    'toolBrush': '画笔',
    'toolEraser': '橡皮',
    'toolEyedropper': '吸管',
    'toolFill': '填充',
    'toolSelect': '选择',
    'toolTransform': '变换',
    'toolShapeFill': '形状填充',
    'toolCutHint': '裁切会复制拖动范围内的像素 — 原图仍在。\n选择图章即可放下手中的碎片。',
    'toolCutNothingHeld': '尚未持有任何内容。\n请先用矩形或套索图块裁切一块。',
    'toolCutPasteAtOrigin': '粘贴到原位置',
    'toolCutFlipHorizontal': '水平翻转',
    'toolCutFlipVertical': '垂直翻转',
    'toolCutRegisterTip': '注册为笔尖…',
    'toolEyedropperReference': '参考',
    'brushSettingsTitle': '笔刷设置',
    'toolShapeRect': '矩形',
    'toolShapeEllipse': '椭圆',
    'toolShapeLasso': '套索',
    'toolShapePolygon': '多边形',
    'toolShapeSelectTemplate': '{shape}选择',
    'toolShapeCutTemplate': '{shape}裁剪',
    'toolShapeFillTemplate': '{shape}填充',
    'brBrushesTitle': '笔刷',
    'brGroupNameField': '组名称',
    'brCreate': '创建',
    'brRenameBrush': '重命名笔刷',
    'brBrushNameField': '笔刷名称',
    'brGroupNameEmpty': '组名称不能为空。',
    'brBrushNameEmpty': '笔刷名称不能为空。',
    'brResetLibraryBody': '要用内置笔刷替换整个库 — 包括每个组、导入的包和已保存的笔刷吗？',
    'brSize': '大小',
    'brOpacity': '不透明度',
    'brFlow': '流量',
    'brMixing': '与底色混合',
    'brPaintAmount': '颜料量',
    'brPaintDensity': '颜料浓度',
    'brColorStretch': '色彩延伸',
    'brHardness': '硬度',
    'stepUp': '增加一级',
    'stepDown': '减少一级',
    'brEdge': '边缘',
    'brEdgeNone': '无',
    'brSpacing': '间距',
    'brAngle': '角度',
    'brRoundness': '圆度',
    'brScale': '缩放',
    'brSizeJitter': '大小抖动',
    'brOpacityJitter': '不透明度抖动',
    'brAngleJitter': '角度抖动',
    'brRoundnessJitter': '圆度抖动',
    'brSpacingJitter': '间隔抖动',
    'brScatter': '散布',
    'brScatterCount': '数量',
    'brScatterBothAxes': '双轴',
    'brTipRotation': '旋转',
    'brRotationFixed': '固定',
    'brRotationDirection': '前进方向',
    'brBrushTip': '笔尖',
    'brTipNone': '无',
    'brDualTip': '双重笔尖',
    'brTexture': '纹理',
    'brTextureDensity': '浓度',
    'brAddTipImage': '从图像添加笔尖',
    'brRenameTip': '重命名笔尖',
    'brDeleteTip': '删除笔尖',
    'brStabilizer': '防抖',
    'tlAutoFrame': '在空单元格上绘制时自动创建帧',
    'brBlend': '混合',
    'brBlendMode': '画笔混合模式',
    'brEditGroup': '编辑分组',
    'brFolderIcon': '文件夹图标',
    'brFolderName': '文件夹名称',
    'brFeather': '羽化',
    'brTolerance': '容差',
    'brGapClose': '闭合缝隙',
    'brGrowShrink': '扩展 / 收缩',
    'brAntiAlias': '抗锯齿',
    'brAntiAliasEdge': '边缘抗锯齿',
    'brTransformPreserveColors': '保留原始颜色',
    'brTransformPreserveColorsHint': '变换时不生成中间色',
    'brFillBeyondCanvas': '填充到画布之外',
    'brOpenRegionsRefuse': '开放区域不会被填充',
    'brName': '名称',
    'brDisplay': '显示',
    'brTipIcon': '笔尖图标',
    'brStrokePreview': '笔画预览',
    'brBrushOptions': '画笔选项',
    'brGroupOptions': '分组选项',
    'brNewGroup': '新建分组',
    'brRenameGroup': '重命名分组',
    'brDeleteGroup': '删除分组',
    'brRenameSelected': '重命名所选画笔',
    'brDeleteSelected': '删除所选画笔',
    'brSaveAsPreset': '将当前设置保存为预设',
    'brImportBrushes': '导入画笔（.abr、.sut、.sutg）',
    'brResetLibrary': '重置画笔库',
    'brExportSelected': '导出画笔',
    'brExportGroup': '导出画笔组',
    'brExportNothing': '这里没有可导出的画笔。',
    'brExpand': '展开',
    'trFlipHorizontal': '水平翻转',
    'trFlipVertical': '垂直翻转',
    'trAnchor': '基准点',
    'trAnchorOpposite': '对角',
    'trAnchorCenter': '中心',
    'trMeshColumns': '列数',
    'trMeshRows': '行数',
    'commonReset': '重置',
    'commonFill': '填充',
    'viewFitToView': '适应窗口',
    'viewResetView': '重置视图（100%）',
    'panelSettings': '设置',
    'viewRotateLeft': '视图向左旋转',
    'viewRotateRight': '视图向右旋转',
    'viewFlipHorizontal': '视图水平翻转',
    'viewFlipVertical': '视图垂直翻转',
    'viewStraighten': '摆正视图（0°）',
    'viewZoomDrag': '缩放（拖动 / 双击）',
    'viewAngleDrag': '视图角度（拖动 / 双击）',
    'viewDragDoubleTap': '拖动 / 双击',
    'viewCanvasColor': '画布颜色',
    'viewPasteboardColor': '底板颜色',
    'viewBackdropColor': '背景颜色',
    'colorUseCurrent': '使用当前颜色',
    'colorNone': '无',
    'tlSections': '区段',
    'tlAllDisplayedLayers': '所有显示的图层',
    'tlShowAll': '全部显示',
    'tlHideAll': '全部隐藏',
    'tlSoloKind': '按类型独奏',
    'tlSoloColor': '按颜色独奏',
    'tlSoloFillReferences': '独奏填充参考',
    'tlSoloFxOnRows': '独奏已开 FX 的行',
    'tlSoloSheetOnRows': '独奏已上表的行',
    'tlApplyAllFx': '应用全部 FX',
    'tlBypassAllFx': '旁通全部 FX',
    'tlAllOnTimesheet': '全部放上摄影表',
    'tlAllOffTimesheet': '全部移出摄影表',
    'tlClearAllMarks': '清除所有标记',
    'tlClearAllFillRefs': '清除所有填充参考',
    'tlColVisibility': '可见性列',
    'tlColLayerKind': '图层类型列',
    'tlColOnionSkin': '洋葱皮列',
    'tlColOpacity': '不透明度列',
    'tlColBlendMode': '混合模式列',
    'tlColFx': 'FX 列',
    'tlColMark': '标记列',
    'tlColFillReference': '填充参考列',
    'tlColTimesheet': '摄影表列',
    'tlOpenOnionPanel': '打开洋葱皮面板',
    'tlLayerMark': '图层标记',
    'tlRepeat': '重复',
    'tlRepeatSelection': '重复所选',
    'tlSeNameTemplate': 'SE 名称 {name}',
    'tlAddLayerHeader': '添加图层',
    'tlNoLayers': '没有图层',
    'tlLegendLayer': '图层',
    'tlAllDisplayedOpacity': '所有显示图层的不透明度',
    'tlLinkedLayerTooltip': '链接图层 — 画面是共享的',
    'tlLayerReference': '引用',
    'tlReferenceSourceShort': '超出素材{n}帧',
    'tlSelectedLayers': '所选图层',
    'tlAudioLane': '音频',
    'tlNameTagGroup': '名牌',
    'tlTransformGroup': '变换',
    'tlRunEdgeNone': '无',
    'tlRunEdgeHold': '保持',
    'tlSelectedFrameRange': '选中的帧范围',
    'tlSelectedLaneRange': '选中的轨道范围',
    'tlSelectedCell': '选中的单元格',
    'tlSelectedPanelRange': '选中的分镜范围',
    'semLayer': '图层',
    'semSelectedLayer': '选中的图层',
    'semTrack': '轨道',
    'semSelectedTrack': '选中的轨道',
    'sbVideoTrack': '视频轨道',
    'noticeFillRegionOpen': '区域未闭合，未进行填充（画布外填充需要一个封闭区域）。',
    'noticeCameraKeysCopied': '已为 After Effects 复制摄像机关键帧。',
    'tlSameAsSelected': '与所选相同',
    'tlKindAnimation': '动画',
    'tlKindStoryboard': '分镜',
    'tlKindImage': '图像',
    'tlKindText': '文本',
    'tlKindAdjustment': '调整图层',
    'tlKindFolder': '文件夹',
    'tlKindSe': 'SE',
    'tlKindTransition': 'Transition',
    'tlKindCamera': 'Camera',
    'tlKindSemanticTemplate': '{kind}图层',
    'textCelNewTitle': '新建文本',
    'textCelEditTitle': '编辑文本',
    'textCelTextLabel': '文本',
    'textCelFontLabel': '字体',
    'textCelFontSystem': '系统',
    'textCelSizeLabel': '大小',
    'textCelAlignLabel': '对齐',
    'textCelAlignLeft': '左',
    'textCelAlignCenter': '居中',
    'textCelAlignRight': '右',
    'textCelColorLabel': '墨色',
    'textCelBoldLabel': '加粗',
    'seNameTagShowLineLabel': '显示台词',
    'seNameTagLineInkLabel': '台词颜色',
    'seNameTagPreviewName': '名字',
    'seNameTagPreviewLine': '台词',
    'textCelOutlineLabel': '描边（白）',
    'textCelBackgroundLabel': '底框（红）',
    'textCelPositionLabel': '位置',
    'seNameTagTitle': 'SE 名字条',
    'seNameTagHint': '这一行说话者标签在画面上的位置。文字取自区块的名称与台词，显示与否由行的眼睛控制。',
    'seNameTagPositionLabel': '位置',
    'seNameTagBoxLabel': '底框',
    'seNameTagSampleName': '名称',
    'seNameTagSampleLine': '台词',
    'seNameTagReset': '恢复默认',
    // 🚨A TRADE TERM, not a general word (user 2026-08-12: 「현장용어만
    // 원어/영어로 두기로 하자」). ja/ko already transliterate it rather than
    // translate it — ディレクション / 디렉션 — so zh standing alone with 指示
    // was the odd one out, not the rule.
    'tlKindInstruction': 'Direction',
    'tlNoriShiro': '留白',
    'tlAttachFreeAbove': '在上方添加自由附属图层',
    'tlAttachFreeBelow': '在下方添加自由附属图层',
    'tlAttachSyncedAbove': '在上方添加同步附属图层',
    'tlAttachSyncedBelow': '在下方添加同步附属图层',
    'tlLayerCommands': '图层命令',
    'tlFrameCommands': '帧命令',
    'tlCut': '镜头',
    'tlLayer': '图层',
    'tlFrame': '帧',
    'tlDuplicateLayer': '复制图层',
    'tlSelectRowSpan': '选择整行',
    'tlLinkDuplicateLayer': '链接复制图层',
    'tlUnlinkLayer': '取消图层链接',
    'tlResetGroup': '重置（保留关键帧）',
    'tlRenameLayer': '重命名图层…',
    'tlCopyLayer': '复制图层',
    'tlDeleteLayer': '删除图层',
    'tlEffects': '效果',
    'tlAddEffectTemplate': '添加{name}',
    'tlRemoveEffectTemplate': '删除{name}',
    'tlDropIntoFolderTemplate': '移入 {name}',
    'tlDropOutOfFolder': '移出文件夹',
    'tlDropAttachSyncedTemplate': '附属到 {name}（同步）',
    'tlDropAttachFreeTemplate': '附属到 {name}（自由）',
    'tlDropDetachAttach': '解除附属',
    'tlDetachLayer': '解除附属',
    'tlAttachDropsFxTitle': '附属后将失去 fx',
    'tlAttachDropsFxBody': '附属图层不保留自身的 fx。继续将丢弃现有的 fx。要继续吗？',
    'tlSharedEdit': '编辑',
    'tlAdd': '添加',
    'tlPush': '推出（空出帧）',
    'tlPull': '拉回（收拢帧）',
    'sbOneStoryboardRowPerCut': '该镜头已有分镜图层，每个镜头只能有一个。',
    'cnPreviousPage': '上一页',
    'cnNextPage': '下一页',
    'cnActionColumn': '动作',
    'cnConte': '分镜',
    'tlBlankX': '空 / ×',
    'tlMark': '标记 ●',
    'tlSetCommasN': '设为 N 格',
    'tlSetCommaTemplate': '设为 {n} 格',
    'tlProjectAudioRate': '项目音频采样率',
    'tlCustom': '自定义…',
    'tlShowSeRows': '显示 SE 行',
    'tlShowCameraRows': '显示摄影机行',
    'tlStoryboardLayer': '分镜图层',
    'setCommasTitle': '设置格数',
    'setCommasField': '曝光帧数',
    'projectFpsTitle': '项目帧率',
    'projectFpsField': '每秒帧数',
  };
}
