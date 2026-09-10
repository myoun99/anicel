import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// Reads an [AppIconButton] through the finder a test already holds for its
/// KEY.
///
/// The key names the [AppIconButtonFace] — the box you see and press — and
/// tests used to read `onPressed` / `isSelected` / `tooltip` off the Material
/// `IconButton` that stood in that spot. That button is gone (2026-09-10: it
/// was 27 render objects a button and 47% of the idle screen), so this climbs
/// from the face to the widget whose PUBLIC API those three fields are.
///
/// ⚠️`onPressed` read here is the REAL callback, where the old read got the
/// silent one the claim hands down. Every test that reads it only asks
/// whether it is null — the same answer from both — and none invokes it
/// (checked across all 37 reads on 2026-09-10). A test that wants to FIRE a
/// button taps it, which goes through the claim like a finger does.
extension AppIconButtonProbe on WidgetTester {
  AppIconButton appIconButton(Finder face) => widget<AppIconButton>(
    find.ancestor(of: face, matching: find.byType(AppIconButton)),
  );
}
