import '../../models/layer_id.dart';
import '../../services/editing/default_layer_helpers.dart';
import '../../services/project_lookup.dart' show projectLayerIdValues;
import 'session_roles.dart';

/// WHERE A NEW ROW'S ID COMES FROM: the `default-layer-N` counter, and the
/// project scan that keeps it honest.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (round 8's G3,
/// 2026-09-07). The counter was a bare `int` field on the host reachable
/// from three collaborators through `SessionInternals`; it owns its state
/// here, and those three hold this by constructor.
class LayerIdMint {
  LayerIdMint({required ProjectAccess project}) : _project = project;

  final ProjectAccess _project;

  int _sequence = 1;

  /// The next unused `default-layer-N`.
  ///
  /// The counter alone is not enough, and the reason is that it is SESSION
  /// state while the project can arrive from DISK. Open a file that already
  /// holds `default-layer-2` and the counter is still 1, so the next added
  /// layer is minted straight on top of an existing row: two layers, one id.
  /// It surfaced as a red screen from the rail (`multiple children with key
  /// …default-layer-2-row`), which is why the fix is here and not there — a
  /// duplicate key is what a duplicate id looks like downstream.
  ///
  /// So the project has the last word, exactly as it already does for
  /// imported cut ids ([ImportLanding.idMint]). The counter still carries a
  /// BATCH, where ids minted a moment ago are not in the project yet.
  ///
  /// [usedIds] lets a caller minting MANY ids hand the scan in once; see
  /// [ImportLanding.idMint], which is the only such caller.
  LayerId mint({Set<String>? usedIds}) {
    final used =
        usedIds ?? projectLayerIdValues(_project.repository.requireProject());
    _sequence += 1;
    var candidate = defaultLayerIdForSequence(_sequence);
    while (used.contains(candidate.value)) {
      _sequence += 1;
      candidate = defaultLayerIdForSequence(_sequence);
    }
    return candidate;
  }
}
