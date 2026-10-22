import 'layer_id.dart';
import 'track_id.dart';

/// WHICH row a timeline-grammar gesture is on.
///
/// The frame axis is shared by three surfaces (the horizontal timeline, the
/// X-sheet, the storyboard), and until now every gesture that crossed one
/// spoke [LayerId] — which is why the storyboard's cut row, whose rows are
/// TRACKS, could not mount the same gesture layer and grew a lookalike of
/// its own. The address is the one thing that actually differs: the drag
/// state machine, the block snap ([snapSpanToBlocks]) and the selection
/// display are the same question on both.
///
/// The verbs a row answers with still differ — a layer row re-times
/// exposures, a track row re-times cuts — and that split lives at the
/// session seam the address is handed to, not in the gesture.
sealed class TimelineRowAddress {
  const TimelineRowAddress();

  /// The row's identity as a widget-key fragment. Layer rows spell out the
  /// bare id — the keys that already read `…-<layerId>` keep reading that
  /// way — and track rows carry a prefix so the two namespaces cannot
  /// collide.
  String get keySuffix;

  /// WHICH LAYER this row belongs to, or null for a row that belongs to no
  /// layer at all (a track's cut row).
  ///
  /// 🚨★★★This exists so nothing has to write `row is LayerRowAddress` again.
  /// That test is not "which layer" — it is "which layer, and lanes do not
  /// count", and the second half was never a rule anyone asked for. It was
  /// typed once per site and then meant something different at each one: a
  /// lane row could not begin a move, could not be recognised as inside the
  /// selection it was visibly inside, and was dropped out of the span the
  /// band had already advertised. The user's law is one line and older than
  /// all of them — 「선택범위는 어떤 레이어를 건너든 자유롭게, 규칙 두지 말
  /// 것」, and [LaneRowAddress]'s own doc says a lane falls back to its
  /// layer rather than refusing.
  ///
  /// ⚠️A verb with no lane meaning is still allowed to say no — ROW ORDER
  /// does, because you cannot re-order a property inside its layer. But it
  /// says so where the verb lives, with a reason, rather than by re-deriving
  /// "is this a real row" from the type.
  ///
  /// ⚠️It answers what a row BELONGS to — the layer you stand on and draw
  /// on — never what a selection holds on it: that is [blockLayerId].
  LayerId? get owningLayerId;

  /// WHOSE BLOCKS this row holds: the layer row's own, and null on a row
  /// whose content is something else — a lane's is keys (an fx header's,
  /// the fx), a cut row's is cuts.
  ///
  /// 🚨F-87 (유저 2026-10-18): 「fx행 선택범위로 선택하고, 삭제버튼누르면
  /// 레이어의 프레임이 삭제됨 … fx를 넘어서 뭐든 선택된 대상으로 버튼의 대상이
  /// 바껴야하는데 법 통일해서 해결하도록」 — and H20 (08-23): 「선택한 곳만
  /// 움직이게하라고」. ↩️A selection read [owningLayerId] for this, so a band
  /// that swept only an fx row held its layer's frames, which nobody swept
  /// and the band never lit: one accessor answered two questions. The user's
  /// law for a selection is 08-12's — 「선택 객체 하나가 종류 섞인 행들을 담고,
  /// 각 동사가 행 종류별로 알아서 처리」 — so a lane row in a band is its own
  /// row, and its layer's blocks are selected when the layer's row is.
  LayerId? get blockLayerId;
}

/// A LAYER's cells row (the timeline and X-sheet grids, the storyboard's SE
/// strips).
final class LayerRowAddress extends TimelineRowAddress {
  const LayerRowAddress(this.layerId);

  final LayerId layerId;

  @override
  LayerId? get owningLayerId => layerId;

  @override
  LayerId? get blockLayerId => layerId;

  @override
  String get keySuffix => layerId.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerRowAddress && other.layerId == layerId;

  @override
  int get hashCode => Object.hash(LayerRowAddress, layerId);

  @override
  String toString() => 'LayerRowAddress($layerId)';
}

/// A LAYER's PROPERTY LANE row — a transform/effect lane, or one of their
/// group headers (R10 #19).
///
/// The third tier of the AE reading the user asked for: a cut, a layer
/// inside it, a property inside that. It is an address rather than a
/// separate selection because "which row is the verb's subject" is ONE
/// question with three answers, not three parallel states — the mistake
/// #13 made and had to undo.
///
/// A lane row is INSIDE a layer, so a verb that has no lane meaning falls
/// back to [layerId] rather than refusing: standing on a property must
/// never cost you the layer you draw on, which is exactly the hazard the
/// user named when asking for selectable fx properties.
///
/// ⚠️STANDING, not selecting: a selection that swept this row holds its
/// keys — and an fx header's fx — never its layer's blocks
/// ([TimelineRowAddress.blockLayerId], F-87).
final class LaneRowAddress extends TimelineRowAddress {
  const LaneRowAddress(this.layerId, this.laneId);

  final LayerId layerId;

  /// The lane's id within its layer ('position', an effect parameter id, or
  /// a group header's).
  final String laneId;

  @override
  LayerId? get owningLayerId => layerId;

  @override
  LayerId? get blockLayerId => null;

  @override
  String get keySuffix => '${layerId.value}-lane-$laneId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaneRowAddress &&
          other.layerId == layerId &&
          other.laneId == laneId;

  @override
  int get hashCode => Object.hash(LaneRowAddress, layerId, laneId);

  @override
  String toString() => 'LaneRowAddress($layerId/$laneId)';
}

/// A TRACK's cut row (the storyboard's V row) — the blocks are cuts on the
/// track-global frame axis.
final class TrackRowAddress extends TimelineRowAddress {
  const TrackRowAddress(this.trackId);

  final TrackId trackId;

  /// A cut row belongs to no layer: its blocks are CUTS.
  @override
  LayerId? get owningLayerId => null;

  @override
  LayerId? get blockLayerId => null;

  @override
  String get keySuffix => 'track-${trackId.value}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackRowAddress && other.trackId == trackId;

  @override
  int get hashCode => Object.hash(TrackRowAddress, trackId);

  @override
  String toString() => 'TrackRowAddress($trackId)';
}
