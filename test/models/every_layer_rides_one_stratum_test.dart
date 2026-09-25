import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';

/// Every layer a sheet prints is baked in exactly one stratum.
///
/// The panels mount a painter per stratum and the timesheet's PNG paints
/// its page stratum by stratum ([SheetStratum]), so a layer no stratum
/// named would print nowhere — the paper left out of the form stratum put
/// no sheet under any of the three panels, and no other test said so.
void main() {
  test('the strata name every layer, none twice', () {
    final named = [
      for (final stratum in SheetStratum.values) ...stratum.layers,
    ];
    expect(named.toSet(), SheetPaintLayer.values.toSet());
    expect(named, hasLength(SheetPaintLayer.values.length));
  });

  test('the paper rides with the form, bottom of the stack', () {
    expect(SheetStratum.values.first, SheetStratum.form);
    expect(SheetStratum.form.layers, {
      SheetPaintLayer.paper,
      SheetPaintLayer.form,
    });
  });
}
