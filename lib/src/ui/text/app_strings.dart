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
}

/// PROGRAM-language strings (UI-R10 #7): what the app chrome reads in.
/// Coverage rolls out incrementally — panels adopt entries as they get
/// touched; untabled strings simply stay English in the widgets.
class AppStrings {
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
  String get noticeNothingToTransform => _s('noticeNothingToTransform');

  /// Synced attach rows look like blocks but own no timing — a grab
  /// redirects to the owner (the synced-block UI's cursor guidance).
  String get noticeEditAttachOwner => _s('noticeEditAttachOwner');

  /// Shared dialog verbs — tabled once, reused by every dialog that
  /// adopts localization.
  String get commonCancel => _s('commonCancel');
  String get commonApply => _s('commonApply');
  String get commonRefresh => _s('commonRefresh');
  String get commonClose => _s('commonClose');

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

  // --- Mix controls (AUDIO-PRO R1) ---
  String get layerAudioTitle => _s('layerAudioTitle');
  String get audioGainLabel => _s('audioGainLabel');
  String get audioPanLabel => _s('audioPanLabel');
  String get layerAudioPanHelp => _s('layerAudioPanHelp');
  String get audioSolo => _s('audioSolo');
  String get audioUnsolo => _s('audioUnsolo');
  String get audioLayerAudioMenu => _s('audioLayerAudioMenu');
  String get audioClipGainMenu => _s('audioClipGainMenu');
  String get audioEnvelopeMenu => _s('audioEnvelopeMenu');
  String get audioFadesEqualPowerMenu => _s('audioFadesEqualPowerMenu');
  String get audioFadesLinearMenu => _s('audioFadesLinearMenu');
  String get audioClipGainTitle => _s('audioClipGainTitle');
  String get audioEnvelopeTitle => _s('audioEnvelopeTitle');
  String get audioEnvelopeHelp => _s('audioEnvelopeHelp');
  String get audioEnvelopeFrameLabel => _s('audioEnvelopeFrameLabel');
  String get audioEnvelopeGainPercentLabel =>
      _s('audioEnvelopeGainPercentLabel');
  String get audioEnvelopeAddKey => _s('audioEnvelopeAddKey');

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

  /// '{frame}' is replaced with the 1-based frame number.
  String get cameraKeyTitleTemplate => _s('cameraKeyTitleTemplate');
  String get cameraKeyLinear => _s('cameraKeyLinear');
  String get cameraKeyHold => _s('cameraKeyHold');

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

  // --- Project lifecycle confirmations ---
  String get recoverAutosaveTitle => _s('recoverAutosaveTitle');
  String get recoverAutosaveBody => _s('recoverAutosaveBody');
  String get recoverOpenSaved => _s('recoverOpenSaved');
  String get recoverAction => _s('recoverAction');
  String get closeProjectTitle => _s('closeProjectTitle');
  String get closeProjectBody => _s('closeProjectBody');
  String get commonSaveAs => _s('commonSaveAs');
  String get unsavedAutosaveTitle => _s('unsavedAutosaveTitle');
  String get unsavedAutosaveBody => _s('unsavedAutosaveBody');
  String get commonNotNow => _s('commonNotNow');

  // --- The menu bar's own headings and its one stateful entry ---
  String get menuBarFile => _s('menuBarFile');
  String get menuBarEdit => _s('menuBarEdit');
  String get menuBarCut => _s('menuBarCut');
  String get menuBarLayer => _s('menuBarLayer');
  String get menuBarPlayback => _s('menuBarPlayback');
  String get menuBarWindow => _s('menuBarWindow');
  String get menuBarHelp => _s('menuBarHelp');
  String get menuPlay => _s('menuPlay');
  String get menuPause => _s('menuPause');

  // --- The file browser ---
  String get fileOpenTitle => _s('fileOpenTitle');
  String get fileSaveTitle => _s('fileSaveTitle');
  String get fileAppDocuments => _s('fileAppDocuments');
  String get fileStorageOffNotice => _s('fileStorageOffNotice');
  String get fileOpenSettings => _s('fileOpenSettings');
  String get fileCheckAgain => _s('fileCheckAgain');
  String get fileNameLabel => _s('fileNameLabel');
  String get fileCloudNoticeOpen => _s('fileCloudNoticeOpen');
  String get fileCloudNoticeSave => _s('fileCloudNoticeSave');
  String get fileNewFolderAction => _s('fileNewFolderAction');
  String get newFolderTitle => _s('newFolderTitle');
  String get newFolderField => _s('newFolderField');
  String get newFolderEmpty => _s('newFolderEmpty');
  String get commonCreate => _s('commonCreate');
  String get replaceFileTitle => _s('replaceFileTitle');

  /// '{name}' is the colliding file name.
  String get replaceFileMessageTemplate => _s('replaceFileMessageTemplate');
  String get commonReplace => _s('commonReplace');

  // --- Canvas size ---
  String get canvasSizeTitle => _s('canvasSizeTitle');
  String get canvasWidthLabel => _s('canvasWidthLabel');
  String get canvasHeightLabel => _s('canvasHeightLabel');

  /// '{min}'/'{max}' are the dimension bounds.
  String get canvasAnchorHelpTemplate => _s('canvasAnchorHelpTemplate');
  String get canvasPresetDefault => _s('canvasPresetDefault');
  String get commonResize => _s('commonResize');

  // --- Project background ---
  String get backgroundTitle => _s('backgroundTitle');
  String get backgroundPaper => _s('backgroundPaper');
  String get backgroundWhite => _s('backgroundWhite');
  String get backgroundBlack => _s('backgroundBlack');
  String get backgroundTransparent => _s('backgroundTransparent');
  String get backgroundCustom => _s('backgroundCustom');
  String get backgroundHelp => _s('backgroundHelp');
  String get stagePaperSection => _s('stagePaperSection');
  String get stagePasteboardSection => _s('stagePasteboardSection');
  String get stageBackdropSection => _s('stageBackdropSection');
  String get stageAlphaLabel => _s('stageAlphaLabel');
  String get menuAlphaPreview => _s('menuAlphaPreview');

  // --- Input settings ---
  String get inputTitle => _s('inputTitle');
  String get inputTouchScroll => _s('inputTouchScroll');
  String get inputTouchScrollHelp => _s('inputTouchScrollHelp');
  String get inputPressureHeading => _s('inputPressureHeading');
  String get inputPressureSoftHard => _s('inputPressureSoftHard');
  String get inputPressureLinear => _s('inputPressureLinear');
  String get inputCanvasHeading => _s('inputCanvasHeading');
  String get inputRightClick => _s('inputRightClick');
  String get inputWheelClick => _s('inputWheelClick');
  String get inputCanvasTouchHeading => _s('inputCanvasTouchHeading');
  String get inputDragOneFinger => _s('inputDragOneFinger');
  String get inputDragTwoFingers => _s('inputDragTwoFingers');
  String get inputDragThreeFingers => _s('inputDragThreeFingers');
  String get inputExtraFinger => _s('inputExtraFinger');
  String get inputExtraFingerHelp => _s('inputExtraFingerHelp');
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
  String get prefsSystem => _s('prefsSystem');

  // --- Accent colours ---
  String get accentTitle => _s('accentTitle');
  String get accent1Label => _s('accent1Label');
  String get accent1Help => _s('accent1Help');
  String get accent2Label => _s('accent2Label');
  String get accent2AutoLabel => _s('accent2AutoLabel');
  String get accent2AutoHelp => _s('accent2AutoHelp');
  String get accent2AutoHint => _s('accent2AutoHint');
  String get accent2CustomHint => _s('accent2CustomHint');

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
  String get sheetVisibleBoxes => _s('sheetVisibleBoxes');
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

  // --- The timeline action toolbar and its flyouts ---
  String get tlAddLayerHeader => _s('tlAddLayerHeader');
  String get tlSameAsSelected => _s('tlSameAsSelected');
  String get tlKindAnimation => _s('tlKindAnimation');
  String get tlKindStoryboard => _s('tlKindStoryboard');
  String get tlKindArt => _s('tlKindArt');
  String get tlKindSe => _s('tlKindSe');
  String get tlKindInstruction => _s('tlKindInstruction');
  String get tlAttachFreeAbove => _s('tlAttachFreeAbove');
  String get tlAttachFreeBelow => _s('tlAttachFreeBelow');
  String get tlAttachSyncedAbove => _s('tlAttachSyncedAbove');
  String get tlAttachSyncedBelow => _s('tlAttachSyncedBelow');
  String get tlLayerCommands => _s('tlLayerCommands');
  String get tlFrameCommands => _s('tlFrameCommands');
  String get tlLayer => _s('tlLayer');
  String get tlFrame => _s('tlFrame');
  String get tlDuplicateLayer => _s('tlDuplicateLayer');
  String get tlLinkDuplicateLayer => _s('tlLinkDuplicateLayer');
  String get tlUnlinkLayer => _s('tlUnlinkLayer');
  String get tlGroupIntoFolder => _s('tlGroupIntoFolder');
  String get tlRenameLayer => _s('tlRenameLayer');
  String get tlCopyLayer => _s('tlCopyLayer');
  String get tlDeleteLayer => _s('tlDeleteLayer');
  String get tlImportAudio => _s('tlImportAudio');
  String get tlCopyFrame => _s('tlCopyFrame');
  String get tlPasteLinkedFrame => _s('tlPasteLinkedFrame');
  String get tlDeleteCell => _s('tlDeleteCell');
  String get tlEditInstance => _s('tlEditInstance');
  String get tlAdd => _s('tlAdd');
  String get tlBlankX => _s('tlBlankX');
  String get tlMark => _s('tlMark');

  /// Design D: the rigid shove as a verb. PUSH opens frames at the anchor
  /// and everything after travels with its spacing; PULL closes them and
  /// stops where the first affected row runs out of room.
  String get tlPush => _s('tlPush');
  String get tlPull => _s('tlPull');
  String get tlSetCommasN => _s('tlSetCommasN');

  /// The storyboard's V rows share ONE height; these step it.
  String get sbShorterRows => _s('sbShorterRows');
  String get sbTallerRows => _s('sbTallerRows');

  /// Refused: a cut holds at most one storyboard row.
  String get sbOneStoryboardRowPerCut => _s('sbOneStoryboardRowPerCut');

  /// The conte sheet panel.
  String get cnPreviousPage => _s('cnPreviousPage');
  String get cnNextPage => _s('cnNextPage');
  String get cnActionColumn => _s('cnActionColumn');
  String get cnConte => _s('cnConte');

  /// '{n}' is the comma count.
  String get tlSetCommaTemplate => _s('tlSetCommaTemplate');
  String get tlProjectAudioRate => _s('tlProjectAudioRate');
  String get tlCustom => _s('tlCustom');
  String get tlShowSeRows => _s('tlShowSeRows');
  String get tlShowCameraRows => _s('tlShowCameraRows');
  String get tlArtLayer => _s('tlArtLayer');
  String get tlStoryboardLayer => _s('tlStoryboardLayer');

  // --- The cut command group ---
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

  // --- The media browser ---
  String get mediaActions => _s('mediaActions');
  String get mediaImportAudio => _s('mediaImportAudio');
  String get mediaRename => _s('mediaRename');
  String get mediaRelink => _s('mediaRelink');
  String get mediaRemove => _s('mediaRemove');
  String get mediaStillLinked => _s('mediaStillLinked');

  // --- Workspace panel names ---
  String get panelCanvas => _s('panelCanvas');
  String get panelColor => _s('panelColor');
  String get panelMedia => _s('panelMedia');
  String get panelOnionSkin => _s('panelOnionSkin');
  String get panelStoryboard => _s('panelStoryboard');
  String get panelTimeline => _s('panelTimeline');
  String get panelTimesheet => _s('panelTimesheet');
  String get panelToolLibrary => _s('panelToolLibrary');
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
  String get autosaveChoose => _s('autosaveChoose');
  String get autosaveDefault => _s('autosaveDefault');
  String get autosaveSidecarFolder => _s('autosaveSidecarFolder');

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
  String get exFilter => _s('exFilter');
  String get exBrowse => _s('exBrowse');
  String get exSavePreset => _s('exSavePreset');
  String get exPresetNameEmpty => _s('exPresetNameEmpty');
  String get exBaseName => _s('exBaseName');
  String get exSuffix => _s('exSuffix');
  String get exDigits => _s('exDigits');
  String get exApplyLayerFx => _s('exApplyLayerFx');
  String get exApplyLayerFxHelp => _s('exApplyLayerFxHelp');
  String get exOnTimesheetOnly => _s('exOnTimesheetOnly');
  String get exInstructionLayer => _s('exInstructionLayer');
  String get exMuxSeMix => _s('exMuxSeMix');
  String get exCutFolder => _s('exCutFolder');
  String get exLayerFolder => _s('exLayerFolder');
  String get exProjectName => _s('exProjectName');
  String get exProject => _s('exProject');
  String get exCut => _s('exCut');
  String get exFreeAttach => _s('exFreeAttach');
  String get exSyncAttach => _s('exSyncAttach');

