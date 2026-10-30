import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/se_sound.dart';
import '../../services/project_lookup.dart' show layerAnywhereOrNull;
import '../editor_session_manager.dart';
import '../session/session_row_button_presses.dart';
import '../theme/app_theme.dart';
import '../widgets/anchored_popup.dart';
import '../widgets/field_slider.dart';
import '../input/control_press_claim.dart';

/// The SE row's mixer, opened by pressing the row's SPEAKER (R10 R3).
///
/// It replaces the speaker's context menu. That menu had two entrances,
/// right-click and long press, and the long press could never fire: a
/// `GestureDetector`'s long press does not resolve inside a
/// `SingleChildScrollView` because the scroll drag takes the arena, and
/// every rail in this app is one. On touch the mixer was unreachable.
///
/// So the speaker stops being a toggle and becomes a door — mute moves
/// inside with solo, and every rail that mounts the speaker gets the same
/// controls instead of the timeline rails getting a menu and the storyboard
/// rail getting nothing. ↩️The fader and the pan stood here too, until the
/// row's volume and pan became its 「오디오」 group's lanes, the volume keyed
/// (I-140: 「음소거버튼은 내부에 있던 게인이나 이런 필요없어지는것들은 삭제」).
/// 🗣️I-145 (유저 2026-10-30): 「위치는 전처럼 스피커버튼안에 볼륨 … 오디오fx
/// 에서도 조절하고 스피커버튼에서도 총 볼륨 조절」 — the fader is back, as
/// the group's Total: one value with two doors (Q1 「따로 한 값 — 두 입구」).
const double seLayerMixerWidth = 236;

/// What the window stands, for where it opens (above or below the speaker):
/// the margin, the title's line, the gap, the buttons' 26, the gap, the
/// bar and the margin.
const double seLayerMixerHeight = 72 + _barGap + FieldSlider.defaultHeight;

const double _barGap = 8;

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
  /// The Total as the bar is dragged. It writes on RELEASE (the commit-on-
  /// release rule the opacity bars follow): a write is an undo step and
  /// re-uploads the whole live audio schedule, neither a per-move price.
  /// Mute and solo are discrete and land immediately.
  double? _totalDrag;

  /// Every control presses as the speaker that opened the window: inside
  /// a row selection they set every selected SE row.
  SessionRowButtonPresses get _presses =>
      SessionRowButtonPresses(widget.session);

  /// The subject row, found wherever it lives. `session.layers` is EMPTY in
  /// a gap (no active cut), where the storyboard rail keeps its SE controls
  /// mounted — and the track resolver answers the ACTIVE track alone, while
  /// the storyboard carries every track's S rows: the mixer opened blank on
  /// another track's speaker (other-track-s-row-fx-and-mixer, 2026-09-25).
  Layer? get _layer => layerAnywhereOrNull(
    widget.session.repository.requireProject(),
    widget.layerId,
  );

  @override
  Widget build(BuildContext context) {
    // The session is the single source for all three: mute and the Total
    // are the Layer's, solo is session-only monitoring state that is never
    // saved and never exported. Listening to both keeps the window honest
    // when something else moves them.
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.session,
        widget.session.visibilitySolo.soloedSeLayerIds,
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
    final soloed = widget.session.visibilitySolo.soloedSeLayerIds.value
        .contains(layer.id);

    // ⛔No `Material` of its own — the anchored popup carries the window
    // now (R4 #8).
    return Padding(
      key: const ValueKey<String>('se-layer-mixer'),
      padding: AnchoredPopupText.bodyPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnchoredPopupHeader(
            title: layer.name.isEmpty ? strings.layerAudioTitle : layer.name,
          ),
          const SizedBox(height: AnchoredPopupText.titleGap),
          Row(
            children: [
              Expanded(
                child: _MixToggle(
                  keyValue: 'se-mixer-mute',
                  label: strings.audioMute,
                  icon: layer.muted ? Icons.volume_off : Icons.volume_up,
                  on: layer.muted,
                  onPressed: () =>
                      _presses.toggleMute(widget.layerId),
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
                      _presses.toggleSolo(widget.layerId),
                ),
              ),
            ],
          ),
          const SizedBox(height: _barGap),
          FieldSlider(
            key: const ValueKey<String>('se-mixer-total-volume'),
            min: 0,
            max: SeSound.maxVolume,
            value: _totalDrag ?? layer.seSound.totalVolume,
            // The group's lane's own name: one value, two doors.
            label: strings.tlSoundTotalVolume,
            // A share of 1 is 100%: the bar reads it as the lane prints it.
            unit: '%',
            displayScale: 100,
            onChanged: (value) => setState(() => _totalDrag = value),
            onChangeEnd: (value) {
              setState(() => _totalDrag = null);
              _presses.setTotalVolume(widget.layerId, value);
            },
          ),
        ],
      ),
    );
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
      child: ControlPressClaim(
        onPressed: onPressed,
        child: InkWell(
          mouseCursor: AppCursors.press,
          key: ValueKey<String>(keyValue),
          customBorder: AppShapes.container(AppShapes.wellRadius),
          onTap: silentPress(onPressed),
          child: Container(
            height: 26,
            decoration: ShapeDecoration(
              shape: AppShapes.container(
                AppShapes.wellRadius,
                side: BorderSide(color: color),
              ),
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
      ),
    );
  }
}
