import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../models/app_accents.dart';
import 'app_theme.dart';

/// Holds [child] and, the moment the palette changes (I-143), builds and
/// paints the whole app again — once.
///
/// ⚠️The chrome reads [AppColors] where it builds and where it paints, not
/// from an inherited theme: a const subtree is never rebuilt by its parent,
/// and a painter that compares its own fields answers that it need not
/// repaint. Without this a switch left every part nothing else touched in
/// the old palette — a screen half dark and half light until each part
/// happened to rebuild.
class ColorModeRederive extends StatefulWidget {
  const ColorModeRederive({super.key, required this.child});

  final Widget child;

  @override
  State<ColorModeRederive> createState() => _ColorModeRederiveState();
}

class _ColorModeRederiveState extends State<ColorModeRederive> {
  AppColorMode _mode = AppColors.mode;

  @override
  void initState() {
    super.initState();
    AppColors.accentSettings.addListener(_changed);
  }

  @override
  void dispose() {
    AppColors.accentSettings.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final mode = AppColors.mode;
    if (mode == _mode) {
      return;
    }
    _mode = mode;
    rederiveEverything();
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