  /// The cel scope toggle for folder members ('Folder 전부' before it was
  /// tabled — the app's second hardcoded-Korean string).
  String get exFolderMembers => _s('exFolderMembers');
  String get exWhite => _s('exWhite');
  String get exBlack => _s('exBlack');

  /// '{w}'/'{h}' are the camera frame's pixel dimensions.
  String get exCameraTemplate => _s('exCameraTemplate');

  /// '{name}' is the current layer-group label.
  String get exLayersTemplate => _s('exLayersTemplate');

  // --- Tools, the brush library and its settings ---
  String get toolBrush => _s('toolBrush');
  String get toolEraser => _s('toolEraser');
  String get toolEyedropper => _s('toolEyedropper');
  String get toolFill => _s('toolFill');
  String get toolSelect => _s('toolSelect');
  String get toolMove => _s('toolMove');
  String get toolBrushTip => _s('toolBrushTip');
  String get toolEraserTip => _s('toolEraserTip');
  String get toolEyedropperTip => _s('toolEyedropperTip');
  String get toolFillTip => _s('toolFillTip');
  String get toolSelectTip => _s('toolSelectTip');
  String get toolMoveTip => _s('toolMoveTip');
  String get brSize => _s('brSize');
  String get brOpacity => _s('brOpacity');
  String get brFlow => _s('brFlow');
  String get brMixing => _s('brMixing');
  String get brPaintAmount => _s('brPaintAmount');
  String get brPaintDensity => _s('brPaintDensity');
  String get brColorStretch => _s('brColorStretch');
  String get brHardness => _s('brHardness');
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
  String get brAddTipImage => _s('brAddTipImage');
  String get brTipRotation => _s('brTipRotation');
  String get brRotationFixed => _s('brRotationFixed');
  String get brRotationDirection => _s('brRotationDirection');
  String get brStabilizer => _s('brStabilizer');
  String get brBlend => _s('brBlend');
  String get brBlendMode => _s('brBlendMode');
  String get brBlendLock => _s('brBlendLock');
  String get brEditGroup => _s('brEditGroup');
  String get brFolderIcon => _s('brFolderIcon');
  String get brFolderName => _s('brFolderName');
  String get brFeather => _s('brFeather');
  String get brTolerance => _s('brTolerance');
  String get brGapClose => _s('brGapClose');
  String get brGrowShrink => _s('brGrowShrink');
  String get brAntiAlias => _s('brAntiAlias');
  String get brAntiAliasEdge => _s('brAntiAliasEdge');
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
  String get brExpand => _s('brExpand');
  String get brMeshWarp => _s('brMeshWarp');
  String get commonReset => _s('commonReset');
  String get commonFill => _s('commonFill');

  // --- Canvas view controls ---
  String get viewZoomIn => _s('viewZoomIn');
  String get viewZoomOut => _s('viewZoomOut');
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

  // --- The layer-controls header (column toggles, solo, section fold) ---
  String get tlSections => _s('tlSections');
  String get tlFoldSection => _s('tlFoldSection');
  String get tlHideSectionLayers => _s('tlHideSectionLayers');
  String get tlShowSectionLayers => _s('tlShowSectionLayers');
  String get tlOnlyThisSection => _s('tlOnlyThisSection');
  String get tlAllDisplayedLayers => _s('tlAllDisplayedLayers');
  String get tlShowAll => _s('tlShowAll');
  String get tlHideAll => _s('tlHideAll');
  String get tlSoloActiveLayer => _s('tlSoloActiveLayer');
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
  String get tlAddLayerHere => _s('tlAddLayerHere');
  String get tlDissolveFolder => _s('tlDissolveFolder');
  String get tlRenameFolder => _s('tlRenameFolder');
  String get tlRemoveAudio => _s('tlRemoveAudio');
  String get tlLayerMark => _s('tlLayerMark');
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

