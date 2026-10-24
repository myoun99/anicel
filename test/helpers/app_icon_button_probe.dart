import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

/// What a test reads off an icon button — whichever family wears the face
/// its key names: the app's [AppIconButton], or the rail's
/// [RailGlyphButton] (I-57 ①, 10-09).
final class IconButtonReading {
  IconButtonReading._({
    required this.tooltip,
    required this.onPressed,
    required this.isSelected,
    required this.danger,
    required this.icon,
    required this.iconColor,
    required this.shortcuts,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool isSelected;
  final bool danger;

  /// The icon the face wears; null when it wears a word or another widget.
  final IconData? icon;

  /// The colour the glyph asks for itself — null where it wears the
  /// button's ink, as an [Icon] with no colour does.
  final Color? iconColor;

  /// The actions the button names (`shortcuts:` — I-40); none on a rail
  /// button, which names no action.
  final List<String> shortcuts;
}

/// Reads an icon button through the finder a test already holds for its
/// KEY.
///
/// The key names the FACE — [AppIconButtonFace], or [RailGlyphButton] on a
/// rail — the box you see and press, and tests used to read `onPressed` /
/// `isSelected` / `tooltip` off the Material `IconButton` that stood in that
/// spot. That button is gone (2026-09-10: it was 27 render objects a button
/// and 47% of the idle screen), so this climbs from the face to the widget
/// whose PUBLIC API those fields are — or reads the rail's button, which is
/// its own face.
///
/// ⚠️`onPressed` read here is the REAL callback, where the old read got the
/// silent one the claim hands down. Every test that reads it only asks
/// whether it is null — the same answer from both — and none invokes it
/// (checked across all 37 reads on 2026-09-10). A test that wants to FIRE a
/// button taps it, which goes through the claim like a finger does.
extension AppIconButtonProbe on WidgetTester {
  IconButtonReading appIconButton(Finder face) {
    final app = find.ancestor(of: face, matching: find.byType(AppIconButton));
    if (app.evaluate().isNotEmpty) {
      final button = widget<AppIconButton>(app);
      final icon = button.icon;
      return IconButtonReading._(
        tooltip: button.tooltip,
        onPressed: button.onPressed,
        isSelected: button.isSelected,
        danger: button.danger,
        icon: icon is Icon ? icon.icon : null,
        iconColor: icon is Icon ? icon.color : null,
        shortcuts: button.shortcuts,
      );
    }
    // A rail's button IS its face.
    final button = widget<RailGlyphButton>(face);
    final glyph = button.glyph;
    return IconButtonReading._(
      tooltip: button.tooltip,
      onPressed: button.onPressed,
      isSelected: button.isSelected,
      danger: button.danger,
      icon: glyph is RailIconGlyph ? glyph.icon : null,
      iconColor: glyph is RailIconGlyph ? glyph.color : null,
      shortcuts: const [],
    );
  }

  /// The one icon button inside [scope] — for a test that holds the widget
  /// wrapping a button rather than the button's key.
  IconButtonReading iconButtonIn(Finder scope) => appIconButton(
    find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIconButtonFace || widget is RailGlyphButton,
      ),
    ),
  );

  /// The colour [face]'s glyph is painted in right now — its ink for the
  /// state the button is in, or the glyph's own colour where it has one.
  Color? glyphInkOf(Finder face) {
    if (widget(face) is RailGlyphButton) {
      return renderObject<RenderRailGlyphFace>(face).debugGlyphInk;
    }
    final icon = find.descendant(of: face, matching: find.byType(Icon));
    return widget<Icon>(icon).color ?? IconTheme.of(element(icon)).color;
  }
}

/// `find.byIcon` and `find.text` for the rail's buttons: a [RailGlyphButton]
/// draws its glyph itself and holds no [Icon] or [Text] to find.
extension RailGlyphFinders on CommonFinders {
  /// The rail faces wearing [icon].
  Finder railIcon(IconData icon) => byWidgetPredicate(
    (widget) => widget is RailGlyphButton && switch (widget.glyph) {
      RailIconGlyph(icon: final worn) => worn == icon,
      RailTextGlyph() => false,
    },
  );

  /// The rail faces wearing the word [text].
  Finder railText(String text) => byWidgetPredicate(
    (widget) => widget is RailGlyphButton && switch (widget.glyph) {
      RailTextGlyph(text: final worn) => worn == text,
      RailIconGlyph() => false,
    },
  );

  /// The light faces whose tooltip is [message] — `find.byTooltip` for a
  /// face that summons the one window instead of holding a `Tooltip`: the
  /// rail's glyph, the rail's plate ([RailPlateButton]) and the app's icon
  /// button ([AppIconButton], since 2026-10-24).
  Finder railTooltip(String message) => byWidgetPredicate(
    (widget) => switch (widget) {
      RailGlyphButton(:final tooltip) ||
      RailPlateButton(:final tooltip) ||
      IconButtonPressFace(:final tooltip) => tooltip == message,
      _ => false,
    },
  );
}
