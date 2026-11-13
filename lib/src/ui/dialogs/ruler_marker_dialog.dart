import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/app_frame_count_settings.dart';
import '../../models/project_frame_rate.dart';
import '../../models/ruler_marker.dart';
import '../text/app_strings.dart';
import '../theme/ruler_marker_palette.dart';
import '../widgets/app_window.dart';
import '../widgets/frame_count_field.dart';
import '../widgets/pill_strip.dart';
import 'instance_edit_dialog.dart';

/// What the marker window resolved to: the marker as the window left it, or
/// its removal.
class RulerMarkerDialogResult {
  const RulerMarkerDialogResult.kept(RulerMarker this.marker);
  const RulerMarkerDialogResult.deleted() : marker = null;

  /// Null takes the marker off its ruler.
  final RulerMarker? marker;
}

/// A ruler marker's window (I-169), in the block windows' family
/// ([InstanceEditDialogShell]): its text on one line — Enter is the
/// window's primary button, as in an SE block's (F-584) — its colour, and
/// how many frames it runs.
///
/// 🗣️I-169-Q4 (유저 2026-11-13): 「구간 정하는건 마커 편집창에서만
/// 하도록하고. 이유는 프레임블록처럼 버튼같은거 만들면 편할거같긴한데 오히려
/// 룰러만 작동시키려할때 불편할거같음」 — a marker's length is given HERE
/// and by nothing on the ruler.
class RulerMarkerDialog extends StatefulWidget {
  const RulerMarkerDialog({
    super.key,
    required this.marker,
    this.editing = false,
    this.frameRate = ProjectFrameRate.fps24,
    this.onCountEntryChanged,
  });

  /// The marker the window opens on: the one standing over the frame that
  /// was opened, or a new one there.
  final RulerMarker marker;

  /// Whether [marker] stands on its ruler already — the title's wording,
  /// and Delete.
  final bool editing;

  /// The project's rate — what the length is typed against as
  /// seconds+frames ([FrameCountField]).
  final ProjectFrameRate frameRate;

  /// The way a count was just switched to be typed — what every count
  /// window opens on next (I-24-open-entry-Q1).
  final ValueChanged<FrameCountEntry>? onCountEntryChanged;

  @override
  State<RulerMarkerDialog> createState() => _RulerMarkerDialogState();
}

class _RulerMarkerDialogState extends State<RulerMarkerDialog> {
  late final TextEditingController _textController = TextEditingController(
    text: widget.marker.text,
  );

  /// The colour and the length given in this sitting, applied on OK.
  late RulerMarkerColor _color = widget.marker.color;
  late int _length = widget.marker.length;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // The text as typed: a space is a glyph's place on the ribbon, as on an
  // SE block (F-484).
  void _submit() => Navigator.of(context).pop(
    RulerMarkerDialogResult.kept(
      widget.marker.copyWith(
        text: _textController.text,
        color: _color,
        length: _length,
      ),
    ),
  );

  // 🗣️I-169-Q4 (유저 2026-11-13): 「여러 색」 — one of six, always: a
  // grouped choice wears the pills (유저 2026-09-09), each with its ribbon's
  // colour before its name.
  Widget _colorField(AppStrings strings) => AppWindowField(
    label: strings.rulerMarkerColorLabel,
    child: PillStrip(
      items: [
        for (final color in RulerMarkerColor.values)
          PillItem(
            keyValue: 'ruler-marker-color-${color.name}',
            label: _colorName(strings, color),
            selected: _color == color,
            onTap: () => setState(() => _color = color),
            leading: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rulerMarkerRibbon(color),
              ),
              child: const SizedBox.square(dimension: _swatchSize),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return InstanceEditDialogShell(
      title: widget.editing
          ? strings.rulerMarkerEditTitle
          : strings.rulerMarkerNewTitle,
      titleIcon: Icons.bookmark_outline,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppWindowField(
            label: strings.rulerMarkerTextLabel,
            emphasized: true,
            child: TextField(
              key: const ValueKey<String>('ruler-marker-text-field'),
              controller: _textController,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 12),
          _colorField(strings),
          const SizedBox(height: 12),
          // A count of frames, typed in the app's one count field (I-24:
          // 「여러곳에서 쓰일테니 공용화」) — a frame at least, which is the
          // marker that stands on one.
          FrameCountField(
            keyPrefix: 'ruler-marker-length',
            label: strings.rulerMarkerLengthLabel,
            framesPerSecond: widget.frameRate.countingBase,
            initialEntry: AppFrameCountSettings.settings.value.lastEntry,
            count: _length,
            onEntryChanged: widget.onCountEntryChanged,
            onChanged: (count) => setState(() => _length = math.max(1, count)),
          ),
        ],
      ),
      onSubmit: _submit,
      onDelete: widget.editing
          ? () => Navigator.of(
              context,
            ).pop(const RulerMarkerDialogResult.deleted())
          : null,
    );
  }
}

/// The dot a colour's pill wears — the label flyout's (14).
const double _swatchSize = 14;

String _colorName(AppStrings strings, RulerMarkerColor color) =>
    switch (color) {
      RulerMarkerColor.yellow => strings.rulerMarkerColorYellow,
      RulerMarkerColor.orange => strings.rulerMarkerColorOrange,
      RulerMarkerColor.pink => strings.rulerMarkerColorPink,
      RulerMarkerColor.sky => strings.rulerMarkerColorSky,
      RulerMarkerColor.violet => strings.rulerMarkerColorViolet,
      RulerMarkerColor.white => strings.rulerMarkerColorWhite,
    };
