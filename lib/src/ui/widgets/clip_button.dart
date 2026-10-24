import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_icon_button.dart';
import 'rail_glyph_button.dart';

/// A row's CLIP TO LAYER BELOW ([Layer.clipsToBelow], I-92) as the rail's
/// button — on every row that can clip ([LayerKind.takesClipping]).
///
/// ↩️It was the fill-reference bucket (R20-C2), with a twin for the ACTIVE
/// layer in the fill's tool settings (I-36); the twin went with the fill's
/// reference answer (I-92: 「그런버튼 삭제하고」).
///
/// The rail's face ([RailGlyphButton]): a cut switch mounts every visible
/// row anew (I-57 ①).
class ClipButton extends StatelessWidget {
  const ClipButton({
    super.key,
    required this.name,
    required this.isOn,
    required this.onPressed,
    this.size = AppIconButtonSize.bar,
  });

  /// What a finder calls the button — its [RailGlyphButton.name].
  final String name;
  final bool isOn;
  final VoidCallback? onPressed;
  final AppIconButtonMetrics size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RailGlyphButton(
      name: name,
      tooltip: isOn ? AppText.strings.railClipOn : AppText.strings.railClip,
      size: size,
      glyph: RailIconGlyph(
        Icons.vertical_align_bottom,
        color: isOn
            ? colorScheme.primary
            : colorScheme.outline.withValues(alpha: 0.45),
      ),
      onPressed: onPressed,
    );
  }
}
