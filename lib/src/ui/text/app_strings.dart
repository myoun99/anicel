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
  const AppStrings._({
    required this.languageSettingsTitle,
    required this.programLanguageLabel,
    required this.notationLanguageLabel,
    required this.programLanguageHelp,
    required this.notationLanguageHelp,
    required this.noCutSelected,
    required this.pageLabel,
    required this.continuousLabel,
    required this.noticeNoFrameHere,
    required this.noticeLayerNotDrawable,
    required this.noticeNothingToTransform,
    required this.commonCancel,
    required this.commonApply,
    required this.commonRefresh,
    required this.commonClose,
    required this.exportNoCuts,
    required this.audioOffsetTitle,
    required this.audioOffsetHelp,
    required this.audioOffsetLabel,
    required this.audioUnitFrames,
    required this.audioDevicesTitle,
    required this.audioDevicesHelp,
    required this.audioOutputLabel,
    required this.audioInputLabel,
    required this.audioSystemDefault,
    required this.audioDeviceDefaultSuffix,
    required this.audioDeviceMissingSuffix,
    required this.audioSyncInspectorTitle,
    required this.recordVoiceTooltip,
    required this.recordVoiceStopTooltip,
    required this.recordMicOpenFailed,
    required this.recordMicPermissionDenied,
    required this.recordSelectSeLane,
    required this.recordTakeClipped,
    required this.recordClipMarkerTooltip,
    required this.audioMicGainLabel,
    required this.audioInputChannelLabel,
    required this.audioInputChannelDevice,
    required this.audioInputChannelMonoMix,
    required this.audioInputChannelLeft,
    required this.audioInputChannelRight,
    required this.audioClippingNoticeLabel,
    required this.audioDenoiseLabel,
    required this.audioInputMeterLabel,
    required this.audioTestSoundLabel,
    required this.audioCountInLabel,
    required this.audioCueBeepsLabel,
    required this.audioStreamerLabel,
    required this.recordNothingRecording,
    required this.recordTakeEmpty,
    required this.recordPlacementFailed,
    required this.recordDroppedFramesTemplate,
    required this.layerAudioTitle,
    required this.audioGainLabel,
    required this.audioPanLabel,
    required this.layerAudioPanHelp,
    required this.audioSolo,
    required this.audioUnsolo,
    required this.audioLayerAudioMenu,
    required this.audioClipGainMenu,
    required this.audioEnvelopeMenu,
    required this.audioFadesEqualPowerMenu,
    required this.audioFadesLinearMenu,
    required this.audioClipGainTitle,
    required this.audioEnvelopeTitle,
    required this.audioEnvelopeHelp,
    required this.audioEnvelopeFrameLabel,
    required this.audioEnvelopeGainPercentLabel,
    required this.audioEnvelopeAddKey,
    required this.fpsAudioTitleTemplate,
    required this.fpsAudioBody,
    required this.fpsAudioKeep,
    required this.fpsAudioPull,
    required this.selectionMoveConfirmTitle,
    required this.selectionMoveConfirmBody,
    required this.selectionMoveRevert,
    required this.selectionMoveApply,
  });

  final String languageSettingsTitle;
  final String programLanguageLabel;
  final String notationLanguageLabel;
  final String programLanguageHelp;
  final String notationLanguageHelp;

  /// The timeline/timesheet gap empty state.
  final String noCutSelected;

  /// The timesheet panel-frame position label: page view prints
  /// '`<pageLabel>` N'.
  final String pageLabel;

  /// The continuous-view position label.
  final String continuousLabel;

  /// R26 #35/#13 — the shared CURSOR NOTICES: every refused action says
  /// why, right where the user is looking.
  final String noticeNoFrameHere;
  /// R27 #16: the refusal is about the LAYER, not the section — the CAM
  /// section is no longer uniformly undrawable in the user's model.
  final String noticeLayerNotDrawable;
  final String noticeNothingToTransform;

  /// Shared dialog verbs — tabled once, reused by every dialog that
  /// adopts localization.
  final String commonCancel;
  final String commonApply;
  final String commonRefresh;
  final String commonClose;

  /// R27 #31: the export window's empty state — the project has no cuts
  /// at all (standing in a GAP is not this; that anchors on the first cut).
  final String exportNoCuts;

  // --- The audio program's UI (Preferences ▸ Audio, 2D + AUDIO-PRO R4) ---
  final String audioOffsetTitle;
  final String audioOffsetHelp;
  final String audioOffsetLabel;

  /// The A/V offset unit dropdown's frame entry ('ms' is universal).
  final String audioUnitFrames;
  final String audioDevicesTitle;
  final String audioDevicesHelp;
  final String audioOutputLabel;
  final String audioInputLabel;
  final String audioSystemDefault;

  /// Appended to a device name: '{name}{suffix}'.
  final String audioDeviceDefaultSuffix;
  final String audioDeviceMissingSuffix;
  final String audioSyncInspectorTitle;

  // --- Guide voice recording (AUDIO-PRO R5) ---
  final String recordVoiceTooltip;
  final String recordVoiceStopTooltip;
  final String recordMicOpenFailed;
  final String recordMicPermissionDenied;

  /// REC1-B: the armed-track refusal — recording needs an SE lane active.
  final String recordSelectSeLane;

  // --- Capture chain (REC1-D) ---
  final String recordTakeClipped;
  final String recordClipMarkerTooltip;
  final String audioMicGainLabel;
  final String audioInputChannelLabel;
  final String audioInputChannelDevice;
  final String audioInputChannelMonoMix;
  final String audioInputChannelLeft;
  final String audioInputChannelRight;
  final String audioClippingNoticeLabel;

  /// The RNNoise toggle (voice-only by design: dialogue ON, foley OFF).
  final String audioDenoiseLabel;
  final String audioInputMeterLabel;
  final String audioTestSoundLabel;

  // --- ADR cueing (REC1-E) ---
  final String audioCountInLabel;
  final String audioCueBeepsLabel;
  final String audioStreamerLabel;
  final String recordNothingRecording;
  final String recordTakeEmpty;
  final String recordPlacementFailed;

  /// '{count}' is replaced with the dropped-frame count.
  final String recordDroppedFramesTemplate;

  // --- Mix controls (AUDIO-PRO R1) ---
  final String layerAudioTitle;
  final String audioGainLabel;
  final String audioPanLabel;
  final String layerAudioPanHelp;
  final String audioSolo;
  final String audioUnsolo;
  final String audioLayerAudioMenu;
  final String audioClipGainMenu;
  final String audioEnvelopeMenu;
  final String audioFadesEqualPowerMenu;
  final String audioFadesLinearMenu;
  final String audioClipGainTitle;
  final String audioEnvelopeTitle;
  final String audioEnvelopeHelp;
  final String audioEnvelopeFrameLabel;
  final String audioEnvelopeGainPercentLabel;
  final String audioEnvelopeAddKey;

  // --- The fps-change audio notice (EXPORT-AUDIO ④) ---
  /// '{from}'/'{to}' are replaced with the rate labels.
  final String fpsAudioTitleTemplate;
  final String fpsAudioBody;
  final String fpsAudioKeep;
  final String fpsAudioPull;

  // --- The pending selection-move prompt (R17-①) ---
  final String selectionMoveConfirmTitle;
  final String selectionMoveConfirmBody;
  final String selectionMoveRevert;
  final String selectionMoveApply;

  static AppStrings of(AppLanguage language) => switch (language) {
    AppLanguage.en => _en,
    AppLanguage.ja => _ja,
    AppLanguage.ko => _ko,
    AppLanguage.fr => _fr,
    AppLanguage.zhHans => _zhHans,
  };

  static const _en = AppStrings._(
    languageSettingsTitle: 'Language Settings',
    programLanguageLabel: 'Program language',
    notationLanguageLabel: 'Notation language',
    programLanguageHelp: 'Menus, panels and labels.',
    notationLanguageHelp: 'What prints on the timesheet and exports.',
    noCutSelected: 'No cut selected',
    pageLabel: 'Page',
    continuousLabel: 'Continuous',
    noticeNoFrameHere: 'No frame here',
    noticeLayerNotDrawable: 'This layer cannot be drawn on',
    noticeNothingToTransform: 'Nothing to transform',
    commonCancel: 'Cancel',
    commonApply: 'Apply',
    commonRefresh: 'Refresh',
    commonClose: 'Close',
    exportNoCuts: 'This project has no cuts to export yet.',
    audioOffsetTitle: 'A/V offset',
    audioOffsetHelp:
        'Fine-tunes when the picture is shown relative to the sound. '
        'The measurable part of the delay is corrected automatically; '
        'this removes what remains — wireless headphones commonly sit '
        '150–300 ms behind and report nothing. Positive shows the '
        'picture LATER (sound arriving late is the common case).',
    audioOffsetLabel: 'Offset',
    audioUnitFrames: 'frames',
    audioDevicesTitle: 'Devices',
    audioDevicesHelp:
        'Which speaker playback uses and which microphone recording '
        'will use. Changes apply from the next playback run; a device '
        'that is no longer attached falls back to the system default.',
    audioOutputLabel: 'Output',
    audioInputLabel: 'Input',
    audioSystemDefault: 'System default',
    audioDeviceDefaultSuffix: ' (default)',
    audioDeviceMissingSuffix: ' (missing)',
    audioSyncInspectorTitle: 'Sync inspector',
    recordVoiceTooltip: 'Record voice at the playhead',
    recordVoiceStopTooltip: 'Stop recording (places the take)',
    recordMicOpenFailed:
        'Could not open the microphone — check Preferences ▸ Audio '
        'and the OS microphone permission.',
    recordMicPermissionDenied: 'Microphone permission was not granted.',
    recordSelectSeLane:
        'Recording lands on the selected SE track — select one first.',
    recordTakeClipped:
        'The take clipped — the red corner marks the block.',
    recordClipMarkerTooltip: 'This take clipped (recorded too hot)',
    audioMicGainLabel: 'Mic gain (dB)',
    audioInputChannelLabel: 'Input channels',
    audioInputChannelDevice: 'As device',
    audioInputChannelMonoMix: 'Mono mix',
    audioInputChannelLeft: 'Left only',
    audioInputChannelRight: 'Right only',
    audioClippingNoticeLabel: 'Clipping warnings (toast + block marker)',
    audioDenoiseLabel: 'Noise suppression (voice only — turn off for foley)',
    audioInputMeterLabel: 'Input level',
    audioTestSoundLabel: 'Test sound',
    audioCountInLabel: 'Count-in (seconds)',
    audioCueBeepsLabel: 'Cue beeps (ADR 3-beep)',
    audioStreamerLabel: 'Streamer (punch-in wipe)',
    recordNothingRecording: 'Nothing was recording.',
    recordTakeEmpty: 'The take was empty — nothing to place.',
    recordPlacementFailed: 'The recording could not be placed.',
    recordDroppedFramesTemplate:
        'Recorded, but {count} frames were dropped (the machine could '
        'not keep up) — check the take.',
    layerAudioTitle: 'Layer Audio',
    audioGainLabel: 'Gain',
    audioPanLabel: 'Pan',
    layerAudioPanHelp:
        'Pan applies on the device mixer path (equal-power law).',
    audioSolo: 'Solo',
    audioUnsolo: 'Unsolo',
    audioLayerAudioMenu: 'Layer audio…',
    audioClipGainMenu: 'Gain…',
    audioEnvelopeMenu: 'Volume envelope…',
    audioFadesEqualPowerMenu: 'Fades: equal-power (switch to linear)',
    audioFadesLinearMenu: 'Fades: linear (switch to equal-power)',
    audioClipGainTitle: 'Clip Gain',
    audioEnvelopeTitle: 'Volume Envelope',
    audioEnvelopeHelp:
        'Keyed gains at clip frames (linear between keys, held past '
        'the ends). Empty = flat.',
    audioEnvelopeFrameLabel: 'frame',
    audioEnvelopeGainPercentLabel: 'gain %',
    audioEnvelopeAddKey: 'Add key',
    fpsAudioTitleTemplate: '{from} → {to}: what happens to sound?',
    fpsAudioBody:
        'These two rates differ by 0.1% in real speed, and audio exists '
        'in real seconds — it cannot stay both frame-exact and '
        'time-exact.\n\n'
        '• Keep audio timing: sounds keep their real seconds; their '
        'frame positions drift by 0.1% (about one frame every 42 '
        'seconds).\n\n'
        '• Pull audio 0.1%: sounds are resampled by the exact pulldown '
        'ratio (an inaudible pitch change — the standard telecine '
        'conform) so every sound keeps its exact frame span.',
    fpsAudioKeep: 'Keep audio timing',
    fpsAudioPull: 'Pull audio 0.1%',
    selectionMoveConfirmTitle: 'Commit move',
    selectionMoveConfirmBody: 'Commit the selection move?',
    selectionMoveRevert: 'Revert',
    selectionMoveApply: 'Commit',
  );

  static const _ja = AppStrings._(
    languageSettingsTitle: '言語設定',
    programLanguageLabel: 'プログラム言語',
    notationLanguageLabel: '表記言語',
    programLanguageHelp: 'メニュー・パネル・ラベルの言語。',
    notationLanguageHelp: 'タイムシートなど提出物に印字される言語。',
    noCutSelected: 'カット未選択',
    pageLabel: 'ページ',
    continuousLabel: '連続表示',
    noticeNoFrameHere: 'フレームがありません',
    noticeLayerNotDrawable: 'このレイヤーには描けません',
    noticeNothingToTransform: '変形する絵がありません',
    commonCancel: 'キャンセル',
    commonApply: '適用',
    commonRefresh: '更新',
    commonClose: '閉じる',
    exportNoCuts: 'このプロジェクトには書き出せるカットがありません。',
    audioOffsetTitle: 'A/Vオフセット',
    audioOffsetHelp:
        '音に対して絵をいつ表示するかを微調整します。測定できる遅延は自動補正され、'
        'これは残りを取り除くための設定です — ワイヤレスイヤホンは150〜300ms'
        '遅れているのに何も報告しないのが普通です。正の値で絵が遅く表示されます'
        '（音が遅れて届くのが一般的なケース）。',
    audioOffsetLabel: 'オフセット',
    audioUnitFrames: 'コマ',
    audioDevicesTitle: 'デバイス',
    audioDevicesHelp:
        '再生に使うスピーカーと録音に使うマイクの選択。変更は次の再生から適用'
        'されます。取り外されたデバイスはシステム既定にフォールバックします。',
    audioOutputLabel: '出力',
    audioInputLabel: '入力',
    audioSystemDefault: 'システム既定',
    audioDeviceDefaultSuffix: '（既定）',
    audioDeviceMissingSuffix: '（未接続）',
    audioSyncInspectorTitle: '同期インスペクタ',
    recordVoiceTooltip: '再生ヘッド位置にボイスを録音',
    recordVoiceStopTooltip: '録音を停止（テイクを配置）',
    recordMicOpenFailed:
        'マイクを開けませんでした — 環境設定▸オーディオとOSのマイク権限を'
        '確認してください。',
    recordMicPermissionDenied: 'マイクの権限が許可されませんでした。',
    recordSelectSeLane: '録音は選択中のSEトラックに配置されます — '
        '先にSEトラックを選択してください。',
    recordTakeClipped: 'テイクがクリッピングしました — ブロックの赤い角が目印です。',
    recordClipMarkerTooltip: 'このテイクはクリッピングしています（入力過大）',
    audioMicGainLabel: 'マイクゲイン（dB）',
    audioInputChannelLabel: '入力チャンネル',
    audioInputChannelDevice: '装置のまま',
    audioInputChannelMonoMix: 'モノラルミックス',
    audioInputChannelLeft: '左のみ',
    audioInputChannelRight: '右のみ',
    audioClippingNoticeLabel: 'クリッピング警告（トースト＋ブロックマーカー）',
    audioDenoiseLabel: 'ノイズ抑制（音声専用 — 効果音はオフに）',
    audioInputMeterLabel: '入力レベル',
    audioTestSoundLabel: 'テスト音を再生',
    audioCountInLabel: 'カウントイン（秒）',
    audioCueBeepsLabel: 'キュービープ（ADR式3ビープ）',
    audioStreamerLabel: 'ストリーマー（パンチイン・ワイプ）',
    recordNothingRecording: '録音中ではありません。',
    recordTakeEmpty: 'テイクが空でした — 配置するものがありません。',
    recordPlacementFailed: '録音を配置できませんでした。',
    recordDroppedFramesTemplate:
        '録音しましたが{count}フレームが欠落しました（処理が追いつきません'
        'でした）— テイクを確認してください。',
    layerAudioTitle: 'レイヤーオーディオ',
    audioGainLabel: 'ゲイン',
    audioPanLabel: 'パン',
    layerAudioPanHelp: 'パンはデバイスミキサー経路で適用されます（等パワー則）。',
    audioSolo: 'ソロ',
    audioUnsolo: 'ソロ解除',
    audioLayerAudioMenu: 'レイヤーオーディオ…',
    audioClipGainMenu: 'ゲイン…',
    audioEnvelopeMenu: 'ボリュームエンベロープ…',
    audioFadesEqualPowerMenu: 'フェード：等パワー（リニアに切替）',
    audioFadesLinearMenu: 'フェード：リニア（等パワーに切替）',
    audioClipGainTitle: 'クリップゲイン',
    audioEnvelopeTitle: 'ボリュームエンベロープ',
    audioEnvelopeHelp:
        'クリップ内コマ位置ごとのゲインキー（キー間は直線、両端は保持）。'
        '空＝フラット。',
    audioEnvelopeFrameLabel: 'コマ',
    audioEnvelopeGainPercentLabel: 'ゲイン %',
    audioEnvelopeAddKey: 'キーを追加',
    fpsAudioTitleTemplate: '{from} → {to}：音はどうしますか？',
    fpsAudioBody:
        'この2つのレートは実速度が0.1%異なり、音は実時間で存在します — '
        'コマ厳密と時間厳密を両立することはできません。\n\n'
        '• 音のタイミングを維持：音は実時間を保ち、コマ位置が0.1%ずれます'
        '（約42秒ごとに1コマ）。\n\n'
        '• 音を0.1%プル：正確なプルダウン比でリサンプルします（聴き取れない'
        'ピッチ変化 — テレシネの標準コンフォーム）。全ての音がコマ範囲を'
        '維持します。',
    fpsAudioKeep: '音のタイミングを維持',
    fpsAudioPull: '音を0.1%プル',
    selectionMoveConfirmTitle: '移動の確定',
    selectionMoveConfirmBody: '選択範囲の移動を確定しますか？',
    selectionMoveRevert: '元に戻す',
    selectionMoveApply: '確定',
  );

  static const _ko = AppStrings._(
    languageSettingsTitle: '언어 설정',
    programLanguageLabel: '프로그램 언어',
    notationLanguageLabel: '표기용 언어',
    programLanguageHelp: '메뉴·패널·라벨의 언어.',
    notationLanguageHelp: '타임시트 등 제출물에 인쇄되는 언어.',
    noCutSelected: '선택된 컷 없음',
    pageLabel: '페이지',
    continuousLabel: '콘티너스',
    noticeNoFrameHere: '프레임이 존재하지 않습니다',
    noticeLayerNotDrawable: '드로잉이 허용되지 않은 레이어입니다',
    noticeNothingToTransform: '변형할 그림이 없습니다',
    commonCancel: '취소',
    commonApply: '적용',
    commonRefresh: '새로고침',
    commonClose: '닫기',
    exportNoCuts: '이 프로젝트에는 출력할 컷이 없습니다.',
    audioOffsetTitle: 'A/V 오프셋',
    audioOffsetHelp:
        '소리에 대해 그림을 언제 표시할지 미세 조정합니다. 측정 가능한 '
        '지연은 자동 보정되며, 이 설정은 그 잔차를 제거합니다 — 무선 '
        '이어폰은 150~300ms 늦으면서 아무것도 보고하지 않는 게 보통입니다. '
        '양수면 그림이 더 늦게 표시됩니다(소리가 늦게 도착하는 경우가 '
        '일반적).',
    audioOffsetLabel: '오프셋',
    audioUnitFrames: '프레임',
    audioDevicesTitle: '장치',
    audioDevicesHelp:
        '재생에 쓸 스피커와 녹음에 쓸 마이크. 변경은 다음 재생부터 '
        '적용되며, 분리된 장치는 시스템 기본값으로 대체됩니다.',
    audioOutputLabel: '출력',
    audioInputLabel: '입력',
    audioSystemDefault: '시스템 기본값',
    audioDeviceDefaultSuffix: ' (기본)',
    audioDeviceMissingSuffix: ' (미연결)',
    audioSyncInspectorTitle: '싱크 인스펙터',
    recordVoiceTooltip: '플레이헤드 위치에 보이스 녹음',
    recordVoiceStopTooltip: '녹음 정지(테이크 배치)',
    recordMicOpenFailed:
        '마이크를 열 수 없습니다 — 환경설정▸오디오와 OS 마이크 권한을 '
        '확인하세요.',
    recordMicPermissionDenied: '마이크 권한이 허용되지 않았습니다.',
    recordSelectSeLane:
        '녹음은 선택된 SE 트랙에 배치됩니다 — 먼저 SE 트랙을 선택하세요.',
    recordTakeClipped: '테이크에 클리핑이 감지되었습니다 — 블록의 빨간 모서리가 표시입니다.',
    recordClipMarkerTooltip: '이 테이크는 클리핑되었습니다(입력 과대)',
    audioMicGainLabel: '마이크 게인(dB)',
    audioInputChannelLabel: '입력 채널',
    audioInputChannelDevice: '장치 그대로',
    audioInputChannelMonoMix: '모노 믹스',
    audioInputChannelLeft: '왼쪽만',
    audioInputChannelRight: '오른쪽만',
    audioClippingNoticeLabel: '클리핑 주의 안내(토스트+블록 마커)',
    audioDenoiseLabel: '잡음 제거(음성 전용 — 효과음 녹음 시 끄기)',
    audioInputMeterLabel: '입력 레벨',
    audioTestSoundLabel: '테스트 사운드',
    audioCountInLabel: '카운트인(초)',
    audioCueBeepsLabel: '큐 비프(ADR식 3비프)',
    audioStreamerLabel: '스트리머(펀치인 와이프)',
    recordNothingRecording: '녹음 중이 아닙니다.',
    recordTakeEmpty: '테이크가 비어 있어 배치할 것이 없습니다.',
    recordPlacementFailed: '녹음을 배치하지 못했습니다.',
    recordDroppedFramesTemplate:
        '녹음됐지만 {count}프레임이 유실됐습니다(처리가 따라가지 못함) — '
        '테이크를 확인하세요.',
    layerAudioTitle: '레이어 오디오',
    audioGainLabel: '게인',
    audioPanLabel: '팬',
    layerAudioPanHelp: '팬은 장치 믹서 경로에서 적용됩니다(등파워 법칙).',
    audioSolo: '솔로',
    audioUnsolo: '솔로 해제',
    audioLayerAudioMenu: '레이어 오디오…',
    audioClipGainMenu: '게인…',
    audioEnvelopeMenu: '볼륨 엔벨로프…',
    audioFadesEqualPowerMenu: '페이드: 등파워(리니어로 전환)',
    audioFadesLinearMenu: '페이드: 리니어(등파워로 전환)',
    audioClipGainTitle: '클립 게인',
    audioEnvelopeTitle: '볼륨 엔벨로프',
    audioEnvelopeHelp:
        '클립 내 프레임 위치별 게인 키(키 사이는 직선, 양 끝은 유지). '
        '비어 있으면 플랫.',
    audioEnvelopeFrameLabel: '프레임',
    audioEnvelopeGainPercentLabel: '게인 %',
    audioEnvelopeAddKey: '키 추가',
    fpsAudioTitleTemplate: '{from} → {to}: 소리는 어떻게 할까요?',
    fpsAudioBody:
        '두 레이트는 실제 속도가 0.1% 다르고, 소리는 실시간으로 존재합니다 '
        '— 프레임 정확과 시간 정확을 동시에 지킬 수 없습니다.\n\n'
        '• 오디오 타이밍 유지: 소리는 실시간을 지키고, 프레임 위치가 '
        '0.1% 어긋납니다(약 42초마다 1프레임).\n\n'
        '• 오디오 0.1% 당김: 정확한 풀다운 비율로 리샘플합니다(들리지 않는 '
        '피치 변화 — 텔레시네 표준 컨폼). 모든 소리가 프레임 범위를 '
        '유지합니다.',
    fpsAudioKeep: '오디오 타이밍 유지',
    fpsAudioPull: '오디오 0.1% 당김',
    selectionMoveConfirmTitle: '이동 확정',
    selectionMoveConfirmBody: '선택 영역 이동을 확정하시겠습니까?',
    selectionMoveRevert: '되돌리기',
    selectionMoveApply: '확정',
  );

  static const _fr = AppStrings._(
    languageSettingsTitle: 'Paramètres de langue',
    programLanguageLabel: 'Langue du programme',
    notationLanguageLabel: 'Langue de notation',
    programLanguageHelp: 'Menus, panneaux et libellés.',
    notationLanguageHelp: 'Ce qui s\'imprime sur la feuille d\'exposition.',
    noCutSelected: 'Aucun plan sélectionné',
    pageLabel: 'Page',
    continuousLabel: 'Continu',
    noticeNoFrameHere: 'Aucune image ici',
    noticeLayerNotDrawable: 'Ce calque n\'accepte pas le dessin',
    noticeNothingToTransform: 'Rien a transformer',
    commonCancel: 'Annuler',
    commonApply: 'Appliquer',
    commonRefresh: 'Actualiser',
    commonClose: 'Fermer',
    exportNoCuts: 'Ce projet ne contient aucun plan à exporter.',
    audioOffsetTitle: 'Décalage A/V',
    audioOffsetHelp:
        'Ajuste finement le moment où l\'image s\'affiche par rapport au '
        'son. La part mesurable du retard est corrigée automatiquement ; '
        'ce réglage retire le reste — les écouteurs sans fil ont souvent '
        '150 à 300 ms de retard sans rien signaler. Une valeur positive '
        'affiche l\'image PLUS TARD (le son en retard est le cas '
        'courant).',
    audioOffsetLabel: 'Décalage',
    audioUnitFrames: 'images',
    audioDevicesTitle: 'Périphériques',
    audioDevicesHelp:
        'Le haut-parleur utilisé en lecture et le micro utilisé en '
        'enregistrement. Les changements s\'appliquent à la prochaine '
        'lecture ; un périphérique débranché retombe sur le choix '
        'système.',
    audioOutputLabel: 'Sortie',
    audioInputLabel: 'Entrée',
    audioSystemDefault: 'Défaut système',
    audioDeviceDefaultSuffix: ' (défaut)',
    audioDeviceMissingSuffix: ' (absent)',
    audioSyncInspectorTitle: 'Inspecteur de synchro',
    recordVoiceTooltip: 'Enregistrer la voix à la tête de lecture',
    recordVoiceStopTooltip: 'Arrêter l\'enregistrement (place la prise)',
    recordMicOpenFailed:
        'Impossible d\'ouvrir le micro — vérifiez Préférences ▸ Audio '
        'et l\'autorisation micro du système.',
    recordMicPermissionDenied: 'L\'autorisation micro a été refusée.',
    recordSelectSeLane:
        'L\'enregistrement se place sur la piste SE sélectionnée — '
        'sélectionnez-en une d\'abord.',
    recordTakeClipped:
        'La prise a saturé — le coin rouge marque le bloc.',
    recordClipMarkerTooltip: 'Prise saturée (niveau trop fort)',
    audioMicGainLabel: 'Gain micro (dB)',
    audioInputChannelLabel: 'Canaux d\'entrée',
    audioInputChannelDevice: 'Tel quel',
    audioInputChannelMonoMix: 'Mixage mono',
    audioInputChannelLeft: 'Gauche seul',
    audioInputChannelRight: 'Droit seul',
    audioClippingNoticeLabel: 'Alertes de saturation (toast + marqueur)',
    audioDenoiseLabel: 'Réduction de bruit (voix — désactiver pour le bruitage)',
    audioInputMeterLabel: 'Niveau d\'entrée',
    audioTestSoundLabel: 'Son de test',
    audioCountInLabel: 'Décompte (secondes)',
    audioCueBeepsLabel: 'Bips de repère (3 bips ADR)',
    audioStreamerLabel: 'Streamer (balayage punch-in)',
    recordNothingRecording: 'Aucun enregistrement en cours.',
    recordTakeEmpty: 'La prise était vide — rien à placer.',
    recordPlacementFailed: 'La prise n\'a pas pu être placée.',
    recordDroppedFramesTemplate:
        'Enregistré, mais {count} trames ont été perdues (la machine '
        'n\'a pas suivi) — vérifiez la prise.',
    layerAudioTitle: 'Audio du calque',
    audioGainLabel: 'Gain',
    audioPanLabel: 'Panoramique',
    layerAudioPanHelp:
        'Le panoramique s\'applique sur la voie du mixeur natif (loi à '
        'puissance constante).',
    audioSolo: 'Solo',
    audioUnsolo: 'Retirer le solo',
    audioLayerAudioMenu: 'Audio du calque…',
    audioClipGainMenu: 'Gain…',
    audioEnvelopeMenu: 'Enveloppe de volume…',
    audioFadesEqualPowerMenu:
        'Fondus : puissance constante (passer en linéaire)',
    audioFadesLinearMenu:
        'Fondus : linéaire (passer en puissance constante)',
    audioClipGainTitle: 'Gain du clip',
    audioEnvelopeTitle: 'Enveloppe de volume',
    audioEnvelopeHelp:
        'Clés de gain aux images du clip (linéaire entre les clés, '
        'maintenu aux extrémités). Vide = plat.',
    audioEnvelopeFrameLabel: 'image',
    audioEnvelopeGainPercentLabel: 'gain %',
    audioEnvelopeAddKey: 'Ajouter une clé',
    fpsAudioTitleTemplate: '{from} → {to} : que faire du son ?',
    fpsAudioBody:
        'Ces deux cadences diffèrent de 0,1 % en vitesse réelle, et le '
        'son existe en secondes réelles — il ne peut pas rester à la '
        'fois exact à l\'image et exact au temps.\n\n'
        '• Garder le timing audio : les sons gardent leurs secondes '
        'réelles ; leurs positions d\'image dérivent de 0,1 % (environ '
        'une image toutes les 42 secondes).\n\n'
        '• Tirer l\'audio de 0,1 % : les sons sont rééchantillonnés au '
        'rapport de pulldown exact (variation de hauteur inaudible — la '
        'conformation télécinéma standard) et chaque son garde sa plage '
        'd\'images exacte.',
    fpsAudioKeep: 'Garder le timing audio',
    fpsAudioPull: 'Tirer l\'audio de 0,1 %',
    selectionMoveConfirmTitle: 'Valider le déplacement',
    selectionMoveConfirmBody: 'Valider le déplacement de la sélection ?',
    selectionMoveRevert: 'Rétablir',
    selectionMoveApply: 'Valider',
  );

  static const _zhHans = AppStrings._(
    languageSettingsTitle: '语言设置',
    programLanguageLabel: '程序语言',
    notationLanguageLabel: '标注语言',
    programLanguageHelp: '菜单、面板与标签的语言。',
    notationLanguageHelp: '打印在摄影表等提交物上的语言。',
    noCutSelected: '未选择镜头',
    pageLabel: '页',
    continuousLabel: '连续视图',
    noticeNoFrameHere: '此处没有帧',
    noticeLayerNotDrawable: '该图层不可绘制',
    noticeNothingToTransform: '没有可变形的内容',
    commonCancel: '取消',
    commonApply: '应用',
    commonRefresh: '刷新',
    commonClose: '关闭',
    exportNoCuts: '此项目暂无可导出的镜头。',
    audioOffsetTitle: 'A/V 偏移',
    audioOffsetHelp:
        '微调画面相对声音的显示时机。可测量的延迟会自动校正，此设置'
        '用于消除剩余部分 — 无线耳机通常落后 150~300 毫秒且不作任何'
        '报告。正值让画面更晚显示（声音迟到是常见情况）。',
    audioOffsetLabel: '偏移',
    audioUnitFrames: '帧',
    audioDevicesTitle: '设备',
    audioDevicesHelp:
        '播放使用的扬声器与录音使用的麦克风。更改自下次播放起生效；'
        '已拔出的设备将回退到系统默认。',
    audioOutputLabel: '输出',
    audioInputLabel: '输入',
    audioSystemDefault: '系统默认',
    audioDeviceDefaultSuffix: '（默认）',
    audioDeviceMissingSuffix: '（未连接）',
    audioSyncInspectorTitle: '同步检查器',
    recordVoiceTooltip: '在播放头位置录制语音',
    recordVoiceStopTooltip: '停止录音（放置素材）',
    recordMicOpenFailed:
        '无法打开麦克风 — 请检查首选项▸音频以及系统麦克风权限。',
    recordMicPermissionDenied: '麦克风权限未被授予。',
    recordSelectSeLane: '录音将放置到所选SE轨道 — 请先选择一个SE轨道。',
    recordTakeClipped: '录音发生削波 — 块上的红角为标记。',
    recordClipMarkerTooltip: '该录音已削波（电平过高）',
    audioMicGainLabel: '麦克风增益（dB）',
    audioInputChannelLabel: '输入声道',
    audioInputChannelDevice: '按设备',
    audioInputChannelMonoMix: '单声道混合',
    audioInputChannelLeft: '仅左声道',
    audioInputChannelRight: '仅右声道',
    audioClippingNoticeLabel: '削波警告（提示+块标记）',
    audioDenoiseLabel: '降噪（仅人声 — 录拟音时请关闭）',
    audioInputMeterLabel: '输入电平',
    audioTestSoundLabel: '测试声音',
    audioCountInLabel: '倒数（秒）',
    audioCueBeepsLabel: '提示音（ADR三响）',
    audioStreamerLabel: '光带（切入扫过）',
    recordNothingRecording: '当前没有在录音。',
    recordTakeEmpty: '录音为空 — 没有可放置的内容。',
    recordPlacementFailed: '录音未能放置。',
    recordDroppedFramesTemplate:
        '已录音，但丢失了 {count} 帧（机器未能跟上）— 请检查这条录音。',
    layerAudioTitle: '图层音频',
    audioGainLabel: '增益',
    audioPanLabel: '声像',
    layerAudioPanHelp: '声像在原生混音器路径上生效（等功率法则）。',
    audioSolo: '独奏',
    audioUnsolo: '取消独奏',
    audioLayerAudioMenu: '图层音频…',
    audioClipGainMenu: '增益…',
    audioEnvelopeMenu: '音量包络…',
    audioFadesEqualPowerMenu: '淡变：等功率（切换为线性）',
    audioFadesLinearMenu: '淡变：线性（切换为等功率）',
    audioClipGainTitle: '片段增益',
    audioEnvelopeTitle: '音量包络',
    audioEnvelopeHelp:
        '按片段内帧位置设置增益关键点（关键点之间线性，两端保持）。'
        '留空＝平直。',
    audioEnvelopeFrameLabel: '帧',
    audioEnvelopeGainPercentLabel: '增益 %',
    audioEnvelopeAddKey: '添加关键点',
    fpsAudioTitleTemplate: '{from} → {to}：声音怎么办？',
    fpsAudioBody:
        '这两个帧率的实际速度相差 0.1%，而声音存在于真实时间中 — '
        '无法同时保持帧精确与时间精确。\n\n'
        '• 保持音频时间：声音保持真实秒数；帧位置漂移 0.1%'
        '（约每 42 秒一帧）。\n\n'
        '• 拉伸音频 0.1%：按精确的 pulldown 比例重采样（听不出的'
        '音高变化 — 电视电影的标准做法），每个声音保持其精确的'
        '帧范围。',
    fpsAudioKeep: '保持音频时间',
    fpsAudioPull: '拉伸音频 0.1%',
    selectionMoveConfirmTitle: '确认移动',
    selectionMoveConfirmBody: '要确认选区的移动吗？',
    selectionMoveRevert: '还原',
    selectionMoveApply: '确认',
  );
}
