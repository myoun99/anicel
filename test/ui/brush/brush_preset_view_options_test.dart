import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_preset_view_options.dart';

/// F-73 ①: the brush library's five view toggles, as the layout file keeps
/// them.
void main() {
  test('every toggle round-trips through the layout file', () {
    const options = BrushPresetViewOptions(
      showTipIcon: false,
      showStrokePreview: true,
      showName: false,
      railShowIcon: true,
      railShowName: false,
    );

    expect(BrushPresetViewOptions.fromJson(options.toJson()), options);
  });

  test('a file from before a toggle existed opens it on, as it always did', () {
    expect(
      BrushPresetViewOptions.fromJson(const {}),
      const BrushPresetViewOptions(),
    );
    expect(
      BrushPresetViewOptions.fromJson(const {'name': 'no', 'railIcon': 1}),
      const BrushPresetViewOptions(),
      reason: 'a key that is not a bool is its default',
    );
  });

  test('⛔a file that hides everything opens that group at its defaults — the '
      'menu can never make a blank row or a blank tab', () {
    expect(
      BrushPresetViewOptions.fromJson(const {
        'tipIcon': false,
        'strokePreview': false,
        'name': false,
        'railIcon': false,
        'railName': false,
      }),
      const BrushPresetViewOptions(),
    );
    expect(
      BrushPresetViewOptions.fromJson(const {
        'tipIcon': false,
        'strokePreview': false,
        'name': true,
        'railIcon': false,
        'railName': false,
      }),
      const BrushPresetViewOptions(showTipIcon: false, showStrokePreview: false),
      reason: 'only the group that shows nothing is put back',
    );
  });
}
