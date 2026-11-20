import 'package:flutter/material.dart';

import '../../models/media_asset.dart' show MediaFitMode;
import '../widgets/panel_flyout.dart';
import 'import_file_settings.dart' show importFitLabel;

/// The fit as a list of its three, in their one spelling ([importFitLabel]):
/// a media preset's (where a picture placed from the pool starts), and a
/// canvas resize's, typed into its window or dragged on the canvas
/// (I-180-Q6 a: 「알약에도 같은 맞춤 칸」).
///
/// ↩️The preset window built its own; a canvas resize's two made it three.
class FitFlyoutButton extends StatelessWidget {
  const FitFlyoutButton({
    super.key,
    required this.keyPrefix,
    required this.fit,
    required this.onPicked,
    this.expand = false,
  });

  /// The button's key and each choice's (`<keyPrefix>-<fit>`).
  final String keyPrefix;
  final MediaFitMode fit;
  final ValueChanged<MediaFitMode> onPicked;
  final bool expand;

  @override
  Widget build(BuildContext context) => PanelFlyoutButton(
    key: ValueKey<String>(keyPrefix),
    label: importFitLabel(fit),
    expand: expand,
    entriesBuilder: () => MediaFitMode.values.asFlyoutValueChoices(
      current: fit,
      choiceOf: (choice) => PanelFlyoutChoice(
        key: '$keyPrefix-${choice.name}',
        label: importFitLabel(choice),
      ),
      onPicked: onPicked,
    ),
  );
}
