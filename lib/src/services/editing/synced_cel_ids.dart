import '../../models/attached_layer_resolve.dart' show attachedMirrorCelId;
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';

/// The ids a synced row's NEW cels take in one bank the cuts of its link
/// group share: each its mirror of the base cel it stands over
/// ([attachedMirrorCelId]) — and a cel of its own where another cut's
/// picture over that base cel took the mirror first.
///
/// 🗣️conte-pair-merge-mints-one-cel-id-for-two-pictures-Q1 own-cel (유저
/// 2026-11-11): 「컷마다 제 셀로 — 두 컷 다 계속 따라간다」. Two 겸용 cuts
/// showing other pictures over one panel of the conte both took that
/// panel's mirror, and the bank held two cels of one id — one picture lost
/// under the other. The second is now a cel of its own, linked from that
/// panel in its own cut alone, and both cuts still follow the conte.
///
/// ⛔ONE LAW FOR THE MERGE AND THE FX BAKE — each minted a synced row's
/// cels by the mirror alone, the same algorithm written twice.
///
/// 🚨A NEW CEL TAKES NO ID ITS BANK HOLDS ([held]) — card
/// a-synced-row-added-in-one-pair-cut-shows-another-rows-picture
/// (검증/서피스 2026-11-16 07:39). A synced row the app makes holds its
/// mirrors already, and a merge's result is kept under the topmost row's
/// id: its mirror of a panel was that row's own cel. The merged picture was
/// laid over it, and an undo gives back rows, not pictures — 🧪measured: a
/// merge of the conte's rows undone, the kept row showed both rows'
/// pictures, and in a 겸용 pair the other cut's row too.
final class SyncedCelIds {
  SyncedCelIds(
    this.mintedUnder,
    this._mintOwn, {
    required Iterable<FrameId> held,
  }) : _taken = {...held};

  /// The row the bank's cels are minted under ([attachedMirrorCelId]).
  final LayerId mintedUnder;

  final FrameId Function() _mintOwn;

  /// The ids no new cel of this bank may take: those it held before, and
  /// those its new cels took.
  final Set<FrameId> _taken;

  /// The id of a new cel of this bank, standing over [baseCel] — asked
  /// once for each picture the bank takes.
  FrameId over(FrameId baseCel) {
    final mirror = attachedMirrorCelId(mintedUnder, baseCel);
    return _taken.add(mirror) ? mirror : _mintOwn();
  }
}
