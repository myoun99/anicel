import 'package:flutter/material.dart';

import '../../models/app_frame_grid_settings.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../ui_scale.dart';
import '../widgets/pill_strip.dart';
import '../widgets/settings_rows.dart';

/// Preferences ▸ Display: the interface scale (R11), and whether the frame
/// lines cross a block's paper (유저 2026-09-24).
///
/// A LADDER, not a slider (유저 확정 2026-08-21: "배율을 사다리로"). Six
/// stops around 100%, which is where a hand actually lands — and a
/// continuous control would multiply the monitor's ratio into an
/// unbounded set of effective ratios, none of which any pin could name.
///
/// ⛔The document views do not follow it. The canvas, the media viewer,
/// the conte, the cut envelope and the timesheet keep their own zoom;
/// that is a decision the user drew by KIND, and it lives at
/// `CanvasZoomScale`, not here.
class DisplaySettingsSection extends StatelessWidget {
  const DisplaySettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppText.strings.uiScaleLabel, style: textTheme.titleSmall),
        const SizedBox(height: 8),
        ValueListenableBuilder<double>(
          valueListenable: AppUiScale.value,
          // The app's one grouped choice (board pill-group-everywhere): its
          // pills change colour and nothing else, so a stop landing never
          // moves its neighbours.
          builder: (context, scale, _) => PillStrip(
            items: [
              for (final stop in AppUiScale.ladder)
                PillItem(
                  // Keyed by the PERCENTAGE rather than the index: a stop
                  // added or removed later must not silently move another
                  // stop's key onto a different number.
                  keyValue: 'ui-scale-stop-${(stop * 100).round()}',
                  label: AppUiScale.label(stop),
                  selected: stop == scale,
                  onTap: () => session.setUiScale(stop),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<AppFrameGridSettings>(
          valueListenable: AppFrameGridSettings.settings,
          builder: (context, grid, _) => SettingsSwitchRow(
            tileKey: const ValueKey<String>('settings-block-frame-lines'),
            label: AppText.strings.blockFrameLinesLabel,
            value: grid.blockFrameLines,
            onChanged: (shown) => session.appSettings.setFrameGridSettings(
              grid.copyWith(blockFrameLines: shown),
            ),
          ),
        ),
      ],
    );
  }
}
