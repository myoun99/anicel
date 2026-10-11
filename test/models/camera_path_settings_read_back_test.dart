import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_path_settings.dart';

/// How the canvas shows a camera's path (I-89 ④), as its store keeps it.
void main() {
  test('what is written reads back as it was', () {
    const settings = CameraPathSettings(
      show: CameraPathShow.off,
      range: CameraPathRange.aroundPlayhead,
      tickEvery: 6,
      around: 3,
    );
    expect(CameraPathSettings.fromJson(settings.toJson()), settings);
  });

  test('a field missing or out of reach reads as its default, and the '
      'fields beside it as they were written', () {
    const defaults = CameraPathSettings();
    expect(
      CameraPathSettings.fromJson({
        'show': 'everything',
        'range': 'aroundPlayhead',
        'tickEvery': 0,
        'around': '12',
      }),
      CameraPathSettings(
        show: defaults.show,
        range: CameraPathRange.aroundPlayhead,
        tickEvery: defaults.tickEvery,
        around: defaults.around,
      ),
    );
    expect(
      CameraPathSettings.fromJson({'show': 'space', 'around': 1}),
      CameraPathSettings(
        show: CameraPathShow.space,
        range: defaults.range,
        tickEvery: defaults.tickEvery,
        around: 1,
      ),
      reason: 'one frame either side is in reach',
    );
  });
}
