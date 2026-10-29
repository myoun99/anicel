import 'package:flutter/foundation.dart';

import '../../models/app_language.dart';
import '../../models/timesheet_info.dart' show WorkPicture;
import '../../models/timesheet_sheet_kind.dart';
import '../../services/persistence/save_stretch.dart';
import '../audio/sound_cannot_play.dart' show SoundCannotPlay;

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

  /// The NOTATION-language table, read at call time: every word a file an
  /// export writes carries — a Photoshop document's row names too (F-485,
  /// 유저 2026-10-27: 「출력물 언어, 표기용 언어에 맞춤」).
  static AppStrings get notation =>
      AppStrings.of(settings.value.notationLanguage);

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

  /// Same contract for a shortcut window shelf's name (`ShortcutShelf`), by
  /// the enum value's `name`: the English is the shelf's own.
  String shortcutShelfName(String shelf, String fallback) =>
      _values['shortcutShelf.$shelf'] ?? fallback;

  /// And for a shortcut preset's name (I-63), by the enum value's `name`: the
  /// English is the preset's own. The app's own name is one word in every
  /// language, so the anicel preset has no row anywhere.
  String shortcutPresetName(String preset, String fallback) =>
      _values['shortcutPreset.$preset'] ?? fallback;

  /// A menu entry's wording, by the stable id the menu bar already keys its
  /// widgets with. Same fallback contract as [shortcutLabel]: English lives
  /// at the call site, the other languages here. An id left untabled — the
  /// play/pause entry, whose label flips with playback state — simply keeps
  /// the label it was given.
  String menuLabel(String id, String fallback) =>
      _values['menuAction.$id'] ?? fallback;

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

  /// A blend mode's name, by the enum value's `name` — ONE family for the
  /// layer, brush and dual-tip blends, whose separable modes share names, so
  /// a row serves every list that offers it. Same contract as
  /// [layerProcessName]: the English is the model's, the rest are here.
  ///
  /// 🚨유저 2026-09-15 (blend-mode-names-language-Q1): 「블렌드 모드도 모든
  /// 언어로 번역」 — reversing the 07-22 rule (ja localized first, every other
  /// language the shared English) for every name a model carries. The ko, fr
  /// and zh words are each language's Photoshop blend list; ja keeps the Clip
  /// Studio words the models carried.
  String blendModeName(String name, String fallback) =>
      _values['blendMode.$name'] ?? fallback;

  /// An effect kind's name, by its `jsonValue` — the same reversal.
  String effectKindName(String key, String fallback) =>
      _values['effectKind.$key'] ?? fallback;

  /// An effect parameter's lane name, by the id its spec carries — F-37
  /// (유저 2026-09-15, F-37-Q1: 「전부 번역 — 레인 이름도 한국어로」), on the
  /// contract [effectKindName] follows.
  String effectParameterName(String id, String fallback) =>
      _values['effectParameter.$id'] ?? fallback;

  /// A word of a menu parameter, by its id (I-132-Q6) — the contract
  /// [effectKindName] follows.
  String effectChoiceName(String id, String fallback) =>
      _values['effectChoice.$id'] ?? fallback;

  /// A key side's kind, by the enum value's `name` (I-89 ②) — the contract
  /// [layerProcessName] keeps: the English is the model's, the rest are
  /// here. ↩️Rows of their own (`keyInterpolationLinear` · `…Hold`) while the
  /// key window offered two of them.
  String keySideKindName(String name, String fallback) =>
      _values['keySideKind.$name'] ?? fallback;

  String keyPathKindName(String name, String fallback) =>
      _values['keyPathKind.$name'] ?? fallback;

  /// A selection mode's name, by the enum value's `name` — the same reversal;
  /// the ko rows are the user's own words (R26 #16).
  String selectionModeName(String name, String fallback) =>
      _values['selectionMode.$name'] ?? fallback;

  /// What an import could not do, by the key the warning carries — the same
  /// contract as [blendModeName]: the English is the model's own wording and
  /// lives at the call site, the other languages are here, and a key no
  /// table answers falls back to that English (F-124, 2026-09-16).
  String importWarning(String key, String fallback) =>
      _values['importWarning.$key'] ?? fallback;

  /// Why a cut folder's parse dropped a file, by `ExclusionReason.name`.
  String exclusionReason(String key, String fallback) =>
      _values['exclusionReason.$key'] ?? fallback;

  /// Why a rasterize left a row the reference it is, and what gets it past
  /// (F-374-Q11), by `ReferenceWait.name` — the contract [exclusionReason]
  /// keeps: the English is the enum's own, the other languages are here.
  String referenceWait(String key, String fallback) =>
      _values['referenceWait.$key'] ?? fallback;

  /// A file type's name in the save window, by the extensions it writes —
  /// the contract of [importWarning]: the English is the group's own label
  /// (`file_type_groups.dart`), the other languages are here (F-273).
  String fileTypeLabel(String extensions, String fallback) =>
      _values['fileType.$extensions'] ?? fallback;

  String get programLanguageLabel => _s('programLanguageLabel');
  String get notationLanguageLabel => _s('notationLanguageLabel');
  String get programLanguageHelp => _s('programLanguageHelp');
  String get notationLanguageHelp => _s('notationLanguageHelp');

  /// The launch splash's stages, in the order they run (I-106, user
  /// 2026-10-21: 「투명하게 하고있는걸 보여주면되. 시간이 매우 짧더라도」).
  String get launchStageEngine => _s('launchStageEngine');
  String get launchStagePlugins => _s('launchStagePlugins');
  String get launchStageApp => _s('launchStageApp');
  String get launchStageFirstFrame => _s('launchStageFirstFrame');

  /// The window the app opens at launch (유저 2026-10-28: 「앱 실행시 앱
  /// 설명 넣고싶어. 다음부터 표시안함버튼있고」) — its words are the bundled
  /// files' (`LaunchNoticeSection`); these are its frame.
  String get launchNoticeTitle => _s('launchNoticeTitle');
  String get launchNoticeDontShowAgain => _s('launchNoticeDontShowAgain');

  /// The usage statistics' one switch (I-70), in Preferences ▸ System, and
  /// what it sends, as its tooltip.
  String get usageStatsSend => _s('usageStatsSend');
  String get usageStatsHelp => _s('usageStatsHelp');

  /// The usage statistics' question at launch (유저 2026-10-29: 「따로 묻는
  /// 작은 창」): the ask, then [usageStatsHelp], then where it changes.
  String get usageStatsTitle => _s('usageStatsTitle');
  String get usageStatsAsk => _s('usageStatsAsk');
  String get usageStatsChangeLater => _s('usageStatsChangeLater');
  String get usageStatsDontSend => _s('usageStatsDontSend');
  String get usageStatsDoSend => _s('usageStatsDoSend');

  /// The first launch's window (I-144, 유저 2026-10-29): the display
  /// settings picked before anything else, and where they change later.
  String get firstRunTitle => _s('firstRunTitle');
  String get firstRunChangeLater => _s('firstRunChangeLater');
  String get firstRunStart => _s('firstRunStart');

  /// The timeline/timesheet gap empty state.
  String get noCutSelected => _s('noCutSelected');

  /// R26 #35/#13 — the shared CURSOR NOTICES: every refused action says
  /// why, right where the user is looking.
  String get noticeNoFrameHere => _s('noticeNoFrameHere');
  String get noticeNothingToCut => _s('noticeNothingToCut');

  /// The conte's pen on a cut with no conte row to draw into, while
  /// 「프레임 자동 생성」 is off (유저 2026-09-30, H51: 「콘티레이어없으면
  /// 프레임이 없다고뜨는데 … 콘티레이어가 없다고」).
  String get noticeNoConteLayer => _s('noticeNoConteLayer');

  /// R27 #16: the refusal is about the LAYER, not the section — the CAM
  /// section is no longer uniformly undrawable in the user's model.
  String get noticeLayerNotDrawable => _s('noticeLayerNotDrawable');

  /// F-242: a row that could be drawn on, with its eye (or a folder's above
  /// it) off — its cel is there, only hidden.
  String get noticeLayerHidden => _s('noticeLayerHidden');

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


  String get tlSharedColourEdit => _s('tlSharedColourEdit');

  /// R27 #31: the export window's empty state — the project has no cuts
  /// at all (standing in a GAP is not this; that anchors on the first cut).
  String get exportNoCuts => _s('exportNoCuts');
  /// The render queue and the presets with nothing in them — one short line
  /// each (유저 2026-09-15, empty-state-law-Q1).
  String get exportQueueEmpty => _s('exportQueueEmpty');
  String get exportPresetsEmpty => _s('exportPresetsEmpty');

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
  String get recordMicNotAllowed => _s('recordMicNotAllowed');

  // --- Capture chain (REC1-D) ---
  String get recordTakeClipped => _s('recordTakeClipped');
  String get recordClipMarkerTooltip => _s('recordClipMarkerTooltip');

  /// D26: the crossing-fade refusal warning (red corner marker's hover
  /// text) — the sanctioned exception to the no-explanatory-UI rule.
  String get tlTransitionCrossingWarning => _s('tlTransitionCrossingWarning');

  /// An O.L's name on the transition row — not the user's to set (F-229,
  /// 유저: 「이름부분은 그냥 컷O.L. 일본어론 カットO.L」). 🗣️F-339 (유저
  /// 2026-10-11): 「O.L 오르쪽에 . 이라는 의문의 점이 있음. 그리고 컷이랑
  /// O.L이랑 띄우도록. 관련된것도 규칙 마찬가지」 — the term the word ends
  /// in is the vocabulary's `O.L`; ↩️the dot was the sentence's.
  String get tlTransitionCutOl => _s('tlTransitionCutOl');
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

  /// The app's consent to the microphone (I-133).
  String get audioMicrophoneAllowedLabel => _s('audioMicrophoneAllowedLabel');
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
  String get audioMute => _s('audioMute');
  String get audioSolo => _s('audioSolo');

  // --- The fps-change audio notice (EXPORT-AUDIO ④) ---
  /// '{from}'/'{to}' are replaced with the rate labels.
  String get fpsAudioTitleTemplate => _s('fpsAudioTitleTemplate');
  String get fpsAudioBody => _s('fpsAudioBody');
  String get fpsAudioKeep => _s('fpsAudioKeep');
  String get fpsAudioPull => _s('fpsAudioPull');

  // --- Send feedback (I-139): the two forms the window chooses between ---
  String get feedbackTextOnly => _s('feedbackTextOnly');
  String get feedbackWithFiles => _s('feedbackWithFiles');

  // --- The pending selection-move prompt (R17-①) ---

  /// Closes an open polygon outline. A tablet has no Enter key, so the
  /// confirm has to be reachable as a button too (the same reason the
  /// deselect button exists).
  String get selectionClosePolygon => _s('selectionClosePolygon');

  /// 선택 반전 (I-23) — the selection tool's settings button that selects
  /// what is not selected, out to the pasteboard wall.
  String get selectionInvert => _s('selectionInvert');
  String get selectionInvertInCanvas => _s('selectionInvertInCanvas');
  String get toolSelectionMode => _s('toolSelectionMode');

  // --- Shared window verbs (the AppWindow action row) ---
  String get commonSave => _s('commonSave');
  String get commonDelete => _s('commonDelete');
  String get commonAdd => _s('commonAdd');
  String get commonRename => _s('commonRename');
  String get commonLink => _s('commonLink');
  String get commonPreview => _s('commonPreview');

  // --- The rename family (AppPromptDialog) ---

  /// A timeline button's window names what it does and, in brackets,
  /// what it does it to — 🗣️I-24-open-entry (유저 2026-10-01): 「노출 길이
  /// 설정 (프레임), 노출 길이 설정 (컷) 이렇게 하자 … 컷이름같은거
  /// 안써도되 … 이 규칙은 다른 타임라인 버튼도 동일하게. 이름편집같은거.
  /// 이름 편집 (레이어) 이렇게」. The KIND of thing, never its own name.
  String windowTitleOn(String action, String target) =>
      _s('windowTitleTemplate')
          .replaceAll('{action}', action)
          .replaceAll('{target}', target);

  /// ↩️Each window wore its own title (「레이어 이름 변경」 …) and a cap
  /// over its field that said it again (「레이어 이름」) — 「텍스트편집위에
  /// 레이어 이름이나 프레임 이름이란 텍스트 필요없음」.
  String get editNameAction => _s('editNameAction');
  String get renameLayerEmpty => _s('renameLayerEmpty');
  /// The import window's cut name field — the rename window no longer
  /// wears it.
  String get renameCutField => _s('renameCutField');
  String get renameCutEmpty => _s('renameCutEmpty');

  /// A drawing guide's name — the label the overlay paints over its axis,
  /// so an empty one has nothing to draw and is refused.
  String get renameGuideTitle => _s('renameGuideTitle');
  String get renameGuideField => _s('renameGuideField');
  String get renameGuideEmpty => _s('renameGuideEmpty');

  /// The cut's note — empty is allowed, it CLEARS the note.
  String get editNoteAction => _s('editNoteAction');

  // --- Confirmations ---
  String get deleteLayerTitle => _s('deleteLayerTitle');

  /// '{name}' is replaced with the layer name.
  String get deleteLayersMessage => _s('deleteLayersMessage');
  String get deleteLayersHeading => _s('deleteLayersHeading');
  String get deleteEffectsHeading => _s('deleteEffectsHeading');
  String get frameNameConflictTitle => _s('frameNameConflictTitle');

  /// Reads right for one frame or many (I-18: 「단일 변경만 대응하는게
  /// 아니라 복수 대응을 기본으로」) — the frames are the list under it.
  String get frameNameConflictBody => _s('frameNameConflictBody');

  /// The same notice said of a LINKED PASTE onto another row (I-71): the
  /// frames listed are the row's own, already holding the names — what
  /// is not brought is the copied drawing, not theirs.
  String get linkedPasteConflictBody => _s('linkedPasteConflictBody');

  /// The fold over the frames a name link would join.
  String get frameNameConflictListHeading =>
      _s('frameNameConflictListHeading');

  // --- The instance editors ---
  String get seInstanceNewTitle => _s('seInstanceNewTitle');
  String get seInstanceEditTitle => _s('seInstanceEditTitle');
  String get seNameLabel => _s('seNameLabel');
  String get seTypeLabel => _s('seTypeLabel');
  String get seDialogueLabel => _s('seDialogueLabel');
  String get seDialogueOffsetLabel => _s('seDialogueOffsetLabel');
  String get seKomaPerGlyphLabel => _s('seKomaPerGlyphLabel');
  String get seLinkedAudioLabel => _s('seLinkedAudioLabel');
  String get seLinkedAudioNone => _s('seLinkedAudioNone');
  String get seUnlinkAudio => _s('seUnlinkAudio');

  /// The key window's two sides (I-89 ②), a row each — the kinds a side can
  /// be are the model's words ([keySideKindName]).
  String get keySideIncoming => _s('keySideIncoming');
  String get keySideOutgoing => _s('keySideOutgoing');

  /// An eased side's influence, AE's — 33% is its Easy Ease.
  String get keyEaseInfluence => _s('keyEaseInfluence');

  /// The key window's path (I-89 ④): a position key's corner or curve.
  String get keyPath => _s('keyPath');

  /// The key window's roving (I-89 ④-Q5): After Effects' Rove Across Time,
  /// a position key's time left to its run.
  String get keyRoving => _s('keyRoving');

  /// What the key window's rows mean, each as its cap's tooltip (F-366,
  /// 유저 2026-10-16: 「이런거 설명은 항목 헤더에 툴팁 띄워줬으면. 도착 출발
  /// 경로 이런거에도」).
  String get keySideIncomingHelp => _s('keySideIncomingHelp');
  String get keySideOutgoingHelp => _s('keySideOutgoingHelp');
  String get keyPathHelp => _s('keyPathHelp');
  String get keyRovingHelp => _s('keyRovingHelp');

  /// The canvas's camera path settings (I-89 ④), words of the confirmed
  /// spec's mock: what it shows, how much of it, and its numbers.
  String get cameraPath => _s('cameraPath');
  String get cameraPathOff => _s('cameraPathOff');
  String get cameraPathSpace => _s('cameraPathSpace');
  String get cameraPathSpaceTime => _s('cameraPathSpaceTime');
  String get cameraPathAllKeys => _s('cameraPathAllKeys');
  String get cameraPathAroundPlayhead => _s('cameraPathAroundPlayhead');
  String get cameraPathTickEvery => _s('cameraPathTickEvery');
  String get cameraPathAround => _s('cameraPathAround');

  // --- Convert to linked cut ---
  String get convertLinkedCutTitle => _s('convertLinkedCutTitle');

  /// '{cut}' is replaced with the origin cut's name.
  String get convertLinkedCutBodyTemplate => _s('convertLinkedCutBodyTemplate');
  String get convertLinkedCutTargetLabel => _s('convertLinkedCutTargetLabel');

  /// The heading over the layers it links.
  String get convertLinkedCutLinksHeading =>
      _s('convertLinkedCutLinksHeading');

  /// '{cut}' the target cut. The origin's picture wins each same-name
  /// conflict (원본 승리) — announced up front, the drawings it replaces
  /// listed under it rather than counted in it (I-18 link-notice-Q1).
  String get convertLinkedCutReplacedTemplate =>
      _s('convertLinkedCutReplacedTemplate');

  /// The fold over those replaced drawings.
  String get convertLinkedCutReplacedHeading =>
      _s('convertLinkedCutReplacedHeading');

  /// '{count}' is the joining drawing count.
  String get convertLinkedCutJoiningTemplate =>
      _s('convertLinkedCutJoiningTemplate');

  /// The heading over the layers '{cut}' gains.
  String get convertLinkedCutTargetGainsHeadingTemplate =>
      _s('convertLinkedCutTargetGainsHeadingTemplate');

  /// The heading over the layers THIS cut gains.
  String get convertLinkedCutOriginGainsHeading =>
      _s('convertLinkedCutOriginGainsHeading');
  String get convertLinkedCutNothing => _s('convertLinkedCutNothing');
  String get convertLinkedCutUndoNote => _s('convertLinkedCutUndoNote');
  String get convertLinkedCutResizeFirst => _s('convertLinkedCutResizeFirst');

  // Drawing guides (symmetry / perspective).
  String get guideKindSymmetry => _s('guideKindSymmetry');
  String get guideKindPerspective => _s('guideKindPerspective');
  String get guideDelete => _s('guideDelete');
  String get guideShow => _s('guideShow');
  String get guideActsOn => _s('guideActsOn');
  String get guideActsOff => _s('guideActsOff');
  String get guideLibraryEmpty => _s('guideLibraryEmpty');
  String get noGuideSelected => _s('noGuideSelected');
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
  String get guideDeleteVanishingPoint => _s('guideDeleteVanishingPoint');
  String get guideParallel => _s('guideParallel');
  String get guideParallelAngle => _s('guideParallelAngle');
  String get guideLineDensity => _s('guideLineDensity');
  String get guideRasterize => _s('guideRasterize');

  // --- Project lifecycle confirmations ---
  String get closeProjectTitle => _s('closeProjectTitle');

  /// A never-saved project's tab (I-7); `{n}` is its number this run.
  String get untitledProjectTab => _s('untitledProjectTab');

  /// Save As pointed at a file another tab has open (I-7).
  String get fileOpenInAnotherTab => _s('fileOpenInAnotherTab');

  /// A project the format numbers refuse, as the open door says it
  /// (`fileErrorWords`): one sentence, and the older one says the
  /// file's format (the save law, 유저 2026-10-06).
  String get openNewerFormat => _s('openNewerFormat');
  String openOlderFormat(int saved, int oldest) =>
      _s('openOlderFormatTemplate')
          .replaceAll('{saved}', '$saved')
          .replaceAll('{oldest}', '$oldest');
  String get closeProjectBody => _s('closeProjectBody');
  String get closeProjectVanishedBody => _s('closeProjectVanishedBody');
  String get commonSaveAs => _s('commonSaveAs');

  /// 「다른 이름으로 저장」 as the row that opens its formats wears it —
  /// the verb and nothing after it, since what it opens is a second
  /// level, not a window (backlog-21-Q1) — and as the formats' actions
  /// are named over it (「다른 이름으로 저장: PNG」).
  String get saveAsTitle => _s('saveAsTitle');

  /// The window a manual save puts in front of itself, running and finished.
  ///
  /// The finished line is the point of the pair. The running one only says
  /// what is happening; this one is the answer to "did it save?", which is
  /// a question the app never used to answer at all.
  String get saveProgressRunning => _s('saveProgressRunning');
  String get saveProgressDone => _s('saveProgressDone');
  String get savePrepareRunning => _s('savePrepareRunning');
  String get savePrepareDone => _s('savePrepareDone');

  /// The stretch of a save the wait window's line names while it runs
  /// (F-494, [SaveStretch]): the media taken out set aside, the cels, the
  /// carried files checked, the media, the sounds converted for playback,
  /// the fonts, the file's gaps closed, the file handed back to its document.
  String get saveStepKeepingLeftBehind => _s('saveStepKeepingLeftBehind');
  String get saveStepCels => _s('saveStepCels');
  String get saveStepChecking => _s('saveStepChecking');
  String get saveStepMedia => _s('saveStepMedia');
  String get saveStepConforms => _s('saveStepConforms');
  String get saveStepFonts => _s('saveStepFonts');
  String get saveStepCompacting => _s('saveStepCompacting');
  String get saveStepHandingBack => _s('saveStepHandingBack');

  /// What a save's window says while it is in [stretch].
  String saveStep(SaveStretch stretch) => switch (stretch) {
    SaveStretch.keepingLeftBehind => saveStepKeepingLeftBehind,
    SaveStretch.cels => saveStepCels,
    SaveStretch.checking => saveStepChecking,
    SaveStretch.media => saveStepMedia,
    SaveStretch.conforms => saveStepConforms,
    SaveStretch.fonts => saveStepFonts,
    SaveStretch.compacting => saveStepCompacting,
    SaveStretch.handingBack => saveStepHandingBack,
  };
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

  /// The notice over a rasterize that left rows the references they are
  /// (F-374-Q11 「막고 경고」): its line. Why each row waits, with what gets
  /// it past, is [referenceWait]'s.
  String get rasterizeLeftReferences => _s('rasterizeLeftReferences');
  String get pasteProgressRunning => _s('pasteProgressRunning');
  String get pasteProgressDone => _s('pasteProgressDone');
  String get unsavedAutosaveTitle => _s('unsavedAutosaveTitle');
  String get unsavedAutosaveBody => _s('unsavedAutosaveBody');
  String get commonNotNow => _s('commonNotNow');

  // --- The menu bar's own headings and its one stateful entry ---
  /// The top strip's two buttons (the menu bar's successor).
  String get topStripProject => _s('topStripProject');
  String get topStripSettings => _s('topStripSettings');

  String get menuPlay => _s('menuPlay');
  String get menuPause => _s('menuPause');

  // --- Project files ---
  String get fileOpenTitle => _s('fileOpenTitle');
  String get fileStorageOffNotice => _s('fileStorageOffNotice');
  String get fileOpenSettings => _s('fileOpenSettings');
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
  String get folderPickDriveNoticeAndroid =>
      _s('folderPickDriveNoticeAndroid');
  String get recentProjectsTitle => _s('recentProjectsTitle');
  String get recentReconnect => _s('recentReconnect');
  String get sortAscending => _s('sortAscending');

  // --- Canvas size ---
  String get canvasSizeTitle => _s('canvasSizeTitle');
  String get cameraSizeTitle => _s('cameraSizeTitle');
  String get canvasWidthLabel => _s('canvasWidthLabel');
  String get canvasHeightLabel => _s('canvasHeightLabel');

  /// '{min}'/'{max}' are the dimension bounds.
  String get canvasSizePresets => _s('canvasSizePresets');
  String get canvasAdjustOnCanvas => _s('canvasAdjustOnCanvas');
  String get cameraRatioFree => _s('cameraRatioFree');
  String get cameraRatioCurrent => _s('cameraRatioCurrent');
  String get commonResize => _s('commonResize');

  // --- Input settings ---
  String get inputPressureCurve => _s('inputPressureCurve');
  String get inputCanvasHeading => _s('inputCanvasHeading');
  String get inputRightClick => _s('inputRightClick');
  String get inputWheelClick => _s('inputWheelClick');
  String get inputPenTail => _s('inputPenTail');
  String get inputCanvasTouchHeading => _s('inputCanvasTouchHeading');
  String get inputIgnoreTouch => _s('inputIgnoreTouch');
  String get inputDragOneFinger => _s('inputDragOneFinger');
  String get inputDragTwoFingers => _s('inputDragTwoFingers');
  String get inputDragThreeFingers => _s('inputDragThreeFingers');
  String get inputExtraFinger => _s('inputExtraFinger');
  String get inputExtraFingerHelp => _s('inputExtraFingerHelp');
  String get inputStrokeFinger => _s('inputStrokeFinger');
  String get inputStrokeFingerHelp => _s('inputStrokeFingerHelp');
  String get inputFlipHaptics => _s('inputFlipHaptics');
  String get inputFlipHapticsHelp => _s('inputFlipHapticsHelp');
  String get inputTwoFingerRotation => _s('inputTwoFingerRotation');
  String get inputTwoFingerRotationHelp => _s('inputTwoFingerRotationHelp');
  String get inputRotationLock => _s('inputRotationLock');
  String get inputRotationLockHelp => _s('inputRotationLockHelp');
  String get inputRotationSnap => _s('inputRotationSnap');
  String get inputZoomSnaps => _s('inputZoomSnaps');
  String get inputZoomCeiling => _s('inputZoomCeiling');
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
  String get memoryItemLayerImages => _s('memoryItemLayerImages');
  String get memoryItemFramePictures => _s('memoryItemFramePictures');
  String get memoryItemBrushTips => _s('memoryItemBrushTips');
  String get memoryItemPanelRasters => _s('memoryItemPanelRasters');
  String get memoryItemViewerPages => _s('memoryItemViewerPages');
  String get memoryItemImageCache => _s('memoryItemImageCache');
  String get memoryItemStoryboardThumbnails =>
      _s('memoryItemStoryboardThumbnails');
  String get memoryItemSheetImages => _s('memoryItemSheetImages');
  String get memoryItemTextImages => _s('memoryItemTextImages');
  String get memoryItemStrokePreviews => _s('memoryItemStrokePreviews');
  String get memoryItemTimelineTiles => _s('memoryItemTimelineTiles');
  String get memoryItemMoviePictures => _s('memoryItemMoviePictures');
  String get memoryItemTileImages => _s('memoryItemTileImages');
  String get memoryItemEnginePool => _s('memoryItemEnginePool');
  String get memoryItemEngineScratch => _s('memoryItemEngineScratch');

  /// What sits outside the allowance — the rows named in [items] — as one
  /// sentence (유저 2026-09-16, memory-allowance-Q2).
  String memoryOutsideAllowance(String items) =>
      _s('memoryOutsideAllowanceTemplate').replaceAll('{items}', items);
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

  // --- A save its file refused: why, and the failed copy (실패본) the work
  // went to instead (whole-write-temp-beside-the-file, 2026-09-23) ---
  String get saveFailedTitle => _s('saveFailedTitle');
  String get saveFailedFileInUse => _s('saveFailedFileInUse');
  String get saveFailedReadOnly => _s('saveFailedReadOnly');
  String get saveFailedDiskFull => _s('saveFailedDiskFull');
  String get saveFailedLocationGone => _s('saveFailedLocationGone');
  String get saveFailedReplaceRefused => _s('saveFailedReplaceRefused');
  String get saveFailedUnknown => _s('saveFailedUnknown');
  String get saveFailedCopyKept => _s('saveFailedCopyKept');
  String get saveFailedNoCopy => _s('saveFailedNoCopy');
  String get saveFailedRetry => _s('saveFailedRetry');
  String get saveFailedDetailsHeading => _s('saveFailedDetailsHeading');

  /// A line of the notice's fold: where the failed copy is.
  String saveFailedCopyLine(String path) =>
      _s('saveFailedCopyLineTemplate').replaceAll('{path}', path);

  /// A line of the notice's fold: the platform's own words.
  String saveFailedErrorLine(String error) =>
      _s('saveFailedErrorLineTemplate').replaceAll('{error}', error);
  String get failedCopyPickTitle => _s('failedCopyPickTitle');
  String get failedCopyVanishOnClose => _s('failedCopyVanishOnClose');
  String get failedCopyBackingUp => _s('failedCopyBackingUp');
  String get failedCopyBackedUp => _s('failedCopyBackedUp');
  String get closeProjectFailedCopyBody => _s('closeProjectFailedCopyBody');

  // --- Display (R11) ---
  String get uiScaleLabel => _s('uiScaleLabel');
  String get blockFrameLinesLabel => _s('blockFrameLinesLabel');
  String get unnamedMarkLabel => _s('unnamedMarkLabel');
  String get drawingCursorLabel => _s('drawingCursorLabel');
  String get drawingCursorBrush => _s('drawingCursorBrush');
  String get drawingCursorPen => _s('drawingCursorPen');
  String get drawingCursorCrosshair => _s('drawingCursorCrosshair');

  // --- Accent colours ---
  String get accent1Help => _s('accent1Help');

  // --- Sheet format ---
  String get sheetFormatTitle => _s('sheetFormatTitle');
  String get sheetFieldTitle => _s('sheetFieldTitle');
  String get sheetFieldEpisode => _s('sheetFieldEpisode');
  String get sheetFieldScene => _s('sheetFieldScene');
  String get sheetFieldCut => _s('sheetFieldCut');
  String get sheetFieldTime => _s('sheetFieldTime');
  String get sheetFieldName => _s('sheetFieldName');
  String get sheetFieldSheet => _s('sheetFieldSheet');
  String get workSettingsTitle => _s('workSettingsTitle');
  String get workSettingsStaff => _s('workSettingsStaff');
  String get workLogo => _s('workLogo');
  String get workCover => _s('workCover');

  /// What a picture of the work is called — in 작품 설정 and in the list of
  /// a pool file's uses alike.
  String workPictureName(WorkPicture picture) => switch (picture) {
    WorkPicture.logo => workLogo,
    WorkPicture.cover => workCover,
  };
  String get staffWorker => _s('staffWorker');
  String get sheetVisibleBoxes => _s('sheetVisibleBoxes');
  String get sheetStretchLineAction => _s('sheetStretchLineAction');
  String get sheetStretchLineCell => _s('sheetStretchLineCell');
  String get sheetStretchLineHelp => _s('sheetStretchLineHelp');
  String get sheetStretchLineOn => _s('sheetStretchLineOn');
  String get sheetStretchLineOff => _s('sheetStretchLineOff');
  String get sheetSeEmptyFill => _s('sheetSeEmptyFill');
  String get sheetLength => _s('sheetLength');
  String get sheetThreeSeconds => _s('sheetThreeSeconds');
  String get sheetSixSeconds => _s('sheetSixSeconds');

  /// What the paper a timesheet prints on is called.
  String sheetKindName(TimesheetSheetKind kind) => switch (kind) {
    TimesheetSheetKind.threeSeconds => sheetThreeSeconds,
    TimesheetSheetKind.sixSeconds => sheetSixSeconds,
  };
  String get sheetFillOn => _s('sheetFillOn');
  String get sheetFillOff => _s('sheetFillOff');
  String get sheetBrushAllow => _s('sheetBrushAllow');
  String get conteCoverPage => _s('conteCoverPage');
  String get conteBlankPage => _s('conteBlankPage');
  String get conteFormatTitle => _s('conteFormatTitle');
  String get conteFrontIn => _s('conteFrontIn');
  String get conteFrontOut => _s('conteFrontOut');
  String get conteForm => _s('conteForm');
  String get conteFormAnalog => _s('conteFormAnalog');
  String get conteFormDigital => _s('conteFormDigital');
  String get conteOutline => _s('conteOutline');
  String get conteOutlineOn => _s('conteOutlineOn');
  String get conteOutlineOff => _s('conteOutlineOff');
  String get envelopeFormatTitle => _s('envelopeFormatTitle');
  String get envelopeForm => _s('envelopeForm');
  String get sheetModeNotation => _s('sheetModeNotation');
  String get sheetModeData => _s('sheetModeData');

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
  String get instructionMarkNone => _s('instructionMarkNone');
  String get instructionNameLabel => _s('instructionNameLabel');
  String get instructionStartLabel => _s('instructionStartLabel');
  String get instructionEndLabel => _s('instructionEndLabel');
  String get instructionEditSetButton => _s('instructionEditSetButton');
  String get instructionEditorIcon => _s('instructionEditorIcon');
  String get instructionEditorColor => _s('instructionEditorColor');
  String get instructionEditorMark => _s('instructionEditorMark');
  String get systemStatusHelp => _s('systemStatusHelp');

  // --- The timeline action toolbar and its flyouts ---
  String get tlNoLayers => _s('tlNoLayers');
  String get tlLegendLayer => _s('tlLegendLayer');
  String get tlAllDisplayedOpacity => _s('tlAllDisplayedOpacity');
  String get tlLinkedWith => _s('tlLinkedWith');

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

  String get tlAudioGroup => _s('tlAudioGroup');
  String get tlSoundVolume => _s('tlSoundVolume');
  String get tlNameTagGroup => _s('tlNameTagGroup');
  String get tlReferenceGroup => _s('tlReferenceGroup');
  String get tlTransformGroup => _s('tlTransformGroup');
  String get tlLaneScale => _s('tlLaneScale');
  String get tlLaneRotation => _s('tlLaneRotation');
  String get tlLanePosition => _s('tlLanePosition');
  String get tlLaneOpacity => _s('tlLaneOpacity');
  String get tlLaneAnchorPoint => _s('tlLaneAnchorPoint');
  String get tlBypassLaneTemplate => _s('tlBypassLaneTemplate');
  String get tlApplyLaneTemplate => _s('tlApplyLaneTemplate');
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
  String get tlKindAnimation => _s('tlKindAnimation');
  String get tlKindStoryboard => _s('tlKindStoryboard');
  String get tlKindImage => _s('tlKindImage');
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

  String get seNameTagShowLineLabel => _s('seNameTagShowLineLabel');
  String get seNameTagLineInkLabel => _s('seNameTagLineInkLabel');
  String get seNameTagTrackingLabel => _s('seNameTagTrackingLabel');
  String get seNameTagSizeLabel => _s('seNameTagSizeLabel');
  String get seNameTagNameInkLabel => _s('seNameTagNameInkLabel');
  String get seNameTagBoxColorLabel => _s('seNameTagBoxColorLabel');
  String get seNameTagBoldLabel => _s('seNameTagBoldLabel');
  String get seNameTagItalicLabel => _s('seNameTagItalicLabel');
  String get seNameTagUnderlineLabel => _s('seNameTagUnderlineLabel');
  String get seNameTagStrikethroughLabel => _s('seNameTagStrikethroughLabel');

  /// The name-tag preview's FIXED samples (R5 #7) — it shows the look, not
  /// the block's own text, so these never change with the playhead.
  String get seNameTagPreviewName => _s('seNameTagPreviewName');
  String get seNameTagPreviewLine => _s('seNameTagPreviewLine');

  // --- The SE name tag editor (R5b) ---

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
  String get tlLayerCommands => _s('tlLayerCommands');
  String get tlFrameCommands => _s('tlFrameCommands');
  String get tlLayer => _s('tlLayer');
  String get tlFrame => _s('tlFrame');
  String get tlKey => _s('tlKey');
  /// I-25: the link window's button, and why it is off on a linked cut's row.
  String get linkWindowUnlink => _s('linkWindowUnlink');
  String get linkWindowUnlinkLinkedCut => _s('linkWindowUnlinkLinkedCut');
  String get tlResetGroup => _s('tlResetGroup');
  String get tlEffects => _s('tlEffects');
  String get tlAddEffectTemplate => _s('tlAddEffectTemplate');
  String get tlDropIntoFolderTemplate => _s('tlDropIntoFolderTemplate');
  String get tlDropOutOfFolder => _s('tlDropOutOfFolder');
  String get tlDropAttachSyncedTemplate => _s('tlDropAttachSyncedTemplate');
  String get tlDropAttachFreeTemplate => _s('tlDropAttachFreeTemplate');
  String get tlDropDetachAttach => _s('tlDropDetachAttach');

  /// ⑦: the one landing a folder attach has no home for — an organizer
  /// folder is FLAT, so a folder carrying a folder cannot become one.


  /// 폴더가 어태치가 될 때 fx 를 잃는다는 확인창(유저 2026-08-29). ⚠️「fx」는
  /// **fx 를 펼쳐서 보이는 전부**다 — 네임태그·트랜스폼·추가 fx. 그래서 문장도
  /// 나눠 쓰지 않고 「fx」 하나로 말한다.
  String get tlAttachDropsFxTitle => _s('tlAttachDropsFxTitle');
  String get tlAttachDropsFxBody => _s('tlAttachDropsFxBody');
  String get tlAttachDropsFxRows => _s('tlAttachDropsFxRows');

  /// The merge's warning (I-78-Q1 「포토샵 · 클튜처럼 (+경고)」): the merged
  /// row can hold one blend, so what it looks like over the rows under it
  /// may change — each line one way it may.
  String get tlMergeChangesTitle => _s('tlMergeChangesTitle');
  String get tlMergeChangesBody => _s('tlMergeChangesBody');
  String get tlMergeChanges => _s('tlMergeChanges');
  String get tlMergeChangeBlend => _s('tlMergeChangeBlend');
  String get tlMergeChangeClip => _s('tlMergeChangeClip');
  String get tlMergeChangeFolder => _s('tlMergeChangeFolder');
  String get tlMergeChangeRiderOver => _s('tlMergeChangeRiderOver');
  String get tlMergeChangeRiderUnder => _s('tlMergeChangeRiderUnder');
  String get tlMergeChangeWall => _s('tlMergeChangeWall');

  /// ⛔No trailing '…' on a BAR BUTTON's writing (B9, 유저 2026-08-17:
  /// 「심플하게 編集」) — this one and [tlSetCommasN] wore it and read as
  /// ellipsized labels on device. ↩️The '…' stayed on menu ENTRIES that
  /// open a dialog until F-437 (유저 2026-10-21: 「이 ... 점 세개 삭제. 그냥
  /// 글자만 … 앱에서 찾아서 전부」): no action's name wears one now, a
  /// button's, a menu row's or the shortcut list's. A line that says
  /// something is under way (「저장 중…」) is not a name, and keeps its own.

  /// Design D: the rigid shove as a verb. PUSH opens frames at the anchor
  /// and everything after travels with its spacing; PULL closes them and
  /// stops where the first affected row runs out of room.
  String get tlPush => _s('tlPush');
  String get tlPull => _s('tlPull');
  String get tlSetCommasN => _s('tlSetCommasN');

  /// Refused: a cut holds at most one storyboard row.
  String get sbOneStoryboardRowPerCut => _s('sbOneStoryboardRowPerCut');

  /// The conte sheet panel.

  /// The conte panel's page readout on the two pages that carry no number.

  /// What the conte PRINTS — read from the NOTATION language's table, not
  /// the program's (`conteWordsIn`).
  String get cnHeadCut => _s('cnHeadCut');
  String get cnHeadPicture => _s('cnHeadPicture');
  String get cnHeadAction => _s('cnHeadAction');
  String get cnHeadDialogue => _s('cnHeadDialogue');
  String get cnHeadSeconds => _s('cnHeadSeconds');
  String get cnCoverCuts => _s('cnCoverCuts');
  String get cnCoverArtist => _s('cnCoverArtist');

  /// What the timesheet PRINTS — read from the NOTATION language's table,
  /// not the program's (`timesheetWordsIn`): its header boxes' labels, and
  /// the words a repeat (UI-R10 #6) and a whole-cut hold (UI-R11 #15) print
  /// down their column. Not the info dialog's field names (`sheetField*`):
  /// those are the program's, and the paper keeps its forms' own shorthand.
  String get sheetPrintEpisode => _s('sheetPrintEpisode');
  String get sheetPrintTitle => _s('sheetPrintTitle');
  String get sheetPrintScene => _s('sheetPrintScene');
  String get sheetPrintCut => _s('sheetPrintCut');
  String get sheetPrintDuration => _s('sheetPrintDuration');
  String get sheetPrintName => _s('sheetPrintName');
  String get sheetPrintPage => _s('sheetPrintPage');
  String get sheetPrintRepeat => _s('sheetPrintRepeat');
  String get sheetPrintHold => _s('sheetPrintHold');

  /// '{n}' is the comma count.
  String get tlSetCommaTemplate => _s('tlSetCommaTemplate');
  String get tlProjectAudioRate => _s('tlProjectAudioRate');
  String get tlShowSeRows => _s('tlShowSeRows');
  String get tlShowCameraRows => _s('tlShowCameraRows');

  // --- The cut command group ---
  /// The cut PILL's name cell — the noun itself, beside [tlLayer] and
  /// [tlFrame]. The pill's first cell writes the noun out (유저 확정: 컷 ·
  /// 레이어 · 프레임은 아이콘 말고 텍스트), so all three need a short word.
  String get tlCut => _s('tlCut');
  String get cutCommands => _s('cutCommands');
  String get cutSettingsTitle => _s('cutSettingsTitle');

  // --- The media pool ---
  String get mediaActions => _s('mediaActions');
  String get mediaPoolEmpty => _s('mediaPoolEmpty');
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
  String get mediaViewerCloseFile => _s('mediaViewerCloseFile');
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

  /// What that notice says, whatever was refused and however many: the
  /// formats this particular opening accepts, [extensions] lower-case and
  /// without dots.
  ///
  /// ⛔It names no file — the files go in the list beneath it (유저
  /// 2026-08-29: 「지원하지 않는 파일이 감지되었습니다. 라는 안내창으로
  /// 두번째줄에 해당 파일들이라는 항목으로 … 파일주소,이름들 표시」).
  /// ↩️It was born with a `{name}` beside the formats, and every caller
  /// filled the formats alone: the placeholder showed in every refusal, in
  /// every language (서피스 AI 실기 2026-10-23, card
  /// open-door-windows-open-with). So the sentence is filled here, where
  /// its placeholders are written.
  String unsupportedFileMessage(Iterable<String> extensions) =>
      _s('unsupportedFileMessageTemplate').replaceAll(
        '{kinds}',
        extensions.map((extension) => '.$extension').join(', '),
      );

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
  String get transportToStart => _s('transportToStart');
  String get transportToEnd => _s('transportToEnd');
  String get transportLoop => _s('transportLoop');
  String get transportOnce => _s('transportOnce');
  String get transportPrevFrame => _s('transportPrevFrame');
  String get transportNextFrame => _s('transportNextFrame');
  String get colorRecent => _s('colorRecent');
  String get colorBackgroundSwap => _s('colorBackgroundSwap');
  String get paletteViewCompact => _s('paletteViewCompact');
  String get paletteViewCards => _s('paletteViewCards');
  String get paletteNew => _s('paletteNew');

  /// A new palette's name, 「팔레트 N」 (I-131-Q2), and back: the number a
  /// name of that pattern carries, null for any other name — both read off
  /// the one template, so the two cannot disagree.
  String paletteNumbered(int number) =>
      _s('paletteNumberedTemplate').replaceAll('{n}', '$number');
  int? paletteNumberOf(String name) {
    final template = RegExp.escape(_s('paletteNumberedTemplate'));
    final number = RegExp(
      '^${template.replaceAll(RegExp.escape('{n}'), r'(\d+)')}\$',
    ).firstMatch(name)?.group(1);
    return number == null ? null : int.parse(number);
  }

  String get paletteMakeDefault => _s('paletteMakeDefault');
  String get paletteDuplicate => _s('paletteDuplicate');
  String get paletteExport => _s('paletteExport');
  String paletteBrought(String name) =>
      _s('paletteBroughtTemplate').replaceAll('{name}', name);
  String paletteCopyName(String name) =>
      _s('paletteCopyTemplate').replaceAll('{name}', name);
  String get paletteDeleteTitle => _s('paletteDeleteTitle');
  String paletteDeleteBody(String name) =>
      _s('paletteDeleteTemplate').replaceAll('{name}', name);
  String get paletteRemoveCurrent => _s('paletteRemoveCurrent');
  String get paletteLock => _s('paletteLock');
  String get paletteMore => _s('paletteMore');
  String get penPressureTitle => _s('penPressureTitle');
  String get brushDynamicsTitle => _s('brushDynamicsTitle');
  String get curveSourcePressure => _s('curveSourcePressure');
  String get curveSourceTilt => _s('curveSourceTilt');
  String get curveSourceSpeed => _s('curveSourceSpeed');
  String get curveSourceRandom => _s('curveSourceRandom');
  String get curveMinimum => _s('curveMinimum');
  String get curveMaximum => _s('curveMaximum');
  String get curveTiltFlat => _s('curveTiltFlat');
  String get curveTiltUpright => _s('curveTiltUpright');
  String get onionCurrentDrawing => _s('onionCurrentDrawing');
  String get audioLevelMeter => _s('audioLevelMeter');
  String get panelMedia => _s('panelMedia');
  String get panelMediaViewer => _s('panelMediaViewer');
  String get panelMediaViewerSub => _s('panelMediaViewerSub');
  String get panelOnionSkin => _s('panelOnionSkin');
  String get panelToolSize => _s('panelToolSize');
  /// 🗣️F-76 (유저 2026-09-11): 「콘티패널은 지금의 스토리보드패널을
  /// 콘티패널로 명명하고, 기존 콘티패널은 알기쉽게 콘티 프리뷰 패널이나 콘티
  /// 용지 패널? 이거는 이름은 제안해주도록」 — F-76-Q1 (09-30): 「콘티 용지」.
  /// Until then the two panels shared one Korean name. The code names follow
  /// separately (storyboard → conte, conte → conteSheet).
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
  String get onionBeforeTint => _s('onionBeforeTint');
  String get onionAfterTint => _s('onionAfterTint');
  String get onionGhostColorHelp => _s('onionGhostColorHelp');
  String get onionPegCountHelp => _s('onionPegCountHelp');
  String get onionPlacementHelp => _s('onionPlacementHelp');
  String get onionStepBlocks => _s('onionStepBlocks');
  String get onionStepBlocksDrawings => _s('onionStepBlocksDrawings');
  String get onionStepFrames => _s('onionStepFrames');
  String get onionModeColors => _s('onionModeColors');
  String get onionModeImages => _s('onionModeImages');
  String get onionPlacementOnTop => _s('onionPlacementOnTop');
  String get onionPlacementInPlace => _s('onionPlacementInPlace');
  String onionPegBefore(int n) =>
      _s('onionPegBeforeTemplate').replaceAll('{n}', '$n');
  String onionPegAfter(int n) =>
      _s('onionPegAfterTemplate').replaceAll('{n}', '$n');

  // --- The shortcut editor ---
  String get shortcutTitle => _s('shortcutTitle');
  String get shortcutResetAll => _s('shortcutResetAll');
  String get shortcutResetToDefault => _s('shortcutResetToDefault');
  String get shortcutUnassign => _s('shortcutUnassign');
  String get shortcutRecordNew => _s('shortcutRecordNew');
  String get shortcutTouch => _s('shortcutTouch');
  String get shortcutSearch => _s('shortcutSearch');
  String get shortcutConflictBanner => _s('shortcutConflictBanner');
  String get shortcutRecordingHint => _s('shortcutRecordingHint');

  String get shortcutPresets => _s('shortcutPresets');
  String get shortcutPresetNew => _s('shortcutPresetNew');
  String get shortcutPresetNameEmpty => _s('shortcutPresetNameEmpty');
  String get shortcutPresetDelete => _s('shortcutPresetDelete');
  String shortcutPresetDeleteBody(String name) =>
      _s('shortcutPresetDeleteTemplate').replaceAll('{name}', name);
  String get shortcutPresetRename => _s('shortcutPresetRename');
  String get shortcutPresetDuplicate => _s('shortcutPresetDuplicate');
  String shortcutPresetCopyName(String name) =>
      _s('shortcutPresetCopyTemplate').replaceAll('{name}', name);

  /// A program's shortcut files made into the new [preset] (I-107): how many
  /// of their keys an action took, and how many none did.
  String shortcutFileImported(String preset, int taken, int skipped) =>
      _s('shortcutFileImportedTemplate')
          .replaceAll('{preset}', preset)
          .replaceAll('{taken}', '$taken')
          .replaceAll('{skipped}', '$skipped');
  String shortcutFileUnreadable(String name) =>
      _s('shortcutFileUnreadableTemplate').replaceAll('{name}', name);
  String get shortcutPresetExport => _s('shortcutPresetExport');
  String shortcutPresetBrought(String name) =>
      _s('shortcutPresetBroughtTemplate').replaceAll('{name}', name);

  // --- Playback transport and the sheet page rail ---
  String get playbackMode => _s('playbackMode');
  String get playbackModeSkipFrames => _s('playbackModeSkipFrames');
  String get playbackModeEveryPicture => _s('playbackModeEveryPicture');
  String get playbackModeRenderFirst => _s('playbackModeRenderFirst');
  String get playbackStop => _s('playbackStop');

  /// The frames a run did not show, in the slot left of its play button
  /// (T29) — said as the mode that skips them is named.
  String playbackDroppedCount(int count) =>
      _count('playbackDroppedCount', count);

  /// The sounds a run plays without, in the same slot as the drops
  /// (playback-says-the-sound-it-cannot-play, 유저 2026-10-17: 「재생 중 재생
  /// 버튼 줄 맨 앞에 빨간 경고 문구」).
  String playbackSilentCount(int count) =>
      _count('playbackSilentCount', count);

  /// The meter's seat, red, when the output would not open.
  String get playbackOutputRefused => _s('playbackOutputRefused');

  /// Why a sound cannot be played — the tooltip on its red cell.
  String soundCannotPlay(SoundCannotPlay why) =>
      _s('soundCannotPlay.${why.name}');
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
  String get commonMinutesShort => _s('commonMinutesShort');

  // --- The export window ---
  String get exExport => _s('exExport');
  String get exAddToQueue => _s('exAddToQueue');
  String get exImage => _s('exImage');
  String get exVideo => _s('exVideo');
  String get exCels => _s('exCels');
  String get exFormat => _s('exFormat');
  String get exOptions => _s('exOptions');
  String get exNaming => _s('exNaming');
  String get exScope => _s('exScope');
  String get exQuality => _s('exQuality');
  String get exCodec => _s('exCodec');
  String get exBitrate => _s('exBitrate');
  String get exChannels => _s('exChannels');
  String get exAudio => _s('exAudio');
  String get exHandOverDeclined => _s('exHandOverDeclined');
  String get exHandOverPending => _s('exHandOverPending');
  String get exHandOverPickAgain => _s('exHandOverPickAgain');
  String get exHandOverDiscard => _s('exHandOverDiscard');
  String get exSavePreset => _s('exSavePreset');
  String get exPresetNameEmpty => _s('exPresetNameEmpty');
  String get exBaseName => _s('exBaseName');
  String get exSuffix => _s('exSuffix');
  String get exPrefix => _s('exPrefix');

  /// The Cels list's band: what is laid over the drawing shown (F-289).
  String get exLayDirection => _s('exLayDirection');

  /// The pill that lays the cut's guides over it (I-105).
  String get exLayGuides => _s('exLayGuides');
  String get exCelFormat => _s('exCelFormat');
  String get exTimesheetFormat => _s('exTimesheetFormat');
  String get exEnvelopeFormat => _s('exEnvelopeFormat');

  /// Why a drawing of the Cels list is no file as things stand — said at
  /// the pointer when its block is pressed (유저 2026-10-06: 「나갈 수 없는
  /// 그림은 작동하려하면 이유 띄우자」).
  String get noticeExportNoPicture => _s('noticeExportNoPicture');
  String get noticeExportNotPlaced => _s('noticeExportNotPlaced');
  String get noticeExportSameName => _s('noticeExportSameName');
  String get exDigits => _s('exDigits');
  String get exApplyLayerFx => _s('exApplyLayerFx');
  String get exMuxSeMix => _s('exMuxSeMix');
  String get exLabel => _s('exLabel');
  String get exApply => _s('exApply');
  String get exKinds => _s('exKinds');
  String get exLayerFilter => _s('exLayerFilter');
  String get exSelBase => _s('exSelBase');
  String get exCelsLayersOut => _s('exCelsLayersOut');
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
  String exCelCount(int count) => _count('exCelCount', count);

  String get exProject => _s('exProject');
  String get exCut => _s('exCut');
  String get exWhite => _s('exWhite');
  String get exBlack => _s('exBlack');
  String get exBackground => _s('exBackground');
  String get exStratumPaper => _s('exStratumPaper');
  String get exStratumForm => _s('exStratumForm');
  String get exStratumContent => _s('exStratumContent');
  String get exStratumPicture => _s('exStratumPicture');
  String get exStratumInk => _s('exStratumInk');
  String get exLeftOutOfTheFile => _s('exLeftOutOfTheFile');
  String get exNoCels => _s('exNoCels');
  String get exNoCuts => _s('exNoCuts');
  String get exPresets => _s('exPresets');
  String get exQueue => _s('exQueue');
  String get exSize => _s('exSize');

  /// The paper a cut envelope is written on: the cut's own pixels, or the
  /// real envelope's.
  String get exCutSize => _s('exCutSize');
  String get exRealSheet => _s('exRealSheet');

  /// A count said with its noun: `<key>One` at one, `<key>` otherwise — a
  /// language whose noun does not change simply says the same word twice.
  ///
  /// ⛔ONE RULE FOR EVERY COUNT (F-124, 2026-09-16). The export window glued
  /// an English `s` onto nine nouns through its own `_plural`, which no other
  /// language can use, while [exCelCount] had written the table's version out
  /// on its own.
  String _count(String key, int count) =>
      (count == 1 ? _s('${key}One') : _s(key)).replaceFirst('{n}', '$count');

  /// The export window's counts. The noun carries the export's kind where the
  /// finished sentence names one — 「3 sheet pages」, not 「3 pages」.
  String exFrameCount(int count) => _count('exFrameCount', count);
  String exPageCount(int count) => _count('exPageCount', count);
  String exFileCount(int count) => _count('exFileCount', count);

  /// How many files the Cels tab writes, said over its list: a cel, a page
  /// of a timesheet and a cut envelope are counted alike — in sheets, where
  /// the language counts them so (장 · 枚 · 张).
  String exWrittenCount(int count) => _count('exWrittenCount', count);
  String exJobCount(int count) => _count('exJobCount', count);
  String exContePageCount(int count) => _count('exContePageCount', count);

  /// How an export ends — the status line's sentences, each taking a count
  /// already said with its noun. ⚠️A name or a cut goes in LAST: it is the
  /// user's text, and a brace in it must not be read as a placeholder.
  String exCancelledAfter(String count) =>
      _s('exCancelledAfterTemplate').replaceAll('{count}', count);
  String exCancelledVideo(String count) =>
      _s('exCancelledVideoTemplate').replaceAll('{count}', count);
  String get exCancelled => _s('exCancelled');
  String exDone(String count) =>
      _s('exDoneTemplate').replaceAll('{count}', count);
  String exDoneSkipped(String count, int skipped) => _s(
    'exDoneSkippedTemplate',
  ).replaceAll('{skipped}', '$skipped').replaceAll('{count}', count);
  String exDoneFile(String name) =>
      _s('exDoneFileTemplate').replaceAll('{name}', name);
  String exDoneVideo(String count) =>
      _s('exDoneVideoTemplate').replaceAll('{count}', count);
  String exDoneConteDocument(String name, String count) => _s(
    'exDoneConteDocumentTemplate',
  ).replaceAll('{name}', name).replaceAll('{count}', count);
  String get exNothingInFrame => _s('exNothingInFrame');
  String exFailed(Object error) =>
      _s('exFailedTemplate').replaceAll('{error}', '$error');
  String exQueueRest(String count, {required int failed, required bool kept}) =>
      _s('exQueueRestTemplate')
          .replaceAll(
            '{failed}',
            failed > 0
                ? _s('exQueueFailedTemplate').replaceAll('{n}', '$failed')
                : '',
          )
          .replaceAll('{rest}', kept ? _s('exQueueRestKept') : '')
          .replaceAll('{count}', count);


  /// The file bar's words and the modules' one-line summaries.
  String get exFileLabel => _s('exFileLabel');
  /// The order an export takes on this machine, said beside its button —
  /// 🗣️F-221 (유저 2026-10-06): 「ios : 출력한 후 위치를 지정합니다 이런식으로
  /// os별로 어떻게 동작하는지 적어두고싶어. 그럼 알기쉬우니까」 · 「윈도우 :
  /// 위치를 지정하고 출력합니다 이런식으로 써주도록?」. ⚠️The one line of
  /// explanation this window carries: the user asked for it by name.
  String get exOrderAsksFirst => _s('exOrderAsksFirst');
  String get exOrderAsksAfter => _s('exOrderAsksAfter');
  String exSeMuxed(String codec) =>
      _s('exSeMuxedTemplate').replaceAll('{codec}', codec);
  String get exVectorPdf => _s('exVectorPdf');
  String get exFxOn => _s('exFxOn');
  String get exFxOff => _s('exFxOff');
  String get exFxBasic => _s('exFxBasic');
  String get exFxBasicOnly => _s('exFxBasicOnly');

  /// The rails: the tab names the presets say, the render queue and its jobs,
  /// the cut grid, and why a format cannot be picked here.
  String get exTabSequence => _s('exTabSequence');
  String get exSizeCamera => _s('exSizeCamera');
  String get exSizeCanvas => _s('exSizeCanvas');
  String get exPageImage => _s('exPageImage');
  String get exSaveCurrent => _s('exSaveCurrent');
  String get exRenderQueue => _s('exRenderQueue');
  String get exRenderAll => _s('exRenderAll');
  String get exJobQueued => _s('exJobQueued');
  String get exJobDone => _s('exJobDone');
  String get exJobFailed => _s('exJobFailed');
  String get exJobCancelled => _s('exJobCancelled');
  String exJob(int id, String tab) =>
      _s('exJobTemplate').replaceAll('{id}', '$id').replaceAll('{tab}', tab);
  String get exIncludeAll => _s('exIncludeAll');
  String exCutsIncluded(int included, int total) => _s(
    'exCutsIncludedTemplate',
  ).replaceAll('{n}', '$included').replaceAll('{total}', '$total');
  String get exNeedsFfmpeg => _s('exNeedsFfmpeg');
  String get exCheckingEncoders => _s('exCheckingEncoders');
  String get exNotInThisBuild => _s('exNotInThisBuild');
  String get exBitrateAuto => _s('exBitrateAuto');

  /// The size pills' canvas row, filled at the call site the way
  /// [exCameraTemplate] beside it is.
  String get exCanvasTemplate => _s('exCanvasTemplate');
  String get exCanvasPerCut => _s('exCanvasPerCut');

  /// The import window's own words. ⚠️Cancel · Resize · Name · Timeline are
  /// NOT here — they are `commonCancel`, `commonResize`, `commonNameField`
  /// and `panelTimeline`, which already say them.
  String get imImport => _s('imImport');
  String get imFile => _s('imFile');
  String get imInto => _s('imInto');
  String get imFit => _s('imFit');

  /// The file table's columns — 「size」 here is a file's BYTES, which is a
  /// different question from the export's pixel [exSize]; a file's pixels
  /// are its [imResolution] (F-375).
  String get imModified => _s('imModified');
  String get imSize => _s('imSize');
  String get imResolution => _s('imResolution');

  /// Where what a cut folder leaves out goes: nowhere — the 넣을 곳 of the
  /// row that names it (F-429).
  String get imExcluded => _s('imExcluded');

  /// A cut folder's 넣을 곳: the folder lands as ONE cut, every row a new
  /// layer of it (F-429-Q1).
  String get imFolderAsOneCut => _s('imFolderAsOneCut');

  /// A cut folder's 넣을 곳: each row where its own 넣을 곳 says — a new layer
  /// of the open cut, or a cut of its own (F-429-Q1).
  String get imFolderPerRow => _s('imFolderPerRow');

  /// The placement strip and the window's title when it places one file, and
  /// the words for a pill that cannot be used from where the window opened.
  String imPlaceTitle(String name) =>
      _s('imPlaceTitleTemplate').replaceAll('{name}', name);

  /// The file table's answers. The file column is the POOL's question
  /// (carry or link) and bake is the LAYER's (user 2026-09-11, round 5).
  String get imModeKeep => _s('imModeKeep');
  String get imModeReference => _s('imModeReference');
  String get imBake => _s('imBake');
  String get imOptions => _s('imOptions');
  String get imPictureAndSound => _s('imPictureAndSound');
  String get imPictureOnly => _s('imPictureOnly');
  String get imSoundOnly => _s('imSoundOnly');
  String imRunSpan(String first, String last, int count) => _s(
    'imRunSpanTemplate',
  )
      .replaceAll('{first}', first)
      .replaceAll('{last}', last)
      .replaceAll('{n}', '$count');
  String imRateTitle({required String movie, required String project}) => _s(
    'imRateTitleTemplate',
  ).replaceAll('{movie}', movie).replaceAll('{project}', project);
  String imRateBody(String movie) =>
      _s('imRateBodyTemplate').replaceAll('{movie}', movie);
  String imRateKeep(String project) =>
      _s('imRateKeepTemplate').replaceAll('{project}', project);
  String imRateTake(String movie) =>
      _s('imRateTakeTemplate').replaceAll('{movie}', movie);
  String get commonOn => _s('commonOn');
  String get commonOff => _s('commonOff');
  String get imFitOriginal => _s('imFitOriginal');
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

  /// What the file doors say themselves — the refusals an open can end in,
  /// the picture a cel could not read, and the two the .tvpp door adds to a
  /// converted project's notice.
  String get imNotTvpp => _s('imNotTvpp');
  String get imNotClip => _s('imNotClip');

  /// What an import's warnings notice opens with, over the lists of what
  /// did not come in (F-370) — a converted project's on the Open door, the
  /// import window's run or pick alike (F-370-Q1).
  String get imLeftBehind => _s('imLeftBehind');
  String get imFileUnreadable => _s('imFileUnreadable');
  String imNotFound(String path) =>
      _s('imNotFoundTemplate').replaceAll('{path}', path);

  /// The import window's last line when a run or a pick left warnings: the
  /// button their notice opens from (F-370-Q1, 유저 2026-10-17: 「끝 줄을
  /// 「경고 N가지」 버튼으로」), counting every warning.
  String imWarningCount(int count) => _count('imWarningCount', count);

  /// What the window says about its source and its run.
  String get imNoSource => _s('imNoSource');
  String imFileCount(int count) =>
      _s('imFileCountTemplate').replaceAll('{n}', '$count');
  String get imStatusImporting => _s('imStatusImporting');
  String get imStatusNothing => _s('imStatusNothing');
  String get imStatusDone => _s('imStatusDone');

  /// The stretch of a run the wait window's line names while it reports
  /// (F-494): a trimmed movie's piece encoded again, another kind's span
  /// written out, a file's bytes carried in, its cels rasterized.
  String get imStepRecoding => _s('imStepRecoding');
  String get imStepWritingSpan => _s('imStepWritingSpan');
  String get imStepCarrying => _s('imStepCarrying');
  String get imStepRasterizing => _s('imStepRasterizing');
  String get imFolderGone => _s('imFolderGone');
  String imFolderUnreadable(String reason) =>
      _s('imFolderUnreadableTemplate').replaceAll('{reason}', reason);
  String get imCutFolderUnreadable => _s('imCutFolderUnreadable');
  String imUnreadable(String name) =>
      _s('imUnreadableTemplate').replaceAll('{name}', name);

  /// A file let go on a reference row that reads, and holds no picture
  /// [number] — the one a cel of the row shows, counted from 1 (I-68 「가」).
  String imLacksPicture(String name, int number) =>
      _s('imLacksPictureTemplate')
          .replaceAll('{name}', name)
          .replaceAll('{number}', '$number');
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

  /// The cut-folder column's words.
  String get imKeepExplain => _s('imKeepExplain');
  String get imReferenceExplain => _s('imReferenceExplain');

  /// The media pool's states and its rename prompt.
  String get mpFileMissing => _s('mpFileMissing');
  String get mpInUseOnTimeline => _s('mpInUseOnTimeline');
  String get mpNameEmpty => _s('mpNameEmpty');

  /// '{size}' is the camera frame's pixel size, as `pixelSizeLabel` spells
  /// every one.
  String get exCameraTemplate => _s('exCameraTemplate');

  /// '{name}' is the current layer-group label.

  // --- Tools, the brush library and its settings ---
  String get toolBrush => _s('toolBrush');
  String get toolEraser => _s('toolEraser');
  String get toolEyedropper => _s('toolEyedropper');
  String get toolFill => _s('toolFill');
  String get toolText => _s('toolText');
  String get toolShape => _s('toolShape');

  // The text tool's settings (R9-rest) — the rows of the layout 유저 took
  // on 2026-10-06.
  String get textToolSelectedText => _s('textToolSelectedText');
  String get textToolDeleteText => _s('textToolDeleteText');
  String get textToolLetters => _s('textToolLetters');
  String get textToolBox => _s('textToolBox');
  String get textToolFont => _s('textToolFont');
  String get textToolSize => _s('textToolSize');
  String get textToolTracking => _s('textToolTracking');
  String get textToolBold => _s('textToolBold');
  String get textToolItalic => _s('textToolItalic');
  String get textToolUnderline => _s('textToolUnderline');
  String get textToolStrikethrough => _s('textToolStrikethrough');
  String get textToolColor => _s('textToolColor');
  String get textToolOutline => _s('textToolOutline');
  String get textToolOutlineWidth => _s('textToolOutlineWidth');
  String get textToolAlign => _s('textToolAlign');
  String get textToolAlignLeft => _s('textToolAlignLeft');
  String get textToolAlignCenter => _s('textToolAlignCenter');
  String get textToolAlignRight => _s('textToolAlignRight');
  String get textToolCentreAcross => _s('textToolCentreAcross');
  String get textToolCentreDown => _s('textToolCentreDown');
  String get textToolBoxWidth => _s('textToolBoxWidth');
  String get textToolWidthAuto => _s('textToolWidthAuto');
  String get textToolWidthFixed => _s('textToolWidthFixed');
  String get textToolLineHeight => _s('textToolLineHeight');
  String get textToolLetterWidth => _s('textToolLetterWidth');
  String get textToolSkew => _s('textToolSkew');
  String get textToolBackground => _s('textToolBackground');
  String get textToolIntoDrawing => _s('textToolIntoDrawing');
  String get textToolWriting => _s('textToolWriting');
  String get textToolWritingLines => _s('textToolWritingLines');
  String get textToolWritingColumns => _s('textToolWritingColumns');
  String get textToolAlignTop => _s('textToolAlignTop');
  String get textToolAlignBottom => _s('textToolAlignBottom');

  /// The ＋ over the list of faces, and a brought face's own delete.
  String get textToolFontImport => _s('textToolFontImport');
  String get textToolFontDelete => _s('textToolFontDelete');

  /// The two groups of the list of faces beside the app's own — the fonts
  /// the project on screen carries, and the ones this device was brought —
  /// and the taking of a font out of the project.
  String get textToolFontsOfProject => _s('textToolFontsOfProject');
  String get textToolFontsOfDevice => _s('textToolFontsOfDevice');
  String get textToolFontTakeOut => _s('textToolFontTakeOut');

  /// ⚠️WARNINGS, written at the face they are about (유저 2026-10-06: 「이
  /// 글꼴은 편집하는 문서에 넣도록 허용되지않아서 다른 기기에서 열면 바뀐다
  /// 이런식으로 적어두자」): a face its maker does not let ride in a project,
  /// and a face a text is written in that this device does not hold.
  String get textToolFontStaysOnThisDevice =>
      _s('textToolFontStaysOnThisDevice');
  String get textToolFontNotOnThisDevice => _s('textToolFontNotOnThisDevice');

  /// A font file opened or dropped like any other file (F-282) went into
  /// this device's fonts — said, because nothing on screen shows it.
  String fontBrought(String family) =>
      _s('fontBroughtTemplate').replaceAll('{family}', family);

  /// Why a picked file was not taken as a font.
  String get textToolFontUnreadable => _s('textToolFontUnreadable');
  String get textToolFontIsTheApps => _s('textToolFontIsTheApps');
  String get textToolFontNotKept => _s('textToolFontNotKept');

  String get toolSelect => _s('toolSelect');
  String get toolTransform => _s('toolTransform');
  String get toolShapeFill => _s('toolShapeFill');
  String get toolCutNothingHeld => _s('toolCutNothingHeld');
  String get toolCutHoldingTemplate => _s('toolCutHoldingTemplate');
  String get toolLibraryEmpty => _s('toolLibraryEmpty');
  String get toolCutPasteAtOrigin => _s('toolCutPasteAtOrigin');
  String get toolCutFlipHorizontal => _s('toolCutFlipHorizontal');
  String get toolCutFlipVertical => _s('toolCutFlipVertical');
  String get toolCutRegisterTip => _s('toolCutRegisterTip');
  String get toolCutDeletesSource => _s('toolCutDeletesSource');
  String get toolReadSource => _s('toolReadSource');
  String get toolReadsEveryVisibleLayer => _s('toolReadsEveryVisibleLayer');
  String get brushSettingsTitle => _s('brushSettingsTitle');
  String get toolShapeRect => _s('toolShapeRect');
  String get toolShapeEllipse => _s('toolShapeEllipse');
  String get toolShapeLasso => _s('toolShapeLasso');
  String get toolShapePolygon => _s('toolShapePolygon');
  String get toolShapeLine => _s('toolShapeLine');
  String get toolShapeSelectTemplate => _s('toolShapeSelectTemplate');
  String get toolShapeCutTemplate => _s('toolShapeCutTemplate');
  String get toolShapeFillTemplate => _s('toolShapeFillTemplate');
  String get toolShapeDrawTemplate => _s('toolShapeDrawTemplate');
  String get shapeToolDraws => _s('shapeToolDraws');
  String get shapeToolStroke => _s('shapeToolStroke');
  String get shapeToolFill => _s('shapeToolFill');
  String get shapeToolType => _s('shapeToolType');
  String get shapeToolTypePlain => _s('shapeToolTypePlain');
  String get shapeToolCorners => _s('shapeToolCorners');
  String get shapeToolCornersSharp => _s('shapeToolCornersSharp');
  String get shapeToolCornersRound => _s('shapeToolCornersRound');
  String get shapeToolRatioLock => _s('shapeToolRatioLock');
  /// A built-in brush's or group's name, by its `builtin-*` id — written ONCE,
  /// when the library makes the built-ins. 유저 2026-09-15
  /// (brush-preset-names-language-Q1): 「만들 때 그 언어로 적는다」. From then
  /// on it is stored text like any renamed brush, so switching the language
  /// renames nothing. No `en` rows: the English is the defaults' own.
  ///
  /// ja takes Clip Studio's names where a brush is modelled on one (Gペン ·
  /// 丸ペン · カブラペン · ミリペン), and Photoshop's for the two rounds it
  /// ships (ハード円ブラシ · ソフト円ブラシ). Names with no settled art-supply
  /// term in a language (Grit Spray, Water Blend) are rendered
  /// from the English, and are the first a translator may refine.
  String builtinBrushName(String id, String fallback) =>
      _values['builtinBrush.$id'] ?? fallback;

  /// A built-in TIP's name, by its mask id — the same contract. The tips are
  /// generated and never stored, so theirs is made at every launch.
  String builtinTipName(String id, String fallback) =>
      _values['builtinTip.$id'] ?? fallback;

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
  String get brMixingMethod => _s('brMixingMethod');
  String get brMixingMix => _s('brMixingMix');
  String get brMixingBlur => _s('brMixingBlur');
  String get brPaintAmount => _s('brPaintAmount');
  String get brPaintDensity => _s('brPaintDensity');
  String get brColorStretch => _s('brColorStretch');
  String get brHardness => _s('brHardness');
  String get stepUp => _s('stepUp');
  String get stepDown => _s('stepDown');
  String get brEdgeNone => _s('brEdgeNone');
  String get brSpacing => _s('brSpacing');
  String get brAngle => _s('brAngle');
  String get brRoundness => _s('brRoundness');
  String get brScale => _s('brScale');
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
  String brDeleteTipBody(String name) =>
      _s('brDeleteTipBodyTemplate').replaceAll('{name}', name);
  String get brTipRotation => _s('brTipRotation');
  String get brRotationFixed => _s('brRotationFixed');
  String get brRotationDirection => _s('brRotationDirection');
  String get brRotationPenTilt => _s('brRotationPenTilt');
  String get brRotationPenTwist => _s('brRotationPenTwist');
  String get brTipOrder => _s('brTipOrder');
  String get brTipOrderRepeat => _s('brTipOrderRepeat');
  String get brTipOrderPingPong => _s('brTipOrderPingPong');
  String get brTipOrderHoldLast => _s('brTipOrderHoldLast');
  String get brTipOrderRandom => _s('brTipOrderRandom');
  String get brTipOrderOneLap => _s('brTipOrderOneLap');
  String get brTipOrderShuffledLap => _s('brTipOrderShuffledLap');
  String get brTipOrderLean => _s('brTipOrderLean');
  String get brTipsPerTurn => _s('brTipsPerTurn');
  String get brStabilizer => _s('brStabilizer');
  String get brStabilizerOn => _s('brStabilizerOn');
  String get brStabilizerBySpeed => _s('brStabilizerBySpeed');
  String get brBySpeedSlow => _s('brBySpeedSlow');
  String get brBySpeedFast => _s('brBySpeedFast');
  String get brPostCorrection => _s('brPostCorrection');
  String get brPostBySpeed => _s('brPostBySpeed');
  String get brPostByViewScale => _s('brPostByViewScale');
  String get brPostBezier => _s('brPostBezier');
  String get brSharpenCorners => _s('brSharpenCorners');
  String get brGroupInk => _s('brGroupInk');
  String get brGroupTip => _s('brGroupTip');
  String get brGroupMixing => _s('brGroupMixing');
  String get brGroupScattering => _s('brGroupScattering');
  String get brGroupTexture => _s('brGroupTexture');
  String get brGroupCorrection => _s('brGroupCorrection');
  String get brDetailTitle => _s('brDetailTitle');
  String get brShowInPanel => _s('brShowInPanel');
  String get brHideFromPanel => _s('brHideFromPanel');

  String get brBlend => _s('brBlend');
  String get brBlendMode => _s('brBlendMode');
  String get brDualBlend => _s('brDualBlend');
  String get brTextureMode => _s('brTextureMode');
  String get brTextureModeHeight => _s('brTextureModeHeight');
  String get brEditGroup => _s('brEditGroup');
  String get brFolderIcon => _s('brFolderIcon');
  String get brFolderName => _s('brFolderName');
  String get brFeather => _s('brFeather');
  String get brTolerance => _s('brTolerance');
  String get brGapClose => _s('brGapClose');
  String get brGrowShrink => _s('brGrowShrink');
  String get brAntiAlias => _s('brAntiAlias');
  String get brFillBeyondCanvas => _s('brFillBeyondCanvas');
  String get brOpenRegionsRefuse => _s('brOpenRegionsRefuse');
  String get brName => _s('brName');
  String get brDisplay => _s('brDisplay');
  String get brTipIcon => _s('brTipIcon');
  String get brStrokePreview => _s('brStrokePreview');
  String get brBrushOptions => _s('brBrushOptions');
  String get brNewGroup => _s('brNewGroup');
  /// What a new group and a new brush are called when they are made — the
  /// built-ins' rule (brush-preset-names-language-Q1). `{n}` is the number
  /// that keeps a new brush's name free.
  String get brNewGroupName => _s('brNewGroupName');
  String get brNewPresetName => _s('brNewPresetName');
  String get brRenameGroup => _s('brRenameGroup');
  String get brDeleteGroup => _s('brDeleteGroup');

  /// The question 「delete this group」 asks: of an empty group, or of one
  /// with [brushes] inside it, which go with it.
  String brDeleteGroupBody(String name, int brushes) =>
      (brushes == 0
              ? _s('brDeleteEmptyGroupTemplate')
              : _count('brDeleteGroupTemplate', brushes))
          .replaceAll('{name}', name);
  String get brRenameSelected => _s('brRenameSelected');
  String get brDeleteSelected => _s('brDeleteSelected');
  String get brSaveAsPreset => _s('brSaveAsPreset');
  String get brImportBrushes => _s('brImportBrushes');
  String get brResetLibrary => _s('brResetLibrary');
  String get brExportSelected => _s('brExportSelected');
  String get brExportGroup => _s('brExportGroup');
  String get brExportNothing => _s('brExportNothing');
  String fileExportPlaceUnchosen(Object error) =>
      _s('fileExportPlaceUnchosenTemplate').replaceAll('{error}', '$error');

  /// A settings file (I-142) — one palette's, one shortcut preset's — and
  /// what came of writing it.
  String settingsExported(String name) =>
      _s('settingsExportedTemplate').replaceAll('{name}', name);
  String settingsExportNotWritten(Object error) =>
      _s('settingsExportNotWrittenTemplate').replaceAll('{error}', '$error');

  /// The preferences window's 「설정 전부 내보내기」 (I-142-Q1), and the name
  /// its file is offered under.
  String get settingsExportAll => _s('settingsExportAll');
  String get settingsAllFileName => _s('settingsAllFileName');

  /// A settings file's rows in the import window (I-142-Q6 · Q9): the two
  /// settings no window of their own names, the Into answer that puts a row
  /// in place, what that costs, and a row this build cannot read.
  String get settingsRowFrameCount => _s('settingsRowFrameCount');
  String get settingsRowWorkspaceLayout => _s('settingsRowWorkspaceLayout');
  String get imIntoSettings => _s('imIntoSettings');
  String get imSettingsGoInPlace => _s('imSettingsGoInPlace');
  String get imSettingsUnreadable => _s('imSettingsUnreadable');
  String brExportNotWritten(Object error) =>
      _s('brExportNotWrittenTemplate').replaceAll('{error}', '$error');
  String brExportedOne(String name) =>
      _s('brExportedOneTemplate').replaceAll('{name}', name);
  String brExportedMany(int count) =>
      _s('brExportedManyTemplate').replaceAll('{count}', '$count');

  /// The file's name when the brushes exported are no one group's.
  String get brExportFallbackName => _s('brExportFallbackName');
  String get brImportUnreadable => _s('brImportUnreadable');
  String brImportPickFailed(Object error) =>
      _s('brImportPickFailedTemplate').replaceAll('{error}', '$error');
  String brImported(int count, String file) =>
      _s(count == 1 ? 'brImportedOneTemplate' : 'brImportedManyTemplate')
          .replaceAll('{count}', '$count')
          .replaceAll('{file}', file);
  String brImportWarnings(String summary, int count) =>
      _s('brImportWarningsTemplate')
          .replaceAll('{summary}', summary)
          .replaceAll('{count}', '$count');
  String get brTipUnreadable => _s('brTipUnreadable');
  String get brTipNoShape => _s('brTipNoShape');
  String get brTipNotSaved => _s('brTipNotSaved');
  String get brExpand => _s('brExpand');
  String get trFlipHorizontal => _s('trFlipHorizontal');
  String get trFlipVertical => _s('trFlipVertical');
  String get trPosition => _s('trPosition');
  String get trScale => _s('trScale');
  String get trScaleLink => _s('trScaleLink');
  String get trRotation => _s('trRotation');
  String get trAnchorPoint => _s('trAnchorPoint');
  String get trMeshColumns => _s('trMeshColumns');
  String get trMeshRows => _s('trMeshRows');
  String get trMesh => _s('trMesh');
  String get trFinish => _s('trFinish');
  String get commonReset => _s('commonReset');

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
  String get valueTypeIn => _s('valueTypeIn');
  String get viewCanvasColor => _s('viewCanvasColor');
  String get viewPasteboardColor => _s('viewPasteboardColor');
  String get pasteboardTitle => _s('pasteboardTitle');
  String get pasteboardInUse => _s('pasteboardInUse');
  String get pasteboardNotInUse => _s('pasteboardNotInUse');
  String get viewBackdropColor => _s('viewBackdropColor');
  String get colorUseCurrent => _s('colorUseCurrent');
  String get colorNone => _s('colorNone');
  String get colorPresent => _s('colorPresent');

  // --- The layer-controls header (column toggles, solo, section fold) ---
  String get tlSections => _s('tlSections');
  String get tlAllDisplayedLayers => _s('tlAllDisplayedLayers');
  String get tlShowAll => _s('tlShowAll');
  String get tlHideAll => _s('tlHideAll');
  String get tlSoloKind => _s('tlSoloKind');
  String get tlSoloColor => _s('tlSoloColor');
  String get tlSoloClips => _s('tlSoloClips');
  String get tlSoloFxOnRows => _s('tlSoloFxOnRows');
  String get tlSoloSheetOnRows => _s('tlSoloSheetOnRows');
  String get tlApplyAllFx => _s('tlApplyAllFx');
  String get tlBypassAllFx => _s('tlBypassAllFx');
  String get tlAllOnTimesheet => _s('tlAllOnTimesheet');
  String get tlAllOffTimesheet => _s('tlAllOffTimesheet');
  String get tlClearMarkFilter => _s('tlClearMarkFilter');
  String get tlClearAllClips => _s('tlClearAllClips');
  String get tlColVisibility => _s('tlColVisibility');
  String get tlColLayerKind => _s('tlColLayerKind');
  String get tlColOnionSkin => _s('tlColOnionSkin');
  String get tlColOpacity => _s('tlColOpacity');
  String get tlColBlendMode => _s('tlColBlendMode');
  String get tlColFx => _s('tlColFx');
  String get tlColMark => _s('tlColMark');
  String get tlColClip => _s('tlColClip');
  String get tlColTimesheet => _s('tlColTimesheet');
  String get tlShowXSheet => _s('tlShowXSheet');
  String get tlShowTimeline => _s('tlShowTimeline');
  String get cameraViewOn => _s('cameraViewOn');
  String get cameraViewOff => _s('cameraViewOff');
  String get tlOpenOnionPanel => _s('tlOpenOnionPanel');
  String get tlApplyOnionToDisplayed => _s('tlApplyOnionToDisplayed');
  String get tlClearOnionOnDisplayed => _s('tlClearOnionOnDisplayed');
  String get tlOnionOnDisplayedToggle => _s('tlOnionOnDisplayedToggle');
  String get tlCollapseAllLayers => _s('tlCollapseAllLayers');
  String get tlExpandAllLayers => _s('tlExpandAllLayers');

  // The rail row's controls (rail-subject-tooltips): one whole sentence per
  // control, state and row. ⛔Never a noun slotted into a template — French
  // contracts it into its article (« du calque », « de la piste ») and
  // Japanese hangs a particle on it, so no one template reads right in all
  // five languages.
  String get railLayerBlendMode => _s('railLayerBlendMode');
  String get railFolderBlendMode => _s('railFolderBlendMode');
  String get railHideLayer => _s('railHideLayer');
  String get railShowLayer => _s('railShowLayer');
  String get railBypassLayerFx => _s('railBypassLayerFx');
  String get railApplyLayerFx => _s('railApplyLayerFx');
  String get railBypassMixedLayerFx => _s('railBypassMixedLayerFx');
  String get railBypassTrackFx => _s('railBypassTrackFx');
  String get railApplyTrackFx => _s('railApplyTrackFx');
  String get railRemoveFromTimesheet => _s('railRemoveFromTimesheet');
  String get railAddToTimesheet => _s('railAddToTimesheet');
  String get railCollapseLanes => _s('railCollapseLanes');
  String get railExpandLanes => _s('railExpandLanes');
  String get railOnionSkinOn => _s('railOnionSkinOn');
  String get railOnionSkin => _s('railOnionSkin');
  String get railLaneGraphOn => _s('railLaneGraphOn');
  String get railLaneGraph => _s('railLaneGraph');
  String get railLanePinOn => _s('railLanePinOn');
  String get railLanePin => _s('railLanePin');
  String get laneGraphValue => _s('laneGraphValue');
  String get laneGraphSpeed => _s('laneGraphSpeed');
  String get laneGraphEnlarge => _s('laneGraphEnlarge');
  String get laneGraphEnlargeOn => _s('laneGraphEnlargeOn');
  String get laneGraphPen => _s('laneGraphPen');
  String get laneGraphPenOn => _s('laneGraphPenOn');
  String get laneGraphTransformBox => _s('laneGraphTransformBox');
  String get laneGraphTransformBoxOn => _s('laneGraphTransformBoxOn');
  String get railClipOn => _s('railClipOn');
  String get railClip => _s('railClip');
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


  // --- Timeline toolbar prompts ---
  String get setLengthAction => _s('setLengthAction');

  /// I-58: how many koma apart the ● goes down a block.
  String get markEveryField => _s('markEveryField');

  /// I-24: the two ways a count of frames is typed (`FrameCountField`).
  String get frameCountEntryFrames => _s('frameCountEntryFrames');
  String get frameCountEntrySecondsPlusFrames =>
      _s('frameCountEntrySecondsPlusFrames');

  /// 자동 이름 지정's one field (I-18): the number the first block takes.
  String get autoNameStartField => _s('autoNameStartField');
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
    'launchStageEngine': 'Starting engine',
    'launchStagePlugins': 'Registering plugins',
    'launchStageApp': 'Preparing app',
    'launchStageFirstFrame': 'Drawing first screen',
    'launchNoticeTitle': 'About this build',
    'launchNoticeDontShowAgain': "Don't show again",
    'usageStatsSend': 'Send usage statistics',
    'usageStatsHelp':
        'When on, the app sends anonymously, when it opens, every 55 '
        'minutes while you use it and when you leave it, that it is in use '
        '— with the OS and its version, the device model, the app build and '
        'the app language. Once a day it also sends the device language, '
        'how many of the last 28 days it was used (new, 1–2, 3 or more), '
        'and four settings: the interface scale, the accent color, autosave '
        'and the cursor. Nothing that identifies you is sent: no drawings '
        'or projects, no file names, no names, not the name you gave the '
        'device. Turning it off also deletes the record kept on this '
        'device.',
    'usageStatsTitle': 'Usage statistics',
    'usageStatsAsk':
        'Send usage statistics? Turning them on helps the development of '
        'Anicel.',
    'usageStatsChangeLater':
        'You can change this any time in Preferences ▸ System.',
    'usageStatsDontSend': "Don't send",
    'usageStatsDoSend': 'Send',
    'firstRunTitle': 'Getting started',
    'firstRunChangeLater': 'You can change these any time in Preferences.',
    'firstRunStart': 'Start',
    'programLanguageLabel': 'Program language',
    'notationLanguageLabel': 'Notation language',
    'programLanguageHelp': 'Menus, panels and labels.',
    'notationLanguageHelp': 'What prints on the timesheet and exports.',
    'noCutSelected': 'No cut selected',
    'noticeNoFrameHere': 'No frame here',
    'noticeNothingToCut': 'There is nothing to cut',
    'noticeNoConteLayer': 'This cut has no storyboard layer',
    'noticeLayerNotDrawable': 'This layer cannot be drawn on',
    'noticeLayerHidden': 'This layer is hidden',
    'noticeEditAttachOwner': 'Edit the owner layer',
    'commonCancel': 'Cancel',
    'commonApply': 'Apply',
    'commonRefresh': 'Refresh',
    'commonClose': 'Close',
    'commonAffectedFiles': 'Affected files',
    'commonNotice': 'Notice',
    'tlSharedColourEdit': 'Color Edit',
    'exportNoCuts': 'This project has no cuts to export yet.',
    'exportQueueEmpty': 'No jobs queued',
    'exportPresetsEmpty': 'No presets',
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
    'recordMicPermissionDenied':
        'Microphone access is off — allow it for Anicel in Settings.',
    'recordMicNotAllowed':
        'The microphone is not allowed — turn on Preferences ▸ Audio ▸ Allow microphone.',
    'recordTakeClipped': 'The take clipped — the red corner marks the block.',
    'recordClipMarkerTooltip': 'This take clipped (recorded too hot)',
    'tlTransitionCrossingWarning': 'Crosses the cut boundary — not applied',
    'tlTransitionCutOl': 'Cut O.L',
    'audioMicGainLabel': 'Mic gain (dB)',
    'audioInputChannelLabel': 'Input channels',
    'audioInputChannelDevice': 'As device',
    'audioInputChannelMonoMix': 'Mono mix',
    'audioInputChannelLeft': 'Left only',
    'audioInputChannelRight': 'Right only',
    'audioClippingNoticeLabel': 'Clipping warnings (toast + block marker)',
    'audioDenoiseLabel': 'Noise suppression (voice only — turn off for foley)',
    'audioInputMeterLabel': 'Input level',
    'audioMicrophoneAllowedLabel': 'Allow microphone',
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
    'audioMute': 'Mute',
    'audioSolo': 'Solo',
    'fpsAudioTitleTemplate': '{from} → {to}: what happens to sound?',
    'fpsAudioBody':
        'These two rates differ by 0.1% in real speed, and audio exists in real seconds — it cannot stay both frame-exact and time-exact.\n\n• Keep audio timing: sounds keep their real seconds; their frame positions drift by 0.1% (about one frame every 42 seconds).\n\n• Pull audio 0.1%: sounds are resampled by the exact pulldown ratio (an inaudible pitch change — the standard telecine conform) so every sound keeps its exact frame span.',
    'fpsAudioKeep': 'Keep audio timing',
    'fpsAudioPull': 'Pull audio 0.1%',
    'feedbackTextOnly': 'Text only',
    'feedbackWithFiles': 'With screenshots / videos (Google sign-in)',
    'selectionClosePolygon': 'Close shape',
    'selectionInvert': 'Invert Selection Beyond Canvas',
    'selectionInvertInCanvas': 'Invert Selection in Canvas',
    'toolSelectionMode': 'Mode',
    'commonSave': 'Save',
    'commonDelete': 'Delete',
    'commonAdd': 'Add',
    'commonRename': 'Rename',
    'commonLink': 'Link',
    'commonPreview': 'Preview',
    'windowTitleTemplate': '{action} ({target})',
    'editNameAction': 'Edit name',
    'editNoteAction': 'Edit note',
    'renameLayerEmpty': 'Layer name cannot be empty.',
    'renameCutField': 'Cut name',
    'renameCutEmpty': 'Cut name cannot be empty.',
    'renameGuideTitle': 'Rename guide',
    'renameGuideField': 'Guide name',
    'renameGuideEmpty': 'Guide name cannot be empty.',
    'deleteLayerTitle': 'Delete layer',
    'deleteLayersMessage': 'Delete the layers below?',
    'deleteLayersHeading': 'Layers to delete',
    'deleteEffectsHeading': 'Effects to delete',
    'frameNameConflictTitle': 'Frame name already exists',
    'frameNameConflictBody':
        'Each frame listed takes a name another frame on its layer already '
        'uses. Link them to the frames holding those names? The same name '
        "then shares the same material, and each listed frame's drawing is "
        'discarded.',
    'linkedPasteConflictBody':
        'Each frame listed already uses a name the pasted frames '
        'carry. Link the pasted blocks to them? The same name then '
        'shares the same material: the pasted blocks show the listed '
        'frames, and the copied drawings are not brought.',
    'frameNameConflictListHeading': 'Frames to link',
    'seInstanceNewTitle': 'New SE',
    'seInstanceEditTitle': 'Edit SE',
    'seNameLabel': 'Name (speaker — blank hides the box)',
    'seTypeLabel': 'Type',
    'seDialogueLabel': 'Dialogue',
    'seDialogueOffsetLabel': 'Dialogue offset',
    'seKomaPerGlyphLabel': 'Frames per character',
    'seLinkedAudioLabel': 'Linked audio',
    'seLinkedAudioNone': 'None',
    'seUnlinkAudio': 'Unlink',
    'keySideIncoming': 'In',
    'keySideOutgoing': 'Out',
    'keyEaseInfluence': 'Influence',
    'keyPath': 'Path',
    'keyRoving': 'Roving',
    'keySideIncomingHelp':
        'How the value arrives at the key. Linear: at an even speed · Ease: slowing into it · Fast: speeding into it · Smooth: carrying the speed the keys either side set. Influence: how much of the way the change takes.',
    'keySideOutgoingHelp':
        'How the value leaves the key. Linear: at an even speed · Ease: setting off slowly · Fast: shooting off · Smooth: carrying the speed the keys either side set · Hold: staying put until the next key. Influence: how much of the way the change takes.',
    'keyPathHelp':
        'The shape of the path a position takes through the key. Linear: a corner at the key · Bezier: a handle on each side, each its own way · Continuous Bezier: the two handles in one line · Auto Bezier: a smooth bend, laid by the keys either side.',
    'keyRovingHelp':
        "The key keeps its place on the path and gives up its time: between the keys either side that keep theirs, it moves to the frame where the speed comes out even (After Effects' Rove Across Time). The first and last keys never rove.",
    'cameraPath': 'Camera path',
    'cameraPathOff': 'Off',
    'cameraPathSpace': 'Space',
    'cameraPathSpaceTime': 'Space + time',
    'cameraPathAllKeys': 'All keys',
    'cameraPathAroundPlayhead': 'Around playhead',
    'cameraPathTickEvery': 'Dots every',
    'cameraPathAround': 'Either side',
    'convertLinkedCutTitle': 'Convert to linked cut',
    'convertLinkedCutBodyTemplate':
        'Link "{cut}" (origin) with another cut. Layers with the SAME NAME '
        'become one shared picture.',
    'convertLinkedCutTargetLabel': 'Link with cut',
    'convertLinkedCutLinksHeading': 'Layers linked',
    'convertLinkedCutReplacedTemplate':
        'Same-name drawings in "{cut}" will be replaced by the '
        "origin's (원본 승리).",
    'convertLinkedCutReplacedHeading': 'Drawings replaced',
    'convertLinkedCutJoiningTemplate':
        '{count} drawing(s) join the shared set.',
    'convertLinkedCutTargetGainsHeadingTemplate': 'Added to "{cut}"',
    'convertLinkedCutOriginGainsHeading': 'Added to this cut',
    'convertLinkedCutNothing':
        'Nothing to link — the cuts are already fully linked or share no '
        'drawing layers.',
    'convertLinkedCutUndoNote':
        'Undo restores every cut the conversion touched.',
    'convertLinkedCutResizeFirst':
        'These cuts have different canvas sizes. Linked cuts share one '
        'canvas, so this cut will be resized to the origin\'s size. Undo '
        'restores it.',
    'guideKindSymmetry': 'Symmetry',
    'guideKindPerspective': 'Perspective',
    'guideDelete': 'Delete guide',
    'guideShow': 'Show on canvas',
    'guideActsOn': 'Acting on strokes',
    'guideActsOff': 'Not acting',
    'guideLibraryEmpty': 'No guides in this cut yet',
    'noGuideSelected': 'No guide selected',
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
    'guideAddVanishingPoint': 'New vanishing point',
    'guideDeleteVanishingPoint': 'Delete vanishing point',
    'guideParallel': 'Parallel',
    'guideParallelAngle': 'Angle',
    'guideLineDensity': 'Line density',
    'guideRasterize': 'Rasterize',
    'closeProjectTitle': 'Close project?',
    'untitledProjectTab': 'Untitled {n}',
    'fileOpenInAnotherTab': 'That file is already open in another tab.',
    'openNewerFormat': 'This project was saved by a newer Anicel.',
    'openOlderFormatTemplate':
        'This project is in format {saved}, older than this Anicel '
        'reads ({oldest}).',
    'closeProjectBody': 'Your changes are not saved. Close anyway?',
    'closeProjectVanishedBody':
        "This project's file is gone. Closing now takes the drawings that "
        'live only inside it. Save As writes what is still open to a new '
        'file.',
    'commonSaveAs': 'Save as',
    'saveAsTitle': 'Save as',
    'saveProgressRunning': 'Saving…',
    'saveProgressDone': 'Saved',
    'savePrepareRunning': 'Preparing…',
    'savePrepareDone': 'Ready',
    'saveStepKeepingLeftBehind': 'Setting aside the media taken out…',
    'saveStepCels': 'Writing cels…',
    'saveStepChecking': 'Checking the files to carry…',
    'saveStepMedia': 'Writing media…',
    'saveStepConforms': 'Writing the sound converted for playback…',
    'saveStepFonts': 'Writing fonts…',
    'saveStepCompacting': 'Closing up the gaps in the file…',
    'saveStepHandingBack': 'Handing the file back to its document…',
    'openProgressRunning': 'Opening…',
    'openProgressDone': 'Opened',
    'openWaitingCloudTemplate': 'Downloading from the cloud · {sec}s',
    'openWaitingStalledTemplate': 'Nothing has arrived for {sec}s',
    'resizeProgressRunning': 'Resizing…',
    'resizeProgressDone': 'Resized',
    'bakeProgressRunning': 'Rasterizing…',
    'bakeProgressDone': 'Rasterized',
    'rasterizeLeftReferences': 'Some layers were left as references.',
    'pasteProgressRunning': 'Pasting…',
    'pasteProgressDone': 'Pasted',
    'unsavedAutosaveTitle': 'Save your project',
    'unsavedAutosaveBody':
        'This project has never been saved, so autosave has nowhere to '
        'write. Pick a file and autosave will guard it from then on.',
    'commonNotNow': 'Not now',
    'topStripProject': 'Project',
    'topStripSettings': 'Settings',
    'menuPlay': 'Play',
    'menuPause': 'Pause',
    'fileOpenTitle': 'Open project',
    'fileStorageOffNotice':
        'Storage access is off — projects outside the app folder need the '
        'All-Files permission.',
    'fileOpenSettings': 'Open settings',
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
    'folderPickDriveNoticeAndroid':
        'Google Drive cannot hand over a folder. Use a folder on this device '
        '— a sync app (Autosync …) can keep a Drive folder there.',
    'recentProjectsTitle': 'Recent projects',
    'recentReconnect': 'Reconnect',
    'sortAscending': 'Ascending',
    'canvasSizeTitle': 'Canvas size',
    'cameraSizeTitle': 'Camera size',
    'canvasWidthLabel': 'Width (px)',
    'canvasHeightLabel': 'Height (px)',
    'canvasSizePresets': 'Presets',
    'canvasAdjustOnCanvas': 'Adjust on canvas',
    'cameraRatioFree': 'Free',
    'cameraRatioCurrent': 'Current',
    'commonResize': 'Resize',
    'inputPressureCurve': 'Pen pressure response',
    'inputCanvasHeading': 'Canvas',
    'inputRightClick': 'Right click / pen side button',
    'inputWheelClick': 'Wheel click / pen upper button',
    'inputPenTail': 'Pen tail (turn the pen over)',
    'inputCanvasTouchHeading': 'Canvas touch',
    'inputIgnoreTouch': 'Ignore all touch',
    'inputDragOneFinger': '1-finger drag',
    'inputDragTwoFingers': '2-finger drag',
    'inputDragThreeFingers': '3-finger drag',
    'inputExtraFinger': 'Extra-finger modifier',
    'inputExtraFingerHelp':
        'A finger added DURING a gesture constrains it — snap '
        'zoom/rotation/size, fine frame steps.',
    'inputStrokeFinger': 'Finger stroke modifier',
    'inputStrokeFingerHelp':
        'A finger resting on the screen while you draw holds the stroke to '
        'the nearest 45° — as Shift does.',
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
    'inputRotationSnap': 'Rotation snap',
    'inputZoomSnaps': 'Zoom snaps (%)',
    'inputZoomCeiling': 'Max zoom lock (%)',
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
    'memoryItemLayerImages': 'Layer images',
    'memoryItemFramePictures': 'Frame pictures',
    'memoryItemBrushTips': 'Brush tips',
    'memoryItemPanelRasters': 'Panel rasters',
    'memoryItemViewerPages': 'Viewer pages',
    'memoryItemImageCache': 'Image cache',
    'memoryItemStoryboardThumbnails': 'Storyboard thumbnails',
    'memoryItemSheetImages': 'Sheet images',
    'memoryItemTextImages': 'Text images',
    'memoryItemStrokePreviews': 'Stroke previews',
    'memoryItemTimelineTiles': 'Timeline tile images',
    'memoryItemMoviePictures': 'Reference movies',
    'memoryItemTileImages': 'Canvas tile images',
    'memoryItemEnginePool': 'Drawing engine tile pool',
    'memoryItemEngineScratch': 'Drawing engine scratch',
    'memoryOutsideAllowanceTemplate':
        'Outside the allowance, because no ceiling can be set on it: '
        '{items}.',
    'containerAreaSettings': 'Settings',
    'containerAreaDiagnostics': 'Diagnostics log',
    'containerAreaSessionScratch': 'Session scratch',
    'containerTotal': 'Total',
    'saveCelsLostTemplate':
        'Saved, but {count} drawing(s) could not be included: the project '
        'file they were stored in was removed while the project was open.',
    'saveCelsLostHeading': 'Affected drawings',
    'saveCelsLostGone': 'A drawing the project no longer has',
    'saveFailedTitle': 'Could not save',
    'saveFailedFileInUse':
        'Another program is using this file — a sync client, a virus '
        'scanner, or an app that has it open — so it could not be replaced.',
    'saveFailedReadOnly':
        'This file or its folder is read-only, so it could not be written.',
    'saveFailedDiskFull':
        'There is not enough space where this file is saved.',
    'saveFailedLocationGone':
        'The place this file is saved in cannot be reached — the drive was '
        'removed, the network dropped, or the folder was deleted.',
    'saveFailedReplaceRefused':
        'This location (a cloud or Files provider) refused to replace the '
        'file.',
    'saveFailedUnknown': 'An error occurred while writing the file.',
    'saveFailedCopyKept':
        'Your work so far is kept in a failed copy inside the app. The '
        'failed copy disappears when the program closes — to keep it, use '
        '“Back up failed copy…” and choose where.',
    'saveFailedNoCopy':
        'A failed copy could not be written either — use Save as to save '
        'somewhere else.',
    'saveFailedRetry':
        'Once the cause is gone, save again and it goes to the original '
        'file.',
    'saveFailedDetailsHeading': 'Details',
    'saveFailedCopyLineTemplate': 'Failed copy: {path}',
    'saveFailedErrorLineTemplate': 'Error: {error}',
    'failedCopyPickTitle': 'Which failed copy?',
    'failedCopyVanishOnClose':
        'Failed copies disappear when the program closes.',
    'failedCopyBackingUp': 'Backing up…',
    'failedCopyBackedUp': 'Backed up',
    'closeProjectFailedCopyBody':
        'The work this project could not save is only in its failed copy '
        'inside the app, and the failed copy disappears when the program '
        'closes. To keep it, use Save as, or “Back up failed copy…” in the '
        'File menu.',
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
    'blockFrameLinesLabel': 'Frame lines inside blocks',
    'unnamedMarkLabel': 'Mark of an unnamed block',
    'drawingCursorLabel': 'Cursor',
    'drawingCursorBrush': 'Brush',
    'drawingCursorPen': 'Pen',
    'drawingCursorCrosshair': 'Crosshair',
    'accent1Help': 'Selection, playhead, active toggles.',
    'sheetFormatTitle': 'Sheet format',
    'sheetFieldTitle': 'Title',
    'sheetFieldEpisode': 'Episode',
    'sheetFieldScene': 'Scene',
    'sheetFieldCut': 'Cut',
    'sheetFieldTime': 'Time',
    'sheetFieldName': 'Name',
    'sheetFieldSheet': 'Sheet',
    'workSettingsTitle': 'Work settings',
    'workSettingsStaff': 'Staff',
    'workLogo': 'Company logo',
    'workCover': 'Cover picture',
    'staffWorker': 'Artist',
    'sheetVisibleBoxes': 'Visible boxes',
    'sheetStretchLineAction': 'Stretch line · ACTION',
    'sheetStretchLineCell': 'Stretch line · CELL',
    'sheetStretchLineHelp':
        'Draw the line from the (N+1)th comma of N+ holds and × runs',
    'sheetStretchLineOn': 'On',
    'sheetStretchLineOff': 'Off',
    'sheetSeEmptyFill': 'Empty SE stretches',
    'sheetLength': 'Sheet length',
    'sheetThreeSeconds': '3 sec',
    'sheetSixSeconds': '6 sec',
    'sheetFillOn': 'Grayed',
    'sheetFillOff': 'Blank',
    'sheetBrushAllow': 'Allow Brush',
    'conteCoverPage': 'Cover',
    'conteBlankPage': 'Blank page',
    'conteFormatTitle': 'Conte sheet format',
    'conteFrontIn': 'Included',
    'conteFrontOut': 'Left out',
    'conteForm': 'Form',
    'conteFormAnalog': 'Analog',
    'conteFormDigital': 'Digital',
    'conteOutline': 'Black frame round pictures',
    'conteOutlineOn': 'On',
    'conteOutlineOff': 'Off',
    'envelopeFormatTitle': 'Envelope format',
    'envelopeForm': 'Form',
    'sheetModeNotation': 'Notation Sheet (repeat/hold words)',
    'sheetModeData': 'Data Sheet (as exported)',
    'instructionsTitle': 'Instructions',
    'instructionEditTooltip': 'Edit instruction',
    'instructionDeleteTooltip': 'Delete instruction',
    'instructionAddButton': 'New instruction',
    'instructionDefTitle': 'Instruction',
    'instructionDefNameLabel': 'Name (FI, PAN, …)',
    'instructionEventEditTitle': 'Edit instruction',
    'instructionEventAddTitle': 'New instruction',
    'instructionMarkLabel': 'Instruction (mark)',
    'instructionMarkNone': '(None)',
    'instructionNameLabel': 'Name (blank = instruction name)',
    'instructionStartLabel': 'Start name (A)',
    'instructionEndLabel': 'End name (B)',
    'instructionEditSetButton': 'Edit instructions',
    'instructionEditorIcon': 'Icon',
    'instructionEditorColor': 'Color',
    'instructionEditorMark': 'Mark',
    'systemStatusHelp':
        'Which implementation each subsystem is running right now. Fallback paths keep the app working but usually run slower — the names are searchable if you want the details.',
    'cutCommands': 'Cut commands',
    'cutSettingsTitle': 'Cut settings',
    'mediaActions': 'Media actions',
    'mediaPoolEmpty': 'No media',
    'mediaRename': 'Rename media',
    'mediaPlace': 'Place',
    'mediaRelink': 'Relink',
    'mediaMissingCount': '{n} media files not found',
    'mediaFindInFolder': 'Find in folder',
    'mediaRelinkFound': 'Found {m} of {n}. Relink them?',
    'mediaRelinkScanning': 'Reading that folder…',
    'mediaRelinkScanned': 'Folder read',
    'mediaRemove': 'Delete media',
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
        'It is in use. Delete it anyway? The layers and frames placed from '
        'it will be deleted.',
    'mediaUsesHeading': 'Where it is used',
    'mediaOpenInViewer': 'Open in Viewer',
    'mediaOpenInSubViewer': 'Open in Sub Viewer',
    'mediaViewerEmpty': 'Nothing to view yet',
    'mediaViewerOpenFile': 'Open File',
    'mediaViewerCloseFile': 'Close File',
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
        'Unsupported files were detected. Usable formats: {kinds}.',
    'mediaViewerSwap': 'Swap with the other viewer',
    'mediaViewerRegisterAsset': 'Add to Media',
    'panelMediaViewer': 'Viewer',
    'panelMediaViewerSub': 'Sub Viewer',
    'panelCanvas': 'Canvas',
    'panelColorWheel': 'Colour wheel',
    'transportIn': 'In',
    'transportOut': 'Out',
    'transportToStart': 'To start',
    'transportToEnd': 'To end',
    'transportLoop': 'Loop',
    'transportOnce': 'Play once',
    'transportPrevFrame': 'Previous frame',
    'transportNextFrame': 'Next frame',
    'colorRecent': 'Recent',
    'colorBackgroundSwap': 'Background colour (tap to swap)',
    'paletteViewCompact': 'Compact',
    'paletteViewCards': 'Cards',
    'paletteNew': 'New palette',
    'paletteNumberedTemplate': 'Palette {n}',
    'paletteMakeDefault': 'Make default',
    'paletteDuplicate': 'Duplicate',
    'paletteExport': 'Export',
    'paletteBroughtTemplate': 'Added the palette "{name}".',
    'paletteCopyTemplate': '{name} copy',
    'paletteDeleteTitle': 'Delete palette',
    'paletteDeleteTemplate': 'Delete the palette "{name}"?',
    'paletteRemoveCurrent': 'Remove the current colour',
    'paletteLock': 'Lock the palette',
    'paletteMore': 'More',
    'penPressureTitle': 'Pen pressure',
    'brushDynamicsTitle': 'Response',
    'curveSourcePressure': 'Pressure',
    'curveSourceTilt': 'Tilt',
    'curveSourceSpeed': 'Speed',
    'curveSourceRandom': 'Random',
    'curveMinimum': 'Min',
    'curveMaximum': 'Max',
    'curveTiltFlat': 'Flat',
    'curveTiltUpright': 'Upright',
    'onionCurrentDrawing': 'Current drawing',
    'audioLevelMeter': 'audio level meter',
    'panelColorRgb': 'RGB',
    'panelColorPalette': 'Palette',
    'panelMedia': 'Media',
    'panelOnionSkin': 'Onion skin',
    'panelToolSize': 'Tool size',
    'panelStoryboard': 'Conte',
    'panelTimeline': 'Timeline',
    'panelTimesheet': 'Timesheet',
    'panelConte': 'Conte Sheet',
    'panelEnvelope': 'Cut envelope',
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
    'onionBeforeTint': 'Before tint',
    'onionAfterTint': 'After tint',
    'onionGhostColorHelp': 'How the ghosts are colored',
    'onionPegCountHelp': 'What one peg counts',
    'onionPlacementHelp': 'Where the ghosts lie',
    'onionStepBlocks': 'Blocks',
    'onionStepBlocksDrawings': 'Blocks (drawings)',
    'onionStepFrames': 'Frames',
    'onionModeColors': 'Colors',
    'onionModeImages': 'Images',
    'onionPlacementOnTop': 'On top',
    'onionPlacementInPlace': 'In place',
    'onionPegBeforeTemplate': '{n} back',
    'onionPegAfterTemplate': '{n} ahead',
    'shortcutTitle': 'Keyboard shortcuts',
    'shortcutResetAll': 'Reset all',
    'shortcutFileImportedTemplate':
        '{taken} shortcuts brought into the new preset "{preset}" '
        '({skipped} with nothing to go on here).',
    'shortcutPresets': 'Presets',
    'shortcutPresetNew': 'New preset',
    'shortcutPresetNameEmpty': 'Preset name cannot be empty.',
    'shortcutPresetDelete': 'Delete preset',
    'shortcutPresetRename': 'Rename preset',
    'shortcutPresetDuplicate': 'Duplicate preset',
    'shortcutPresetExport': 'Export preset',
    'shortcutPresetBroughtTemplate': 'Added the preset "{name}".',
    'shortcutPresetCopyTemplate': '{name} copy',
    'shortcutPresetDeleteTemplate': 'Delete the preset "{name}"?',
    'shortcutFileUnreadableTemplate':
        '{name}: no shortcuts could be read out of this file.',
    'shortcutResetToDefault': 'Reset to default',
    'shortcutUnassign': 'Remove shortcut',
    'shortcutRecordNew': 'Record new shortcut',
    'shortcutTouch': 'Touch shortcut',
    'shortcutSearch': 'Search actions',
    'shortcutConflictBanner':
        'Some actions share the same key — the highlighted bindings collide.',
    'shortcutRecordingHint': 'Press keys… (Esc cancels)',
    'playbackMode': 'Playback mode',
    'playbackModeSkipFrames': 'Skip frames',
    'playbackModeEveryPicture': 'Every frame',
    'playbackModeRenderFirst': 'Render first',
    'playbackDroppedCount': '{n} dropped',
    'playbackDroppedCountOne': '{n} dropped',
    'playbackSilentCount': '{n} silent',
    'playbackSilentCountOne': '{n} silent',
    'playbackOutputRefused': 'No sound — the output would not open.',
    'soundCannotPlay.missing': 'Cannot play — the file is not there.',
    'soundCannotPlay.notReadYet':
        'Cannot play yet — the file could not be read (a cloud copy may still be coming down).',
    'soundCannotPlay.format': 'Cannot play — no decoder reads this format.',
    'soundCannotPlay.conform':
        'Cannot play — converting it for playback failed.',
    'soundCannotPlay.deviceRate':
        "Cannot play — it could not be brought to the output's sample rate.",
    'playbackStop': 'Stop',
    'sheetPreviousPage': 'Previous page',
    'sheetNextPage': 'Next page',
    'sheetPageDrag': 'Page (drag)',
    'autosaveTitle': 'Autosave',
    'autosaveEvery': 'Every',
    'autosaveSectionHelp':
        'Saves the project every so often, so a crash or a flat battery costs at most that much work.',
    'autosaveSwitchHelp':
        'Off means the project only changes when you save it, and a crash costs everything since.',
    'appContainerTitle': 'App container',
    'appContainerHelp':
        'What the app keeps outside your project files: settings and brush tips, media and audio an import brought in that no save has absorbed yet, and a diagnostics log.',
    'commonMinutesShort': ' min',
    'exExport': 'Export',
    'exAddToQueue': 'Add to queue',
    'exImage': 'Image',
    'exVideo': 'Video',
    'exCels': 'Cels',
    'exFormat': 'Format',
    'exOptions': 'Options',
    'exNaming': 'Naming',
    'exScope': 'Scope',
    'exQuality': 'Quality',
    'exCodec': 'Codec',
    'exBitrate': 'Bitrate',
    'exChannels': 'Channels',
    'exAudio': 'Audio',
    'exHandOverDeclined': 'Not handed over — the outputs were let go.',
    'exHandOverPending': 'The outputs have not been handed over yet.',
    'exHandOverPickAgain': 'Pick again',
    'exHandOverDiscard': 'Discard',
    'exSavePreset': 'Save preset',
    'exPresetNameEmpty': 'Preset name cannot be empty.',
    'exBaseName': 'Base name',
    'exSuffix': 'Suffix',
    'exPrefix': 'Prefix',
    'exLayDirection': 'Lay direction on this drawing',
    'exLayGuides': 'Guides',
    'exCelFormat': 'Cel format',
    'exTimesheetFormat': 'Timesheet format',
    'exEnvelopeFormat': 'Cut envelope format',
    'exWrittenCount': '{n} files',
    'exWrittenCountOne': '{n} file',
    'noticeExportNoPicture': 'No row that is on holds a picture for this cel',
    'noticeExportNotPlaced': 'This drawing is not on the timeline',
    'noticeExportSameName':
        'A row of the same name already exports this picture',
    'exDigits': 'Digits',
    'exApplyLayerFx': 'Layer FX',
    'exMuxSeMix': 'Mux the SE mix into the video',
    'exLabel': 'Label',
    'exApply': 'Apply',
    'exKinds': 'Kinds to export',
    'exLayerFilter': 'Layers',
    'exSelBase': 'Base',
    'exCelsLayersOut': 'Layers to export',
    'exSelAttach': 'Attach',
    'exSelSheet': 'Sheet only',
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
    'exStratumPaper': 'Paper',
    'exStratumForm': 'Form',
    'exStratumContent': 'Text',
    'exStratumPicture': 'Pictures',
    'exStratumInk': 'Ink',
    'exLeftOutOfTheFile': 'Not everything could be kept in the file.',
    'exNoCels': '(no cels)',
    'exNoCuts': '(no cuts)',
    'exPresets': 'Presets',
    'exQueue': 'Queue',
    'exSize': 'Size',
    'exCutSize': 'Cut size',
    'exRealSheet': 'Real sheet',
    'imNotTvpp': 'This file cannot be read as a TVPaint project.',
    'imNotClip': 'This file cannot be read as a CLIP STUDIO PAINT file.',
    'imLeftBehind': 'Not everything could be imported.',
    'imWarningCount': '{n} warnings',
    'imWarningCountOne': '{n} warning',
    'imFileUnreadable':
        'The file could not be read — if it is in the cloud, try again in a '
        'moment.',
    'imNotFoundTemplate': 'Not found: {path}',

    'exFrameCount': '{n} frames',
    'exFrameCountOne': '{n} frame',
    'exPageCount': '{n} pages',
    'exPageCountOne': '{n} page',
    'exFileCount': '{n} files',
    'exFileCountOne': '{n} file',
    'exJobCount': '{n} jobs',
    'exJobCountOne': '{n} job',
    'exContePageCount': '{n} conte pages',
    'exContePageCountOne': '{n} conte page',
    'exCancelledAfterTemplate': 'Export cancelled after {count}.',
    'exCancelledVideoTemplate':
        'Export cancelled after {count} (partial video kept).',
    'exCancelled': 'Export cancelled.',
    'exDoneTemplate': 'Exported {count}.',
    'exDoneSkippedTemplate': 'Exported {count} ({skipped} empty skipped).',
    'exDoneFileTemplate': 'Exported {name}.',
    'exDoneVideoTemplate': 'Exported video ({count}).',
    'exDoneConteDocumentTemplate': 'Exported {name} ({count}).',
    'exNothingInFrame': 'Nothing to export (empty frame).',
    'exFailedTemplate': 'Export failed: {error}',
    'exQueueRestTemplate': 'Queue: {count} done{failed}{rest}.',
    'exQueueFailedTemplate': ', {n} failed',
    'exQueueRestKept': ', rest kept',
    'exFileLabel': 'File',
    'exOrderAsksFirst': 'Asks where first, then exports',
    'exOrderAsksAfter': 'Exports first, then asks where',
    'exSeMuxedTemplate': 'SE muxed · {codec}',
    'exVectorPdf': 'Vector PDF',
    'exFxOn': 'FX on',
    'exFxOff': 'FX off',
    'exFxBasic': 'Basic FX only',
    'exFxBasicOnly': 'Basic only',
    'exTabSequence': 'Sequence',
    'exSizeCamera': 'Camera',
    'exSizeCanvas': 'Canvas',
    'exPageImage': 'Page image',
    'exSaveCurrent': '+ Save current',
    'exRenderQueue': 'Render queue',
    'exRenderAll': 'Render All',
    'exJobQueued': 'Queued',
    'exJobDone': 'Done',
    'exJobFailed': 'Failed',
    'exJobCancelled': 'Cancelled',
    'exJobTemplate': 'Job {id} · {tab}',
    'exIncludeAll': 'All',
    'exCutsIncludedTemplate': '{n} / {total} cuts',
    'exNeedsFfmpeg': 'Needs FFmpeg on PATH on this machine.',
    'exCheckingEncoders': 'Checking this machine’s encoders…',
    'exNotInThisBuild': 'Not available in this build yet.',
    'exBitrateAuto': 'Auto',
    'exCanvasTemplate': 'Canvas {size}',
    'exCanvasPerCut': 'Canvas (per cut)',
    'imImport': 'Import',
    'imFile': 'File',
    'imInto': 'Into',
    'imFit': 'Fit',
    'imModified': 'Modified',
    'imSize': 'Size',
    'imResolution': 'Resolution',
    'imExcluded': 'Excluded',
    'imFolderAsOneCut': 'Cut',
    'imFolderPerRow': 'Custom',
    'imPlaceTitleTemplate': 'Place — {name}',
    'imModeKeep': 'Keep',
    'imModeReference': 'Link',
    'imBake': 'Rasterize',
    'imOptions': 'Options',
    'imPictureAndSound': 'Picture + sound',
    'imPictureOnly': 'Picture only',
    'imSoundOnly': 'Sound only',
    'imRunSpanTemplate': '{first}–{last} ({n})',
    'imRateTitleTemplate': 'Movie {movie} · project {project}',
    'imRateBodyTemplate':
        'Set the project to {movie}? The sound keeps its timing.',
    'imRateKeepTemplate': 'Keep {project}',
    'imRateTakeTemplate': 'Set to {movie}',
    'commonOn': 'On',
    'commonOff': 'Off',
    'imFitOriginal': 'Original size',
    'imFitContain': 'Fit, keep ratio',
    'imFitStretch': 'Stretch, ignore ratio',
    'imIntoNewLayer': 'New layer',
    'imIntoSeRow': 'SE row',
    'imIntoRowCellTemplate': '{row} · frame {frame}',
    'imIntoNewCut': 'New cut',
    'imPsdMerge': 'Merge layers',
    'imPsdExpand': 'Keep layers',
    'imNoSource': 'No source selected',
    'imFileCountTemplate': '{n} files',
    'imStatusImporting': 'Importing…',
    'imStatusNothing': 'Nothing imported.',
    'imStatusDone': 'Imported',
    'imStepRecoding': 'Re-encoding the trimmed movie…',
    'imStepWritingSpan': 'Writing the trimmed span to a file…',
    'imStepCarrying': 'Keeping the file inside the project…',
    'imStepRasterizing': 'Rasterizing into cels…',
    'imFolderGone': 'That folder is gone.',
    'imFolderUnreadableTemplate': 'Could not read the folder: {reason}',
    'imCutFolderUnreadable': 'Could not read that folder.',
    'imUnreadableTemplate': '{name}: could not read the file.',
    'imLacksPictureTemplate': '{name}: the file has no picture {number}.',
    'imCorruptTemplate':
        '{name}: could not be opened — corrupt or password-locked.',
    'imPagesFailedTemplate':
        '{name}: {n} page(s) failed to render — their cels stay empty.',
    'imFramesFailedTemplate':
        '{name}: {n} frame(s) failed to decode — their cels stay empty.',
    'imNoPdfRendererTemplate': '{name}: no PDF renderer in this build.',
    'imCouldNotImportTemplate': '{name}: could not be imported.',
    'imPsdNoLayersTemplate':
        '{name}: no layers to expand — import it merged instead.',
    'imKeepExplain':
        'The project file holds these, compressed; the originals are left alone.',
    'imReferenceExplain':
        'The files stay where they are and the project points at them.',
    'mpFileMissing': 'File missing — relink it',
    'mpInUseOnTimeline': 'In use on the timeline',
    'mpNameEmpty': 'Media name cannot be empty.',
    'exCameraTemplate': 'Camera {size}',
    'toolBrush': 'Brush',
    'toolEraser': 'Eraser',
    'toolEyedropper': 'Eyedropper',
    'toolFill': 'Fill',
    'toolText': 'Text',
    'toolShape': 'Shape',
    'textToolSelectedText': 'Selected text',
    'textToolDeleteText': 'Delete text',
    'textToolLetters': 'Letters',
    'textToolBox': 'Box',
    'textToolFont': 'Font',
    'textToolSize': 'Size',
    'textToolTracking': 'Tracking',
    'textToolBold': 'Bold',
    'textToolItalic': 'Italic',
    'textToolUnderline': 'Underline',
    'textToolStrikethrough': 'Strikethrough',
    'textToolColor': 'Color',
    'textToolOutline': 'Outline',
    'textToolOutlineWidth': 'Outline width',
    'textToolAlign': 'Align',
    'textToolAlignLeft': 'Left',
    'textToolAlignCenter': 'Center',
    'textToolAlignRight': 'Right',
    'textToolCentreAcross': 'Center horizontally',
    'textToolCentreDown': 'Center vertically',
    'textToolBoxWidth': 'Box width',
    'textToolWidthAuto': 'Auto',
    'textToolWidthFixed': 'Fixed',
    'textToolLineHeight': 'Line spacing',
    'textToolLetterWidth': 'Horizontal scale',
    'textToolSkew': 'Skew',
    'textToolBackground': 'Background',
    'textToolIntoDrawing': 'Rasterize',
    'textToolWriting': 'Direction',
    'textToolWritingLines': 'Horizontal',
    'textToolWritingColumns': 'Vertical',
    'textToolAlignTop': 'Top',
    'textToolAlignBottom': 'Bottom',
    'textToolFontImport': 'Import a font file',
    'textToolFontDelete': 'Delete font',
    'textToolFontsOfProject': 'Fonts in this project',
    'textToolFontsOfDevice': 'Fonts on this device',
    'textToolFontTakeOut': 'Take out of the project',
    'textToolFontStaysOnThisDevice':
        'This font may not be put inside a document that is edited, so it '
        'changes when opened on another device.',
    'textToolFontNotOnThisDevice':
        'This font is not on this device, so it shows in another.',
    'textToolFontUnreadable': 'That file could not be read as a font.',
    'textToolFontIsTheApps': "That font is already one of the app's own.",
    'textToolFontNotKept': 'That font could not be saved.',
    'toolSelect': 'Select',
    'toolTransform': 'Transform',
    'toolShapeFill': 'Shape Fill',
    'toolCutNothingHeld': 'Nothing held yet',
    'toolCutHoldingTemplate': 'Holding {size} px',
    'toolLibraryEmpty': 'Nothing to show',
    'toolCutPasteAtOrigin': 'Paste at original position',
    'toolCutFlipHorizontal': 'Flip horizontal',
    'toolCutFlipVertical': 'Flip vertical',
    'toolCutRegisterTip': 'Register as Tip',
    'toolCutDeletesSource': 'Delete original',
    'toolReadSource': 'Reference',
    'toolReadsEveryVisibleLayer': 'Every visible layer',
    'brushSettingsTitle': 'Brush Settings',
    'toolShapeRect': 'Rectangle',
    'toolShapeEllipse': 'Ellipse',
    'toolShapeLasso': 'Lasso',
    'toolShapePolygon': 'Polygon',
    'toolShapeLine': 'Line',
    'toolShapeSelectTemplate': '{shape} Select',
    'toolShapeCutTemplate': '{shape} Cut',
    'toolShapeFillTemplate': '{shape} Fill',
    'toolShapeDrawTemplate': 'Draw {shape}',
    'shapeToolDraws': 'Draw',
    'shapeToolStroke': 'Stroke',
    'shapeToolFill': 'Fill',
    'shapeToolType': 'Type',
    'shapeToolTypePlain': 'Plain',
    'shapeToolCorners': 'Corners',
    'shapeToolCornersSharp': 'Sharp',
    'shapeToolCornersRound': 'Round',
    'shapeToolRatioLock': 'Lock ratio',
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
    'brMixing': 'Colour mixing',
    'brMixingMethod': 'Method',
    'brMixingMix': 'Mix with ground',
    'brMixingBlur': 'Blur',
    'brPaintAmount': 'Paint amount',
    'brPaintDensity': 'Paint density',
    'brColorStretch': 'Colour stretch',
    'brHardness': 'Hardness',
    'stepUp': 'Step up',
    'stepDown': 'Step down',
    'brEdgeNone': 'None',
    'brSpacing': 'Spacing',
    'brAngle': 'Angle',
    'brRoundness': 'Roundness',
    'brScale': 'Scale',
    'brScatter': 'Scatter',
    'brScatterCount': 'Count',
    'brScatterBothAxes': 'Both Axes',
    'brTipRotation': 'Direction',
    'brRotationFixed': 'None',
    'brRotationDirection': 'Line Direction',
    'brRotationPenTilt': 'Pen Direction',
    'brRotationPenTwist': 'Barrel Rotation',
    'brTipOrder': 'Repeat Method',
    'brTipOrderRepeat': 'Repeat',
    'brTipOrderPingPong': 'Back and Forth',
    'brTipOrderHoldLast': 'No Repeat',
    'brTipOrderRandom': 'Random',
    'brTipOrderOneLap': 'Once Through',
    'brTipOrderShuffledLap': 'Random Once Through',
    'brTipOrderLean': 'Pen Lean',
    'brTipsPerTurn': 'Tips per Turn',
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
    'brDeleteTipBodyTemplate': '“{name}” will be removed from the library.',
    'brStabilizer': 'Stabilizer',
    'brStabilizerOn': 'Apply stabilizer',
    'brStabilizerBySpeed': 'By speed',
    'brBySpeedSlow': 'Slow',
    'brBySpeedFast': 'Fast',
    'brPostCorrection': 'Post-correction',
    'brPostBySpeed': 'Adjust by speed',
    'brPostByViewScale': 'Adjust by zoom',
    'brPostBezier': 'Bezier curve',
    'brSharpenCorners': 'Sharpen corners',
    'brGroupInk': 'Ink',
    'brGroupTip': 'Brush tip',
    'brGroupMixing': 'Mixing',
    'brGroupScattering': 'Scattering',
    'brGroupTexture': 'Texture',
    'brGroupCorrection': 'Correction',
    'brDetailTitle': 'Brush Details',
    'brShowInPanel': 'Show in the panel',
    'brHideFromPanel': 'Hide from the panel',
    'brBlend': 'Blend',
    'brBlendMode': 'Brush blend mode',
    'brDualBlend': 'Dual blend',
    'brTextureMode': 'Texture mode',
    'brTextureModeHeight': 'Height',
    'brEditGroup': 'Edit group',
    'brFolderIcon': 'Folder icon',
    'brFolderName': 'Folder name',
    'brFeather': 'Feather',
    'brTolerance': 'Tolerance',
    'brGapClose': 'Gap Close',
    'brGrowShrink': 'Grow/Shrink',
    'brAntiAlias': 'Anti-alias',
    'brFillBeyondCanvas': 'Fill Beyond Canvas',
    'brOpenRegionsRefuse': 'Open regions refuse to fill',
    'brName': 'Name',
    'brDisplay': 'Display',
    'brTipIcon': 'Tip icon',
    'brStrokePreview': 'Stroke preview',
    'brBrushOptions': 'Brush options',
    'brNewGroup': 'New group',
    'brNewGroupName': 'New Group',
    'brNewPresetName': 'Preset {n}',
    'brRenameGroup': 'Rename group',
    'brDeleteGroup': 'Delete group',
    'brDeleteEmptyGroupTemplate': 'Delete the empty group "{name}"?',
    'brDeleteGroupTemplateOne': 'Delete "{name}" and the brush inside it?',
    'brDeleteGroupTemplate': 'Delete "{name}" and the {n} brushes inside it?',
    'brRenameSelected': 'Rename selected brush',
    'brDeleteSelected': 'Delete selected brush',
    'brSaveAsPreset': 'Save current settings as preset',
    'brImportBrushes': 'Import brushes (.abr, .sut, .sutg)',
    'brResetLibrary': 'Reset brush library',
    'brExportSelected': 'Export brush',
    'brExportGroup': 'Export brush group',
    'brExportNothing': 'There is nothing to export here.',
    'fileExportPlaceUnchosenTemplate': 'Could not choose where to save: {error}',
    'settingsExportedTemplate': 'Exported "{name}".',
    'settingsExportNotWrittenTemplate': 'Could not write the file: {error}',
    'settingsExportAll': 'Export all settings',
    'settingsAllFileName': 'Anicel settings',
    'settingsRowFrameCount': 'Frame count entry',
    'settingsRowWorkspaceLayout': 'Workspace layout',
    'imIntoSettings': 'Settings',
    'imSettingsGoInPlace':
        'What goes into Settings replaces what is there now — '
        'the current ones will be gone.',
    'imSettingsUnreadable': 'Unreadable',
    'brExportNotWrittenTemplate': 'Could not write the brush file: {error}',
    'brExportedOneTemplate': 'Exported "{name}".',
    'brExportedManyTemplate': 'Exported {count} brushes.',
    'brExportFallbackName': 'Brushes',
    'brImportUnreadable': 'This file could not be read as a brush file.',
    'brImportPickFailedTemplate': 'Could not open the file: {error}',
    'fontBroughtTemplate': 'Added the font "{family}" to this device.',
    'brImportedOneTemplate': 'Imported 1 brush from "{file}".',
    'brImportedManyTemplate': 'Imported {count} brushes from "{file}".',
    'brImportWarningsTemplate': '{summary} ({count} entries with warnings)',
    'brTipUnreadable': 'That image could not be read as a brush tip.',
    'brTipNoShape': 'That image has no visible shape to use as a tip.',
    'brTipNotSaved': 'That tip could not be saved.',
    'brExpand': 'Expand',
    'trFlipHorizontal': 'Flip Horizontal',
    'trFlipVertical': 'Flip Vertical',
    'trPosition': 'Position',
    'trScale': 'Scale',
    'trScaleLink': 'Link scale',
    'trRotation': 'Rotation',
    'trAnchorPoint': 'Anchor',
    'trMeshColumns': 'Columns',
    'trMeshRows': 'Rows',
    'trMesh': 'Mesh',
    'trFinish': 'Finish',
    'commonReset': 'Reset',
    'viewFitToView': 'Fit to View',
    'viewResetView': 'Reset Zoom (100%)',
    'panelSettings': 'Settings',
    'viewRotateLeft': 'Rotate View Left',
    'viewRotateRight': 'Rotate View Right',
    'viewFlipHorizontal': 'Flip View Horizontal',
    'viewFlipVertical': 'Flip View Vertical',
    'viewStraighten': 'Straighten View (0°)',
    'viewZoomDrag': 'Zoom (drag)',
    'viewAngleDrag': 'View angle (drag)',
    'valueTypeIn': 'Type a value',
    'viewCanvasColor': 'Canvas color',
    'viewPasteboardColor': 'Pasteboard color',
    'pasteboardTitle': 'Pasteboard',
    'pasteboardInUse': 'In use',
    'pasteboardNotInUse': 'Not in use',
    'viewBackdropColor': 'Backdrop color',
    'colorUseCurrent': 'Use current color',
    'colorNone': 'None',
    'colorPresent': 'Present',
    'tlSections': 'Sections',
    'tlAllDisplayedLayers': 'All displayed layers',
    'tlShowAll': 'Show all',
    'tlHideAll': 'Hide all',
    'tlSoloKind': 'Solo kind',
    'tlSoloColor': 'Solo color',
    'tlSoloClips': 'Solo clipped layers',
    'tlSoloFxOnRows': 'Solo fx-on rows',
    'tlSoloSheetOnRows': 'Solo sheet-on rows',
    'tlApplyAllFx': 'Apply all fx',
    'tlBypassAllFx': 'Bypass all fx',
    'tlAllOnTimesheet': 'All on timesheet',
    'tlAllOffTimesheet': 'All off timesheet',
    'tlClearMarkFilter': 'Clear mark filter',
    'tlClearAllClips': 'Release all clipping',
    'tlColVisibility': 'Visibility column',
    'tlColLayerKind': 'Layer kind column',
    'tlColOnionSkin': 'Onion skin column',
    'tlColOpacity': 'Opacity column',
    'tlColBlendMode': 'Blend mode column',
    'tlColFx': 'FX column',
    'tlColMark': 'Mark column',
    'tlColClip': 'Clipping column',
    'tlColTimesheet': 'Timesheet column',
    'tlShowXSheet': 'Show X-sheet',
    'tlShowTimeline': 'Show timeline',
    'cameraViewOn': 'Camera view (on)',
    'cameraViewOff': 'Camera view',
    'tlOpenOnionPanel': 'Open onion skin panel',
    'tlApplyOnionToDisplayed': 'Apply onion skin to displayed layers',
    'tlClearOnionOnDisplayed': 'Clear onion skin on displayed layers',
    'tlOnionOnDisplayedToggle': 'Onion skin on displayed layers (on/off)',
    'tlCollapseAllLayers': 'Collapse all layers',
    'tlExpandAllLayers': 'Expand all layers',
    'railLayerBlendMode': 'Layer blend mode',
    'railFolderBlendMode': 'Folder blend mode',
    'railHideLayer': 'Hide layer',
    'railShowLayer': 'Show layer',
    'railBypassLayerFx': 'Bypass layer FX',
    'railApplyLayerFx': 'Apply layer FX',
    'railBypassMixedLayerFx': 'Bypass all layer FX (some are off)',
    'railBypassTrackFx': 'Bypass track FX',
    'railApplyTrackFx': 'Apply track FX',
    'railRemoveFromTimesheet': 'Remove from timesheet',
    'railAddToTimesheet': 'Add to timesheet',
    'railCollapseLanes': 'Collapse lanes',
    'railExpandLanes': 'Expand lanes',
    'railOnionSkinOn': 'Onion skin (on)',
    'railOnionSkin': 'Onion skin',
    'railLaneGraphOn': 'Graph (on)',
    'railLaneGraph': 'Graph',
    'railLanePinOn': 'Pinned to every graph',
    'railLanePin': 'Pin to every graph',
    'laneGraphValue': 'Value',
    'laneGraphSpeed': 'Speed',
    'laneGraphEnlarge': 'Enlarge',
    'laneGraphEnlargeOn': 'Enlarge (on)',
    'laneGraphPen': 'Pen',
    'laneGraphPenOn': 'Pen (on)',
    'laneGraphTransformBox': 'Transform box',
    'laneGraphTransformBoxOn': 'Transform box (on)',
    'railClipOn': 'Clip to layer below (on)',
    'railClip': 'Clip to layer below',
    'tlLayerMark': 'Layer mark',
    'tlLayerMarkNone': 'No label',
    'tlLayerMarkSource': 'Material',
    'tlLayerTake': 'Take',
    'tlLayerTakeNumber': 'Take {n}',
    'tlRepeat': 'Repeat',
    'tlRepeatSelection': 'Repeat selection',
    'tlNoLayers': 'No layers',
    'tlLegendLayer': 'LAYER',
    'tlAllDisplayedOpacity': 'All displayed layers opacity',
    'tlLinkedWith': 'Linked with',
    'tlLayerReference': 'Reference',
    'tlReferenceSourceShort': 'Runs {n} frames past the source',
    'tlSelectedLayers': 'Selected layers',
    'tlAudioGroup': 'Audio',
    'tlSoundVolume': 'Volume',
    'tlNameTagGroup': 'Name Tag',
    'tlReferenceGroup': 'Reference',
    'tlTransformGroup': 'Transform',
    'tlLaneScale': 'Scale',
    'tlLaneRotation': 'Rotation',
    'tlLanePosition': 'Position',
    'tlLaneOpacity': 'Opacity',
    'tlLaneAnchorPoint': 'Anchor Point',
    'tlBypassLaneTemplate': 'Bypass {name}',
    'tlApplyLaneTemplate': 'Apply {name}',
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
    'tlKindAnimation': 'Animation',
    'tlKindStoryboard': 'Storyboard',
    'tlKindImage': 'Image',
    'tlKindAdjustment': 'Adjustment',
    'tlKindFolder': 'Folder',
    'tlKindSe': 'SE',
    'tlKindTransition': 'Transition',
    'tlKindCamera': 'Camera',
    'tlKindSemanticTemplate': '{kind} layer',
    'tlKindInstruction': 'Direction',
    'tlNoriShiro': 'MARGIN',
    'seNameTagShowLineLabel': 'Show Dialogue',
    'seNameTagLineInkLabel': 'Dialogue Ink',
    'seNameTagTrackingLabel': 'Tracking',
    'seNameTagSizeLabel': 'Size',
    'seNameTagNameInkLabel': 'Name Ink',
    'seNameTagBoxColorLabel': 'Box Colour',
    'seNameTagBoldLabel': 'Bold',
    'seNameTagItalicLabel': 'Italic',
    'seNameTagUnderlineLabel': 'Underline',
    'seNameTagStrikethroughLabel': 'Strikethrough',
    'seNameTagPreviewName': 'Name',
    'seNameTagPreviewLine': 'Line',
    'tlLayerCommands': 'Layer commands',
    'tlFrameCommands': 'Frame commands',
    'tlCut': 'Cut',
    'tlLayer': 'Layer',
    'tlFrame': 'Frame',
    'tlKey': 'Key',
    'linkWindowUnlink': 'Unlink',
    'linkWindowUnlinkLinkedCut': "A linked cut's layers unlink with the cut",
    'tlResetGroup': 'Reset (keeps keys)',
    'tlEffects': 'Effects',
    'tlAddEffectTemplate': 'Add {name}',
    'tlDropIntoFolderTemplate': 'into {name}',
    'tlDropOutOfFolder': 'out of the folder',
    'tlDropAttachSyncedTemplate': 'attach to {name} (synced)',
    'tlDropAttachFreeTemplate': 'attach to {name} (free)',
    'tlDropDetachAttach': 'detach',
    'tlAttachDropsFxRows': 'Layers that lose their fx',
    'tlAttachDropsFxTitle': 'Attaching drops its fx',
    'tlMergeChangesTitle': 'Merging may change how it looks',
    'tlMergeChangesBody':
        'The merged layer may look different over the layers under it.',
    'tlMergeChanges': 'What changes',
    'tlMergeChangeBlend':
        'A layer blends in its own mode — the merged layer is Normal',
    'tlMergeChangeClip':
        'A selected layer and one not selected are joined by clipping',
    'tlMergeChangeFolder':
        "The merged layer's folder lays its look over layers from outside it",
    'tlMergeChangeRiderOver': 'An attached layer comes to cover other pictures',
    'tlMergeChangeRiderUnder': 'An attached layer goes under other pictures',
    'tlMergeChangeWall': 'What lies past the pasteboard is cut off',
    'tlAttachDropsFxBody':
        'An attached layer keeps no fx of its own. Continuing discards the existing fx. Continue?',
    'tlPush': 'Push (open frames)',
    'tlPull': 'Pull (close frames)',
    'sbOneStoryboardRowPerCut':
        'This cut already has a storyboard row. A cut can hold only one.',
    'cnHeadCut': 'CUT',
    'cnHeadPicture': 'PICTURE',
    'cnHeadAction': 'ACTION',
    'cnHeadDialogue': 'DIALOGUE',
    'cnHeadSeconds': 'TIME',
    'cnCoverCuts': ' cuts',
    'cnCoverArtist': 'Storyboard',
    'sheetPrintEpisode': 'Ep.no',
    'sheetPrintTitle': 'Title',
    'sheetPrintScene': 'Scene',
    'sheetPrintCut': 'Cut.no',
    'sheetPrintDuration': 'Duration',
    'sheetPrintName': 'Name',
    'sheetPrintPage': 'Page',
    'sheetPrintRepeat': 'REPEAT',
    'sheetPrintHold': 'HOLD',
    'tlSetCommasN': 'Set N commas',
    'tlSetCommaTemplate': 'Set {n} comma exposure',
    'tlProjectAudioRate': 'Project audio sample rate',
    'tlShowSeRows': 'Show SE rows',
    'tlShowCameraRows': 'Show camera rows',
    'setLengthAction': 'Set exposure length',
    'markEveryField': 'Interval',
    'frameCountEntryFrames': 'Frames',
    'frameCountEntrySecondsPlusFrames': 'Seconds+frames',
    'projectFpsTitle': 'Project frame rate',
    'projectFpsField': 'Frames per second',
    'autoNameStartField': 'Start number',
  };

  static const _jaValues = <String, String>{
    'launchStageEngine': 'エンジン起動',
    'launchStagePlugins': 'プラグイン登録',
    'launchStageApp': 'アプリ準備',
    'launchStageFirstFrame': '最初の画面を描画',
    'launchNoticeTitle': 'ご案内',
    'launchNoticeDontShowAgain': '次回から表示しない',
    'usageStatsSend': '利用統計を送信',
    'usageStatsHelp':
        'オンにすると、アプリを開いたとき・使っている間の55分ごと・離れたときに、使用中であることを'
        'OSとそのバージョン・端末の機種名・アプリのビルド・アプリの言語とともに'
        '匿名で送信します。'
        '1日1回、端末の言語と、直近28日間に使った日数の区分（初回 / 1〜2日 / 3日以上）、'
        '4つの設定（UIの大きさ・アクセントカラー・自動保存・カーソル）も送信します。'
        '絵・プロジェクト・ファイル名・名前・端末に付けた名前など、あなたを特定できる'
        'ものは送信しません。オフにすると、この端末に残した記録も削除します。',
    'usageStatsTitle': '利用統計',
    'usageStatsAsk': '利用統計を送信しますか？オンにしていただくと、Anicel の開発の助けになります。',
    'usageStatsChangeLater': '環境設定 ▸ システムでいつでも変更できます。',
    'usageStatsDontSend': '送信しない',
    'usageStatsDoSend': '送信する',
    'firstRunTitle': 'はじめの設定',
    'firstRunChangeLater': '環境設定でいつでも変更できます。',
    'firstRunStart': 'はじめる',
    'programLanguageLabel': 'プログラム言語',
    'notationLanguageLabel': '表記言語',
    'programLanguageHelp': 'メニュー・パネル・ラベルの言語。',
    'notationLanguageHelp': 'タイムシートなど提出物に印字される言語。',
    'noCutSelected': 'カット未選択',
    'noticeNoFrameHere': 'フレームがありません',
    'noticeNothingToCut': '切り取る対象がありません',
    'noticeNoConteLayer': 'このカットには絵コンテレイヤーがありません',
    'noticeLayerNotDrawable': 'このレイヤーには描けません',
    'noticeLayerHidden': 'このレイヤーは非表示です',
    'noticeEditAttachOwner': '親レイヤーを編集してください',
    'commonCancel': 'キャンセル',
    'commonApply': '適用',
    'commonRefresh': '更新',
    'commonClose': '閉じる',
    'commonAffectedFiles': '該当ファイル',
    'commonNotice': 'お知らせ',
    'tlSharedColourEdit': '色編集',
    'exportNoCuts': 'このプロジェクトには書き出せるカットがありません。',
    'exportQueueEmpty': 'キューにジョブがありません',
    'exportPresetsEmpty': 'プリセットがありません',
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
    'recordMicPermissionDenied': 'マイクへのアクセスがオフです — 設定でAnicelのマイクを許可してください。',
    'recordMicNotAllowed': 'マイクが許可されていません — 環境設定▸オーディオ▸「マイクを許可」をオンにしてください。',
    'recordTakeClipped': 'テイクがクリッピングしました — ブロックの赤い角が目印です。',
    'recordClipMarkerTooltip': 'このテイクはクリッピングしています（入力過大）',
    'tlTransitionCrossingWarning': 'カット境界を越えています — 適用されません',
    'tlTransitionCutOl': 'カット O.L',
    'audioMicGainLabel': 'マイクゲイン（dB）',
    'audioInputChannelLabel': '入力チャンネル',
    'audioInputChannelDevice': '装置のまま',
    'audioInputChannelMonoMix': 'モノラルミックス',
    'audioInputChannelLeft': '左のみ',
    'audioInputChannelRight': '右のみ',
    'audioClippingNoticeLabel': 'クリッピング警告（トースト＋ブロックマーカー）',
    'audioDenoiseLabel': 'ノイズ抑制（音声専用 — 効果音はオフに）',
    'audioInputMeterLabel': '入力レベル',
    'audioMicrophoneAllowedLabel': 'マイクを許可',
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
    'audioMute': 'ミュート',
    'audioSolo': 'ソロ',
    'fpsAudioTitleTemplate': '{from} → {to}：音はどうしますか？',
    'fpsAudioBody':
        'この2つのレートは実速度が0.1%異なり、音は実時間で存在します — コマ厳密と時間厳密を両立することはできません。\n\n• 音のタイミングを維持：音は実時間を保ち、コマ位置が0.1%ずれます（約42秒ごとに1コマ）。\n\n• 音を0.1%プル：正確なプルダウン比でリサンプルします（聴き取れないピッチ変化 — テレシネの標準コンフォーム）。全ての音がコマ範囲を維持します。',
    'fpsAudioKeep': '音のタイミングを維持',
    'fpsAudioPull': '音を0.1%プル',
    'feedbackTextOnly': 'テキストのみ',
    'feedbackWithFiles': 'スクリーンショット・動画つき（Google ログイン）',
    'selectionClosePolygon': '形を閉じる',
    'selectionInvert': 'カンバス外も選択範囲を反転',
    'selectionInvertInCanvas': 'カンバス内で選択範囲を反転',
    'toolSelectionMode': 'モード',
    'commonSave': '保存',
    'commonDelete': '削除',
    'commonAdd': '追加',
    'commonRename': '名前を変更',
    'commonLink': 'リンク',
    'commonPreview': 'プレビュー',
    'windowTitleTemplate': '{action}（{target}）',
    'editNameAction': '名前の編集',
    'editNoteAction': 'メモの編集',
    'renameLayerEmpty': 'レイヤー名を空にはできません。',
    'renameCutField': 'カット名',
    'renameCutEmpty': 'カット名を空にはできません。',
    'renameGuideTitle': 'ガイド名の変更',
    'renameGuideField': 'ガイド名',
    'renameGuideEmpty': 'ガイド名を空にはできません。',
    'deleteLayerTitle': 'レイヤーの削除',
    'deleteLayersMessage': '下のレイヤーを削除しますか？',
    'deleteLayersHeading': '削除するレイヤー',
    'deleteEffectsHeading': '削除するエフェクト',
    'frameNameConflictTitle': '同じフレーム名が既にあります',
    'frameNameConflictBody':
        '一覧のフレームには、同じレイヤーの別のフレームが既に使っている名前が付きます。'
        'その名前のフレームにリンクしますか？リンクすると同じ名前が同じ素材を共有し、'
        '一覧のフレームの絵は破棄されます。',
    'linkedPasteConflictBody':
        '貼り付けるフレームの名前を、一覧のフレームが既に使っています。'
        '貼り付けるブロックをそのフレームにリンクしますか？リンクすると同じ名前が'
        '同じ素材を共有し、貼り付けたブロックは一覧のフレームを表示します。'
        'コピーした絵は取り込まれません。',
    'frameNameConflictListHeading': 'リンクするフレーム',
    'seInstanceNewTitle': 'SEの新規作成',
    'seInstanceEditTitle': 'SEの編集',
    'seNameLabel': '名前（話者 — 空欄でボックス非表示）',
    'seTypeLabel': 'タイプ',
    'seDialogueLabel': 'セリフ',
    'seDialogueOffsetLabel': 'セリフのオフセット',
    'seKomaPerGlyphLabel': '1文字のコマ数',
    'seLinkedAudioLabel': 'リンクされた音声',
    'seLinkedAudioNone': 'なし',
    'seUnlinkAudio': 'リンクを解除',
    'keySideIncoming': 'イン',
    'keySideOutgoing': 'アウト',
    'keySideKind.linear': 'リニア',
    'keySideKind.ease': 'イーズ',
    'keySideKind.fast': 'クイック',
    'keySideKind.auto': 'スムーズ',
    'keySideKind.hold': 'ホールド',
    'keyEaseInfluence': '影響',
    'keyPath': 'パス',
    'keyPathKind.linear': 'リニア',
    'keyPathKind.bezier': 'ベジェ',
    'keyPathKind.continuousBezier': '連続ベジェ',
    'keyPathKind.autoBezier': '自動ベジェ',
    'keyRoving': 'ロービング',
    'keySideIncomingHelp':
        '前のキーからこのキーに入る速さ。リニア：一定 · イーズ：減速して到着 · クイック：加速して到着 · スムーズ：前後のキーに合わせて速さをつなぐ。影響：その変化が区間のどれだけにかかるか。',
    'keySideOutgoingHelp':
        'このキーから次のキーへ出る速さ。リニア：一定 · イーズ：ゆっくり出発 · クイック：勢いよく出発 · スムーズ：前後のキーに合わせて速さをつなぐ · ホールド：次のキーまで値をそのまま。影響：その変化が区間のどれだけにかかるか。',
    'keyPathHelp':
        '位置がこのキーを通る道の形。リニア：キーで折れる · ベジェ：前後のハンドルがそれぞれの向き · 連続ベジェ：二つのハンドルが一直線につながる · 自動ベジェ：前後のキーに合わせてなめらかに曲がる。',
    'keyRovingHelp':
        'パス上の位置はそのままに、キーが時間を手放す。時間を持つ前後のキーの間で、速さが均一になるフレームへ自動で移る（After Effects の Rove Across Time）。最初と最後のキーはロービングしない。',
    'cameraPath': 'カメラパス',
    'cameraPathOff': 'オフ',
    'cameraPathSpace': '空間',
    'cameraPathSpaceTime': '空間＋時間',
    'cameraPathAllKeys': '全キー',
    'cameraPathAroundPlayhead': '再生ヘッド周辺',
    'cameraPathTickEvery': '点の間隔',
    'cameraPathAround': '前後',
    'convertLinkedCutTitle': '兼用カットに変換',
    'convertLinkedCutBodyTemplate':
        '「{cut}」（原本）を別のカットとリンクします。同じ名前のレイヤーが'
        '1枚の共有画になります。',
    'convertLinkedCutTargetLabel': 'リンクするカット',
    'convertLinkedCutLinksHeading': 'リンクするレイヤー',
    'convertLinkedCutReplacedTemplate':
        '「{cut}」の同名作画が原本のもので置き換わります（原本優先）。',
    'convertLinkedCutReplacedHeading': '置き換わる作画',
    'convertLinkedCutJoiningTemplate': '作画 {count} 枚が共有セットに加わります。',
    'convertLinkedCutTargetGainsHeadingTemplate': '「{cut}」に追加されるレイヤー',
    'convertLinkedCutOriginGainsHeading': 'このカットに追加されるレイヤー',
    'convertLinkedCutNothing':
        'リンクするものがありません — 既に完全にリンク済みか、共有できる'
        '作画レイヤーがありません。',
    'convertLinkedCutUndoNote': '元に戻すと、変換で変わったカットがすべて復元されます。',
    'convertLinkedCutResizeFirst':
        'キャンバスサイズが異なります。兼用カットはキャンバスを共有するため'
        'このカットは元のカットのサイズに変更されます。元に戻すと復元されます。',
    'guideKindSymmetry': '対称',
    'guideKindPerspective': 'パース',
    'guideDelete': 'ガイドを削除',
    'guideShow': 'キャンバスに表示',
    'guideActsOn': '線に効いている',
    'guideActsOff': '効いていない',
    'guideLibraryEmpty': 'このカットにはまだガイドがありません',
    'noGuideSelected': 'ガイド未選択',
    'guideLineCount': '線の数',
    'guideMirrorMode': '線対称',
    'guideMirrorModeOn': 'コピーが左右反転します（本当の鏡）。',
    'guideMirrorModeOff': 'コピーは回転のみ — 反転しません。',
    'guideEyeLevelShow': 'アイレベルを表示',
    'guideConstrainToEyeLevel': '消失点をアイレベル上に固定',
    'guideConstrainToEyeLevelNote': '次のドラッグに効きます。すでに置いたものは動きません。',
    'guideVanishingPoint': '消失点',
    'guideVanishingPointAtInfinity': '平行（無限遠）',
    'guideAddVanishingPoint': '新規消失点',
    'guideDeleteVanishingPoint': '消失点を削除',
    'guideParallel': '平行',
    'guideParallelAngle': '角度',
    'guideLineDensity': '線の密度',
    'guideRasterize': 'ラスタライズ',
    'closeProjectTitle': 'プロジェクトを閉じますか？',
    'shortcutAction.file-new': '新規プロジェクト',
    'untitledProjectTab': '無題 {n}',
    'fileOpenInAnotherTab': 'そのファイルは別のタブで開いています。',
    'openNewerFormat': '新しいバージョンの Anicel で保存されたプロジェクトのため開けません。',
    'openOlderFormatTemplate':
        '形式 {saved} のプロジェクトのため開けません（この Anicel が開けるのは形式 {oldest} からです）。',
    'closeProjectBody': '変更は保存されていません。閉じますか？',
    'closeProjectVanishedBody':
        'このプロジェクトのファイルがなくなっています。このまま閉じると、その中にしか'
        'ない絵も一緒に失われます。「名前を付けて保存」なら、今開いているものを新しい'
        'ファイルに書き出せます。',
    'commonSaveAs': '名前を付けて保存',
    'saveAsTitle': '名前を付けて保存',
    'saveProgressRunning': '保存中…',
    'saveProgressDone': '保存しました',
    'savePrepareRunning': '準備中…',
    'savePrepareDone': '準備完了',
    'saveStepKeepingLeftBehind': '外したメディアを退避中…',
    'saveStepCels': 'セルを書き込み中…',
    'saveStepChecking': '格納するファイルを確認中…',
    'saveStepMedia': 'メディアを書き込み中…',
    'saveStepConforms': '再生用に変換した音声を書き込み中…',
    'saveStepFonts': 'フォントを書き込み中…',
    'saveStepCompacting': 'ファイルの空きを詰めています…',
    'saveStepHandingBack': '元の書類にファイルを渡しています…',
    'openProgressRunning': '読み込み中…',
    'openProgressDone': '読み込みました',
    'openWaitingCloudTemplate': 'クラウドから受信中 · {sec}秒',
    'openWaitingStalledTemplate': '{sec}秒間、まだ届いていません',
    'resizeProgressRunning': 'サイズ変更中…',
    'resizeProgressDone': 'サイズ変更しました',
    'bakeProgressRunning': 'ラスタライズ中…',
    'bakeProgressDone': 'ラスタライズしました',
    'rasterizeLeftReferences': '参照のまま残したレイヤーがあります。',
    'referenceWait.attached':
        'アタッチされたレイヤーはベースのトランスフォームで置かれるため、'
        '動く参照を自分のキーに移せません。'
        'アタッチを解除するとラスタライズできます。',
    'referenceWait.laidAsFitted':
        '以前のバージョンで合わせた大きさに置かれたファイルのため、'
        '動く参照をキーに移せません。'
        'ファイルを置き直すとラスタライズできます。',
    'referenceWait.sheared':
        '片方の軸だけ伸ばした拡大率の下での90°単位でない回転は、'
        'トランスフォームでは描けません。'
        '拡大率をそろえるか90°単位で回すとラスタライズできます。',
    'referenceWait.othersKeepKeys':
        'トランスフォームのスイッチを共有する別のレイヤーが、'
        'オフの間のキーを持っているため、'
        'スイッチを入れるとそのキーが表示されます。'
        '先にトランスフォームをオンにするとラスタライズできます。',
    'referenceWait.usesApart':
        'リンクされたレイヤーが同じセルの絵を別々の位置に見せているため、'
        'セル1枚に収められません。'
        '参照を同じ位置にそろえるとラスタライズできます。',
    'pasteProgressRunning': 'ペースト中…',
    'pasteProgressDone': 'ペーストしました',
    'unsavedAutosaveTitle': 'プロジェクトを保存',
    'unsavedAutosaveBody':
        'このプロジェクトはまだ一度も保存されていないため、自動保存の書き込み'
        '先がありません。ファイルを選べば、以降は自動保存が守ります。',
    'commonNotNow': '後で',
    'topStripProject': 'プロジェクト',
    'topStripSettings': '設定',
    'menuPlay': '再生',
    'menuPause': '一時停止',
    'shortcutAction.file-open': 'ファイルを開く',
    'shortcutAction.file-open-folder': 'フォルダを開く',
    'shortcutAction.file-export': '書き出し',
    'menuAction.edit-undo': '元に戻す',
    'menuAction.edit-redo': 'やり直す',
    'menuAction.edit-copy-frame': 'フレームをコピー',
    'menuAction.edit-paste-linked-frame': 'リンクフレームを貼り付け',
    'menuAction.edit-new-drawing': 'このフレームに新規作画',
    'menuAction.edit-delete-cell': 'セルを削除',
    'menuAction.edit-cut-exposure': '露光をカット',
    'menuAction.edit-toggle-mark': 'マークの切り替え',
    'shortcutAction.edit-keyboard-shortcuts': 'キーボードショートカット',
    'shortcutAction.edit-preferences': '環境設定',
    'shortcutAction.work-settings': '作品設定',
    'menuAction.file-save-as': 'プロジェクト(.anicel)',
    'menuAction.project-settings': 'プロジェクト設定',
    'shortcutAction.cut-create-linked': '兼用カットを作成',
    'shortcutAction.cut-convert-linked': '兼用カットに変換',
    'shortcutAction.cut-canvas-size': 'カンバスサイズ',
    'menuAction.cut-delete': 'カットを削除',
    'menuAction.layer-add': '新規レイヤー',
    'menuAction.layer-link-duplicate': 'リンクして複製',
    'menuAction.layer-unlink': 'リンクを解除',
    'menuAction.layer-group-into-folder': 'フォルダにまとめる',
    'menuAction.layer-rename': 'レイヤー名を変更',
    'shortcutAction.layer-rasterize': 'ラスタライズ',
    'menuAction.layer-se-name-tag': 'SE ネームタグ',
    'menuAction.layer-copy': 'レイヤーをコピー',
    'menuAction.layer-paste': 'レイヤーを貼り付け',
    'menuAction.layer-delete': 'レイヤーを削除',
    'menuAction.playback-stop': '停止',
    'menuAction.playback-play-all': '全カットを再生',
    'menuAction.window-panels': 'パネル',
    'shortcutAction.window-tool-rail-right': 'ツールバーを右端に',
    'shortcutAction.window-region-on-top': 'タイムライン領域を上に',
    'shortcutAction.window-brush-values-on-strip': 'ブラシの値を上部のバーに',
    'shortcutAction.window-full-screen': '全画面表示',
    'shortcutAction.window-region-fold': 'タイムライン領域を畳む / 開く',
    'shortcutAction.window-reset-layout': 'ワークスペース配置をリセット',
    'menuAction.edit-debug': 'デバッグ',
    'shortcutAction.edit-input-inspector': '入力インスペクタ',
    'shortcutAction.edit-frame-timing-overlay': 'フレームタイミングのオーバーレイ',
    'shortcutAction.edit-frame-stats': 'フレーム統計',
    'shortcutAction.edit-show-repaints': '再描画を表示',
    'menuAction.edit-knee-at-one': '画面解像度バッファ',
    'menuAction.edit-show-unpainted-tiles': '描画されなかったタイルを表示',
    'shortcutAction.help-about': 'Anicel について',
    'shortcutAction.help-send-feedback': 'フィードバックを送る',
    'fileOpenTitle': 'プロジェクトを開く',
    'fileStorageOffNotice':
        'ストレージへのアクセスがオフです — アプリフォルダの外にある'
        'プロジェクトには「すべてのファイル」の権限が必要です。',
    'fileOpenSettings': '設定を開く',
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
    'folderPickDriveNoticeAndroid':
        'Google ドライブはフォルダーを渡せません。この端末のフォルダーを'
        'お使いください — 同期アプリ（Autosync など）でドライブのフォルダーを'
        '端末に置けます。',
    'recentProjectsTitle': '最近使ったプロジェクト',
    'recentReconnect': '再接続',
    'sortAscending': '昇順',
    'canvasSizeTitle': 'カンバスサイズ',
    'cameraSizeTitle': 'カメラサイズ',
    'canvasWidthLabel': '幅（px）',
    'canvasHeightLabel': '高さ（px）',
    'canvasSizePresets': 'プリセット',
    'canvasAdjustOnCanvas': 'キャンバスで調整',
    'cameraRatioFree': '自由',
    'cameraRatioCurrent': '今の比率',
    'commonResize': 'サイズ変更',
    'inputPressureCurve': '筆圧カーブ',
    'inputCanvasHeading': 'カンバス',
    'inputRightClick': '右クリック / ペンのサイドボタン',
    'inputWheelClick': 'ホイールクリック / ペンの上ボタン',
    'inputPenTail': 'ペンのお尻（ペンを裏返す）',
    'inputCanvasTouchHeading': 'カンバスのタッチ',
    'inputIgnoreTouch': 'タッチをすべて無視',
    'inputDragOneFinger': '1本指ドラッグ',
    'inputDragTwoFingers': '2本指ドラッグ',
    'inputDragThreeFingers': '3本指ドラッグ',
    'inputExtraFinger': '追加指モディファイア',
    'inputExtraFingerHelp':
        'ジェスチャーの途中で指を足すと動作が制限されます — ズーム・回転・'
        'サイズのスナップ、フレームの微送り。',
    'inputStrokeFinger': '指ストロークモディファイア',
    'inputStrokeFingerHelp':
        '描いている間、別の指を画面に置いているとストロークが最も近い '
        '45° 方向に固定されます(Shift と同じ)。',
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
    'inputRotationSnap': '回転スナップ',
    'inputZoomSnaps': 'ズームスナップ（%）',
    'inputZoomCeiling': '最大ズームをロック（%）',
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
    'memoryItemLayerImages': 'レイヤー画像',
    'memoryItemFramePictures': 'フレーム画像',
    'memoryItemBrushTips': 'ブラシ先端',
    'memoryItemPanelRasters': 'パネルのラスター',
    'memoryItemViewerPages': 'ビューアのページ',
    'memoryItemImageCache': '画像キャッシュ',
    'memoryItemStoryboardThumbnails': '絵コンテのサムネイル',
    'memoryItemSheetImages': '用紙の画像',
    'memoryItemTextImages': '文字の画像',
    'memoryItemStrokePreviews': 'ストロークのプレビュー',
    'memoryItemTimelineTiles': 'タイムラインのタイル画像',
    'memoryItemMoviePictures': '参照動画',
    'memoryItemTileImages': 'キャンバスのタイル画像',
    'memoryItemEnginePool': '描画エンジンのタイルプール',
    'memoryItemEngineScratch': '描画エンジンの作業バッファ',
    'memoryOutsideAllowanceTemplate': '割り当ての外（上限を掛けられないもの）: {items}',
    'containerAreaSettings': '設定',
    'containerAreaDiagnostics': '診断ログ',
    'containerAreaSessionScratch': 'セッション作業領域',
    'containerTotal': '合計',
    'saveCelsLostTemplate':
        '保存しましたが、{count} 枚の絵を含められませんでした。それらが入っていたプロジェクトファイルが、開いている間に削除されました。',
    'saveCelsLostHeading': '該当する絵',
    'saveCelsLostGone': 'プロジェクトにもう無い絵',
    'saveFailedTitle': '保存できませんでした',
    'saveFailedFileInUse':
        '別のプログラム（同期・ウイルス対策、またはこのファイルを開いているアプリ）がこのファイルを使っているため、書き換えられませんでした。',
    'saveFailedReadOnly': 'このファイルまたはフォルダーが読み取り専用のため、書き込めませんでした。',
    'saveFailedDiskFull': '保存先の空き容量が足りません。',
    'saveFailedLocationGone':
        '保存先にアクセスできません — ドライブが外されたか、ネットワークが切れたか、フォルダーが削除されました。',
    'saveFailedReplaceRefused': 'この場所（クラウド・ファイルアプリ）がファイルの置き換えを拒否しました。',
    'saveFailedUnknown': 'ファイルの書き込み中にエラーが起きました。',
    'saveFailedCopyKept':
        'ここまでの作業はアプリ内の失敗版に保存してあります。失敗版はプログラムを閉じると消えます — 残すには「失敗版をバックアップ…」で好きな場所に保存してください。',
    'saveFailedNoCopy': '失敗版も作れませんでした — 「名前を付けて保存」で別の場所に保存してください。',
    'saveFailedRetry': '原因がなくなってからもう一度保存すると、元のファイルに保存されます。',
    'saveFailedDetailsHeading': '詳細',
    'saveFailedCopyLineTemplate': '失敗版: {path}',
    'saveFailedErrorLineTemplate': 'エラー: {error}',
    'shortcutAction.file-back-up-failed-copy': '失敗版をバックアップ',
    'failedCopyPickTitle': 'バックアップする失敗版',
    'failedCopyVanishOnClose': '失敗版はプログラムを閉じると消えます。',
    'failedCopyBackingUp': 'バックアップ中…',
    'failedCopyBackedUp': 'バックアップ完了',
    'closeProjectFailedCopyBody':
        'このプロジェクトが保存できなかった作業はアプリ内の失敗版にしかなく、失敗版はプログラムを閉じると消えます。残すには「名前を付けて保存」するか、ファイルメニューの「失敗版をバックアップ…」を使ってください。',
    'projectFileVanished':
        'このプロジェクトのファイルが見つかりません — 削除か移動された可能性があります。ゴミ箱に残っていれば今すぐ戻してください。保存済みの絵はそのファイルの中にしかありません。',
    'uiScaleLabel': 'UIの大きさ',
    'blockFrameLinesLabel': 'ブロック内のフレーム線',
    'unnamedMarkLabel': '名前のないブロックのマーク',
    'drawingCursorLabel': 'カーソル',
    'drawingCursorBrush': 'ブラシ',
    'drawingCursorPen': 'ペン',
    'drawingCursorCrosshair': '十字',
    'accent1Help': '選択・再生ヘッド・オンの状態に使われます。',
    'sheetFormatTitle': 'シート書式',
    'sheetFieldTitle': 'タイトル',
    'sheetFieldEpisode': '話数',
    'sheetFieldScene': 'シーン',
    'sheetFieldCut': 'カット',
    'sheetFieldTime': 'タイム',
    'sheetFieldName': '作画者',
    'sheetFieldSheet': 'シート',
    'workSettingsTitle': '作品設定',
    'workSettingsStaff': 'スタッフ設定',
    'workLogo': '会社ロゴ',
    'workCover': '表紙の絵',
    'staffWorker': '作業者',
    'sheetVisibleBoxes': '表示する枠',
    'sheetStretchLineAction': '引き伸ばし線・ACTION',
    'sheetStretchLineCell': '引き伸ばし線・CELL',
    'sheetStretchLineHelp': 'N コマ以上の止め・× で (N+1) コマ目から線を引く',
    'sheetStretchLineOn': 'あり',
    'sheetStretchLineOff': 'なし',
    'sheetSeEmptyFill': 'セリフのない区間',
    'sheetLength': 'シートの長さ',
    'sheetThreeSeconds': '3秒',
    'sheetSixSeconds': '6秒',
    'sheetFillOn': '塗る',
    'sheetFillOff': '塗らない',
    'sheetBrushAllow': 'ブラシを許可',
    'conteCoverPage': '表紙',
    'conteBlankPage': '白紙',
    'conteFormatTitle': 'コンテ用紙書式',
    'conteFrontIn': '入れる',
    'conteFrontOut': '入れない',
    'conteForm': '様式',
    'conteFormAnalog': 'アナログ',
    'conteFormDigital': 'デジタル',
    'conteOutline': '画面の黒枠',
    'conteOutlineOn': 'あり',
    'conteOutlineOff': 'なし',
    'envelopeFormatTitle': 'カット袋書式',
    'envelopeForm': '様式',
    'sheetModeNotation': '表記シート（リピート・止めの文字）',
    'sheetModeData': 'データシート（書き出しのまま）',
    'instructionsTitle': '指示記号',
    'instructionEditTooltip': '指示記号を編集',
    'instructionDeleteTooltip': '指示記号を削除',
    'instructionAddButton': '新規指示記号',
    'instructionDefTitle': '指示記号',
    'instructionDefNameLabel': '名前（FI、PAN など）',
    'instructionEventEditTitle': '指示の編集',
    'instructionEventAddTitle': '新規指示',
    'instructionMarkLabel': '指示（記号）',
    'instructionMarkNone': '（なし）',
    'instructionNameLabel': '名前（空欄なら記号名）',
    'instructionStartLabel': '始点名（A）',
    'instructionEndLabel': '終点名（B）',
    'instructionEditSetButton': '指示記号を編集',
    'instructionEditorIcon': 'アイコン',
    'instructionEditorColor': '色',
    'instructionEditorMark': '記号',
    'systemStatusHelp':
        '各サブシステムが今どの実装で動いているかです。フォールバック経路でもアプリは動きますが、たいていは遅くなります — 詳しく知りたいときは名前で検索できます。',
    'shortcutShelf.canvas': 'カンバス',
    'shortcutShelf.tools': 'ツール',
    'shortcutShelf.toolTiles': 'サブツール',
    'shortcutShelf.blendModes': '合成モード',
    'shortcutShelf.selection': '選択',
    'shortcutShelf.edit': '編集',
    'shortcutShelf.view': '表示',
    'shortcutShelf.timeline': 'タイムライン・コンテ',
    'shortcutShelf.moves': 'ナビゲーション',
    'shortcutShelf.playback': '再生',
    'shortcutShelf.pills': 'ピル',
    'shortcutShelf.cutPill': 'カットのピル',
    'shortcutShelf.layerPill': 'レイヤーのピル',
    'shortcutShelf.framePill': 'フレームのピル',
    'shortcutShelf.fxPill': 'FXのピル',
    'shortcutShelf.sharedPill': '共用のピル',
    'shortcutShelf.colourEdit': '色編集',
    'shortcutShelf.layerHeader': 'レイヤーヘッダー',
    'shortcutShelf.timelineBar': 'タイムラインのバー',
    'shortcutShelf.toolLibrary': 'ツールライブラリ',
    'shortcutShelf.brushLibrary': 'ブラシライブラリ',
    'shortcutShelf.brushToolBrushes': 'ブラシツールのブラシ',
    'shortcutShelf.eraserToolBrushes': '消しゴムツールのブラシ',
    'shortcutShelf.guides': 'ガイド',
    'shortcutShelf.texts': 'テキスト',
    'shortcutShelf.topStrip': '上部のバー',
    'shortcutShelf.file': 'ファイル',
    'shortcutShelf.settings': '設定',
    'shortcutShelf.panels': 'パネル',
    'shortcutShelf.debug': 'デバッグ',
    'shortcutShelf.inAPanel': 'パネルの中',
    'shortcutShelf.media': 'メディア',
    'shortcutShelf.timesheet': 'タイムシート',
    'shortcutShelf.conteSheet': 'コンテ用紙',
    'shortcutShelf.envelope': 'カット袋',
    'shortcutShelf.palette': 'パレット',
    'shortcutPreset.clipStudio': 'CLIP STUDIO ベース',
    'shortcutPreset.tvpaint': 'TVPaint ベース',
    'shortcutAction.frame-previous': '前のフレーム',
    'shortcutAction.frame-next': '次のフレーム',
    'shortcutAction.drawing-previous': '前のブロック',
    'shortcutAction.drawing-next': '次のブロック',
    'shortcutAction.playback-toggle': '再生 / 一時停止',
    'shortcutAction.playback-to-start': '先頭へ',
    'shortcutAction.playback-loop-toggle': 'ループ / 1回再生',
    'shortcutAction.canvas-pan-hold': '移動（押している間）',
    'shortcutAction.canvas-rotate-hold': '回転（押している間）',
    'shortcutAction.canvas-line-hold': '直前のストロークから直線（押している間）',
    'shortcutAction.voice-record-toggle': '音声収録（開始/停止）',
    'shortcutAction.edit-undo': '元に戻す',
    'shortcutAction.edit-redo': 'やり直す',
    'shortcutAction.tool-brush': 'ブラシツール',
    'shortcutAction.tool-eraser': '消しゴムツール',
    'shortcutAction.tool-eyedropper': 'スポイトツール',
    'shortcutAction.tool-fill': '塗りつぶしツール',
    'shortcutAction.tool-fill-bucket': '塗りつぶし',
    'shortcutAction.tool-text': 'テキストツール',
    'shortcutAction.tool-shape': '図形ツール',
    'shortcutAction.tool-guide': 'ガイドツール',
    'shortcutAction.guide-add-symmetry': '新規対称ガイド',
    'shortcutAction.guide-add-perspective': '新規パースガイド',
    'shortcutAction.timesheet-data-mode': '表記シート / データシート',
    'shortcutAction.tool-select': '選択ツール',
    'shortcutAction.tool-transform': '変形ツール',
    'shortcutAction.tool-transform-normal': '通常変形',
    'shortcutAction.tool-transform-free': '自由変形',
    'shortcutAction.tool-transform-mesh': 'メッシュワープ',
    'shortcutAction.tool-cut': '切り抜きツール',
    'shortcutAction.tool-cut-whole': '全体カット',
    'shortcutAction.tool-cut-stamp': 'スタンプ',
    'shortcutAction.selection-deselect': '選択解除',
    'shortcutAction.layer-up': 'レイヤーを上へ',
    'shortcutAction.layer-down': 'レイヤーを下へ',
    'shortcutAction.edit-confirm': '確定',
    'shortcutAction.selection-transform-cancel': '変形をキャンセル',
    'shortcutAction.transform-flip-horizontal': '変形を左右反転',
    'shortcutAction.transform-flip-vertical': '変形を上下反転',
    'shortcutAction.transform-reset': '変形をリセット',
    'shortcutAction.cut-stamp-reset': 'スタンプをリセット',
    'shortcutAction.onion-skin-toggle': 'オニオンスキンの切り替え',
    'shortcutAction.camera-view-toggle': 'カメラビューの切り替え',
    'shortcutAction.canvas-rotate-ccw': 'カンバス表示を左に回転',
    'shortcutAction.canvas-rotate-cw': 'カンバス表示を右に回転',
    'shortcutAction.canvas-flip-horizontal': 'カンバス表示を左右反転',
    'shortcutAction.canvas-flip-vertical': 'カンバス表示を上下反転',
    'shortcutAction.canvas-straighten': 'カンバス表示の傾きをリセット',
    'shortcutAction.canvas-fit': 'カンバス表示を画面に合わせる',
    'shortcutAction.canvas-reset-view': 'カンバスのズームをリセット（100%）',
    'shortcutAction.timeline-comma-1': '1コマに設定',
    'shortcutAction.timeline-comma-2': '2コマに設定',
    'shortcutAction.timeline-comma-3': '3コマに設定',
    'shortcutAction.timeline-comma-4': '4コマに設定',
    'shortcutAction.timeline-comma-n': 'Nコマに設定',
    'shortcutAction.frame-new-drawing': '新規フレーム',
    'shortcutAction.layer-add': '新規レイヤー',
    'shortcutAction.frame-blank-exposure': '空にする',
    'shortcutAction.frame-toggle-mark-one': '中割りマーク1',
    'shortcutAction.frame-toggle-mark': '中割りマーク2',
    'shortcutAction.frame-mark-every': '中割りマークを自動追加',
    'shortcutAction.timeline-push-blocks': '押し出し（コマを開ける）',
    'shortcutAction.timeline-pull-blocks': '詰め（コマを詰める）',
    'shortcutAction.timeline-zoom-in': 'タイムラインを拡大',
    'shortcutAction.timeline-zoom-out': 'タイムラインを縮小',
    'shortcutAction.timeline-zoom-fit': 'タイムラインを全体表示',
    'shortcutAction.timeline-orientation-toggle': 'タイムライン / Xシート',
    'shortcutAction.edit-cut': '切り取り',
    'shortcutAction.edit-copy': 'コピー',
    'shortcutAction.edit-paste-linked': 'リンクして貼り付け',
    'shortcutAction.edit-paste-independent': '独立して貼り付け',
    'shortcutAction.edit-unlink': 'リンクから独立',
    'shortcutAction.edit-delete': '削除',
    'shortcutAction.edit-duplicate': '複製',
    'shortcutAction.edit-merge': '結合',
    'shortcutAction.edit-replace-colour': '色変換',
    'shortcutAction.edit-clear-pixels': 'ピクセル消去',
    'shortcutAction.edit-binarize': '2値化',
    'shortcutAction.edit-delete-colour': '色削除',
    'shortcutAction.edit-keep-colour': '色残し',
    'shortcutAction.edit-cut-pixels': 'ピクセル切り取り',
    'shortcutAction.edit-copy-pixels': 'ピクセルコピー',
    'shortcutAction.edit-paste-pixels-above': 'ピクセルを上に貼り付け',
    'shortcutAction.edit-paste-pixels-below': 'ピクセルを下に貼り付け',
    'shortcutAction.edit-instance': '編集',
    'shortcutAction.edit-auto-name': '自動命名',
    'blendMode.passThrough': '通過',
    'blendMode.normal': '通常',
    'blendMode.color': '通常',
    'blendMode.behind': '背面',
    'blendMode.erase': '消去',
    'blendMode.darken': '比較（暗）',
    'blendMode.multiply': '乗算',
    'blendMode.colorBurn': '焼き込みカラー',
    'blendMode.lighten': '比較（明）',
    'blendMode.screen': 'スクリーン',
    'blendMode.colorDodge': '覆い焼きカラー',
    'blendMode.add': '加算',
    'blendMode.overlay': 'オーバーレイ',
    'blendMode.softLight': 'ソフトライト',
    'blendMode.hardLight': 'ハードライト',
    'blendMode.difference': '差の絶対値',
    'blendMode.exclusion': '除外',
    'blendMode.linearBurn': '焼き込み（リニア）',
    'blendMode.subtract': '減算',
    'blendMode.vividLight': 'ビビッドライト',
    'blendMode.linearLight': 'リニアライト',
    'blendMode.pinLight': 'ピンライト',
    'blendMode.hardMix': 'ハードミックス',
    'blendMode.darkerColor': 'カラー比較（暗）',
    'blendMode.lighterColor': 'カラー比較（明）',
    'blendMode.divide': '除算',
    'blendMode.hue': '色相',
    'blendMode.saturation': '彩度',
    'blendMode.chroma': 'カラー',
    'blendMode.luminosity': '輝度',
    'effectKind.brightnessContrast': '輝度＆コントラスト',
    'effectKind.hueSaturation': '色相/彩度',
    'effectKind.blur': 'ブラー（ガウス）',
    'effectKind.directionalBlur': 'ブラー（方向）',
    'effectKind.radialBlur': 'ブラー（放射状）',
    'effectKind.cameraLensBlur': 'ブラー（カメラレンズ）',
    'effectKind.colorKey': 'カラーキー',
    'effectKind.celNumber': 'セル番号',
    'effectParameter.brightness': '輝度',
    'effectParameter.contrast': 'コントラスト',
    'effectParameter.hue': 'マスターの色相',
    'effectParameter.saturation': 'マスターの彩度',
    'effectParameter.lightness': 'マスターの明度',
    'effectParameter.blurriness': 'ブラー',
    'effectParameter.blurDimensions': 'ブラーの方向',
    'effectParameter.repeatEdgePixels': 'エッジピクセルを繰り返す',
    'effectParameter.direction': '方向',
    'effectParameter.blurLength': 'ブラーの長さ',
    'effectParameter.keyColor': 'キー色',
    'effectParameter.ink': '色',
    'effectParameter.tolerance': '許容値',
    'effectParameter.amount': '適用量',
    'effectParameter.keyOperation': 'キー操作',
    'effectParameter.center': '中心',
    'effectParameter.type': '種類',
    'effectParameter.antialiasing': 'アンチエイリアス',
    'effectParameter.blurRadius': 'ブラーの半径',
    'effectParameter.irisShape': 'シェイプ',
    'effectParameter.irisRoundness': '真円率',
    'effectParameter.irisAspectRatio': '縦横比',
    'effectParameter.irisRotation': '回転',
    'effectParameter.irisDiffractionFringe': '回折フリンジ',
    'effectParameter.blurMapLayer': 'ブラーマップのレイヤー',
    'effectParameter.blurMapChannel': 'ブラーマップのチャンネル',
    'effectParameter.blurFocalDistance': 'ブラーの焦点距離',
    'effectParameter.invertBlurMap': 'ブラーマップを反転',
    'effectParameter.highlightGain': 'ハイライトのゲイン',
    'effectParameter.highlightThreshold': 'ハイライトのしきい値',
    'effectParameter.highlightSaturation': 'ハイライトの彩度',
    'effectParameter.useLinearWorkingSpace': 'リニア化された作業スペースを使用',
    'effectChoice.keyColors': 'キーカラー',
    'effectChoice.keepColors': 'カラー維持',
    'effectChoice.horizontalAndVertical': '水平および垂直',
    'effectChoice.horizontal': '水平',
    'effectChoice.vertical': '垂直',
    'effectChoice.spin': '回転',
    'effectChoice.zoom': 'ズーム',
    'effectChoice.best': '最高',
    'effectChoice.draft': 'ドラフト',
    'effectChoice.triangle': '三角形',
    'effectChoice.square': '正方形',
    'effectChoice.pentagon': '五角形',
    'effectChoice.hexagon': '六角形',
    'effectChoice.heptagon': '七角形',
    'effectChoice.octagon': '八角形',
    'effectChoice.nonagon': '九角形',
    'effectChoice.decagon': '十角形',
    'effectChoice.luminance': '輝度',
    'effectChoice.red': '赤',
    'effectChoice.green': '緑',
    'effectChoice.blue': '青',
    'effectChoice.alpha': 'アルファ',
    'selectionMode.replace': '新規選択',
    'selectionMode.add': '追加選択',
    'selectionMode.subtract': '部分解除',
    'selectionMode.intersect': '選択中',
    'shortcutAction.file-save': '保存',
    'shortcutAction.file-save-as': '名前を付けて保存',
    'shortcutAction.layer-visibility-solo': 'アクティブレイヤーをソロ',
    'shortcutAction.canvas-zoom-in': 'ズームイン',
    'shortcutAction.canvas-zoom-out': 'ズームアウト',
    'cutCommands': 'カット操作',
    'shortcutAction.cut-new': '新規カット',
    'shortcutAction.cut-edit-note': 'カットメモを編集',
    'shortcutAction.cut-settings': 'カット設定',
    'cutSettingsTitle': 'カット設定',
    'mediaActions': 'メディア操作',
    'mediaPoolEmpty': 'メディアがありません',
    'mediaRename': 'メディア名を変更',
    'mediaPlace': '配置',
    'mediaRelink': '再リンク',
    'mediaMissingCount': '見つからないファイル {n} 個',
    'mediaFindInFolder': 'フォルダーから探す',
    'mediaRelinkFound': '{n} 件中 {m} 件が見つかりました。再リンクしますか？',
    'mediaRelinkScanning': 'フォルダーを読み込み中…',
    'mediaRelinkScanned': '読み込みました',
    'mediaRemove': 'メディアを削除',
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
    'mediaViewerEmpty': '表示するものがありません',
    'mediaViewerOpenFile': 'ファイルを開く',
    'mediaViewerCloseFile': 'ファイルを閉じる',
    'mediaViewerLoadFailed': 'このファイルを読み込めませんでした。',
    'mediaViewerCutTooLarge': 'メモリ許容量に収まらないため、原寸で切り取れません。',
    'mediaViewerCannotDisplay': 'この種類のメディアはまだ表示できません。',
    'mediaViewerNoPdfRenderer': 'このビルドにはPDFレンダラーがありません — PDFページを表示できません。',
    'mediaViewerNoVideoDecoder': 'このビルドには動画デコーダーがありません — 動画を表示できません。',
    'mediaViewerNoAudioDecoder': 'この音声を読み込めませんでした — 波形を表示できません。',
    'mediaViewerSwap': 'もう一方のビューアと入れ替え',
    'unsupportedFileTitle': 'サポートされていないファイル',
    'unsupportedFileMessageTemplate':
        'サポートされていないファイルが検出されました。使用できる形式: {kinds}。',
    'mediaViewerRegisterAsset': 'メディアに登録',
    'panelMediaViewer': 'ビューア',
    'panelMediaViewerSub': 'サブビューア',
    'panelCanvas': 'カンバス',
    'panelColorWheel': 'カラーホイール',
    'transportIn': 'イン',
    'transportOut': 'アウト',
    'transportToStart': '先頭へ',
    'transportToEnd': '末尾へ',
    'transportLoop': 'ループ',
    'transportOnce': '1回再生',
    'transportPrevFrame': '前のフレーム',
    'transportNextFrame': '次のフレーム',
    'colorRecent': '最近',
    'colorBackgroundSwap': '背景色（タップで入れ替え）',
    'paletteViewCompact': 'コンパクト',
    'paletteViewCards': 'カード',
    'paletteNew': '新しいパレット',
    'paletteNumberedTemplate': 'パレット {n}',
    'paletteMakeDefault': 'デフォルトにする',
    'paletteDuplicate': '複製',
    'paletteExport': '書き出し',
    'paletteBroughtTemplate': 'パレット「{name}」を追加しました。',
    'paletteCopyTemplate': '{name} のコピー',
    'paletteDeleteTitle': 'パレットを削除',
    'paletteDeleteTemplate': 'パレット「{name}」を削除しますか？',
    'paletteRemoveCurrent': '今の色を外す',
    'paletteLock': 'パレットをロック',
    'paletteMore': 'その他',
    'penPressureTitle': '筆圧',
    'brushDynamicsTitle': '入り抜き',
    'curveSourcePressure': '筆圧',
    'curveSourceTilt': '傾き',
    'curveSourceSpeed': '速度',
    'curveSourceRandom': 'ランダム',
    'curveMinimum': '最小値',
    'curveMaximum': '最大値',
    'curveTiltFlat': '水平',
    'curveTiltUpright': '垂直',
    'onionCurrentDrawing': '現在の絵',
    'audioLevelMeter': '音声レベルメーター',
    'panelColorRgb': 'RGB',
    'panelColorPalette': 'パレット',
    'panelMedia': 'メディア',
    'panelOnionSkin': 'オニオンスキン',
    'panelToolSize': 'ツールサイズ',
    'panelStoryboard': 'コンテ',
    'panelTimeline': 'タイムライン',
    'panelTimesheet': 'タイムシート',
    'panelConte': 'コンテ用紙',
    'panelEnvelope': 'カット袋',
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
    'onionBeforeTint': '前の色',
    'onionAfterTint': '後の色',
    'onionGhostColorHelp': 'ゴーストの色付け方',
    'onionPegCountHelp': '1段が数えるもの',
    'onionPlacementHelp': 'ゴーストの置き場所',
    'onionStepBlocks': 'ブロック',
    'onionStepBlocksDrawings': 'ブロック（絵）',
    'onionStepFrames': 'フレーム',
    'onionModeColors': '色',
    'onionModeImages': '絵',
    'onionPlacementOnTop': '最前面',
    'onionPlacementInPlace': 'その場',
    'onionPegBeforeTemplate': '前 {n}',
    'onionPegAfterTemplate': '後 {n}',
    'shortcutTitle': 'キーボードショートカット',
    'shortcutResetAll': 'すべてリセット',
    'shortcutFileImportedTemplate':
        'ショートカット {taken} 件を新しいプリセット「{preset}」に'
        '取り込みました（対応なし {skipped} 件）。',
    'shortcutPresets': 'プリセット',
    'shortcutPresetNew': '新しいプリセット',
    'shortcutPresetNameEmpty': 'プリセット名を空にはできません。',
    'shortcutPresetDelete': 'プリセットを削除',
    'shortcutPresetRename': 'プリセット名を変更',
    'shortcutPresetDuplicate': 'プリセットを複製',
    'shortcutPresetExport': 'プリセットを書き出し',
    'shortcutPresetBroughtTemplate': 'プリセット「{name}」を追加しました。',
    'shortcutPresetCopyTemplate': '{name} のコピー',
    'shortcutPresetDeleteTemplate': 'プリセット「{name}」を削除しますか？',
    'shortcutFileUnreadableTemplate':
        '{name}: このファイルから読めるショートカットがありません。',
    'shortcutResetToDefault': '既定に戻す',
    'shortcutUnassign': 'ショートカットを解除',
    'shortcutRecordNew': '新しいショートカットを記録',
    'shortcutTouch': 'タッチショートカット',
    'shortcutSearch': 'アクションを検索',
    'shortcutConflictBanner':
        '同じキーを共有しているアクションがあります — 強調された割り当てが'
        '衝突しています。',
    'shortcutRecordingHint': 'キーを押してください…（Escで中止）',
    'playbackMode': '再生方式',
    'playbackModeSkipFrames': 'フレームを飛ばす',
    'playbackModeEveryPicture': 'すべてのフレーム',
    'playbackModeRenderFirst': '再生前にレンダリング',
    'playbackDroppedCount': '{n}コマ落ち',
    'playbackDroppedCountOne': '{n}コマ落ち',
    'playbackSilentCount': '音声{n}件 再生不可',
    'playbackSilentCountOne': '音声{n}件 再生不可',
    'playbackOutputRefused': '音が出ません — 出力デバイスを開けませんでした。',
    'soundCannotPlay.missing': '再生できません — ファイルがありません。',
    'soundCannotPlay.notReadYet':
        'まだ再生できません — ファイルを読めませんでした（クラウドのファイルがまだダウンロード中かもしれません）。',
    'soundCannotPlay.format': '再生できません — この形式を読めるデコーダーがありません。',
    'soundCannotPlay.conform': '再生できません — 再生用の変換に失敗しました。',
    'soundCannotPlay.deviceRate':
        '再生できません — 出力のサンプルレートに変換できませんでした。',
    'playbackStop': '停止',
    'sheetPreviousPage': '前のページ',
    'sheetNextPage': '次のページ',
    'sheetPageDrag': 'ページ（ドラッグ）',
    'autosaveTitle': '自動保存',
    'autosaveEvery': '間隔',
    'autosaveSectionHelp':
        '一定間隔でプロジェクトを保存するので、クラッシュや電池切れで失う作業は最大でもその間隔ぶんです。',
    'autosaveSwitchHelp': 'オフにすると、プロジェクトは保存したときだけ変わり、クラッシュすればそれ以降の作業はすべて失われます。',
    'appContainerTitle': 'アプリコンテナ',
    'appContainerHelp':
        'プロジェクトファイルの外にアプリが持つもの — 設定とブラシ先端、読み込みが取り込んだまままだどの保存にも吸収されていないメディアと音声、そして診断ログです。',
    'commonMinutesShort': ' 分',
    'exExport': '書き出し',
    'exAddToQueue': 'キューに追加',
    'exImage': '画像',
    'exVideo': '動画',
    'exCels': 'セル',
    'exFormat': '形式',
    'exOptions': 'オプション',
    'exNaming': '命名',
    'exScope': '範囲',
    'exQuality': '画質',
    'exCodec': 'コーデック',
    'exBitrate': 'ビットレート',
    'exChannels': 'チャンネル',
    'exAudio': '音声',
    'exHandOverDeclined': '渡さなかったため、書き出した結果は破棄しました。',
    'exHandOverPending': '書き出した結果をまだ渡していません。',
    'exHandOverPickAgain': '選び直す',
    'exHandOverDiscard': '破棄',
    'exSavePreset': 'プリセットを保存',
    'exPresetNameEmpty': 'プリセット名を空にはできません。',
    'exBaseName': 'ベース名',
    'exSuffix': '接尾辞',
    'exPrefix': '接頭辞',
    'exLayDirection': 'この絵にディレクションを適用',
    'exLayGuides': 'ガイド',
    'exCelFormat': 'セル形式',
    'exTimesheetFormat': 'タイムシート形式',
    'exEnvelopeFormat': 'カット袋形式',
    'exWrittenCount': '{n}枚',
    'exWrittenCountOne': '{n}枚',
    'noticeExportNoPicture': 'このセルにはオンの行の絵がありません',
    'noticeExportNotPlaced': 'タイムラインに置かれていない絵です',
    'noticeExportSameName': '同じ名前の行がこの絵を書き出します',
    'exDigits': '桁数',
    'exApplyLayerFx': 'レイヤーFX',
    'exMuxSeMix': 'SEミックスを動画に多重化',
    'exLabel': 'ラベル',
    'exApply': '適用',
    'exKinds': '書き出す種類',
    'exLayerFilter': 'レイヤー',
    'exSelBase': '基準',
    'exCelsLayersOut': '出力するレイヤー',
    'exSelAttach': 'アタッチ',
    'exSelSheet': 'シートのみ',
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
    'exStratumPaper': '用紙',
    'exStratumForm': '書式',
    'exStratumContent': 'テキスト',
    'exStratumPicture': '絵',
    'exStratumInk': 'インク',
    'exLeftOutOfTheFile': 'ファイルに収められなかったものがあります。',
    'exNoCels': '（セルなし）',
    'exNoCuts': '（カットなし）',
    'exPresets': 'プリセット',
    'exQueue': 'キュー',
    'exSize': 'サイズ',
    'exCutSize': 'カットサイズ',
    'exRealSheet': '実寸用紙',
    'imNotTvpp': 'このファイルはTVPaintプロジェクトとして読めません。',
    'imNotClip': 'このファイルはCLIP STUDIO PAINTのファイルとして読めません。',
    'imLeftBehind': '一部を取り込めませんでした。',
    'imWarningCount': '警告 {n} 件',
    'imWarningCountOne': '警告 {n} 件',
    'imFileUnreadable': 'ファイルを読めませんでした — クラウド上のファイルなら、少し後にもう一度お試しください。',
    'imNotFoundTemplate': '見つかりません: {path}',
    'importWarning.stagedCopy': 'その場で読めなかったため一時コピーから開きました — この文言が出たら知らせてください。',
    'importWarning.soundMissing': 'この場所に音声ファイルがありません: {path}',
    'importWarning.celUnreadable': '{file}: 絵を読めませんでした — {detail}',
    'importWarning.psdBitDepth': '{depth}ビットのドキュメントを8ビットに落としました。',
    'importWarning.psdVectorMask': '{name}: ベクターマスクを無視しました。',
    'importWarning.psdComposite': '合成画像の圧縮形式 {compression} には対応していません — 飛ばしました。',
    'importWarning.psdExtraChannels': 'ドキュメントの余分なチャンネルを無視しました。',
    'importWarning.psd32Bit': '32ビットの予測チャンネルデータには対応していません。',
    'importWarning.psdDuotone': 'ダブルトーンをグレースケールとして読みました。',
    'importWarning.psdMultichannel': 'マルチチャンネルを最初のチャンネルのグレースケールとして読みました。',
    'importWarning.psdIndexedNoPalette': 'パレットのないインデックスカラーをグレースケールとして読みました。',
    'importWarning.psdCmyk': 'CMYKをプロファイルなしでRGBに変換しました — 色が変わります。',
    'importWarning.psdLab': 'LabをプロファイルなしでRGBに変換しました — 色が変わります。',
    'importWarning.clippingNotApplied': '{name}: クリッピングマスクは適用しませんでした。',
    'importWarning.layerEffectsNotApplied': '{name}: レイヤー効果は適用しませんでした。',
    'importWarning.layerMaskNotApplied': '{name}: レイヤーマスクは適用しませんでした。',
    'importWarning.lockNotImported': '{name}: ロックは読み込みませんでした。',
    'importWarning.psdBlend': '{name}: 描画モード「{mode}」に相当するものがありません — 通常にしました。',
    'importWarning.folderNothing': 'このフォルダーに取り込めるセルや画像はありませんでした。',
    'importWarning.folderNoCutNumber': 'フォルダー名にカット番号が見つかりません。',
    'importWarning.tvpNoFile': '{name}: フレーム{frame}のインスタンスがファイル名を持ちません — そのセルは空のままです。',
    'importWarning.tvpMuted': '{file}: トラックはミュートでした — 音はそのまま繋いでいます。',
    'importWarning.tvpBlend': '{name}: 描画モード「{mode}」に相当するものがAnicelにありません — 通常として取り込みました。',
    'importWarning.tvppHoldNoDrawing': '{name}: フレーム{frame}のホールドが受け継ぐ絵がありません。',
    'importWarning.tvppChunkBroken': 'クリップ{n}: @{at} でチャンクの連なりが切れました — 以降のデータは捨てます。',
    'importWarning.clipRead': 'ファイルの一部をたどれませんでした: {detail}',
    'importWarning.clipFps': 'タイムラインごとにフレームレートが違います — プロジェクトは最初のタイムラインの {fps} fps にしました。',
    'importWarning.clipUnplaced': '{name}: どのタイムラインにも置かれていないセルが{count}枚あります — 取り込みませんでした。',
    'importWarning.clipNoSuchCel': '{name}: フォルダーにないセルを指すキーが{count}個あります。',
    'importWarning.clipCelLayers': '{name}: セルの中のレイヤーは、ほかのセルと同じ名前なら名前で、それ以外は上から何番目かで行に分けました — それぞれの名前とフォルダーは残りません。',
    'importWarning.clipSpread': '{name}: {count}枚のセルで、フォルダーの不透明度や合成モードを中の各レイヤーに分けて付けました — レイヤーが重なる所は見え方が変わることがあります。',
    'importWarning.clipLineOrder': '{name}: {count}枚のセルで、2枚のレイヤーの重なり順がCLIP STUDIOと逆になりました — レイヤーが重なる所は見え方が変わることがあります。',
    'importWarning.clipVector':
        '{name}: ベクターレイヤー — 丸ペンで描画しました。ブラシの形と質感は再現していません。',
    'importWarning.clipVectorUnread':
        '{name}: 読めない種類のベクター線 {count} 本 — 描画していません。',
    'importWarning.clipSound': '{name}: 音声レイヤーは取り込みませんでした。',
    'importWarning.clipSoundMissing':
        '{name}: その音声がファイルに入っていません — 再生しません。',
    'importWarning.clipSoundSpeed':
        '{name}: CLIP STUDIO では別の速度で再生しています — ここでは元の速度で再生します。',
    'importWarning.clipSoundVolume':
        '{name}: クリップの途中で音量が変わります — クリップの始まりの音量にしました。',
    'importWarning.clipCurve':
        '{name}: 読み込めない補間のキーがあります — その間はまっすぐ動きます。',
    'importWarning.unsupportedLayerKind':
        '{name}: このレイヤーの種類には対応していません。',
    'importWarning.clipBlend': '{name}: 合成モード {mode} に相当するものがありません — 通常にしました。',
    'importWarning.clipNotColour': '{name}: グレー・モノクロのレイヤー — 描画していません。',
    'importWarning.clipTransform': '{name}: 画像の拡大縮小・回転は適用していません。',
    'importWarning.clipTextUnread': '{name}: 設定を読めないテキスト — 取り込みませんでした。',
    'importWarning.clipTextAlign':
        '{name}: このアプリでは組めない揃え方の行 — CLIP STUDIO が描いたまま表示し、編集すると一つの揃え方で組み直します。',
    'importWarning.clipTextSpacing':
        '{name}: 不揃いな行間 — CLIP STUDIO が描いたまま表示し、編集すると均等な行間で組み直します。',
    'importWarning.clipTextDistorted':
        '{name}: 歪んだテキスト — CLIP STUDIO が描いたまま表示し、編集すると歪みなしで組み直します。',
    'importWarning.clipTextSetHere':
        '{name}: このアプリで組んだテキスト — CLIP STUDIO が描いた画像がファイルにないか、読めませんでした。',
    'importWarning.brushPackUnreadable':
        'このファイルは Anicel のブラシファイルとして読み込めません。',
    'importWarning.brushPackNotOurs': 'このファイルは Anicel のブラシファイルではありません。',
    'importWarning.brushPackNewer':
        'このブラシファイルは新しいバージョンの Anicel で書かれています（形式 {version}）。'
        'このビルドが読めるのは {readable} までです。',
    'importWarning.brushPackEmpty': 'このブラシファイルにはブラシが入っていません。',
    'importWarning.brushPackDamaged': 'このブラシファイルは壊れていて読み込めませんでした。',
    'importWarning.abrTooShort': 'ABR ファイルとしては短すぎます。',
    'importWarning.abrOldVersion':
        'ABR バージョン {version}（Photoshop 6 の頃）にはまだ対応していません。'
        '新しい Photoshop でブラシを保存し直してください。',
    'importWarning.abrUnknownVersion': '対応していない ABR ファイルです（バージョン {version}）。',
    'importWarning.abrCorruptSection': 'ABR のセクションの長さが壊れています。',
    'importWarning.abrNoBrushes': 'ABR ファイルにブラシが見つかりません。',
    'importWarning.abrNothingImportable': 'ABR ファイルに読み込めるブラシがありませんでした。',
    'importWarning.sutCannotOpen': 'ファイルを開けませんでした: {error}',
    'importWarning.sutUnreadable':
        'このファイルは読み込める CLIP STUDIO のブラシではありません（{error}）。',
    'importWarning.sutNoBrushData': 'このファイルに CLIP STUDIO のブラシデータが見つかりません。',
    'importWarning.sutNothingImportable': 'ファイルに読み込めるブラシがありませんでした。',
    'fileType.anicel': 'Anicel プロジェクト',
    'fileType.wav': 'WAV 音声',
    'fileType.anibrush': 'Anicel ブラシ',
    'exclusionReason.processSubfolder': '工程サブフォルダー（アーカイブ）',
    'exclusionReason.unrecognized': '認識できない名前',
    'exclusionReason.excludedName': '除外する名前',
    'exclusionReason.memoText': 'メモのテキスト',
    'exclusionReason.insertionLettersOff': '中割り記号はオフ',
    'exFrameCount': '{n}フレーム',
    'exFrameCountOne': '{n}フレーム',
    'exPageCount': '{n}ページ',
    'exPageCountOne': '{n}ページ',
    'exFileCount': '{n}ファイル',
    'exFileCountOne': '{n}ファイル',
    'exJobCount': 'ジョブ{n}件',
    'exJobCountOne': 'ジョブ{n}件',
    'exContePageCount': 'コンテ{n}ページ',
    'exContePageCountOne': 'コンテ{n}ページ',
    'exCancelledAfterTemplate': '{count}を書き出したところで中止しました。',
    'exCancelledVideoTemplate': '{count}を書き出したところで中止しました（途中までの動画は残しています）。',
    'exCancelled': '書き出しを中止しました。',
    'exDoneTemplate': '{count}を書き出しました。',
    'exDoneSkippedTemplate': '{count}を書き出しました（空の{skipped}件は飛ばしました）。',
    'exDoneFileTemplate': '{name}を書き出しました。',
    'exDoneVideoTemplate': '動画を書き出しました（{count}）。',
    'exDoneConteDocumentTemplate': '{name}を書き出しました（{count}）。',
    'exNothingInFrame': '書き出すものがありません（空のフレーム）。',
    'exFailedTemplate': '書き出しに失敗しました: {error}',
    'exQueueRestTemplate': 'キュー: {count}完了{failed}{rest}。',
    'exQueueFailedTemplate': '、{n}件失敗',
    'exQueueRestKept': '、残りは保持',
    'exFileLabel': 'ファイル',
    'exOrderAsksFirst': '場所を指定してから書き出します',
    'exOrderAsksAfter': '書き出したあとに場所を指定します',
    'exSeMuxedTemplate': 'SE多重化 · {codec}',
    'exVectorPdf': 'ベクターPDF',
    'exFxOn': 'FXオン',
    'exFxOff': 'FXオフ',
    'exFxBasic': 'FX基本のみ',
    'exFxBasicOnly': '基本のみ',
    'exTabSequence': '連番',
    'exSizeCamera': 'カメラ',
    'exSizeCanvas': 'キャンバス',
    'exPageImage': 'ページ画像',
    'exSaveCurrent': '+ 現在の設定を保存',
    'exRenderQueue': 'レンダーキュー',
    'exRenderAll': 'すべてレンダー',
    'exJobQueued': '待機中',
    'exJobDone': '完了',
    'exJobFailed': '失敗',
    'exJobCancelled': '中止',
    'exJobTemplate': 'ジョブ{id} · {tab}',
    'exIncludeAll': 'すべて',
    'exCutsIncludedTemplate': '{n} / {total} カット',
    'exNeedsFfmpeg': 'このマシンのPATHにFFmpegが必要です。',
    'exCheckingEncoders': 'このマシンのエンコーダーを確認中…',
    'exNotInThisBuild': 'このビルドではまだ使えません。',
    'exBitrateAuto': '自動',
    'exCanvasTemplate': 'キャンバス {size}',
    'exCanvasPerCut': 'キャンバス（カットごと）',
    'imImport': 'インポート',
    'imFile': 'ファイル',
    'imInto': '配置先',
    'imFit': 'フィット',
    'imModified': '更新日時',
    'imSize': 'サイズ',
    'imResolution': '解像度',
    'imExcluded': '除外',
    'imFolderAsOneCut': 'カット',
    'imFolderPerRow': 'カスタム',
    'imPlaceTitleTemplate': '配置 — {name}',
    'imModeKeep': '埋め込み',
    'imModeReference': 'リンク',
    'imBake': 'ラスタライズ',
    'imOptions': 'オプション',
    'imPictureAndSound': '絵 + 音',
    'imPictureOnly': '絵のみ',
    'imSoundOnly': '音のみ',
    'imRunSpanTemplate': '{first}–{last}（{n}枚）',
    'imRateTitleTemplate': '動画 {movie}・プロジェクト {project}',
    'imRateBodyTemplate': 'プロジェクトを {movie} に合わせますか？音のタイミングは維持されます。',
    'imRateKeepTemplate': '{project} のまま',
    'imRateTakeTemplate': '{movie} に合わせる',
    'commonOn': 'オン',
    'commonOff': 'オフ',
    'imFitOriginal': '原寸',
    'imFitContain': '比率を保って伸ばす',
    'imFitStretch': '比率を無視して伸ばす',
    'imIntoNewLayer': '新規レイヤー',
    'imIntoSeRow': 'SE行',
    'imIntoRowCellTemplate': '{row} · {frame}コマ目',
    'imIntoNewCut': '新規カット',
    'imPsdMerge': 'レイヤーを統合',
    'imPsdExpand': 'レイヤーを保持',
    'imNoSource': 'ソースが選ばれていません',
    'imFileCountTemplate': '{n}個のファイル',
    'imStatusImporting': 'インポート中…',
    'imStatusNothing': '何もインポートされませんでした。',
    'imStatusDone': 'インポートしました',
    'imStepRecoding': 'トリミングした動画を再エンコード中…',
    'imStepWritingSpan': '切り出した範囲をファイルに書き出し中…',
    'imStepCarrying': 'ファイルをプロジェクトに埋め込み中…',
    'imStepRasterizing': 'セルにラスタライズ中…',
    'imFolderGone': 'そのフォルダーは見つかりません。',
    'imFolderUnreadableTemplate': 'フォルダーを読めませんでした: {reason}',
    'imCutFolderUnreadable': 'そのフォルダーを読めませんでした。',
    'imUnreadableTemplate': '{name}: ファイルを読めませんでした。',
    'imLacksPictureTemplate': '{name}: このファイルには{number}番目の画像がありません。',
    'imCorruptTemplate':
        '{name}: 開けませんでした — 破損しているか、パスワードで保護されています。',
    'imPagesFailedTemplate':
        '{name}: {n}ページを描画できませんでした — そのセルは空のままです。',
    'imFramesFailedTemplate':
        '{name}: {n}フレームをデコードできませんでした — そのセルは空のままです。',
    'imNoPdfRendererTemplate': '{name}: このビルドには PDF レンダラーがありません。',
    'imCouldNotImportTemplate': '{name}: インポートできませんでした。',
    'imPsdNoLayersTemplate':
        '{name}: 展開するレイヤーがありません — 統合で読み込んでください。',
    'imKeepExplain': 'プロジェクトファイルが圧縮して持ちます。元のファイルはそのままです。',
    'imReferenceExplain': 'ファイルはその場所に残り、プロジェクトはそれを指します。',
    'mpFileMissing': 'ファイルが見つかりません — リンクし直してください',
    'mpInUseOnTimeline': 'タイムラインで使用中',
    'mpNameEmpty': 'メディア名を入力してください。',
    'exCameraTemplate': 'カメラ {size}',
    'toolBrush': 'ブラシ',
    'toolEraser': '消しゴム',
    'toolEyedropper': 'スポイト',
    'toolFill': '塗りつぶし',
    'toolText': 'テキスト',
    'toolShape': '図形',
    'textToolSelectedText': '選択中のテキスト',
    'textToolDeleteText': 'テキストを削除',
    'textToolLetters': '文字',
    'textToolBox': 'ボックス',
    'textToolFont': 'フォント',
    'textToolSize': 'サイズ',
    'textToolTracking': '字間',
    'textToolBold': '太字',
    'textToolItalic': '斜体',
    'textToolUnderline': '下線',
    'textToolStrikethrough': '取り消し線',
    'textToolColor': '色',
    'textToolOutline': 'フチ',
    'textToolOutlineWidth': 'フチの太さ',
    'textToolAlign': '揃え',
    'textToolAlignLeft': '左',
    'textToolAlignCenter': '中央',
    'textToolAlignRight': '右',
    'textToolCentreAcross': '左右中央',
    'textToolCentreDown': '上下中央',
    'textToolBoxWidth': 'ボックス幅',
    'textToolWidthAuto': '自動',
    'textToolWidthFixed': '固定',
    'textToolLineHeight': '行間',
    'textToolLetterWidth': '水平比率',
    'textToolSkew': '傾き',
    'textToolBackground': '背景',
    'textToolIntoDrawing': 'ラスタライズ',
    'textToolWriting': '文字方向',
    'textToolWritingLines': '横書き',
    'textToolWritingColumns': '縦書き',
    'textToolAlignTop': '上',
    'textToolAlignBottom': '下',
    'textToolFontImport': 'フォントファイルを読み込み',
    'textToolFontDelete': 'フォントを削除',
    'textToolFontsOfProject': 'このプロジェクトのフォント',
    'textToolFontsOfDevice': 'このデバイスのフォント',
    'textToolFontTakeOut': 'プロジェクトから外す',
    'textToolFontStaysOnThisDevice':
        'このフォントは編集する文書への埋め込みが許可されていないため、'
        '別の端末で開くと別のフォントになります。',
    'textToolFontNotOnThisDevice': 'この端末にないフォントのため、別のフォントで表示されます。',
    'textToolFontUnreadable': 'フォントファイルとして読み込めませんでした。',
    'textToolFontIsTheApps': 'アプリにすでに入っているフォントです。',
    'textToolFontNotKept': 'フォントを保存できませんでした。',
    'toolSelect': '選択',
    'toolTransform': '変形',
    // TVPaint's own term for this verb in Japanese studios.
    'toolShapeFill': '図形の塗り',
    'toolCutNothingHeld': 'まだ何も持っていません',
    'toolCutHoldingTemplate': '{size} px を持っています',
    'toolLibraryEmpty': '表示するものがありません',
    'toolCutPasteAtOrigin': '元の位置に貼り付け',
    'toolCutFlipHorizontal': '左右反転',
    'toolCutFlipVertical': '上下反転',
    'toolCutRegisterTip': '先端として登録',
    'toolCutDeletesSource': '元画像を削除',
    'toolReadSource': '参照',
    'toolReadsEveryVisibleLayer': '表示中のすべてのレイヤー',
    'brushSettingsTitle': 'ブラシ設定',
    'toolShapeRect': '矩形',
    'toolShapeEllipse': '楕円',
    'toolShapeLasso': '投げ縄',
    'toolShapePolygon': '多角形',
    'toolShapeLine': '直線',
    'toolShapeSelectTemplate': '{shape}選択',
    'toolShapeCutTemplate': '{shape}カット',
    'toolShapeFillTemplate': '{shape}塗り',
    'toolShapeDrawTemplate': '{shape}描画',
    'shapeToolDraws': '描画',
    'shapeToolStroke': '線',
    'shapeToolFill': '塗り',
    'shapeToolType': '種類',
    'shapeToolTypePlain': '通常',
    'shapeToolCorners': '角',
    'shapeToolCornersSharp': 'シャープ',
    'shapeToolCornersRound': '丸',
    'shapeToolRatioLock': '比率を固定',
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
    'brMixing': '混色',
    'brMixingMethod': '方式',
    'brMixingMix': '下地混色',
    'brMixingBlur': 'ぼかし',
    'brPaintAmount': '絵の具量',
    'brPaintDensity': '絵の具濃度',
    'brColorStretch': '色延び',
    'brHardness': '硬さ',
    'stepUp': '1目盛り上げる',
    'stepDown': '1目盛り下げる',
    'brEdgeNone': 'なし',
    'brSpacing': '間隔',
    'brAngle': '角度',
    'brRoundness': '真円率',
    'brScale': '拡大率',
    'brScatter': '散布',
    'brScatterCount': '個数',
    'brScatterBothAxes': '両軸',
    'brTipRotation': '向き',
    'brRotationFixed': 'なし',
    'brRotationDirection': '線の方向',
    'brRotationPenTilt': 'ペンの方向',
    'brRotationPenTwist': 'ペン軸の回転',
    'brTipOrder': '繰り返し方法',
    'brTipOrderRepeat': '繰り返し',
    'brTipOrderPingPong': '折り返し',
    'brTipOrderHoldLast': '繰り返さない',
    'brTipOrderRandom': 'ランダム',
    'brTipOrderOneLap': '一巡のみ',
    'brTipOrderShuffledLap': 'ランダムに一巡',
    'brTipOrderLean': 'ペンの傾き',
    'brTipsPerTurn': '1回の先端数',
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
    'brDeleteTipBodyTemplate': '「{name}」をライブラリから削除します。',
    'brStabilizer': '手ブレ補正',
    'brStabilizerOn': '手ブレ補正を適用',
    'brStabilizerBySpeed': '速度で補正',
    'brBySpeedSlow': 'ゆっくり',
    'brBySpeedFast': 'すばやく',
    'brPostCorrection': '描いた後に補正',
    'brPostBySpeed': '速度で調整',
    'brPostByViewScale': '表示倍率で調整',
    'brPostBezier': 'ベジェ曲線',
    'brSharpenCorners': '角をとがらせる',
    'brGroupInk': 'インク',
    'brGroupTip': 'ブラシ先端',
    'brGroupMixing': '混色',
    'brGroupScattering': '散布',
    'brGroupTexture': '質感',
    'brGroupCorrection': '補正',
    'brDetailTitle': 'ブラシ詳細',
    'brShowInPanel': 'パネルに表示',
    'brHideFromPanel': 'パネルに表示しない',
    'shortcutAction.frame-auto-create': 'フレーム自動生成',
    'brBlend': '合成',
    'brBlendMode': 'ブラシの合成モード',
    'brDualBlend': 'デュアルの合成',
    'brTextureMode': 'テクスチャ合成',
    'brTextureModeHeight': '高さ',
    'brEditGroup': 'グループを編集',
    'brFolderIcon': 'フォルダーのアイコン',
    'brFolderName': 'フォルダー名',
    'brFeather': 'ぼかし',
    'brTolerance': '許容値',
    'brGapClose': '隙間閉じ',
    'brGrowShrink': '拡張 / 収縮',
    'brAntiAlias': 'アンチエイリアス',
    'brFillBeyondCanvas': 'カンバス外も塗る',
    'brOpenRegionsRefuse': '開いた領域は塗られません',
    'brName': '名前',
    'brDisplay': '表示',
    'brTipIcon': '先端アイコン',
    'brStrokePreview': 'ストロークのプレビュー',
    'brBrushOptions': 'ブラシオプション',
    'brNewGroup': 'グループを新規作成',
    'brNewGroupName': '新規グループ',
    'brNewPresetName': 'プリセット {n}',
    'builtinBrush.builtin-basic-group': '基本',
    'builtinBrush.builtin-pencil-group': '鉛筆',
    'builtinBrush.builtin-ink-group': 'ペン',
    'builtinBrush.builtin-dry-media-group': '乾式画材',
    'builtinBrush.builtin-watercolor-group': '水彩',
    'builtinBrush.builtin-paint-group': '油彩',
    'builtinBrush.builtin-airbrush-group': 'エアブラシ',
    'builtinBrush.builtin-blend-group': '色混ぜ',
    'builtinBrush.builtin-texture-group': 'テクスチャ',
    'builtinBrush.builtin-decoration-group': 'デコレーション',
    'builtinBrush.builtin-pencil': '鉛筆 HB',
    'builtinBrush.builtin-soft-pencil': '鉛筆 2B',
    'builtinBrush.builtin-mechanical-pencil': 'シャープペンシル',
    'builtinBrush.builtin-hard-pencil': '鉛筆 2H',
    'builtinBrush.builtin-dark-pencil': '鉛筆 4B',
    'builtinBrush.builtin-colored-pencil': '色鉛筆',
    'builtinBrush.builtin-coloring-pencil': '塗り色鉛筆',
    'builtinBrush.builtin-shading-pencil': '寝かせ鉛筆',
    'builtinBrush.builtin-rough-edge': 'ラフ鉛筆',
    'builtinBrush.builtin-ink-pen': 'ハード円ブラシ',
    'builtinBrush.builtin-g-pen': 'Gペン',
    'builtinBrush.builtin-maru-pen': '丸ペン',
    'builtinBrush.builtin-brush-pen': '筆ペン',
    'builtinBrush.builtin-calligraphy': 'カリグラフィ',
    'builtinBrush.builtin-marker': 'マーカー',
    'builtinBrush.builtin-kabura-pen': 'カブラペン',
    'builtinBrush.builtin-technical-pen': 'ミリペン',
    'builtinBrush.builtin-dry-ink': 'かすれインク',
    'builtinBrush.builtin-chalk-preset': 'チョーク',
    'builtinBrush.builtin-charcoal': '木炭',
    'builtinBrush.builtin-pastel': 'パステル',
    'builtinBrush.builtin-crayon': 'クレヨン',
    'builtinBrush.builtin-graphite-stick': 'グラファイトスティック',
    'builtinBrush.builtin-watercolor': '水彩',
    'builtinBrush.builtin-analog-watercolor': 'アナログ水彩',
    'builtinBrush.builtin-wet-watercolor': 'にじみ水彩',
    'builtinBrush.builtin-dense-watercolor': '濃い水彩',
    'builtinBrush.builtin-flat-wash': '平塗り',
    'builtinBrush.builtin-flat-bristle': '平筆',
    'builtinBrush.builtin-gouache': 'ガッシュ',
    'builtinBrush.builtin-oil-brush': '油彩ブラシ',
    'builtinBrush.builtin-palette-knife': 'パレットナイフ',
    'builtinBrush.builtin-dry-brush': 'ドライブラシ',
    'builtinBrush.builtin-airbrush': 'エアブラシ',
    'builtinBrush.builtin-soft-brush': 'ソフト円ブラシ',
    'builtinBrush.builtin-grit-spray': '粗いスプレー',
    'builtinBrush.builtin-blender': '色混ぜ',
    'builtinBrush.builtin-water-blend': '水ぼかし',
    'builtinBrush.builtin-blending-stump': '擦筆',
    'builtinBrush.builtin-blur': 'ぼかし',
    'builtinBrush.builtin-splatter-preset': 'スパッタリング',
    'builtinBrush.builtin-stipple': '点描',
    'builtinBrush.builtin-sponge': 'スポンジ',
    'builtinBrush.builtin-cloud': '雲',
    'builtinBrush.builtin-concrete': 'コンクリート',
    'builtinBrush.builtin-grass': '草',
    'builtinBrush.builtin-sparkle': 'キラキラ',
    'builtinBrush.builtin-snow': '雪',
    'builtinBrush.builtin-bubble': '泡',
    'builtinBrush.builtin-leaves': '葉っぱ',
    'builtinTip.builtin-chalk': 'チョーク',
    'builtinTip.builtin-splatter': 'スパッタリング',
    'builtinTip.builtin-grain': '粒子',
    'builtinTip.builtin-bristle': '筆の毛',
    'builtinTip.builtin-sponge': 'スポンジ',
    'builtinTip.builtin-wet-blot': 'にじみ',
    'builtinTip.builtin-star': '星',
    'builtinTip.builtin-flake': '雪の結晶',
    'builtinTip.builtin-ring': 'リング',
    'builtinTip.builtin-leaf': '葉',
    'builtinTip.builtin-grass-clump': '草むら',
    'builtinTip.builtin-paper-grain': '紙目',
    'builtinTip.builtin-canvas-weave': 'キャンバス目',
    'builtinTip.builtin-cold-press': 'コールドプレス紙',
    'builtinTip.builtin-pencil-side': '鉛筆の芯の腹',
    'builtinTip.builtin-graphite-tooth': '鉛筆の紙目',
    'builtinTip.builtin-color-clumps': '色鉛筆のかすれ',
    'builtinTip.builtin-pencil-face-0-0': '鉛筆の芯 1-1',
    'builtinTip.builtin-pencil-face-0-1': '鉛筆の芯 1-2',
    'builtinTip.builtin-pencil-face-0-2': '鉛筆の芯 1-3',
    'builtinTip.builtin-pencil-face-1-0': '鉛筆の芯 2-1',
    'builtinTip.builtin-pencil-face-1-1': '鉛筆の芯 2-2',
    'builtinTip.builtin-pencil-face-1-2': '鉛筆の芯 2-3',
    'builtinTip.builtin-pencil-face-2-0': '鉛筆の芯 3-1',
    'builtinTip.builtin-pencil-face-2-1': '鉛筆の芯 3-2',
    'builtinTip.builtin-pencil-face-2-2': '鉛筆の芯 3-3',
    'builtinTip.builtin-pencil-face-3-0': '鉛筆の芯 4-1',
    'builtinTip.builtin-pencil-face-3-1': '鉛筆の芯 4-2',
    'builtinTip.builtin-pencil-face-3-2': '鉛筆の芯 4-3',
    'builtinTip.builtin-pencil-face-4-0': '鉛筆の芯 5-1',
    'builtinTip.builtin-pencil-face-4-1': '鉛筆の芯 5-2',
    'builtinTip.builtin-pencil-face-4-2': '鉛筆の芯 5-3',
    'builtinTip.builtin-pencil-face-5-0': '鉛筆の芯 6-1',
    'builtinTip.builtin-pencil-face-5-1': '鉛筆の芯 6-2',
    'builtinTip.builtin-pencil-face-5-2': '鉛筆の芯 6-3',
    'builtinTip.builtin-pencil-crumb-0': '鉛筆の粒 1',
    'builtinTip.builtin-pencil-crumb-1': '鉛筆の粒 2',
    'builtinTip.builtin-pencil-crumb-2': '鉛筆の粒 3',
    'brRenameGroup': 'グループ名を変更',
    'brDeleteGroup': 'グループを削除',
    'brDeleteEmptyGroupTemplate': '空のグループ「{name}」を削除しますか？',
    'brDeleteGroupTemplateOne': 'グループ「{name}」と中のブラシ1個を削除しますか？',
    'brDeleteGroupTemplate': 'グループ「{name}」と中のブラシ{n}個を削除しますか？',
    'brRenameSelected': '選択中のブラシ名を変更',
    'brDeleteSelected': '選択中のブラシを削除',
    'brSaveAsPreset': '現在の設定をプリセットとして保存',
    'brImportBrushes': 'ブラシを読み込み（.abr、.sut、.sutg）',
    'brResetLibrary': 'ブラシライブラリをリセット',
    'brExportSelected': 'ブラシを書き出し',
    'brExportGroup': 'ブラシグループを書き出し',
    'brExportNothing': '書き出すブラシがありません。',
    'fileExportPlaceUnchosenTemplate': '保存先を選べませんでした: {error}',
    'settingsExportedTemplate': '「{name}」を書き出しました。',
    'settingsExportNotWrittenTemplate': 'ファイルを書き込めませんでした: {error}',
    'settingsExportAll': '設定をすべて書き出す',
    'settingsAllFileName': 'Anicel 設定',
    'settingsRowFrameCount': 'コマ数の入力方式',
    'settingsRowWorkspaceLayout': 'ワークスペース配置',
    'imIntoSettings': '設定',
    'imSettingsGoInPlace': '「設定」に入れる項目は、今の設定が消えます。',
    'imSettingsUnreadable': '読めません',
    'brExportNotWrittenTemplate': 'ブラシファイルを書き込めませんでした: {error}',
    'brExportedOneTemplate': '「{name}」を書き出しました。',
    'brExportedManyTemplate': 'ブラシを{count}個書き出しました。',
    'brExportFallbackName': 'ブラシ',
    'brImportUnreadable': 'このファイルはブラシファイルとして読み込めませんでした。',
    'brImportPickFailedTemplate': 'ファイルを開けませんでした: {error}',
    'fontBroughtTemplate': 'フォント「{family}」をこの端末に読み込みました。',
    'brImportedOneTemplate': '「{file}」からブラシを1個読み込みました。',
    'brImportedManyTemplate': '「{file}」からブラシを{count}個読み込みました。',
    'brImportWarningsTemplate': '{summary}（警告のある項目 {count}件）',
    'brTipUnreadable': 'その画像はブラシ先端として読み込めませんでした。',
    'brTipNoShape': 'その画像には先端に使える見える形がありません。',
    'brTipNotSaved': 'その先端を保存できませんでした。',
    'brExpand': '展開',
    'trFlipHorizontal': '左右反転',
    'trFlipVertical': '上下反転',
    'trPosition': '位置',
    'trScale': '拡大率',
    'trScaleLink': '拡大率を連動',
    'trRotation': '回転',
    'trAnchorPoint': '基準点',
    'trMeshColumns': '横のマス',
    'trMeshRows': '縦のマス',
    'trMesh': 'メッシュ',
    'trFinish': '仕上げ',
    'commonReset': 'リセット',
    'viewFitToView': '画面に合わせる',
    'viewResetView': 'ズームをリセット（100%）',
    'panelSettings': '設定',
    'viewRotateLeft': '表示を左に回転',
    'viewRotateRight': '表示を右に回転',
    'viewFlipHorizontal': '表示を左右反転',
    'viewFlipVertical': '表示を上下反転',
    'viewStraighten': '傾きをリセット（0°）',
    'viewZoomDrag': 'ズーム（ドラッグ）',
    'viewAngleDrag': '表示角度（ドラッグ）',
    'valueTypeIn': '数値を入力',
    'viewCanvasColor': 'カンバスの色',
    'viewPasteboardColor': 'ペーストボードの色',
    'pasteboardTitle': 'ペーストボード',
    'pasteboardInUse': '使用',
    'pasteboardNotInUse': '使用しない',
    'viewBackdropColor': '背景の色',
    'colorUseCurrent': '現在の色を適用',
    'colorNone': 'なし',
    'colorPresent': 'あり',
    'tlSections': 'セクション',
    'tlAllDisplayedLayers': '表示中の全レイヤー',
    'tlShowAll': 'すべて表示',
    'tlHideAll': 'すべて隠す',
    'tlSoloKind': '種類をソロ',
    'tlSoloColor': '色をソロ',
    'tlSoloClips': 'クリッピングをソロ',
    'tlSoloFxOnRows': 'FXオンの行をソロ',
    'tlSoloSheetOnRows': 'シートオンの行をソロ',
    'tlApplyAllFx': 'FXをすべて適用',
    'tlBypassAllFx': 'FXをすべてバイパス',
    'tlAllOnTimesheet': 'すべてシートに載せる',
    'tlAllOffTimesheet': 'すべてシートから外す',
    'tlClearMarkFilter': 'マークフィルターを解除',
    'tlClearAllClips': 'クリッピングをすべて解除',
    'tlColVisibility': '表示列',
    'tlColLayerKind': 'レイヤー種類列',
    'tlColOnionSkin': 'オニオンスキン列',
    'tlColOpacity': '不透明度列',
    'tlColBlendMode': '合成モード列',
    'tlColFx': 'FX列',
    'tlColMark': 'マーク列',
    'tlColClip': 'クリッピング列',
    'tlColTimesheet': 'タイムシート列',
    'tlShowXSheet': 'Xシートで表示',
    'tlShowTimeline': 'タイムラインで表示',
    'cameraViewOn': 'カメラビュー（オン）',
    'cameraViewOff': 'カメラビュー',
    'tlOpenOnionPanel': 'オニオンスキンパネルを開く',
    'tlApplyOnionToDisplayed': '表示中のレイヤーにオニオンスキンを適用',
    'tlClearOnionOnDisplayed': '表示中のレイヤーのオニオンスキンを解除',
    'tlOnionOnDisplayedToggle': '表示中のレイヤーのオニオンスキン(オン/オフ)',
    'tlCollapseAllLayers': 'すべてのレイヤーを折りたたむ',
    'tlExpandAllLayers': 'すべてのレイヤーを展開',
    'railLayerBlendMode': 'レイヤーの合成モード',
    'railFolderBlendMode': 'フォルダーの合成モード',
    'railHideLayer': 'レイヤーを隠す',
    'railShowLayer': 'レイヤーを表示',
    'railBypassLayerFx': 'レイヤーFXをバイパス',
    'railApplyLayerFx': 'レイヤーFXを適用',
    'railBypassMixedLayerFx': 'レイヤーFXをすべてバイパス（一部オフ）',
    'railBypassTrackFx': 'トラックFXをバイパス',
    'railApplyTrackFx': 'トラックFXを適用',
    'railRemoveFromTimesheet': 'シートから外す',
    'railAddToTimesheet': 'シートに載せる',
    'railCollapseLanes': 'レーンを畳む',
    'railExpandLanes': 'レーンを展開',
    'railOnionSkinOn': 'オニオンスキン（オン）',
    'railOnionSkin': 'オニオンスキン',
    'railLaneGraphOn': 'グラフ（オン）',
    'railLaneGraph': 'グラフ',
    'railLanePinOn': 'すべてのグラフに表示中',
    'railLanePin': 'すべてのグラフに表示',
    'laneGraphValue': '値',
    'laneGraphSpeed': '速度',
    'laneGraphEnlarge': '拡大表示',
    'laneGraphEnlargeOn': '拡大表示（オン）',
    'laneGraphPen': 'ペン',
    'laneGraphPenOn': 'ペン（オン）',
    'laneGraphTransformBox': '変形ボックス',
    'laneGraphTransformBoxOn': '変形ボックス（オン）',
    'railClipOn': '下のレイヤーでクリッピング（オン）',
    'railClip': '下のレイヤーでクリッピング',
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
    'tlNoLayers': 'レイヤーがありません',
    'tlLegendLayer': 'レイヤー',
    'tlAllDisplayedOpacity': '表示中レイヤー全体の不透明度',
    'tlLinkedWith': 'リンク先',
    'tlLayerReference': '参照',
    'tlReferenceSourceShort': '素材より{n}フレーム長い',
    'tlSelectedLayers': '選択したレイヤー',
    'tlAudioGroup': '音声',
    'tlSoundVolume': '音量',
    'tlNameTagGroup': 'ネームタグ',
    'tlReferenceGroup': '参照',
    'tlTransformGroup': 'トランスフォーム',
    'tlLaneScale': 'スケール',
    'tlLaneRotation': '回転',
    'tlLanePosition': '位置',
    'tlLaneOpacity': '不透明度',
    'tlLaneAnchorPoint': 'アンカーポイント',
    'tlBypassLaneTemplate': '{name}をバイパス',
    'tlApplyLaneTemplate': '{name}を適用',
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
    // 🗣️The row KIND's name is the user's (2026-10-02: 「애니메이션 레이어로
    // 이름바꾸자. 일본어도 アニメーション」). ⛔Not 動画 — that word is the
    // in-between PROCESS (`layerProcess.inbetween`), another axis.
    'tlKindAnimation': 'アニメーション',
    'tlKindStoryboard': '絵コンテ',
    'tlKindImage': '画像',
    'tlKindAdjustment': '調整レイヤー',
    'tlKindFolder': 'フォルダー',
    'tlKindSe': 'SE',
    'tlKindTransition': 'トランジション',
    'tlKindCamera': 'カメラ',
    'tlKindSemanticTemplate': '{kind}レイヤー',
    'seNameTagShowLineLabel': 'セリフを表示',
    'seNameTagLineInkLabel': 'セリフの色',
    'seNameTagTrackingLabel': '字間',
    'seNameTagSizeLabel': 'サイズ',
    'seNameTagNameInkLabel': '名前の色',
    'seNameTagBoxColorLabel': 'ボックスの色',
    'seNameTagBoldLabel': '太字',
    'seNameTagItalicLabel': '斜体',
    'seNameTagUnderlineLabel': '下線',
    'seNameTagStrikethroughLabel': '取り消し線',
    'seNameTagPreviewName': '名前',
    'seNameTagPreviewLine': 'セリフ',
    'tlKindInstruction': 'ディレクション',
    'tlNoriShiro': 'のりしろ',
    'shortcutAction.layer-attach-free-above': '上にフリーのアタッチレイヤー',
    'shortcutAction.layer-attach-free-below': '下にフリーのアタッチレイヤー',
    'shortcutAction.layer-attach-synced-above': '上にシンクのアタッチレイヤー',
    'shortcutAction.layer-attach-synced-below': '下にシンクのアタッチレイヤー',
    'tlLayerCommands': 'レイヤー操作',
    'tlFrameCommands': 'フレーム操作',
    'tlCut': 'カット',
    'tlLayer': 'レイヤー',
    'tlFrame': 'フレーム',
    'tlKey': 'キー',
    'shortcutAction.frame-select-row-span': '行全体を選択',
    'linkWindowUnlink': 'リンクを解除',
    'linkWindowUnlinkLinkedCut': '兼用カットのレイヤーはカットごと解除します',
    'tlResetGroup': 'リセット（キーは残す）',
    'tlEffects': 'エフェクト',
    'tlAddEffectTemplate': '{name}を追加',
    'tlDropIntoFolderTemplate': '{name} の中へ',
    'tlDropOutOfFolder': 'フォルダの外へ',
    'tlDropAttachSyncedTemplate': '{name} にアタッチ（シンク）',
    'tlDropAttachFreeTemplate': '{name} にアタッチ（フリー）',
    'tlDropDetachAttach': 'アタッチを解除',
    'shortcutAction.layer-detach': 'アタッチを解除',
    'tlAttachDropsFxRows': 'fx を失うレイヤー',
    'tlAttachDropsFxTitle': 'アタッチすると fx が失われます',
    'tlMergeChangesTitle': '結合すると見た目が変わることがあります',
    'tlMergeChangesBody': '結合したレイヤーは、下のレイヤーの上で違って見えることがあります。',
    'tlMergeChanges': '変わるもの',
    'tlMergeChangeBlend': '通常以外の合成モードが含まれています — 結合したレイヤーは通常になります',
    'tlMergeChangeClip': '選んだレイヤーと選んでいないレイヤーがクリッピングでつながっています',
    'tlMergeChangeFolder': '結合したレイヤーが入るフォルダーの効果が、フォルダーの外から来たレイヤーにもかかります',
    'tlMergeChangeRiderOver': 'アタッチレイヤーがほかの絵を覆うようになります',
    'tlMergeChangeRiderUnder': 'アタッチレイヤーがほかの絵の下に入ります',
    'tlMergeChangeWall': 'ペーストボードの外の部分が切り取られます',
    'tlAttachDropsFxBody': 'アタッチレイヤーは自分の fx を持ちません。続けると既存の fx は失われます。実行しますか？',
    'tlPush': '押し出し（コマを開ける）',
    'tlPull': '詰め（コマを詰める）',
    'sbOneStoryboardRowPerCut': 'このカットには既に絵コンテレイヤーがあります。カットにつき1つだけです。',
    'cnHeadCut': 'カット',
    'cnHeadPicture': '画面',
    'cnHeadAction': '内容',
    'cnHeadDialogue': 'セリフ',
    'cnHeadSeconds': '秒',
    'cnCoverCuts': 'cut',
    'cnCoverArtist': 'コンテ',
    'sheetPrintEpisode': '話数',
    'sheetPrintTitle': 'タイトル',
    'sheetPrintScene': 'シーン',
    'sheetPrintCut': 'カット',
    'sheetPrintDuration': 'タイム',
    'sheetPrintName': '原画',
    'sheetPrintPage': 'シート',
    'sheetPrintRepeat': 'リピート',
    'sheetPrintHold': '止め',
    'tlSetCommasN': 'Nコマに設定',
    'tlSetCommaTemplate': '{n}コマに設定',
    'tlProjectAudioRate': 'プロジェクトの音声サンプルレート',
    'tlShowSeRows': 'SE行を表示',
    'tlShowCameraRows': 'カメラ行を表示',
    'shortcutAction.layer-storyboard': '絵コンテレイヤー',
    'setLengthAction': '露光の長さの設定',
    'markEveryField': '間隔',
    'frameCountEntryFrames': 'コマ数',
    'frameCountEntrySecondsPlusFrames': '秒+コマ',
    'projectFpsTitle': 'プロジェクトのフレームレート',
    'projectFpsField': '1秒あたりのフレーム数',
    'autoNameStartField': '開始番号',
  };

  static const _koValues = <String, String>{
    'launchStageEngine': '엔진 시작',
    'launchStagePlugins': '플러그인 등록',
    'launchStageApp': '앱 준비',
    'launchStageFirstFrame': '첫 화면 그리기',
    'launchNoticeTitle': '안내',
    'launchNoticeDontShowAgain': '다음부터 표시 안 함',
    'usageStatsSend': '사용 통계 보내기',
    'usageStatsHelp':
        '켜 두면 앱을 열 때 · 쓰는 동안 55분마다 · 앱을 떠날 때, 쓰고 있다는 것을 '
        'OS와 그 버전 · 기기 모델명 · 앱 빌드 · 앱 언어와 함께 '
        '익명으로 보냅니다. 하루 한 번은 기기 언어와 최근 28일 중 쓴 날의 구간'
        '(처음 / 1–2일 / 3일 이상), 설정 네 가지'
        '(UI 크기 · 강조 색상 · 자동 저장 · 커서)도 보냅니다. '
        '그림 · 프로젝트 · 파일 이름 · 이름 · 기기에 붙인 이름 등 '
        '사용자를 알아볼 수 있는 것은 보내지 않습니다. '
        '끄면 이 기기에 남긴 기록도 지웁니다.',
    'usageStatsTitle': '사용 통계',
    'usageStatsAsk': '사용 통계를 보내시겠습니까? 켜 주시면 Anicel 개발에 도움이 됩니다.',
    'usageStatsChangeLater': '환경설정 ▸ 시스템에서 언제든 바꿀 수 있습니다.',
    'usageStatsDontSend': '보내지 않기',
    'usageStatsDoSend': '보내기',
    'firstRunTitle': '처음 설정',
    'firstRunChangeLater': '환경설정에서 언제든 바꿀 수 있습니다.',
    'firstRunStart': '시작',
    'programLanguageLabel': '프로그램 언어',
    'notationLanguageLabel': '표기용 언어',
    'programLanguageHelp': '메뉴·패널·라벨의 언어.',
    'notationLanguageHelp': '타임시트 등 제출물에 인쇄되는 언어.',
    'noCutSelected': '선택된 컷 없음',
    'noticeNoFrameHere': '프레임이 존재하지 않습니다',
    'noticeNothingToCut': '잘라낼 대상이 존재하지 않습니다',
    'noticeNoConteLayer': '콘티 레이어가 존재하지 않습니다',
    'noticeLayerNotDrawable': '드로잉이 허용되지 않은 레이어입니다',
    'noticeLayerHidden': '숨김 상태인 레이어입니다',
    'noticeEditAttachOwner': '주인 레이어를 편집하세요',
    'commonCancel': '취소',
    'commonApply': '적용',
    'commonRefresh': '새로고침',
    'commonClose': '닫기',
    'commonAffectedFiles': '해당 파일들',
    'commonNotice': '알림',
    'tlSharedColourEdit': '색 편집',
    'exportNoCuts': '이 프로젝트에는 출력할 컷이 없습니다.',
    'exportQueueEmpty': '큐에 작업이 없습니다',
    'exportPresetsEmpty': '프리셋이 없습니다',
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
    'recordMicPermissionDenied': '마이크 접근이 꺼져 있습니다 — 설정에서 Anicel의 마이크를 허용하세요.',
    'recordMicNotAllowed': '마이크가 허용되어 있지 않습니다 — 환경설정▸오디오▸「마이크 허용」을 켜세요.',
    'recordTakeClipped': '테이크에 클리핑이 감지되었습니다 — 블록의 빨간 모서리가 표시입니다.',
    'recordClipMarkerTooltip': '이 테이크는 클리핑되었습니다(입력 과대)',
    'tlTransitionCrossingWarning': '컷 경계를 넘어 적용되지 않습니다',
    'tlTransitionCutOl': '컷 O.L',
    'audioMicGainLabel': '마이크 게인(dB)',
    'audioInputChannelLabel': '입력 채널',
    'audioInputChannelDevice': '장치 그대로',
    'audioInputChannelMonoMix': '모노 믹스',
    'audioInputChannelLeft': '왼쪽만',
    'audioInputChannelRight': '오른쪽만',
    'audioClippingNoticeLabel': '클리핑 주의 안내(토스트+블록 마커)',
    'audioDenoiseLabel': '잡음 제거(음성 전용 — 효과음 녹음 시 끄기)',
    'audioInputMeterLabel': '입력 레벨',
    'audioMicrophoneAllowedLabel': '마이크 허용',
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
    'audioMute': '음소거',
    'audioSolo': '솔로',
    'fpsAudioTitleTemplate': '{from} → {to}: 소리는 어떻게 할까요?',
    'fpsAudioBody':
        '두 레이트는 실제 속도가 0.1% 다르고, 소리는 실시간으로 존재합니다 — 프레임 정확과 시간 정확을 동시에 지킬 수 없습니다.\n\n• 오디오 타이밍 유지: 소리는 실시간을 지키고, 프레임 위치가 0.1% 어긋납니다(약 42초마다 1프레임).\n\n• 오디오 0.1% 당김: 정확한 풀다운 비율로 리샘플합니다(들리지 않는 피치 변화 — 텔레시네 표준 컨폼). 모든 소리가 프레임 범위를 유지합니다.',
    'fpsAudioKeep': '오디오 타이밍 유지',
    'fpsAudioPull': '오디오 0.1% 당김',
    'feedbackTextOnly': '글만 보내기',
    'feedbackWithFiles': '사진·동영상 포함 (Google 로그인)',
    'selectionClosePolygon': '도형 닫기',
    'selectionInvert': '캔버스 밖도 선택 반전',
    'selectionInvertInCanvas': '캔버스 안 선택 반전',
    'toolSelectionMode': '모드',
    'commonSave': '저장',
    'commonDelete': '삭제',
    'commonAdd': '추가',
    'commonRename': '이름 변경',
    'commonLink': '링크',
    'commonPreview': '미리보기',
    'windowTitleTemplate': '{action} ({target})',
    'editNameAction': '이름 편집',
    'editNoteAction': '메모 편집',
    'renameLayerEmpty': '레이어 이름은 비울 수 없습니다.',
    'renameCutField': '컷 이름',
    'renameCutEmpty': '컷 이름은 비울 수 없습니다.',
    'renameGuideTitle': '가이드 이름 변경',
    'renameGuideField': '가이드 이름',
    'renameGuideEmpty': '가이드 이름은 비울 수 없습니다.',
    'deleteLayerTitle': '레이어 삭제',
    'deleteLayersMessage': '아래 레이어를 삭제할까요?',
    'deleteLayersHeading': '삭제할 레이어',
    'deleteEffectsHeading': '삭제할 이펙트',
    'frameNameConflictTitle': '같은 프레임 이름이 이미 있습니다',
    'frameNameConflictBody':
        '목록의 프레임에 붙을 이름을 같은 레이어의 다른 프레임이 이미 쓰고 '
        '있습니다. 그 이름의 프레임에 링크할까요? 링크하면 같은 이름이 같은 '
        '원화를 공유하고, 목록의 프레임 그림은 버려집니다.',
    'linkedPasteConflictBody':
        '붙여넣는 프레임의 이름을 목록의 프레임이 이미 쓰고 있습니다. '
        '붙여넣는 블록을 그 프레임에 링크할까요? 링크하면 같은 이름이 '
        '같은 원화를 공유해서, 붙여넣은 블록은 목록의 프레임을 보여 '
        '주고 복사해 온 그림은 들어오지 않습니다.',
    'frameNameConflictListHeading': '링크할 프레임',
    'seInstanceNewTitle': '새 SE',
    'seInstanceEditTitle': 'SE 편집',
    'seNameLabel': '이름 (화자 — 비우면 박스 숨김)',
    'seTypeLabel': '타입',
    'seDialogueLabel': '대사',
    'seDialogueOffsetLabel': '대사 오프셋',
    'seKomaPerGlyphLabel': '글자별 코마',
    'seLinkedAudioLabel': '링크된 오디오',
    'seLinkedAudioNone': '없음',
    'seUnlinkAudio': '링크 해제',
    'keySideIncoming': '도착',
    'keySideOutgoing': '출발',
    'keySideKind.linear': '리니어',
    'keySideKind.ease': '천천히',
    'keySideKind.fast': '급하게',
    'keySideKind.auto': '부드럽게',
    'keySideKind.hold': '홀드',
    'keyEaseInfluence': '세기',
    'keyPath': '경로',
    'keyPathKind.linear': '선형',
    'keyPathKind.bezier': '베지어',
    'keyPathKind.continuousBezier': '연속 베지어',
    'keyPathKind.autoBezier': '자동 베지어',
    'keyRoving': '로빙',
    'keySideIncomingHelp':
        '앞 키에서 이 키로 들어오는 빠르기. 리니어: 고르게 · 천천히: 느려지며 도착 · 급하게: 빨라지며 도착 · 부드럽게: 앞뒤 키에 맞춰 빠르기를 이어 지나감. 세기: 그 변화가 구간의 얼마만큼에 걸치는지.',
    'keySideOutgoingHelp':
        '이 키에서 다음 키로 나가는 빠르기. 리니어: 고르게 · 천천히: 천천히 출발 · 급하게: 빠르게 튀어 나감 · 부드럽게: 앞뒤 키에 맞춰 빠르기를 이어 지나감 · 홀드: 다음 키까지 값을 그대로. 세기: 그 변화가 구간의 얼마만큼에 걸치는지.',
    'keyPathHelp':
        '위치가 이 키를 지나는 길의 모양. 선형: 키에서 꺾임 · 베지어: 앞뒤 손잡이가 각자의 방향 · 연속 베지어: 두 손잡이가 한 줄로 이어짐 · 자동 베지어: 앞뒤 키에 맞춰 매끄럽게 휘어 지나감.',
    'keyRovingHelp':
        '경로 위의 자리는 그대로 두고 키가 시간을 내놓는다. 시간을 가진 앞뒤 키 사이에서 빠르기가 고르게 되는 프레임으로 저절로 옮겨진다(After Effects 의 Rove Across Time). 처음 · 마지막 키는 로빙하지 않는다.',
    'cameraPath': '카메라 경로',
    'cameraPathOff': '끄기',
    'cameraPathSpace': '공간',
    'cameraPathSpaceTime': '공간+시간',
    'cameraPathAllKeys': '키 전체',
    'cameraPathAroundPlayhead': '재생헤드 주변',
    'cameraPathTickEvery': '점 간격',
    'cameraPathAround': '앞뒤',
    'convertLinkedCutTitle': '겸용컷으로 변환',
    'convertLinkedCutBodyTemplate':
        '"{cut}"(원본)을 다른 컷과 링크합니다. 이름이 같은 레이어끼리 '
        '한 장의 공유 그림이 됩니다.',
    'convertLinkedCutTargetLabel': '링크할 컷',
    'convertLinkedCutLinksHeading': '링크할 레이어',
    'convertLinkedCutReplacedTemplate':
        '"{cut}"의 같은 이름 원화가 원본 것으로 대체됩니다(원본 승리).',
    'convertLinkedCutReplacedHeading': '대체되는 원화',
    'convertLinkedCutJoiningTemplate': '원화 {count}장이 공유 세트에 합류합니다.',
    'convertLinkedCutTargetGainsHeadingTemplate': '"{cut}"에 추가되는 레이어',
    'convertLinkedCutOriginGainsHeading': '이 컷에 추가되는 레이어',
    'convertLinkedCutNothing':
        '링크할 것이 없습니다 — 이미 완전히 링크됐거나 공유할 그리기 '
        '레이어가 없습니다.',
    'convertLinkedCutUndoNote': '실행 취소하면 변환이 건드린 컷이 모두 복원됩니다.',
    'convertLinkedCutResizeFirst':
        '두 컷의 캔버스 크기가 다릅니다. 겸용컷은 캔버스를 함께 쓰므로 '
        '이 컷이 원본 컷의 크기로 바뀝니다. 실행 취소하면 되돌아갑니다.',
    'guideKindSymmetry': '대칭',
    'guideKindPerspective': '퍼스',
    'guideDelete': '가이드 삭제',
    'guideShow': '캔버스에 표시',
    'guideActsOn': '획에 작용 중',
    'guideActsOff': '작용 안 함',
    'guideLibraryEmpty': '이 컷에는 아직 가이드가 없습니다',
    'noGuideSelected': '선택된 가이드 없음',
    'guideLineCount': '선 수',
    'guideMirrorModeOn': '사본이 좌우로 뒤집힙니다(진짜 거울).',
    'guideMirrorMode': '선대칭',
    'guideMirrorModeOff': '사본은 회전일 뿐 — 뒤집히지 않습니다.',
    'guideEyeLevelShow': '아이레벨 표시',
    'guideConstrainToEyeLevel': '소실점을 아이레벨에 고정',
    'guideConstrainToEyeLevelNote': '다음 드래그부터 적용됩니다. 이미 놓인 것은 움직이지 않습니다.',
    'guideVanishingPoint': '소실점',
    'guideVanishingPointAtInfinity': '평행(무한대)',
    'guideAddVanishingPoint': '새 소실점',
    'guideDeleteVanishingPoint': '소실점 삭제',
    'guideParallel': '평행',
    'guideParallelAngle': '각도',
    'guideLineDensity': '선 밀도',
    'guideRasterize': '래스터라이즈',
    'closeProjectTitle': '프로젝트를 닫을까요?',
    'shortcutAction.file-new': '새 프로젝트',
    'untitledProjectTab': '제목 없음 {n}',
    'fileOpenInAnotherTab': '그 파일은 다른 탭에서 열려 있습니다.',
    'openNewerFormat': '더 새 버전의 Anicel 로 저장된 프로젝트라서 열 수 없습니다.',
    'openOlderFormatTemplate':
        '형식 {saved}의 프로젝트라서 열 수 없습니다(이 Anicel 은 형식 {oldest}부터 엽니다).',
    'closeProjectBody': '변경 사항이 저장되지 않았습니다. 그래도 닫을까요?',
    'closeProjectVanishedBody':
        '이 프로젝트의 파일이 사라졌습니다. 지금 닫으면 그 안에만 있던 그림도 함께 '
        '사라집니다. 「다른 이름으로 저장」하면 지금 열려 있는 것을 새 파일로 '
        '옮길 수 있습니다.',
    'commonSaveAs': '다른 이름으로 저장',
    'saveAsTitle': '다른 이름으로 저장',
    'saveProgressRunning': '저장 중…',
    'saveProgressDone': '저장 완료',
    'savePrepareRunning': '준비 중…',
    'savePrepareDone': '준비 완료',
    'saveStepKeepingLeftBehind': '빠진 미디어를 옮겨 두는 중…',
    'saveStepCels': '셀을 쓰는 중…',
    'saveStepChecking': '품을 파일을 확인하는 중…',
    'saveStepMedia': '미디어를 쓰는 중…',
    'saveStepConforms': '재생용으로 변환한 소리를 쓰는 중…',
    'saveStepFonts': '글꼴을 쓰는 중…',
    'saveStepCompacting': '파일의 빈 자리를 메우는 중…',
    'saveStepHandingBack': '원래 문서로 파일을 넘기는 중…',
    'openProgressRunning': '여는 중…',
    'openProgressDone': '열기 완료',
    'openWaitingCloudTemplate': '클라우드에서 내려받는 중 · {sec}초',
    'openWaitingStalledTemplate': '{sec}초째 도착하지 않았습니다',
    'resizeProgressRunning': '크기 변경 중…',
    'resizeProgressDone': '크기 변경 완료',
    'bakeProgressRunning': '래스터라이즈 중…',
    'bakeProgressDone': '래스터라이즈 완료',
    'rasterizeLeftReferences': '참조로 남긴 레이어가 있습니다.',
    'referenceWait.attached':
        '어태치된 레이어는 베이스의 변형으로 놓여, 움직이는 참조를 자기 키로 '
        '옮길 수 없습니다. 어태치를 해제하면 래스터라이즈됩니다.',
    'referenceWait.laidAsFitted':
        '이전 버전에서 맞춘 크기로 깔린 파일이라, 움직이는 참조를 키로 옮길 수 '
        '없습니다. 파일을 다시 놓으면 래스터라이즈됩니다.',
    'referenceWait.sheared':
        '한 축만 늘인 배율 아래에서 90° 단위가 아닌 회전은 변형이 그릴 수 '
        '없습니다. 배율을 고르게 하거나 90° 단위로 돌리면 래스터라이즈됩니다.',
    'referenceWait.othersKeepKeys':
        '변형 스위치를 같이 쓰는 다른 레이어가 꺼 둔 동안의 키를 갖고 있어, '
        '스위치를 켜면 그 키가 보이게 됩니다. 변형을 먼저 켜면 '
        '래스터라이즈됩니다.',
    'referenceWait.usesApart':
        '링크된 레이어들이 같은 셀의 그림을 서로 다른 자리에 보여, 셀 한 장에 '
        '담을 수 없습니다. 참조를 같은 자리로 맞추면 래스터라이즈됩니다.',
    'pasteProgressRunning': '붙여넣는 중…',
    'pasteProgressDone': '붙여넣음',
    'unsavedAutosaveTitle': '프로젝트 저장',
    'unsavedAutosaveBody':
        '이 프로젝트는 한 번도 저장된 적이 없어서 자동 저장이 쓸 곳이 '
        '없습니다. 파일을 지정하면 그때부터 자동 저장이 지켜줍니다.',
    'commonNotNow': '나중에',
    'topStripProject': '프로젝트',
    'topStripSettings': '설정',
    'menuPlay': '재생',
    'menuPause': '일시정지',
    'shortcutAction.file-open': '파일 열기',
    'shortcutAction.file-open-folder': '폴더 열기',
    'shortcutAction.file-export': '내보내기',
    'menuAction.edit-undo': '실행 취소',
    'menuAction.edit-redo': '다시 실행',
    'menuAction.edit-copy-frame': '프레임 복사',
    'menuAction.edit-paste-linked-frame': '링크 프레임 붙여넣기',
    'menuAction.edit-new-drawing': '이 프레임에 새 원화',
    'menuAction.edit-delete-cell': '셀 삭제',
    'menuAction.edit-cut-exposure': '노출 잘라내기',
    'menuAction.edit-toggle-mark': '마크 켜기/끄기',
    'shortcutAction.edit-keyboard-shortcuts': '키보드 단축키',
    'shortcutAction.edit-preferences': '환경설정',
    'shortcutAction.work-settings': '작품 설정',
    'menuAction.file-save-as': '프로젝트(.anicel)',
    'menuAction.project-settings': '프로젝트 설정',
    'shortcutAction.cut-create-linked': '겸용컷 만들기',
    'shortcutAction.cut-convert-linked': '겸용컷으로 변환',
    'shortcutAction.cut-canvas-size': '캔버스 크기',
    'menuAction.cut-delete': '컷 삭제',
    'menuAction.layer-add': '새 레이어',
    'menuAction.layer-link-duplicate': '링크해서 복제',
    'menuAction.layer-unlink': '링크 해제',
    'menuAction.layer-group-into-folder': '폴더로 묶기',
    'menuAction.layer-rename': '레이어 이름 변경',
    'shortcutAction.layer-rasterize': '래스터라이즈',
    'menuAction.layer-se-name-tag': 'SE 이름표',
    'menuAction.layer-copy': '레이어 복사',
    'menuAction.layer-paste': '레이어 붙여넣기',
    'menuAction.layer-delete': '레이어 삭제',
    'menuAction.playback-stop': '정지',
    'menuAction.playback-play-all': '모든 컷 재생',
    'menuAction.window-panels': '패널',
    'shortcutAction.window-tool-rail-right': '툴 바를 오른쪽에',
    'shortcutAction.window-region-on-top': '타임라인 영역을 위로',
    'shortcutAction.window-brush-values-on-strip': '브러시 값을 상단띠로',
    'shortcutAction.window-full-screen': '전체 창 모드',
    'shortcutAction.window-region-fold': '타임라인 영역 접기 / 펼치기',
    'shortcutAction.window-reset-layout': '작업공간 배치 초기화',
    'menuAction.edit-debug': '디버그',
    'shortcutAction.edit-input-inspector': '입력 인스펙터',
    'shortcutAction.edit-frame-timing-overlay': '프레임 타이밍 오버레이',
    'shortcutAction.edit-frame-stats': '프레임 통계',
    'shortcutAction.edit-show-repaints': '다시 그리기 표시',
    'menuAction.edit-knee-at-one': '화면 해상도 버퍼',
    'menuAction.edit-show-unpainted-tiles': '그려지지 않은 타일 표시',
    'shortcutAction.help-about': 'Anicel 정보',
    'shortcutAction.help-send-feedback': '의견 보내기',
    'fileOpenTitle': '프로젝트 열기',
    'fileStorageOffNotice':
        '저장소 접근이 꺼져 있습니다 — 앱 폴더 바깥의 프로젝트에는 '
        '모든 파일 권한이 필요합니다.',
    'fileOpenSettings': '설정 열기',
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
    'folderPickDriveNoticeAndroid':
        '구글 드라이브는 폴더를 넘겨주지 못합니다. 이 기기의 폴더를 '
        '사용하세요 — 동기화 앱(Autosync 등)으로 드라이브 폴더를 이 기기에 '
        '둘 수 있습니다.',
    'recentProjectsTitle': '최근 프로젝트',
    'recentReconnect': '다시 연결',
    'sortAscending': '오름차순',
    'canvasSizeTitle': '캔버스 크기',
    'cameraSizeTitle': '카메라 크기',
    'canvasWidthLabel': '너비 (px)',
    'canvasHeightLabel': '높이 (px)',
    'canvasSizePresets': '프리셋',
    'canvasAdjustOnCanvas': '캔버스에서 조정',
    'cameraRatioFree': '자유',
    'cameraRatioCurrent': '지금 비율',
    'commonResize': '크기 변경',
    'inputPressureCurve': '필압 곡선',
    'inputCanvasHeading': '캔버스',
    'inputRightClick': '우클릭 / 펜 사이드 버튼',
    'inputWheelClick': '휠 클릭 / 펜 위쪽 버튼',
    'inputPenTail': '펜 엉덩이(펜을 뒤집기)',
    'inputCanvasTouchHeading': '캔버스 터치',
    'inputIgnoreTouch': '모든 터치 무시',
    'inputDragOneFinger': '한 손가락 드래그',
    'inputDragTwoFingers': '두 손가락 드래그',
    'inputDragThreeFingers': '세 손가락 드래그',
    'inputExtraFinger': '손가락 추가 모디파이어',
    'inputExtraFingerHelp':
        '제스처 도중에 손가락을 더하면 동작이 제한됩니다 — 줌·회전·크기 '
        '스냅, 프레임 미세 이동.',
    'inputStrokeFinger': '손가락 스트로크 모디파이어',
    'inputStrokeFingerHelp':
        '그리는 동안 다른 손가락을 화면에 대고 있으면 획이 가장 가까운 45° '
        '방향으로 잠깁니다(Shift 와 같음).',
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
    'inputRotationSnap': '회전 스냅',
    'inputZoomSnaps': '줌 스냅 (%)',
    'inputZoomCeiling': '최대 줌 잠금 (%)',
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
    'memoryItemLayerImages': '레이어 이미지',
    'memoryItemFramePictures': '프레임 이미지',
    'memoryItemBrushTips': '브러시 팁',
    'memoryItemPanelRasters': '패널 래스터',
    'memoryItemViewerPages': '뷰어 페이지',
    'memoryItemImageCache': '이미지 캐시',
    'memoryItemStoryboardThumbnails': '콘티 썸네일',
    'memoryItemSheetImages': '용지 이미지',
    'memoryItemTextImages': '글자 이미지',
    'memoryItemStrokePreviews': '스트로크 미리보기',
    'memoryItemTimelineTiles': '타임라인 타일 이미지',
    'memoryItemMoviePictures': '참조 동영상',
    'memoryItemTileImages': '캔버스 타일 이미지',
    'memoryItemEnginePool': '그리기 엔진 타일 풀',
    'memoryItemEngineScratch': '그리기 엔진 작업 버퍼',
    'memoryOutsideAllowanceTemplate': '허용치 밖(천장을 걸 수 없는 것): {items}',
    'containerAreaSettings': '설정',
    'containerAreaDiagnostics': '진단 로그',
    'containerAreaSessionScratch': '세션 작업 공간',
    'containerTotal': '합계',
    'saveCelsLostTemplate':
        '저장했지만 그림 {count}장을 담지 못했습니다. 그 그림들이 들어 있던 프로젝트 파일이 열려 있는 동안 삭제되었습니다.',
    'saveCelsLostHeading': '해당 그림들',
    'saveCelsLostGone': '프로젝트에 더는 없는 그림',
    'saveFailedTitle': '저장하지 못했습니다',
    'saveFailedFileInUse':
        '다른 프로그램(동기화·백신 또는 이 파일을 연 앱)이 이 파일을 사용하고 있어서 바꿔 쓸 수 없었습니다.',
    'saveFailedReadOnly': '이 파일이나 폴더가 읽기 전용이라 쓸 수 없었습니다.',
    'saveFailedDiskFull': '저장할 곳의 공간이 부족합니다.',
    'saveFailedLocationGone':
        '저장할 곳에 닿을 수 없습니다 — 드라이브가 빠졌거나, 네트워크가 끊겼거나, 폴더가 지워졌습니다.',
    'saveFailedReplaceRefused': '이 위치(클라우드·파일 앱)가 파일을 바꿔 쓰는 것을 거부했습니다.',
    'saveFailedUnknown': '파일을 쓰는 중에 오류가 났습니다.',
    'saveFailedCopyKept':
        '지금까지의 작업은 앱 안의 실패본에 저장해 두었습니다. 실패본은 프로그램을 닫으면 사라집니다 — 남기려면 「실패본 백업…」으로 원하는 곳에 저장하세요.',
    'saveFailedNoCopy': '실패본도 만들지 못했습니다 — 「다른 이름으로 저장」으로 다른 곳에 저장하세요.',
    'saveFailedRetry': '원인이 없어진 뒤 다시 저장하면 원래 파일에 저장됩니다.',
    'saveFailedDetailsHeading': '자세히',
    'saveFailedCopyLineTemplate': '실패본: {path}',
    'saveFailedErrorLineTemplate': '오류: {error}',
    'shortcutAction.file-back-up-failed-copy': '실패본 백업',
    'failedCopyPickTitle': '백업할 실패본',
    'failedCopyVanishOnClose': '실패본은 프로그램을 닫으면 사라집니다.',
    'failedCopyBackingUp': '백업 중…',
    'failedCopyBackedUp': '백업 완료',
    'closeProjectFailedCopyBody':
        '이 프로젝트가 저장하지 못한 작업은 앱 안의 실패본에만 있고, 실패본은 프로그램을 닫으면 사라집니다. 남기려면 「다른 이름으로 저장」하거나 파일 메뉴의 「실패본 백업…」을 쓰세요.',
    'projectFileVanished':
        '이 프로젝트의 파일이 사라졌습니다 — 지워졌거나 옮겨졌습니다. 휴지통에 아직 있다면 지금 되살리세요. 이미 저장했던 그림들은 그 파일 안에만 있습니다.',
    'uiScaleLabel': 'UI 크기',
    'blockFrameLinesLabel': '블록 안 프레임선',
    'unnamedMarkLabel': '이름 없는 블록의 마크',
    'drawingCursorLabel': '커서',
    'drawingCursorBrush': '브러시',
    'drawingCursorPen': '펜',
    'drawingCursorCrosshair': '십자',
    'accent1Help': '선택·플레이헤드·켜진 토글에 쓰입니다.',
    'sheetFormatTitle': '타임시트 서식',
    'sheetFieldTitle': '제목',
    'sheetFieldEpisode': '화수',
    'sheetFieldScene': '씬',
    'sheetFieldCut': '컷',
    'sheetFieldTime': '타임',
    'sheetFieldName': '작화자',
    'sheetFieldSheet': '시트',
    'workSettingsTitle': '작품 설정',
    'workSettingsStaff': '스태프 설정',
    'workLogo': '회사 로고',
    'workCover': '표지 그림',
    'staffWorker': '작업자',
    'sheetVisibleBoxes': '표시할 칸',
    'sheetStretchLineAction': '늘림 선 · 액션란',
    'sheetStretchLineCell': '늘림 선 · 셀란',
    'sheetStretchLineHelp': 'N코마 이상 止め · ×에서 (N+1)번째 코마부터 선을 긋기',
    'sheetStretchLineOn': '있음',
    'sheetStretchLineOff': '없음',
    'sheetSeEmptyFill': '대사 없는 구간',
    'sheetLength': '시트 길이',
    'sheetThreeSeconds': '3초',
    'sheetSixSeconds': '6초',
    'sheetFillOn': '칠함',
    'sheetFillOff': '비움',
    'sheetBrushAllow': '브러시 허용',
    'conteCoverPage': '표지',
    'conteBlankPage': '빈 용지',
    'conteFormatTitle': '콘티 용지 서식',
    'conteFrontIn': '넣음',
    'conteFrontOut': '뺌',
    'conteForm': '양식',
    'conteFormAnalog': '아날로그',
    'conteFormDigital': '디지털',
    'conteOutline': '화면 검은 외곽선',
    'conteOutlineOn': '적용',
    'conteOutlineOff': '미적용',
    'envelopeFormatTitle': '컷 봉투 서식',
    'envelopeForm': '양식',
    'sheetModeNotation': '표기 시트(반복·止め 글자)',
    'sheetModeData': '데이터 시트(내보내는 그대로)',
    'instructionsTitle': '지시 기호',
    'instructionEditTooltip': '지시 기호 편집',
    'instructionDeleteTooltip': '지시 기호 삭제',
    'instructionAddButton': '새 지시 기호',
    'instructionDefTitle': '지시 기호',
    'instructionDefNameLabel': '이름 (FI, PAN 등)',
    'instructionEventEditTitle': '지시 편집',
    'instructionEventAddTitle': '새 지시',
    'instructionMarkLabel': '지시 (기호)',
    'instructionMarkNone': '(없음)',
    'instructionNameLabel': '이름 (비우면 기호 이름)',
    'instructionStartLabel': '시작 이름 (A)',
    'instructionEndLabel': '끝 이름 (B)',
    'instructionEditSetButton': '지시 기호 편집',
    'instructionEditorIcon': '아이콘',
    'instructionEditorColor': '색',
    'instructionEditorMark': '기호',
    'systemStatusHelp':
        '각 서브시스템이 지금 어떤 구현으로 돌고 있는지입니다. 폴백 경로에서도 앱은 동작하지만 대개 더 느립니다 — 자세히 알고 싶으면 이름으로 검색할 수 있습니다.',
    'shortcutShelf.canvas': '캔버스',
    'shortcutShelf.tools': '도구',
    'shortcutShelf.toolTiles': '세부 도구',
    'shortcutShelf.blendModes': '합성 모드',
    'shortcutShelf.selection': '선택',
    'shortcutShelf.edit': '편집',
    'shortcutShelf.view': '보기',
    'shortcutShelf.timeline': '타임라인 · 콘티',
    'shortcutShelf.moves': '이동',
    'shortcutShelf.playback': '재생',
    'shortcutShelf.pills': '알약',
    'shortcutShelf.cutPill': '컷 알약',
    'shortcutShelf.layerPill': '레이어 알약',
    'shortcutShelf.framePill': '프레임 알약',
    'shortcutShelf.fxPill': 'FX 알약',
    'shortcutShelf.sharedPill': '공용 알약',
    'shortcutShelf.colourEdit': '색 편집',
    'shortcutShelf.layerHeader': '레이어 머리',
    'shortcutShelf.timelineBar': '타임라인 막대',
    'shortcutShelf.toolLibrary': '도구 라이브러리',
    'shortcutShelf.brushLibrary': '브러시 라이브러리',
    'shortcutShelf.brushToolBrushes': '브러시 도구의 브러시',
    'shortcutShelf.eraserToolBrushes': '지우개 도구의 브러시',
    'shortcutShelf.guides': '가이드',
    'shortcutShelf.texts': '텍스트',
    'shortcutShelf.topStrip': '맨 위 띠',
    'shortcutShelf.file': '파일',
    'shortcutShelf.settings': '설정',
    'shortcutShelf.panels': '패널',
    'shortcutShelf.debug': '디버그',
    'shortcutShelf.inAPanel': '패널 안',
    'shortcutShelf.media': '미디어',
    'shortcutShelf.timesheet': '타임시트',
    'shortcutShelf.conteSheet': '콘티 용지',
    'shortcutShelf.envelope': '컷 봉투',
    'shortcutShelf.palette': '팔레트',
    'shortcutPreset.clipStudio': '클립 스튜디오 기반',
    'shortcutPreset.tvpaint': 'TVPaint 기반',
    'shortcutAction.frame-previous': '이전 프레임',
    'shortcutAction.frame-next': '다음 프레임',
    'shortcutAction.drawing-previous': '이전 블록',
    'shortcutAction.drawing-next': '다음 블록',
    'shortcutAction.playback-toggle': '재생 / 일시정지',
    'shortcutAction.playback-to-start': '처음으로',
    'shortcutAction.playback-loop-toggle': '반복 / 한 번 재생',
    'shortcutAction.canvas-pan-hold': '이동(누르는 동안)',
    'shortcutAction.canvas-rotate-hold': '회전(누르는 동안)',
    'shortcutAction.canvas-line-hold': '직전 획에서 직선(누르는 동안)',
    'shortcutAction.voice-record-toggle': '음성 녹음 (시작/정지)',
    'shortcutAction.edit-undo': '실행 취소',
    'shortcutAction.edit-redo': '다시 실행',
    'shortcutAction.tool-brush': '브러시 도구',
    'shortcutAction.tool-eraser': '지우개 도구',
    'shortcutAction.tool-eyedropper': '스포이트 도구',
    'shortcutAction.tool-fill': '채우기 도구',
    'shortcutAction.tool-fill-bucket': '채우기',
    'shortcutAction.tool-text': '텍스트 도구',
    'shortcutAction.tool-shape': '도형 도구',
    'shortcutAction.tool-guide': '가이드 도구',
    'shortcutAction.guide-add-symmetry': '새 대칭 가이드',
    'shortcutAction.guide-add-perspective': '새 퍼스 가이드',
    'shortcutAction.timesheet-data-mode': '표기 시트 / 데이터 시트',
    'shortcutAction.tool-select': '선택 도구',
    'shortcutAction.tool-transform': '변형 도구',
    'shortcutAction.tool-transform-normal': '일반 변형',
    'shortcutAction.tool-transform-free': '자유 변형',
    'shortcutAction.tool-transform-mesh': '메시 워프',
    'shortcutAction.tool-cut': '잘라내기 도구',
    'shortcutAction.tool-cut-whole': '전체 잘라내기',
    'shortcutAction.tool-cut-stamp': '스탬프',
    'shortcutAction.selection-deselect': '선택 해제',
    'shortcutAction.layer-up': '위 레이어',
    'shortcutAction.layer-down': '아래 레이어',
    'shortcutAction.edit-confirm': '확정',
    'shortcutAction.selection-transform-cancel': '변형 취소',
    'shortcutAction.transform-flip-horizontal': '변형 좌우 반전',
    'shortcutAction.transform-flip-vertical': '변형 상하 반전',
    'shortcutAction.transform-reset': '변형 초기화',
    'shortcutAction.cut-stamp-reset': '스탬프 초기화',
    'shortcutAction.onion-skin-toggle': '어니언 스킨 켜기/끄기',
    'shortcutAction.camera-view-toggle': '카메라 뷰 켜기/끄기',
    'shortcutAction.canvas-rotate-ccw': '캔버스 보기 왼쪽 회전',
    'shortcutAction.canvas-rotate-cw': '캔버스 보기 오른쪽 회전',
    'shortcutAction.canvas-flip-horizontal': '캔버스 보기 좌우 반전',
    'shortcutAction.canvas-flip-vertical': '캔버스 보기 상하 반전',
    'shortcutAction.canvas-straighten': '캔버스 보기 기울기 초기화',
    'shortcutAction.canvas-fit': '캔버스 보기 화면에 맞추기',
    'shortcutAction.canvas-reset-view': '캔버스 줌 초기화 (100%)',
    'shortcutAction.timeline-comma-1': '1코마로 설정',
    'shortcutAction.timeline-comma-2': '2코마로 설정',
    'shortcutAction.timeline-comma-3': '3코마로 설정',
    'shortcutAction.timeline-comma-4': '4코마로 설정',
    'shortcutAction.timeline-comma-n': 'N코마로 설정',
    'shortcutAction.frame-new-drawing': '새 프레임',
    'shortcutAction.layer-add': '새 레이어',
    'shortcutAction.frame-blank-exposure': '비우기',
    'shortcutAction.frame-toggle-mark-one': '중간나누기 마크1',
    'shortcutAction.frame-toggle-mark': '중간나누기 마크2',
    'shortcutAction.frame-mark-every': '중간나누기 마크 자동 추가',
    'shortcutAction.timeline-push-blocks': '밀기(칸 열기)',
    'shortcutAction.timeline-pull-blocks': '당기기(칸 닫기)',
    'shortcutAction.timeline-zoom-in': '타임라인 확대',
    'shortcutAction.timeline-zoom-out': '타임라인 축소',
    'shortcutAction.timeline-zoom-fit': '타임라인 줌 맞춤',
    'shortcutAction.timeline-orientation-toggle': '타임라인 / X시트',
    'shortcutAction.edit-cut': '잘라내기',
    'shortcutAction.edit-copy': '복사',
    'shortcutAction.edit-paste-linked': '링크 붙여넣기',
    'shortcutAction.edit-paste-independent': '독립 붙여넣기',
    'shortcutAction.edit-unlink': '링크 독립',
    'shortcutAction.edit-delete': '삭제',
    'shortcutAction.edit-duplicate': '복제',
    'shortcutAction.edit-merge': '병합',
    'shortcutAction.edit-replace-colour': '색 변환',
    'shortcutAction.edit-clear-pixels': '픽셀 비우기',
    'shortcutAction.edit-binarize': '2치화',
    'shortcutAction.edit-delete-colour': '색 삭제',
    'shortcutAction.edit-keep-colour': '색 남기기',
    'shortcutAction.edit-cut-pixels': '픽셀 잘라내기',
    'shortcutAction.edit-copy-pixels': '픽셀 복사',
    'shortcutAction.edit-paste-pixels-above': '픽셀 위 붙여넣기',
    'shortcutAction.edit-paste-pixels-below': '픽셀 아래 붙여넣기',
    'shortcutAction.edit-instance': '편집',
    'shortcutAction.edit-auto-name': '자동 이름 지정',
    'blendMode.passThrough': '통과',
    'blendMode.normal': '표준',
    'blendMode.color': '표준',
    'blendMode.behind': '배경',
    'blendMode.erase': '지우기',
    'blendMode.darken': '어둡게 하기',
    'blendMode.multiply': '곱하기',
    'blendMode.colorBurn': '색상 번',
    'blendMode.lighten': '밝게 하기',
    'blendMode.screen': '스크린',
    'blendMode.colorDodge': '색상 닷지',
    'blendMode.add': '선형 닷지(추가)',
    'blendMode.overlay': '오버레이',
    'blendMode.softLight': '소프트 라이트',
    'blendMode.hardLight': '하드 라이트',
    'blendMode.difference': '차이',
    'blendMode.exclusion': '제외',
    'blendMode.linearBurn': '선형 번',
    'blendMode.subtract': '빼기',
    'blendMode.vividLight': '선명한 라이트',
    'blendMode.linearLight': '선형 라이트',
    'blendMode.pinLight': '핀 라이트',
    'blendMode.hardMix': '하드 혼합',
    'blendMode.darkerColor': '어두운 색상',
    'blendMode.lighterColor': '밝은 색상',
    'blendMode.divide': '나누기',
    'blendMode.hue': '색조',
    'blendMode.saturation': '채도',
    'blendMode.chroma': '색상',
    'blendMode.luminosity': '광도',
    'effectKind.brightnessContrast': '명도 및 대비',
    'effectKind.hueSaturation': '색조/채도',
    'effectKind.blur': '가우시안 흐림',
    'effectKind.directionalBlur': '방향 흐림',
    'effectKind.radialBlur': '방사형 흐림',
    'effectKind.cameraLensBlur': '카메라 렌즈 흐림',
    'effectKind.colorKey': '색상 키',
    'effectKind.celNumber': '셀 번호',
    'effectParameter.brightness': '명도',
    'effectParameter.contrast': '대비',
    'effectParameter.hue': '마스터 색조',
    'effectParameter.saturation': '마스터 채도',
    'effectParameter.lightness': '마스터 밝기',
    'effectParameter.blurriness': '흐림 정도',
    'effectParameter.blurDimensions': '흐림 방향',
    'effectParameter.repeatEdgePixels': '가장자리 픽셀 반복',
    'effectParameter.direction': '방향',
    'effectParameter.blurLength': '흐림 길이',
    'effectParameter.keyColor': '키 색',
    'effectParameter.ink': '잉크',
    'effectParameter.tolerance': '허용차',
    'effectParameter.amount': '적용량',
    'effectParameter.keyOperation': '키 작업',
    'effectParameter.center': '중심',
    'effectParameter.type': '유형',
    'effectParameter.antialiasing': '안티앨리어스',
    'effectParameter.blurRadius': '흐림 반경',
    'effectParameter.irisShape': '모양',
    'effectParameter.irisRoundness': '원형률',
    'effectParameter.irisAspectRatio': '종횡비',
    'effectParameter.irisRotation': '회전',
    'effectParameter.irisDiffractionFringe': '에돌이 줄무늬',
    'effectParameter.blurMapLayer': '흐림 맵 레이어',
    'effectParameter.blurMapChannel': '흐림 맵 채널',
    'effectParameter.blurFocalDistance': '흐림 초점 거리',
    'effectParameter.invertBlurMap': '흐림 맵 반전',
    'effectParameter.highlightGain': '하이라이트 증폭',
    'effectParameter.highlightThreshold': '하이라이트 문턱',
    'effectParameter.highlightSaturation': '하이라이트 채도',
    'effectParameter.useLinearWorkingSpace': '선형 작업 공간 사용',
    'effectChoice.keyColors': '키 색상',
    'effectChoice.keepColors': '색상 유지',
    'effectChoice.horizontalAndVertical': '가로 및 세로',
    'effectChoice.horizontal': '가로',
    'effectChoice.vertical': '세로',
    'effectChoice.spin': '회전',
    'effectChoice.zoom': '확대/축소',
    'effectChoice.best': '최고',
    'effectChoice.draft': '드래프트',
    'effectChoice.triangle': '삼각형',
    'effectChoice.square': '사각형',
    'effectChoice.pentagon': '오각형',
    'effectChoice.hexagon': '육각형',
    'effectChoice.heptagon': '칠각형',
    'effectChoice.octagon': '팔각형',
    'effectChoice.nonagon': '구각형',
    'effectChoice.decagon': '십각형',
    'effectChoice.luminance': '광도',
    'effectChoice.red': '빨강',
    'effectChoice.green': '녹색',
    'effectChoice.blue': '파랑',
    'effectChoice.alpha': '알파',
    // R26 #16 — the user's own words for the four selection modes
    // (「갱신/추가/삭제/선택중」), moved here from the enum.
    'selectionMode.replace': '갱신',
    'selectionMode.add': '추가',
    'selectionMode.subtract': '삭제',
    'selectionMode.intersect': '선택중',
    'shortcutAction.file-save': '저장',
    'shortcutAction.file-save-as': '다른 이름으로 저장',
    'shortcutAction.layer-visibility-solo': '활성 레이어 솔로',
    'shortcutAction.canvas-zoom-in': '확대',
    'shortcutAction.canvas-zoom-out': '축소',
    'cutCommands': '컷 명령',
    'shortcutAction.cut-new': '새 컷',
    'shortcutAction.cut-edit-note': '컷 메모 편집',
    'shortcutAction.cut-settings': '컷 설정',
    'cutSettingsTitle': '컷 설정',
    'mediaActions': '미디어 작업',
    'mediaPoolEmpty': '미디어가 없습니다',
    'mediaRename': '미디어 이름 변경',
    'mediaPlace': '배치',
    'mediaRelink': '다시 연결',
    'mediaMissingCount': '못 찾은 파일 {n}개',
    'mediaFindInFolder': '폴더에서 찾기',
    'mediaRelinkFound': '{n}개 중 {m}개를 찾았습니다. 다시 연결할까요?',
    'mediaRelinkScanning': '폴더를 읽는 중…',
    'mediaRelinkScanned': '폴더를 읽었습니다',
    'mediaRemove': '미디어 삭제',
    'mediaRegisterInProject': '프로젝트 파일에 품기',
    'mediaExportWav': 'WAV로 내보내기',
    'mediaExportWavNoAudio': '이 소재에는 내보낼 오디오가 없습니다.',
    'mediaCarriedState': '품음',
    'mediaReferencedState': '참조',
    'projectLegacyAssetsFolder':
        '이 프로젝트 옆에 아직 {name} 폴더가 있습니다. 이제 쓰지 않습니다 — '
        '한 번 저장하면 안의 미디어가 프로젝트 파일로 들어가고, 그 뒤엔 폴더를 지워도 됩니다.',
    'mediaRemoveInUse': '사용 중인데 삭제하겠습니까? 배치한 레이어/프레임이 삭제됩니다.',
    'mediaUsesHeading': '쓰는 곳',
    'mediaOpenInViewer': '뷰어에서 열기',
    'mediaOpenInSubViewer': '서브 뷰어에서 열기',
    'mediaViewerEmpty': '표시할 것이 없습니다',
    'mediaViewerOpenFile': '파일 열기',
    'mediaViewerCloseFile': '파일 닫기',
    'mediaViewerLoadFailed': '이 파일을 읽지 못했습니다.',
    'mediaViewerCutTooLarge': '메모리 허용치 안에 들어가지 않아 원본 크기로 잘라낼 수 없습니다.',
    'mediaViewerCannotDisplay': '이 종류의 미디어는 아직 표시할 수 없습니다.',
    'mediaViewerNoPdfRenderer': '이 빌드에는 PDF 렌더러가 없습니다 — PDF 페이지를 표시할 수 없습니다.',
    'mediaViewerNoVideoDecoder': '이 빌드에는 비디오 디코더가 없습니다 — 동영상을 표시할 수 없습니다.',
    'mediaViewerNoAudioDecoder': '이 소리를 읽지 못했습니다 — 파형을 표시할 수 없습니다.',
    'mediaViewerSwap': '반대쪽 뷰어와 맞바꾸기',
    'unsupportedFileTitle': '지원하지 않는 파일',
    'unsupportedFileMessageTemplate':
        '지원하지 않는 파일이 감지되었습니다. 사용 가능한 형식: {kinds}.',
    'mediaViewerRegisterAsset': '미디어에 등록',
    'panelMediaViewer': '뷰어',
    'panelMediaViewerSub': '서브 뷰어',
    'panelCanvas': '캔버스',
    'panelColorWheel': '컬러 휠',
    'transportIn': '인',
    'transportOut': '아웃',
    'transportToStart': '처음으로',
    'transportToEnd': '끝으로',
    'transportLoop': '루프',
    'transportOnce': '한 번 재생',
    'transportPrevFrame': '이전 프레임',
    'transportNextFrame': '다음 프레임',
    'colorRecent': '최근',
    'colorBackgroundSwap': '배경색 (눌러서 교체)',
    'paletteViewCompact': '작게',
    'paletteViewCards': '카드',
    'paletteNew': '새 팔레트',
    'paletteNumberedTemplate': '팔레트 {n}',
    'paletteMakeDefault': '기본 팔레트로',
    'paletteDuplicate': '복제',
    'paletteExport': '내보내기',
    'paletteBroughtTemplate': '「{name}」 팔레트를 추가했습니다.',
    'paletteCopyTemplate': '{name} 사본',
    'paletteDeleteTitle': '팔레트 삭제',
    'paletteDeleteTemplate': '「{name}」 팔레트를 삭제할까요?',
    'paletteRemoveCurrent': '지금 색 빼기',
    'paletteLock': '팔레트 잠금',
    'paletteMore': '더 보기',
    'penPressureTitle': '필압',
    'brushDynamicsTitle': '반응',
    'curveSourcePressure': '필압',
    'curveSourceTilt': '기울기',
    'curveSourceSpeed': '속도',
    'curveSourceRandom': '랜덤',
    'curveMinimum': '최소값',
    'curveMaximum': '최대값',
    'curveTiltFlat': '수평',
    'curveTiltUpright': '수직',
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
    'panelConte': '콘티 용지',
    'panelEnvelope': '컷 봉투',
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
    'onionBeforeTint': '이전 색',
    'onionAfterTint': '이후 색',
    'onionGhostColorHelp': '고스트에 색을 입히는 방식',
    'onionPegCountHelp': '한 칸이 세는 단위',
    'onionPlacementHelp': '고스트가 놓이는 자리',
    'onionStepBlocks': '블록',
    'onionStepBlocksDrawings': '블록(그림)',
    'onionStepFrames': '프레임',
    'onionModeColors': '색',
    'onionModeImages': '그림',
    'onionPlacementOnTop': '맨 위',
    'onionPlacementInPlace': '제자리',
    'onionPegBeforeTemplate': '이전 {n}',
    'onionPegAfterTemplate': '이후 {n}',
    'shortcutTitle': '키보드 단축키',
    'shortcutResetAll': '모두 초기화',
    'shortcutFileImportedTemplate':
        '단축키 {taken}개를 새 프리셋 「{preset}」에 가져왔습니다'
        '(대응 없음 {skipped}개).',
    'shortcutPresets': '프리셋',
    'shortcutPresetNew': '새 프리셋',
    'shortcutPresetNameEmpty': '프리셋 이름은 비울 수 없습니다.',
    'shortcutPresetDelete': '프리셋 삭제',
    'shortcutPresetRename': '프리셋 이름 바꾸기',
    'shortcutPresetDuplicate': '프리셋 복제',
    'shortcutPresetExport': '프리셋 내보내기',
    'shortcutPresetBroughtTemplate': '「{name}」 프리셋을 추가했습니다.',
    'shortcutPresetCopyTemplate': '{name} 복사본',
    'shortcutPresetDeleteTemplate': '「{name}」 프리셋을 삭제할까요?',
    'shortcutFileUnreadableTemplate':
        '{name}: 이 파일에서 읽을 단축키가 없습니다.',
    'shortcutResetToDefault': '기본값으로',
    'shortcutUnassign': '단축키 해제',
    'shortcutRecordNew': '새 단축키 기록',
    'shortcutTouch': '터치 단축키',
    'shortcutSearch': '동작 검색',
    'shortcutConflictBanner': '같은 키를 쓰는 동작이 있습니다 — 강조된 할당이 충돌합니다.',
    'shortcutRecordingHint': '키를 누르세요… (Esc로 취소)',
    'playbackMode': '재생 방식',
    'playbackModeSkipFrames': '건너뛰기',
    'playbackModeEveryPicture': '모든 그림',
    'playbackModeRenderFirst': '재생 전 렌더링',
    'playbackDroppedCount': '{n} 건너뜀',
    'playbackDroppedCountOne': '{n} 건너뜀',
    'playbackSilentCount': '소리 {n}개 못 냄',
    'playbackSilentCountOne': '소리 {n}개 못 냄',
    'playbackOutputRefused': '소리가 안 납니다 — 출력 장치를 열지 못했습니다.',
    'soundCannotPlay.missing': '재생할 수 없음 — 파일이 없습니다.',
    'soundCannotPlay.notReadYet':
        '아직 재생할 수 없음 — 파일을 읽지 못했습니다(클라우드 파일을 아직 내려받는 중일 수 있습니다).',
    'soundCannotPlay.format': '재생할 수 없음 — 이 형식을 읽는 디코더가 없습니다.',
    'soundCannotPlay.conform': '재생할 수 없음 — 재생용 변환에 실패했습니다.',
    'soundCannotPlay.deviceRate':
        '재생할 수 없음 — 출력 장치의 샘플레이트로 바꾸지 못했습니다.',
    'playbackStop': '정지',
    'sheetPreviousPage': '이전 페이지',
    'sheetNextPage': '다음 페이지',
    'sheetPageDrag': '페이지 (드래그)',
    'autosaveTitle': '자동 저장',
    'autosaveEvery': '주기',
    'autosaveSectionHelp':
        '일정 주기로 프로젝트를 저장합니다. 크래시나 배터리 방전으로 잃는 작업이 최대 그 주기만큼으로 줄어듭니다.',
    'autosaveSwitchHelp': '끄면 프로젝트는 저장할 때만 바뀌고, 크래시가 나면 그 이후 작업이 전부 사라집니다.',
    'appContainerTitle': '앱 컨테이너',
    'appContainerHelp':
        '프로젝트 파일 바깥에 앱이 두는 것 — 설정과 브러시 팁, 가져오기가 들여왔지만 아직 어떤 저장에도 흡수되지 않은 미디어와 오디오, 그리고 진단 로그입니다.',
    'commonMinutesShort': '분',
    'exExport': '내보내기',
    'exAddToQueue': '큐에 추가',
    'exImage': '이미지',
    'exVideo': '동영상',
    'exCels': '셀',
    'exFormat': '형식',
    'exOptions': '옵션',
    'exNaming': '이름 규칙',
    'exScope': '범위',
    'exQuality': '품질',
    'exCodec': '코덱',
    'exBitrate': '비트레이트',
    'exChannels': '채널',
    'exAudio': '오디오',
    'exHandOverDeclined': '넘기지 않아 내보낸 결과물을 버렸습니다.',
    'exHandOverPending': '결과물을 아직 넘기지 않았습니다.',
    'exHandOverPickAgain': '다시 고르기',
    'exHandOverDiscard': '버리기',
    'exSavePreset': '프리셋 저장',
    'exPresetNameEmpty': '프리셋 이름은 비울 수 없습니다.',
    'exBaseName': '기본 이름',
    'exSuffix': '접미사',
    'exPrefix': '접두사',
    'exLayDirection': '이 그림에 디렉션 적용',
    'exLayGuides': '가이드',
    'exCelFormat': '셀 형식',
    'exTimesheetFormat': '타임시트 형식',
    'exEnvelopeFormat': '컷 봉투 형식',
    'exWrittenCount': '{n}장',
    'exWrittenCountOne': '{n}장',
    'noticeExportNoPicture': '이 셀에 켜진 그림이 존재하지 않습니다',
    'noticeExportNotPlaced': '타임라인에 놓이지 않은 그림입니다',
    'noticeExportSameName': '같은 이름의 줄이 이 그림을 내보냅니다',
    'exDigits': '자릿수',
    'exApplyLayerFx': '레이어 FX',
    'exMuxSeMix': 'SE 믹스를 영상에 먹싱',
    'exLabel': '라벨',
    'exApply': '적용',
    'exKinds': '내보낼 종류',
    'exLayerFilter': '레이어',
    'exSelBase': '기준',
    'exCelsLayersOut': '출력할 레이어',
    'exSelAttach': '어태치',
    'exSelSheet': '시트만',
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
    'exStratumPaper': '용지',
    'exStratumForm': '서식',
    'exStratumContent': '텍스트',
    'exStratumPicture': '그림',
    'exStratumInk': '잉크',
    'exLeftOutOfTheFile': '파일에 담지 못한 것이 있습니다.',
    'exNoCels': '(셀 없음)',
    'exNoCuts': '(컷 없음)',
    'exPresets': '프리셋',
    'exQueue': '대기열',
    'exSize': '크기',
    'exCutSize': '컷 크기',
    'exRealSheet': '실측 용지',
    'imNotTvpp': 'TVPaint 프로젝트로 읽을 수 없는 파일입니다.',
    'imNotClip': 'CLIP STUDIO PAINT 파일로 읽을 수 없는 파일입니다.',
    'imLeftBehind': '가져오지 못한 것이 있습니다.',
    'imWarningCount': '경고 {n}가지',
    'imWarningCountOne': '경고 {n}가지',
    'imFileUnreadable': '파일을 읽지 못했습니다 — 클라우드의 파일이면 잠시 후 다시 시도해 주세요.',
    'imNotFoundTemplate': '찾을 수 없습니다: {path}',
    'importWarning.stagedCopy': '제자리에서 읽지 못해 임시 사본으로 열었습니다 — 이 문구가 보이면 알려주세요.',
    'importWarning.soundMissing': '사운드 파일이 이 자리에 없습니다: {path}',
    'importWarning.celUnreadable': '{file}: 그림을 읽지 못했습니다 — {detail}',
    'importWarning.psdBitDepth': '{depth}비트 문서를 8비트로 낮췄습니다.',
    'importWarning.psdVectorMask': '{name}: 벡터 마스크를 무시했습니다.',
    'importWarning.psdComposite': '합성 이미지의 압축 방식 {compression} 은(는) 지원하지 않습니다 — 건너뛰었습니다.',
    'importWarning.psdExtraChannels': '문서의 여분 채널을 무시했습니다.',
    'importWarning.psd32Bit': '32비트 예측 채널 데이터는 지원하지 않습니다.',
    'importWarning.psdDuotone': '듀오톤을 그레이스케일로 읽었습니다.',
    'importWarning.psdMultichannel': '멀티채널을 첫 채널의 그레이스케일로 읽었습니다.',
    'importWarning.psdIndexedNoPalette': '팔레트가 없는 인덱스 컬러를 그레이스케일로 읽었습니다.',
    'importWarning.psdCmyk': 'CMYK를 프로파일 없이 RGB로 변환했습니다 — 색이 달라집니다.',
    'importWarning.psdLab': 'Lab를 프로파일 없이 RGB로 변환했습니다 — 색이 달라집니다.',
    'importWarning.clippingNotApplied': '{name}: 클리핑 마스크는 적용하지 않았습니다.',
    'importWarning.layerEffectsNotApplied': '{name}: 레이어 효과는 적용하지 않았습니다.',
    'importWarning.layerMaskNotApplied': '{name}: 레이어 마스크는 적용하지 않았습니다.',
    'importWarning.lockNotImported': '{name}: 잠금은 가져오지 않았습니다.',
    'importWarning.psdBlend': '{name}: 블렌드 모드 "{mode}" 에 해당하는 것이 없습니다 — 보통으로 설정했습니다.',
    'importWarning.folderNothing': '이 폴더에 가져올 수 있는 셀이나 그림이 없습니다.',
    'importWarning.folderNoCutNumber': '폴더 이름에서 컷 번호를 찾지 못했습니다.',
    'importWarning.tvpNoFile': '{name}: {frame}프레임의 인스턴스가 파일 이름을 갖고 있지 않습니다 — 그 셀은 빈 채로 둡니다.',
    'importWarning.tvpMuted': '{file}: 트랙이 뮤트 상태였습니다 — 소리는 그대로 연결합니다.',
    'importWarning.tvpBlend': '{name}: 블렌딩 모드 "{mode}" 에 해당하는 것이 Anicel 에 없습니다 — 보통으로 가져왔습니다.',
    'importWarning.tvppHoldNoDrawing': '{name}: {frame}프레임의 홀드가 이어받을 그림이 없습니다.',
    'importWarning.tvppChunkBroken': '클립 {n}: @{at} 에서 청크 열이 끊겼습니다 — 이후 데이터는 버립니다.',
    'importWarning.clipRead': '파일의 일부를 따라가지 못했습니다: {detail}',
    'importWarning.clipFps': '타임라인마다 프레임 레이트가 다릅니다 — 프로젝트는 첫 타임라인의 {fps} fps 로 했습니다.',
    'importWarning.clipUnplaced': '{name}: 어느 타임라인에도 놓이지 않은 셀 {count}장은 가져오지 않았습니다.',
    'importWarning.clipNoSuchCel': '{name}: 폴더에 없는 셀을 가리키는 키가 {count}개 있습니다.',
    'importWarning.clipCelLayers': '{name}: 셀 안의 레이어는 다른 셀과 이름이 같으면 이름으로, 아니면 위에서 몇 번째인가로 행에 나눴습니다 — 각자의 이름과 폴더는 남지 않습니다.',
    'importWarning.clipSpread': '{name}: 셀 {count}장에서 폴더의 불투명도나 합성 모드를 안의 레이어마다 나눠 줬습니다 — 레이어가 겹치는 자리는 다르게 보일 수 있습니다.',
    'importWarning.clipLineOrder': '{name}: 셀 {count}장에서 두 레이어의 순서가 CLIP STUDIO와 반대가 됐습니다 — 레이어가 겹치는 자리는 다르게 보일 수 있습니다.',
    'importWarning.clipVector':
        '{name}: 벡터 레이어 — 둥근 펜으로 그렸습니다. 브러시의 모양과 질감은 옮기지 못했습니다.',
    'importWarning.clipVectorUnread':
        '{name}: 읽지 못하는 종류의 벡터 선 {count}개 — 그리지 않았습니다.',
    'importWarning.clipSound': '{name}: 소리 레이어는 가져오지 않았습니다.',
    'importWarning.clipSoundMissing':
        '{name}: 그 소리가 파일에 들어 있지 않습니다 — 재생하지 않습니다.',
    'importWarning.clipSoundSpeed':
        '{name}: CLIP STUDIO 에서는 다른 속도로 재생됩니다 — 여기서는 제 속도로 재생합니다.',
    'importWarning.clipSoundVolume':
        '{name}: 클립 안에서 음량이 바뀝니다 — 클립이 시작할 때의 음량으로 맞췄습니다.',
    'importWarning.clipCurve':
        '{name}: 읽지 못하는 보간의 키가 있습니다 — 그 사이는 곧게 움직입니다.',
    'importWarning.unsupportedLayerKind':
        '{name}: 이 레이어 종류는 지원되지 않습니다.',
    'importWarning.clipBlend': '{name}: 합성 모드 {mode} 에 해당하는 것이 없습니다 — 보통으로 설정했습니다.',
    'importWarning.clipNotColour': '{name}: 그레이 · 모노크롬 레이어 — 그리지 않았습니다.',
    'importWarning.clipTransform': '{name}: 그림의 크기 · 회전은 적용하지 않았습니다.',
    'importWarning.clipTextUnread': '{name}: 설정을 읽지 못한 글 — 가져오지 않았습니다.',
    'importWarning.clipTextAlign':
        '{name}: 이 앱이 짤 수 없는 정렬의 줄 — CLIP STUDIO가 그린 그대로 보이고, 고치면 한 가지 정렬로 다시 짜입니다.',
    'importWarning.clipTextSpacing':
        '{name}: 고르지 않은 줄 간격 — CLIP STUDIO가 그린 그대로 보이고, 고치면 고른 줄 간격으로 다시 짜입니다.',
    'importWarning.clipTextDistorted':
        '{name}: 비스듬히 일그러진 글 — CLIP STUDIO가 그린 그대로 보이고, 고치면 반듯하게 다시 짜입니다.',
    'importWarning.clipTextSetHere':
        '{name}: 이 앱이 짠 글 — CLIP STUDIO가 그린 그림이 파일에 없거나 읽지 못했습니다.',
    'importWarning.brushPackUnreadable': '이 파일은 Anicel 브러시 파일로 읽을 수 없습니다.',
    'importWarning.brushPackNotOurs': '이 파일은 Anicel 브러시 파일이 아닙니다.',
    'importWarning.brushPackNewer':
        '이 브러시 파일은 더 새 버전의 Anicel 에서 썼습니다(형식 {version}). '
        '이 빌드는 {readable} 까지 읽습니다.',
    'importWarning.brushPackEmpty': '이 브러시 파일에는 브러시가 없습니다.',
    'importWarning.brushPackDamaged': '이 브러시 파일은 손상되어 읽지 못했습니다.',
    'importWarning.abrTooShort': 'ABR 파일이라기엔 너무 짧습니다.',
    'importWarning.abrOldVersion':
        'ABR 버전 {version}(Photoshop 6 시절)은 아직 지원하지 않습니다. '
        '새 Photoshop 으로 브러시를 다시 저장해 주세요.',
    'importWarning.abrUnknownVersion': '지원하지 않는 ABR 파일입니다(버전 {version}).',
    'importWarning.abrCorruptSection': 'ABR 구역의 길이가 손상되었습니다.',
    'importWarning.abrNoBrushes': 'ABR 파일에서 브러시를 찾지 못했습니다.',
    'importWarning.abrNothingImportable': 'ABR 파일에 가져올 수 있는 브러시가 없습니다.',
    'importWarning.sutCannotOpen': '파일을 열지 못했습니다: {error}',
    'importWarning.sutUnreadable':
        '이 파일은 읽을 수 있는 CLIP STUDIO 브러시가 아닙니다({error}).',
    'importWarning.sutNoBrushData': '이 파일에서 CLIP STUDIO 브러시 데이터를 찾지 못했습니다.',
    'importWarning.sutNothingImportable': '파일에 가져올 수 있는 브러시가 없습니다.',
    'fileType.anicel': 'Anicel 프로젝트',
    'fileType.wav': 'WAV 오디오',
    'fileType.anibrush': 'Anicel 브러시',
    'exclusionReason.processSubfolder': '공정 하위 폴더(보관)',
    'exclusionReason.unrecognized': '알 수 없는 이름',
    'exclusionReason.excludedName': '제외 이름',
    'exclusionReason.memoText': '메모 텍스트',
    'exclusionReason.insertionLettersOff': '중간 삽입 문자 꺼짐',
    'exFrameCount': '{n}프레임',
    'exFrameCountOne': '{n}프레임',
    'exPageCount': '{n}페이지',
    'exPageCountOne': '{n}페이지',
    'exFileCount': '파일 {n}개',
    'exFileCountOne': '파일 {n}개',
    'exJobCount': '작업 {n}개',
    'exJobCountOne': '작업 {n}개',
    'exContePageCount': '콘티 {n}페이지',
    'exContePageCountOne': '콘티 {n}페이지',
    'exCancelledAfterTemplate': '{count} 내보낸 뒤 취소했습니다.',
    'exCancelledVideoTemplate': '{count} 내보낸 뒤 취소했습니다(중간까지의 영상은 남겼습니다).',
    'exCancelled': '내보내기를 취소했습니다.',
    'exDoneTemplate': '{count} 내보냈습니다.',
    'exDoneSkippedTemplate': '{count} 내보냈습니다(빈 것 {skipped}개는 건너뜀).',
    'exDoneFileTemplate': '{name} 내보냈습니다.',
    'exDoneVideoTemplate': '영상을 내보냈습니다({count}).',
    'exDoneConteDocumentTemplate': '{name} 내보냈습니다({count}).',
    'exNothingInFrame': '내보낼 것이 없습니다(빈 프레임).',
    'exFailedTemplate': '내보내기 실패: {error}',
    'exQueueRestTemplate': '대기열: {count} 완료{failed}{rest}.',
    'exQueueFailedTemplate': ', {n}개 실패',
    'exQueueRestKept': ', 나머지는 남겨 둠',
    'exFileLabel': '파일',
    'exOrderAsksFirst': '위치를 지정하고 출력합니다',
    'exOrderAsksAfter': '출력한 후 위치를 지정합니다',
    'exSeMuxedTemplate': 'SE 먹싱 · {codec}',
    'exVectorPdf': '벡터 PDF',
    'exFxOn': 'FX 켬',
    'exFxOff': 'FX 끔',
    'exFxBasic': 'FX 기본만',
    'exFxBasicOnly': '기본만 켬',
    'exTabSequence': '시퀀스',
    'exSizeCamera': '카메라',
    'exSizeCanvas': '캔버스',
    'exPageImage': '페이지 이미지',
    'exSaveCurrent': '+ 현재 설정 저장',
    'exRenderQueue': '렌더 대기열',
    'exRenderAll': '모두 렌더',
    'exJobQueued': '대기 중',
    'exJobDone': '완료',
    'exJobFailed': '실패',
    'exJobCancelled': '취소됨',
    'exJobTemplate': '작업 {id} · {tab}',
    'exIncludeAll': '전부',
    'exCutsIncludedTemplate': '{n} / {total} 컷',
    'exNeedsFfmpeg': '이 컴퓨터의 PATH에 FFmpeg가 필요합니다.',
    'exCheckingEncoders': '이 컴퓨터의 인코더를 확인하는 중…',
    'exNotInThisBuild': '이 빌드에서는 아직 쓸 수 없습니다.',
    'exBitrateAuto': '자동',
    'exCanvasTemplate': '캔버스 {size}',
    'exCanvasPerCut': '캔버스(컷마다)',
    'imImport': '임포트',
    'imFile': '파일',
    'imInto': '넣을 곳',
    'imFit': '맞춤',
    'imModified': '수정일',
    'imSize': '크기',
    'imResolution': '해상도',
    'imExcluded': '제외',
    'imFolderAsOneCut': '컷',
    'imFolderPerRow': '커스텀',
    'imPlaceTitleTemplate': '배치 — {name}',
    'imModeKeep': '품기',
    'imModeReference': '참조',
    'imBake': '래스터라이즈',
    'imOptions': '옵션',
    'imPictureAndSound': '그림 + 소리',
    'imPictureOnly': '그림만',
    'imSoundOnly': '소리만',
    'imRunSpanTemplate': '{first}–{last} ({n}장)',
    'imRateTitleTemplate': '동영상 {movie} · 프로젝트 {project}',
    'imRateBodyTemplate': '프로젝트를 {movie} 로 맞출까요? 소리는 타이밍을 유지합니다.',
    'imRateKeepTemplate': '{project} 그대로',
    'imRateTakeTemplate': '{movie} 로 맞춤',
    'commonOn': '켬',
    'commonOff': '끔',
    'imFitOriginal': '원본 크기',
    'imFitContain': '비율 유지 늘림',
    'imFitStretch': '비율 무시 늘림',
    'imIntoNewLayer': '새 레이어',
    'imIntoSeRow': 'SE 행',
    'imIntoRowCellTemplate': '{row} · {frame}번 칸',
    'imIntoNewCut': '새 컷',
    'imPsdMerge': '레이어 합치기',
    'imPsdExpand': '레이어 보존',
    'imNoSource': '고른 소스가 없습니다',
    'imFileCountTemplate': '파일 {n}개',
    'imStatusImporting': '임포트하는 중…',
    'imStatusNothing': '임포트된 것이 없습니다.',
    'imStatusDone': '임포트 완료',
    'imStepRecoding': '잘라 낸 동영상을 다시 인코딩하는 중…',
    'imStepWritingSpan': '잘라 낸 구간을 파일로 쓰는 중…',
    'imStepCarrying': '파일을 프로젝트에 품는 중…',
    'imStepRasterizing': '셀로 래스터라이즈하는 중…',
    'imFolderGone': '그 폴더가 없어졌습니다.',
    'imFolderUnreadableTemplate': '폴더를 읽지 못했습니다: {reason}',
    'imCutFolderUnreadable': '그 폴더를 읽지 못했습니다.',
    'imUnreadableTemplate': '{name}: 파일을 읽지 못했습니다.',
    'imLacksPictureTemplate': '{name}: 이 파일에는 {number}번째 그림이 없습니다.',
    'imCorruptTemplate': '{name}: 열 수 없습니다 — 손상됐거나 암호로 잠겨 있습니다.',
    'imPagesFailedTemplate': '{name}: {n}쪽을 그리지 못했습니다 — 그 셀은 비어 있습니다.',
    'imFramesFailedTemplate':
        '{name}: {n}프레임을 디코드하지 못했습니다 — 그 셀은 비어 있습니다.',
    'imNoPdfRendererTemplate': '{name}: 이 빌드에는 PDF 렌더러가 없습니다.',
    'imCouldNotImportTemplate': '{name}: 임포트하지 못했습니다.',
    'imPsdNoLayersTemplate': '{name}: 펼칠 레이어가 없습니다 — 합치기로 가져오세요.',
    'imKeepExplain': '프로젝트 파일이 압축해서 품습니다. 원본은 그대로 둡니다.',
    'imReferenceExplain': '파일은 그 자리에 두고 프로젝트가 가리킵니다.',
    'mpFileMissing': '파일이 없습니다 — 다시 연결하세요',
    'mpInUseOnTimeline': '타임라인에서 쓰는 중',
    'mpNameEmpty': '미디어 이름을 비울 수 없습니다.',
    'exCameraTemplate': '카메라 {size}',
    'toolBrush': '브러시',
    'toolEraser': '지우개',
    'toolEyedropper': '스포이트',
    'toolFill': '채우기',
    'toolText': '텍스트',
    'toolShape': '도형',
    'textToolSelectedText': '선택된 텍스트',
    'textToolDeleteText': '텍스트 삭제',
    'textToolLetters': '글자',
    'textToolBox': '상자',
    'textToolFont': '글꼴',
    'textToolSize': '크기',
    'textToolTracking': '자간',
    'textToolBold': '굵게',
    'textToolItalic': '기울임',
    'textToolUnderline': '밑줄',
    'textToolStrikethrough': '취소선',
    'textToolColor': '색',
    'textToolOutline': '윤곽선',
    'textToolOutlineWidth': '윤곽선 굵기',
    'textToolAlign': '정렬',
    'textToolAlignLeft': '왼쪽',
    'textToolAlignCenter': '가운데',
    'textToolAlignRight': '오른쪽',
    'textToolCentreAcross': '가로 가운데',
    'textToolCentreDown': '세로 가운데',
    'textToolBoxWidth': '상자 폭',
    'textToolWidthAuto': '자동',
    'textToolWidthFixed': '고정',
    'textToolLineHeight': '줄 간격',
    'textToolLetterWidth': '장평',
    'textToolSkew': '기울임',
    'textToolBackground': '배경',
    'textToolIntoDrawing': '래스터라이즈',
    'textToolWriting': '쓰기 방향',
    'textToolWritingLines': '가로',
    'textToolWritingColumns': '세로',
    'textToolAlignTop': '위',
    'textToolAlignBottom': '아래',
    'textToolFontImport': '글꼴 파일 가져오기',
    'textToolFontDelete': '글꼴 삭제',
    'textToolFontsOfProject': '이 프로젝트의 글꼴',
    'textToolFontsOfDevice': '이 기기의 글꼴',
    'textToolFontTakeOut': '프로젝트에서 빼기',
    'textToolFontStaysOnThisDevice':
        '이 글꼴은 편집하는 문서에 넣도록 허용되지 않아서 다른 기기에서 열면 바뀝니다.',
    'textToolFontNotOnThisDevice': '이 기기에 없는 글꼴이라 다른 글꼴로 보입니다.',
    'textToolFontUnreadable': '글꼴 파일로 읽을 수 없습니다.',
    'textToolFontIsTheApps': '앱에 이미 들어 있는 글꼴입니다.',
    'textToolFontNotKept': '글꼴을 저장하지 못했습니다.',
    'toolSelect': '선택',
    'toolTransform': '변형',
    'toolShapeFill': '도형 채우기',
    'toolCutNothingHeld': '아직 든 것이 없습니다',
    'toolCutHoldingTemplate': '{size} px 를 들고 있습니다',
    'toolLibraryEmpty': '표시할 것이 없습니다',
    'toolCutPasteAtOrigin': '원래 위치에 붙여넣기',
    'toolCutFlipHorizontal': '좌우 반전',
    'toolCutFlipVertical': '상하 반전',
    'toolCutRegisterTip': '팁으로 등록',
    'toolCutDeletesSource': '원본 삭제',
    'toolReadSource': '참조',
    'toolReadsEveryVisibleLayer': '보이는 레이어 전부',
    'brushSettingsTitle': '브러시 설정',
    'toolShapeRect': '사각형',
    'toolShapeEllipse': '타원',
    'toolShapeLasso': '올가미',
    'toolShapePolygon': '다각형',
    'toolShapeLine': '직선',
    'toolShapeSelectTemplate': '{shape} 선택',
    'toolShapeCutTemplate': '{shape} 잘라내기',
    'toolShapeFillTemplate': '{shape} 채우기',
    'toolShapeDrawTemplate': '{shape} 그리기',
    'shapeToolDraws': '그리기',
    'shapeToolStroke': '선',
    'shapeToolFill': '채움',
    'shapeToolType': '타입',
    'shapeToolTypePlain': '일반',
    'shapeToolCorners': '모서리',
    'shapeToolCornersSharp': '각지게',
    'shapeToolCornersRound': '둥글게',
    'shapeToolRatioLock': '비율 고정',
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
    'brMixing': '혼색',
    'brMixingMethod': '방식',
    'brMixingMix': '섞기',
    'brMixingBlur': '흐리기',
    'brPaintAmount': '물감량',
    'brPaintDensity': '물감 농도',
    'brColorStretch': '색 늘이기',
    'brHardness': '경도',
    'stepUp': '한 걸음 올리기',
    'stepDown': '한 걸음 내리기',
    'brEdgeNone': '없음',
    'brSpacing': '간격',
    'brAngle': '각도',
    'brRoundness': '원형률',
    'brScale': '배율',
    'brScatter': '살포',
    'brScatterCount': '개수',
    'brScatterBothAxes': '양축',
    'brTipRotation': '방향',
    'brRotationFixed': '없음',
    'brRotationDirection': '선 방향',
    'brRotationPenTilt': '펜 방향',
    'brRotationPenTwist': '펜 축 회전',
    'brTipOrder': '반복 방법',
    'brTipOrderRepeat': '반복',
    'brTipOrderPingPong': '왕복',
    'brTipOrderHoldLast': '반복 안 함',
    'brTipOrderRandom': '랜덤',
    'brTipOrderOneLap': '한 바퀴만',
    'brTipOrderShuffledLap': '랜덤 한 바퀴',
    'brTipOrderLean': '펜 기울기',
    'brTipsPerTurn': '차례당 팁 수',
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
    'brDeleteTipBodyTemplate': '「{name}」 끝을 라이브러리에서 삭제합니다.',
    'brStabilizer': '손떨림 보정',
    'brStabilizerOn': '손떨림 보정 적용',
    'brStabilizerBySpeed': '속도에 따라',
    'brBySpeedSlow': '느릴 때',
    'brBySpeedFast': '빠를 때',
    'brPostCorrection': '후보정',
    'brPostBySpeed': '속도로 조정',
    'brPostByViewScale': '배율로 조정',
    'brPostBezier': '베지어 곡선',
    'brSharpenCorners': '각 날카롭게',
    'brGroupInk': '잉크',
    'brGroupTip': '브러시 끝',
    'brGroupMixing': '혼색',
    'brGroupScattering': '살포',
    'brGroupTexture': '질감',
    'brGroupCorrection': '보정',
    'brDetailTitle': '브러시 상세',
    'brShowInPanel': '패널에 보이기',
    'brHideFromPanel': '패널에서 숨기기',
    'shortcutAction.frame-auto-create': '프레임 자동 생성',
    'brBlend': '합성',
    'brBlendMode': '브러시 합성 모드',
    'brDualBlend': '듀얼 합성',
    'brTextureMode': '텍스처 합성',
    'brTextureModeHeight': '높이',
    'brEditGroup': '그룹 편집',
    'brFolderIcon': '폴더 아이콘',
    'brFolderName': '폴더 이름',
    'brFeather': '페더',
    'brTolerance': '허용치',
    'brGapClose': '틈 메우기',
    'brGrowShrink': '확장 / 축소',
    'brAntiAlias': '안티앨리어스',
    'brFillBeyondCanvas': '캔버스 밖도 채우기',
    'brOpenRegionsRefuse': '열린 영역은 채워지지 않습니다',
    'brName': '이름',
    'brDisplay': '표시',
    'brTipIcon': '팁 아이콘',
    'brStrokePreview': '스트로크 미리보기',
    'brBrushOptions': '브러시 옵션',
    'brNewGroup': '새 그룹',
    'brNewGroupName': '새 그룹',
    'brNewPresetName': '프리셋 {n}',
    'builtinBrush.builtin-basic-group': '기본',
    'builtinBrush.builtin-pencil-group': '연필',
    'builtinBrush.builtin-ink-group': '펜',
    'builtinBrush.builtin-dry-media-group': '건식 재료',
    'builtinBrush.builtin-watercolor-group': '수채',
    'builtinBrush.builtin-paint-group': '유화',
    'builtinBrush.builtin-airbrush-group': '에어브러시',
    'builtinBrush.builtin-blend-group': '색 혼합',
    'builtinBrush.builtin-texture-group': '텍스처',
    'builtinBrush.builtin-decoration-group': '데코레이션',
    'builtinBrush.builtin-pencil': 'HB 연필',
    'builtinBrush.builtin-soft-pencil': '2B 연필',
    'builtinBrush.builtin-mechanical-pencil': '샤프',
    'builtinBrush.builtin-hard-pencil': '2H 연필',
    'builtinBrush.builtin-dark-pencil': '4B 연필',
    'builtinBrush.builtin-colored-pencil': '색연필',
    'builtinBrush.builtin-coloring-pencil': '칠하는 색연필',
    // 유저 F-433 (2026-10-21): 「눕혀쓰는연필은 이름 기니 눕힌 연필로」.
    'builtinBrush.builtin-shading-pencil': '눕힌 연필',
    'builtinBrush.builtin-rough-edge': '거친 연필',
    'builtinBrush.builtin-ink-pen': '하드 라운드',
    'builtinBrush.builtin-g-pen': 'G펜',
    'builtinBrush.builtin-maru-pen': '둥근 펜',
    'builtinBrush.builtin-brush-pen': '붓펜',
    'builtinBrush.builtin-calligraphy': '캘리그래피',
    'builtinBrush.builtin-marker': '마커',
    'builtinBrush.builtin-kabura-pen': '카부라 펜',
    'builtinBrush.builtin-technical-pen': '밀리 펜',
    'builtinBrush.builtin-dry-ink': '마른 잉크',
    'builtinBrush.builtin-chalk-preset': '초크',
    'builtinBrush.builtin-charcoal': '목탄',
    'builtinBrush.builtin-pastel': '파스텔',
    'builtinBrush.builtin-crayon': '크레용',
    'builtinBrush.builtin-graphite-stick': '흑연 스틱',
    'builtinBrush.builtin-watercolor': '수채',
    'builtinBrush.builtin-analog-watercolor': '아날로그 수채',
    'builtinBrush.builtin-wet-watercolor': '번지는 수채',
    'builtinBrush.builtin-dense-watercolor': '진한 수채',
    'builtinBrush.builtin-flat-wash': '평칠',
    'builtinBrush.builtin-flat-bristle': '납작붓',
    'builtinBrush.builtin-gouache': '과슈',
    'builtinBrush.builtin-oil-brush': '유화 붓',
    'builtinBrush.builtin-palette-knife': '팔레트 나이프',
    'builtinBrush.builtin-dry-brush': '드라이 브러시',
    'builtinBrush.builtin-airbrush': '에어브러시',
    'builtinBrush.builtin-soft-brush': '소프트 라운드',
    'builtinBrush.builtin-grit-spray': '거친 스프레이',
    'builtinBrush.builtin-blender': '색 혼합',
    'builtinBrush.builtin-water-blend': '물 번짐',
    'builtinBrush.builtin-blending-stump': '찰필',
    'builtinBrush.builtin-blur': '흐리기',
    'builtinBrush.builtin-splatter-preset': '흩뿌리기',
    'builtinBrush.builtin-stipple': '점묘',
    'builtinBrush.builtin-sponge': '스펀지',
    'builtinBrush.builtin-cloud': '구름',
    'builtinBrush.builtin-concrete': '콘크리트',
    'builtinBrush.builtin-grass': '풀',
    'builtinBrush.builtin-sparkle': '반짝이',
    'builtinBrush.builtin-snow': '눈',
    'builtinBrush.builtin-bubble': '거품',
    'builtinBrush.builtin-leaves': '나뭇잎',
    'builtinTip.builtin-chalk': '초크',
    'builtinTip.builtin-splatter': '흩뿌리기',
    'builtinTip.builtin-grain': '입자',
    'builtinTip.builtin-bristle': '붓털',
    'builtinTip.builtin-sponge': '스펀지',
    'builtinTip.builtin-wet-blot': '번짐',
    'builtinTip.builtin-star': '별',
    'builtinTip.builtin-flake': '눈송이',
    'builtinTip.builtin-ring': '고리',
    'builtinTip.builtin-leaf': '잎',
    'builtinTip.builtin-grass-clump': '풀포기',
    'builtinTip.builtin-paper-grain': '종이 결',
    'builtinTip.builtin-canvas-weave': '캔버스 결',
    'builtinTip.builtin-cold-press': '콜드프레스 종이',
    'builtinTip.builtin-pencil-side': '연필심 옆면',
    'builtinTip.builtin-graphite-tooth': '연필 종이결',
    'builtinTip.builtin-color-clumps': '색연필 결',
    'builtinTip.builtin-pencil-face-0-0': '연필심 1-1',
    'builtinTip.builtin-pencil-face-0-1': '연필심 1-2',
    'builtinTip.builtin-pencil-face-0-2': '연필심 1-3',
    'builtinTip.builtin-pencil-face-1-0': '연필심 2-1',
    'builtinTip.builtin-pencil-face-1-1': '연필심 2-2',
    'builtinTip.builtin-pencil-face-1-2': '연필심 2-3',
    'builtinTip.builtin-pencil-face-2-0': '연필심 3-1',
    'builtinTip.builtin-pencil-face-2-1': '연필심 3-2',
    'builtinTip.builtin-pencil-face-2-2': '연필심 3-3',
    'builtinTip.builtin-pencil-face-3-0': '연필심 4-1',
    'builtinTip.builtin-pencil-face-3-1': '연필심 4-2',
    'builtinTip.builtin-pencil-face-3-2': '연필심 4-3',
    'builtinTip.builtin-pencil-face-4-0': '연필심 5-1',
    'builtinTip.builtin-pencil-face-4-1': '연필심 5-2',
    'builtinTip.builtin-pencil-face-4-2': '연필심 5-3',
    'builtinTip.builtin-pencil-face-5-0': '연필심 6-1',
    'builtinTip.builtin-pencil-face-5-1': '연필심 6-2',
    'builtinTip.builtin-pencil-face-5-2': '연필심 6-3',
    'builtinTip.builtin-pencil-crumb-0': '연필 알갱이 1',
    'builtinTip.builtin-pencil-crumb-1': '연필 알갱이 2',
    'builtinTip.builtin-pencil-crumb-2': '연필 알갱이 3',
    'brRenameGroup': '그룹 이름 변경',
    'brDeleteGroup': '그룹 삭제',
    'brDeleteEmptyGroupTemplate': '「{name}」 빈 그룹을 삭제할까요?',
    'brDeleteGroupTemplateOne': '「{name}」 그룹과 안의 브러시 1개를 삭제할까요?',
    'brDeleteGroupTemplate': '「{name}」 그룹과 안의 브러시 {n}개를 삭제할까요?',
    'brRenameSelected': '선택한 브러시 이름 변경',
    'brDeleteSelected': '선택한 브러시 삭제',
    'brSaveAsPreset': '현재 설정을 프리셋으로 저장',
    'brImportBrushes': '브러시 가져오기 (.abr, .sut, .sutg)',
    'brResetLibrary': '브러시 라이브러리 초기화',
    'brExportSelected': '브러시 내보내기',
    'brExportGroup': '브러시 그룹 내보내기',
    'brExportNothing': '내보낼 브러시가 없습니다.',
    'fileExportPlaceUnchosenTemplate': '저장할 곳을 고르지 못했습니다: {error}',
    'settingsExportedTemplate': '「{name}」 내보냈습니다.',
    'settingsExportNotWrittenTemplate': '파일을 쓰지 못했습니다: {error}',
    'settingsExportAll': '설정 전부 내보내기',
    'settingsAllFileName': 'Anicel 설정',
    'settingsRowFrameCount': '프레임 수 입력 방식',
    'settingsRowWorkspaceLayout': '작업공간 배치',
    'imIntoSettings': '설정',
    'imSettingsGoInPlace': '「설정」에 넣는 항목은 지금 것이 사라집니다.',
    'imSettingsUnreadable': '읽을 수 없음',
    'brExportNotWrittenTemplate': '브러시 파일을 쓰지 못했습니다: {error}',
    'brExportedOneTemplate': '브러시 「{name}」 내보냈습니다.',
    'brExportedManyTemplate': '브러시 {count}개를 내보냈습니다.',
    'brExportFallbackName': '브러시',
    'brImportUnreadable': '이 파일은 브러시 파일로 읽을 수 없습니다.',
    'brImportPickFailedTemplate': '파일을 열지 못했습니다: {error}',
    'fontBroughtTemplate': '「{family}」 글꼴을 이 기기에 가져왔습니다.',
    'brImportedOneTemplate': '「{file}」에서 브러시 1개를 가져왔습니다.',
    'brImportedManyTemplate': '「{file}」에서 브러시 {count}개를 가져왔습니다.',
    'brImportWarningsTemplate': '{summary} (경고가 있는 항목 {count}개)',
    'brTipUnreadable': '그 이미지는 브러시 팁으로 읽을 수 없습니다.',
    'brTipNoShape': '그 이미지에는 팁으로 쓸 보이는 모양이 없습니다.',
    'brTipNotSaved': '그 팁을 저장하지 못했습니다.',
    'brExpand': '펼치기',
    'trFlipHorizontal': '좌우 반전',
    'trFlipVertical': '상하 반전',
    'trPosition': '위치',
    'trScale': '배율',
    'trScaleLink': '배율 연동',
    'trRotation': '회전',
    'trAnchorPoint': '기준점',
    'trMeshColumns': '가로 칸',
    'trMeshRows': '세로 칸',
    'trMesh': '메시',
    'trFinish': '마무리',
    'commonReset': '초기화',
    'viewFitToView': '화면에 맞추기',
    'viewResetView': '줌 초기화 (100%)',
    'panelSettings': '설정',
    'viewRotateLeft': '보기 왼쪽 회전',
    'viewRotateRight': '보기 오른쪽 회전',
    'viewFlipHorizontal': '보기 좌우 반전',
    'viewFlipVertical': '보기 상하 반전',
    'viewStraighten': '기울기 초기화 (0°)',
    'viewZoomDrag': '줌 (드래그)',
    'viewAngleDrag': '보기 각도 (드래그)',
    'valueTypeIn': '직접 입력',
    'viewCanvasColor': '캔버스 색',
    'viewPasteboardColor': '페이스트보드 색',
    'pasteboardTitle': '페이스트보드',
    'pasteboardInUse': '사용',
    'pasteboardNotInUse': '사용 안 함',
    'viewBackdropColor': '배경 색',
    'colorUseCurrent': '현재 색 반영',
    'colorNone': '없음',
    'colorPresent': '있음',
    'tlSections': '섹션',
    'tlAllDisplayedLayers': '표시 중인 모든 레이어',
    'tlShowAll': '모두 표시',
    'tlHideAll': '모두 숨기기',
    'tlSoloKind': '종류 솔로',
    'tlSoloColor': '색 솔로',
    'tlSoloClips': '클리핑 솔로',
    'tlSoloFxOnRows': 'FX 켜진 행 솔로',
    'tlSoloSheetOnRows': '시트 켜진 행 솔로',
    'tlApplyAllFx': 'FX 모두 적용',
    'tlBypassAllFx': 'FX 모두 우회',
    'tlAllOnTimesheet': '모두 시트에 올리기',
    'tlAllOffTimesheet': '모두 시트에서 내리기',
    'tlClearMarkFilter': '마크 필터 해제',
    'tlClearAllClips': '클리핑 모두 해제',
    'tlColVisibility': '표시 열',
    'tlColLayerKind': '레이어 종류 열',
    'tlColOnionSkin': '어니언 스킨 열',
    'tlColOpacity': '불투명도 열',
    'tlColBlendMode': '블렌드 모드 열',
    'tlColFx': 'FX 열',
    'tlColMark': '마크 열',
    'tlColClip': '클리핑 열',
    'tlColTimesheet': '타임시트 열',
    'tlShowXSheet': 'X시트로 보기',
    'tlShowTimeline': '타임라인으로 보기',
    'cameraViewOn': '카메라 뷰 (켜짐)',
    'cameraViewOff': '카메라 뷰',
    'tlOpenOnionPanel': '어니언 스킨 패널 열기',
    'tlApplyOnionToDisplayed': '표시 중인 레이어에 어니언 스킨 적용',
    'tlClearOnionOnDisplayed': '표시 중인 레이어의 어니언 스킨 해제',
    'tlOnionOnDisplayedToggle': '표시 중인 레이어의 어니언 스킨 켜기/끄기',
    'tlCollapseAllLayers': '모든 레이어 접기',
    'tlExpandAllLayers': '모든 레이어 펼치기',
    'railLayerBlendMode': '레이어 블렌드 모드',
    'railFolderBlendMode': '폴더 블렌드 모드',
    'railHideLayer': '레이어 숨기기',
    'railShowLayer': '레이어 표시',
    'railBypassLayerFx': '레이어 FX 우회',
    'railApplyLayerFx': '레이어 FX 적용',
    'railBypassMixedLayerFx': '레이어 FX 모두 우회 (일부 꺼짐)',
    'railBypassTrackFx': '트랙 FX 우회',
    'railApplyTrackFx': '트랙 FX 적용',
    'railRemoveFromTimesheet': '시트에서 내리기',
    'railAddToTimesheet': '시트에 올리기',
    'railCollapseLanes': '레인 접기',
    'railExpandLanes': '레인 펼치기',
    'railOnionSkinOn': '어니언 스킨 (켜짐)',
    'railOnionSkin': '어니언 스킨',
    'railLaneGraphOn': '그래프 (켜짐)',
    'railLaneGraph': '그래프',
    'railLanePinOn': '모든 그래프에 고정됨',
    'railLanePin': '모든 그래프에 고정',
    'laneGraphValue': '값',
    'laneGraphSpeed': '속도',
    'laneGraphEnlarge': '크게 보기',
    'laneGraphEnlargeOn': '크게 보기 (켜짐)',
    'laneGraphPen': '펜',
    'laneGraphPenOn': '펜 (켜짐)',
    'laneGraphTransformBox': '변형 상자',
    'laneGraphTransformBoxOn': '변형 상자 (켜짐)',
    'railClipOn': '아래 레이어로 클리핑 (켜짐)',
    'railClip': '아래 레이어로 클리핑',
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
    'tlNoLayers': '레이어 없음',
    'tlLegendLayer': '레이어',
    'tlAllDisplayedOpacity': '표시 중인 레이어 전체 불투명도',
    'tlLinkedWith': '링크 대상',
    'tlLayerReference': '참조',
    'tlReferenceSourceShort': '원본보다 {n}프레임 깁니다',
    'tlSelectedLayers': '선택한 레이어',
    'tlAudioGroup': '오디오',
    'tlSoundVolume': '볼륨',
    'tlNameTagGroup': '이름표',
    'tlReferenceGroup': '참조',
    'tlTransformGroup': '변형',
    'tlLaneScale': '비율',
    'tlLaneRotation': '회전',
    'tlLanePosition': '위치',
    'tlLaneOpacity': '불투명도',
    'tlLaneAnchorPoint': '기준점',
    'tlBypassLaneTemplate': '{name} 우회',
    'tlApplyLaneTemplate': '{name} 적용',
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
    // 🗣️The row KIND's name is the user's (2026-10-02: 「애니메이션 레이어로
    // 이름바꾸자」). ⛔Not 동화 — that word is the in-between PROCESS
    // (`layerProcess.inbetween`), another axis.
    'tlKindAnimation': '애니메이션',
    'tlKindStoryboard': '콘티',
    'tlKindImage': '이미지',
    'tlKindAdjustment': '조정 레이어',
    'tlKindFolder': '폴더',
    'tlKindSe': 'SE',
    'tlKindTransition': '트랜지션',
    'tlKindCamera': '카메라',
    'tlKindSemanticTemplate': '{kind} 레이어',
    'seNameTagShowLineLabel': '대사 표시',
    'seNameTagLineInkLabel': '대사 잉크',
    'seNameTagTrackingLabel': '자간',
    'seNameTagSizeLabel': '크기',
    'seNameTagNameInkLabel': '이름 잉크',
    'seNameTagBoxColorLabel': '박스 색',
    'seNameTagBoldLabel': '굵게',
    'seNameTagItalicLabel': '기울임',
    'seNameTagUnderlineLabel': '밑줄',
    'seNameTagStrikethroughLabel': '취소선',
    'seNameTagPreviewName': '이름',
    'seNameTagPreviewLine': '대사',
    'tlKindInstruction': '디렉션',
    'tlNoriShiro': '여백',
    'shortcutAction.layer-attach-free-above': '위에 프리 어태치 레이어',
    'shortcutAction.layer-attach-free-below': '아래에 프리 어태치 레이어',
    'shortcutAction.layer-attach-synced-above': '위에 싱크 어태치 레이어',
    'shortcutAction.layer-attach-synced-below': '아래에 싱크 어태치 레이어',
    'tlLayerCommands': '레이어 명령',
    'tlFrameCommands': '프레임 명령',
    'tlCut': '컷',
    'tlLayer': '레이어',
    'tlFrame': '프레임',
    'tlKey': '키',
    'shortcutAction.frame-select-row-span': '행 전체 선택',
    'linkWindowUnlink': '링크 해제',
    'linkWindowUnlinkLinkedCut': '겸용컷이라 레이어만 해제할 수 없습니다',
    'tlResetGroup': '리셋 (키는 유지)',
    'tlEffects': '이펙트',
    'tlAddEffectTemplate': '{name} 추가',
    'tlDropIntoFolderTemplate': '{name} 안으로',
    'tlDropOutOfFolder': '폴더 밖으로',
    'tlDropAttachSyncedTemplate': '{name}에 어태치 (싱크)',
    'tlDropAttachFreeTemplate': '{name}에 어태치 (프리)',
    'tlDropDetachAttach': '어태치 해제',
    'shortcutAction.layer-detach': '어태치 해제',
    'tlAttachDropsFxRows': 'fx 가 사라지는 레이어',
    'tlAttachDropsFxTitle': '어태치하면 fx 가 사라집니다',
    'tlMergeChangesTitle': '병합하면 겉보기가 달라질 수 있습니다',
    'tlMergeChangesBody': '병합한 레이어는 그 아래 레이어 위에서 다르게 보일 수 있습니다.',
    'tlMergeChanges': '달라지는 것',
    'tlMergeChangeBlend': '표준이 아닌 합성 모드가 섞여 있습니다 — 병합한 레이어는 표준이 됩니다',
    'tlMergeChangeClip': '고른 레이어와 고르지 않은 레이어가 클리핑으로 이어져 있습니다',
    'tlMergeChangeFolder': '병합한 레이어가 놓일 폴더의 효과가 그 폴더 밖에서 온 레이어에도 걸립니다',
    'tlMergeChangeRiderOver': '어태치 레이어가 다른 그림을 덮게 됩니다',
    'tlMergeChangeRiderUnder': '어태치 레이어가 다른 그림 밑으로 들어갑니다',
    'tlMergeChangeWall': '페이스트보드 밖 부분이 잘립니다',
    'tlAttachDropsFxBody':
        '어태치된 레이어는 자기 fx 를 갖지 않습니다. 계속하면 기존 fx 가 사라집니다. 실행하겠습니까?',
    'tlPush': '밀기(칸 열기)',
    'tlPull': '당기기(칸 닫기)',
    'sbOneStoryboardRowPerCut': '이 컷에는 이미 콘티 레이어가 있습니다. 컷당 하나만 가능합니다.',
    'cnHeadCut': '컷',
    'cnHeadPicture': '화면',
    'cnHeadAction': '내용',
    'cnHeadDialogue': '대사',
    'cnHeadSeconds': '초',
    'cnCoverCuts': '컷',
    'cnCoverArtist': '콘티',
    'sheetPrintEpisode': '화수',
    'sheetPrintTitle': '제목',
    'sheetPrintScene': '씬',
    'sheetPrintCut': '컷',
    'sheetPrintDuration': '타임',
    'sheetPrintName': '원화',
    'sheetPrintPage': '시트',
    'sheetPrintRepeat': '리피트',
    'sheetPrintHold': '홀드',
    'tlSetCommasN': 'N코마로 설정',
    'tlSetCommaTemplate': '{n}코마로 설정',
    'tlProjectAudioRate': '프로젝트 오디오 샘플레이트',
    'tlShowSeRows': 'SE 행 표시',
    'tlShowCameraRows': '카메라 행 표시',
    'shortcutAction.layer-storyboard': '콘티 레이어',
    'setLengthAction': '노출 길이 설정',
    'markEveryField': '간격',
    'frameCountEntryFrames': '프레임',
    'frameCountEntrySecondsPlusFrames': '초+코마',
    'projectFpsTitle': '프로젝트 프레임레이트',
    'projectFpsField': '초당 프레임 수',
    'autoNameStartField': '시작 번호',
  };

  static const _frValues = <String, String>{
    'launchStageEngine': 'Démarrage du moteur',
    'launchStagePlugins': 'Enregistrement des plugins',
    'launchStageApp': "Préparation de l'application",
    'launchStageFirstFrame': 'Affichage du premier écran',
    'launchNoticeTitle': 'À propos de cette version',
    'launchNoticeDontShowAgain': 'Ne plus afficher',
    'usageStatsSend': "Envoyer des statistiques d'utilisation",
    'usageStatsHelp':
        "Activé, l'app envoie de façon anonyme, à son ouverture, toutes les "
        "55 minutes pendant que vous l'utilisez et quand vous la quittez, "
        "qu'elle est utilisée — avec le système et sa version, le modèle de "
        "l'appareil, la version de l'app et la langue de l'app. "
        "Une fois par jour, elle envoie aussi la langue de l'appareil, le "
        "nombre de jours d'utilisation sur les 28 derniers (nouveau, 1–2, "
        '3 ou plus) et '
        "quatre réglages : la taille de l'interface, la couleur d'accent, "
        'la sauvegarde auto et le curseur. '
        "Rien qui vous identifie n'est envoyé : ni dessins ni projets, "
        "ni noms de fichiers, ni noms, ni le nom donné à l'appareil. Le "
        "désactiver efface aussi l'historique gardé sur cet appareil.",
    'usageStatsTitle': "Statistiques d'utilisation",
    'usageStatsAsk':
        "Envoyer des statistiques d'utilisation ? Les activer aide au "
        "développement d'Anicel.",
    'usageStatsChangeLater':
        'Vous pouvez changer cela à tout moment dans Préférences ▸ Système.',
    'usageStatsDontSend': 'Ne pas envoyer',
    'usageStatsDoSend': 'Envoyer',
    'firstRunTitle': 'Premiers réglages',
    'firstRunChangeLater':
        'Vous pouvez les changer à tout moment dans les Préférences.',
    'firstRunStart': 'Commencer',
    'programLanguageLabel': 'Langue du programme',
    'notationLanguageLabel': 'Langue de notation',
    'programLanguageHelp': 'Menus, panneaux et libellés.',
    'notationLanguageHelp': 'Ce qui s\'imprime sur la feuille d\'exposition.',
    'noCutSelected': 'Aucun plan sélectionné',
    'noticeNoFrameHere': 'Aucune image ici',
    'noticeNothingToCut': 'Rien à couper',
    'noticeNoConteLayer': 'Ce plan n\'a pas de calque storyboard',
    'noticeLayerNotDrawable': 'Ce calque n\'accepte pas le dessin',
    'noticeLayerHidden': 'Ce calque est masqué',
    'noticeEditAttachOwner': 'Modifiez le calque parent',
    'commonCancel': 'Annuler',
    'commonApply': 'Appliquer',
    'commonRefresh': 'Actualiser',
    'commonClose': 'Fermer',
    'commonAffectedFiles': 'Fichiers concernés',
    'commonNotice': 'Avis',
    'tlSharedColourEdit': 'Édition couleur',
    'exportNoCuts': 'Ce projet ne contient aucun plan à exporter.',
    'exportQueueEmpty': 'Aucune tâche dans la file',
    'exportPresetsEmpty': 'Aucun préréglage',
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
    'recordMicPermissionDenied':
        'L\'accès au micro est désactivé — autorisez-le pour Anicel dans les Réglages.',
    'recordMicNotAllowed':
        'Le micro n\'est pas autorisé — activez Préférences ▸ Audio ▸ Autoriser le micro.',
    'recordTakeClipped': 'La prise a saturé — le coin rouge marque le bloc.',
    'recordClipMarkerTooltip': 'Prise saturée (niveau trop fort)',
    'tlTransitionCrossingWarning': 'Dépasse la limite du plan — non appliqué',
    'tlTransitionCutOl': 'O.L de plan',
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
    'audioMicrophoneAllowedLabel': 'Autoriser le micro',
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
    'audioMute': 'Muet',
    'audioSolo': 'Solo',
    'fpsAudioTitleTemplate': '{from} → {to} : que faire du son ?',
    'fpsAudioBody':
        'Ces deux cadences diffèrent de 0,1 % en vitesse réelle, et le son existe en secondes réelles — il ne peut pas rester à la fois exact à l\'image et exact au temps.\n\n• Garder le timing audio : les sons gardent leurs secondes réelles ; leurs positions d\'image dérivent de 0,1 % (environ une image toutes les 42 secondes).\n\n• Tirer l\'audio de 0,1 % : les sons sont rééchantillonnés au rapport de pulldown exact (variation de hauteur inaudible — la conformation télécinéma standard) et chaque son garde sa plage d\'images exacte.',
    'fpsAudioKeep': 'Garder le timing audio',
    'fpsAudioPull': 'Tirer l\'audio de 0,1 %',
    'feedbackTextOnly': 'Texte seul',
    'feedbackWithFiles': 'Avec captures / vidéos (connexion Google)',
    'selectionClosePolygon': 'Fermer la forme',
    'selectionInvert': 'Inverser la sélection au-delà du canevas',
    'selectionInvertInCanvas': 'Inverser la sélection dans le canevas',
    'toolSelectionMode': 'Mode',
    'commonSave': 'Enregistrer',
    'commonDelete': 'Supprimer',
    'commonAdd': 'Ajouter',
    'commonRename': 'Renommer',
    'commonLink': 'Lier',
    'commonPreview': 'Aperçu',
    'windowTitleTemplate': '{action} ({target})',
    'editNameAction': 'Modifier le nom',
    'editNoteAction': 'Modifier la note',
    'renameLayerEmpty': 'Le nom du calque ne peut pas être vide.',
    'renameCutField': 'Nom du plan',
    'renameCutEmpty': 'Le nom du plan ne peut pas être vide.',
    'renameGuideTitle': 'Renommer le repère',
    'renameGuideField': 'Nom du repère',
    'renameGuideEmpty': 'Le nom du repère ne peut pas être vide.',
    'deleteLayerTitle': 'Supprimer le calque',
    'deleteLayersMessage': 'Supprimer les calques ci-dessous ?',
    'deleteLayersHeading': 'Calques à supprimer',
    'deleteEffectsHeading': 'Effets à supprimer',
    'frameNameConflictTitle': "Ce nom d'image existe déjà",
    'frameNameConflictBody':
        'Chaque image listée prend un nom déjà utilisé par une autre image de '
        'son calque. Les lier aux images qui portent ces noms ? Le même nom '
        'partagera alors le même dessin, et le dessin de chaque image listée '
        'sera supprimé.',
    'linkedPasteConflictBody':
        'Chaque image listée utilise déjà un nom porté par les images '
        'collées. Lier les blocs collés à ces images ? Le même nom '
        'partagera alors le même dessin : les blocs collés montreront '
        'les images listées, et les dessins copiés ne seront pas '
        'apportés.',
    'frameNameConflictListHeading': 'Images à lier',
    'seInstanceNewTitle': 'Nouveau SE',
    'seInstanceEditTitle': 'Modifier le SE',
    'seNameLabel': 'Nom (locuteur — vide masque le cadre)',
    'seTypeLabel': 'Type',
    'seDialogueLabel': 'Dialogue',
    'seDialogueOffsetLabel': 'Décalage du dialogue',
    'seKomaPerGlyphLabel': 'Images par caractère',
    'seLinkedAudioLabel': 'Audio lié',
    'seLinkedAudioNone': 'Aucun',
    'seUnlinkAudio': 'Dissocier',
    'keySideIncoming': 'Entrée',
    'keySideOutgoing': 'Sortie',
    'keySideKind.linear': 'Linéaire',
    'keySideKind.ease': 'Lissage',
    'keySideKind.fast': 'Vite',
    'keySideKind.auto': 'Fluide',
    'keySideKind.hold': 'Maintien',
    'keyEaseInfluence': 'Influence',
    'keyPath': 'Trajectoire',
    'keyPathKind.linear': 'Linéaire',
    'keyPathKind.bezier': 'Bézier',
    'keyPathKind.continuousBezier': 'Bézier continue',
    'keyPathKind.autoBezier': 'Bézier auto',
    'keyRoving': 'Itinérance',
    'keySideIncomingHelp':
        'Comment la valeur arrive à la clé. Linéaire : vitesse constante · Lissage : en ralentissant · Vite : en accélérant · Fluide : à la vitesse que donnent les clés voisines. Influence : quelle part du trajet prend le changement.',
    'keySideOutgoingHelp':
        "Comment la valeur quitte la clé. Linéaire : vitesse constante · Lissage : en démarrant doucement · Vite : en partant d'un coup · Fluide : à la vitesse que donnent les clés voisines · Maintien : la valeur reste jusqu'à la clé suivante. Influence : quelle part du trajet prend le changement.",
    'keyPathHelp':
        "La forme du chemin d'une position à travers la clé. Linéaire : un angle à la clé · Bézier : une poignée de chaque côté, chacune dans sa direction · Bézier continue : les deux poignées alignées · Bézier auto : une courbe douce, tracée selon les clés voisines.",
    'keyRovingHelp':
        "La clé garde sa place sur la trajectoire et cède son temps : entre les clés voisines qui gardent le leur, elle se place à l'image où la vitesse devient régulière (Rove Across Time d'After Effects). La première et la dernière clé ne bougent jamais.",
    'cameraPath': 'Trajectoire de la caméra',
    'cameraPathOff': 'Désactivé',
    'cameraPathSpace': 'Espace',
    'cameraPathSpaceTime': 'Espace + temps',
    'cameraPathAllKeys': 'Toutes les clés',
    'cameraPathAroundPlayhead': 'Autour de la tête',
    'cameraPathTickEvery': 'Points tous les',
    'cameraPathAround': 'De chaque côté',
    'convertLinkedCutTitle': 'Convertir en plan lié',
    'convertLinkedCutBodyTemplate':
        'Lier « {cut} » (origine) à un autre plan. Les calques de MÊME NOM '
        'deviennent un seul dessin partagé.',
    'convertLinkedCutTargetLabel': 'Lier au plan',
    'convertLinkedCutLinksHeading': 'Calques liés',
    'convertLinkedCutReplacedTemplate':
        'Les dessins de même nom dans « {cut} » seront remplacés par '
        "ceux de l'origine (원본 승리).",
    'convertLinkedCutReplacedHeading': 'Dessins remplacés',
    'convertLinkedCutJoiningTemplate':
        "{count} dessin(s) rejoignent l'ensemble partagé.",
    'convertLinkedCutTargetGainsHeadingTemplate': 'Ajoutés à « {cut} »',
    'convertLinkedCutOriginGainsHeading': 'Ajoutés à ce plan',
    'convertLinkedCutNothing':
        'Rien à lier — les plans sont déjà entièrement liés ou ne partagent '
        'aucun calque de dessin.',
    'convertLinkedCutUndoNote':
        'Annuler restaure tous les plans touchés par la conversion.',
    'convertLinkedCutResizeFirst':
        'Ces plans ont des tailles de canevas différentes. Les plans liés '
        'partagent une seule image, donc la taille du plan d\'origine '
        'l\'emporte — il est conseillé d\'harmoniser les tailles d\'abord.',
    'guideKindSymmetry': 'Symétrie',
    'guideKindPerspective': 'Perspective',
    'guideDelete': 'Supprimer le repère',
    'guideShow': 'Afficher sur le canevas',
    'guideActsOn': 'Agit sur les traits',
    'guideActsOff': 'N\'agit pas',
    'guideLibraryEmpty': 'Aucun repère dans ce plan',
    'noGuideSelected': 'Aucun repère sélectionné',
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
    'guideAddVanishingPoint': 'Nouveau point de fuite',
    'guideDeleteVanishingPoint': 'Supprimer le point de fuite',
    'guideParallel': 'Parallèle',
    'guideParallelAngle': 'Angle',
    'guideLineDensity': 'Densité des lignes',
    'guideRasterize': 'Pixelliser',
    'closeProjectTitle': 'Fermer le projet ?',
    'shortcutAction.file-new': 'Nouveau projet',
    'untitledProjectTab': 'Sans titre {n}',
    'fileOpenInAnotherTab': 'Ce fichier est déjà ouvert dans un autre onglet.',
    'openNewerFormat':
        'Ce projet a été enregistré par une version plus récente d’Anicel et ne peut pas être ouvert.',
    'openOlderFormatTemplate':
        'Ce projet est au format {saved} et ne peut pas être ouvert (cet Anicel ouvre à partir du format {oldest}).',
    'closeProjectBody':
        'Vos modifications ne sont pas enregistrées. Fermer quand même ?',
    'closeProjectVanishedBody':
        'Le fichier de ce projet a disparu. Fermer maintenant emporte les '
        "dessins qui n'existent que dedans. « Enregistrer sous » écrit dans "
        'un nouveau fichier ce qui est encore ouvert.',
    'commonSaveAs': 'Enregistrer sous',
    'saveAsTitle': 'Enregistrer sous',
    'saveProgressRunning': 'Enregistrement…',
    'saveProgressDone': 'Enregistré',
    'savePrepareRunning': 'Préparation…',
    'savePrepareDone': 'Prêt',
    'saveStepKeepingLeftBehind': 'Mise de côté des médias retirés…',
    'saveStepCels': 'Écriture des cellulos…',
    'saveStepChecking': 'Vérification des fichiers à intégrer…',
    'saveStepMedia': 'Écriture des médias…',
    'saveStepConforms': 'Écriture du son converti pour la lecture…',
    'saveStepFonts': 'Écriture des polices…',
    'saveStepCompacting': 'Comblement des vides du fichier…',
    'saveStepHandingBack': 'Remise du fichier à son document…',
    'resizeProgressRunning': 'Redimensionnement…',
    'resizeProgressDone': 'Redimensionné',
    'bakeProgressRunning': 'Pixellisation…',
    'bakeProgressDone': 'Pixellisé',
    'rasterizeLeftReferences': 'Certains calques restent des références.',
    'referenceWait.attached':
        'Un calque attaché se place selon la Transformation de sa base. Une '
        'Référence qui bouge ne peut donc pas devenir ses propres clés. '
        'Détachez-le pour le pixelliser.',
    'referenceWait.laidAsFitted':
        'Ce fichier a été posé à une taille ajustée par une version '
        'antérieure. Une Référence qui bouge ne peut donc pas devenir des '
        'clés. Replacez le fichier pour le pixelliser.',
    'referenceWait.sheared':
        'Une rotation qui n’est pas un multiple de 90° sous une Échelle '
        'étirée sur un seul axe donne une forme qu’aucune Transformation ne '
        'dessine. Égalisez l’Échelle ou tournez par 90° pour pixelliser.',
    'referenceWait.othersKeepKeys':
        'Un autre calque qui partage cet interrupteur de Transformation garde '
        'ses propres clés tant qu’il est éteint, et l’allumer les montrerait. '
        'Allumez d’abord la Transformation pour pixelliser.',
    'referenceWait.usesApart':
        'Les calques liés montrent l’image de ce cellulo à des endroits '
        'différents, et un cellulo la garde à un seul. Alignez leur '
        'Référence pour pixelliser.',
    'pasteProgressRunning': 'Collage…',
    'pasteProgressDone': 'Collé',
    'unsavedAutosaveTitle': 'Enregistrez votre projet',
    'unsavedAutosaveBody':
        "Ce projet n'a jamais été enregistré : la sauvegarde automatique "
        "n'a nulle part où écrire. Choisissez un fichier et elle le "
        'protégera ensuite.',
    'commonNotNow': 'Plus tard',
    'topStripProject': 'Projet',
    'topStripSettings': 'Paramètres',
    'menuPlay': 'Lire',
    'menuPause': 'Pause',
    'shortcutAction.file-open': 'Ouvrir un fichier',
    'shortcutAction.file-open-folder': 'Ouvrir un dossier',
    'shortcutAction.file-export': 'Exporter',
    'menuAction.edit-undo': 'Annuler',
    'menuAction.edit-redo': 'Rétablir',
    'menuAction.edit-copy-frame': "Copier l'image",
    'menuAction.edit-paste-linked-frame': "Coller l'image liée",
    'menuAction.edit-new-drawing': 'Nouveau dessin sur cette image',
    'menuAction.edit-delete-cell': 'Supprimer la case',
    'menuAction.edit-cut-exposure': "Couper l'exposition",
    'menuAction.edit-toggle-mark': 'Basculer le repère',
    'shortcutAction.edit-keyboard-shortcuts': 'Raccourcis clavier',
    'shortcutAction.edit-preferences': 'Préférences',
    'shortcutAction.work-settings': 'Réglages de l’œuvre',
    'menuAction.file-save-as': 'Projet (.anicel)',
    'menuAction.project-settings': 'Réglages du projet',
    'shortcutAction.cut-create-linked': 'Créer un plan lié',
    'shortcutAction.cut-convert-linked': 'Convertir en plan lié',
    'shortcutAction.cut-canvas-size': 'Taille du canevas',
    'menuAction.cut-delete': 'Supprimer le plan',
    'menuAction.layer-add': 'Nouveau calque',
    'menuAction.layer-link-duplicate': 'Dupliquer en liant',
    'menuAction.layer-unlink': 'Délier le calque',
    'menuAction.layer-group-into-folder': 'Grouper dans un dossier',
    'menuAction.layer-rename': 'Renommer le calque',
    'shortcutAction.layer-rasterize': 'Pixelliser le calque',
    'menuAction.layer-se-name-tag': 'Étiquette SE',
    'menuAction.layer-copy': 'Copier le calque',
    'menuAction.layer-paste': 'Coller le calque',
    'menuAction.layer-delete': 'Supprimer le calque',
    'menuAction.playback-stop': 'Arrêter',
    'menuAction.playback-play-all': 'Lire tous les plans',
    'menuAction.window-panels': 'Panneaux',
    'shortcutAction.window-tool-rail-right': "Barre d'outils à droite",
    'shortcutAction.window-region-on-top': 'Zone de timeline en haut',
    'shortcutAction.window-brush-values-on-strip':
        'Valeurs du pinceau dans le bandeau du haut',
    'shortcutAction.window-full-screen': 'Plein écran',
    'shortcutAction.window-region-fold': 'Replier / déplier la zone de timeline',
    'shortcutAction.window-reset-layout': "Réinitialiser l'espace de travail",
    'menuAction.edit-debug': 'Débogage',
    'shortcutAction.edit-input-inspector': "Inspecteur d'entrée",
    'shortcutAction.edit-frame-timing-overlay':
        'Superposition du minutage des images',
    'shortcutAction.edit-frame-stats': 'Statistiques des images',
    'shortcutAction.edit-show-repaints': 'Afficher les redessins',
    'menuAction.edit-knee-at-one': "Tampon à la résolution de l'écran",
    'menuAction.edit-show-unpainted-tiles': 'Afficher les tuiles non peintes',
    'shortcutAction.help-about': 'À propos de Anicel',
    'shortcutAction.help-send-feedback': 'Envoyer un avis',
    'fileOpenTitle': 'Ouvrir un projet',
    'fileStorageOffNotice':
        "L'accès au stockage est désactivé — les projets hors du dossier de "
        "l'application exigent l'autorisation Tous les fichiers.",
    'fileOpenSettings': 'Ouvrir les réglages',
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
    'folderPickDriveNoticeAndroid':
        'Google Drive ne peut pas fournir de dossier. Utilisez un dossier de '
        'cet appareil — une app de synchronisation (Autosync …) peut y garder '
        'un dossier Drive.',
    'recentProjectsTitle': 'Projets récents',
    'recentReconnect': 'Reconnecter',
    'sortAscending': 'Croissant',
    'canvasSizeTitle': 'Taille du canevas',
    'cameraSizeTitle': 'Taille de la caméra',
    'canvasWidthLabel': 'Largeur (px)',
    'canvasHeightLabel': 'Hauteur (px)',
    'canvasSizePresets': 'Préréglages',
    'canvasAdjustOnCanvas': 'Ajuster sur la toile',
    'cameraRatioFree': 'Libre',
    'cameraRatioCurrent': 'Actuel',
    'commonResize': 'Redimensionner',
    'inputPressureCurve': 'Réponse à la pression',
    'inputCanvasHeading': 'Canevas',
    'inputRightClick': 'Clic droit / bouton latéral du stylet',
    'inputWheelClick': 'Clic molette / bouton supérieur du stylet',
    'inputPenTail': 'Talon du stylet (retourner le stylet)',
    'inputCanvasTouchHeading': 'Toucher sur le canevas',
    'inputIgnoreTouch': 'Ignorer tout le tactile',
    'inputDragOneFinger': 'Glissement à 1 doigt',
    'inputDragTwoFingers': 'Glissement à 2 doigts',
    'inputDragThreeFingers': 'Glissement à 3 doigts',
    'inputExtraFinger': 'Modificateur au doigt supplémentaire',
    'inputExtraFingerHelp':
        'Un doigt ajouté PENDANT un geste le contraint — zoom, rotation et '
        'taille par crans, avance image par image fine.',
    'inputStrokeFinger': 'Modificateur de trait au doigt',
    'inputStrokeFingerHelp':
        'Un doigt posé sur l’écran pendant le tracé bloque le trait sur le '
        '45° le plus proche — comme Maj.',
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
    'inputRotationSnap': 'Cran de rotation',
    'inputZoomSnaps': 'Crans de zoom (%)',
    'inputZoomCeiling': 'Verrou de zoom max (%)',
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
    'memoryItemLayerImages': 'Images de calque',
    'memoryItemFramePictures': 'Images composées',
    'memoryItemBrushTips': 'Pointes de brosse',
    'memoryItemPanelRasters': 'Rasters de panneau',
    'memoryItemViewerPages': 'Pages de la visionneuse',
    'memoryItemImageCache': "Cache d'images",
    'memoryItemStoryboardThumbnails': 'Vignettes du storyboard',
    'memoryItemSheetImages': 'Images sur feuille',
    'memoryItemTextImages': 'Images de texte',
    'memoryItemStrokePreviews': 'Aperçus du tracé',
    'memoryItemTimelineTiles': 'Images des tuiles de la timeline',
    'memoryItemMoviePictures': 'Vidéos de référence',
    'memoryItemTileImages': 'Images des tuiles du canevas',
    'memoryItemEnginePool': 'Réserve de tuiles du moteur de dessin',
    'memoryItemEngineScratch': 'Tampons de travail du moteur de dessin',
    'memoryOutsideAllowanceTemplate':
        "Hors de l'allocation, faute de plafond possible : {items}.",
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
    'saveFailedTitle': 'Enregistrement impossible',
    'saveFailedFileInUse':
        'Un autre programme utilise ce fichier (synchronisation, antivirus '
        "ou app qui l'a ouvert) : il n'a pas pu être remplacé.",
    'saveFailedReadOnly':
        "Ce fichier ou son dossier est en lecture seule : impossible d'y "
        'écrire.',
    'saveFailedDiskFull':
        "Il n'y a pas assez d'espace là où ce fichier est enregistré.",
    'saveFailedLocationGone':
        "L'emplacement de ce fichier est inaccessible : le lecteur a été "
        'retiré, le réseau coupé ou le dossier supprimé.',
    'saveFailedReplaceRefused':
        "Cet emplacement (un service cloud ou l'app Fichiers) a refusé de "
        'remplacer le fichier.',
    'saveFailedUnknown':
        "Une erreur s'est produite pendant l'écriture du fichier.",
    'saveFailedCopyKept':
        "Votre travail est conservé dans une copie d'échec à l'intérieur de "
        "l'app. Elle disparaît à la fermeture du programme — pour la garder, "
        "utilisez « Sauvegarder la copie d'échec… » et choisissez où.",
    'saveFailedNoCopy':
        "La copie d'échec n'a pas pu être écrite non plus — utilisez "
        '« Enregistrer sous » pour enregistrer ailleurs.',
    'saveFailedRetry':
        'Une fois la cause levée, enregistrez à nouveau : cela ira dans le '
        "fichier d'origine.",
    'saveFailedDetailsHeading': 'Détails',
    'saveFailedCopyLineTemplate': "Copie d'échec : {path}",
    'saveFailedErrorLineTemplate': 'Erreur : {error}',
    'shortcutAction.file-back-up-failed-copy': "Sauvegarder la copie d'échec",
    'failedCopyPickTitle': "Quelle copie d'échec ?",
    'failedCopyVanishOnClose':
        "Les copies d'échec disparaissent à la fermeture du programme.",
    'failedCopyBackingUp': 'Sauvegarde…',
    'failedCopyBackedUp': 'Sauvegardé',
    'closeProjectFailedCopyBody':
        "Le travail que ce projet n'a pas pu enregistrer n'existe que dans "
        "sa copie d'échec à l'intérieur de l'app, et elle disparaît à la "
        'fermeture du programme. Pour le garder, utilisez « Enregistrer '
        "sous » ou « Sauvegarder la copie d'échec… » dans le menu Fichier.",
    'projectFileVanished':
        "Le fichier de ce projet n'est plus là — supprimé ou déplacé. "
        "Restaurez-le maintenant s'il est encore dans une corbeille : les "
        'dessins déjà enregistrés ne vivent que dans ce fichier.',
    'accent1Help': 'Sélection, tête de lecture, bascules actives.',
    'sheetFormatTitle': 'Format de la feuille',
    'sheetFieldTitle': 'Titre',
    'sheetFieldEpisode': 'Épisode',
    'sheetFieldScene': 'Scène',
    'sheetFieldCut': 'Plan',
    'sheetFieldTime': 'Durée',
    'sheetFieldName': 'Animateur',
    'sheetFieldSheet': 'Feuille',
    'workSettingsTitle': 'Réglages de l’œuvre',
    'workSettingsStaff': 'Équipe',
    'workLogo': 'Logo du studio',
    'workCover': 'Image de couverture',
    'staffWorker': 'Artiste',
    'sheetVisibleBoxes': 'Cases visibles',
    'sheetStretchLineAction': "Trait d'extension · ACTION",
    'sheetStretchLineCell': "Trait d'extension · CELL",
    'sheetStretchLineHelp':
        'Tracer le trait à partir du (N+1)e comma des maintiens et des × de N+',
    'sheetStretchLineOn': 'Oui',
    'sheetStretchLineOff': 'Non',
    'sheetSeEmptyFill': 'Plages sans dialogue',
    'sheetLength': 'Longueur de feuille',
    'sheetThreeSeconds': '3 s',
    'sheetSixSeconds': '6 s',
    'sheetFillOn': 'Grisées',
    'sheetFillOff': 'Vides',
    'sheetBrushAllow': 'Autoriser le pinceau',
    'conteCoverPage': 'Couverture',
    'conteBlankPage': 'Page blanche',
    'conteFormatTitle': 'Format de la feuille de conte',
    'conteFrontIn': 'Incluse',
    'conteFrontOut': 'Retirée',
    'conteForm': 'Modèle',
    'conteFormAnalog': 'Analogique',
    'conteFormDigital': 'Numérique',
    'conteOutline': 'Cadre noir des images',
    'conteOutlineOn': 'Oui',
    'conteOutlineOff': 'Non',
    'envelopeFormatTitle': 'Format de l\'enveloppe',
    'envelopeForm': 'Modèle',
    'sheetModeNotation': 'Feuille de notation (répétition / maintien)',
    'sheetModeData': "Feuille de données (telle qu'exportée)",
    'instructionsTitle': 'Indications',
    'instructionEditTooltip': "Modifier l'indication",
    'instructionDeleteTooltip': "Supprimer l'indication",
    'instructionAddButton': 'Nouvelle indication',
    'instructionDefTitle': 'Indication',
    'instructionDefNameLabel': 'Nom (FI, PAN, …)',
    'instructionEventEditTitle': "Modifier l'indication",
    'instructionEventAddTitle': 'Nouvelle indication',
    'instructionMarkLabel': 'Indication (repère)',
    'instructionMarkNone': '(Aucune)',
    'instructionNameLabel': "Nom (vide = nom de l'indication)",
    'instructionStartLabel': 'Nom de début (A)',
    'instructionEndLabel': 'Nom de fin (B)',
    'instructionEditSetButton': 'Modifier les indications',
    'instructionEditorIcon': 'Icône',
    'instructionEditorColor': 'Couleur',
    'instructionEditorMark': 'Repère',
    'systemStatusHelp':
        'Quelle implémentation chaque sous-système exécute en ce moment. Les chemins de repli gardent l\'application fonctionnelle mais tournent en général plus lentement — les noms sont cherchables si vous voulez les détails.',
    'shortcutShelf.canvas': 'Canevas',
    'shortcutShelf.tools': 'Outils',
    'shortcutShelf.toolTiles': 'Sous-outils',
    'shortcutShelf.blendModes': 'Modes de fusion',
    'shortcutShelf.selection': 'Sélection',
    'shortcutShelf.edit': 'Édition',
    'shortcutShelf.view': 'Affichage',
    'shortcutShelf.timeline': 'Timeline · Conte',
    'shortcutShelf.moves': 'Navigation',
    'shortcutShelf.playback': 'Lecture',
    'shortcutShelf.pills': 'Pilules',
    'shortcutShelf.cutPill': 'Pilule Plan',
    'shortcutShelf.layerPill': 'Pilule Calque',
    'shortcutShelf.framePill': 'Pilule Image',
    'shortcutShelf.fxPill': 'Pilule FX',
    'shortcutShelf.sharedPill': 'Pilule commune',
    'shortcutShelf.colourEdit': 'Édition couleur',
    'shortcutShelf.layerHeader': 'En-tête des calques',
    'shortcutShelf.timelineBar': 'Barre de la timeline',
    'shortcutShelf.toolLibrary': "Bibliothèque d'outils",
    'shortcutShelf.brushLibrary': 'Bibliothèque de pinceaux',
    'shortcutShelf.brushToolBrushes': 'Pinceaux de l’outil pinceau',
    'shortcutShelf.eraserToolBrushes': 'Pinceaux de l’outil gomme',
    'shortcutShelf.guides': 'Guides',
    'shortcutShelf.texts': 'Textes',
    'shortcutShelf.topStrip': 'Bandeau du haut',
    'shortcutShelf.file': 'Fichier',
    'shortcutShelf.settings': 'Réglages',
    'shortcutShelf.panels': 'Panneaux',
    'shortcutShelf.debug': 'Débogage',
    'shortcutShelf.inAPanel': 'Dans un panneau',
    'shortcutShelf.media': 'Médias',
    'shortcutShelf.timesheet': 'Feuille de temps',
    'shortcutShelf.conteSheet': 'Feuille de conte',
    'shortcutShelf.envelope': 'Enveloppe de plan',
    'shortcutShelf.palette': 'Palette',
    'shortcutPreset.clipStudio': 'Base Clip Studio',
    'shortcutPreset.tvpaint': 'Base TVPaint',
    'shortcutAction.frame-previous': 'Image précédente',
    'shortcutAction.frame-next': 'Image suivante',
    'shortcutAction.drawing-previous': 'Bloc précédent',
    'shortcutAction.drawing-next': 'Bloc suivant',
    'shortcutAction.playback-toggle': 'Lecture / Pause',
    'shortcutAction.playback-to-start': 'Au début',
    'shortcutAction.playback-loop-toggle': 'Boucle / lecture unique',
    'shortcutAction.canvas-pan-hold': 'Déplacer (maintenir)',
    'shortcutAction.canvas-rotate-hold': 'Pivoter (maintenir)',
    'shortcutAction.canvas-line-hold':
        'Ligne depuis le dernier trait (maintenir)',
    'shortcutAction.voice-record-toggle':
        'Enregistrer la voix (démarrer/arrêter)',
    'shortcutAction.edit-undo': 'Annuler',
    'shortcutAction.edit-redo': 'Rétablir',
    'shortcutAction.tool-brush': 'Outil pinceau',
    'shortcutAction.tool-eraser': 'Outil gomme',
    'shortcutAction.tool-eyedropper': 'Outil pipette',
    'shortcutAction.tool-fill': 'Outil remplissage',
    'shortcutAction.tool-fill-bucket': 'Pot de peinture',
    'shortcutAction.tool-text': 'Outil texte',
    'shortcutAction.tool-shape': 'Outil forme',
    'shortcutAction.tool-guide': 'Outil repère',
    'shortcutAction.guide-add-symmetry': 'Nouveau repère de symétrie',
    'shortcutAction.guide-add-perspective': 'Nouveau repère de perspective',
    'shortcutAction.timesheet-data-mode': 'Feuille de notation / de données',
    'shortcutAction.tool-select': 'Outil sélection',
    'shortcutAction.tool-transform': 'Outil transformation',
    'shortcutAction.tool-transform-normal': 'Transformation normale',
    'shortcutAction.tool-transform-free': 'Transformation libre',
    'shortcutAction.tool-transform-mesh': 'Déformation par grille',
    'shortcutAction.tool-cut': 'Outil découpe',
    'shortcutAction.tool-cut-whole': 'Découpe entière',
    'shortcutAction.tool-cut-stamp': 'Tampon',
    'shortcutAction.selection-deselect': 'Désélectionner',
    'shortcutAction.layer-up': 'Calque vers le haut',
    'shortcutAction.layer-down': 'Calque vers le bas',
    'shortcutAction.edit-confirm': 'Valider',
    'shortcutAction.selection-transform-cancel': 'Annuler la transformation',
    'shortcutAction.transform-flip-horizontal':
        'Miroir horizontal de la transformation',
    'shortcutAction.transform-flip-vertical':
        'Miroir vertical de la transformation',
    'shortcutAction.transform-reset': 'Réinitialiser la transformation',
    'shortcutAction.cut-stamp-reset': 'Réinitialiser le tampon',
    'shortcutAction.onion-skin-toggle': "Activer/désactiver la pelure d'oignon",
    'shortcutAction.camera-view-toggle': 'Activer/désactiver la vue caméra',
    'shortcutAction.canvas-rotate-ccw': 'Pivoter la vue à gauche',
    'shortcutAction.canvas-rotate-cw': 'Pivoter la vue à droite',
    'shortcutAction.canvas-flip-horizontal': 'Miroir horizontal de la vue',
    'shortcutAction.canvas-flip-vertical': 'Miroir vertical de la vue',
    'shortcutAction.canvas-straighten': 'Redresser la vue',
    'shortcutAction.canvas-fit': 'Ajuster la vue à la fenêtre',
    'shortcutAction.canvas-reset-view': 'Réinitialiser le zoom (100 %)',
    'shortcutAction.timeline-comma-1': 'Régler sur 1 comma',
    'shortcutAction.timeline-comma-2': 'Régler sur 2 commas',
    'shortcutAction.timeline-comma-3': 'Régler sur 3 commas',
    'shortcutAction.timeline-comma-4': 'Régler sur 4 commas',
    'shortcutAction.timeline-comma-n': 'Régler sur N commas',
    'shortcutAction.frame-new-drawing': 'Nouvelle image',
    'shortcutAction.layer-add': 'Nouveau calque',
    'shortcutAction.frame-blank-exposure': 'Vider',
    'shortcutAction.frame-toggle-mark-one': "Repère d'intervalle 1",
    'shortcutAction.frame-toggle-mark': "Repère d'intervalle 2",
    'shortcutAction.frame-mark-every': "Ajout auto de repères d'intervalle",
    'shortcutAction.timeline-push-blocks': 'Pousser (ouvrir des images)',
    'shortcutAction.timeline-pull-blocks': 'Tirer (fermer des images)',
    'shortcutAction.timeline-zoom-in': 'Zoom avant de la timeline',
    'shortcutAction.timeline-zoom-out': 'Zoom arrière de la timeline',
    'shortcutAction.timeline-zoom-fit': 'Ajuster la timeline à la vue',
    'shortcutAction.timeline-orientation-toggle':
        "Timeline / feuille d'exposition",
    'shortcutAction.edit-cut': 'Couper',
    'shortcutAction.edit-copy': 'Copier',
    'shortcutAction.edit-paste-linked': 'Coller lié',
    'shortcutAction.edit-paste-independent': 'Coller indépendant',
    'shortcutAction.edit-unlink': 'Rendre indépendant',
    'shortcutAction.edit-delete': 'Supprimer',
    'shortcutAction.edit-duplicate': 'Dupliquer',
    'shortcutAction.edit-merge': 'Fusionner',
    'shortcutAction.edit-replace-colour': 'Remplacer la couleur',
    'shortcutAction.edit-clear-pixels': 'Effacer les pixels',
    'shortcutAction.edit-binarize': 'Binariser',
    'shortcutAction.edit-delete-colour': 'Supprimer la couleur',
    'shortcutAction.edit-keep-colour': 'Conserver la couleur',
    'shortcutAction.edit-cut-pixels': 'Couper les pixels',
    'shortcutAction.edit-copy-pixels': 'Copier les pixels',
    'shortcutAction.edit-paste-pixels-above': 'Coller les pixels dessus',
    'shortcutAction.edit-paste-pixels-below': 'Coller les pixels dessous',
    'shortcutAction.edit-instance': 'Modifier',
    'shortcutAction.edit-auto-name': 'Nommer automatiquement',
    'blendMode.passThrough': 'Transfert',
    'blendMode.normal': 'Normal',
    'blendMode.color': 'Normal',
    'blendMode.behind': 'Arrière',
    'blendMode.erase': 'Effacer',
    'blendMode.darken': 'Obscurcir',
    'blendMode.multiply': 'Produit',
    'blendMode.colorBurn': 'Densité couleur +',
    'blendMode.lighten': 'Éclaircir',
    'blendMode.screen': 'Superposition',
    'blendMode.colorDodge': 'Densité couleur -',
    'blendMode.add': 'Densité linéaire - (Ajout)',
    'blendMode.overlay': 'Incrustation',
    'blendMode.softLight': 'Lumière tamisée',
    'blendMode.hardLight': 'Lumière crue',
    'blendMode.difference': 'Différence',
    'blendMode.exclusion': 'Exclusion',
    'blendMode.linearBurn': 'Densité linéaire +',
    'blendMode.subtract': 'Soustraction',
    'blendMode.vividLight': 'Lumière vive',
    'blendMode.linearLight': 'Lumière linéaire',
    'blendMode.pinLight': 'Lumière ponctuelle',
    'blendMode.hardMix': 'Mélange maximal',
    'blendMode.darkerColor': 'Couleur plus foncée',
    'blendMode.lighterColor': 'Couleur plus claire',
    'blendMode.divide': 'Division',
    'blendMode.hue': 'Teinte',
    'blendMode.saturation': 'Saturation',
    'blendMode.chroma': 'Couleur',
    'blendMode.luminosity': 'Luminosité',
    'effectKind.brightnessContrast': 'Luminosité/Contraste',
    'effectKind.hueSaturation': 'Teinte/Saturation',
    'effectKind.blur': 'Flou gaussien',
    'effectKind.directionalBlur': 'Flou directionnel',
    'effectKind.radialBlur': 'Flou radial',
    'effectKind.cameraLensBlur': 'Flou objectif appareil photo',
    'effectKind.colorKey': 'Masquage par couleur',
    'effectKind.celNumber': 'Numéro de cellulo',
    'effectParameter.brightness': 'Luminosité',
    'effectParameter.contrast': 'Contraste',
    'effectParameter.hue': 'Teinte globale',
    'effectParameter.saturation': 'Saturation globale',
    'effectParameter.lightness': 'Luminosité globale',
    'effectParameter.blurriness': 'Flou',
    'effectParameter.blurDimensions': 'Dimensions du flou',
    'effectParameter.repeatEdgePixels': 'Répéter les pixels du contour',
    'effectParameter.direction': 'Direction',
    'effectParameter.blurLength': 'Longueur du flou',
    'effectParameter.keyColor': 'Couleur de la clé',
    'effectParameter.ink': 'Encre',
    'effectParameter.tolerance': 'Tolérance',
    'effectParameter.amount': 'Quantité',
    'effectParameter.keyOperation': 'Opération',
    'effectParameter.center': 'Centre',
    'effectParameter.type': 'Type',
    'effectParameter.antialiasing': 'Anticrénelage',
    'effectParameter.blurRadius': 'Rayon du flou',
    'effectParameter.irisShape': 'Forme',
    'effectParameter.irisRoundness': 'Arrondi',
    'effectParameter.irisAspectRatio': 'Format',
    'effectParameter.irisRotation': 'Rotation',
    'effectParameter.irisDiffractionFringe': 'Frange de diffraction',
    'effectParameter.blurMapLayer': 'Calque de la carte de flou',
    'effectParameter.blurMapChannel': 'Couche de la carte de flou',
    'effectParameter.blurFocalDistance': 'Distance focale du flou',
    'effectParameter.invertBlurMap': 'Inverser la carte de flou',
    'effectParameter.highlightGain': 'Gain des tons clairs',
    'effectParameter.highlightThreshold': 'Seuil des tons clairs',
    'effectParameter.highlightSaturation': 'Saturation des tons clairs',
    'effectParameter.useLinearWorkingSpace': "Utiliser l'espace de travail linéaire",
    'effectChoice.keyColors': 'Masquer',
    'effectChoice.keepColors': 'Conserver',
    'effectChoice.horizontalAndVertical': 'Horizontale et verticale',
    'effectChoice.horizontal': 'Horizontale',
    'effectChoice.vertical': 'Verticale',
    'effectChoice.spin': 'Rotation',
    'effectChoice.zoom': 'Zoom',
    'effectChoice.best': 'Optimal',
    'effectChoice.draft': 'Brouillon',
    'effectChoice.triangle': 'Triangle',
    'effectChoice.square': 'Carré',
    'effectChoice.pentagon': 'Pentagone',
    'effectChoice.hexagon': 'Hexagone',
    'effectChoice.heptagon': 'Heptagone',
    'effectChoice.octagon': 'Octogone',
    'effectChoice.nonagon': 'Ennéagone',
    'effectChoice.decagon': 'Décagone',
    'effectChoice.luminance': 'Luminance',
    'effectChoice.red': 'Rouge',
    'effectChoice.green': 'Vert',
    'effectChoice.blue': 'Bleu',
    'effectChoice.alpha': 'Alpha',
    'selectionMode.replace': 'Nouvelle sélection',
    'selectionMode.add': 'Ajouter à la sélection',
    'selectionMode.subtract': 'Soustraire de la sélection',
    'selectionMode.intersect': 'Intersection avec la sélection',
    'shortcutAction.file-save': 'Enregistrer',
    'shortcutAction.file-save-as': 'Enregistrer sous',
    'shortcutAction.layer-visibility-solo': 'Solo du calque actif',
    'shortcutAction.canvas-zoom-in': 'Zoom avant',
    'shortcutAction.canvas-zoom-out': 'Zoom arrière',
    'cutCommands': 'Commandes de plan',
    'shortcutAction.cut-new': 'Nouveau plan',
    'shortcutAction.cut-edit-note': 'Modifier la note du plan',
    'shortcutAction.cut-settings': 'Réglages du plan',
    'cutSettingsTitle': 'Réglages du plan',
    'mediaActions': 'Actions média',
    'mediaPoolEmpty': 'Aucun média',
    'mediaRename': 'Renommer le média',
    'mediaPlace': 'Placer',
    'mediaRelink': 'Relier',
    'mediaMissingCount': '{n} fichiers multimédias introuvables',
    'mediaFindInFolder': 'Chercher dans un dossier',
    'mediaRelinkFound': '{m} sur {n} trouvés. Les relier ?',
    'mediaRemove': 'Supprimer le média',
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
    'mediaViewerEmpty': 'Rien à afficher',
    'mediaViewerOpenFile': 'Ouvrir un fichier',
    'mediaViewerCloseFile': 'Fermer le fichier',
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
        'Des fichiers non pris en charge ont été détectés. Formats '
        'acceptés : {kinds}.',
    'mediaViewerSwap': "Échanger avec l'autre visionneuse",
    'mediaViewerRegisterAsset': 'Ajouter aux médias',
    'panelMediaViewer': 'Visionneuse',
    'panelMediaViewerSub': 'Visionneuse secondaire',
    'mediaRemoveInUse':
        'Ce média est utilisé. Le supprimer quand même ? Les calques et '
        'images placés seront supprimés.',
    'mediaUsesHeading': 'Utilisations',
    'panelCanvas': 'Canevas',
    'panelColorWheel': 'Roue chromatique',
    'transportIn': 'Entrée',
    'transportOut': 'Sortie',
    'transportToStart': 'Au début',
    'transportToEnd': 'À la fin',
    'transportLoop': 'Boucle',
    'transportOnce': 'Lire une fois',
    'transportPrevFrame': 'Image précédente',
    'transportNextFrame': 'Image suivante',
    'colorRecent': 'Récentes',
    'colorBackgroundSwap': 'Couleur de fond (toucher pour échanger)',
    'paletteViewCompact': 'Compact',
    'paletteViewCards': 'Cartes',
    'paletteNew': 'Nouvelle palette',
    'paletteNumberedTemplate': 'Palette {n}',
    'paletteMakeDefault': 'Définir par défaut',
    'paletteDuplicate': 'Dupliquer',
    'paletteExport': 'Exporter',
    'paletteBroughtTemplate': 'Palette « {name} » ajoutée.',
    'paletteCopyTemplate': 'Copie de {name}',
    'paletteDeleteTitle': 'Supprimer la palette',
    'paletteDeleteTemplate': 'Supprimer la palette « {name} » ?',
    'paletteRemoveCurrent': 'Retirer la couleur actuelle',
    'paletteLock': 'Verrouiller la palette',
    'paletteMore': 'Plus',
    'penPressureTitle': 'Pression du stylet',
    'brushDynamicsTitle': 'Réponse',
    'curveSourcePressure': 'Pression',
    'curveSourceTilt': 'Inclinaison',
    'curveSourceSpeed': 'Vitesse',
    'curveSourceRandom': 'Aléatoire',
    'curveMinimum': 'Min',
    'curveMaximum': 'Max',
    'curveTiltFlat': 'À plat',
    'curveTiltUpright': 'Droit',
    'onionCurrentDrawing': 'Dessin actuel',
    'audioLevelMeter': 'vumètre audio',
    'panelColorRgb': 'RVB',
    'panelColorPalette': 'Palette',
    'panelMedia': 'Médias',
    'panelOnionSkin': "Pelure d'oignon",
    'panelToolSize': 'Taille de l\'outil',
    'panelStoryboard': 'Conte',
    'panelTimeline': 'Timeline',
    'panelTimesheet': 'Feuille de temps',
    'panelConte': 'Feuille de conte',
    'panelEnvelope': 'Enveloppe de plan',
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
    'onionBeforeTint': 'Teinte avant',
    'onionAfterTint': 'Teinte après',
    'onionGhostColorHelp': 'Comment les fantômes sont colorés',
    'onionPegCountHelp': 'Ce que compte un cran',
    'onionPlacementHelp': 'Où se placent les fantômes',
    'onionStepBlocks': 'Blocs',
    'onionStepBlocksDrawings': 'Blocs (dessins)',
    'onionStepFrames': 'Images',
    'onionModeColors': 'Couleurs',
    'onionModeImages': 'Dessins',
    'onionPlacementOnTop': 'Au-dessus',
    'onionPlacementInPlace': 'Sur place',
    'onionPegBeforeTemplate': '{n} avant',
    'onionPegAfterTemplate': '{n} après',
    'shortcutTitle': 'Raccourcis clavier',
    'shortcutResetAll': 'Tout réinitialiser',
    'shortcutFileImportedTemplate':
        '{taken} raccourcis importés dans le nouveau préréglage '
        '« {preset} » ({skipped} sans équivalent ici).',
    'shortcutPresets': 'Préréglages',
    'shortcutPresetNew': 'Nouveau préréglage',
    'shortcutPresetNameEmpty': 'Le nom du préréglage ne peut pas être vide.',
    'shortcutPresetDelete': 'Supprimer le préréglage',
    'shortcutPresetRename': 'Renommer le préréglage',
    'shortcutPresetDuplicate': 'Dupliquer le préréglage',
    'shortcutPresetExport': 'Exporter le préréglage',
    'shortcutPresetBroughtTemplate': 'Préréglage « {name} » ajouté.',
    'shortcutPresetCopyTemplate': 'Copie de {name}',
    'shortcutPresetDeleteTemplate': 'Supprimer le préréglage « {name} » ?',
    'shortcutFileUnreadableTemplate':
        '{name} : aucun raccourci lisible dans ce fichier.',
    'shortcutResetToDefault': 'Rétablir le défaut',
    'shortcutUnassign': 'Retirer le raccourci',
    'shortcutRecordNew': 'Enregistrer un nouveau raccourci',
    'shortcutTouch': 'Raccourci tactile',
    'shortcutSearch': 'Rechercher une action',
    'shortcutConflictBanner':
        'Certaines actions partagent la même touche — les assignations '
        'surlignées entrent en conflit.',
    'shortcutRecordingHint': 'Appuyez sur des touches… (Échap annule)',
    'playbackMode': 'Mode de lecture',
    'playbackModeSkipFrames': 'Sauter des images',
    'playbackModeEveryPicture': 'Toutes les images',
    'playbackModeRenderFirst': 'Rendu avant lecture',
    'playbackDroppedCount': '{n} sautées',
    'playbackDroppedCountOne': '{n} sautée',
    'playbackSilentCount': '{n} sons muets',
    'playbackSilentCountOne': '{n} son muet',
    'playbackOutputRefused': "Pas de son — la sortie ne s'est pas ouverte.",
    'soundCannotPlay.missing': 'Lecture impossible — le fichier est introuvable.',
    'soundCannotPlay.notReadYet':
        "Lecture impossible pour l'instant — le fichier n'a pas pu être lu (une copie cloud est peut-être encore en téléchargement).",
    'soundCannotPlay.format':
        'Lecture impossible — aucun décodeur ne lit ce format.',
    'soundCannotPlay.conform':
        'Lecture impossible — la conversion pour la lecture a échoué.',
    'soundCannotPlay.deviceRate':
        "Lecture impossible — impossible de l'amener à la fréquence d'échantillonnage de la sortie.",
    'playbackStop': 'Arrêter',
    'sheetPreviousPage': 'Page précédente',
    'sheetNextPage': 'Page suivante',
    'sheetPageDrag': 'Page (glisser)',
    'autosaveTitle': 'Sauvegarde automatique',
    'autosaveEvery': 'Toutes les',
    'autosaveSectionHelp':
        'Enregistre le projet à intervalle régulier : un plantage ou une batterie vide ne coûte au plus que cet intervalle de travail.',
    'autosaveSwitchHelp':
        'Désactivé, le projet ne change qu\'à l\'enregistrement, et un plantage coûte tout ce qui a suivi.',
    'appContainerTitle': 'Conteneur de l\'application',
    'appContainerHelp':
        'Ce que l\'application garde en dehors de vos fichiers de projet : réglages et pointes de brosse, les médias et l\'audio qu\'un import a apportés et qu\'aucun enregistrement n\'a encore absorbés, et un journal de diagnostic.',
    'commonMinutesShort': ' min',
    'exExport': 'Exporter',
    'exAddToQueue': 'Ajouter à la file',
    'exImage': 'Image',
    'exVideo': 'Vidéo',
    'exCels': 'Cellulos',
    'exFormat': 'Format',
    'exOptions': 'Options',
    'exNaming': 'Nommage',
    'exScope': 'Portée',
    'exQuality': 'Qualité',
    'exCodec': 'Codec',
    'exBitrate': 'Débit',
    'exChannels': 'Canaux',
    'exAudio': 'Audio',
    'exHandOverDeclined': 'Non transmis — les fichiers exportés ont été abandonnés.',
    'exHandOverPending': 'Les fichiers exportés n’ont pas encore été transmis.',
    'exHandOverPickAgain': 'Choisir à nouveau',
    'exHandOverDiscard': 'Abandonner',
    'exSavePreset': 'Enregistrer le préréglage',
    'exPresetNameEmpty': 'Le nom du préréglage ne peut pas être vide.',
    'exBaseName': 'Nom de base',
    'exSuffix': 'Suffixe',
    'exPrefix': 'Préfixe',
    'exLayDirection': 'Poser une direction sur ce dessin',
    'exLayGuides': 'Repères',
    'exCelFormat': 'Format des cellulos',
    'exTimesheetFormat': 'Format de la feuille de temps',
    'exEnvelopeFormat': 'Format de l\'enveloppe de plan',
    'exWrittenCount': '{n} fichiers',
    'exWrittenCountOne': '{n} fichier',
    'noticeExportNoPicture':
        'Aucune ligne active n\'a de dessin pour ce cellulo',
    'noticeExportNotPlaced': 'Ce dessin n\'est pas sur la timeline',
    'noticeExportSameName': 'Une ligne du même nom exporte déjà ce dessin',
    'exDigits': 'Chiffres',
    'exApplyLayerFx': 'FX de calque',
    'exMuxSeMix': 'Intégrer le mixage SE dans la vidéo',
    'exLabel': 'Étiquette',
    'exApply': 'Appliquer',
    'exKinds': 'Types à exporter',
    'exLayerFilter': 'Calques',
    'exSelBase': 'Base',
    'exCelsLayersOut': 'Calques à exporter',
    'exSelAttach': 'Attaches',
    'exSelSheet': 'Feuille seule',
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
    'exStratumPaper': 'Papier',
    'exStratumForm': 'Formulaire',
    'exStratumContent': 'Texte',
    'exStratumPicture': 'Images',
    'exStratumInk': 'Encre',
    'exLeftOutOfTheFile': 'Tout n’a pas pu être conservé dans le fichier.',
    'exNoCels': '(aucun cellulo)',
    'exNoCuts': '(aucun plan)',
    'exPresets': 'Préréglages',
    'exQueue': 'File d\'attente',
    'exSize': 'Taille',
    'exCutSize': 'Taille du plan',
    'exRealSheet': 'Feuille réelle',
    'imNotTvpp': 'Ce fichier ne peut pas être lu comme un projet TVPaint.',
    'imNotClip':
        'Ce fichier ne peut pas être lu comme un fichier CLIP STUDIO PAINT.',
    'imLeftBehind': 'Tout n’a pas pu être importé.',
    'imWarningCount': '{n} avertissements',
    'imWarningCountOne': '{n} avertissement',
    'imFileUnreadable':
        'Le fichier n\'a pas pu être lu — s\'il est dans le cloud, réessayez '
        'dans un instant.',
    'imNotFoundTemplate': 'Introuvable : {path}',
    'importWarning.stagedCopy':
        'Ouvert via une copie temporaire, le fichier n\'ayant pas pu être lu '
        'sur place — signalez-le si vous voyez ce message.',
    'importWarning.soundMissing':
        'Le fichier son n\'est pas à cet emplacement : {path}',
    'importWarning.celUnreadable':
        '{file} : impossible de lire l\'image — {detail}',
    'importWarning.psdBitDepth': 'Document {depth} bits ramené à 8 bits.',
    'importWarning.psdVectorMask': '{name} : masque vectoriel ignoré.',
    'importWarning.psdComposite':
        'L\'image composite utilise la compression {compression} — ignorée.',
    'importWarning.psdExtraChannels':
        'Canaux supplémentaires du document ignorés.',
    'importWarning.psd32Bit':
        'Les données de canal prédites en 32 bits ne sont pas prises en '
        'charge.',
    'importWarning.psdDuotone': 'Bichromie lue en niveaux de gris.',
    'importWarning.psdMultichannel':
        'Multicanal lu en niveaux de gris de son premier canal.',
    'importWarning.psdIndexedNoPalette':
        'Couleurs indexées sans palette lues en niveaux de gris.',
    'importWarning.psdCmyk':
        'CMJN converti en RVB sans profil — les couleurs changent.',
    'importWarning.psdLab':
        'Lab converti en RVB sans profil — les couleurs changent.',
    'importWarning.clippingNotApplied': '{name} : masque d\'écrêtage non appliqué.',
    'importWarning.layerEffectsNotApplied': '{name} : effets de calque non appliqués.',
    'importWarning.layerMaskNotApplied': '{name} : masque de fusion non appliqué.',
    'importWarning.lockNotImported': '{name} : verrouillage non importé.',
    'importWarning.psdBlend':
        '{name} : le mode de fusion « {mode} » n\'a pas d\'équivalent — réglé '
        'sur normal.',
    'importWarning.folderNothing':
        'Ce dossier ne contient ni cellulo ni image importable.',
    'importWarning.folderNoCutNumber':
        'Aucun numéro de plan dans le nom du dossier.',
    'importWarning.tvpNoFile':
        '{name} : l\'instance à l\'image {frame} ne nomme aucun fichier — son '
        'cellulo reste vide.',
    'importWarning.tvpMuted':
        '{file} : la piste était muette — son son est tout de même lié.',
    'importWarning.tvpBlend':
        '{name} : le mode de fusion « {mode} » n\'a pas d\'équivalent dans '
        'Anicel — importé en normal.',
    'importWarning.tvppHoldNoDrawing':
        '{name} : le maintien à l\'image {frame} n\'a aucun dessin à '
        'reprendre.',
    'importWarning.tvppChunkBroken':
        'Clip {n} : la chaîne de blocs s\'est rompue à @{at} — tout ce qui '
        'suit est abandonné.',
    'importWarning.clipRead':
        'Une partie du fichier n\'a pas pu être suivie : {detail}',
    'importWarning.clipFps':
        'Les timelines n\'ont pas la même cadence — le projet prend celle de '
        'la première, {fps} i/s.',
    'importWarning.clipUnplaced':
        '{name} : {count} cellulo(s) ne figurent sur aucune timeline — non '
        'importé(s).',
    'importWarning.clipNoSuchCel':
        '{name} : {count} clé(s) désignent un cellulo absent du dossier.',
    'importWarning.clipCelLayers':
        '{name} : les calques de ses cellulos sont devenus des rangées — par '
        'leur nom quand d\'autres cellulos le partagent, sinon selon leur '
        'place depuis le haut ; leurs noms et leurs dossiers ne sont pas '
        'conservés.',
    'importWarning.clipSpread':
        '{name} : dans {count} cellulo(s), l\'opacité ou le mode de fusion '
        'd\'un dossier a été donné à chacun de ses calques — là où ils se '
        'chevauchent, le rendu peut différer.',
    'importWarning.clipLineOrder':
        '{name} : dans {count} cellulo(s), deux calques se superposent dans '
        'l\'ordre inverse de CLIP STUDIO — là où ils se chevauchent, le '
        'rendu peut différer.',
    'importWarning.clipVector':
        '{name} : calque vectoriel — dessiné au stylo rond ; la forme et la '
        'texture de la brosse ne sont pas reprises.',
    'importWarning.clipVectorUnread':
        '{name} : {count} traits vectoriels d’un type illisible — non '
        'dessinés.',
    'importWarning.clipSound': '{name} : calque son non importé.',
    'importWarning.clipSoundMissing':
        "{name} : son son n'est pas dans le fichier — il n'est pas joué.",
    'importWarning.clipSoundSpeed':
        '{name} : CLIP STUDIO le joue à une autre vitesse — il est joué ici à '
        'la sienne.',
    'importWarning.clipSoundVolume':
        '{name} : son volume change au cours du clip — réglé sur celui du '
        'début du clip.',
    'importWarning.clipCurve':
        '{name} : des clés suivent une courbe que cette importation ne lit '
        'pas — le calque va en ligne droite entre elles.',
    'importWarning.unsupportedLayerKind':
        "{name} : ce type de calque n'est pas pris en charge.",
    'importWarning.clipBlend':
        '{name} : le mode de fusion {mode} n\'a pas d\'équivalent — réglé '
        'sur normal.',
    'importWarning.clipNotColour':
        '{name} : calque gris ou monochrome — non dessiné.',
    'importWarning.clipTransform':
        '{name} : l\'échelle ou la rotation de l\'image n\'est pas appliquée.',
    'importWarning.clipTextUnread':
        '{name} : un texte dont les réglages sont illisibles — non importé.',
    'importWarning.clipTextAlign':
        '{name} : lignes alignées d\'une façon que cette application ne sait '
        'pas composer — affichées telles que CLIP STUDIO les a dessinées, et '
        'alignées d\'une seule façon une fois modifiées.',
    'importWarning.clipTextSpacing':
        '{name} : interlignes inégaux — affichés tels que CLIP STUDIO les a '
        'dessinés, et égalisés une fois modifiés.',
    'importWarning.clipTextDistorted':
        '{name} : un texte déformé — affiché tel que CLIP STUDIO l\'a '
        'dessiné, et composé sans déformation une fois modifié.',
    'importWarning.clipTextSetHere':
        '{name} : un texte composé par cette application — l\'image qu\'en a '
        'faite CLIP STUDIO n\'est pas dans le fichier, ou n\'a pas pu être lue.',
    'importWarning.brushPackUnreadable':
        'Ce fichier ne peut pas être lu comme un fichier de brosses Anicel.',
    'importWarning.brushPackNotOurs':
        'Ce fichier n’est pas un fichier de brosses Anicel.',
    'importWarning.brushPackNewer':
        'Ce fichier de brosses a été écrit par une version plus récente '
        'd’Anicel (format {version}) ; cette version lit jusqu’au format '
        '{readable}.',
    'importWarning.brushPackEmpty':
        'Ce fichier de brosses ne contient aucune brosse.',
    'importWarning.brushPackDamaged':
        'Ce fichier de brosses est endommagé et n’a pas pu être lu.',
    'importWarning.abrTooShort':
        'Fichier trop court pour être un fichier ABR.',
    'importWarning.abrOldVersion':
        'La version ABR {version} (époque de Photoshop 6) n’est pas encore '
        'prise en charge ; réenregistrez les brosses avec un Photoshop récent.',
    'importWarning.abrUnknownVersion':
        'Fichier ABR non pris en charge (version {version}).',
    'importWarning.abrCorruptSection': 'Longueur de section ABR corrompue.',
    'importWarning.abrNoBrushes': 'Aucune brosse trouvée dans le fichier ABR.',
    'importWarning.abrNothingImportable':
        'Le fichier ABR ne contient aucune brosse importable.',
    'importWarning.sutCannotOpen': 'Impossible d’ouvrir le fichier : {error}',
    'importWarning.sutUnreadable':
        'Ce fichier n’est pas une brosse CLIP STUDIO lisible ({error}).',
    'importWarning.sutNoBrushData':
        'Aucune donnée de brosse CLIP STUDIO trouvée dans ce fichier.',
    'importWarning.sutNothingImportable':
        'Le fichier ne contient aucune brosse importable.',
    'fileType.anicel': 'Projet Anicel',
    'fileType.wav': 'Audio WAV',
    'fileType.anibrush': 'Brosse Anicel',
    'exclusionReason.processSubfolder': 'sous-dossier de process (archive)',
    'exclusionReason.unrecognized': 'non reconnu',
    'exclusionReason.excludedName': 'nom exclu',
    'exclusionReason.memoText': 'texte de mémo',
    'exclusionReason.insertionLettersOff': 'lettres d\'intercalage désactivées',
    'exFrameCount': '{n} images',
    'exFrameCountOne': '{n} image',
    'exPageCount': '{n} pages',
    'exPageCountOne': '{n} page',
    'exFileCount': '{n} fichiers',
    'exFileCountOne': '{n} fichier',
    'exJobCount': '{n} tâches',
    'exJobCountOne': '{n} tâche',
    'exContePageCount': '{n} pages de conte',
    'exContePageCountOne': '{n} page de conte',
    'exCancelledAfterTemplate': 'Export annulé après {count}.',
    'exCancelledVideoTemplate': 'Export annulé après {count} (vidéo partielle conservée).',
    'exCancelled': 'Export annulé.',
    'exDoneTemplate': 'Exporté : {count}.',
    'exDoneSkippedTemplate': 'Exporté : {count} ({skipped} vides ignorés).',
    'exDoneFileTemplate': 'Exporté : {name}.',
    'exDoneVideoTemplate': 'Vidéo exportée ({count}).',
    'exDoneConteDocumentTemplate': 'Exporté : {name} ({count}).',
    'exNothingInFrame': 'Rien à exporter (image vide).',
    'exFailedTemplate': 'Échec de l\'export : {error}',
    'exQueueRestTemplate': 'File : {count} terminé{failed}{rest}.',
    'exQueueFailedTemplate': ', {n} en échec',
    'exQueueRestKept': ', le reste est conservé',
    'exFileLabel': 'Fichier',
    'exOrderAsksFirst': 'Choisit l’emplacement, puis exporte',
    'exOrderAsksAfter': 'Exporte, puis choisit l’emplacement',
    'exSeMuxedTemplate': 'SE intégré · {codec}',
    'exVectorPdf': 'PDF vectoriel',
    'exFxOn': 'FX activés',
    'exFxOff': 'FX désactivés',
    'exFxBasic': 'FX de base seuls',
    'exFxBasicOnly': 'Base seule',
    'exTabSequence': 'Séquence',
    'exSizeCamera': 'Caméra',
    'exSizeCanvas': 'Canevas',
    'exPageImage': 'Image de page',
    'exSaveCurrent': '+ Enregistrer l\'actuel',
    'exRenderQueue': 'File de rendu',
    'exRenderAll': 'Tout rendre',
    'exJobQueued': 'En attente',
    'exJobDone': 'Terminé',
    'exJobFailed': 'Échec',
    'exJobCancelled': 'Annulé',
    'exJobTemplate': 'Tâche {id} · {tab}',
    'exIncludeAll': 'Tous',
    'exCutsIncludedTemplate': '{n} / {total} plans',
    'exNeedsFfmpeg': 'Nécessite FFmpeg dans le PATH de cette machine.',
    'exCheckingEncoders': 'Vérification des encodeurs de cette machine…',
    'exNotInThisBuild': 'Pas encore disponible dans cette version.',
    'exBitrateAuto': 'Auto',
    'exCanvasTemplate': 'Canevas {size}',
    'exCanvasPerCut': 'Canevas (par plan)',
    'imImport': 'Importer',
    'imFile': 'Fichier',
    'imInto': 'Vers',
    'imFit': 'Ajuster',
    'imModified': 'Modifié',
    'imSize': 'Taille',
    'imResolution': 'Résolution',
    'imExcluded': 'Exclu',
    'imFolderAsOneCut': 'Plan',
    'imFolderPerRow': 'Personnalisé',
    'imPlaceTitleTemplate': 'Placer — {name}',
    'imModeKeep': 'Intégrer',
    'imModeReference': 'Lier',
    'imBake': 'Pixelliser',
    'imOptions': 'Options',
    'imPictureAndSound': 'Image + son',
    'imPictureOnly': 'Image seule',
    'imSoundOnly': 'Son seul',
    'imRunSpanTemplate': '{first}–{last} ({n})',
    'imRateTitleTemplate': 'Vidéo {movie} · projet {project}',
    'imRateBodyTemplate':
        'Régler le projet à {movie} ? Le son garde son timing.',
    'imRateKeepTemplate': 'Garder {project}',
    'imRateTakeTemplate': 'Régler à {movie}',
    'commonOn': 'Oui',
    'commonOff': 'Non',
    'imFitOriginal': 'Taille d’origine',
    'imFitContain': 'Ajuster, proportions gardées',
    'imFitStretch': 'Étirer, proportions ignorées',
    'imIntoNewLayer': 'Nouveau calque',
    'imIntoSeRow': 'Ligne SE',
    'imIntoRowCellTemplate': '{row} · image {frame}',
    'imIntoNewCut': 'Nouveau plan',
    'imPsdMerge': 'Fusionner les calques',
    'imPsdExpand': 'Garder les calques',
    'imNoSource': 'Aucune source',
    'imFileCountTemplate': '{n} fichiers',
    'imStatusImporting': 'Importation…',
    'imStatusNothing': 'Rien n’a été importé.',
    'imStatusDone': 'Importé',
    'imStepRecoding': 'Réencodage de la vidéo découpée…',
    'imStepWritingSpan': 'Écriture de la plage découpée dans un fichier…',
    'imStepCarrying': 'Intégration du fichier au projet…',
    'imStepRasterizing': 'Pixellisation en cellulos…',
    'imFolderGone': 'Ce dossier n’existe plus.',
    'imFolderUnreadableTemplate': 'Impossible de lire le dossier : {reason}',
    'imCutFolderUnreadable': 'Impossible de lire ce dossier.',
    'imUnreadableTemplate': '{name} : impossible de lire le fichier.',
    'imLacksPictureTemplate': '{name} : le fichier n’a pas d’image n° {number}.',
    'imCorruptTemplate':
        '{name} : impossible à ouvrir — fichier corrompu ou protégé par mot de passe.',
    'imPagesFailedTemplate':
        '{name} : {n} page(s) non rendue(s) — elles restent vides.',
    'imFramesFailedTemplate':
        '{name} : {n} image(s) non décodée(s) — elles restent vides.',
    'imNoPdfRendererTemplate': '{name} : pas de moteur PDF dans cette version.',
    'imCouldNotImportTemplate': '{name} : impossible à importer.',
    'imPsdNoLayersTemplate':
        '{name} : aucun calque à développer — importez-le fusionné.',
    'imKeepExplain':
        'Le fichier du projet les contient, compressés ; les originaux restent intacts.',
    'imReferenceExplain':
        'Les fichiers restent où ils sont et le projet pointe vers eux.',
    'mpFileMissing': 'Fichier introuvable — reliez-le',
    'mpInUseOnTimeline': 'Utilisé dans la timeline',
    'mpNameEmpty': 'Le nom du média ne peut pas être vide.',
    'exCameraTemplate': 'Caméra {size}',
    'toolBrush': 'Pinceau',
    'toolEraser': 'Gomme',
    'toolEyedropper': 'Pipette',
    'toolFill': 'Remplissage',
    'toolText': 'Texte',
    'toolShape': 'Forme',
    'textToolSelectedText': 'Texte sélectionné',
    'textToolDeleteText': 'Supprimer le texte',
    'textToolLetters': 'Caractères',
    'textToolBox': 'Bloc',
    'textToolFont': 'Police',
    'textToolSize': 'Taille',
    'textToolTracking': 'Interlettrage',
    'textToolBold': 'Gras',
    'textToolItalic': 'Italique',
    'textToolUnderline': 'Souligné',
    'textToolStrikethrough': 'Barré',
    'textToolColor': 'Couleur',
    'textToolOutline': 'Contour',
    'textToolOutlineWidth': 'Épaisseur du contour',
    'textToolAlign': 'Alignement',
    'textToolAlignLeft': 'Gauche',
    'textToolAlignCenter': 'Centre',
    'textToolAlignRight': 'Droite',
    'textToolCentreAcross': 'Centrer horizontalement',
    'textToolCentreDown': 'Centrer verticalement',
    'textToolBoxWidth': 'Largeur du bloc',
    'textToolWidthAuto': 'Auto',
    'textToolWidthFixed': 'Fixe',
    'textToolLineHeight': 'Interligne',
    'textToolLetterWidth': 'Échelle horizontale',
    'textToolSkew': 'Inclinaison',
    'textToolBackground': 'Fond',
    'textToolIntoDrawing': 'Pixelliser',
    'textToolWriting': 'Direction',
    'textToolWritingLines': 'Horizontale',
    'textToolWritingColumns': 'Verticale',
    'textToolAlignTop': 'Haut',
    'textToolAlignBottom': 'Bas',
    'textToolFontImport': 'Importer un fichier de police',
    'textToolFontDelete': 'Supprimer la police',
    'textToolFontsOfProject': 'Polices de ce projet',
    'textToolFontsOfDevice': 'Polices de cet appareil',
    'textToolFontTakeOut': 'Retirer du projet',
    'textToolFontStaysOnThisDevice':
        'Cette police ne peut pas être intégrée à un document modifiable : '
        "elle changera à l'ouverture sur un autre appareil.",
    'textToolFontNotOnThisDevice':
        "Cette police n'est pas sur cet appareil : le texte s'affiche avec "
        'une autre.',
    'textToolFontUnreadable': "Ce fichier n'a pas pu être lu comme une police.",
    'textToolFontIsTheApps': "Cette police fait déjà partie de l'application.",
    'textToolFontNotKept': "La police n'a pas pu être enregistrée.",
    'toolSelect': 'Sélection',
    'toolTransform': 'Transformation',
    'toolShapeFill': 'Remplissage de forme',
    'toolCutNothingHeld': 'Rien en main pour l\'instant',
    'toolCutHoldingTemplate': 'En main : {size} px',
    'toolLibraryEmpty': 'Rien à afficher',
    'toolCutPasteAtOrigin': 'Coller à la position d\'origine',
    'toolCutFlipHorizontal': 'Miroir horizontal',
    'toolCutFlipVertical': 'Miroir vertical',
    'toolCutRegisterTip': 'Enregistrer comme pointe',
    'toolCutDeletesSource': "Supprimer l'original",
    'toolReadSource': 'Référence',
    'toolReadsEveryVisibleLayer': 'Tous les calques visibles',
    'brushSettingsTitle': 'Réglages de brosse',
    'toolShapeRect': 'Rectangle',
    'toolShapeEllipse': 'Ellipse',
    'toolShapeLasso': 'Lasso',
    'toolShapePolygon': 'Polygone',
    'toolShapeLine': 'Ligne',
    'toolShapeSelectTemplate': 'Sélection {shape}',
    'toolShapeCutTemplate': 'Découpe {shape}',
    'toolShapeFillTemplate': 'Remplissage {shape}',
    'toolShapeDrawTemplate': 'Tracé {shape}',
    'shapeToolDraws': 'Tracé',
    'shapeToolStroke': 'Contour',
    'shapeToolFill': 'Remplissage',
    'shapeToolType': 'Type',
    'shapeToolTypePlain': 'Simple',
    'shapeToolCorners': 'Coins',
    'shapeToolCornersSharp': 'Vifs',
    'shapeToolCornersRound': 'Arrondis',
    'shapeToolRatioLock': 'Verrouiller les proportions',
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
    'brMixing': 'Mélange',
    'brMixingMethod': 'Méthode',
    'brMixingMix': 'Mélanger au fond',
    'brMixingBlur': 'Flouter',
    'brPaintAmount': 'Quantité de peinture',
    'brPaintDensity': 'Densité de peinture',
    'brColorStretch': 'Étirement de la couleur',
    'brHardness': 'Dureté',
    'stepUp': 'Monter d’un cran',
    'stepDown': 'Baisser d’un cran',
    'brEdgeNone': 'Aucun',
    'brSpacing': 'Espacement',
    'brAngle': 'Angle',
    'brRoundness': 'Rondeur',
    'brScale': 'Échelle',
    'brScatter': 'Dispersion',
    'brScatterCount': 'Nombre',
    'brScatterBothAxes': 'Deux axes',
    'brTipRotation': 'Orientation',
    'brRotationFixed': 'Aucune',
    'brRotationDirection': 'Sens du trait',
    'brRotationPenTilt': 'Sens du stylet',
    'brRotationPenTwist': 'Rotation du stylet',
    'brTipOrder': 'Méthode de répétition',
    'brTipOrderRepeat': 'Répéter',
    'brTipOrderPingPong': 'Aller-retour',
    'brTipOrderHoldLast': 'Sans répétition',
    'brTipOrderRandom': 'Aléatoire',
    'brTipOrderOneLap': 'Un seul tour',
    'brTipOrderShuffledLap': 'Un tour aléatoire',
    'brTipOrderLean': 'Inclinaison du stylet',
    'brTipsPerTurn': 'Pointes par tour',
    'brBrushTip': 'Pointe',
    'brTipNone': 'Aucune',
    'brDualTip': 'Pointe double',
    'brTexture': 'Texture',
    'brTextureDensity': 'Densité',
    'brTextureMode': 'Mode de texture',
    'brTextureModeHeight': 'Hauteur',
    'brAddTipImage': 'Ajouter une pointe depuis une image',
    'brRenameTip': 'Renommer la pointe',
    'brDeleteTip': 'Supprimer la pointe',
    'brDeleteTipBodyTemplate': '« {name} » sera retirée de la bibliothèque.',
    'brStabilizer': 'Stabilisateur',
    'brStabilizerOn': 'Appliquer le stabilisateur',
    'brStabilizerBySpeed': 'Selon la vitesse',
    'brBySpeedSlow': 'Lent',
    'brBySpeedFast': 'Rapide',
    'brPostCorrection': 'Lissage après tracé',
    'brPostBySpeed': 'Ajuster à la vitesse',
    'brPostByViewScale': 'Ajuster au zoom',
    'brPostBezier': 'Courbe de Bézier',
    'brSharpenCorners': 'Angles vifs',
    'brGroupInk': 'Encre',
    'brGroupTip': 'Pointe',
    'brGroupMixing': 'Mélange',
    'brGroupScattering': 'Dispersion',
    'brGroupTexture': 'Texture',
    'brGroupCorrection': 'Correction',
    'brDetailTitle': 'Détails de la brosse',
    'brShowInPanel': 'Afficher dans le panneau',
    'brHideFromPanel': 'Masquer du panneau',
    'shortcutAction.frame-auto-create': "Création auto d'images",
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
    'trFlipHorizontal': 'Miroir horizontal',
    'trFlipVertical': 'Miroir vertical',
    'trPosition': 'Position',
    'trScale': 'Échelle',
    'trScaleLink': 'Échelles liées',
    'trRotation': 'Rotation',
    'trAnchorPoint': 'Ancre',
    'trMeshColumns': 'Colonnes',
    'trMeshRows': 'Lignes',
    'trMesh': 'Grille',
    'trFinish': 'Finition',
    'brFillBeyondCanvas': 'Remplir au-delà du canevas',
    'brOpenRegionsRefuse': 'Les zones ouvertes ne se remplissent pas',
    'brName': 'Nom',
    'brDisplay': 'Affichage',
    'brTipIcon': 'Icône de pointe',
    'brStrokePreview': 'Aperçu du tracé',
    'brBrushOptions': 'Options du pinceau',
    'brNewGroup': 'Nouveau groupe',
    'brNewGroupName': 'Nouveau groupe',
    'brNewPresetName': 'Préréglage {n}',
    'builtinBrush.builtin-basic-group': 'Base',
    'builtinBrush.builtin-pencil-group': 'Crayon',
    'builtinBrush.builtin-ink-group': 'Plume',
    'builtinBrush.builtin-dry-media-group': 'Techniques sèches',
    'builtinBrush.builtin-watercolor-group': 'Aquarelle',
    'builtinBrush.builtin-paint-group': 'Huile',
    'builtinBrush.builtin-airbrush-group': 'Aérographe',
    'builtinBrush.builtin-blend-group': 'Mélange',
    'builtinBrush.builtin-texture-group': 'Texture',
    'builtinBrush.builtin-decoration-group': 'Décoration',
    'builtinBrush.builtin-pencil': 'Crayon HB',
    'builtinBrush.builtin-soft-pencil': 'Crayon 2B',
    'builtinBrush.builtin-mechanical-pencil': 'Porte-mine',
    'builtinBrush.builtin-hard-pencil': 'Crayon 2H',
    'builtinBrush.builtin-dark-pencil': 'Crayon 4B',
    'builtinBrush.builtin-colored-pencil': 'Crayon de couleur',
    'builtinBrush.builtin-coloring-pencil': 'Crayon à colorier',
    'builtinBrush.builtin-shading-pencil': 'Crayon couché',
    'builtinBrush.builtin-rough-edge': 'Crayon rugueux',
    'builtinBrush.builtin-ink-pen': 'Rond dur',
    'builtinBrush.builtin-g-pen': 'Plume G',
    'builtinBrush.builtin-maru-pen': 'Plume ronde',
    'builtinBrush.builtin-brush-pen': 'Feutre pinceau',
    'builtinBrush.builtin-calligraphy': 'Calligraphie',
    'builtinBrush.builtin-marker': 'Marqueur',
    'builtinBrush.builtin-kabura-pen': 'Plume Kabura',
    'builtinBrush.builtin-technical-pen': 'Stylo technique',
    'builtinBrush.builtin-dry-ink': 'Encre sèche',
    'builtinBrush.builtin-chalk-preset': 'Craie',
    'builtinBrush.builtin-charcoal': 'Fusain',
    'builtinBrush.builtin-pastel': 'Pastel',
    'builtinBrush.builtin-crayon': 'Crayon de cire',
    'builtinBrush.builtin-graphite-stick': 'Bâton de graphite',
    'builtinBrush.builtin-watercolor': 'Aquarelle',
    'builtinBrush.builtin-analog-watercolor': 'Aquarelle analogique',
    'builtinBrush.builtin-wet-watercolor': 'Aquarelle mouillée',
    'builtinBrush.builtin-dense-watercolor': 'Aquarelle dense',
    'builtinBrush.builtin-flat-wash': 'Lavis uni',
    'builtinBrush.builtin-flat-bristle': 'Brosse plate',
    'builtinBrush.builtin-gouache': 'Gouache',
    'builtinBrush.builtin-oil-brush': 'Pinceau à l\'huile',
    'builtinBrush.builtin-palette-knife': 'Couteau à peindre',
    'builtinBrush.builtin-dry-brush': 'Brosse sèche',
    'builtinBrush.builtin-airbrush': 'Aérographe',
    'builtinBrush.builtin-soft-brush': 'Rond flou',
    'builtinBrush.builtin-grit-spray': 'Spray granuleux',
    'builtinBrush.builtin-blender': 'Mélangeur',
    'builtinBrush.builtin-water-blend': 'Fondu à l\'eau',
    'builtinBrush.builtin-blending-stump': 'Estompe',
    'builtinBrush.builtin-blur': 'Flou',
    'builtinBrush.builtin-splatter-preset': 'Éclaboussures',
    'builtinBrush.builtin-stipple': 'Pointillé',
    'builtinBrush.builtin-sponge': 'Éponge',
    'builtinBrush.builtin-cloud': 'Nuage',
    'builtinBrush.builtin-concrete': 'Béton',
    'builtinBrush.builtin-grass': 'Herbe',
    'builtinBrush.builtin-sparkle': 'Scintillement',
    'builtinBrush.builtin-snow': 'Neige',
    'builtinBrush.builtin-bubble': 'Bulles',
    'builtinBrush.builtin-leaves': 'Feuilles',
    'builtinTip.builtin-chalk': 'Craie',
    'builtinTip.builtin-splatter': 'Éclaboussures',
    'builtinTip.builtin-grain': 'Grain',
    'builtinTip.builtin-bristle': 'Poils',
    'builtinTip.builtin-sponge': 'Éponge',
    'builtinTip.builtin-wet-blot': 'Tache humide',
    'builtinTip.builtin-star': 'Étoile',
    'builtinTip.builtin-flake': 'Flocon',
    'builtinTip.builtin-ring': 'Anneau',
    'builtinTip.builtin-leaf': 'Feuille',
    'builtinTip.builtin-grass-clump': "Touffe d'herbe",
    'builtinTip.builtin-paper-grain': 'Grain du papier',
    'builtinTip.builtin-canvas-weave': 'Trame de toile',
    'builtinTip.builtin-cold-press': 'Papier grain fin',
    'builtinTip.builtin-pencil-side': 'Flanc de mine',
    'builtinTip.builtin-graphite-tooth': 'Grain du graphite',
    'builtinTip.builtin-color-clumps': 'Grain de crayon de couleur',
    'builtinTip.builtin-pencil-face-0-0': 'Mine 1-1',
    'builtinTip.builtin-pencil-face-0-1': 'Mine 1-2',
    'builtinTip.builtin-pencil-face-0-2': 'Mine 1-3',
    'builtinTip.builtin-pencil-face-1-0': 'Mine 2-1',
    'builtinTip.builtin-pencil-face-1-1': 'Mine 2-2',
    'builtinTip.builtin-pencil-face-1-2': 'Mine 2-3',
    'builtinTip.builtin-pencil-face-2-0': 'Mine 3-1',
    'builtinTip.builtin-pencil-face-2-1': 'Mine 3-2',
    'builtinTip.builtin-pencil-face-2-2': 'Mine 3-3',
    'builtinTip.builtin-pencil-face-3-0': 'Mine 4-1',
    'builtinTip.builtin-pencil-face-3-1': 'Mine 4-2',
    'builtinTip.builtin-pencil-face-3-2': 'Mine 4-3',
    'builtinTip.builtin-pencil-face-4-0': 'Mine 5-1',
    'builtinTip.builtin-pencil-face-4-1': 'Mine 5-2',
    'builtinTip.builtin-pencil-face-4-2': 'Mine 5-3',
    'builtinTip.builtin-pencil-face-5-0': 'Mine 6-1',
    'builtinTip.builtin-pencil-face-5-1': 'Mine 6-2',
    'builtinTip.builtin-pencil-face-5-2': 'Mine 6-3',
    'builtinTip.builtin-pencil-crumb-0': 'Grain de mine 1',
    'builtinTip.builtin-pencil-crumb-1': 'Grain de mine 2',
    'builtinTip.builtin-pencil-crumb-2': 'Grain de mine 3',
    'brRenameGroup': 'Renommer le groupe',
    'brDeleteGroup': 'Supprimer le groupe',
    'brDeleteEmptyGroupTemplate': 'Supprimer le groupe vide « {name} » ?',
    'brDeleteGroupTemplateOne':
        'Supprimer « {name} » et le pinceau qu’il contient ?',
    'brDeleteGroupTemplate':
        'Supprimer « {name} » et les {n} pinceaux qu’il contient ?',
    'brRenameSelected': 'Renommer le pinceau sélectionné',
    'brDeleteSelected': 'Supprimer le pinceau sélectionné',
    'brSaveAsPreset': 'Enregistrer les réglages comme préréglage',
    'brImportBrushes': 'Importer des pinceaux (.abr, .sut, .sutg)',
    'brResetLibrary': 'Réinitialiser la bibliothèque',
    'brExportSelected': 'Exporter la brosse',
    'brExportGroup': 'Exporter le groupe',
    'brExportNothing': 'Aucune brosse à exporter ici.',
    'fileExportPlaceUnchosenTemplate':
        'Impossible de choisir où enregistrer : {error}',
    'settingsExportedTemplate': 'Exporté : « {name} ».',
    'settingsExportNotWrittenTemplate':
        'Impossible d’écrire le fichier : {error}',
    'settingsExportAll': 'Exporter toutes les préférences',
    'settingsAllFileName': 'Préférences Anicel',
    'settingsRowFrameCount': 'Saisie des durées',
    'settingsRowWorkspaceLayout': 'Disposition de l’espace de travail',
    'imIntoSettings': 'Préférences',
    'imSettingsGoInPlace':
        'Ce qui va dans Préférences remplace l’actuel — il sera perdu.',
    'imSettingsUnreadable': 'Illisible',
    'brExportNotWrittenTemplate':
        'Impossible d’écrire le fichier de brosses : {error}',
    'brExportedOneTemplate': 'Brosse exportée : « {name} ».',
    'brExportedManyTemplate': '{count} brosses exportées.',
    'brExportFallbackName': 'Brosses',
    'brImportUnreadable':
        'Ce fichier n’a pas pu être lu comme un fichier de brosses.',
    'brImportPickFailedTemplate': 'Impossible d’ouvrir le fichier : {error}',
    'fontBroughtTemplate': 'Police « {family} » ajoutée à cet appareil.',
    'brImportedOneTemplate': '1 brosse importée depuis « {file} ».',
    'brImportedManyTemplate': '{count} brosses importées depuis « {file} ».',
    'brImportWarningsTemplate':
        '{summary} ({count} entrées avec des avertissements)',
    'brTipUnreadable': 'Cette image n’a pas pu être lue comme pointe de brosse.',
    'brTipNoShape':
        'Cette image n’a aucune forme visible à utiliser comme pointe.',
    'brTipNotSaved': 'Cette pointe n’a pas pu être enregistrée.',
    'brExpand': 'Déplier',
    'commonReset': 'Réinitialiser',
    'viewFitToView': 'Ajuster à la fenêtre',
    'viewResetView': 'Réinitialiser le zoom (100 %)',
    'panelSettings': 'Paramètres',
    'viewRotateLeft': 'Pivoter la vue à gauche',
    'viewRotateRight': 'Pivoter la vue à droite',
    'viewFlipHorizontal': 'Miroir horizontal',
    'viewFlipVertical': 'Miroir vertical',
    'viewStraighten': 'Redresser la vue (0°)',
    'viewZoomDrag': 'Zoom (glisser)',
    'viewAngleDrag': 'Angle de vue (glisser)',
    'valueTypeIn': 'Saisir la valeur',
    'viewCanvasColor': 'Couleur du canevas',
    'viewPasteboardColor': 'Couleur du fond',
    'pasteboardTitle': 'Fond',
    'pasteboardInUse': 'Utilisé',
    'pasteboardNotInUse': 'Inutilisé',
    'viewBackdropColor': 'Couleur de l\'arrière-plan',
    'colorUseCurrent': 'Utiliser la couleur actuelle',
    'colorNone': 'Aucune',
    'colorPresent': 'Présente',
    'tlSections': 'Sections',
    'tlAllDisplayedLayers': 'Tous les calques affichés',
    'tlShowAll': 'Tout afficher',
    'tlHideAll': 'Tout masquer',
    'tlSoloKind': 'Solo par type',
    'tlSoloColor': 'Solo par couleur',
    'tlSoloClips': 'Solo des calques écrêtés',
    'tlSoloFxOnRows': 'Solo des lignes avec FX',
    'tlSoloSheetOnRows': 'Solo des lignes sur la feuille',
    'tlApplyAllFx': 'Appliquer tous les FX',
    'tlBypassAllFx': 'Contourner tous les FX',
    'tlAllOnTimesheet': 'Tout mettre sur la feuille',
    'tlAllOffTimesheet': 'Tout retirer de la feuille',
    'tlClearMarkFilter': 'Effacer le filtre de repères',
    'tlClearAllClips': 'Libérer tous les masques d’écrêtage',
    'tlColVisibility': 'Colonne visibilité',
    'tlColLayerKind': 'Colonne type de calque',
    'tlColOnionSkin': "Colonne pelure d'oignon",
    'tlColOpacity': 'Colonne opacité',
    'tlColBlendMode': 'Colonne mode de fusion',
    'tlColFx': 'Colonne FX',
    'tlColMark': 'Colonne repère',
    'tlColClip': 'Colonne masque d’écrêtage',
    'tlColTimesheet': 'Colonne feuille de temps',
    'tlShowXSheet': "Afficher en feuille d'exposition",
    'tlShowTimeline': 'Afficher en timeline',
    'cameraViewOn': 'Vue caméra (activée)',
    'cameraViewOff': 'Vue caméra',
    'tlOpenOnionPanel': "Ouvrir le panneau pelure d'oignon",
    'tlApplyOnionToDisplayed': "Appliquer la pelure d'oignon aux calques affichés",
    'tlClearOnionOnDisplayed': "Retirer la pelure d'oignon des calques affichés",
    'tlOnionOnDisplayedToggle': "Pelure d'oignon des calques affichés (activer/désactiver)",
    'tlCollapseAllLayers': 'Replier tous les calques',
    'tlExpandAllLayers': 'Déplier tous les calques',
    'railLayerBlendMode': 'Mode de fusion du calque',
    'railFolderBlendMode': 'Mode de fusion du dossier',
    'railHideLayer': 'Masquer le calque',
    'railShowLayer': 'Afficher le calque',
    'railBypassLayerFx': 'Contourner les FX du calque',
    'railApplyLayerFx': 'Appliquer les FX du calque',
    'railBypassMixedLayerFx':
        'Contourner tous les FX du calque (certains sont désactivés)',
    'railBypassTrackFx': 'Contourner les FX de la piste',
    'railApplyTrackFx': 'Appliquer les FX de la piste',
    'railRemoveFromTimesheet': 'Retirer de la feuille',
    'railAddToTimesheet': 'Mettre sur la feuille',
    'railCollapseLanes': 'Replier les pistes',
    'railExpandLanes': 'Déplier les pistes',
    'railOnionSkinOn': "Pelure d'oignon (activée)",
    'railOnionSkin': "Pelure d'oignon",
    'railLaneGraphOn': 'Graphique (activé)',
    'railLaneGraph': 'Graphique',
    'railLanePinOn': 'Épinglé à tous les graphiques',
    'railLanePin': 'Épingler à tous les graphiques',
    'laneGraphValue': 'Valeur',
    'laneGraphSpeed': 'Vitesse',
    'laneGraphEnlarge': 'Agrandir',
    'laneGraphEnlargeOn': 'Agrandir (activé)',
    'laneGraphPen': 'Plume',
    'laneGraphPenOn': 'Plume (activée)',
    'laneGraphTransformBox': 'Boîte de transformation',
    'laneGraphTransformBoxOn': 'Boîte de transformation (activée)',
    'railClipOn': 'Masque d’écrêtage sur le calque inférieur (activé)',
    'railClip': 'Masque d’écrêtage sur le calque inférieur',
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
    'tlNoLayers': 'Aucun calque',
    'tlLegendLayer': 'CALQUE',
    'tlAllDisplayedOpacity': 'Opacité de tous les calques affichés',
    'tlLinkedWith': 'Lié à',
    'tlLayerReference': 'Référence',
    'tlReferenceSourceShort': 'Dépasse la source de {n} images',
    'tlSelectedLayers': 'Calques sélectionnés',
    'tlAudioGroup': 'Audio',
    'tlSoundVolume': 'Volume',
    'tlNameTagGroup': 'Étiquette',
    'tlReferenceGroup': 'Référence',
    'tlTransformGroup': 'Transformation',
    'tlLaneScale': 'Échelle',
    'tlLaneRotation': 'Rotation',
    'tlLanePosition': 'Position',
    'tlLaneOpacity': 'Opacité',
    'tlLaneAnchorPoint': "Point d'ancrage",
    'tlBypassLaneTemplate': 'Contourner {name}',
    'tlApplyLaneTemplate': 'Appliquer {name}',
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
    'tlKindAnimation': 'Animation',
    'tlKindStoryboard': 'Storyboard',
    'tlKindImage': 'Image',
    'tlKindAdjustment': 'Calque de réglage',
    'tlKindFolder': 'Dossier',
    'tlKindSe': 'SE',
    'tlKindTransition': 'Transition',
    'tlKindCamera': 'Camera',
    'tlKindSemanticTemplate': 'Calque {kind}',
    'tlKindInstruction': 'Direction',
    'tlNoriShiro': 'MARGE',
    'seNameTagShowLineLabel': 'Afficher le dialogue',
    'seNameTagLineInkLabel': 'Encre du dialogue',
    'seNameTagTrackingLabel': 'Interlettrage',
    'seNameTagSizeLabel': 'Taille',
    'seNameTagNameInkLabel': 'Encre du nom',
    'seNameTagBoxColorLabel': 'Couleur de la boîte',
    'seNameTagBoldLabel': 'Gras',
    'seNameTagItalicLabel': 'Italique',
    'seNameTagUnderlineLabel': 'Souligné',
    'seNameTagStrikethroughLabel': 'Barré',
    'seNameTagPreviewName': 'Nom',
    'seNameTagPreviewLine': 'Réplique',
    'shortcutAction.layer-attach-free-above': 'Calque attaché libre au-dessus',
    'shortcutAction.layer-attach-free-below': 'Calque attaché libre en dessous',
    'shortcutAction.layer-attach-synced-above':
        'Calque attaché synchronisé au-dessus',
    'shortcutAction.layer-attach-synced-below':
        'Calque attaché synchronisé en dessous',
    'tlLayerCommands': 'Commandes de calque',
    'tlFrameCommands': "Commandes d'image",
    'tlCut': 'Plan',
    'tlLayer': 'Calque',
    'tlFrame': 'Image',
    'tlKey': 'Clé',
    'shortcutAction.frame-select-row-span': 'Sélectionner toute la ligne',
    'linkWindowUnlink': 'Délier',
    'linkWindowUnlinkLinkedCut': "Les calques d'une coupe liée se délient avec la coupe",
    'tlResetGroup': 'Réinitialiser (garde les clés)',
    'tlEffects': 'Effets',
    'tlAddEffectTemplate': 'Ajouter {name}',
    'tlDropIntoFolderTemplate': 'dans {name}',
    'tlDropOutOfFolder': 'hors du dossier',
    'tlDropAttachSyncedTemplate': 'attacher à {name} (synchronisé)',
    'tlDropAttachFreeTemplate': 'attacher à {name} (libre)',
    'tlDropDetachAttach': 'détacher',
    'shortcutAction.layer-detach': 'Détacher de la base',
    'tlAttachDropsFxRows': 'Calques qui perdent leur fx',
    'tlAttachDropsFxTitle': 'Le fx sera perdu',
    'tlMergeChangesTitle': 'La fusion peut changer le rendu',
    'tlMergeChangesBody':
        'Le calque fusionné peut changer sur les calques en dessous.',
    'tlMergeChanges': 'Ce qui change',
    'tlMergeChangeBlend':
        'Un calque a son propre mode de fusion — le résultat sera Normal',
    'tlMergeChangeClip':
        'Un écrêtage relie un calque choisi à un calque non choisi',
    'tlMergeChangeFolder':
        "Le dossier du résultat s'applique à des calques venus d'ailleurs",
    'tlMergeChangeRiderOver':
        "Un calque attaché recouvrira d'autres dessins",
    'tlMergeChangeRiderUnder': "Un calque attaché passera sous d'autres dessins",
    'tlMergeChangeWall': 'Ce qui dépasse du fond est coupé',
    'tlAttachDropsFxBody':
        'Une couche attachée ne garde pas son propre fx. Continuer supprimera le fx existant. Continuer ?',
    'tlPush': 'Pousser (ouvrir des images)',
    'tlPull': 'Tirer (fermer des images)',
    'sbOneStoryboardRowPerCut':
        'Ce plan a déjà un calque storyboard. Un seul par plan.',
    'blockFrameLinesLabel': "Lignes d'image dans les blocs",
    'brDualBlend': 'Fusion double',
    'brTextureBrightness': 'Luminosité',
    'brTextureContrast': 'Contraste',
    'brTextureInvert': 'Inverser',
    'drawingCursorLabel': 'Curseur',
    'drawingCursorBrush': 'Brosse',
    'drawingCursorPen': 'Stylo',
    'drawingCursorCrosshair': 'Réticule',
    'mediaRelinkScanning': 'Lecture du dossier…',
    'mediaRelinkScanned': 'Dossier lu',
    'openProgressRunning': 'Ouverture…',
    'openProgressDone': 'Ouvert',
    'openWaitingCloudTemplate': 'Téléchargement depuis le cloud · {sec} s',
    'openWaitingStalledTemplate': 'Rien reçu depuis {sec} s',
    'prefsDisplay': 'Affichage',
    'uiScaleLabel': "Taille de l'interface",
    'unnamedMarkLabel': "Marque d'un bloc sans nom",
    // A label chip's short form: the English ones, which an animator reads
    // the same in any language (유저 2026-08-31 「업계 용어부분쪽 관련 말고는
    // 다 번역」) — written here so the table is whole; whether French takes
    // its own is fr-zh-strings-fall-back-to-english-Q1.
    'layerProcessAbbrev.paper': 'PAP',
    'layerProcessAbbrev.conte': 'SB',
    'layerProcessAbbrev.art': 'ART',
    'layerProcessAbbrev.layout': 'LO',
    'layerProcessAbbrev.rough-key': 'RK',
    'layerProcessAbbrev.key': 'KEY',
    'layerProcessAbbrev.inbetween': 'IB',
    'layerProcessAbbrev.finish': 'FIN',
    'layerReviseAbbrev.direction': 'DIR',
    'layerReviseAbbrev.animation-director': 'AD',
    'layerReviseAbbrev.chief-animation-director': 'CAD',
    'layerReviseAbbrev.director': 'DR',
    'layerReviseAbbrev.chief-director': 'CD',
    'layerReviseAbbrev.action-animation-director': 'AAD',
    'layerReviseAbbrev.inbetween-check': 'IBC',
    'layerReviseAbbrev.cell-check': 'CC',
    'cnHeadCut': 'PLAN',
    'cnHeadPicture': 'IMAGE',
    'cnHeadAction': 'ACTION',
    'cnHeadDialogue': 'DIALOGUE',
    'cnHeadSeconds': 'DURÉE',
    'cnCoverCuts': ' plans',
    'cnCoverArtist': 'Storyboard',
    'sheetPrintEpisode': 'Ép.',
    'sheetPrintTitle': 'Titre',
    'sheetPrintScene': 'Scène',
    'sheetPrintCut': 'Plan',
    'sheetPrintDuration': 'Durée',
    'sheetPrintName': 'Animateur',
    'sheetPrintPage': 'Feuille',
    'sheetPrintRepeat': 'RÉPÉT.',
    'sheetPrintHold': 'FIXE',
    'tlSetCommasN': 'Régler sur N commas',
    'tlSetCommaTemplate': 'Régler sur {n} comma',
    'tlProjectAudioRate': "Fréquence d'échantillonnage du projet",
    'tlShowSeRows': 'Afficher les lignes SE',
    'tlShowCameraRows': 'Afficher les lignes caméra',
    'shortcutAction.layer-storyboard': 'Calque storyboard',
    'setLengthAction': "Définir la durée d'exposition",
    'markEveryField': 'Intervalle',
    'frameCountEntryFrames': 'Images',
    'frameCountEntrySecondsPlusFrames': 'Secondes+images',
    'projectFpsTitle': 'Fréquence du projet',
    'projectFpsField': 'Images par seconde',
    'autoNameStartField': 'Numéro de départ',
  };

  static const _zhHansValues = <String, String>{
    'launchStageEngine': '启动引擎',
    'launchStagePlugins': '注册插件',
    'launchStageApp': '准备应用',
    'launchStageFirstFrame': '绘制首个画面',
    'launchNoticeTitle': '本版本说明',
    'launchNoticeDontShowAgain': '不再显示',
    'usageStatsSend': '发送使用统计',
    'usageStatsHelp':
        '开启后，会在打开应用时、使用期间每 55 分钟一次以及离开应用时，匿名发送“正在使用”，'
        '并附带操作系统及其版本、设备型号、应用版本号和应用语言。每天一次还会'
        '发送设备语言、最近 28 天内使用天数的区间（首次 / 1–2 天 / 3 天以上）以及四项设置'
        '（界面大小、强调色、自动保存、光标）。不会发送画作、项目、'
        '文件名、名称、您给设备起的名字等任何能识别您的信息。关闭后也会删除本设备上'
        '保存的记录。',
    'usageStatsTitle': '使用统计',
    'usageStatsAsk': '要发送使用统计吗？开启后将有助于 Anicel 的开发。',
    'usageStatsChangeLater': '可随时在偏好设置 ▸ 系统中更改。',
    'usageStatsDontSend': '不发送',
    'usageStatsDoSend': '发送',
    'firstRunTitle': '初始设置',
    'firstRunChangeLater': '可随时在偏好设置中更改。',
    'firstRunStart': '开始',
    'programLanguageLabel': '程序语言',
    'notationLanguageLabel': '标注语言',
    'programLanguageHelp': '菜单、面板与标签的语言。',
    'notationLanguageHelp': '打印在摄影表等提交物上的语言。',
    'noCutSelected': '未选择镜头',
    'noticeNoFrameHere': '此处没有帧',
    'noticeNothingToCut': '没有可剪切的内容',
    'noticeNoConteLayer': '该镜头没有分镜图层',
    'noticeLayerNotDrawable': '该图层不可绘制',
    'noticeLayerHidden': '该图层已隐藏',
    'noticeEditAttachOwner': '请编辑父图层',
    'commonCancel': '取消',
    'commonApply': '应用',
    'commonRefresh': '刷新',
    'commonClose': '关闭',
    'commonAffectedFiles': '相关文件',
    'commonNotice': '提示',
    'tlSharedColourEdit': '颜色编辑',
    'exportNoCuts': '此项目暂无可导出的镜头。',
    'exportQueueEmpty': '队列中没有任务',
    'exportPresetsEmpty': '没有预设',
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
    'recordMicOpenFailed': '无法打开麦克风 — 请检查偏好设置▸音频以及系统麦克风权限。',
    'recordMicPermissionDenied': '麦克风访问已关闭 — 请在设置中允许 Anicel 使用麦克风。',
    'recordMicNotAllowed': '未允许使用麦克风 — 请在偏好设置▸音频中打开「允许麦克风」。',
    'recordTakeClipped': '录音发生削波 — 块上的红角为标记。',
    'recordClipMarkerTooltip': '该录音已削波（电平过高）',
    'tlTransitionCrossingWarning': '超出镜头边界 — 未应用',
    'tlTransitionCutOl': '镜头 O.L',
    'audioMicGainLabel': '麦克风增益（dB）',
    'audioInputChannelLabel': '输入声道',
    'audioInputChannelDevice': '按设备',
    'audioInputChannelMonoMix': '单声道混合',
    'audioInputChannelLeft': '仅左声道',
    'audioInputChannelRight': '仅右声道',
    'audioClippingNoticeLabel': '削波警告（提示+块标记）',
    'audioDenoiseLabel': '降噪（仅人声 — 录拟音时请关闭）',
    'audioInputMeterLabel': '输入电平',
    'audioMicrophoneAllowedLabel': '允许麦克风',
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
    'audioMute': '静音',
    'audioSolo': '独奏',
    'fpsAudioTitleTemplate': '{from} → {to}：声音怎么办？',
    'fpsAudioBody':
        '这两个帧率的实际速度相差 0.1%，而声音存在于真实时间中 — 无法同时保持帧精确与时间精确。\n\n• 保持音频时间：声音保持真实秒数；帧位置漂移 0.1%（约每 42 秒一帧）。\n\n• 拉伸音频 0.1%：按精确的 pulldown 比例重采样（听不出的音高变化 — 电视电影的标准做法），每个声音保持其精确的帧范围。',
    'fpsAudioKeep': '保持音频时间',
    'fpsAudioPull': '拉伸音频 0.1%',
    'feedbackTextOnly': '仅文字',
    'feedbackWithFiles': '附截图 / 视频（需登录 Google）',
    'selectionClosePolygon': '闭合形状',
    'selectionInvert': '反选到画布之外',
    'selectionInvertInCanvas': '在画布内反选',
    'toolSelectionMode': '模式',
    'commonSave': '保存',
    'commonDelete': '删除',
    'commonAdd': '添加',
    'commonRename': '重命名',
    'commonLink': '链接',
    'commonPreview': '预览',
    'windowTitleTemplate': '{action}（{target}）',
    'editNameAction': '编辑名称',
    'editNoteAction': '编辑备注',
    'renameLayerEmpty': '图层名称不能为空。',
    'renameCutField': '镜头名称',
    'renameCutEmpty': '镜头名称不能为空。',
    'renameGuideTitle': '重命名参考线',
    'renameGuideField': '参考线名称',
    'renameGuideEmpty': '参考线名称不能为空。',
    'deleteLayerTitle': '删除图层',
    'deleteLayersMessage': '要删除下列图层吗？',
    'deleteLayersHeading': '要删除的图层',
    'deleteEffectsHeading': '要删除的效果',
    'frameNameConflictTitle': '帧名称已存在',
    'frameNameConflictBody':
        '列表中的帧将使用同一图层中另一帧已在使用的名称。是否链接到使用该名称的帧？'
        '链接后相同名称共用同一张原画，列表中各帧的原画将被舍弃。',
    'linkedPasteConflictBody':
        '列表中的帧已在使用要粘贴的帧所带的名称。是否将粘贴的块链接到这些帧？'
        '链接后相同名称共用同一张原画：粘贴的块显示列表中的帧，复制来的原画不会带入。',
    'frameNameConflictListHeading': '要链接的帧',
    'seInstanceNewTitle': '新建 SE',
    'seInstanceEditTitle': '编辑 SE',
    'seNameLabel': '名称（说话者 — 留空则隐藏名条）',
    'seTypeLabel': '类型',
    'seDialogueLabel': '台词',
    'seDialogueOffsetLabel': '台词偏移',
    'seKomaPerGlyphLabel': '每字帧数',
    'seLinkedAudioLabel': '已链接音频',
    'seLinkedAudioNone': '无',
    'seUnlinkAudio': '解除链接',
    'keySideIncoming': '进入',
    'keySideOutgoing': '离开',
    'keySideKind.linear': '线性',
    'keySideKind.ease': '缓动',
    'keySideKind.fast': '快速',
    'keySideKind.auto': '平滑',
    'keySideKind.hold': '保持',
    'keyEaseInfluence': '影响',
    'keyPath': '路径',
    'keyPathKind.linear': '线性',
    'keyPathKind.bezier': '贝塞尔曲线',
    'keyPathKind.continuousBezier': '连续贝塞尔曲线',
    'keyPathKind.autoBezier': '自动贝塞尔曲线',
    'keyRoving': '漂浮',
    'keySideIncomingHelp':
        '值进入此关键帧的方式。线性：匀速 · 缓动：减速进入 · 快速：加速进入 · 平滑：按前后关键帧接续速度。影响：变化占区间的多少。',
    'keySideOutgoingHelp':
        '值离开此关键帧的方式。线性：匀速 · 缓动：缓慢出发 · 快速：迅速出发 · 平滑：按前后关键帧接续速度 · 保持：值保持到下一个关键帧。影响：变化占区间的多少。',
    'keyPathHelp':
        '位置经过此关键帧的路径形状。线性：在关键帧处转折 · 贝塞尔曲线：前后手柄各自的方向 · 连续贝塞尔曲线：两个手柄连成一条直线 · 自动贝塞尔曲线：按前后关键帧平滑弯曲。',
    'keyRovingHelp':
        '关键帧保留其在路径上的位置，交出时间：在前后保有时间的关键帧之间，自动移到速度均匀的帧（After Effects 的 Rove Across Time）。第一个和最后一个关键帧不会漂浮。',
    'cameraPath': '摄影机路径',
    'cameraPathOff': '关',
    'cameraPathSpace': '空间',
    'cameraPathSpaceTime': '空间＋时间',
    'cameraPathAllKeys': '全部关键帧',
    'cameraPathAroundPlayhead': '播放头附近',
    'cameraPathTickEvery': '点间隔',
    'cameraPathAround': '前后',
    'convertLinkedCutTitle': '转换为链接镜头',
    'convertLinkedCutBodyTemplate': '将“{cut}”（原本）与另一个镜头链接。同名图层会合并为一张共用画面。',
    'convertLinkedCutTargetLabel': '链接的镜头',
    'convertLinkedCutLinksHeading': '链接的图层',
    'convertLinkedCutReplacedTemplate': '“{cut}”中的同名原画将被原本的替换（원본 승리）。',
    'convertLinkedCutReplacedHeading': '被替换的原画',
    'convertLinkedCutJoiningTemplate': '{count} 张原画加入共用集合。',
    'convertLinkedCutTargetGainsHeadingTemplate': '添加到“{cut}”的图层',
    'convertLinkedCutOriginGainsHeading': '添加到本镜头的图层',
    'convertLinkedCutNothing':
        '没有可链接的内容 — 两个镜头已完全链接，'
        '或没有可共用的绘制图层。',
    'convertLinkedCutUndoNote': '撤销会还原此次转换涉及的所有镜头。',
    'convertLinkedCutResizeFirst':
        '两个镜头的画布尺寸不同。共用镜头共享同一张画，因此以原镜头的尺寸为准 '
        '— 建议先统一尺寸再进行更改。',
    'guideKindSymmetry': '对称',
    'guideKindPerspective': '透视',
    'guideDelete': '删除参考线',
    'guideShow': '在画布上显示',
    'guideActsOn': '正在作用于笔画',
    'guideActsOff': '未作用',
    'guideLibraryEmpty': '此镜头还没有参考线',
    'noGuideSelected': '未选择参考线',
    'guideLineCount': '份数',
    'guideMirrorMode': '轴对称',
    'guideMirrorModeOn': '副本左右翻转（真正的镜像）。',
    'guideMirrorModeOff': '副本只是旋转 — 不会翻转。',
    'guideEyeLevelShow': '显示视平线',
    'guideConstrainToEyeLevel': '将消失点固定在视平线上',
    'guideConstrainToEyeLevelNote': '对下一次拖动生效；不会移动已放置的。',
    'guideVanishingPoint': '消失点',
    'guideVanishingPointAtInfinity': '平行（无穷远）',
    'guideAddVanishingPoint': '新建消失点',
    'guideDeleteVanishingPoint': '删除消失点',
    'guideParallel': '平行',
    'guideParallelAngle': '角度',
    'guideLineDensity': '线条密度',
    'guideRasterize': '栅格化',
    'closeProjectTitle': '关闭项目？',
    'shortcutAction.file-new': '新建项目',
    'untitledProjectTab': '未命名 {n}',
    'fileOpenInAnotherTab': '该文件已在另一个标签页中打开。',
    'openNewerFormat': '此项目由更新版本的 Anicel 保存，无法打开。',
    'openOlderFormatTemplate':
        '此项目为格式 {saved}，无法打开（此 Anicel 从格式 {oldest} 起才能打开）。',
    'closeProjectBody': '你的更改尚未保存。仍要关闭吗？',
    'closeProjectVanishedBody':
        '此项目的文件已不在。现在关闭会一并失去只存在于该文件中的画稿。'
        '使用「另存为」可将当前仍打开的内容写入新文件。',
    'commonSaveAs': '另存为',
    'saveAsTitle': '另存为',
    'saveProgressRunning': '正在保存…',
    'saveProgressDone': '已保存',
    'savePrepareRunning': '正在准备…',
    'savePrepareDone': '准备完成',
    'saveStepKeepingLeftBehind': '正在暂存移除的媒体…',
    'saveStepCels': '正在写入赛璐珞…',
    'saveStepChecking': '正在校验要内嵌的文件…',
    'saveStepMedia': '正在写入媒体…',
    'saveStepConforms': '正在写入为播放转换的音频…',
    'saveStepFonts': '正在写入字体…',
    'saveStepCompacting': '正在填补文件中的空隙…',
    'saveStepHandingBack': '正在将文件交还给原文档…',
    'resizeProgressRunning': '正在调整尺寸…',
    'resizeProgressDone': '已调整尺寸',
    'bakeProgressRunning': '正在栅格化…',
    'bakeProgressDone': '栅格化完成',
    'rasterizeLeftReferences': '部分图层仍保留为参照。',
    'referenceWait.attached':
        '附属图层由其基底的变换放置，移动的参照无法变成它自己的关键帧。'
        '解除附属即可栅格化。',
    'referenceWait.laidAsFitted':
        '此文件由旧版本按适配尺寸放置，移动的参照无法变成关键帧。'
        '重新放置文件即可栅格化。',
    'referenceWait.sheared':
        '在只拉伸一个轴的缩放下，非 90° 倍数的旋转无法用变换绘制。'
        '统一缩放或按 90° 旋转即可栅格化。',
    'referenceWait.othersKeepKeys':
        '共用此变换开关的另一个图层在关闭期间保留了自己的关键帧，'
        '打开开关会显示它们。先打开变换即可栅格化。',
    'referenceWait.usesApart':
        '链接的图层在不同位置显示同一张赛璐珞的画面，'
        '一张赛璐珞只能放在一个位置。将参照对齐到同一位置即可栅格化。',
    'pasteProgressRunning': '粘贴中…',
    'pasteProgressDone': '已粘贴',
    'unsavedAutosaveTitle': '保存你的项目',
    'unsavedAutosaveBody':
        '此项目从未保存过，自动保存没有可写入的位置。选择一个文件后，'
        '自动保存就会开始守护它。',
    'commonNotNow': '暂不',
    'topStripProject': '项目',
    'topStripSettings': '设置',
    'menuPlay': '播放',
    'menuPause': '暂停',
    'shortcutAction.file-open': '打开文件',
    'shortcutAction.file-open-folder': '打开文件夹',
    'shortcutAction.file-export': '导出',
    'menuAction.edit-undo': '撤销',
    'menuAction.edit-redo': '重做',
    'menuAction.edit-copy-frame': '复制帧',
    'menuAction.edit-paste-linked-frame': '粘贴链接帧',
    'menuAction.edit-new-drawing': '在此帧新建原画',
    'menuAction.edit-delete-cell': '删除单元格',
    'menuAction.edit-cut-exposure': '剪切曝光',
    'menuAction.edit-toggle-mark': '切换标记',
    'shortcutAction.edit-keyboard-shortcuts': '键盘快捷键',
    'shortcutAction.edit-preferences': '偏好设置',
    'shortcutAction.work-settings': '作品设置',
    'menuAction.file-save-as': '项目(.anicel)',
    'menuAction.project-settings': '项目设置',
    'shortcutAction.cut-create-linked': '创建链接镜头',
    'shortcutAction.cut-convert-linked': '转换为链接镜头',
    'shortcutAction.cut-canvas-size': '画布尺寸',
    'menuAction.cut-delete': '删除镜头',
    'menuAction.layer-add': '新建图层',
    'menuAction.layer-link-duplicate': '链接复制图层',
    'menuAction.layer-unlink': '取消图层链接',
    'menuAction.layer-group-into-folder': '编组到文件夹',
    'menuAction.layer-rename': '重命名图层',
    'shortcutAction.layer-rasterize': '栅格化图层',
    'menuAction.layer-se-name-tag': 'SE 名字条',
    'menuAction.layer-copy': '复制图层',
    'menuAction.layer-paste': '粘贴图层',
    'menuAction.layer-delete': '删除图层',
    'menuAction.playback-stop': '停止',
    'menuAction.playback-play-all': '播放所有镜头',
    'menuAction.window-panels': '面板',
    'shortcutAction.window-tool-rail-right': '工具条在右侧',
    'shortcutAction.window-region-on-top': '时间轴区域置顶',
    'shortcutAction.window-brush-values-on-strip': '画笔数值放在顶部栏',
    'shortcutAction.window-full-screen': '全屏',
    'shortcutAction.window-region-fold': '折叠 / 展开时间轴区域',
    'shortcutAction.window-reset-layout': '重置工作区布局',
    'menuAction.edit-debug': '调试',
    'shortcutAction.edit-input-inspector': '输入检查器',
    'shortcutAction.edit-frame-timing-overlay': '帧时序叠加',
    'shortcutAction.edit-frame-stats': '帧统计',
    'shortcutAction.edit-show-repaints': '显示重绘',
    'menuAction.edit-knee-at-one': '屏幕分辨率缓冲区',
    'menuAction.edit-show-unpainted-tiles': '显示未绘制的图块',
    'shortcutAction.help-about': '关于 Anicel',
    'shortcutAction.help-send-feedback': '发送反馈',
    'fileOpenTitle': '打开项目',
    'fileStorageOffNotice': '存储访问已关闭 — 应用文件夹之外的项目需要"所有文件"权限。',
    'fileOpenSettings': '打开设置',
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
    'folderPickDriveNoticeAndroid':
        'Google 云端硬盘无法提供文件夹。请使用本设备上的文件夹 — 同步应用'
        '（Autosync 等）可以把云端硬盘文件夹放到本设备上。',
    'recentProjectsTitle': '最近的项目',
    'recentReconnect': '重新连接',
    'sortAscending': '升序',
    'canvasSizeTitle': '画布尺寸',
    'cameraSizeTitle': '摄影机尺寸',
    'canvasWidthLabel': '宽度（px）',
    'canvasHeightLabel': '高度（px）',
    'canvasSizePresets': '预设',
    'canvasAdjustOnCanvas': '在画布上调整',
    'cameraRatioFree': '自由',
    'cameraRatioCurrent': '当前比例',
    'commonResize': '调整尺寸',
    'inputPressureCurve': '压感曲线',
    'inputCanvasHeading': '画布',
    'inputRightClick': '右键 / 笔侧键',
    'inputWheelClick': '滚轮点击 / 笔上键',
    'inputPenTail': '笔尾（把笔倒过来）',
    'inputCanvasTouchHeading': '画布触摸',
    'inputIgnoreTouch': '忽略所有触摸',
    'inputDragOneFinger': '单指拖动',
    'inputDragTwoFingers': '双指拖动',
    'inputDragThreeFingers': '三指拖动',
    'inputExtraFinger': '加指修饰键',
    'inputExtraFingerHelp': '手势进行中再加一根手指会约束它 — 缩放/旋转/画笔大小吸附，逐帧微调。',
    'inputStrokeFinger': '手指笔画修饰键',
    'inputStrokeFingerHelp': '绘制时另一根手指按在屏幕上，笔画会锁定到最近的45°方向（与Shift相同）。',
    'inputFlipHaptics': '翻页震动',
    'inputFlipHapticsHelp': '每当翻页落到另一张画上时轻震一下。空白处不震动，没有马达的设备也不会。',
    'inputTwoFingerRotation': '双指旋转',
    'inputTwoFingerRotationHelp': '关闭：导航手势只做平移和缩放（旋转按钮与快捷键保留）。',
    'inputRotationLock': '修饰键锁定旋转',
    'inputRotationLockHelp': '开启：额外的手指会冻结角度（纯平移 + 吸附缩放）。关闭（默认）：吸附角度。',
    'inputRotationSnap': '旋转吸附',
    'inputZoomSnaps': '缩放吸附（%）',
    'inputZoomCeiling': '锁定最大缩放（%）',
    'inputTabletHeading': '数位板服务',
    'inputTabletStandard': '标准（默认）',
    'inputTabletStandardHelp': '系统指针通道（Windows Ink）— 适合新版驱动和内置笔。',
    'inputTabletWintab': 'Wintab',
    'inputTabletWintabHelp': '直接从数位板驱动读取压感 — 当笔没有压感或被识别为触摸/鼠标时的退路。',
    'inputTabletAutoDemoted': '已切回 Standard：在 Wintab 通道下，笔完全无法到达窗口。',
    'dragActionFlip': '翻页（帧 / 图层）',
    'dragActionScreen': '画面（平移·缩放·旋转）',
    'dragActionBrushSize': '画笔大小',
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
    'memoryItemLayerImages': '图层图像',
    'memoryItemFramePictures': '帧图像',
    'memoryItemBrushTips': '笔尖',
    'memoryItemPanelRasters': '面板栅格',
    'memoryItemViewerPages': '查看器页面',
    'memoryItemImageCache': '图像缓存',
    'memoryItemStoryboardThumbnails': '分镜缩略图',
    'memoryItemSheetImages': '纸面图像',
    'memoryItemTextImages': '文字图像',
    'memoryItemStrokePreviews': '笔画预览',
    'memoryItemTimelineTiles': '时间轴图块图像',
    'memoryItemMoviePictures': '引用视频',
    'memoryItemTileImages': '画布图块图像',
    'memoryItemEnginePool': '绘图引擎图块池',
    'memoryItemEngineScratch': '绘图引擎工作缓冲区',
    'memoryOutsideAllowanceTemplate': '配额之外（无法设上限）：{items}',
    'containerAreaSettings': '设置',
    'containerAreaDiagnostics': '诊断日志',
    'containerAreaSessionScratch': '会话暂存区',
    'containerTotal': '合计',
    'saveCelsLostTemplate': '已保存，但有 {count} 张画面未能包含：存放它们的项目文件在项目打开期间被删除了。',
    'saveCelsLostHeading': '相关画面',
    'saveCelsLostGone': '项目中已不存在的画面',
    'saveFailedTitle': '无法保存',
    'saveFailedFileInUse': '另一个程序（同步、杀毒软件或打开了此文件的应用）正在使用此文件，因此无法覆盖。',
    'saveFailedReadOnly': '此文件或其文件夹为只读，无法写入。',
    'saveFailedDiskFull': '保存位置的空间不足。',
    'saveFailedLocationGone': '无法访问保存位置——驱动器已移除、网络已断开，或文件夹已被删除。',
    'saveFailedReplaceRefused': '此位置（云端或“文件”应用）拒绝替换该文件。',
    'saveFailedUnknown': '写入文件时出错。',
    'saveFailedCopyKept':
        '目前的工作已保存在应用内的失败副本中。程序关闭后失败副本会消失——如需保留，请用“备份失败副本…”保存到您选择的位置。',
    'saveFailedNoCopy': '也无法写入失败副本——请用“另存为”保存到其他位置。',
    'saveFailedRetry': '排除原因后再次保存，即会保存到原文件。',
    'saveFailedDetailsHeading': '详细信息',
    'saveFailedCopyLineTemplate': '失败副本：{path}',
    'saveFailedErrorLineTemplate': '错误：{error}',
    'shortcutAction.file-back-up-failed-copy': '备份失败副本',
    'failedCopyPickTitle': '要备份的失败副本',
    'failedCopyVanishOnClose': '程序关闭后失败副本会消失。',
    'failedCopyBackingUp': '正在备份…',
    'failedCopyBackedUp': '已备份',
    'closeProjectFailedCopyBody':
        '此项目未能保存的工作只存在于应用内的失败副本中，程序关闭后失败副本会消失。如需保留，请使用“另存为”，或文件菜单中的“备份失败副本…”。',
    'projectFileVanished':
        '此项目的文件已不在原处 — 可能被删除或移动了。若还能从回收站恢复，请现在恢复：已保存过的画面只存在于该文件中。',
    'accent1Help': '用于选区、播放头和已启用的开关。',
    'sheetFormatTitle': '摄影表格式',
    'sheetFieldTitle': '标题',
    'sheetFieldEpisode': '集数',
    'sheetFieldScene': '场',
    'sheetFieldCut': '镜头',
    'sheetFieldTime': '时长',
    'sheetFieldName': '作画',
    'sheetFieldSheet': '表号',
    'workSettingsTitle': '作品设置',
    'workSettingsStaff': '人员设置',
    'workLogo': '公司标志',
    'workCover': '封面图',
    'staffWorker': '作业者',
    'sheetVisibleBoxes': '显示的栏位',
    'sheetStretchLineAction': '延长线 · ACTION',
    'sheetStretchLineCell': '延长线 · CELL',
    'sheetStretchLineHelp': '在 N 格以上的保持或 × 中，从第 (N+1) 格开始画线',
    'sheetStretchLineOn': '有',
    'sheetStretchLineOff': '无',
    'sheetSeEmptyFill': '无台词区间',
    'sheetLength': '摄影表长度',
    'sheetThreeSeconds': '3秒',
    'sheetSixSeconds': '6秒',
    'sheetFillOn': '置灰',
    'sheetFillOff': '留空',
    'sheetBrushAllow': '允许画笔',
    'conteCoverPage': '封面',
    'conteBlankPage': '空白页',
    'conteFormatTitle': '分镜用纸格式',
    'conteFrontIn': '包含',
    'conteFrontOut': '不含',
    'conteForm': '样式',
    'conteFormAnalog': '传统',
    'conteFormDigital': '数字',
    'conteOutline': '画面黑框',
    'conteOutlineOn': '有',
    'conteOutlineOff': '无',
    'envelopeFormatTitle': '卡袋版式',
    'envelopeForm': '样式',
    'sheetModeNotation': '标注表（重复·保持文字）',
    'sheetModeData': '数据表（与导出一致）',
    'instructionsTitle': '指示记号',
    'instructionEditTooltip': '编辑指示记号',
    'instructionDeleteTooltip': '删除指示记号',
    'instructionAddButton': '新建指示记号',
    'instructionDefTitle': '指示记号',
    'instructionDefNameLabel': '名称（FI、PAN 等）',
    'instructionEventEditTitle': '编辑指示',
    'instructionEventAddTitle': '新建指示',
    'instructionMarkLabel': '指示（记号）',
    'instructionMarkNone': '（无）',
    'instructionNameLabel': '名称（留空则用记号名）',
    'instructionStartLabel': '起点名称（A）',
    'instructionEndLabel': '终点名称（B）',
    'instructionEditSetButton': '编辑指示记号',
    'instructionEditorIcon': '图标',
    'instructionEditorColor': '颜色',
    'instructionEditorMark': '记号',
    'systemStatusHelp': '每个子系统当前运行的是哪一种实现。回退路径仍能让应用正常工作，但通常更慢 — 想了解细节可以按名称搜索。',
    'shortcutShelf.canvas': '画布',
    'shortcutShelf.tools': '工具',
    'shortcutShelf.toolTiles': '子工具',
    'shortcutShelf.blendModes': '混合模式',
    'shortcutShelf.selection': '选区',
    'shortcutShelf.edit': '编辑',
    'shortcutShelf.view': '视图',
    'shortcutShelf.timeline': '时间轴 · 分镜',
    'shortcutShelf.moves': '导航',
    'shortcutShelf.playback': '播放',
    'shortcutShelf.pills': '胶囊',
    'shortcutShelf.cutPill': '镜头胶囊',
    'shortcutShelf.layerPill': '图层胶囊',
    'shortcutShelf.framePill': '帧胶囊',
    'shortcutShelf.fxPill': 'FX胶囊',
    'shortcutShelf.sharedPill': '共用胶囊',
    'shortcutShelf.colourEdit': '颜色编辑',
    'shortcutShelf.layerHeader': '图层表头',
    'shortcutShelf.timelineBar': '时间轴栏',
    'shortcutShelf.toolLibrary': '工具库',
    'shortcutShelf.brushLibrary': '画笔库',
    'shortcutShelf.brushToolBrushes': '画笔工具的画笔',
    'shortcutShelf.eraserToolBrushes': '橡皮工具的画笔',
    'shortcutShelf.guides': '参考线',
    'shortcutShelf.texts': '文字',
    'shortcutShelf.topStrip': '顶部栏',
    'shortcutShelf.file': '文件',
    'shortcutShelf.settings': '设置',
    'shortcutShelf.panels': '面板',
    'shortcutShelf.debug': '调试',
    'shortcutShelf.inAPanel': '面板内',
    'shortcutShelf.media': '媒体',
    'shortcutShelf.timesheet': '摄影表',
    'shortcutShelf.conteSheet': '分镜用纸',
    'shortcutShelf.envelope': '卡袋',
    'shortcutShelf.palette': '色板',
    'shortcutPreset.clipStudio': '基于 CLIP STUDIO',
    'shortcutPreset.tvpaint': '基于 TVPaint',
    'shortcutAction.frame-previous': '上一帧',
    'shortcutAction.frame-next': '下一帧',
    'shortcutAction.drawing-previous': '上一个块',
    'shortcutAction.drawing-next': '下一个块',
    'shortcutAction.playback-toggle': '播放 / 暂停',
    'shortcutAction.playback-to-start': '回到开头',
    'shortcutAction.playback-loop-toggle': '循环 / 单次播放',
    'shortcutAction.canvas-pan-hold': '移动（按住）',
    'shortcutAction.canvas-rotate-hold': '旋转（按住）',
    'shortcutAction.canvas-line-hold': '从上一笔画直线（按住）',
    'shortcutAction.voice-record-toggle': '录音（开始/停止）',
    'shortcutAction.edit-undo': '撤销',
    'shortcutAction.edit-redo': '重做',
    'shortcutAction.tool-brush': '画笔工具',
    'shortcutAction.tool-eraser': '橡皮工具',
    'shortcutAction.tool-eyedropper': '吸管工具',
    'shortcutAction.tool-fill': '填充工具',
    'shortcutAction.tool-fill-bucket': '油漆桶',
    'shortcutAction.tool-text': '文字工具',
    'shortcutAction.tool-shape': '形状工具',
    'shortcutAction.tool-guide': '参考线工具',
    'shortcutAction.guide-add-symmetry': '新建对称参考线',
    'shortcutAction.guide-add-perspective': '新建透视参考线',
    'shortcutAction.timesheet-data-mode': '标注表 / 数据表',
    'shortcutAction.tool-select': '选择工具',
    'shortcutAction.tool-transform': '变换工具',
    'shortcutAction.tool-transform-normal': '普通变换',
    'shortcutAction.tool-transform-free': '自由变换',
    'shortcutAction.tool-transform-mesh': '网格变形',
    'shortcutAction.tool-cut': '裁剪工具',
    'shortcutAction.tool-cut-whole': '整体裁剪',
    'shortcutAction.tool-cut-stamp': '图章',
    'shortcutAction.selection-deselect': '取消选择',
    'shortcutAction.layer-up': '图层上移',
    'shortcutAction.layer-down': '图层下移',
    'shortcutAction.edit-confirm': '确认',
    'shortcutAction.selection-transform-cancel': '取消变换',
    'shortcutAction.transform-flip-horizontal': '变换水平翻转',
    'shortcutAction.transform-flip-vertical': '变换垂直翻转',
    'shortcutAction.transform-reset': '重置变换',
    'shortcutAction.cut-stamp-reset': '重置图章',
    'shortcutAction.onion-skin-toggle': '切换洋葱皮',
    'shortcutAction.camera-view-toggle': '切换摄影机视图',
    'shortcutAction.canvas-rotate-ccw': '画布视图向左旋转',
    'shortcutAction.canvas-rotate-cw': '画布视图向右旋转',
    'shortcutAction.canvas-flip-horizontal': '画布视图水平翻转',
    'shortcutAction.canvas-flip-vertical': '画布视图垂直翻转',
    'shortcutAction.canvas-straighten': '摆正画布视图',
    'shortcutAction.canvas-fit': '画布视图适应窗口',
    'shortcutAction.canvas-reset-view': '重置画布缩放（100%）',
    'shortcutAction.timeline-comma-1': '设为 1 格',
    'shortcutAction.timeline-comma-2': '设为 2 格',
    'shortcutAction.timeline-comma-3': '设为 3 格',
    'shortcutAction.timeline-comma-4': '设为 4 格',
    'shortcutAction.timeline-comma-n': '设为 N 格',
    'shortcutAction.frame-new-drawing': '新建帧',
    'shortcutAction.layer-add': '新建图层',
    'shortcutAction.frame-blank-exposure': '清空',
    'shortcutAction.frame-toggle-mark-one': '中间画标记1',
    'shortcutAction.frame-toggle-mark': '中间画标记2',
    'shortcutAction.frame-mark-every': '自动添加中间画标记',
    'shortcutAction.timeline-push-blocks': '推出（空出帧）',
    'shortcutAction.timeline-pull-blocks': '拉回（收拢帧）',
    'shortcutAction.timeline-zoom-in': '放大时间轴',
    'shortcutAction.timeline-zoom-out': '缩小时间轴',
    'shortcutAction.timeline-zoom-fit': '时间轴适合窗口',
    'shortcutAction.timeline-orientation-toggle': '时间轴 / 摄影表',
    'shortcutAction.edit-cut': '剪切',
    'shortcutAction.edit-copy': '复制',
    'shortcutAction.edit-paste-linked': '粘贴链接',
    'shortcutAction.edit-paste-independent': '粘贴独立',
    'shortcutAction.edit-unlink': '取消链接',
    'shortcutAction.edit-delete': '删除',
    'shortcutAction.edit-duplicate': '创建副本',
    'shortcutAction.edit-merge': '合并',
    'shortcutAction.edit-replace-colour': '替换颜色',
    'shortcutAction.edit-clear-pixels': '清空像素',
    'shortcutAction.edit-binarize': '二值化',
    'shortcutAction.edit-delete-colour': '删除颜色',
    'shortcutAction.edit-keep-colour': '保留颜色',
    'shortcutAction.edit-cut-pixels': '剪切像素',
    'shortcutAction.edit-copy-pixels': '复制像素',
    'shortcutAction.edit-paste-pixels-above': '粘贴像素到上方',
    'shortcutAction.edit-paste-pixels-below': '粘贴像素到下方',
    'shortcutAction.edit-instance': '编辑',
    'shortcutAction.edit-auto-name': '自动命名',
    'blendMode.passThrough': '穿透',
    'blendMode.normal': '正常',
    'blendMode.color': '正常',
    'blendMode.behind': '背后',
    'blendMode.erase': '擦除',
    'blendMode.darken': '变暗',
    'blendMode.multiply': '正片叠底',
    'blendMode.colorBurn': '颜色加深',
    'blendMode.lighten': '变亮',
    'blendMode.screen': '滤色',
    'blendMode.colorDodge': '颜色减淡',
    'blendMode.add': '线性减淡（添加）',
    'blendMode.overlay': '叠加',
    'blendMode.softLight': '柔光',
    'blendMode.hardLight': '强光',
    'blendMode.difference': '差值',
    'blendMode.exclusion': '排除',
    'blendMode.linearBurn': '线性加深',
    'blendMode.subtract': '减去',
    'blendMode.vividLight': '亮光',
    'blendMode.linearLight': '线性光',
    'blendMode.pinLight': '点光',
    'blendMode.hardMix': '实色混合',
    'blendMode.darkerColor': '深色',
    'blendMode.lighterColor': '浅色',
    'blendMode.divide': '划分',
    'blendMode.hue': '色相',
    'blendMode.saturation': '饱和度',
    'blendMode.chroma': '颜色',
    'blendMode.luminosity': '明度',
    'effectKind.brightnessContrast': '亮度和对比度',
    'effectKind.hueSaturation': '色相/饱和度',
    'effectKind.blur': '高斯模糊',
    'effectKind.directionalBlur': '定向模糊',
    'effectKind.radialBlur': '径向模糊',
    'effectKind.cameraLensBlur': '相机镜头模糊',
    'effectKind.colorKey': '颜色键',
    'effectKind.celNumber': '赛璐珞编号',
    'effectParameter.brightness': '亮度',
    'effectParameter.contrast': '对比度',
    'effectParameter.hue': '主色相',
    'effectParameter.saturation': '主饱和度',
    'effectParameter.lightness': '主亮度',
    'effectParameter.blurriness': '模糊度',
    'effectParameter.blurDimensions': '模糊方向',
    'effectParameter.repeatEdgePixels': '重复边缘像素',
    'effectParameter.direction': '方向',
    'effectParameter.blurLength': '模糊长度',
    'effectParameter.keyColor': '键色',
    'effectParameter.ink': '颜色',
    'effectParameter.tolerance': '容差',
    'effectParameter.amount': '数量',
    'effectParameter.keyOperation': '主要操作',
    'effectParameter.center': '中心',
    'effectParameter.type': '类型',
    'effectParameter.antialiasing': '抗锯齿',
    'effectParameter.blurRadius': '模糊半径',
    'effectParameter.irisShape': '形状',
    'effectParameter.irisRoundness': '圆度',
    'effectParameter.irisAspectRatio': '长宽比',
    'effectParameter.irisRotation': '旋转',
    'effectParameter.irisDiffractionFringe': '衍射条纹',
    'effectParameter.blurMapLayer': '模糊图图层',
    'effectParameter.blurMapChannel': '模糊图通道',
    'effectParameter.blurFocalDistance': '模糊焦距',
    'effectParameter.invertBlurMap': '反转模糊图',
    'effectParameter.highlightGain': '高光增益',
    'effectParameter.highlightThreshold': '高光阈值',
    'effectParameter.highlightSaturation': '高光饱和度',
    'effectParameter.useLinearWorkingSpace': '使用线性工作空间',
    'effectChoice.keyColors': '主色',
    'effectChoice.keepColors': '保持颜色',
    'effectChoice.horizontalAndVertical': '水平和垂直',
    'effectChoice.horizontal': '水平',
    'effectChoice.vertical': '垂直',
    'effectChoice.spin': '旋转',
    'effectChoice.zoom': '缩放',
    'effectChoice.best': '最佳',
    'effectChoice.draft': '草稿',
    'effectChoice.triangle': '三角形',
    'effectChoice.square': '正方形',
    'effectChoice.pentagon': '五边形',
    'effectChoice.hexagon': '六边形',
    'effectChoice.heptagon': '七边形',
    'effectChoice.octagon': '八边形',
    'effectChoice.nonagon': '九边形',
    'effectChoice.decagon': '十边形',
    'effectChoice.luminance': '明亮度',
    'effectChoice.red': '红色',
    'effectChoice.green': '绿色',
    'effectChoice.blue': '蓝色',
    'effectChoice.alpha': 'Alpha',
    'selectionMode.replace': '新选区',
    'selectionMode.add': '添加到选区',
    'selectionMode.subtract': '从选区减去',
    'selectionMode.intersect': '与选区交叉',
    'shortcutAction.file-save': '保存',
    'shortcutAction.file-save-as': '另存为',
    'shortcutAction.layer-visibility-solo': '独奏当前图层',
    'shortcutAction.canvas-zoom-in': '放大',
    'shortcutAction.canvas-zoom-out': '缩小',
    'cutCommands': '镜头命令',
    'shortcutAction.cut-new': '新建镜头',
    'shortcutAction.cut-edit-note': '编辑镜头备注',
    'shortcutAction.cut-settings': '镜头设置',
    'cutSettingsTitle': '镜头设置',
    'mediaActions': '媒体操作',
    'mediaPoolEmpty': '没有媒体',
    'mediaRename': '重命名媒体',
    'mediaPlace': '放置',
    'mediaRelink': '重新链接',
    'mediaMissingCount': '找不到 {n} 个媒体文件',
    'mediaFindInFolder': '在文件夹中查找',
    'mediaRelinkFound': '在 {n} 个中找到 {m} 个。要重新链接吗？',
    'mediaRemove': '删除媒体',
    'mediaRegisterInProject': '收入项目文件',
    'mediaExportWav': '导出为 WAV',
    'mediaExportWavNoAudio': '此素材没有可导出的音频。',
    'mediaCarriedState': '在项目内',
    'mediaReferencedState': '链接',
    'projectLegacyAssetsFolder':
        '此项目旁边仍有 {name} 文件夹。它已不再被写入 — 保存一次后，'
        '其中的媒体会进入项目文件，之后即可删除该文件夹。',
    'mediaRemoveInUse': '正在使用中。仍要删除吗？放置的图层/帧将被删除。',
    'mediaUsesHeading': '使用位置',
    'mediaOpenInViewer': '在查看器中打开',
    'mediaOpenInSubViewer': '在副查看器中打开',
    'mediaViewerEmpty': '暂无可查看的内容',
    'mediaViewerOpenFile': '打开文件',
    'mediaViewerCloseFile': '关闭文件',
    'mediaViewerLoadFailed': '无法读取此文件。',
    'mediaViewerCutTooLarge': '超出内存允许量，无法按原尺寸裁切。',
    'mediaViewerCannotDisplay': '此类媒体暂时无法查看。',
    'mediaViewerNoPdfRenderer': '此版本没有 PDF 渲染器 — 无法显示 PDF 页面。',
    'mediaViewerNoVideoDecoder': '此版本没有视频解码器 — 无法显示影片。',
    'mediaViewerNoAudioDecoder': '无法读取此声音 — 没有可显示的波形。',
    'mediaViewerSwap': '与另一个查看器互换',
    'unsupportedFileTitle': '不支持的文件',
    'unsupportedFileMessageTemplate': '检测到不支持的文件。可用格式：{kinds}。',
    'mediaViewerRegisterAsset': '添加到媒体',
    'panelMediaViewer': '查看器',
    'panelMediaViewerSub': '副查看器',
    'panelCanvas': '画布',
    'panelColorWheel': '色轮',
    'transportIn': '入点',
    'transportOut': '出点',
    'transportToStart': '回到开头',
    'transportToEnd': '跳到结尾',
    'transportLoop': '循环',
    'transportOnce': '播放一次',
    'transportPrevFrame': '上一帧',
    'transportNextFrame': '下一帧',
    'colorRecent': '最近',
    'colorBackgroundSwap': '背景色（点按交换）',
    'paletteViewCompact': '紧凑',
    'paletteViewCards': '卡片',
    'paletteNew': '新建调色板',
    'paletteNumberedTemplate': '调色板 {n}',
    'paletteMakeDefault': '设为默认',
    'paletteDuplicate': '复制',
    'paletteExport': '导出',
    'paletteBroughtTemplate': '已添加调色板“{name}”。',
    'paletteCopyTemplate': '{name} 副本',
    'paletteDeleteTitle': '删除调色板',
    'paletteDeleteTemplate': '要删除调色板“{name}”吗？',
    'paletteRemoveCurrent': '移除当前颜色',
    'paletteLock': '锁定调色板',
    'paletteMore': '更多',
    'penPressureTitle': '笔压',
    'brushDynamicsTitle': '响应',
    'curveSourcePressure': '笔压',
    'curveSourceTilt': '倾斜',
    'curveSourceSpeed': '速度',
    'curveSourceRandom': '随机',
    'curveMinimum': '最小值',
    'curveMaximum': '最大值',
    'curveTiltFlat': '水平',
    'curveTiltUpright': '垂直',
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
    'panelConte': '分镜用纸',
    'panelEnvelope': '卡袋',
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
    'onionBeforeTint': '之前色调',
    'onionAfterTint': '之后色调',
    'onionGhostColorHelp': '残影的着色方式',
    'onionPegCountHelp': '一格所计的单位',
    'onionPlacementHelp': '残影的位置',
    'onionStepBlocks': '块',
    'onionStepBlocksDrawings': '块（画面）',
    'onionStepFrames': '帧',
    'onionModeColors': '颜色',
    'onionModeImages': '画面',
    'onionPlacementOnTop': '最上层',
    'onionPlacementInPlace': '原位',
    'onionPegBeforeTemplate': '之前 {n}',
    'onionPegAfterTemplate': '之后 {n}',
    'shortcutTitle': '键盘快捷键',
    'shortcutResetAll': '全部重置',
    'shortcutFileImportedTemplate':
        '已将 {taken} 个快捷键导入新预设“{preset}”（{skipped} 个无对应）。',
    'shortcutPresets': '预设',
    'shortcutPresetNew': '新建预设',
    'shortcutPresetNameEmpty': '预设名称不能为空。',
    'shortcutPresetDelete': '删除预设',
    'shortcutPresetRename': '重命名预设',
    'shortcutPresetDuplicate': '复制预设',
    'shortcutPresetExport': '导出预设',
    'shortcutPresetBroughtTemplate': '已添加预设“{name}”。',
    'shortcutPresetCopyTemplate': '{name} 副本',
    'shortcutPresetDeleteTemplate': '要删除预设“{name}”吗？',
    'shortcutFileUnreadableTemplate': '{name}：此文件中没有可读取的快捷键。',
    'shortcutResetToDefault': '恢复默认',
    'shortcutUnassign': '移除快捷键',
    'shortcutRecordNew': '录制新快捷键',
    'shortcutTouch': '触摸快捷方式',
    'shortcutSearch': '搜索动作',
    'shortcutConflictBanner': '有动作共用同一按键 — 高亮的绑定发生冲突。',
    'shortcutRecordingHint': '请按键…（Esc 取消）',
    'playbackMode': '播放方式',
    'playbackModeSkipFrames': '跳帧',
    'playbackModeEveryPicture': '所有帧',
    'playbackModeRenderFirst': '播放前渲染',
    'playbackDroppedCount': '跳过{n}帧',
    'playbackDroppedCountOne': '跳过{n}帧',
    'playbackSilentCount': '{n}个音频无法播放',
    'playbackSilentCountOne': '{n}个音频无法播放',
    'playbackOutputRefused': '没有声音 — 无法打开输出设备。',
    'soundCannotPlay.missing': '无法播放 — 文件不存在。',
    'soundCannotPlay.notReadYet': '暂时无法播放 — 无法读取文件（云端副本可能仍在下载）。',
    'soundCannotPlay.format': '无法播放 — 没有能读取此格式的解码器。',
    'soundCannotPlay.conform': '无法播放 — 播放用的转换失败。',
    'soundCannotPlay.deviceRate': '无法播放 — 无法转换为输出的采样率。',
    'playbackStop': '停止',
    'sheetPreviousPage': '上一页',
    'sheetNextPage': '下一页',
    'sheetPageDrag': '页面（拖动）',
    'autosaveTitle': '自动保存',
    'autosaveEvery': '间隔',
    'autosaveSectionHelp':
        '每隔一段时间保存项目，崩溃或电量耗尽最多只损失这段时间的工作。',
    'autosaveSwitchHelp': '关闭后，项目只在保存时才会改变；一旦崩溃，此后的工作将全部丢失。',
    'appContainerTitle': '应用容器',
    'appContainerHelp':
        '应用保存在项目文件之外的内容：设置与笔尖、导入时带进来且尚未被任何一次保存吸收的媒体与音频，以及一份诊断日志。',
    'commonMinutesShort': ' 分钟',
    'exExport': '导出',
    'exAddToQueue': '加入队列',
    'exImage': '图像',
    'exVideo': '视频',
    'exCels': '赛璐珞',
    'exFormat': '格式',
    'exOptions': '选项',
    'exNaming': '命名',
    'exScope': '范围',
    'exQuality': '质量',
    'exCodec': '编解码器',
    'exBitrate': '码率',
    'exChannels': '声道',
    'exAudio': '音频',
    'exHandOverDeclined': '未交出，导出的结果已丢弃。',
    'exHandOverPending': '导出的结果尚未交出。',
    'exHandOverPickAgain': '重新选择',
    'exHandOverDiscard': '丢弃',
    'exSavePreset': '保存预设',
    'exPresetNameEmpty': '预设名称不能为空。',
    'exBaseName': '基础名称',
    'exSuffix': '后缀',
    'exPrefix': '前缀',
    'exLayDirection': '在此画上应用指示',
    'exLayGuides': '参考线',
    'exCelFormat': '赛璐珞格式',
    'exTimesheetFormat': '摄影表格式',
    'exEnvelopeFormat': '卡袋格式',
    'exWrittenCount': '{n}张',
    'exWrittenCountOne': '{n}张',
    'noticeExportNoPicture': '此赛璐珞没有已开启的画',
    'noticeExportNotPlaced': '此画未放在时间轴上',
    'noticeExportSameName': '同名的行已导出此画',
    'exDigits': '位数',
    'exApplyLayerFx': '图层 FX',
    'exMuxSeMix': '将 SE 混音封装进视频',
    'exLabel': '标签',
    'exApply': '应用',
    'exKinds': '导出种类',
    'exLayerFilter': '图层',
    'exSelBase': '基准',
    'exCelsLayersOut': '要导出的图层',
    'exSelAttach': '附属',
    'exSelSheet': '仅摄影表',
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
    'exStratumPaper': '用纸',
    'exStratumForm': '格式',
    'exStratumContent': '文字',
    'exStratumPicture': '画面',
    'exStratumInk': '墨水',
    'exLeftOutOfTheFile': '部分内容未能保存到文件中。',
    'exNoCels': '（无赛璐珞）',
    'exNoCuts': '（无镜头）',
    'exPresets': '预设',
    'exQueue': '队列',
    'exSize': '尺寸',
    'exCutSize': '镜头尺寸',
    'exRealSheet': '实际纸张',
    'imNotTvpp': '该文件无法作为 TVPaint 项目读取。',
    'imNotClip': '该文件无法作为 CLIP STUDIO PAINT 文件读取。',
    'imLeftBehind': '部分内容未能导入。',
    'imWarningCount': '{n} 条警告',
    'imWarningCountOne': '{n} 条警告',
    'imFileUnreadable': '无法读取该文件——如果文件在云端，请稍后重试。',
    'imNotFoundTemplate': '未找到：{path}',
    'importWarning.stagedCopy': '因无法就地读取，已通过临时副本打开——看到此提示请告知。',
    'importWarning.soundMissing': '此位置没有声音文件：{path}',
    'importWarning.celUnreadable': '{file}：无法读取该画面——{detail}',
    'importWarning.psdBitDepth': '{depth} 位文档已降为 8 位。',
    'importWarning.psdVectorMask': '{name}：已忽略矢量蒙版。',
    'importWarning.psdComposite': '合成图像使用压缩方式 {compression}——已跳过。',
    'importWarning.psdExtraChannels': '已忽略文档的额外通道。',
    'importWarning.psd32Bit': '不支持 32 位预测通道数据。',
    'importWarning.psdDuotone': '双色调按灰度读取。',
    'importWarning.psdMultichannel': '多通道按其第一个通道的灰度读取。',
    'importWarning.psdIndexedNoPalette': '无调色板的索引颜色按灰度读取。',
    'importWarning.psdCmyk': 'CMYK 在无配置文件的情况下转为 RGB——颜色会偏移。',
    'importWarning.psdLab': 'Lab 在无配置文件的情况下转为 RGB——颜色会偏移。',
    'importWarning.clippingNotApplied': '{name}：未应用剪贴蒙版。',
    'importWarning.layerEffectsNotApplied': '{name}：未应用图层效果。',
    'importWarning.layerMaskNotApplied': '{name}：未应用图层蒙版。',
    'importWarning.lockNotImported': '{name}：未导入锁定。',
    'importWarning.psdBlend': '{name}：混合模式“{mode}”没有对应项——已设为正常。',
    'importWarning.folderNothing': '该文件夹中没有可导入的赛璐珞或图片。',
    'importWarning.folderNoCutNumber': '文件夹名中找不到镜头编号。',
    'importWarning.tvpNoFile': '{name}：第 {frame} 帧的实例没有文件名——该赛璐珞保持为空。',
    'importWarning.tvpMuted': '{file}：该轨道处于静音——声音仍然链接。',
    'importWarning.tvpBlend': '{name}：混合模式“{mode}”在 Anicel 中没有对应项——按正常导入。',
    'importWarning.tvppHoldNoDrawing': '{name}：第 {frame} 帧的保持没有可承接的画。',
    'importWarning.tvppChunkBroken': '片段 {n}：块链在 @{at} 处中断——其后的数据被丢弃。',
    'importWarning.clipRead': '文件的一部分无法读取：{detail}',
    'importWarning.clipFps': '各时间轴的帧率不同——项目采用第一条时间轴的 {fps} fps。',
    'importWarning.clipUnplaced': '{name}：有 {count} 张赛璐珞不在任何时间轴上——未导入。',
    'importWarning.clipNoSuchCel': '{name}：有 {count} 个关键帧指向文件夹中不存在的赛璐珞。',
    'importWarning.clipCelLayers': '{name}：赛璐珞中的图层与其他赛璐珞同名的按名称、其余按从上往下的位置分成了行——各自的名称和文件夹不保留。',
    'importWarning.clipSpread': '{name}：在 {count} 张赛璐珞中，文件夹的不透明度或混合模式分给了其中的每个图层——图层重叠处看起来可能不同。',
    'importWarning.clipLineOrder': '{name}：在 {count} 张赛璐珞中，两个图层的叠放顺序与 CLIP STUDIO 相反——图层重叠处看起来可能不同。',
    'importWarning.clipVector': '{name}：矢量图层——已用圆头笔绘制；画笔的形状和质感未能保留。',
    'importWarning.clipVectorUnread': '{name}：{count} 条无法读取的矢量线——未绘制。',
    'importWarning.clipSound': '{name}：未导入声音图层。',
    'importWarning.clipSoundMissing': '{name}：文件中没有它的声音——不播放。',
    'importWarning.clipSoundSpeed':
        '{name}：CLIP STUDIO 以其他速度播放——这里按原速播放。',
    'importWarning.clipSoundVolume': '{name}：音量在片段中途变化——已设为片段开始时的音量。',
    'importWarning.clipCurve': '{name}：部分关键帧使用了无法读取的插值——其间按直线移动。',
    'importWarning.unsupportedLayerKind': '{name}：不支持此图层类型。',
    'importWarning.clipBlend': '{name}：混合模式 {mode} 没有对应项——已设为正常。',
    'importWarning.clipNotColour': '{name}：灰度或单色图层——未绘制。',
    'importWarning.clipTransform': '{name}：未应用图片的缩放或旋转。',
    'importWarning.clipTextUnread': '{name}：无法读取设置的文字——未导入。',
    'importWarning.clipTextAlign':
        '{name}：本应用无法排出的行对齐——按 CLIP STUDIO 绘制的样子显示，编辑后以统一的对齐重新排版。',
    'importWarning.clipTextSpacing':
        '{name}：行距不均——按 CLIP STUDIO 绘制的样子显示，编辑后以均匀行距重新排版。',
    'importWarning.clipTextDistorted':
        '{name}：变形的文字——按 CLIP STUDIO 绘制的样子显示，编辑后去掉变形重新排版。',
    'importWarning.clipTextSetHere':
        '{name}：由本应用排版的文字——文件中没有 CLIP STUDIO 绘制的图像，或无法读取。',
    'importWarning.brushPackUnreadable': '无法将此文件读取为 Anicel 画笔文件。',
    'importWarning.brushPackNotOurs': '此文件不是 Anicel 画笔文件。',
    'importWarning.brushPackNewer':
        '此画笔文件由更新版本的 Anicel 写入（格式 {version}）；此版本最多读取到 {readable}。',
    'importWarning.brushPackEmpty': '此画笔文件中没有画笔。',
    'importWarning.brushPackDamaged': '此画笔文件已损坏，无法读取。',
    'importWarning.abrTooShort': '文件太短，不是 ABR 文件。',
    'importWarning.abrOldVersion':
        '尚不支持 ABR 版本 {version}（Photoshop 6 时代）；请用新版 Photoshop 重新保存画笔。',
    'importWarning.abrUnknownVersion': '不支持的 ABR 文件（版本 {version}）。',
    'importWarning.abrCorruptSection': 'ABR 区段长度已损坏。',
    'importWarning.abrNoBrushes': '在 ABR 文件中未找到画笔。',
    'importWarning.abrNothingImportable': 'ABR 文件中没有可导入的画笔。',
    'importWarning.sutCannotOpen': '无法打开文件：{error}',
    'importWarning.sutUnreadable': '此文件不是可读取的 CLIP STUDIO 画笔（{error}）。',
    'importWarning.sutNoBrushData': '在此文件中未找到 CLIP STUDIO 画笔数据。',
    'importWarning.sutNothingImportable': '文件中没有可导入的画笔。',
    'fileType.anicel': 'Anicel 项目',
    'fileType.wav': 'WAV 音频',
    'fileType.anibrush': 'Anicel 画笔',
    'exclusionReason.processSubfolder': '工序子文件夹（存档）',
    'exclusionReason.unrecognized': '无法识别',
    'exclusionReason.excludedName': '被排除的名称',
    'exclusionReason.memoText': '备注文本',
    'exclusionReason.insertionLettersOff': '插入字母已关闭',
    'exFrameCount': '{n}帧',
    'exFrameCountOne': '{n}帧',
    'exPageCount': '{n}页',
    'exPageCountOne': '{n}页',
    'exFileCount': '{n}个文件',
    'exFileCountOne': '{n}个文件',
    'exJobCount': '{n}个任务',
    'exJobCountOne': '{n}个任务',
    'exContePageCount': '分镜稿{n}页',
    'exContePageCountOne': '分镜稿{n}页',
    'exCancelledAfterTemplate': '导出{count}后已取消。',
    'exCancelledVideoTemplate': '导出{count}后已取消（已保留部分视频）。',
    'exCancelled': '导出已取消。',
    'exDoneTemplate': '已导出{count}。',
    'exDoneSkippedTemplate': '已导出{count}（跳过{skipped}个空白）。',
    'exDoneFileTemplate': '已导出 {name}。',
    'exDoneVideoTemplate': '已导出视频（{count}）。',
    'exDoneConteDocumentTemplate': '已导出 {name}（{count}）。',
    'exNothingInFrame': '没有可导出的内容（空帧）。',
    'exFailedTemplate': '导出失败：{error}',
    'exQueueRestTemplate': '队列：已完成{count}{failed}{rest}。',
    'exQueueFailedTemplate': '，{n}个失败',
    'exQueueRestKept': '，其余保留',
    'exFileLabel': '文件',
    'exOrderAsksFirst': '先指定位置，再导出',
    'exOrderAsksAfter': '导出后再指定位置',
    'exSeMuxedTemplate': 'SE 已封装 · {codec}',
    'exVectorPdf': '矢量 PDF',
    'exFxOn': 'FX 开',
    'exFxOff': 'FX 关',
    'exFxBasic': 'FX 仅基础',
    'exFxBasicOnly': '仅基础',
    'exTabSequence': '序列',
    'exSizeCamera': '摄影机',
    'exSizeCanvas': '画布',
    'exPageImage': '页面图像',
    'exSaveCurrent': '+ 保存当前设置',
    'exRenderQueue': '渲染队列',
    'exRenderAll': '全部渲染',
    'exJobQueued': '排队中',
    'exJobDone': '完成',
    'exJobFailed': '失败',
    'exJobCancelled': '已取消',
    'exJobTemplate': '任务 {id} · {tab}',
    'exIncludeAll': '全部',
    'exCutsIncludedTemplate': '{n} / {total} 个镜头',
    'exNeedsFfmpeg': '需要本机 PATH 中有 FFmpeg。',
    'exCheckingEncoders': '正在检查本机的编码器…',
    'exNotInThisBuild': '此版本尚不可用。',
    'exBitrateAuto': '自动',
    'exCanvasTemplate': '画布 {size}',
    'exCanvasPerCut': '画布（按镜头）',
    'imImport': '导入',
    'imFile': '文件',
    'imInto': '放入',
    'imFit': '适配',
    'imModified': '修改时间',
    'imSize': '大小',
    'imResolution': '分辨率',
    'imExcluded': '已排除',
    'imFolderAsOneCut': '镜头',
    'imFolderPerRow': '自定义',
    'imPlaceTitleTemplate': '放置 — {name}',
    'imModeKeep': '内嵌',
    'imModeReference': '链接',
    'imBake': '栅格化',
    'imOptions': '选项',
    'imPictureAndSound': '画面 + 声音',
    'imPictureOnly': '仅画面',
    'imSoundOnly': '仅声音',
    'imRunSpanTemplate': '{first}–{last}（{n}张）',
    'imRateTitleTemplate': '视频 {movie} · 项目 {project}',
    'imRateBodyTemplate': '将项目设为 {movie}？声音保持其时间。',
    'imRateKeepTemplate': '保持 {project}',
    'imRateTakeTemplate': '设为 {movie}',
    'commonOn': '开',
    'commonOff': '关',
    'imFitOriginal': '原始尺寸',
    'imFitContain': '保持比例拉伸',
    'imFitStretch': '忽略比例拉伸',
    'imIntoNewLayer': '新图层',
    'imIntoSeRow': 'SE 行',
    'imIntoRowCellTemplate': '{row} · 第{frame}格',
    'imIntoNewCut': '新镜头',
    'imPsdMerge': '合并图层',
    'imPsdExpand': '保留图层',
    'imNoSource': '未选择来源',
    'imFileCountTemplate': '{n} 个文件',
    'imStatusImporting': '正在导入…',
    'imStatusNothing': '没有导入任何内容。',
    'imStatusDone': '已导入',
    'imStepRecoding': '正在重新编码裁剪后的视频…',
    'imStepWritingSpan': '正在将裁剪的范围写入文件…',
    'imStepCarrying': '正在将文件内嵌到项目…',
    'imStepRasterizing': '正在栅格化为赛璐珞…',
    'imFolderGone': '该文件夹已不存在。',
    'imFolderUnreadableTemplate': '无法读取文件夹：{reason}',
    'imCutFolderUnreadable': '无法读取该文件夹。',
    'imUnreadableTemplate': '{name}：无法读取文件。',
    'imLacksPictureTemplate': '{name}：该文件没有第 {number} 张图片。',
    'imCorruptTemplate': '{name}：无法打开 — 文件已损坏或受密码保护。',
    'imPagesFailedTemplate': '{name}：{n} 页渲染失败 — 这些页保持空白。',
    'imFramesFailedTemplate': '{name}：{n} 帧解码失败 — 这些格保持空白。',
    'imNoPdfRendererTemplate': '{name}：此版本没有 PDF 渲染器。',
    'imCouldNotImportTemplate': '{name}：无法导入。',
    'imPsdNoLayersTemplate': '{name}：没有可展开的图层 — 请以合并方式导入。',
    'imKeepExplain': '项目文件以压缩方式保存这些文件；原文件保持不变。',
    'imReferenceExplain': '文件保留在原处，项目指向它们。',
    'mpFileMissing': '文件缺失 — 请重新链接',
    'mpInUseOnTimeline': '在时间线中使用',
    'mpNameEmpty': '媒体名称不能为空。',
    'exCameraTemplate': '摄影机 {size}',
    'toolBrush': '画笔',
    'toolEraser': '橡皮',
    'toolEyedropper': '吸管',
    'toolFill': '填充',
    'toolText': '文字',
    'toolShape': '形状',
    'textToolSelectedText': '所选文字',
    'textToolDeleteText': '删除文字',
    'textToolLetters': '字符',
    'textToolBox': '文本框',
    'textToolFont': '字体',
    'textToolSize': '大小',
    'textToolTracking': '字距',
    'textToolBold': '加粗',
    'textToolItalic': '倾斜',
    'textToolUnderline': '下划线',
    'textToolStrikethrough': '删除线',
    'textToolColor': '颜色',
    'textToolOutline': '描边',
    'textToolOutlineWidth': '描边粗细',
    'textToolAlign': '对齐',
    'textToolAlignLeft': '左',
    'textToolAlignCenter': '居中',
    'textToolAlignRight': '右',
    'textToolCentreAcross': '水平居中',
    'textToolCentreDown': '垂直居中',
    'textToolBoxWidth': '框宽度',
    'textToolWidthAuto': '自动',
    'textToolWidthFixed': '固定',
    'textToolLineHeight': '行距',
    'textToolLetterWidth': '水平缩放',
    'textToolSkew': '倾斜',
    'textToolBackground': '背景',
    'textToolIntoDrawing': '栅格化',
    'textToolWriting': '文字方向',
    'textToolWritingLines': '横排',
    'textToolWritingColumns': '竖排',
    'textToolAlignTop': '上',
    'textToolAlignBottom': '下',
    'textToolFontImport': '导入字体文件',
    'textToolFontDelete': '删除字体',
    'textToolFontsOfProject': '此项目的字体',
    'textToolFontsOfDevice': '此设备的字体',
    'textToolFontTakeOut': '从项目中移除',
    'textToolFontStaysOnThisDevice': '此字体不允许嵌入可编辑的文档，在其他设备上打开时会变成其他字体。',
    'textToolFontNotOnThisDevice': '此设备上没有该字体，因此以其他字体显示。',
    'textToolFontUnreadable': '无法将该文件读取为字体。',
    'textToolFontIsTheApps': '该字体已内置于应用中。',
    'textToolFontNotKept': '无法保存该字体。',
    'toolSelect': '选择',
    'toolTransform': '变换',
    'toolShapeFill': '形状填充',
    'toolCutNothingHeld': '尚未持有任何内容',
    'toolCutHoldingTemplate': '持有 {size} px',
    'toolLibraryEmpty': '没有可显示的内容',
    'toolCutPasteAtOrigin': '粘贴到原位置',
    'toolCutFlipHorizontal': '水平翻转',
    'toolCutFlipVertical': '垂直翻转',
    'toolCutRegisterTip': '注册为笔尖',
    'toolCutDeletesSource': '删除原图',
    'toolReadSource': '参考',
    'toolReadsEveryVisibleLayer': '所有可见图层',
    'brushSettingsTitle': '画笔设置',
    'toolShapeRect': '矩形',
    'toolShapeEllipse': '椭圆',
    'toolShapeLasso': '套索',
    'toolShapePolygon': '多边形',
    'toolShapeLine': '直线',
    'toolShapeSelectTemplate': '{shape}选择',
    'toolShapeCutTemplate': '{shape}裁剪',
    'toolShapeFillTemplate': '{shape}填充',
    'toolShapeDrawTemplate': '{shape}绘制',
    'shapeToolDraws': '绘制',
    'shapeToolStroke': '描边',
    'shapeToolFill': '填充',
    'shapeToolType': '类型',
    'shapeToolTypePlain': '普通',
    'shapeToolCorners': '边角',
    'shapeToolCornersSharp': '尖角',
    'shapeToolCornersRound': '圆角',
    'shapeToolRatioLock': '锁定比例',
    'brBrushesTitle': '画笔',
    'brGroupNameField': '组名称',
    'brCreate': '创建',
    'brRenameBrush': '重命名画笔',
    'brBrushNameField': '画笔名称',
    'brGroupNameEmpty': '组名称不能为空。',
    'brBrushNameEmpty': '画笔名称不能为空。',
    'brResetLibraryBody': '要用内置画笔替换整个库 — 包括每个组、导入的包和已保存的画笔吗？',
    'brSize': '大小',
    'brOpacity': '不透明度',
    'brFlow': '流量',
    'brMixing': '混色',
    'brMixingMethod': '方式',
    'brMixingMix': '与底色混合',
    'brMixingBlur': '模糊',
    'brPaintAmount': '颜料量',
    'brPaintDensity': '颜料浓度',
    'brColorStretch': '色彩延伸',
    'brHardness': '硬度',
    'stepUp': '增加一级',
    'stepDown': '减少一级',
    'brEdgeNone': '无',
    'brSpacing': '间距',
    'brAngle': '角度',
    'brRoundness': '圆度',
    'brScale': '缩放',
    'brScatter': '散布',
    'brScatterCount': '数量',
    'brScatterBothAxes': '双轴',
    'brTipRotation': '方向',
    'brRotationFixed': '无',
    'brRotationDirection': '线条方向',
    'brRotationPenTilt': '笔的方向',
    'brRotationPenTwist': '笔杆旋转',
    'brTipOrder': '重复方法',
    'brTipOrderRepeat': '重复',
    'brTipOrderPingPong': '往返',
    'brTipOrderHoldLast': '不重复',
    'brTipOrderRandom': '随机',
    'brTipOrderOneLap': '仅一轮',
    'brTipOrderShuffledLap': '随机一轮',
    'brTipOrderLean': '笔的倾斜',
    'brTipsPerTurn': '每轮笔尖数',
    'brBrushTip': '笔尖',
    'brTipNone': '无',
    'brDualTip': '双重笔尖',
    'brTexture': '纹理',
    'brTextureDensity': '浓度',
    'brTextureMode': '纹理合成',
    'brTextureModeHeight': '高度',
    'brAddTipImage': '从图像添加笔尖',
    'brRenameTip': '重命名笔尖',
    'brDeleteTip': '删除笔尖',
    'brDeleteTipBodyTemplate': '将从库中删除“{name}”。',
    'brStabilizer': '防抖',
    'brStabilizerOn': '应用防抖',
    'brStabilizerBySpeed': '按速度',
    'brBySpeedSlow': '慢',
    'brBySpeedFast': '快',
    'brPostCorrection': '后修正',
    'brPostBySpeed': '按速度调整',
    'brPostByViewScale': '按缩放调整',
    'brPostBezier': '贝塞尔曲线',
    'brSharpenCorners': '锐化拐角',
    'brGroupInk': '墨水',
    'brGroupTip': '笔尖',
    'brGroupMixing': '混色',
    'brGroupScattering': '散布',
    'brGroupTexture': '纹理',
    'brGroupCorrection': '修正',
    'brDetailTitle': '画笔详细设置',
    'brShowInPanel': '在面板中显示',
    'brHideFromPanel': '在面板中隐藏',
    'shortcutAction.frame-auto-create': '自动创建帧',
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
    'brFillBeyondCanvas': '填充到画布之外',
    'brOpenRegionsRefuse': '开放区域不会被填充',
    'brName': '名称',
    'brDisplay': '显示',
    'brTipIcon': '笔尖图标',
    'brStrokePreview': '笔画预览',
    'brBrushOptions': '画笔选项',
    'brNewGroup': '新建分组',
    'brNewGroupName': '新建分组',
    'brNewPresetName': '预设 {n}',
    'builtinBrush.builtin-basic-group': '基础',
    'builtinBrush.builtin-pencil-group': '铅笔',
    'builtinBrush.builtin-ink-group': '笔',
    'builtinBrush.builtin-dry-media-group': '干性画材',
    'builtinBrush.builtin-watercolor-group': '水彩',
    'builtinBrush.builtin-paint-group': '油画',
    'builtinBrush.builtin-airbrush-group': '喷枪',
    'builtinBrush.builtin-blend-group': '混色',
    'builtinBrush.builtin-texture-group': '纹理',
    'builtinBrush.builtin-decoration-group': '装饰',
    'builtinBrush.builtin-pencil': 'HB铅笔',
    'builtinBrush.builtin-soft-pencil': '2B铅笔',
    'builtinBrush.builtin-mechanical-pencil': '自动铅笔',
    'builtinBrush.builtin-hard-pencil': '2H铅笔',
    'builtinBrush.builtin-dark-pencil': '4B铅笔',
    'builtinBrush.builtin-colored-pencil': '彩色铅笔',
    'builtinBrush.builtin-coloring-pencil': '涂色彩铅',
    'builtinBrush.builtin-shading-pencil': '侧锋铅笔',
    'builtinBrush.builtin-rough-edge': '粗糙铅笔',
    'builtinBrush.builtin-ink-pen': '硬边圆',
    'builtinBrush.builtin-g-pen': 'G笔',
    'builtinBrush.builtin-maru-pen': '圆笔',
    'builtinBrush.builtin-brush-pen': '软笔',
    'builtinBrush.builtin-calligraphy': '书法',
    'builtinBrush.builtin-marker': '马克笔',
    'builtinBrush.builtin-kabura-pen': '镝笔',
    'builtinBrush.builtin-technical-pen': '针管笔',
    'builtinBrush.builtin-dry-ink': '枯墨',
    'builtinBrush.builtin-chalk-preset': '粉笔',
    'builtinBrush.builtin-charcoal': '炭笔',
    'builtinBrush.builtin-pastel': '色粉',
    'builtinBrush.builtin-crayon': '蜡笔',
    'builtinBrush.builtin-graphite-stick': '石墨条',
    'builtinBrush.builtin-watercolor': '水彩',
    'builtinBrush.builtin-analog-watercolor': '手绘水彩',
    'builtinBrush.builtin-wet-watercolor': '湿水彩',
    'builtinBrush.builtin-dense-watercolor': '浓水彩',
    'builtinBrush.builtin-flat-wash': '平涂',
    'builtinBrush.builtin-flat-bristle': '平头笔',
    'builtinBrush.builtin-gouache': '水粉',
    'builtinBrush.builtin-oil-brush': '油画笔',
    'builtinBrush.builtin-palette-knife': '调色刀',
    'builtinBrush.builtin-dry-brush': '干笔',
    'builtinBrush.builtin-airbrush': '喷枪',
    'builtinBrush.builtin-soft-brush': '柔边圆',
    'builtinBrush.builtin-grit-spray': '颗粒喷雾',
    'builtinBrush.builtin-blender': '混色笔',
    'builtinBrush.builtin-water-blend': '水晕',
    'builtinBrush.builtin-blending-stump': '纸笔',
    'builtinBrush.builtin-blur': '模糊',
    'builtinBrush.builtin-splatter-preset': '喷溅',
    'builtinBrush.builtin-stipple': '点画',
    'builtinBrush.builtin-sponge': '海绵',
    'builtinBrush.builtin-cloud': '云',
    'builtinBrush.builtin-concrete': '混凝土',
    'builtinBrush.builtin-grass': '草',
    'builtinBrush.builtin-sparkle': '闪光',
    'builtinBrush.builtin-snow': '雪',
    'builtinBrush.builtin-bubble': '泡泡',
    'builtinBrush.builtin-leaves': '树叶',
    'builtinTip.builtin-chalk': '粉笔',
    'builtinTip.builtin-splatter': '喷溅',
    'builtinTip.builtin-grain': '颗粒',
    'builtinTip.builtin-bristle': '鬃毛',
    'builtinTip.builtin-sponge': '海绵',
    'builtinTip.builtin-wet-blot': '湿晕',
    'builtinTip.builtin-star': '星形',
    'builtinTip.builtin-flake': '雪花',
    'builtinTip.builtin-ring': '圆环',
    'builtinTip.builtin-leaf': '叶子',
    'builtinTip.builtin-grass-clump': '草丛',
    'builtinTip.builtin-paper-grain': '纸纹',
    'builtinTip.builtin-canvas-weave': '画布纹',
    'builtinTip.builtin-cold-press': '冷压纸',
    'builtinTip.builtin-pencil-side': '铅芯侧面',
    'builtinTip.builtin-graphite-tooth': '铅笔纸纹',
    'builtinTip.builtin-color-clumps': '彩铅笔触',
    'builtinTip.builtin-pencil-face-0-0': '铅芯 1-1',
    'builtinTip.builtin-pencil-face-0-1': '铅芯 1-2',
    'builtinTip.builtin-pencil-face-0-2': '铅芯 1-3',
    'builtinTip.builtin-pencil-face-1-0': '铅芯 2-1',
    'builtinTip.builtin-pencil-face-1-1': '铅芯 2-2',
    'builtinTip.builtin-pencil-face-1-2': '铅芯 2-3',
    'builtinTip.builtin-pencil-face-2-0': '铅芯 3-1',
    'builtinTip.builtin-pencil-face-2-1': '铅芯 3-2',
    'builtinTip.builtin-pencil-face-2-2': '铅芯 3-3',
    'builtinTip.builtin-pencil-face-3-0': '铅芯 4-1',
    'builtinTip.builtin-pencil-face-3-1': '铅芯 4-2',
    'builtinTip.builtin-pencil-face-3-2': '铅芯 4-3',
    'builtinTip.builtin-pencil-face-4-0': '铅芯 5-1',
    'builtinTip.builtin-pencil-face-4-1': '铅芯 5-2',
    'builtinTip.builtin-pencil-face-4-2': '铅芯 5-3',
    'builtinTip.builtin-pencil-face-5-0': '铅芯 6-1',
    'builtinTip.builtin-pencil-face-5-1': '铅芯 6-2',
    'builtinTip.builtin-pencil-face-5-2': '铅芯 6-3',
    'builtinTip.builtin-pencil-crumb-0': '铅笔颗粒 1',
    'builtinTip.builtin-pencil-crumb-1': '铅笔颗粒 2',
    'builtinTip.builtin-pencil-crumb-2': '铅笔颗粒 3',
    'brRenameGroup': '重命名分组',
    'brDeleteGroup': '删除分组',
    'brDeleteEmptyGroupTemplate': '要删除空分组“{name}”吗？',
    'brDeleteGroupTemplateOne': '要删除“{name}”及其中的 1 个画笔吗？',
    'brDeleteGroupTemplate': '要删除“{name}”及其中的 {n} 个画笔吗？',
    'brRenameSelected': '重命名所选画笔',
    'brDeleteSelected': '删除所选画笔',
    'brSaveAsPreset': '将当前设置保存为预设',
    'brImportBrushes': '导入画笔（.abr、.sut、.sutg）',
    'brResetLibrary': '重置画笔库',
    'brExportSelected': '导出画笔',
    'brExportGroup': '导出画笔组',
    'brExportNothing': '这里没有可导出的画笔。',
    'fileExportPlaceUnchosenTemplate': '无法选择保存位置：{error}',
    'settingsExportedTemplate': '已导出“{name}”。',
    'settingsExportNotWrittenTemplate': '无法写入文件：{error}',
    'settingsExportAll': '导出全部设置',
    'settingsAllFileName': 'Anicel 设置',
    'settingsRowFrameCount': '帧数输入方式',
    'settingsRowWorkspaceLayout': '工作区布局',
    'imIntoSettings': '设置',
    'imSettingsGoInPlace': '放入“设置”的项目会替换当前设置，当前设置将丢失。',
    'imSettingsUnreadable': '无法读取',
    'brExportNotWrittenTemplate': '无法写入画笔文件：{error}',
    'brExportedOneTemplate': '已导出画笔“{name}”。',
    'brExportedManyTemplate': '已导出 {count} 个画笔。',
    'brExportFallbackName': '画笔',
    'brImportUnreadable': '无法将此文件读取为画笔文件。',
    'brImportPickFailedTemplate': '无法打开文件：{error}',
    'fontBroughtTemplate': '已将字体“{family}”导入此设备。',
    'brImportedOneTemplate': '已从“{file}”导入 1 个画笔。',
    'brImportedManyTemplate': '已从“{file}”导入 {count} 个画笔。',
    'brImportWarningsTemplate': '{summary}（{count} 项有警告）',
    'brTipUnreadable': '无法将该图像读取为笔尖。',
    'brTipNoShape': '该图像没有可用作笔尖的可见形状。',
    'brTipNotSaved': '无法保存该笔尖。',
    'brExpand': '展开',
    'trFlipHorizontal': '水平翻转',
    'trFlipVertical': '垂直翻转',
    'trPosition': '位置',
    'trScale': '缩放',
    'trScaleLink': '缩放联动',
    'trRotation': '旋转',
    'trAnchorPoint': '基准点',
    'trMeshColumns': '列数',
    'trMeshRows': '行数',
    'trMesh': '网格',
    'trFinish': '收尾',
    'commonReset': '重置',
    'viewFitToView': '适应窗口',
    'viewResetView': '重置缩放（100%）',
    'panelSettings': '设置',
    'viewRotateLeft': '视图向左旋转',
    'viewRotateRight': '视图向右旋转',
    'viewFlipHorizontal': '视图水平翻转',
    'viewFlipVertical': '视图垂直翻转',
    'viewStraighten': '摆正视图（0°）',
    'viewZoomDrag': '缩放（拖动）',
    'viewAngleDrag': '视图角度（拖动）',
    'valueTypeIn': '输入数值',
    'viewCanvasColor': '画布颜色',
    'viewPasteboardColor': '底板颜色',
    'pasteboardTitle': '底板',
    'pasteboardInUse': '使用',
    'pasteboardNotInUse': '不使用',
    'viewBackdropColor': '背景颜色',
    'colorUseCurrent': '使用当前颜色',
    'colorNone': '无',
    'colorPresent': '有',
    'tlSections': '区段',
    'tlAllDisplayedLayers': '所有显示的图层',
    'tlShowAll': '全部显示',
    'tlHideAll': '全部隐藏',
    'tlSoloKind': '按类型独奏',
    'tlSoloColor': '按颜色独奏',
    'tlSoloClips': '独奏剪贴图层',
    'tlSoloFxOnRows': '独奏已开 FX 的行',
    'tlSoloSheetOnRows': '独奏已上表的行',
    'tlApplyAllFx': '应用全部 FX',
    'tlBypassAllFx': '旁通全部 FX',
    'tlAllOnTimesheet': '全部放上摄影表',
    'tlAllOffTimesheet': '全部移出摄影表',
    'tlClearMarkFilter': '清除标记筛选',
    'tlClearAllClips': '释放所有剪贴',
    'tlColVisibility': '可见性列',
    'tlColLayerKind': '图层类型列',
    'tlColOnionSkin': '洋葱皮列',
    'tlColOpacity': '不透明度列',
    'tlColBlendMode': '混合模式列',
    'tlColFx': 'FX 列',
    'tlColMark': '标记列',
    'tlColClip': '剪贴列',
    'tlColTimesheet': '摄影表列',
    'tlShowXSheet': '以摄影表显示',
    'tlShowTimeline': '以时间轴显示',
    'cameraViewOn': '摄影机视图（开）',
    'cameraViewOff': '摄影机视图',
    'tlOpenOnionPanel': '打开洋葱皮面板',
    'tlApplyOnionToDisplayed': '对显示的图层应用洋葱皮',
    'tlClearOnionOnDisplayed': '清除显示图层的洋葱皮',
    'tlOnionOnDisplayedToggle': '显示图层的洋葱皮(开/关)',
    'tlCollapseAllLayers': '折叠所有图层',
    'tlExpandAllLayers': '展开所有图层',
    'railLayerBlendMode': '图层混合模式',
    'railFolderBlendMode': '文件夹混合模式',
    'railHideLayer': '隐藏图层',
    'railShowLayer': '显示图层',
    'railBypassLayerFx': '旁通图层 FX',
    'railApplyLayerFx': '应用图层 FX',
    'railBypassMixedLayerFx': '旁通全部图层 FX（部分已关闭）',
    'railBypassTrackFx': '旁通轨道 FX',
    'railApplyTrackFx': '应用轨道 FX',
    'railRemoveFromTimesheet': '移出摄影表',
    'railAddToTimesheet': '放上摄影表',
    'railCollapseLanes': '折叠轨道',
    'railExpandLanes': '展开轨道',
    'railOnionSkinOn': '洋葱皮（开）',
    'railOnionSkin': '洋葱皮',
    'railLaneGraphOn': '图表（开）',
    'railLaneGraph': '图表',
    'railLanePinOn': '已固定到所有图表',
    'railLanePin': '固定到所有图表',
    'laneGraphValue': '值',
    'laneGraphSpeed': '速度',
    'laneGraphEnlarge': '放大',
    'laneGraphEnlargeOn': '放大（开）',
    'laneGraphPen': '钢笔',
    'laneGraphPenOn': '钢笔（开）',
    'laneGraphTransformBox': '变换框',
    'laneGraphTransformBoxOn': '变换框（开）',
    'railClipOn': '用下一图层剪贴（开）',
    'railClip': '用下一图层剪贴',
    'tlLayerMark': '图层标记',
    'tlRepeat': '重复',
    'tlRepeatSelection': '重复所选',
    'tlNoLayers': '没有图层',
    'tlLegendLayer': '图层',
    'tlAllDisplayedOpacity': '所有显示图层的不透明度',
    'tlLinkedWith': '链接到',
    'tlLayerReference': '引用',
    'tlReferenceSourceShort': '超出素材{n}帧',
    'tlSelectedLayers': '所选图层',
    'tlAudioGroup': '音频',
    'tlSoundVolume': '音量',
    'tlNameTagGroup': '名字条',
    'tlReferenceGroup': '参照',
    'tlTransformGroup': '变换',
    'tlLaneScale': '缩放',
    'tlLaneRotation': '旋转',
    'tlLanePosition': '位置',
    'tlLaneOpacity': '不透明度',
    'tlLaneAnchorPoint': '锚点',
    'tlBypassLaneTemplate': '旁通{name}',
    'tlApplyLaneTemplate': '应用{name}',
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
    'tlKindAnimation': '动画',
    'tlKindStoryboard': '分镜',
    'tlKindImage': '图像',
    'tlKindAdjustment': '调整图层',
    'tlKindFolder': '文件夹',
    'tlKindSe': 'SE',
    'tlKindTransition': 'Transition',
    'tlKindCamera': 'Camera',
    'tlKindSemanticTemplate': '{kind}图层',
    'seNameTagShowLineLabel': '显示台词',
    'seNameTagLineInkLabel': '台词颜色',
    'seNameTagTrackingLabel': '字距',
    'seNameTagSizeLabel': '大小',
    'seNameTagNameInkLabel': '名字颜色',
    'seNameTagBoxColorLabel': '底框颜色',
    'seNameTagBoldLabel': '加粗',
    'seNameTagItalicLabel': '倾斜',
    'seNameTagUnderlineLabel': '下划线',
    'seNameTagStrikethroughLabel': '删除线',
    'seNameTagPreviewName': '名字',
    'seNameTagPreviewLine': '台词',
    // 🚨A TRADE TERM, not a general word (user 2026-08-12: 「현장용어만
    // 원어/영어로 두기로 하자」). ja/ko already transliterate it rather than
    // translate it — ディレクション / 디렉션 — so zh standing alone with 指示
    // was the odd one out, not the rule.
    'tlKindInstruction': 'Direction',
    'tlNoriShiro': '留白',
    'shortcutAction.layer-attach-free-above': '在上方添加自由附属图层',
    'shortcutAction.layer-attach-free-below': '在下方添加自由附属图层',
    'shortcutAction.layer-attach-synced-above': '在上方添加同步附属图层',
    'shortcutAction.layer-attach-synced-below': '在下方添加同步附属图层',
    'tlLayerCommands': '图层命令',
    'tlFrameCommands': '帧命令',
    'tlCut': '镜头',
    'tlLayer': '图层',
    'tlFrame': '帧',
    'tlKey': '关键帧',
    'shortcutAction.frame-select-row-span': '选择整行',
    'linkWindowUnlink': '取消链接',
    'linkWindowUnlinkLinkedCut': '链接镜头的图层只能随镜头一起取消链接',
    'tlResetGroup': '重置（保留关键帧）',
    'tlEffects': '效果',
    'tlAddEffectTemplate': '添加{name}',
    'tlDropIntoFolderTemplate': '移入 {name}',
    'tlDropOutOfFolder': '移出文件夹',
    'tlDropAttachSyncedTemplate': '附属到 {name}（同步）',
    'tlDropAttachFreeTemplate': '附属到 {name}（自由）',
    'tlDropDetachAttach': '解除附属',
    'shortcutAction.layer-detach': '解除附属',
    'tlAttachDropsFxRows': '将失去 fx 的图层',
    'tlAttachDropsFxTitle': '附属后将失去 fx',
    'tlMergeChangesTitle': '合并后外观可能会改变',
    'tlMergeChangesBody': '合并后的图层叠在下方图层上时可能看起来不同。',
    'tlMergeChanges': '会改变的内容',
    'tlMergeChangeBlend': '含有非正常的混合模式 — 合并后的图层为正常',
    'tlMergeChangeClip': '选中的图层与未选中的图层之间有剪贴关系',
    'tlMergeChangeFolder': '合并后图层所在文件夹的效果也会作用于来自文件夹外的图层',
    'tlMergeChangeRiderOver': '附属图层会盖住其他画面',
    'tlMergeChangeRiderUnder': '附属图层会被压到其他画面下面',
    'tlMergeChangeWall': '超出底板的部分会被裁掉',
    'tlAttachDropsFxBody': '附属图层不保留自身的 fx。继续将丢弃现有的 fx。要继续吗？',
    'tlPush': '推出（空出帧）',
    'tlPull': '拉回（收拢帧）',
    'sbOneStoryboardRowPerCut': '该镜头已有分镜图层，每个镜头只能有一个。',
    'blockFrameLinesLabel': '块内帧线',
    'brDualBlend': '双重混合',
    'brTextureBrightness': '亮度',
    'brTextureContrast': '对比度',
    'brTextureInvert': '浓度反转',
    'drawingCursorLabel': '光标',
    'drawingCursorBrush': '画笔',
    'drawingCursorPen': '钢笔',
    'drawingCursorCrosshair': '十字',
    'mediaRelinkScanning': '正在读取该文件夹…',
    'mediaRelinkScanned': '已读取文件夹',
    'openProgressRunning': '正在打开…',
    'openProgressDone': '已打开',
    'openWaitingCloudTemplate': '正在从云端下载 · {sec} 秒',
    'openWaitingStalledTemplate': '已有 {sec} 秒未收到数据',
    'prefsDisplay': '显示',
    'uiScaleLabel': '界面大小',
    'unnamedMarkLabel': '无名块的标记',
    'tlLayerMarkNone': '无标记',
    'tlLayerMarkSource': '素材',
    'tlLayerTake': '镜次',
    'tlLayerTakeNumber': '镜次 {n}',
    'layerProcess.paper': '用纸',
    'layerProcess.conte': '分镜',
    'layerProcess.art': '美术',
    'layerProcess.layout': '设计稿',
    'layerProcess.rough-key': '粗原画',
    'layerProcess.key': '原画',
    'layerProcess.inbetween': '中割',
    'layerProcess.finish': '上色',
    'layerProcessAbbrev.paper': '用纸',
    'layerProcessAbbrev.conte': '分镜',
    'layerProcessAbbrev.art': '美术',
    'layerProcessAbbrev.layout': 'LO',
    'layerProcessAbbrev.rough-key': '粗原',
    'layerProcessAbbrev.key': '原画',
    'layerProcessAbbrev.inbetween': '中割',
    'layerProcessAbbrev.finish': '上色',
    'layerRevise.direction': '演出',
    'layerRevise.animation-director': '作画监督',
    'layerRevise.chief-animation-director': '总作画监督',
    'layerRevise.director': '导演',
    'layerRevise.chief-director': '总导演',
    'layerRevise.action-animation-director': '动作作画监督',
    'layerRevise.inbetween-check': '中割检查',
    'layerRevise.cell-check': '赛璐珞检查',
    'layerReviseAbbrev.direction': '演出',
    'layerReviseAbbrev.animation-director': '作监',
    'layerReviseAbbrev.chief-animation-director': '总作监',
    'layerReviseAbbrev.director': '导演',
    'layerReviseAbbrev.chief-director': '总导演',
    'layerReviseAbbrev.action-animation-director': '动作',
    'layerReviseAbbrev.inbetween-check': '中检',
    'layerReviseAbbrev.cell-check': '赛检',
    'cnHeadCut': '镜头',
    'cnHeadPicture': '画面',
    'cnHeadAction': '内容',
    'cnHeadDialogue': '台词',
    'cnHeadSeconds': '秒',
    'cnCoverCuts': '个镜头',
    'cnCoverArtist': '分镜',
    'sheetPrintEpisode': '话数',
    'sheetPrintTitle': '标题',
    'sheetPrintScene': '场景',
    'sheetPrintCut': '镜头',
    'sheetPrintDuration': '时间',
    'sheetPrintName': '原画',
    'sheetPrintPage': '摄影表',
    'sheetPrintRepeat': '重复',
    'sheetPrintHold': '停格',
    'tlSetCommasN': '设为 N 格',
    'tlSetCommaTemplate': '设为 {n} 格',
    'tlProjectAudioRate': '项目音频采样率',
    'tlShowSeRows': '显示 SE 行',
    'tlShowCameraRows': '显示摄影机行',
    'shortcutAction.layer-storyboard': '分镜图层',
    'setLengthAction': '设置曝光长度',
    'markEveryField': '间隔',
    'frameCountEntryFrames': '帧数',
    'frameCountEntrySecondsPlusFrames': '秒+帧',
    'projectFpsTitle': '项目帧率',
    'projectFpsField': '每秒帧数',
    'autoNameStartField': '起始编号',
  };
}
