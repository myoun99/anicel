import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_accents.dart';
import 'package:anicel/src/models/project.dart'
    show defaultProjectBackdropArgb, defaultProjectPasteboardArgb;
import 'package:anicel/src/ui/canvas/stage_planes_painter.dart'
    show stageColorOnScreen;
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/color_mode_rederive.dart';

/// 🗣️I-143: a switch of the palette reaches every colour on screen at once
/// ([ColorModeRederive]) — the parts nothing else would touch included.
void main() {
  tearDown(
    () => AppColors.accentSettings.value = const AppAccentSettings(),
  );

  void wear(AppColorMode mode) => AppColors.accentSettings.value =
      AppColors.accentSettings.value.copyWith(mode: mode);

  testWidgets('a const subtree that reads a token is built again', (
    tester,
  ) async {
    await tester.pumpWidget(const ColorModeRederive(child: _Plate()));
    Color plate() => tester.widget<ColoredBox>(find.byKey(_Plate.box)).color;
    expect(plate(), AppPalette.dark.surface);

    wear(AppColorMode.light);
    await tester.pump();
    expect(plate(), AppPalette.light.surface);
  });

  testWidgets('a painter that answers it need not repaint paints again', (
    tester,
  ) async {
    final painted = <Color>[];
    await tester.pumpWidget(
      ColorModeRederive(
        child: CustomPaint(
          size: const Size.square(10),
          painter: _KeepsItsPicture(painted),
        ),
      ),
    );
    expect(painted, [AppPalette.dark.surface]);

    wear(AppColorMode.light);
    await tester.pump();
    expect(painted, [AppPalette.dark.surface, AppPalette.light.surface]);
  });

  testWidgets('an accent picked builds nothing again', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      ColorModeRederive(child: _Counted(() => builds += 1)),
    );
    expect(builds, 1);

    AppColors.accentSettings.value = const AppAccentSettings(
      accent: Color(0xFF5B9BD5),
    );
    await tester.pump();
    expect(builds, 1, reason: 'the walk is for the palette, not the accent');
  });

  /// 🗣️I-143-Q5 (유저 2026-10-30, 「바닥을 따라 밝게」).
  test('a stage left at the floor wears the floor of the palette worn', () {
    expect(
      const Color(defaultProjectBackdropArgb),
      AppPalette.dark.backdrop,
      reason: 'what a project stores as its start IS the dark floor',
    );
    for (final (mode, floor) in [
      (AppColorMode.dark, AppPalette.dark.backdrop),
      (AppColorMode.light, AppPalette.light.backdrop),
    ]) {
      wear(mode);
      expect(stageColorOnScreen(defaultProjectBackdropArgb), floor);
      expect(stageColorOnScreen(defaultProjectPasteboardArgb), floor);
      expect(stageColorOnScreen(0xFF336699), const Color(0xFF336699));
    }
  });
}

class _Plate extends StatelessWidget {
  const _Plate();

  static const box = ValueKey<String>('plate');

  @override
  Widget build(BuildContext context) =>
      ColoredBox(key: box, color: AppColors.surface);
}

class _Counted extends StatelessWidget {
  const _Counted(this.onBuild);

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.shrink();
  }
}

class _KeepsItsPicture extends CustomPainter {
  _KeepsItsPicture(this.painted);

  final List<Color> painted;

  @override
  void paint(Canvas canvas, Size size) => painted.add(AppColors.surface);

  @override
  bool shouldRepaint(_KeepsItsPicture oldDelegate) => false;
}
