import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project.dart';

/// EXPORT-AUDIO ③: the audio rate is PROJECT state, defaulting to the
/// film-standard 48k and omitted from JSON at the default so existing
/// files keep their exact bytes.
void main() {
  test('defaults to 48k and stays OUT of the JSON at the default', () {
    final project = createDefaultProject();
    expect(project.audioSampleRate, defaultProjectAudioSampleRate);
    expect(project.toJson().containsKey('audioSampleRate'), isFalse);
    // A legacy file (no key) opens at the default.
    expect(
      Project.fromJson(project.toJson()).audioSampleRate,
      defaultProjectAudioSampleRate,
    );
  });

  test('a non-default rate round-trips through JSON', () {
    final project = createDefaultProject().copyWith(audioSampleRate: 44100);
    final json = project.toJson();
    expect(json['audioSampleRate'], 44100);
    expect(Project.fromJson(json).audioSampleRate, 44100);
  });

  test('nonsense rates fall back to the default rather than propagate', () {
    expect(
      createDefaultProject().copyWith(audioSampleRate: 0).audioSampleRate,
      defaultProjectAudioSampleRate,
    );
  });
}
