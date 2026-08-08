import 'package:flutter/material.dart';

import '../models/layer_effect.dart';
import 'editor_session_manager.dart';
import 'text/app_strings.dart';
import 'widgets/panel_flyout.dart';

/// The V row's fx entrance — the storyboard's counterpart of the timeline's
/// Layer ▾ Effects section (user 2026-08-08: "스토리보드패널에서 글로벌트랙인
/// v행에 fx를 걸게").
///
/// It lives on the command bar rather than growing another control on the V
/// row, for the reason the layer effects entrance gives: the row is already
/// crowded, and adding an effect is a command, not a per-row switch. Once an
/// effect exists, its own lanes carry the work — the bypass glyph on its
/// group header, its parameters, its keys.
class TrackFxCommandGroup extends StatelessWidget {
  const TrackFxCommandGroup({super.key, required this.session});

  final EditorSessionManager session;

  List<PanelFlyoutEntry> _entries() {
    // The V row being worked: the selected track, which is the one holding
    // the active cut ([EditorSessionManager.activeTrack]'s rule).
    final track = session.activeTrack;
    return [
      PanelFlyoutHeader(AppText.strings.tlEffects),
      for (final kind in EffectKind.values)
        PanelFlyoutItem(
          keyValue: 'storyboard-add-track-effect-${kind.jsonValue}',
          label: AppText.strings.tlAddEffectTemplate.replaceAll(
            '{name}',
            kind.labelFor(AppText.language),
          ),
          icon: Icons.auto_fix_high_outlined,
          onSelected: () => session.addEffectToTrack(track.id, kind),
        ),
      for (final effect in track.effects)
        PanelFlyoutItem(
          keyValue: 'storyboard-remove-track-effect-${effect.id.value}',
          label: AppText.strings.tlRemoveEffectTemplate.replaceAll(
            '{name}',
            effect.kind.labelFor(AppText.language),
          ),
          icon: Icons.remove_circle_outline,
          danger: true,
          onSelected: () => session.removeEffectFromTrack(track.id, effect.id),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PanelFlyoutButton(
      key: const ValueKey<String>('storyboard-track-fx-menu-button'),
      label: 'V',
      tooltip: AppText.strings.sbTrackFxCommands,
      entriesBuilder: _entries,
    );
  }
}
