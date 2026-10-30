import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// Holds [child] and, the moment the colours worn change — the palette
/// (I-143) or the accent (F-508) — builds and paints the whole app again,
/// once.
///
/// ⚠️The chrome reads [AppColors] where it builds and where it paints, not
/// from an inherited theme: a const subtree is never rebuilt by its parent,
/// and a painter that compares its own fields answers that it need not
/// repaint. Without this a switch left every part nothing else touched in
/// the old palette — a screen half dark and half light until each part
/// happened to rebuild.
///
/// ↩️It walked for the palette only, and a new accent left the add-layer
/// and stabilizer buttons in the old one until a hover rebuilt them
/// (F-508). The accent is picked from a row of swatches, one press at a
/// time, so the walk costs no more there than on the palette's switch.
class AppColorsRederive extends StatefulWidget {
  const AppColorsRederive({super.key, required this.child});

  final Widget child;

  @override
  State<AppColorsRederive> createState() => _AppColorsRederiveState();
}

class _AppColorsRederiveState extends State<AppColorsRederive> {
  @override
  void initState() {
    super.initState();
    AppColors.accentSettings.addListener(rederiveEverything);
  }

  @override
  void dispose() {
    AppColors.accentSettings.removeListener(rederiveEverything);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Marks every element to build and every render object to paint, as a
/// reassemble does — the dialogs and popups too, which are the Navigator's
/// overlay's and not any page's.
void rederiveEverything() {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(rebuild);

  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  RendererBinding.instance.renderViews.forEach(repaint);
}
