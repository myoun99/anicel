// Pins the catalogue: which glyph each stored group-icon name draws.
//
// The name is the SAVED form, so a face swapping to another entry's glyph is
// a silent change to every library already on disk. This test names the pair
// so that change cannot happen quietly.
import 'package:anicel/src/models/brush_group_icon.dart';
import 'package:anicel/src/ui/brush/brush_group_icon_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('brush group icon glyphs', () {
    const expected = <BrushGroupIcon, IconData>{
      BrushGroupIcon.brush: Icons.brush,
      BrushGroupIcon.pencil: Icons.edit,
      BrushGroupIcon.pen: Icons.create,
      BrushGroupIcon.marker: Icons.border_color,
      BrushGroupIcon.paint: Icons.format_paint,
      BrushGroupIcon.palette: Icons.palette,
      BrushGroupIcon.ink: Icons.water_drop,
      BrushGroupIcon.watercolor: Icons.opacity,
      BrushGroupIcon.airbrush: Icons.blur_on,
      BrushGroupIcon.texture: Icons.texture,
      BrushGroupIcon.grain: Icons.grain,
      BrushGroupIcon.eraser: Icons.cleaning_services,
      BrushGroupIcon.effect: Icons.auto_fix_high,
      BrushGroupIcon.shape: Icons.category,
      BrushGroupIcon.line: Icons.gesture,
      BrushGroupIcon.star: Icons.star,
      BrushGroupIcon.folder: Icons.folder_outlined,
    };

    test('every catalogue entry draws the face it has always drawn', () {
      expect(expected.length, BrushGroupIcon.values.length);
      for (final icon in BrushGroupIcon.values) {
        expect(
          brushGroupIconGlyph(icon),
          expected[icon],
          reason: 'BrushGroupIcon.${icon.name} changed face',
        );
      }
    });

    test('no two entries wear the same face', () {
      final faces = BrushGroupIcon.values.map(brushGroupIconGlyph).toSet();
      expect(faces.length, BrushGroupIcon.values.length);
    });

    test('the stored form round-trips through the enum name', () {
      for (final icon in BrushGroupIcon.values) {
        expect(BrushGroupIcon.byName(icon.name), icon);
      }
      expect(BrushGroupIcon.byName(null), isNull);
      expect(BrushGroupIcon.byName('not-an-icon'), isNull);
    });
  });
}