  static const _en = AppStrings._(_enValues);
  static const _ja = AppStrings._(_jaValues);
  static const _ko = AppStrings._(_koValues);
  static const _fr = AppStrings._(_frValues);
  static const _zhHans = AppStrings._(_zhHansValues);

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
    'noticeNothingToTransform': 'Nothing to transform',
    'noticeEditAttachOwner': 'Edit the owner layer',
    'commonCancel': 'Cancel',
    'commonApply': 'Apply',
    'commonRefresh': 'Refresh',
    'commonClose': 'Close',
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
    'audioSolo': 'Solo',
    'audioUnsolo': 'Unsolo',
    'audioLayerAudioMenu': 'Layer audio…',
    'audioClipGainMenu': 'Gain…',
    'audioEnvelopeMenu': 'Volume envelope…',
    'audioFadesEqualPowerMenu': 'Fades: equal-power (switch to linear)',
    'audioFadesLinearMenu': 'Fades: linear (switch to equal-power)',
    'audioClipGainTitle': 'Clip Gain',
    'audioEnvelopeTitle': 'Volume Envelope',
    'audioEnvelopeHelp':
        'Keyed gains at clip frames (linear between keys, held past the ends). Empty = flat.',
    'audioEnvelopeFrameLabel': 'frame',
    'audioEnvelopeGainPercentLabel': 'gain %',
    'audioEnvelopeAddKey': 'Add key',
    'fpsAudioTitleTemplate': '{from} → {to}: what happens to sound?',
    'fpsAudioBody':
        'These two rates differ by 0.1% in real speed, and audio exists in real seconds — it cannot stay both frame-exact and time-exact.\n\n• Keep audio timing: sounds keep their real seconds; their frame positions drift by 0.1% (about one frame every 42 seconds).\n\n• Pull audio 0.1%: sounds are resampled by the exact pulldown ratio (an inaudible pitch change — the standard telecine conform) so every sound keeps its exact frame span.',
    'fpsAudioKeep': 'Keep audio timing',
    'fpsAudioPull': 'Pull audio 0.1%',
    'selectionMoveConfirmTitle': 'Commit move',
    'selectionMoveConfirmBody': 'Commit the selection move?',
    'selectionMoveRevert': 'Revert',
    'selectionMoveApply': 'Commit',
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
    'cameraKeyTitleTemplate': 'Camera keys — frame {frame}',
    'cameraKeyLinear': 'Linear',
    'cameraKeyHold': 'Hold',
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
    'recoverAutosaveTitle': 'Recover autosaved changes?',
    'recoverAutosaveBody':
        'A newer autosave exists for this project. Recover it, or open the '
        'file as last saved?',
    'recoverOpenSaved': 'Open saved',
    'recoverAction': 'Recover',
    'closeProjectTitle': 'Close project?',
    'closeProjectBody': 'Your changes are not saved. Close anyway?',
    'commonSaveAs': 'Save as…',
    'unsavedAutosaveTitle': 'Save your project',
    'unsavedAutosaveBody':
        'This project has never been saved, so autosave has nowhere to '
        'write. Pick a file and autosave will guard it from then on.',
    'commonNotNow': 'Not now',
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
    'fileAppDocuments': 'App documents',
    'fileStorageOffNotice':
        'Storage access is off — projects outside the app folder need the '
        'All-Files permission.',
    'fileOpenSettings': 'Open settings',
    'fileCheckAgain': 'Check again',
    'fileNameLabel': 'File name',
    'fileCloudNoticeOpen':
        'Cloud services (Google Drive, Dropbox …): use a sync app (Autosync, '
        'FolderSync …) and open its mirror folder here — direct cloud '
        'documents are not supported.',
    'fileCloudNoticeSave':
        'Cloud folders: save into a sync-app mirror folder to work with '
        'Google Drive / Dropbox.',
    'fileNewFolderAction': 'New folder…',
    'newFolderTitle': 'New folder',
    'newFolderField': 'Folder name',
    'newFolderEmpty': 'Folder name cannot be empty.',
    'commonCreate': 'Create',
    'replaceFileTitle': 'Replace file?',
    'replaceFileMessageTemplate': '{name} already exists here.',
    'commonReplace': 'Replace',
    'canvasSizeTitle': 'Canvas size',
    'canvasWidthLabel': 'Width (px)',
    'canvasHeightLabel': 'Height (px)',
    'canvasAnchorHelpTemplate':
        'Anchor: existing artwork stays pinned here. Cropped strokes are '
        'kept and reappear if the canvas grows again. ({min}–{max} px)',
    'canvasPresetDefault': 'Default',
    'commonResize': 'Resize',
    'backgroundTitle': 'Project background',
    'backgroundPaper': 'Paper (default)',
    'backgroundWhite': 'White',
    'backgroundBlack': 'Black',
    'backgroundTransparent': 'Transparent',
    'backgroundCustom': 'Custom',
    'backgroundHelp':
        'The stage is four planes: backdrop, pasteboard, paper, pictures. '
        'Paper and pasteboard carry alpha — thinning them reveals the '
        'planes behind, on screen and in exports alike. The backdrop is '
        'opaque: it is what fades reveal and what empty frames print.',
    'stagePaperSection': 'Paper',
    'stagePasteboardSection': 'Pasteboard',
    'stageBackdropSection': 'Backdrop',
    'stageAlphaLabel': 'Alpha',
    'menuAlphaPreview': 'Alpha preview',
    'inputTitle': 'Input settings',
    'inputTouchScroll': 'Touch scrolls the timeline',
    'inputTouchScrollHelp':
        'ON (default): finger pans scroll the grids — the edit gestures '
        'release touch entirely.\n'
        'OFF: touch edits exactly like the pen (select, move, drag grips) — '
        'the safety net for pens that report as touch.',
    'inputPressureHeading': 'Pen pressure response',
    'inputPressureSoftHard': 'Soft ↔ Hard',
    'inputPressureLinear': 'Linear',
    'inputCanvasHeading': 'Canvas',
    'inputRightClick': 'Right click / pen side button',
    'inputWheelClick': 'Wheel click / pen upper button',
    'inputCanvasTouchHeading': 'Canvas touch',
    'inputDragOneFinger': '1-finger drag',
    'inputDragTwoFingers': '2-finger drag',
    'inputDragThreeFingers': '3-finger drag',
    'inputExtraFinger': 'Extra-finger modifier',
    'inputExtraFingerHelp':
        'A finger added DURING a gesture constrains it — snap '
        'zoom/rotation/size, fine frame steps.',
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
    'prefsSystem': 'System',
    'accentTitle': 'Accent colors',
    'accent1Label': 'Accent 1',
    'accent1Help': 'Selection, playhead, active toggles.',
    'accent2Label': 'Accent 2',
    'accent2AutoLabel': 'Accent 2 follows the complement',
    'accent2AutoHelp':
        'Repeat patterns and selected key diamonds use accent 2.',
    'accent2AutoHint': 'Automatic: the complement of accent 1.',
    'accent2CustomHint': 'Custom accent 2.',
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
    'sheetVisibleBoxes': 'Visible boxes',
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
    'mediaRelink': 'Relink…',
    'mediaRemove': 'Remove',
    'mediaStillLinked': 'Still linked on SE rows — remove its sounds first.',
    'panelCanvas': 'Canvas',
    'panelColor': 'Color',
    'panelMedia': 'Media',
    'panelOnionSkin': 'Onion skin',
    'panelStoryboard': 'Storyboard',
    'panelTimeline': 'Timeline',
    'panelTimesheet': 'Timesheet',
    'panelToolLibrary': 'Tool library',
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
    'autosaveChoose': 'Choose…',
    'autosaveDefault': 'Default',
    'autosaveSidecarFolder': 'Keep sidecars in a separate folder',
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
    'exFilter': 'Filter',
    'exBrowse': 'Browse…',
    'exSavePreset': 'Save preset',
    'exPresetNameEmpty': 'Preset name cannot be empty.',
    'exBaseName': 'Base name',
    'exSuffix': 'Suffix',
    'exDigits': 'Digits',
    'exApplyLayerFx': 'Apply layer FX',
    'exApplyLayerFxHelp': 'Apply layer FX (transforms and animated opacity)',
    'exOnTimesheetOnly': 'On-timesheet layers only',
    'exInstructionLayer': 'Instruction layer',
    'exMuxSeMix': 'Mux the SE mix into the video',
    'exCutFolder': 'Cut folder',
    'exLayerFolder': 'Layer folder',
    'exProjectName': 'Project name',
    'exProject': 'Project',
    'exCut': 'Cut',
    'exFreeAttach': 'Free attach',
    'exSyncAttach': 'Sync attach',
    'exFolderMembers': 'All folder members',
    'exWhite': 'White',
    'exBlack': 'Black',
    'exCameraTemplate': 'Camera {w}×{h}',
    'exLayersTemplate': 'Layers · {name}',
    'toolBrush': 'Brush',
    'toolEraser': 'Eraser',
    'toolEyedropper': 'Eyedropper',
    'toolFill': 'Fill',
    'toolSelect': 'Select',
    'toolMove': 'Move / Transform',
    'toolBrushTip': 'Brush Tool',
    'toolEraserTip': 'Eraser Tool',
    'toolEyedropperTip': 'Eyedropper Tool',
    'toolFillTip': 'Fill Tool',
    'toolSelectTip': 'Select Tool',
    'toolMoveTip': 'Move / Transform Tool',
    'brSize': 'Size',
    'brOpacity': 'Opacity',
    'brFlow': 'Flow',
    'brMixing': 'Mix with ground colour',
    'brPaintAmount': 'Paint amount',
    'brPaintDensity': 'Paint density',
    'brColorStretch': 'Colour stretch',
    'brHardness': 'Hardness',
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
    'brAddTipImage': 'Add a tip from an image',
    'brStabilizer': 'Stabilizer',
    'brBlend': 'Blend',
    'brBlendMode': 'Brush blend mode',
    'brBlendLock': 'Pin this blend mode to the brush',
    'brEditGroup': 'Edit group',
    'brFolderIcon': 'Folder icon',
    'brFolderName': 'Folder name',
    'brFeather': 'Feather',
    'brTolerance': 'Tolerance',
    'brGapClose': 'Gap Close',
    'brGrowShrink': 'Grow/Shrink',
    'brAntiAlias': 'Anti-alias',
    'brAntiAliasEdge': 'Anti-alias edge',
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
    'brExpand': 'Expand',
    'brMeshWarp': 'Mesh Warp',
    'commonReset': 'Reset',
    'commonFill': 'Fill',
    'viewZoomIn': 'Zoom In',
    'viewZoomOut': 'Zoom Out',
    'viewFitToView': 'Fit to View',
    'viewResetView': 'Reset View (100%)',
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
    'tlSections': 'Sections',
    'tlFoldSection': 'Fold section',
    'tlHideSectionLayers': 'Hide section layers',
    'tlShowSectionLayers': 'Show section layers',
    'tlOnlyThisSection': 'Only this section',
    'tlAllDisplayedLayers': 'All displayed layers',
    'tlShowAll': 'Show all',
    'tlHideAll': 'Hide all',
    'tlSoloActiveLayer': 'Solo active layer',
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
    'tlAddLayerHere': 'Add layer here',
    'tlDissolveFolder': 'Dissolve folder',
    'tlRenameFolder': 'Rename folder…',
    'tlRemoveAudio': 'Remove audio',
    'tlLayerMark': 'Layer mark',
    'tlRepeat': 'Repeat',
    'tlRepeatSelection': 'Repeat selection',
    'tlSeNameTemplate': 'SE name {name}',
    'tlAddLayerHeader': 'Add layer',
    'tlSameAsSelected': 'Same as selected',
    'tlKindAnimation': 'Animation',
    'tlKindStoryboard': 'Storyboard',
    'tlKindArt': 'Art',
    'tlKindSe': 'SE',
    'tlKindInstruction': 'Instruction',
    'tlAttachFreeAbove': 'Attach free layer above',
    'tlAttachFreeBelow': 'Attach free layer below',
    'tlAttachSyncedAbove': 'Attach synced layer above',
    'tlAttachSyncedBelow': 'Attach synced layer below',
    'tlLayerCommands': 'Layer commands',
    'tlFrameCommands': 'Frame commands',
    'tlLayer': 'Layer',
    'tlFrame': 'Frame',
    'tlDuplicateLayer': 'Duplicate layer',
    'tlLinkDuplicateLayer': 'Link duplicate layer',
    'tlUnlinkLayer': 'Unlink layer',
    'tlGroupIntoFolder': 'Group into folder',
    'tlRenameLayer': 'Rename layer…',
    'tlCopyLayer': 'Copy layer',
    'tlDeleteLayer': 'Delete layer',
    'tlImportAudio': 'Import audio…',
    'tlCopyFrame': 'Copy frame',
    'tlPasteLinkedFrame': 'Paste linked frame',
    'tlDeleteCell': 'Delete cell',
    'tlEditInstance': 'Edit instance…',
    'tlAdd': 'Add',
    'tlPush': 'Push (open frames)',
    'tlPull': 'Pull (close frames)',
    'sbShorterRows': 'Shorter rows',
    'sbTallerRows': 'Taller rows',
    'sbOneStoryboardRowPerCut':
        'This cut already has a storyboard row. A cut can hold only one.',
    'cnPreviousPage': 'Previous page',
    'cnNextPage': 'Next page',
    'cnActionColumn': 'Action',
    'cnConte': 'Conte',
    'tlBlankX': 'Blank / X',
    'tlMark': 'Mark ●',
    'tlSetCommasN': 'Set N commas…',
    'tlSetCommaTemplate': 'Set {n} comma exposure',
    'tlProjectAudioRate': 'Project audio sample rate',
    'tlCustom': 'Custom…',
    'tlShowSeRows': 'Show SE rows',
    'tlShowCameraRows': 'Show camera rows',
    'tlArtLayer': 'Art layer',
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
    'noticeNothingToTransform': '変形する絵がありません',
    'noticeEditAttachOwner': '親レイヤーを編集してください',
    'commonCancel': 'キャンセル',
    'commonApply': '適用',
    'commonRefresh': '更新',
    'commonClose': '閉じる',
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
    'audioSolo': 'ソロ',
    'audioUnsolo': 'ソロ解除',
    'audioLayerAudioMenu': 'レイヤーオーディオ…',
    'audioClipGainMenu': 'ゲイン…',
    'audioEnvelopeMenu': 'ボリュームエンベロープ…',
    'audioFadesEqualPowerMenu': 'フェード：等パワー（リニアに切替）',
    'audioFadesLinearMenu': 'フェード：リニア（等パワーに切替）',
    'audioClipGainTitle': 'クリップゲイン',
    'audioEnvelopeTitle': 'ボリュームエンベロープ',
    'audioEnvelopeHelp': 'クリップ内コマ位置ごとのゲインキー（キー間は直線、両端は保持）。空＝フラット。',
    'audioEnvelopeFrameLabel': 'コマ',
    'audioEnvelopeGainPercentLabel': 'ゲイン %',
    'audioEnvelopeAddKey': 'キーを追加',
    'fpsAudioTitleTemplate': '{from} → {to}：音はどうしますか？',
    'fpsAudioBody':
        'この2つのレートは実速度が0.1%異なり、音は実時間で存在します — コマ厳密と時間厳密を両立することはできません。\n\n• 音のタイミングを維持：音は実時間を保ち、コマ位置が0.1%ずれます（約42秒ごとに1コマ）。\n\n• 音を0.1%プル：正確なプルダウン比でリサンプルします（聴き取れないピッチ変化 — テレシネの標準コンフォーム）。全ての音がコマ範囲を維持します。',
    'fpsAudioKeep': '音のタイミングを維持',
    'fpsAudioPull': '音を0.1%プル',
    'selectionMoveConfirmTitle': '移動の確定',
    'selectionMoveConfirmBody': '選択範囲の移動を確定しますか？',
    'selectionMoveRevert': '元に戻す',
    'selectionMoveApply': '確定',
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
    'cameraKeyTitleTemplate': 'カメラキー — {frame}フレーム目',
    'cameraKeyLinear': 'リニア',
    'cameraKeyHold': 'ホールド',
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
    'recoverAutosaveTitle': '自動保存の変更を復元しますか？',
    'recoverAutosaveBody':
        'このプロジェクトには、より新しい自動保存があります。それを復元'
        'しますか、それとも最後に保存したファイルを開きますか？',
    'recoverOpenSaved': '保存済みを開く',
    'recoverAction': '復元',
    'closeProjectTitle': 'プロジェクトを閉じますか？',
    'closeProjectBody': '変更は保存されていません。閉じますか？',
    'commonSaveAs': '名前を付けて保存…',
    'unsavedAutosaveTitle': 'プロジェクトを保存',
    'unsavedAutosaveBody':
        'このプロジェクトはまだ一度も保存されていないため、自動保存の書き込み'
        '先がありません。ファイルを選べば、以降は自動保存が守ります。',
    'commonNotNow': '後で',
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
    'menuAction.file-save': '保存',
    'menuAction.file-save-as': '名前を付けて保存…',
    'menuAction.file-project-background': 'プロジェクトの背景…',
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
    'menuAction.layer-rename': 'レイヤー名を変更…',
    'menuAction.layer-copy': 'レイヤーをコピー',
    'menuAction.layer-paste': 'レイヤーを貼り付け',
    'menuAction.layer-delete': 'レイヤーを削除…',
    'menuAction.playback-stop': '停止',
    'menuAction.playback-play-all': '全カットを再生',
    'menuAction.window-reset-layout': 'ワークスペース配置をリセット',
    'menuAction.help-about': 'Anicel について',
    'fileOpenTitle': 'プロジェクトを開く',
    'fileSaveTitle': 'プロジェクトを保存',
    'fileAppDocuments': 'アプリのドキュメント',
    'fileStorageOffNotice':
        'ストレージへのアクセスがオフです — アプリフォルダの外にある'
        'プロジェクトには「すべてのファイル」の権限が必要です。',
    'fileOpenSettings': '設定を開く',
    'fileCheckAgain': '再確認',
    'fileNameLabel': 'ファイル名',
    'fileCloudNoticeOpen':
        'クラウドサービス（Google ドライブ、Dropbox など）：同期アプリ'
        '（Autosync、FolderSync など）を使い、そのミラーフォルダをここで'
        '開いてください — クラウド上のドキュメントを直接扱うことはできません。',
    'fileCloudNoticeSave':
        'クラウドフォルダ：Google ドライブ / Dropbox と連携するには、同期'
        'アプリのミラーフォルダに保存してください。',
    'fileNewFolderAction': '新規フォルダ…',
    'newFolderTitle': '新規フォルダ',
    'newFolderField': 'フォルダ名',
    'newFolderEmpty': 'フォルダ名を空にはできません。',
    'commonCreate': '作成',
    'replaceFileTitle': 'ファイルを置き換えますか？',
    'replaceFileMessageTemplate': '{name} はここに既にあります。',
    'commonReplace': '置き換え',
    'canvasSizeTitle': 'カンバスサイズ',
    'canvasWidthLabel': '幅（px）',
    'canvasHeightLabel': '高さ（px）',
    'canvasAnchorHelpTemplate':
        '基準：既存の絵はここに固定されます。切り取られた線は保持され、'
        'カンバスを広げれば再び現れます。（{min}〜{max} px）',
    'canvasPresetDefault': '既定',
    'commonResize': 'サイズ変更',
    'backgroundTitle': 'プロジェクトの背景',
    'backgroundPaper': '紙（既定）',
    'backgroundWhite': '白',
    'backgroundBlack': '黒',
    'backgroundTransparent': '透明',
    'backgroundCustom': 'カスタム',
    'stagePaperSection': '紙',
    'stagePasteboardSection': 'ペーストボード',
    'stageBackdropSection': '背景',
    'stageAlphaLabel': '不透明度',
    'menuAlphaPreview': 'アルファプレビュー',
    'backgroundHelp':
        'ステージは背景・ペーストボード・紙・絵の4層です。紙とペースト'
        'ボードは不透明度を持ち、薄くすると背後の層が画面でも書き出し'
        'でも透けます。背景は不透明の最終面で、フェードや空きフレーム'
        'が行き着く色です。',
    'inputTitle': '入力設定',
    'inputTouchScroll': 'タッチでタイムラインをスクロール',
    'inputTouchScrollHelp':
        'ON（既定）：指のドラッグでグリッドをスクロールします — 編集'
        'ジェスチャーはタッチを完全に手放します。\n'
        'OFF：タッチがペンとまったく同じに編集します（選択・移動・グリップの'
        'ドラッグ）— タッチとして報告されるペンのための保険です。',
    'inputPressureHeading': '筆圧カーブ',
    'inputPressureSoftHard': '柔らかい ↔ 硬い',
    'inputPressureLinear': 'リニア',
    'inputCanvasHeading': 'カンバス',
    'inputRightClick': '右クリック / ペンのサイドボタン',
    'inputWheelClick': 'ホイールクリック / ペンの上ボタン',
    'inputCanvasTouchHeading': 'カンバスのタッチ',
    'inputDragOneFinger': '1本指ドラッグ',
    'inputDragTwoFingers': '2本指ドラッグ',
    'inputDragThreeFingers': '3本指ドラッグ',
    'inputExtraFinger': '追加指モディファイア',
    'inputExtraFingerHelp':
        'ジェスチャーの途中で指を足すと動作が制限されます — ズーム・回転・'
        'サイズのスナップ、フレームの微送り。',
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
    'prefsSystem': 'システム',
    'accentTitle': 'アクセントカラー',
    'accent1Label': 'アクセント1',
    'accent1Help': '選択・再生ヘッド・オンの状態に使われます。',
    'accent2Label': 'アクセント2',
    'accent2AutoLabel': 'アクセント2を補色に追従',
    'accent2AutoHelp': 'リピート範囲と選択キーのひし形がアクセント2を使います。',
    'accent2AutoHint': '自動：アクセント1の補色。',
    'accent2CustomHint': 'アクセント2を個別指定。',
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
    'sheetVisibleBoxes': '表示する枠',
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
    'shortcutCategory.Navigation': 'ナビゲーション',
    'shortcutCategory.Playback': '再生',
    'shortcutCategory.Edit': '編集',
    'shortcutCategory.Tools': 'ツール',
    'shortcutCategory.Selection': '選択',
    'shortcutCategory.View': '表示',
    'shortcutCategory.Timeline': 'タイムライン',
    'shortcutAction.frame-previous': '前のフレーム',
    'shortcutAction.frame-next': '次のフレーム',
    'shortcutAction.drawing-previous': '前の作画',
    'shortcutAction.drawing-next': '次の作画',
    'shortcutAction.playback-toggle': '再生 / 一時停止',
    'shortcutAction.voice-record-toggle': '音声収録（開始/停止）',
    'shortcutAction.edit-undo': '元に戻す',
    'shortcutAction.edit-redo': 'やり直す',
    'shortcutAction.tool-brush': 'ブラシツール',
    'shortcutAction.tool-eraser': '消しゴムツール',
    'shortcutAction.tool-eyedropper': 'スポイトツール',
    'shortcutAction.tool-fill': '塗りつぶしツール',
    'shortcutAction.tool-select-rect': '長方形選択ツール',
    'shortcutAction.tool-lasso': '投げなわ選択ツール',
    'shortcutAction.tool-move': '移動ツール',
    'shortcutAction.selection-deselect': '選択解除',
    'shortcutAction.selection-nudge-up': '選択 / レイヤーを上へ微調整',
    'shortcutAction.selection-nudge-down': '選択 / レイヤーを下へ微調整',
    'shortcutAction.selection-free-transform': '自由変形',
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
    'mediaRelink': '再リンク…',
    'mediaRemove': '削除',
    'mediaStillLinked': 'SE行でまだ使われています — 先に音を外してください。',
    'panelCanvas': 'カンバス',
    'panelColor': 'カラー',
    'panelMedia': 'メディア',
    'panelOnionSkin': 'オニオンスキン',
    'panelStoryboard': '絵コンテ',
    'panelTimeline': 'タイムライン',
    'panelTimesheet': 'タイムシート',
    'panelToolLibrary': 'ツールライブラリ',
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
    'autosaveChoose': '選択…',
    'autosaveDefault': '既定',
    'autosaveSidecarFolder': 'サイドカーを別フォルダに置く',
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
    'exFilter': 'フィルター',
    'exBrowse': '参照…',
    'exSavePreset': 'プリセットを保存',
    'exPresetNameEmpty': 'プリセット名を空にはできません。',
    'exBaseName': 'ベース名',
    'exSuffix': '接尾辞',
    'exDigits': '桁数',
    'exApplyLayerFx': 'レイヤーFXを適用',
    'exApplyLayerFxHelp': 'レイヤーFXを適用（変形とアニメーション不透明度）',
    'exOnTimesheetOnly': 'シートに載っているレイヤーのみ',
    'exInstructionLayer': '指示レイヤー',
    'exMuxSeMix': 'SEミックスを動画に多重化',
    'exCutFolder': 'カットフォルダ',
    'exLayerFolder': 'レイヤーフォルダ',
    'exProjectName': 'プロジェクト名',
    'exProject': 'プロジェクト',
    'exCut': 'カット',
    'exFreeAttach': 'フリー付属',
    'exSyncAttach': '同期付属',
    'exFolderMembers': 'フォルダ内すべて',
    'exWhite': '白',
    'exBlack': '黒',
    'exCameraTemplate': 'カメラ {w}×{h}',
    'exLayersTemplate': 'レイヤー · {name}',
    'toolBrush': 'ブラシ',
    'toolEraser': '消しゴム',
    'toolEyedropper': 'スポイト',
    'toolFill': '塗りつぶし',
    'toolSelect': '選択',
    'toolMove': '移動 / 変形',
    'toolBrushTip': 'ブラシツール',
    'toolEraserTip': '消しゴムツール',
    'toolEyedropperTip': 'スポイトツール',
    'toolFillTip': '塗りつぶしツール',
    'toolSelectTip': '選択ツール',
    'toolMoveTip': '移動 / 変形ツール',
    'brSize': 'サイズ',
    'brOpacity': '不透明度',
    'brFlow': '流量',
    'brMixing': '下地混色',
    'brPaintAmount': '絵の具量',
    'brPaintDensity': '絵の具濃度',
    'brColorStretch': '色延び',
    'brHardness': '硬さ',
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
    'brAddTipImage': '画像から先端を追加',
    'brStabilizer': '手ブレ補正',
    'brBlend': '合成',
    'brBlendMode': 'ブラシの合成モード',
    'brBlendLock': '合成モードをブラシに固定',
    'brEditGroup': 'グループを編集',
    'brFolderIcon': 'フォルダーのアイコン',
    'brFolderName': 'フォルダー名',
    'brFeather': 'ぼかし',
    'brTolerance': '許容値',
    'brGapClose': '隙間閉じ',
    'brGrowShrink': '拡張 / 収縮',
    'brAntiAlias': 'アンチエイリアス',
    'brAntiAliasEdge': '縁のアンチエイリアス',
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
    'brExpand': '展開',
    'brMeshWarp': 'メッシュワープ',
    'commonReset': 'リセット',
    'commonFill': '塗りつぶし',
    'viewZoomIn': 'ズームイン',
    'viewZoomOut': 'ズームアウト',
    'viewFitToView': '画面に合わせる',
    'viewResetView': '表示をリセット（100%）',
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
    'tlSections': 'セクション',
    'tlFoldSection': 'セクションを折りたたむ',
    'tlHideSectionLayers': 'セクションのレイヤーを隠す',
    'tlShowSectionLayers': 'セクションのレイヤーを表示',
    'tlOnlyThisSection': 'このセクションだけ',
    'tlAllDisplayedLayers': '表示中の全レイヤー',
    'tlShowAll': 'すべて表示',
    'tlHideAll': 'すべて隠す',
    'tlSoloActiveLayer': 'アクティブレイヤーをソロ',
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
    'tlAddLayerHere': 'ここにレイヤーを追加',
    'tlDissolveFolder': 'フォルダを解除',
    'tlRenameFolder': 'フォルダ名を変更…',
    'tlRemoveAudio': '音声を外す',
    'tlLayerMark': 'レイヤーマーク',
    'tlRepeat': 'リピート',
    'tlRepeatSelection': '選択範囲をリピート',
    'tlSeNameTemplate': 'SE名 {name}',
    'tlAddLayerHeader': 'レイヤーを追加',
    'tlSameAsSelected': '選択中と同じ種類',
    'tlKindAnimation': '動画',
    'tlKindStoryboard': '絵コンテ',
    'tlKindArt': '美術',
    'tlKindSe': 'SE',
    'tlKindInstruction': '指示',
    'tlAttachFreeAbove': '上にフリーの付属レイヤー',
    'tlAttachFreeBelow': '下にフリーの付属レイヤー',
    'tlAttachSyncedAbove': '上に同期の付属レイヤー',
    'tlAttachSyncedBelow': '下に同期の付属レイヤー',
    'tlLayerCommands': 'レイヤー操作',
    'tlFrameCommands': 'フレーム操作',
    'tlLayer': 'レイヤー',
    'tlFrame': 'フレーム',
    'tlDuplicateLayer': 'レイヤーを複製',
    'tlLinkDuplicateLayer': 'リンクして複製',
    'tlUnlinkLayer': 'リンクを解除',
    'tlGroupIntoFolder': 'フォルダにまとめる',
    'tlRenameLayer': 'レイヤー名を変更…',
    'tlCopyLayer': 'レイヤーをコピー',
    'tlDeleteLayer': 'レイヤーを削除',
    'tlImportAudio': '音声を読み込み…',
    'tlCopyFrame': 'フレームをコピー',
    'tlPasteLinkedFrame': 'リンクフレームを貼り付け',
    'tlDeleteCell': 'セルを削除',
    'tlEditInstance': 'インスタンスを編集…',
    'tlAdd': '追加',
    'tlPush': '押し出し（コマを開ける）',
    'tlPull': '詰め（コマを詰める）',
    'sbShorterRows': '行を低く',
    'sbTallerRows': '行を高く',
    'sbOneStoryboardRowPerCut': 'このカットには既に絵コンテレイヤーがあります。カットにつき1つだけです。',
    'cnPreviousPage': '前のページ',
    'cnNextPage': '次のページ',
    'cnActionColumn': 'アクション',
    'cnConte': '絵コンテ',
    'tlBlankX': '中割なし / ×',
    'tlMark': 'マーク ●',
    'tlSetCommasN': 'Nコマに設定…',
    'tlSetCommaTemplate': '{n}コマに設定',
    'tlProjectAudioRate': 'プロジェクトの音声サンプルレート',
    'tlCustom': 'カスタム…',
    'tlShowSeRows': 'SE行を表示',
    'tlShowCameraRows': 'カメラ行を表示',
    'tlArtLayer': '美術レイヤー',
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
    'noticeNothingToTransform': '변형할 그림이 없습니다',
    'noticeEditAttachOwner': '주인 레이어를 편집하세요',
    'commonCancel': '취소',
    'commonApply': '적용',
    'commonRefresh': '새로고침',
    'commonClose': '닫기',
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
    'audioSolo': '솔로',
    'audioUnsolo': '솔로 해제',
    'audioLayerAudioMenu': '레이어 오디오…',
    'audioClipGainMenu': '게인…',
    'audioEnvelopeMenu': '볼륨 엔벨로프…',
    'audioFadesEqualPowerMenu': '페이드: 등파워(리니어로 전환)',
    'audioFadesLinearMenu': '페이드: 리니어(등파워로 전환)',
    'audioClipGainTitle': '클립 게인',
    'audioEnvelopeTitle': '볼륨 엔벨로프',
    'audioEnvelopeHelp': '클립 내 프레임 위치별 게인 키(키 사이는 직선, 양 끝은 유지). 비어 있으면 플랫.',
    'audioEnvelopeFrameLabel': '프레임',
    'audioEnvelopeGainPercentLabel': '게인 %',
    'audioEnvelopeAddKey': '키 추가',
    'fpsAudioTitleTemplate': '{from} → {to}: 소리는 어떻게 할까요?',
    'fpsAudioBody':
        '두 레이트는 실제 속도가 0.1% 다르고, 소리는 실시간으로 존재합니다 — 프레임 정확과 시간 정확을 동시에 지킬 수 없습니다.\n\n• 오디오 타이밍 유지: 소리는 실시간을 지키고, 프레임 위치가 0.1% 어긋납니다(약 42초마다 1프레임).\n\n• 오디오 0.1% 당김: 정확한 풀다운 비율로 리샘플합니다(들리지 않는 피치 변화 — 텔레시네 표준 컨폼). 모든 소리가 프레임 범위를 유지합니다.',
    'fpsAudioKeep': '오디오 타이밍 유지',
    'fpsAudioPull': '오디오 0.1% 당김',
    'selectionMoveConfirmTitle': '이동 확정',
    'selectionMoveConfirmBody': '선택 영역 이동을 확정하시겠습니까?',
    'selectionMoveRevert': '되돌리기',
    'selectionMoveApply': '확정',
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
    'cameraKeyTitleTemplate': '카메라 키 — {frame}프레임',
    'cameraKeyLinear': '리니어',
    'cameraKeyHold': '홀드',
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
    'recoverAutosaveTitle': '자동 저장된 변경을 복구할까요?',
    'recoverAutosaveBody':
        '이 프로젝트에 더 최신인 자동 저장이 있습니다. 그것을 복구할까요, '
        '아니면 마지막으로 저장된 파일을 열까요?',
    'recoverOpenSaved': '저장본 열기',
    'recoverAction': '복구',
    'closeProjectTitle': '프로젝트를 닫을까요?',
    'closeProjectBody': '변경 사항이 저장되지 않았습니다. 그래도 닫을까요?',
    'commonSaveAs': '다른 이름으로 저장…',
    'unsavedAutosaveTitle': '프로젝트 저장',
    'unsavedAutosaveBody':
        '이 프로젝트는 한 번도 저장된 적이 없어서 자동 저장이 쓸 곳이 '
        '없습니다. 파일을 지정하면 그때부터 자동 저장이 지켜줍니다.',
    'commonNotNow': '나중에',
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
    'menuAction.file-save': '저장',
    'menuAction.file-save-as': '다른 이름으로 저장…',
    'menuAction.file-project-background': '프로젝트 배경…',
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
    'menuAction.layer-rename': '레이어 이름 변경…',
    'menuAction.layer-copy': '레이어 복사',
    'menuAction.layer-paste': '레이어 붙여넣기',
    'menuAction.layer-delete': '레이어 삭제…',
    'menuAction.playback-stop': '정지',
    'menuAction.playback-play-all': '모든 컷 재생',
    'menuAction.window-reset-layout': '작업공간 배치 초기화',
    'menuAction.help-about': 'Anicel 정보',
    'fileOpenTitle': '프로젝트 열기',
    'fileSaveTitle': '프로젝트 저장',
    'fileAppDocuments': '앱 문서',
    'fileStorageOffNotice':
        '저장소 접근이 꺼져 있습니다 — 앱 폴더 바깥의 프로젝트에는 '
        '모든 파일 권한이 필요합니다.',
    'fileOpenSettings': '설정 열기',
    'fileCheckAgain': '다시 확인',
    'fileNameLabel': '파일 이름',
    'fileCloudNoticeOpen':
        '클라우드 서비스(Google 드라이브, Dropbox 등): 동기화 앱'
        '(Autosync, FolderSync 등)을 쓰고 그 미러 폴더를 여기서 여세요 — '
        '클라우드 문서를 직접 다루는 건 지원하지 않습니다.',
    'fileCloudNoticeSave':
        '클라우드 폴더: Google 드라이브 / Dropbox와 함께 쓰려면 동기화 앱의 '
        '미러 폴더에 저장하세요.',
    'fileNewFolderAction': '새 폴더…',
    'newFolderTitle': '새 폴더',
    'newFolderField': '폴더 이름',
    'newFolderEmpty': '폴더 이름은 비울 수 없습니다.',
    'commonCreate': '만들기',
    'replaceFileTitle': '파일을 바꿀까요?',
    'replaceFileMessageTemplate': '{name}이(가) 여기 이미 있습니다.',
    'commonReplace': '바꾸기',
    'canvasSizeTitle': '캔버스 크기',
    'canvasWidthLabel': '너비 (px)',
    'canvasHeightLabel': '높이 (px)',
    'canvasAnchorHelpTemplate':
        '기준점: 기존 그림이 여기에 고정됩니다. 잘린 획은 보존되며 캔버스를 '
        '다시 넓히면 되살아납니다. ({min}~{max} px)',
    'canvasPresetDefault': '기본',
    'commonResize': '크기 변경',
    'backgroundTitle': '프로젝트 배경',
    'backgroundPaper': '종이 (기본)',
    'backgroundWhite': '흰색',
    'backgroundBlack': '검정',
    'backgroundTransparent': '투명',
    'backgroundCustom': '사용자 지정',
    'stagePaperSection': '종이',
    'stagePasteboardSection': '페이스트보드',
    'stageBackdropSection': '배경',
    'stageAlphaLabel': '불투명도',
    'menuAlphaPreview': '알파 미리보기',
    'backgroundHelp':
        '무대는 배경·페이스트보드·종이·그림의 4층입니다. 종이와 '
        '페이스트보드는 불투명도를 가지며, 낮추면 화면에서도 출력에서도 '
        '뒤 층이 비칩니다. 배경은 불투명한 최종 면으로, 페이드와 빈 '
        '프레임이 도달하는 색입니다.',
    'inputTitle': '입력 설정',
    'inputTouchScroll': '터치로 타임라인 스크롤',
    'inputTouchScrollHelp':
        'ON(기본): 손가락 드래그가 그리드를 스크롤합니다 — 편집 제스처는 '
        '터치를 완전히 놓습니다.\n'
        'OFF: 터치가 펜과 똑같이 편집합니다(선택·이동·그립 드래그) — '
        '터치로 보고되는 펜을 위한 안전장치입니다.',
    'inputPressureHeading': '필압 곡선',
    'inputPressureSoftHard': '부드럽게 ↔ 단단하게',
    'inputPressureLinear': '리니어',
    'inputCanvasHeading': '캔버스',
    'inputRightClick': '우클릭 / 펜 사이드 버튼',
    'inputWheelClick': '휠 클릭 / 펜 위쪽 버튼',
    'inputCanvasTouchHeading': '캔버스 터치',
    'inputDragOneFinger': '한 손가락 드래그',
    'inputDragTwoFingers': '두 손가락 드래그',
    'inputDragThreeFingers': '세 손가락 드래그',
    'inputExtraFinger': '손가락 추가 모디파이어',
    'inputExtraFingerHelp':
        '제스처 도중에 손가락을 더하면 동작이 제한됩니다 — 줌·회전·크기 '
        '스냅, 프레임 미세 이동.',
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
    'prefsSystem': '시스템',
    'accentTitle': '강조 색상',
    'accent1Label': '강조색 1',
    'accent1Help': '선택·플레이헤드·켜진 토글에 쓰입니다.',
    'accent2Label': '강조색 2',
    'accent2AutoLabel': '강조색 2를 보색으로 자동',
    'accent2AutoHelp': '반복 구간과 선택된 키 다이아몬드가 강조색 2를 씁니다.',
    'accent2AutoHint': '자동: 강조색 1의 보색.',
    'accent2CustomHint': '강조색 2 직접 지정.',
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
    'sheetVisibleBoxes': '표시할 칸',
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
    'shortcutCategory.Navigation': '이동',
    'shortcutCategory.Playback': '재생',
    'shortcutCategory.Edit': '편집',
    'shortcutCategory.Tools': '도구',
    'shortcutCategory.Selection': '선택',
    'shortcutCategory.View': '보기',
    'shortcutCategory.Timeline': '타임라인',
    'shortcutAction.frame-previous': '이전 프레임',
    'shortcutAction.frame-next': '다음 프레임',
    'shortcutAction.drawing-previous': '이전 원화',
    'shortcutAction.drawing-next': '다음 원화',
    'shortcutAction.playback-toggle': '재생 / 일시정지',
    'shortcutAction.voice-record-toggle': '음성 녹음 (시작/정지)',
    'shortcutAction.edit-undo': '실행 취소',
    'shortcutAction.edit-redo': '다시 실행',
    'shortcutAction.tool-brush': '브러시 도구',
    'shortcutAction.tool-eraser': '지우개 도구',
    'shortcutAction.tool-eyedropper': '스포이트 도구',
    'shortcutAction.tool-fill': '채우기 도구',
    'shortcutAction.tool-select-rect': '사각형 선택 도구',
    'shortcutAction.tool-lasso': '올가미 선택 도구',
    'shortcutAction.tool-move': '이동 도구',
    'shortcutAction.selection-deselect': '선택 해제',
    'shortcutAction.selection-nudge-up': '선택 / 레이어 위로 미세 이동',
    'shortcutAction.selection-nudge-down': '선택 / 레이어 아래로 미세 이동',
    'shortcutAction.selection-free-transform': '자유 변형',
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
    'mediaRelink': '다시 연결…',
    'mediaRemove': '제거',
    'mediaStillLinked': 'SE 행에서 아직 쓰이고 있습니다 — 소리를 먼저 빼세요.',
    'panelCanvas': '캔버스',
    'panelColor': '색',
    'panelMedia': '미디어',
    'panelOnionSkin': '어니언 스킨',
    'panelStoryboard': '콘티',
    'panelTimeline': '타임라인',
    'panelTimesheet': '타임시트',
    'panelToolLibrary': '도구 라이브러리',
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
    'autosaveChoose': '선택…',
    'autosaveDefault': '기본',
    'autosaveSidecarFolder': '사이드카를 별도 폴더에 보관',
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
    'exFilter': '필터',
    'exBrowse': '찾아보기…',
    'exSavePreset': '프리셋 저장',
    'exPresetNameEmpty': '프리셋 이름은 비울 수 없습니다.',
    'exBaseName': '기본 이름',
    'exSuffix': '접미사',
    'exDigits': '자릿수',
    'exApplyLayerFx': '레이어 FX 적용',
    'exApplyLayerFxHelp': '레이어 FX 적용 (변형과 애니메이션 불투명도)',
    'exOnTimesheetOnly': '시트에 올라간 레이어만',
    'exInstructionLayer': '지시 레이어',
    'exMuxSeMix': 'SE 믹스를 영상에 먹싱',
    'exCutFolder': '컷 폴더',
    'exLayerFolder': '레이어 폴더',
    'exProjectName': '프로젝트 이름',
    'exProject': '프로젝트',
    'exCut': '컷',
    'exFreeAttach': '프리 부속',
    'exSyncAttach': '동기 부속',
    'exFolderMembers': '폴더 전부',
    'exWhite': '흰색',
    'exBlack': '검정',
    'exCameraTemplate': '카메라 {w}×{h}',
    'exLayersTemplate': '레이어 · {name}',
    'toolBrush': '브러시',
    'toolEraser': '지우개',
    'toolEyedropper': '스포이트',
    'toolFill': '채우기',
    'toolSelect': '선택',
    'toolMove': '이동 / 변형',
    'toolBrushTip': '브러시 도구',
    'toolEraserTip': '지우개 도구',
    'toolEyedropperTip': '스포이트 도구',
    'toolFillTip': '채우기 도구',
    'toolSelectTip': '선택 도구',
    'toolMoveTip': '이동 / 변형 도구',
    'brSize': '크기',
    'brOpacity': '불투명도',
    'brFlow': '흐름',
    'brMixing': '밑바탕 혼색',
    'brPaintAmount': '물감량',
    'brPaintDensity': '물감 농도',
    'brColorStretch': '색 늘이기',
    'brHardness': '경도',
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
    'brAddTipImage': '이미지에서 끝 추가',
    'brStabilizer': '손떨림 보정',
    'brBlend': '합성',
    'brBlendMode': '브러시 합성 모드',
    'brBlendLock': '합성 모드를 브러시에 고정',
    'brEditGroup': '그룹 편집',
    'brFolderIcon': '폴더 아이콘',
    'brFolderName': '폴더 이름',
    'brFeather': '페더',
    'brTolerance': '허용치',
    'brGapClose': '틈 메우기',
    'brGrowShrink': '확장 / 축소',
    'brAntiAlias': '앤티에일리어스',
    'brAntiAliasEdge': '가장자리 앤티에일리어스',
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
    'brExpand': '펼치기',
    'brMeshWarp': '메시 워프',
    'commonReset': '초기화',
    'commonFill': '채우기',
    'viewZoomIn': '확대',
    'viewZoomOut': '축소',
    'viewFitToView': '화면에 맞추기',
    'viewResetView': '보기 초기화 (100%)',
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
    'tlSections': '섹션',
    'tlFoldSection': '섹션 접기',
    'tlHideSectionLayers': '섹션 레이어 숨기기',
    'tlShowSectionLayers': '섹션 레이어 표시',
    'tlOnlyThisSection': '이 섹션만',
    'tlAllDisplayedLayers': '표시 중인 모든 레이어',
    'tlShowAll': '모두 표시',
    'tlHideAll': '모두 숨기기',
    'tlSoloActiveLayer': '활성 레이어 솔로',
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
    'tlAddLayerHere': '여기에 레이어 추가',
    'tlDissolveFolder': '폴더 해제',
    'tlRenameFolder': '폴더 이름 변경…',
    'tlRemoveAudio': '오디오 제거',
    'tlLayerMark': '레이어 마크',
    'tlRepeat': '반복',
    'tlRepeatSelection': '선택 영역 반복',
    'tlSeNameTemplate': 'SE 이름 {name}',
    'tlAddLayerHeader': '레이어 추가',
    'tlSameAsSelected': '선택한 것과 같은 종류',
    'tlKindAnimation': '동화',
    'tlKindStoryboard': '콘티',
    'tlKindArt': '미술',
    'tlKindSe': 'SE',
    'tlKindInstruction': '지시',
    'tlAttachFreeAbove': '위에 프리 부속 레이어',
    'tlAttachFreeBelow': '아래에 프리 부속 레이어',
    'tlAttachSyncedAbove': '위에 동기 부속 레이어',
    'tlAttachSyncedBelow': '아래에 동기 부속 레이어',
    'tlLayerCommands': '레이어 명령',
    'tlFrameCommands': '프레임 명령',
    'tlLayer': '레이어',
    'tlFrame': '프레임',
    'tlDuplicateLayer': '레이어 복제',
    'tlLinkDuplicateLayer': '링크해서 복제',
    'tlUnlinkLayer': '링크 해제',
    'tlGroupIntoFolder': '폴더로 묶기',
    'tlRenameLayer': '레이어 이름 변경…',
    'tlCopyLayer': '레이어 복사',
    'tlDeleteLayer': '레이어 삭제',
    'tlImportAudio': '오디오 불러오기…',
    'tlCopyFrame': '프레임 복사',
    'tlPasteLinkedFrame': '링크 프레임 붙여넣기',
    'tlDeleteCell': '셀 삭제',
    'tlEditInstance': '인스턴스 편집…',
    'tlAdd': '추가',
    'tlPush': '밀기(칸 열기)',
    'tlPull': '당기기(칸 닫기)',
    'sbShorterRows': '행 낮게',
    'sbTallerRows': '행 높게',
    'sbOneStoryboardRowPerCut': '이 컷에는 이미 스토리보드 레이어가 있습니다. 컷당 하나만 가능합니다.',
    'cnPreviousPage': '이전 페이지',
    'cnNextPage': '다음 페이지',
    'cnActionColumn': '액션',
    'cnConte': '콘티',
    'tlBlankX': '중간 없음 / ×',
    'tlMark': '마크 ●',
    'tlSetCommasN': 'N코마로 설정…',
    'tlSetCommaTemplate': '{n}코마로 설정',
    'tlProjectAudioRate': '프로젝트 오디오 샘플레이트',
    'tlCustom': '사용자 지정…',
    'tlShowSeRows': 'SE 행 표시',
    'tlShowCameraRows': '카메라 행 표시',
    'tlArtLayer': '미술 레이어',
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
    'noticeNothingToTransform': 'Rien a transformer',
    'noticeEditAttachOwner': 'Modifiez le calque parent',
    'commonCancel': 'Annuler',
    'commonApply': 'Appliquer',
    'commonRefresh': 'Actualiser',
    'commonClose': 'Fermer',
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
    'audioSolo': 'Solo',
    'audioUnsolo': 'Retirer le solo',
    'audioLayerAudioMenu': 'Audio du calque…',
    'audioClipGainMenu': 'Gain…',
    'audioEnvelopeMenu': 'Enveloppe de volume…',
    'audioFadesEqualPowerMenu':
        'Fondus : puissance constante (passer en linéaire)',
    'audioFadesLinearMenu': 'Fondus : linéaire (passer en puissance constante)',
    'audioClipGainTitle': 'Gain du clip',
    'audioEnvelopeTitle': 'Enveloppe de volume',
    'audioEnvelopeHelp':
        'Clés de gain aux images du clip (linéaire entre les clés, maintenu aux extrémités). Vide = plat.',
    'audioEnvelopeFrameLabel': 'image',
    'audioEnvelopeGainPercentLabel': 'gain %',
    'audioEnvelopeAddKey': 'Ajouter une clé',
    'fpsAudioTitleTemplate': '{from} → {to} : que faire du son ?',
    'fpsAudioBody':
        'Ces deux cadences diffèrent de 0,1 % en vitesse réelle, et le son existe en secondes réelles — il ne peut pas rester à la fois exact à l\'image et exact au temps.\n\n• Garder le timing audio : les sons gardent leurs secondes réelles ; leurs positions d\'image dérivent de 0,1 % (environ une image toutes les 42 secondes).\n\n• Tirer l\'audio de 0,1 % : les sons sont rééchantillonnés au rapport de pulldown exact (variation de hauteur inaudible — la conformation télécinéma standard) et chaque son garde sa plage d\'images exacte.',
    'fpsAudioKeep': 'Garder le timing audio',
    'fpsAudioPull': 'Tirer l\'audio de 0,1 %',
    'selectionMoveConfirmTitle': 'Valider le déplacement',
    'selectionMoveConfirmBody': 'Valider le déplacement de la sélection ?',
    'selectionMoveRevert': 'Rétablir',
    'selectionMoveApply': 'Valider',
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
    'cutNoteTitle': 'Modifier la note du plan',
    'cutNoteField': 'Note du plan',
    'deleteLayerTitle': 'Supprimer le calque',
    'deleteLayerMessageTemplate': 'Supprimer le calque « {name} » ?',
    'frameNameConflictTitle': "Ce nom d'image existe déjà",
    'frameNameConflictBody':
        "Ce nom est déjà utilisé par une autre image de ce calque. Lier à "
        "l'image existante pour que le même nom partage le même dessin ?",
    'seInstanceNewTitle': 'Nouveau SE',
    'seInstanceEditTitle': 'Modifier le SE',
    'seNameLabel': 'Nom (locuteur — vide masque le cadre)',
    'seDialogueLabel': 'Dialogue',
    'cameraKeyTitleTemplate': 'Clés caméra — image {frame}',
    'cameraKeyLinear': 'Linéaire',
    'cameraKeyHold': 'Maintien',
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
    'recoverAutosaveTitle': 'Récupérer les modifications enregistrées ?',
    'recoverAutosaveBody':
        'Une sauvegarde automatique plus récente existe pour ce projet. La '
        'récupérer, ou ouvrir le fichier tel quel ?',
    'recoverOpenSaved': 'Ouvrir la version enregistrée',
    'recoverAction': 'Récupérer',
    'closeProjectTitle': 'Fermer le projet ?',
    'closeProjectBody':
        'Vos modifications ne sont pas enregistrées. Fermer quand même ?',
    'commonSaveAs': 'Enregistrer sous…',
    'unsavedAutosaveTitle': 'Enregistrez votre projet',
    'unsavedAutosaveBody':
        "Ce projet n'a jamais été enregistré : la sauvegarde automatique "
        "n'a nulle part où écrire. Choisissez un fichier et elle le "
        'protégera ensuite.',
    'commonNotNow': 'Plus tard',
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
    'menuAction.file-save': 'Enregistrer',
    'menuAction.file-save-as': 'Enregistrer sous…',
    'menuAction.file-project-background': 'Arrière-plan du projet…',
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
    'menuAction.layer-rename': 'Renommer le calque…',
    'menuAction.layer-copy': 'Copier le calque',
    'menuAction.layer-paste': 'Coller le calque',
    'menuAction.layer-delete': 'Supprimer le calque…',
    'menuAction.playback-stop': 'Arrêter',
    'menuAction.playback-play-all': 'Lire tous les plans',
    'menuAction.window-reset-layout': "Réinitialiser l'espace de travail",
    'menuAction.help-about': 'À propos de Anicel',
    'fileOpenTitle': 'Ouvrir un projet',
    'fileSaveTitle': 'Enregistrer le projet',
    'fileAppDocuments': "Documents de l'app",
    'fileStorageOffNotice':
        "L'accès au stockage est désactivé — les projets hors du dossier de "
        "l'application exigent l'autorisation Tous les fichiers.",
    'fileOpenSettings': 'Ouvrir les réglages',
    'fileCheckAgain': 'Vérifier à nouveau',
    'fileNameLabel': 'Nom du fichier',
    'fileCloudNoticeOpen':
        'Services cloud (Google Drive, Dropbox …) : utilisez une app de '
        'synchronisation (Autosync, FolderSync …) et ouvrez son dossier '
        'miroir ici — les documents cloud directs ne sont pas pris en charge.',
    'fileCloudNoticeSave':
        "Dossiers cloud : enregistrez dans le dossier miroir d'une app de "
        'synchronisation pour travailler avec Google Drive / Dropbox.',
    'fileNewFolderAction': 'Nouveau dossier…',
    'newFolderTitle': 'Nouveau dossier',
    'newFolderField': 'Nom du dossier',
    'newFolderEmpty': 'Le nom du dossier ne peut pas être vide.',
    'commonCreate': 'Créer',
    'replaceFileTitle': 'Remplacer le fichier ?',
    'replaceFileMessageTemplate': '{name} existe déjà ici.',
    'commonReplace': 'Remplacer',
    'canvasSizeTitle': 'Taille du canevas',
    'canvasWidthLabel': 'Largeur (px)',
    'canvasHeightLabel': 'Hauteur (px)',
    'canvasAnchorHelpTemplate':
        "Ancrage : le dessin existant reste fixé ici. Les traits rognés sont "
        'conservés et réapparaissent si le canevas est agrandi. '
        '({min}–{max} px)',
    'canvasPresetDefault': 'Par défaut',
    'commonResize': 'Redimensionner',
    'backgroundTitle': 'Arrière-plan du projet',
    'backgroundPaper': 'Papier (par défaut)',
    'backgroundWhite': 'Blanc',
    'backgroundBlack': 'Noir',
    'backgroundTransparent': 'Transparent',
    'backgroundCustom': 'Personnalisé',
    'stagePaperSection': 'Papier',
    'stagePasteboardSection': 'Table de montage',
    'stageBackdropSection': 'Fond',
    'stageAlphaLabel': 'Alpha',
    'menuAlphaPreview': 'Aperçu alpha',
    'backgroundHelp':
        'La scène a quatre plans : fond, table de montage, papier, images. '
        'Le papier et la table portent un alpha — les amincir révèle les '
        "plans derrière, à l'écran comme à l'export. Le fond est opaque : "
        "c'est ce que révèlent les fondus et ce qu'impriment les images "
        'vides.',
    'inputTitle': 'Paramètres de saisie',
    'inputTouchScroll': 'Le toucher fait défiler la timeline',
    'inputTouchScrollHelp':
        'ACTIVÉ (par défaut) : le glissement au doigt fait défiler les '
        'grilles — les gestes d\'édition relâchent entièrement le toucher.\n'
        'DÉSACTIVÉ : le toucher édite exactement comme le stylet '
        '(sélection, déplacement, poignées) — le filet de sécurité pour les '
        'stylets vus comme du toucher.',
    'inputPressureHeading': 'Réponse à la pression',
    'inputPressureSoftHard': 'Doux ↔ Dur',
    'inputPressureLinear': 'Linéaire',
    'inputCanvasHeading': 'Canevas',
    'inputRightClick': 'Clic droit / bouton latéral du stylet',
    'inputWheelClick': 'Clic molette / bouton supérieur du stylet',
    'inputCanvasTouchHeading': 'Toucher sur le canevas',
    'inputDragOneFinger': 'Glissement à 1 doigt',
    'inputDragTwoFingers': 'Glissement à 2 doigts',
    'inputDragThreeFingers': 'Glissement à 3 doigts',
    'inputExtraFinger': 'Modificateur au doigt supplémentaire',
    'inputExtraFingerHelp':
        'Un doigt ajouté PENDANT un geste le contraint — zoom, rotation et '
        'taille par crans, avance image par image fine.',
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
    'accentTitle': "Couleurs d'accent",
    'accent1Label': 'Accent 1',
    'accent1Help': 'Sélection, tête de lecture, bascules actives.',
    'accent2Label': 'Accent 2',
    'accent2AutoLabel': "L'accent 2 suit la couleur complémentaire",
    'accent2AutoHelp':
        'Les motifs répétés et les losanges de clés sélectionnées utilisent '
        "l'accent 2.",
    'accent2AutoHint': "Automatique : le complément de l'accent 1.",
    'accent2CustomHint': 'Accent 2 personnalisé.',
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
    'sheetVisibleBoxes': 'Cases visibles',
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
    'shortcutCategory.Navigation': 'Navigation',
    'shortcutCategory.Playback': 'Lecture',
    'shortcutCategory.Edit': 'Édition',
    'shortcutCategory.Tools': 'Outils',
    'shortcutCategory.Selection': 'Sélection',
    'shortcutCategory.View': 'Affichage',
    'shortcutCategory.Timeline': 'Timeline',
    'shortcutAction.frame-previous': 'Image précédente',
    'shortcutAction.frame-next': 'Image suivante',
    'shortcutAction.drawing-previous': 'Dessin précédent',
    'shortcutAction.drawing-next': 'Dessin suivant',
    'shortcutAction.playback-toggle': 'Lecture / Pause',
    'shortcutAction.voice-record-toggle':
        'Enregistrer la voix (démarrer/arrêter)',
    'shortcutAction.edit-undo': 'Annuler',
    'shortcutAction.edit-redo': 'Rétablir',
    'shortcutAction.tool-brush': 'Outil pinceau',
    'shortcutAction.tool-eraser': 'Outil gomme',
    'shortcutAction.tool-eyedropper': 'Outil pipette',
    'shortcutAction.tool-fill': 'Outil remplissage',
    'shortcutAction.tool-select-rect': 'Outil sélection rectangle',
    'shortcutAction.tool-lasso': 'Outil lasso',
    'shortcutAction.tool-move': 'Outil déplacement',
    'shortcutAction.selection-deselect': 'Désélectionner',
    'shortcutAction.selection-nudge-up':
        'Décaler la sélection / le calque vers le haut',
    'shortcutAction.selection-nudge-down':
        'Décaler la sélection / le calque vers le bas',
    'shortcutAction.selection-free-transform': 'Transformation libre',
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
    'mediaRelink': 'Relier…',
    'mediaRemove': 'Retirer',
    'mediaStillLinked':
        "Encore lié sur des lignes SE — retirez d'abord ses sons.",
    'panelCanvas': 'Canevas',
    'panelColor': 'Couleur',
    'panelMedia': 'Médias',
    'panelOnionSkin': "Pelure d'oignon",
    'panelStoryboard': 'Storyboard',
    'panelTimeline': 'Timeline',
    'panelTimesheet': 'Feuille de temps',
    'panelToolLibrary': "Bibliothèque d'outils",
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
    'autosaveChoose': 'Choisir…',
    'autosaveDefault': 'Par défaut',
    'autosaveSidecarFolder':
        'Garder les fichiers annexes dans un dossier séparé',
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
    'exFilter': 'Filtre',
    'exBrowse': 'Parcourir…',
    'exSavePreset': 'Enregistrer le préréglage',
    'exPresetNameEmpty': 'Le nom du préréglage ne peut pas être vide.',
    'exBaseName': 'Nom de base',
    'exSuffix': 'Suffixe',
    'exDigits': 'Chiffres',
    'exApplyLayerFx': 'Appliquer les FX de calque',
    'exApplyLayerFxHelp':
        'Appliquer les FX de calque (transformations et opacité animée)',
    'exOnTimesheetOnly': 'Uniquement les calques sur la feuille',
    'exInstructionLayer': "Calque d'indications",
    'exMuxSeMix': 'Intégrer le mixage SE dans la vidéo',
    'exCutFolder': 'Dossier du plan',
    'exLayerFolder': 'Dossier du calque',
    'exProjectName': 'Nom du projet',
    'exProject': 'Projet',
    'exCut': 'Plan',
    'exFreeAttach': 'Attache libre',
    'exSyncAttach': 'Attache synchronisée',
    'exFolderMembers': 'Tout le dossier',
    'exWhite': 'Blanc',
    'exBlack': 'Noir',
    'exCameraTemplate': 'Caméra {w}×{h}',
    'exLayersTemplate': 'Calques · {name}',
    'toolBrush': 'Pinceau',
    'toolEraser': 'Gomme',
    'toolEyedropper': 'Pipette',
    'toolFill': 'Remplissage',
    'toolSelect': 'Sélection',
    'toolMove': 'Déplacer / Transformer',
    'toolBrushTip': 'Outil pinceau',
    'toolEraserTip': 'Outil gomme',
    'toolEyedropperTip': 'Outil pipette',
    'toolFillTip': 'Outil remplissage',
    'toolSelectTip': 'Outil sélection',
    'toolMoveTip': 'Outil déplacer / transformer',
    'brSize': 'Taille',
    'brOpacity': 'Opacité',
    'brFlow': 'Débit',
    'brMixing': 'Mélanger au fond',
    'brPaintAmount': 'Quantité de peinture',
    'brPaintDensity': 'Densité de peinture',
    'brColorStretch': 'Étirement de la couleur',
    'brHardness': 'Dureté',
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
    'brStabilizer': 'Stabilisateur',
    'brBlend': 'Fusion',
    'brBlendMode': 'Mode de fusion du pinceau',
    'brBlendLock': 'Épingler ce mode de fusion au pinceau',
    'brEditGroup': 'Modifier le groupe',
    'brFolderIcon': 'Icône du dossier',
    'brFolderName': 'Nom du dossier',
    'brFeather': 'Contour progressif',
    'brTolerance': 'Tolérance',
    'brGapClose': 'Fermeture des trous',
    'brGrowShrink': 'Étendre / Réduire',
    'brAntiAlias': 'Anticrénelage',
    'brAntiAliasEdge': 'Anticrénelage du bord',
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
    'brExpand': 'Déplier',
    'brMeshWarp': 'Déformation par grille',
    'commonReset': 'Réinitialiser',
    'commonFill': 'Remplir',
    'viewZoomIn': 'Zoom avant',
    'viewZoomOut': 'Zoom arrière',
    'viewFitToView': 'Ajuster à la fenêtre',
    'viewResetView': 'Réinitialiser la vue (100 %)',
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
    'tlSections': 'Sections',
    'tlFoldSection': 'Replier la section',
    'tlHideSectionLayers': 'Masquer les calques de la section',
    'tlShowSectionLayers': 'Afficher les calques de la section',
    'tlOnlyThisSection': 'Cette section uniquement',
    'tlAllDisplayedLayers': 'Tous les calques affichés',
    'tlShowAll': 'Tout afficher',
    'tlHideAll': 'Tout masquer',
    'tlSoloActiveLayer': 'Solo du calque actif',
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
    'tlAddLayerHere': 'Ajouter un calque ici',
    'tlDissolveFolder': 'Dissoudre le dossier',
    'tlRenameFolder': 'Renommer le dossier…',
    'tlRemoveAudio': "Retirer l'audio",
    'tlLayerMark': 'Repère de calque',
    'tlRepeat': 'Répéter',
    'tlRepeatSelection': 'Répéter la sélection',
    'tlSeNameTemplate': 'Nom SE {name}',
    'tlAddLayerHeader': 'Ajouter un calque',
    'tlSameAsSelected': 'Comme la sélection',
    'tlKindAnimation': 'Animation',
    'tlKindStoryboard': 'Storyboard',
    'tlKindArt': 'Décor',
    'tlKindSe': 'SE',
    'tlKindInstruction': 'Indication',
    'tlAttachFreeAbove': 'Calque attaché libre au-dessus',
    'tlAttachFreeBelow': 'Calque attaché libre en dessous',
    'tlAttachSyncedAbove': 'Calque attaché synchronisé au-dessus',
    'tlAttachSyncedBelow': 'Calque attaché synchronisé en dessous',
    'tlLayerCommands': 'Commandes de calque',
    'tlFrameCommands': "Commandes d'image",
    'tlLayer': 'Calque',
    'tlFrame': 'Image',
    'tlDuplicateLayer': 'Dupliquer le calque',
    'tlLinkDuplicateLayer': 'Dupliquer en liant',
    'tlUnlinkLayer': 'Délier le calque',
    'tlGroupIntoFolder': 'Grouper dans un dossier',
    'tlRenameLayer': 'Renommer le calque…',
    'tlCopyLayer': 'Copier le calque',
    'tlDeleteLayer': 'Supprimer le calque',
    'tlImportAudio': "Importer de l'audio…",
    'tlCopyFrame': "Copier l'image",
    'tlPasteLinkedFrame': "Coller l'image liée",
    'tlDeleteCell': 'Supprimer la case',
    'tlEditInstance': "Modifier l'instance…",
    'tlAdd': 'Ajouter',
    'tlPush': 'Pousser (ouvrir des images)',
    'tlPull': 'Tirer (fermer des images)',
    'sbShorterRows': 'Lignes plus basses',
    'sbTallerRows': 'Lignes plus hautes',
    'sbOneStoryboardRowPerCut':
        'Ce plan a déjà un calque storyboard. Un seul par plan.',
    'cnPreviousPage': 'Page précédente',
    'cnNextPage': 'Page suivante',
    'cnActionColumn': 'Action',
    'cnConte': 'Storyboard',
    'tlBlankX': 'Vide / X',
    'tlMark': 'Repère ●',
    'tlSetCommasN': 'Régler sur N commas…',
    'tlSetCommaTemplate': 'Régler sur {n} comma',
    'tlProjectAudioRate': "Fréquence d'échantillonnage du projet",
    'tlCustom': 'Personnalisé…',
    'tlShowSeRows': 'Afficher les lignes SE',
    'tlShowCameraRows': 'Afficher les lignes caméra',
    'tlArtLayer': 'Calque décor',
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
    'noticeNothingToTransform': '没有可变形的内容',
    'noticeEditAttachOwner': '请编辑父图层',
    'commonCancel': '取消',
    'commonApply': '应用',
    'commonRefresh': '刷新',
    'commonClose': '关闭',
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
    'audioSolo': '独奏',
    'audioUnsolo': '取消独奏',
    'audioLayerAudioMenu': '图层音频…',
    'audioClipGainMenu': '增益…',
    'audioEnvelopeMenu': '音量包络…',
    'audioFadesEqualPowerMenu': '淡变：等功率（切换为线性）',
    'audioFadesLinearMenu': '淡变：线性（切换为等功率）',
    'audioClipGainTitle': '片段增益',
    'audioEnvelopeTitle': '音量包络',
    'audioEnvelopeHelp': '按片段内帧位置设置增益关键点（关键点之间线性，两端保持）。留空＝平直。',
    'audioEnvelopeFrameLabel': '帧',
    'audioEnvelopeGainPercentLabel': '增益 %',
    'audioEnvelopeAddKey': '添加关键点',
    'fpsAudioTitleTemplate': '{from} → {to}：声音怎么办？',
    'fpsAudioBody':
        '这两个帧率的实际速度相差 0.1%，而声音存在于真实时间中 — 无法同时保持帧精确与时间精确。\n\n• 保持音频时间：声音保持真实秒数；帧位置漂移 0.1%（约每 42 秒一帧）。\n\n• 拉伸音频 0.1%：按精确的 pulldown 比例重采样（听不出的音高变化 — 电视电影的标准做法），每个声音保持其精确的帧范围。',
    'fpsAudioKeep': '保持音频时间',
    'fpsAudioPull': '拉伸音频 0.1%',
    'selectionMoveConfirmTitle': '确认移动',
    'selectionMoveConfirmBody': '要确认选区的移动吗？',
    'selectionMoveRevert': '还原',
    'selectionMoveApply': '确认',
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
    'cameraKeyTitleTemplate': '摄影表关键帧 — 第 {frame} 帧',
    'cameraKeyLinear': '线性',
    'cameraKeyHold': '保持',
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
    'recoverAutosaveTitle': '要恢复自动保存的更改吗？',
    'recoverAutosaveBody': '此项目存在更新的自动保存。是恢复它，还是打开上次保存的文件？',
    'recoverOpenSaved': '打开已保存版本',
    'recoverAction': '恢复',
    'closeProjectTitle': '关闭项目？',
    'closeProjectBody': '你的更改尚未保存。仍要关闭吗？',
    'commonSaveAs': '另存为…',
    'unsavedAutosaveTitle': '保存你的项目',
    'unsavedAutosaveBody':
        '此项目从未保存过，自动保存没有可写入的位置。选择一个文件后，'
        '自动保存就会开始守护它。',
    'commonNotNow': '暂不',
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
    'menuAction.file-save': '保存',
    'menuAction.file-save-as': '另存为…',
    'menuAction.file-project-background': '项目背景…',
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
    'menuAction.layer-rename': '重命名图层…',
    'menuAction.layer-copy': '复制图层',
    'menuAction.layer-paste': '粘贴图层',
    'menuAction.layer-delete': '删除图层…',
    'menuAction.playback-stop': '停止',
    'menuAction.playback-play-all': '播放所有镜头',
    'menuAction.window-reset-layout': '重置工作区布局',
    'menuAction.help-about': '关于 Anicel',
    'fileOpenTitle': '打开项目',
    'fileSaveTitle': '保存项目',
    'fileAppDocuments': '应用文档',
    'fileStorageOffNotice': '存储访问已关闭 — 应用文件夹之外的项目需要"所有文件"权限。',
    'fileOpenSettings': '打开设置',
    'fileCheckAgain': '重新检查',
    'fileNameLabel': '文件名',
    'fileCloudNoticeOpen':
        '云服务（Google 云端硬盘、Dropbox 等）：请使用同步应用'
        '（Autosync、FolderSync 等），并在此打开它的镜像文件夹 — '
        '不支持直接打开云端文档。',
    'fileCloudNoticeSave': '云文件夹：保存到同步应用的镜像文件夹，即可配合 Google 云端硬盘 / Dropbox 使用。',
    'fileNewFolderAction': '新建文件夹…',
    'newFolderTitle': '新建文件夹',
    'newFolderField': '文件夹名称',
    'newFolderEmpty': '文件夹名称不能为空。',
    'commonCreate': '创建',
    'replaceFileTitle': '替换文件？',
    'replaceFileMessageTemplate': '{name} 已存在于此处。',
    'commonReplace': '替换',
    'canvasSizeTitle': '画布尺寸',
    'canvasWidthLabel': '宽度（px）',
    'canvasHeightLabel': '高度（px）',
    'canvasAnchorHelpTemplate':
        '锚点：已有画面固定在此处。被裁掉的笔画会保留，画布再放大时会重新出现。'
        '（{min}–{max} px）',
    'canvasPresetDefault': '默认',
    'commonResize': '调整尺寸',
    'backgroundTitle': '项目背景',
    'backgroundPaper': '纸（默认）',
    'backgroundWhite': '白色',
    'backgroundBlack': '黑色',
    'backgroundTransparent': '透明',
    'backgroundCustom': '自定义',
    'stagePaperSection': '纸',
    'stagePasteboardSection': '粘贴板',
    'stageBackdropSection': '背景',
    'stageAlphaLabel': '不透明度',
    'menuAlphaPreview': '透明度预览',
    'backgroundHelp':
        '舞台由四层组成：背景、粘贴板、纸、图画。纸和粘贴板带有透明度 — '
        '调低后，屏幕和导出都会透出后面的层。背景是不透明的最终面：'
        '淡出与空帧最终落在这个颜色上。',
    'inputTitle': '输入设置',
    'inputTouchScroll': '触摸滚动时间轴',
    'inputTouchScrollHelp':
        '开启（默认）：手指拖动滚动网格 — 编辑手势完全放开触摸。\n'
        '关闭：触摸与笔完全一样地编辑（选择、移动、拖动手柄）— '
        '这是为被识别成触摸的笔准备的保险。',
    'inputPressureHeading': '压感曲线',
    'inputPressureSoftHard': '软 ↔ 硬',
    'inputPressureLinear': '线性',
    'inputCanvasHeading': '画布',
    'inputRightClick': '右键 / 笔侧键',
    'inputWheelClick': '滚轮点击 / 笔上键',
    'inputCanvasTouchHeading': '画布触摸',
    'inputDragOneFinger': '单指拖动',
    'inputDragTwoFingers': '双指拖动',
    'inputDragThreeFingers': '三指拖动',
    'inputExtraFinger': '加指修饰键',
    'inputExtraFingerHelp': '手势进行中再加一根手指会约束它 — 缩放/旋转/笔刷大小吸附，逐帧微调。',
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
    'accentTitle': '强调色',
    'accent1Label': '强调色 1',
    'accent1Help': '用于选区、播放头和已启用的开关。',
    'accent2Label': '强调色 2',
    'accent2AutoLabel': '强调色 2 跟随补色',
    'accent2AutoHelp': '重复区间与选中的关键帧菱形使用强调色 2。',
    'accent2AutoHint': '自动：强调色 1 的补色。',
    'accent2CustomHint': '自定义强调色 2。',
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
    'sheetVisibleBoxes': '显示的栏位',
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
    'shortcutCategory.Navigation': '导航',
    'shortcutCategory.Playback': '播放',
    'shortcutCategory.Edit': '编辑',
    'shortcutCategory.Tools': '工具',
    'shortcutCategory.Selection': '选区',
    'shortcutCategory.View': '视图',
    'shortcutCategory.Timeline': '时间轴',
    'shortcutAction.frame-previous': '上一帧',
    'shortcutAction.frame-next': '下一帧',
    'shortcutAction.drawing-previous': '上一张原画',
    'shortcutAction.drawing-next': '下一张原画',
    'shortcutAction.playback-toggle': '播放 / 暂停',
    'shortcutAction.voice-record-toggle': '录音（开始/停止）',
    'shortcutAction.edit-undo': '撤销',
    'shortcutAction.edit-redo': '重做',
    'shortcutAction.tool-brush': '画笔工具',
    'shortcutAction.tool-eraser': '橡皮工具',
    'shortcutAction.tool-eyedropper': '吸管工具',
    'shortcutAction.tool-fill': '填充工具',
    'shortcutAction.tool-select-rect': '矩形选择工具',
    'shortcutAction.tool-lasso': '套索选择工具',
    'shortcutAction.tool-move': '移动工具',
    'shortcutAction.selection-deselect': '取消选择',
    'shortcutAction.selection-nudge-up': '选区 / 图层上移微调',
    'shortcutAction.selection-nudge-down': '选区 / 图层下移微调',
    'shortcutAction.selection-free-transform': '自由变换',
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
    'mediaRelink': '重新链接…',
    'mediaRemove': '移除',
    'mediaStillLinked': 'SE 行仍在使用 — 请先移除它的声音。',
    'panelCanvas': '画布',
    'panelColor': '颜色',
    'panelMedia': '媒体',
    'panelOnionSkin': '洋葱皮',
    'panelStoryboard': '分镜',
    'panelTimeline': '时间轴',
    'panelTimesheet': '摄影表',
    'panelToolLibrary': '工具库',
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
    'autosaveChoose': '选择…',
    'autosaveDefault': '默认',
    'autosaveSidecarFolder': '将附属文件放在单独文件夹',
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
    'exFilter': '滤镜',
    'exBrowse': '浏览…',
    'exSavePreset': '保存预设',
    'exPresetNameEmpty': '预设名称不能为空。',
    'exBaseName': '基础名称',
    'exSuffix': '后缀',
    'exDigits': '位数',
    'exApplyLayerFx': '应用图层 FX',
    'exApplyLayerFxHelp': '应用图层 FX（变换与动画不透明度）',
    'exOnTimesheetOnly': '仅摄影表上的图层',
    'exInstructionLayer': '指示图层',
    'exMuxSeMix': '将 SE 混音封装进视频',
    'exCutFolder': '镜头文件夹',
    'exLayerFolder': '图层文件夹',
    'exProjectName': '项目名称',
    'exProject': '项目',
    'exCut': '镜头',
    'exFreeAttach': '自由附属',
    'exSyncAttach': '同步附属',
    'exFolderMembers': '整个文件夹',
    'exWhite': '白色',
    'exBlack': '黑色',
    'exCameraTemplate': '摄影机 {w}×{h}',
    'exLayersTemplate': '图层 · {name}',
    'toolBrush': '画笔',
    'toolEraser': '橡皮',
    'toolEyedropper': '吸管',
    'toolFill': '填充',
    'toolSelect': '选择',
    'toolMove': '移动 / 变换',
    'toolBrushTip': '画笔工具',
    'toolEraserTip': '橡皮工具',
    'toolEyedropperTip': '吸管工具',
    'toolFillTip': '填充工具',
    'toolSelectTip': '选择工具',
    'toolMoveTip': '移动 / 变换工具',
    'brSize': '大小',
    'brOpacity': '不透明度',
    'brFlow': '流量',
    'brMixing': '与底色混合',
    'brPaintAmount': '颜料量',
    'brPaintDensity': '颜料浓度',
    'brColorStretch': '色彩延伸',
    'brHardness': '硬度',
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
    'brStabilizer': '防抖',
    'brBlend': '混合',
    'brBlendMode': '画笔混合模式',
    'brBlendLock': '将混合模式固定到画笔',
    'brEditGroup': '编辑分组',
    'brFolderIcon': '文件夹图标',
    'brFolderName': '文件夹名称',
    'brFeather': '羽化',
    'brTolerance': '容差',
    'brGapClose': '闭合缝隙',
    'brGrowShrink': '扩展 / 收缩',
    'brAntiAlias': '抗锯齿',
    'brAntiAliasEdge': '边缘抗锯齿',
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
    'brExpand': '展开',
    'brMeshWarp': '网格变形',
    'commonReset': '重置',
    'commonFill': '填充',
    'viewZoomIn': '放大',
    'viewZoomOut': '缩小',
    'viewFitToView': '适应窗口',
    'viewResetView': '重置视图（100%）',
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
    'tlSections': '区段',
    'tlFoldSection': '折叠区段',
    'tlHideSectionLayers': '隐藏区段图层',
    'tlShowSectionLayers': '显示区段图层',
    'tlOnlyThisSection': '仅此区段',
    'tlAllDisplayedLayers': '所有显示的图层',
    'tlShowAll': '全部显示',
    'tlHideAll': '全部隐藏',
    'tlSoloActiveLayer': '独奏当前图层',
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
    'tlAddLayerHere': '在此添加图层',
    'tlDissolveFolder': '解散文件夹',
    'tlRenameFolder': '重命名文件夹…',
    'tlRemoveAudio': '移除音频',
    'tlLayerMark': '图层标记',
    'tlRepeat': '重复',
    'tlRepeatSelection': '重复所选',
    'tlSeNameTemplate': 'SE 名称 {name}',
    'tlAddLayerHeader': '添加图层',
    'tlSameAsSelected': '与所选相同',
    'tlKindAnimation': '动画',
    'tlKindStoryboard': '分镜',
    'tlKindArt': '美术',
    'tlKindSe': 'SE',
    'tlKindInstruction': '指示',
    'tlAttachFreeAbove': '在上方添加自由附属图层',
    'tlAttachFreeBelow': '在下方添加自由附属图层',
    'tlAttachSyncedAbove': '在上方添加同步附属图层',
    'tlAttachSyncedBelow': '在下方添加同步附属图层',
    'tlLayerCommands': '图层命令',
    'tlFrameCommands': '帧命令',
    'tlLayer': '图层',
    'tlFrame': '帧',
    'tlDuplicateLayer': '复制图层',
    'tlLinkDuplicateLayer': '链接复制图层',
    'tlUnlinkLayer': '取消图层链接',
    'tlGroupIntoFolder': '编组到文件夹',
    'tlRenameLayer': '重命名图层…',
    'tlCopyLayer': '复制图层',
    'tlDeleteLayer': '删除图层',
    'tlImportAudio': '导入音频…',
    'tlCopyFrame': '复制帧',
    'tlPasteLinkedFrame': '粘贴链接帧',
    'tlDeleteCell': '删除单元格',
    'tlEditInstance': '编辑实例…',
    'tlAdd': '添加',
    'tlPush': '推出（空出帧）',
    'tlPull': '拉回（收拢帧）',
    'sbShorterRows': '行更矮',
    'sbTallerRows': '行更高',
    'sbOneStoryboardRowPerCut': '该镜头已有分镜图层，每个镜头只能有一个。',
    'cnPreviousPage': '上一页',
    'cnNextPage': '下一页',
    'cnActionColumn': '动作',
    'cnConte': '分镜',
    'tlBlankX': '空 / ×',
    'tlMark': '标记 ●',
    'tlSetCommasN': '设为 N 格…',
    'tlSetCommaTemplate': '设为 {n} 格',
    'tlProjectAudioRate': '项目音频采样率',
    'tlCustom': '自定义…',
    'tlShowSeRows': '显示 SE 行',
    'tlShowCameraRows': '显示摄影机行',
    'tlArtLayer': '美术图层',
    'tlStoryboardLayer': '分镜图层',
    'setCommasTitle': '设置格数',
    'setCommasField': '曝光帧数',
    'projectFpsTitle': '项目帧率',
    'projectFpsField': '每秒帧数',
  };
}
