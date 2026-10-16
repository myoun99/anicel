import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../services/project_lookup.dart' show layerAnywhereOrNull;
import 'session_roles.dart';

/// THE row a write names by id — the fx switches' and the lane verbs'.
extension RowWrittenById on ProjectAccess {
  /// The row a write of [layerId] addresses: [ProjectAccess.commitLayerById]
  /// — the row every layer op commits against, a track-owned SE row's
  /// GLOBAL form and not its cut's projection — and where that knows
  /// nothing, the row wherever it lives.
  ///
  /// ⛔A private `fxSwitchLayerById` restated it as 「cut layer, else the SE
  /// row」 and asked the cut FIRST, which hands back the projection: a chain
  /// built from it lands on the track at the cut's frames
  /// (se-row-fx-write-path's third pin).
  ///
  /// 🚨AND WHERE THAT KNOWS NOTHING, THE ROW WHEREVER IT LIVES
  /// (other-track-s-row-fx-and-mixer, measured 2026-09-25): the storyboard
  /// rail carries every track's S rows, and `commitLayerById` answers a
  /// track row from the ACTIVE track alone — another track's fx read
  /// 「on」 forever and its press did nothing. The model walk returns the
  /// global form too, never a projection. `commitLayerById` itself stays
  /// as it is: its timing callers work inside the active cut's window.
  ///
  /// A cut's row not stood in is found the same way (I-89-Q23): a header
  /// graph's line of that cut is edited there, by the lane verbs. ↩️They
  /// asked `commitLayerById` alone, and its handle wrote nothing.
  Layer? rowWrittenById(LayerId layerId) =>
      commitLayerById(layerId) ??
      layerAnywhereOrNull(repository.requireProject(), layerId);
}
