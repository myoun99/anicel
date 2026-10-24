import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🪶A LIGHT FACE IS ITS OWN CLAIM (card frame-panels-build-in-one-frame,
/// 2026-10-25): the rail's glyph, the rail's plate and the icon button's
/// face wear [PressClaim] instead of sitting under a [ControlPressClaim].
/// What the claim read from its place in the tree — WHEN it fires
/// ([PressFireScope]) — the face now reads itself, as it is built and as it
/// is rebuilt.
void main() {
  const box = AppIconButtonBox(width: 22, height: 26, iconSize: 16);

  final faces = <String, Widget Function(VoidCallback onPressed)>{
    'rail glyph': (onPressed) => RailGlyphButton(
      name: 'face',
      tooltip: '',
      glyph: const RailIconGlyph(Icons.draw),
      onPressed: onPressed,
      size: box,
    ),
    'rail plate': (onPressed) => RailPlateButton(
      name: 'face',
      tooltip: '',
      onPressed: onPressed,
      child: const SizedBox(width: 30, height: 20),
    ),
    'icon button': (onPressed) => AppIconButton(
      keyValue: 'face',
      tooltip: '',
      icon: const Icon(Icons.draw),
      onPressed: onPressed,
      size: box,
    ),
  };

  for (final MapEntry(key: kind, value: face) in faces.entries) {
    group(kind, () {
      testWidgets('fires as its place says — and again as the place it is '
          'rebuilt in says', (tester) async {
        final said = <String>[];
        late StateSetter rebuild;
        var fireOn = PressFire.down;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return PressFireScope(
                    fireOn: fireOn,
                    child: face(() => said.add(fireOn.name)),
                  );
                },
              ),
            ),
          ),
        );
        final at = tester.getCenter(find.byType(PressFireScope));

        final column = await tester.startGesture(at);
        expect(said, ['down'], reason: 'built in a column: fires on the press');
        await column.up();
        expect(said, ['down']);

        rebuild(() => fireOn = PressFire.upInside);
        await tester.pump();
        final button = await tester.startGesture(at);
        expect(said, ['down'], reason: 'rebuilt as a button: not yet');
        await button.up();
        expect(said, ['down', 'upInside']);
      });

      testWidgets('is the one box that claims — no claim stands over it', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Center(child: face(() {})),
          ),
        );
        // Every element above a render object answers with it: count boxes.
        expect(
          tester.allRenderObjects.whereType<PressClaim>().toSet(),
          hasLength(1),
        );
        expect(find.byType(ControlPressClaim), findsNothing);
      });
    });
  }
}
