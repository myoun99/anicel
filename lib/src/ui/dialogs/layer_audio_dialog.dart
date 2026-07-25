import 'package:flutter/material.dart';

import '../../models/layer_id.dart';
import '../editor_session_manager.dart';
import '../widgets/field_slider.dart';
import '../widgets/app_window.dart';

/// AUDIO-PRO R1: the SE row's track fader + pan — the layer-level mix
/// controls (clip gain/fades stay on the lane). Opened from the speaker
/// button's context menu.
Future<void> showLayerAudioDialog(
  BuildContext context, {
  required EditorSessionManager session,
  required LayerId layerId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _LayerAudioDialog(session: session, layerId: layerId),
  );
}

class _LayerAudioDialog extends StatefulWidget {
  const _LayerAudioDialog({required this.session, required this.layerId});

  final EditorSessionManager session;
  final LayerId layerId;

  @override
  State<_LayerAudioDialog> createState() => _LayerAudioDialogState();
}

class _LayerAudioDialogState extends State<_LayerAudioDialog> {
  late double _gain;
  late double _pan;

  @override
  void initState() {
    super.initState();
    final layer = widget.session.layers
        .where((layer) => layer.id == widget.layerId)
        .firstOrNull;
    _gain = (layer?.audioGain ?? 1.0).clamp(0.0, 2.0);
    _pan = (layer?.audioPan ?? 0.0).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.session.uiStrings;
    return AppWindow(
      windowKey: const ValueKey<String>('layer-audio-dialog'),
      title: strings.layerAudioTitle,
      titleIcon: Icons.volume_up_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 320,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            FieldSlider(
              key: const ValueKey<String>('layer-audio-gain-slider'),
              min: 0,
              max: 2,
              value: _gain,
              label: strings.audioGainLabel,
              valueText: '${(_gain * 100).round()}%',
              displayFactor: 100,
              onChanged: (value) => setState(() => _gain = value),
            ),
            const SizedBox(height: 8),
            FieldSlider(
              key: const ValueKey<String>('layer-audio-pan-slider'),
              min: -1,
              max: 1,
              value: _pan,
              label: strings.audioPanLabel,
              valueText: _pan == 0
                  ? 'C'
                  : _pan < 0
                  ? 'L${(-_pan * 100).round()}'
                  : 'R${(_pan * 100).round()}',
              displayFactor: 100,
              onChanged: (value) => setState(() => _pan = value),
            ),
          const SizedBox(height: 4),
          Text(
            strings.layerAudioPanHelp,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('layer-audio-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonApply,
          actionKey: const ValueKey<String>('layer-audio-apply'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () {
            widget.session.setLayerAudio(
              layerId: widget.layerId,
              gain: _gain,
              pan: _pan,
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
