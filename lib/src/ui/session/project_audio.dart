import '../../models/project_frame_rate.dart';
import '../../services/commands/update_project_audio_sample_rate_command.dart';
import '../../services/commands/update_project_frame_rate_command.dart';
import 'project_file_door.dart';
import 'project_settings.dart';
import 'session_roles.dart';

/// The PROJECT-WIDE AUDIO SETTINGS — the rate every conform lands at, and
/// the pulldown pull a frame-rate change applies to every sound so it keeps
/// its frame span (EXPORT-AUDIO ③ and ④).
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// G3, 2026-09-07). It owns no state of its own — the facts live in the
/// project — and names the roles and siblings it needs in its constructor.
class ProjectAudio {
  ProjectAudio({
    required ProjectAccess project,
    required ChangeSink changes,
    required ProjectSettings settings,
    required ProjectFileDoor door,
  }) : _project = project,
       _changes = changes,
       _settings = settings,
       _door = door;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ProjectSettings _settings;
  final ProjectFileDoor _door;

  /// Whether any SE row anywhere carries a sound — what decides if a
  /// pulldown-pair rate change even asks the audio question.
  bool get projectHasAnyAudio {
    for (final track in _project.repository.requireProject().tracks) {
      for (final layer in track.seLayers) {
        if (layer.audioClips.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// EXPORT-AUDIO ④, the "frame-exact" choice: sets the rate AND pulls
  /// the audio by the exact pulldown rational (23.976→24 = 1001/1000) so
  /// every sound keeps its frame span — one undo step for both, and the
  /// conforms rebuild at the new speed in the background. Falls back to a
  /// plain rate change when the pair carries no pull.
  void setProjectFrameRateWithAudioPull(ProjectFrameRate frameRate) {
    final pull = audioPullBetween(_settings.projectFrameRate, frameRate);
    if (pull == null) {
      _settings.setProjectFrameRate(frameRate);
      return;
    }
    final project = _project.repository.requireProject();
    // Pulls accumulate — and cancel: 23.976→24→23.976 lands back at 1/1.
    var numerator = project.audioSpeedNumerator * pull.numerator;
    var denominator = project.audioSpeedDenominator * pull.denominator;
    final divisor = numerator.gcd(denominator);
    numerator ~/= divisor;
    denominator ~/= divisor;
    _settings.commitProjectSetting(
      UpdateProjectFrameRateCommand(
        repository: _project.repository,
        frameRate: frameRate,
        audioSpeedNumerator: numerator,
        audioSpeedDenominator: denominator,
      ),
      () {
        _door.warmAudioConforms();
        _changes.warmActiveCut();
      },
    );
  }

  /// The project's audio rate — what every conform lands at (EXPORT-AUDIO
  /// ③).
  int get projectAudioSampleRate =>
      _project.repository.requireProject().audioSampleRate;

  /// Sets the project's audio rate (one undo step, no-op when unchanged).
  /// Existing conforms re-build at the new rate in the background — the
  /// store treats a rate-mismatched entry as stale on its own, so undo
  /// and redo self-heal too.
  void setProjectAudioSampleRate(int sampleRate) {
    if (sampleRate < 8000 ||
        sampleRate > 192000 ||
        sampleRate == projectAudioSampleRate) {
      return;
    }
    _settings.commitProjectSetting(
      UpdateProjectAudioSampleRateCommand(
        repository: _project.repository,
        audioSampleRate: sampleRate,
      ),
      _door.warmAudioConforms,
    );
  }
}
