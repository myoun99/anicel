import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart';

import '../theme/app_theme.dart';

/// One tab in an [AppWindow]'s strip. The window renders the strip; the
/// caller owns which one is selected, so Export's domains and Preferences'
/// sections drive the SAME widget rather than two look-alikes.
class AppWindowTab {
  const AppWindowTab({
    required this.label,
    required this.onSelected,
    this.tabKey,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onSelected;
  final Key? tabKey;
  final bool enabled;
}

/// A footer action. The footer divides its width EVENLY among these — a
/// window never right-aligns a small pair against dead space, at any width.
class AppWindowAction {
  const AppWindowAction({
    required this.label,
    required this.onPressed,
    this.actionKey,
    this.emphasis = AppWindowActionEmphasis.quiet,
    this.tooltip,
  });

  final String label;

  /// Null disables the button (nothing selected yet, name still empty).
  final VoidCallback? onPressed;
  final Key? actionKey;
  final AppWindowActionEmphasis emphasis;

  /// The consequence, for an action whose label cannot hold it.
  ///
  /// ⚠️ A SECOND line of defence, never the only one. A pen hovering an
  /// iPad does raise a tooltip — but a finger never does, and nor does an
  /// older tablet. So the label still has to carry the verb on its own;
  /// this carries the detail that would not fit, for the pointer that
  /// happens to be there.
  final String? tooltip;
}

enum AppWindowActionEmphasis {
  /// The confirm action — accent fill. At most one per window.
  primary,

  /// Cancel/close — filled, but in the raised surface.
  quiet,

  /// Delete and friends — quiet fill, danger ink.
  danger,
}

/// The app's ONE window shell.
///
/// Chrome, top to bottom: a title bar the same height and colour as
/// [EditorPanelHeader] (a window is a floating panel, and should read as
/// one), an optional tab strip with an accent underline, the body, and a
/// footer whose actions split the full width evenly.
///
/// Every dialog in the app is expected to be this widget with a different
/// [body] — a redesign lands here and nowhere else. Call sites keep their
/// own action keys ([AppWindowAction.actionKey]) so existing tests and
/// muscle memory survive the move.
class AppWindow extends StatelessWidget {
  const AppWindow({
    super.key,
    required this.title,
    required this.body,
    this.titleIcon,
    this.windowKey,
    this.tabs = const <AppWindowTab>[],
    this.selectedTab = 0,
    this.actions = const <AppWindowAction>[],
    this.footerNote,
    this.onClose,
    this.width,
    this.minWidth = 264,
    this.maxWidth = 720,
    this.height,
    this.scrollBody = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 14, 12, 12),
  });

  final String title;
  final IconData? titleIcon;
  final Widget body;

  /// Identifies the surface for tests; the shell's own chrome carries no
  /// key so two windows never collide.
  final Key? windowKey;

  final List<AppWindowTab> tabs;
  final int selectedTab;

  /// Left to right. The confirm action goes last, the way the platform
  /// reads.
  final List<AppWindowAction> actions;

  /// A status line ABOVE the action row (export progress, a warning).
  /// It gets its own row because the actions own the footer's full width —
  /// there is no leftover strip beside them to put it in.
  final Widget? footerNote;

  /// Null hides the close button (a window that must be answered).
  final VoidCallback? onClose;

  /// A fixed width, or null to size between [minWidth] and [maxWidth].
  final double? width;
  final double minWidth;
  final double maxWidth;
  final double? height;

  /// Whether the body scrolls when it outgrows the window. Off for bodies
  /// that scroll internally (lists, the Export zones).
  final bool scrollBody;
  final EdgeInsetsGeometry bodyPadding;

  static const double titleBarHeight = 32;
  static const double tabBarHeight = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(padding: bodyPadding, child: this.body);
    return Dialog(
      key: windowKey,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: width ?? minWidth,
          maxWidth: width ?? maxWidth,
        ),
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleBar(context, theme),
              if (tabs.isNotEmpty) _tabBar(theme),
              if (height != null)
                Expanded(child: scrollBody ? _scrolled(body) : body)
              else if (scrollBody)
                Flexible(child: _scrolled(body))
              else
                Flexible(child: body),
              if (actions.isNotEmpty || footerNote != null) _footer(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrolled(Widget body) =>
      SingleChildScrollView(primary: false, child: body);

  Widget _titleBar(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      height: titleBarHeight,
      padding: EdgeInsets.only(left: 10, right: onClose == null ? 10 : 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (titleIcon != null) ...[
            Icon(titleIcon, size: 14, color: AppColors.accent),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 14),
              iconSize: 14,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              visualDensity: VisualDensity.compact,
              color: colorScheme.onSurfaceVariant,
              tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            ),
        ],
      ),
    );
  }

  Widget _tabBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      height: tabBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      // Scrolls rather than overflows: a window may carry more tabs than
      // its width fits (Preferences has seven, one of them long), and the
      // strip must never be the thing that decides the window's width.
      // ⚠️A test that taps a tab must `ensureVisible` it first — the
      // seventh section landed past the right edge and `tap()` missed.
      child: UnbarredScrollable(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) _tab(theme, tabs[i], i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(ThemeData theme, AppWindowTab tab, int index) {
    final selected = index == selectedTab;
    final accent = theme.colorScheme.primary;
    return InkWell(
      key: tab.tabKey,
      onTap: !tab.enabled || selected ? null : tab.onSelected,
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.fromLTRB(11, 0, 11, 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? accent : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          tab.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? accent
                : tab.enabled
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    final footerNote = this.footerNote;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (footerNote != null) ...[
            footerNote,
            if (actions.isNotEmpty) const SizedBox(height: 8),
          ],
          if (actions.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _actionButton(theme, actions[i])),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _actionButton(ThemeData theme, AppWindowAction action) {
    final hint = action.tooltip;
    final button = _actionButtonBody(theme, action);
    return hint == null ? button : Tooltip(message: hint, child: button);
  }

  Widget _actionButtonBody(ThemeData theme, AppWindowAction action) {
    final colorScheme = theme.colorScheme;
    final label = Text(action.label);
    return switch (action.emphasis) {
      AppWindowActionEmphasis.primary => FilledButton(
        key: action.actionKey,
        onPressed: action.onPressed,
        child: label,
      ),
      // These two carry no border, so with one chrome fill they would be
      // invisible rectangles on the window body. A quiet action reads as a
      // well sunk into the surface — the same level every field already uses
      // — which also puts it a step BELOW the confirm rather than beside it.
      AppWindowActionEmphasis.quiet => TextButton(
        key: action.actionKey,
        onPressed: action.onPressed,
        style: TextButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerLowest,
        ),
        child: label,
      ),
      AppWindowActionEmphasis.danger => TextButton(
        key: action.actionKey,
        onPressed: action.onPressed,
        style: TextButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerLowest,
          foregroundColor: colorScheme.error,
        ),
        child: label,
      ),
    };
  }
}

/// A labelled row in an [AppWindow] body: an 11px cap above the control,
/// never a floating label inside it (a floated label eats the field's own
/// height and reads as a placeholder half the time).
class AppWindowField extends StatelessWidget {
  const AppWindowField({
    super.key,
    required this.label,
    required this.child,
    this.emphasized = false,
  });

  final String label;
  final Widget child;

  /// The field the window is really about (the name being typed) — its cap
  /// takes the accent.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: emphasized
                  ? AppColors.accent
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
