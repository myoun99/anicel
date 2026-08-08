import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../editor_session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/anchored_popup.dart';
import '../widgets/field_slider.dart';

/// The SE row's mixer, opened by pressing the row's SPEAKER (R10 R3).
///
/// It replaces the speaker's context menu. That menu had two entrances,
/// right-click and long press, and the long press could never fire: a
/// `GestureDetector`'s long press does not resolve inside a
/// `SingleChildScrollView` because the scroll drag takes the arena, and
/// every rail in this app is one. On touch the mixer was unreachable.
///
/// So the speaker stops being a toggle and becomes a door — mute moves
/// inside with solo, the fader and the pan, and every rail that mounts the
/// speaker gets the same four controls instead of the timeline rails
/// getting a menu and the storyboard rail getting nothing.
const double seLayerMixerWidth = 236;
const double seLayerMixerHeight = 224;

Future<void> showSeLayerMixer(
  BuildContext anchorContext, {
  required EditorSessionManager session,
  required LayerId layerId,
}) {
  return showAnchoredPopup<void>(
    anchorContext,
    label: 'se-layer-mixer',
    width: seLayerMixerWidth,
    height: seLayerMixerHeight,
    builder: (context, _) => _SeLayerMixer(session: session, layerId: layerId),
  );
}

class _SeLayerMixer extends StatefulWidget {
  const _SeLayerMixer({required this.session, required this.layerId});

  final EditorSessionManager session;
  final LayerId layerId;

  @override
  State<_SeLayerMixer> createState() => _SeLayerMixerState();
}

class _SeLayerMixerState extends State<_SeLayerMixer> {
  /// The live drag values. Gain and pan write on RELEASE (the commit-on-
  /// release rule the opacity bars follow): `setLayerAudio` refreshes the
  /// whole live audio schedule, which is not a per-move price. Mute and
  /// solo are discrete and land immediately.
  double? _gainDrag;
  double? _panDrag;

  /// The subject row. `session.layers` is EMPTY in a gap (no active cut),
  /// and the storyboard rail deliberately keeps its SE controls mounted
  /// there — a track-owned SE row is not a cut's layer. Falling back to
  /// the track resolver is what keeps the mixer from opening blank on the
  /// one surface that can be standing in a gap.
  Layer? get _layer =>
      widget.session.layers
          .where((layer) => layer.id == widget.layerId)
          .firstOrNull ??
      widget.session.trackSeGlobalLayerById(widget.layerId);

  @override
  Widget build(BuildContext context) {
    // The session is the single source for all four: mute/gain/pan are
    // Layer fields, solo is session-only monitoring state that is never
    // saved and never exported. Listening to both keeps the window honest
    // when something else moves them.
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.session,
        widget.session.soloedSeLayerIds,
      ]),
      builder: (context, _) {
        final layer = _layer;
        if (layer == null) {
          return const SizedBox.shrink();
        }
        return _body(context, layer);
      },
    );
  }

  Widget _body(BuildContext context, Layer layer) {
    final strings = widget.session.uiStrings;
    final soloed = widget.session.soloedSeLayerIds.value.contains(layer.id);
    final gain = _gainDrag ?? layer.audioGain.clamp(0.0, 2.0);
    final pan = _panDrag ?? layer.audioPan.clamp(-1.0, 1.0);

    // ⛔No `Material` of its own — the anchored popup carries the window
    // now (R4 #8).
    return Padding(
      key: const ValueKey<String>('se-layer-mixer'),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            layer.name.isEmpty ? strings.layerAudioTitle : layer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MixToggle(
                  keyValue: 'se-mixer-mute',
                  label: strings.audioMute,
                  icon: layer.muted ? Icons.volume_off : Icons.volume_up,
                  on: layer.muted,
                  onPressed: () =>
                      widget.session.toggleLayerMuted(widget.layerId),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MixToggle(
                  keyValue: 'se-mixer-solo',
                  label: strings.audioSolo,
                  icon: Icons.headphones,
                  on: soloed,
                  onPressed: () =>
                      widget.session.toggleLayerSolo(widget.layerId),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FieldSlider(
            key: const ValueKey<String>('se-mixer-gain'),
            min: 0,
            max: 2,
            value: gain,
            label: strings.audioGainLabel,
            // The bar reads percent, so the numeric field must TYPE
            // percent: without this a typed 80 means 80× and clamps to
            // the 2.0 ceiling — 200% from a keystroke that asked for 80.
            valueText: _gainText(gain),
            valueTextBuilder: _gainText,
            onChanged: (value) => setState(() => _gainDrag = value),
            onChangeEnd: (value) {
              setState(() => _gainDrag = null);
              widget.session.setLayerAudio(
                layerId: widget.layerId,
                gain: value,
              );
            },
          ),
          const SizedBox(height: 6),
          FieldSlider(
            key: const ValueKey<String>('se-mixer-pan'),
            min: -1,
            max: 1,
            value: pan,
            label: strings.audioPanLabel,
            // A balance, not a quantity: the bar leaves CENTRE toward the
            // side it is panned to, so hard left reads as "fully left"
            // rather than as an empty fader.
            fillOrigin: 0,
            // Same unit contract as the fader: the label says L50/R50,
            // so the field takes ±100.
            valueText: _panText(pan),
            valueTextBuilder: _panText,
            onChanged: (value) => setState(() => _panDrag = value),
            onChangeEnd: (value) {
              setState(() => _panDrag = null);
              widget.session.setLayerAudio(layerId: widget.layerId, pan: value);
            },
          ),
          const SizedBox(height: 6),
          // The one honest caveat this window owes the user: pan reaches
          // the sound only on the device-mixer path. The platform-player
          // fallback sets volume and drops pan entirely.
          Text(
            strings.layerAudioPanHelp,
            style: TextStyle(fontSize: 10, color: AppColors.hairline),
          ),
        ],
      ),
    );
  }

  static String _gainText(double gain) => '${(gain * 100).round()}%';

  static String _panText(double pan) {
    if (pan == 0) {
      return 'C';
    }
    return pan < 0 ? 'L${(-pan * 100).round()}' : 'R${(pan * 100).round()}';
  }
}

/// A latching button in the mixer: icon + label, accent while engaged
/// (selection style — colour only, no checkmark).
class _MixToggle extends StatelessWidget {
  const _MixToggle({
    required this.keyValue,
    required this.label,
    required this.icon,
    required this.on,
    required this.onPressed,
  });

  final String keyValue;
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.accent : AppColors.hairline;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>(keyValue),
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: on ? AppColors.accent : null),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: on ? AppColors.accent : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
