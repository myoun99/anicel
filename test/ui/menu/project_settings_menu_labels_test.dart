// THE PROJECT SETTINGS' LABELS: A SAMPLE RATE READS IN KILOHERTZ, WHOLE
// WHEN IT DIVIDES, ONE DECIMAL WHEN IT DOES NOT; THE FRAME-RATE MENU IS
// THE MODEL'S PRESET LIST.
//
// No test named this file (audit 2026-09-03). These pins cover the pure
// rules it states; the menu's rows are exercised through the panels.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/menu/project_settings_menu.dart';

void main() {
  test('a sample rate reads in kilohertz', () {
    expect(ProjectSettingsMenu.audioSampleRateLabel(48000), '48kHz');
    expect(ProjectSettingsMenu.audioSampleRateLabel(96000), '96kHz');
    expect(ProjectSettingsMenu.audioSampleRateLabel(44100), '44.1kHz');
  });

  test('the audio presets are film, music, and the high rate', () {
    expect(ProjectSettingsMenu.audioSampleRatePresets, [44100, 48000, 96000]);
  });

  test('the frame-rate menu is the model\'s preset list', () {
    expect(ProjectSettingsMenu.fpsPresets, ProjectFrameRate.presets);
    expect(ProjectSettingsMenu.fpsPresets, contains(ProjectFrameRate.fps24));
  });
}
