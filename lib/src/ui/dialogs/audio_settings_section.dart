import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../editor_session_manager.dart';
import '../playback/audio_input_monitor.dart';
import '../playback/audio_sync_settings.dart';
import '../playback/voice_take_processing.dart'
    show micGainFactor, voiceClipThreshold;
import '../text/app_strings.dart';

/// Audio program 2D: the A/V offset and the sync inspector
/// (Preferences ▸ Audio).
///
/// The offset is the RESIDUAL correction — what remains after the device's
/// reported latency is applied automatically. It describes this machine's
/// output path (screen pipeline, Bluetooth, an AV receiver), which is why
/// it lives in app settings and not in the project file.
class AudioSettingsSection extends StatefulWidget {
  const AudioSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  State<AudioSettingsSection> createState() => _AudioSettingsSectionState();
}

class _AudioSettingsSectionState extends State<AudioSettingsSection> {
  /// The live input meter (REC1-D2): attached for this section's
  /// lifetime; the session handles yielding to the recorder.
  late final AudioInputMonitor _monitor = widget.session.attachInputMeter();

  @override
  void dispose() {
    widget.session.detachInputMeter();
    super.dispose();
  }

  /// One device picker row: "System default" plus the live enumeration.
  /// A SAVED name that is no longer attached still shows (marked
  /// missing) so the choice is visible rather than silently reverted —
  /// the open-time fallback handles the audio side.
  Widget _deviceRow({
    required AppStrings strings,
    required String label,
    required String keyValue,
    required bool capture,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    final devices = widget.session.audioDevicesOf(capture: capture);
    final names = {for (final device in devices) device.name};
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        DropdownButton<String?>(
          key: ValueKey<String>(keyValue),
          value: selected,
          isDense: true,
          style: const TextStyle(fontSize: 12),
          items: [
            DropdownMenuItem<String?>(
              child: Text(strings.audioSystemDefault),
            ),
            for (final device in devices)
              DropdownMenuItem<String?>(
                value: device.name,
                child: Text(
                  device.isDefault
                      ? '${device.name}${strings.audioDeviceDefaultSuffix}'
                      : device.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (selected != null && !names.contains(selected))
              DropdownMenuItem<String?>(
                value: selected,
                child: Text('$selected${strings.audioDeviceMissingSuffix}'),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Language is a live subscription (the timeline empty-state pattern):
    // an open Preferences window follows a language switch immediately.
    return ValueListenableBuilder<AppLanguageSettings>(
      valueListenable: widget.session.languageSettings,
      builder: (context, language, _) => _buildSection(
        AppStrings.of(language.programLanguage),
      ),
    );
  }

  Widget _buildSection(AppStrings strings) {
    return ValueListenableBuilder<AudioSyncSettings>(
      valueListenable: widget.session.audioSyncSettings,
      builder: (context, settings, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.audioOffsetTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              strings.audioOffsetHelp,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioOffsetLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: _OffsetField(
                    key: const ValueKey<String>('settings-av-offset-value'),
                    offset: settings.offset,
                    unit: settings.unit,
                    onCommitted: (value) => widget.session.setAudioSyncSettings(
                      settings.copyWith(
                        offset: AudioSyncSettings.clampOffset(
                          value,
                          settings.unit,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<AvOffsetUnit>(
                  key: const ValueKey<String>('settings-av-offset-unit'),
                  value: settings.unit,
                  isDense: true,
                  style: const TextStyle(fontSize: 12),
                  items: [
                    const DropdownMenuItem(
                      value: AvOffsetUnit.milliseconds,
                      child: Text('ms'),
                    ),
                    DropdownMenuItem(
                      value: AvOffsetUnit.frames,
                      child: Text(strings.audioUnitFrames),
                    ),
                  ],
                  // Switching units keeps the NUMBER (it is what the user
                  // typed), re-clamped into the new unit's range.
                  onChanged: (unit) {
                    if (unit != null && unit != settings.unit) {
                      widget.session.setAudioSyncSettings(
                        AudioSyncSettings(
                          offset: AudioSyncSettings.clampOffset(
                            settings.offset,
                            unit,
                          ),
                          unit: unit,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              strings.audioDevicesTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              strings.audioDevicesHelp,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            _deviceRow(
              strings: strings,
              label: strings.audioOutputLabel,
              keyValue: 'settings-audio-output-device',
              capture: false,
              selected: settings.outputDeviceName,
              onChanged: (name) => widget.session.setAudioSyncSettings(
                settings.copyWith(outputDeviceName: name),
              ),
            ),
            const SizedBox(height: 4),
            _deviceRow(
              strings: strings,
              label: strings.audioInputLabel,
              keyValue: 'settings-audio-input-device',
              capture: true,
              selected: settings.inputDeviceName,
              onChanged: (name) {
                widget.session.setAudioSyncSettings(
                  settings.copyWith(inputDeviceName: name),
                );
                // The live meter follows the new microphone immediately.
                widget.session.restartInputMeter();
              },
            ),
            const SizedBox(height: 4),
            // The live input meter (REC1-D2): raw device peak × the gain
            // slider's factor — turning the slider moves this bar without
            // reopening the microphone. The dot is the clip light.
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioInputMeterLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _monitor.peak,
                  builder: (context, rawPeak, _) {
                    final scheme = Theme.of(context).colorScheme;
                    final scaled =
                        rawPeak * micGainFactor(settings.micGainDb);
                    final level = scaled.clamp(0.0, 1.0);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          key: const ValueKey<String>('settings-input-meter'),
                          width: 140,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: level,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          key: const ValueKey<String>(
                            'settings-input-meter-clip',
                          ),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scaled >= voiceClipThreshold
                                ? scheme.error
                                : scheme.outlineVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioTestSoundLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('settings-output-test-button'),
                  tooltip: strings.audioTestSoundLabel,
                  icon: const Icon(Icons.volume_up, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.session.playOutputTestTone,
                ),
              ],
            ),
            // The capture chain (REC1-D): software gain BAKED into takes
            // (the meter and the file agree), the channel fold for
            // one-sided interface mics, and the clipping-notice gate for
            // the toast + block marker (the transport light stays on
            // duty regardless).
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioMicGainLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Slider(
                    key: const ValueKey<String>('settings-mic-gain-slider'),
                    value: settings.micGainDb.toDouble(),
                    min: -AudioSyncSettings.maxMicGainDb.toDouble(),
                    max: AudioSyncSettings.maxMicGainDb.toDouble(),
                    divisions: AudioSyncSettings.maxMicGainDb * 2,
                    onChanged: (value) => widget.session.setAudioSyncSettings(
                      settings.copyWith(
                        micGainDb: AudioSyncSettings.clampMicGainDb(
                          value.round(),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${settings.micGainDb > 0 ? '+' : ''}${settings.micGainDb}',
                    key: const ValueKey<String>('settings-mic-gain-value'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioInputChannelLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                DropdownButton<VoiceInputChannelMode>(
                  key: const ValueKey<String>('settings-input-channel-mode'),
                  value: settings.inputChannelMode,
                  isDense: true,
                  style: const TextStyle(fontSize: 12),
                  items: [
                    DropdownMenuItem(
                      value: VoiceInputChannelMode.device,
                      child: Text(strings.audioInputChannelDevice),
                    ),
                    DropdownMenuItem(
                      value: VoiceInputChannelMode.monoMix,
                      child: Text(strings.audioInputChannelMonoMix),
                    ),
                    DropdownMenuItem(
                      value: VoiceInputChannelMode.left,
                      child: Text(strings.audioInputChannelLeft),
                    ),
                    DropdownMenuItem(
                      value: VoiceInputChannelMode.right,
                      child: Text(strings.audioInputChannelRight),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null && mode != settings.inputChannelMode) {
                      widget.session.setAudioSyncSettings(
                        settings.copyWith(inputChannelMode: mode),
                      );
                    }
                  },
                ),
              ],
            ),
            // RNNoise (the noise-suppression round): BAKED into the take
            // like the gain — speech-specific, so foley sessions turn it
            // off (the label says so).
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioDenoiseLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Switch(
                  key: const ValueKey<String>('settings-denoise-voice'),
                  value: settings.denoiseVoice,
                  onChanged: (value) => widget.session.setAudioSyncSettings(
                    settings.copyWith(denoiseVoice: value),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioClippingNoticeLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Switch(
                  key: const ValueKey<String>('settings-clipping-notice'),
                  value: settings.clippingNotice,
                  onChanged: (value) => widget.session.setAudioSyncSettings(
                    settings.copyWith(clippingNotice: value),
                  ),
                ),
              ],
            ),
            // ADR cueing (REC1-E): the stopped-⏺ count-in, the 3-beep
            // countdown into a punch, and the streamer wipe on the
            // picture.
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioCountInLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Slider(
                    key: const ValueKey<String>('settings-count-in-slider'),
                    value: settings.countInSeconds.toDouble(),
                    max: AudioSyncSettings.maxCountInSeconds.toDouble(),
                    divisions: AudioSyncSettings.maxCountInSeconds,
                    onChanged: (value) => widget.session.setAudioSyncSettings(
                      settings.copyWith(
                        countInSeconds: AudioSyncSettings.clampCountInSeconds(
                          value.round(),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${settings.countInSeconds}',
                    key: const ValueKey<String>('settings-count-in-value'),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioCueBeepsLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Switch(
                  key: const ValueKey<String>('settings-cue-beeps'),
                  value: settings.cueBeeps,
                  onChanged: (value) => widget.session.setAudioSyncSettings(
                    settings.copyWith(cueBeeps: value),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioStreamerLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Switch(
                  key: const ValueKey<String>('settings-streamer'),
                  value: settings.streamerEnabled,
                  onChanged: (value) => widget.session.setAudioSyncSettings(
                    settings.copyWith(streamerEnabled: value),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.audioSyncInspectorTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('settings-audio-report-refresh'),
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: strings.commonRefresh,
                  onPressed: () => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // One pasteable line — a real-device report should be evidence,
            // not an impression.
            SelectableText(
              widget.session.audioDeviceTransport.report.summary,
              key: const ValueKey<String>('settings-audio-report'),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        );
      },
    );
  }
}

/// A compact signed-integer field that commits on submit/focus loss and
/// snaps back to the live value on bad input (mirrors the autosave
/// minutes field).
class _OffsetField extends StatefulWidget {
  const _OffsetField({
    super.key,
    required this.offset,
    required this.unit,
    required this.onCommitted,
  });

  final int offset;
  final AvOffsetUnit unit;
  final ValueChanged<int> onCommitted;

  @override
  State<_OffsetField> createState() => _OffsetFieldState();
}

class _OffsetFieldState extends State<_OffsetField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.offset}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _OffsetField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.offset != oldWidget.offset || widget.unit != oldWidget.unit) &&
        !_focus.hasFocus) {
      _controller.text = '${widget.offset}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.offset}';
      return;
    }
    if (parsed != widget.offset) {
      widget.onCommitted(parsed);
    } else {
      // Same value: still normalize the text (e.g. "+3" → "3").
      _controller.text = '${widget.offset}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      textAlign: TextAlign.end,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(isDense: true),
      onSubmitted: (_) => _commit(),
    );
  }
}
