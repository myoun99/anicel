import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../ui_scale.dart';

/// Preferences ▸ Display: the interface scale (R11).
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
    return ValueListenableBuilder<double>(
      valueListenable: AppUiScale.value,
      builder: (context, scale, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppText.strings.uiScaleLabel, style: textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final stop in AppUiScale.ladder)
                _ScaleStop(
                  stop: stop,
                  selected: stop == scale,
                  onPressed: () => session.setUiScale(stop),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScaleStop extends StatelessWidget {
  const _ScaleStop({
    required this.stop,
    required this.selected,
    required this.onPressed,
  });

  final double stop;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      // Keyed by the PERCENTAGE rather than the index: a stop added or
      // removed later must not silently move another stop's key onto a
      // different number.
      key: ValueKey<String>('ui-scale-stop-${(stop * 100).round()}'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          // Selection is COLOR only (법): no check mark, no swelling
          // border that would move its neighbours when it lands.
          color: selected ? colorScheme.primary.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          AppUiScale.label(stop),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: selected ? colorScheme.primary : null,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
        ),
      ),
    );
  }
}
