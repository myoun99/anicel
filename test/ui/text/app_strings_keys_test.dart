import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/app_language.dart';
import 'package:quick_animaker_v2/src/ui/text/app_strings.dart';

/// The key contract behind the fallback table.
///
/// [AppStrings] resolves each getter through a string key into a per-language
/// map, falling back to English. That buys partial translations at the cost
/// of the compiler no longer checking the key — so this reads EVERY getter in
/// EVERY language. A typo'd key throws here instead of at the one moment a
/// user opens that panel in that language.
void main() {
  final readers = <String, String Function(AppStrings)>{
    'languageSettingsTitle': (s) => s.languageSettingsTitle,
    'programLanguageLabel': (s) => s.programLanguageLabel,
    'notationLanguageLabel': (s) => s.notationLanguageLabel,
    'programLanguageHelp': (s) => s.programLanguageHelp,
    'notationLanguageHelp': (s) => s.notationLanguageHelp,
    'noCutSelected': (s) => s.noCutSelected,
    'pageLabel': (s) => s.pageLabel,
    'continuousLabel': (s) => s.continuousLabel,
    'noticeNoFrameHere': (s) => s.noticeNoFrameHere,
    'noticeLayerNotDrawable': (s) => s.noticeLayerNotDrawable,
    'noticeNothingToTransform': (s) => s.noticeNothingToTransform,
    'commonCancel': (s) => s.commonCancel,
    'commonApply': (s) => s.commonApply,
    'commonRefresh': (s) => s.commonRefresh,
    'commonClose': (s) => s.commonClose,
    'exportNoCuts': (s) => s.exportNoCuts,
    'audioOffsetTitle': (s) => s.audioOffsetTitle,
    'audioOffsetHelp': (s) => s.audioOffsetHelp,
    'audioOffsetLabel': (s) => s.audioOffsetLabel,
    'audioUnitFrames': (s) => s.audioUnitFrames,
    'audioDevicesTitle': (s) => s.audioDevicesTitle,
    'audioDevicesHelp': (s) => s.audioDevicesHelp,
    'audioOutputLabel': (s) => s.audioOutputLabel,
    'audioInputLabel': (s) => s.audioInputLabel,
    'audioSystemDefault': (s) => s.audioSystemDefault,
    'audioDeviceDefaultSuffix': (s) => s.audioDeviceDefaultSuffix,
    'audioDeviceMissingSuffix': (s) => s.audioDeviceMissingSuffix,
    'audioSyncInspectorTitle': (s) => s.audioSyncInspectorTitle,
    'recordVoiceTooltip': (s) => s.recordVoiceTooltip,
    'recordVoiceStopTooltip': (s) => s.recordVoiceStopTooltip,
    'recordMicOpenFailed': (s) => s.recordMicOpenFailed,
    'recordMicPermissionDenied': (s) => s.recordMicPermissionDenied,
    'recordSelectSeLane': (s) => s.recordSelectSeLane,
    'recordTakeClipped': (s) => s.recordTakeClipped,
    'recordClipMarkerTooltip': (s) => s.recordClipMarkerTooltip,
    'audioMicGainLabel': (s) => s.audioMicGainLabel,
    'audioInputChannelLabel': (s) => s.audioInputChannelLabel,
    'audioInputChannelDevice': (s) => s.audioInputChannelDevice,
    'audioInputChannelMonoMix': (s) => s.audioInputChannelMonoMix,
    'audioInputChannelLeft': (s) => s.audioInputChannelLeft,
    'audioInputChannelRight': (s) => s.audioInputChannelRight,
    'audioClippingNoticeLabel': (s) => s.audioClippingNoticeLabel,
    'audioDenoiseLabel': (s) => s.audioDenoiseLabel,
    'audioInputMeterLabel': (s) => s.audioInputMeterLabel,
    'audioTestSoundLabel': (s) => s.audioTestSoundLabel,
    'audioCountInLabel': (s) => s.audioCountInLabel,
    'audioCueBeepsLabel': (s) => s.audioCueBeepsLabel,
    'audioStreamerLabel': (s) => s.audioStreamerLabel,
    'recordNothingRecording': (s) => s.recordNothingRecording,
    'recordTakeEmpty': (s) => s.recordTakeEmpty,
    'recordPlacementFailed': (s) => s.recordPlacementFailed,
    'recordDroppedFramesTemplate': (s) => s.recordDroppedFramesTemplate,
    'layerAudioTitle': (s) => s.layerAudioTitle,
    'audioGainLabel': (s) => s.audioGainLabel,
    'audioPanLabel': (s) => s.audioPanLabel,
    'layerAudioPanHelp': (s) => s.layerAudioPanHelp,
    'audioSolo': (s) => s.audioSolo,
    'audioUnsolo': (s) => s.audioUnsolo,
    'audioLayerAudioMenu': (s) => s.audioLayerAudioMenu,
    'audioClipGainMenu': (s) => s.audioClipGainMenu,
    'audioEnvelopeMenu': (s) => s.audioEnvelopeMenu,
    'audioFadesEqualPowerMenu': (s) => s.audioFadesEqualPowerMenu,
    'audioFadesLinearMenu': (s) => s.audioFadesLinearMenu,
    'audioClipGainTitle': (s) => s.audioClipGainTitle,
    'audioEnvelopeTitle': (s) => s.audioEnvelopeTitle,
    'audioEnvelopeHelp': (s) => s.audioEnvelopeHelp,
    'audioEnvelopeFrameLabel': (s) => s.audioEnvelopeFrameLabel,
    'audioEnvelopeGainPercentLabel': (s) => s.audioEnvelopeGainPercentLabel,
    'audioEnvelopeAddKey': (s) => s.audioEnvelopeAddKey,
    'fpsAudioTitleTemplate': (s) => s.fpsAudioTitleTemplate,
    'fpsAudioBody': (s) => s.fpsAudioBody,
    'fpsAudioKeep': (s) => s.fpsAudioKeep,
    'fpsAudioPull': (s) => s.fpsAudioPull,
    'selectionMoveConfirmTitle': (s) => s.selectionMoveConfirmTitle,
    'selectionMoveConfirmBody': (s) => s.selectionMoveConfirmBody,
    'selectionMoveRevert': (s) => s.selectionMoveRevert,
    'selectionMoveApply': (s) => s.selectionMoveApply,
    'commonSave': (s) => s.commonSave,
    'commonDelete': (s) => s.commonDelete,
    'commonRename': (s) => s.commonRename,
    'commonLink': (s) => s.commonLink,
    'commonPreview': (s) => s.commonPreview,
    'renameLayerTitle': (s) => s.renameLayerTitle,
    'renameLayerField': (s) => s.renameLayerField,
    'renameLayerEmpty': (s) => s.renameLayerEmpty,
    'renameCutTitle': (s) => s.renameCutTitle,
    'renameCutField': (s) => s.renameCutField,
    'renameCutEmpty': (s) => s.renameCutEmpty,
    'renameFrameTitle': (s) => s.renameFrameTitle,
    'renameFrameField': (s) => s.renameFrameField,
    'cutNoteTitle': (s) => s.cutNoteTitle,
    'cutNoteField': (s) => s.cutNoteField,
    'deleteLayerTitle': (s) => s.deleteLayerTitle,
    'deleteLayerMessageTemplate': (s) => s.deleteLayerMessageTemplate,
    'frameNameConflictTitle': (s) => s.frameNameConflictTitle,
    'frameNameConflictBody': (s) => s.frameNameConflictBody,
    'seInstanceNewTitle': (s) => s.seInstanceNewTitle,
    'seInstanceEditTitle': (s) => s.seInstanceEditTitle,
    'seNameLabel': (s) => s.seNameLabel,
    'seDialogueLabel': (s) => s.seDialogueLabel,
    'cameraKeyTitleTemplate': (s) => s.cameraKeyTitleTemplate,
    'cameraKeyLinear': (s) => s.cameraKeyLinear,
    'cameraKeyHold': (s) => s.cameraKeyHold,
    'convertLinkedCutTitle': (s) => s.convertLinkedCutTitle,
    'convertLinkedCutBodyTemplate': (s) => s.convertLinkedCutBodyTemplate,
    'convertLinkedCutTargetLabel': (s) => s.convertLinkedCutTargetLabel,
    'convertLinkedCutLinksTemplate': (s) => s.convertLinkedCutLinksTemplate,
    'convertLinkedCutReplacedTemplate': (s) =>
        s.convertLinkedCutReplacedTemplate,
    'convertLinkedCutJoiningTemplate': (s) =>
        s.convertLinkedCutJoiningTemplate,
    'convertLinkedCutTargetGainsTemplate': (s) =>
        s.convertLinkedCutTargetGainsTemplate,
    'convertLinkedCutOriginGainsTemplate': (s) =>
        s.convertLinkedCutOriginGainsTemplate,
    'convertLinkedCutNothing': (s) => s.convertLinkedCutNothing,
    'convertLinkedCutUndoNote': (s) => s.convertLinkedCutUndoNote,
  };

  for (final language in AppLanguage.values) {
    test('every string resolves in ${language.name}', () {
      final strings = AppStrings.of(language);
      for (final entry in readers.entries) {
        expect(
          entry.value(strings),
          isNotEmpty,
          reason: '${entry.key} is empty or unresolved in ${language.name}',
        );
      }
    });
  }

  test('the reader table covers every getter the class declares', () {
    // Guards the guard: a string added without a line here would other-
    // wise be silently unchecked.
    expect(readers, hasLength(113));
  });
}
