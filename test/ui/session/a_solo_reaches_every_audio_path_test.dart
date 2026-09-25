import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨The SE solo narrows EVERY audio path to the soloed rows — the device
/// transport, the scrubber and the frame-synced fallback each read it
/// through the playback rig. The set lives with the toggle that writes it
/// (`VisibilitySolo`, ARCH-session-state's fifth family, 2026-09-25) and the
/// rig takes it by constructor; the narrowing itself is pinned below the rig
/// (`the_se_window_on_the_track_axis_test`), and this pins that all three
/// paths still hear the one set.
void main() {
  test('a solo reaches all three audio paths, and so does leaving it', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    const row = LayerId('a-soloed-se-row');
    final rig = session.playbackRig;
    final paths = <String, Set<LayerId> Function()?>{
      'the device transport': rig.audioDeviceTransport.resolveSoloedLayerIds,
      'the scrubber': rig.audioScrubber.resolveSoloedLayerIds,
      'the frame-synced fallback':
          rig.audioPlaybackSync.resolveSoloedLayerIds,
    };
    void expectEvery(Set<LayerId> soloed, String when) {
      for (final path in paths.entries) {
        expect(path.value?.call(), soloed, reason: '${path.key}, $when');
      }
    }

    expectEvery(const {}, 'before any solo');
    session.visibilitySolo.toggleLayerSolo(row);
    expectEvery({row}, 'once the row is soloed');
    session.visibilitySolo.toggleLayerSolo(row);
    expectEvery(const {}, 'once the solo is left');
  });
}
