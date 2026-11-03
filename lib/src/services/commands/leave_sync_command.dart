import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/cut_sync_alignment.dart' show sheetInkKeyOfCut;
import '../brush_frame_store.dart';
import 'link_registry_snapshot_command.dart';

/// 동기 해제, the sync's half (I-150-Q6, 유저 2026-11-04 「동기 해제 = 독립
/// 컷」): [cutId] leaves its 동기컷 — a sync left with one cut is none. The
/// rows' links are the step's other half (`LinkCommands.unsyncCut`).
///
/// The sheets' handwriting — the conte's blocks, the timesheet's pages — is
/// the sync's ONE paper, kept under its canonical cut (`syncedSheetInkKey`).
/// The part of the sync without it starts from its own copy, whichever part
/// that is: the cut leaving, or the cuts staying when the cut leaving held
/// it — a copy goes on apart, as a duplicated cut's does (유저 2026-09-26,
/// cut-duplicate-sheet-ink-Q1: 「복제는 전부 복사」).
class LeaveSyncCommand extends LinkRegistrySnapshotCommand {
  LeaveSyncCommand({
    required super.repository,
    required this.sheetInkStores,
    required this.cutId,
  });

  /// The sheets' ink stores — every one the session keeps; a store holding
  /// no sheet of the sync is left as it was.
  final List<BrushFrameStore> sheetInkStores;
  final CutId cutId;

  /// The copies made at execute — undo empties exactly these. Keys and
  /// sizes, never the surfaces (`UnlinkLayerCommand._forkedCels`'s reason).
  final List<(BrushFrameStore, BrushFrameKey, CanvasSize)> _copied = [];

  @override
  String get description => 'Leave the sync of $cutId';

  @override
  void execute() {
    final project = repository.requireProject();
    final registry = project.linkRegistry;
    final sync = registry.syncOf(cutId);
    if (sync == null) {
      markExecuted();
      return;
    }
    final staying = [
      for (final cut in sync.cuts)
        if (cut != cutId) cut,
    ];
    final paper = sync.canonical;
    final copier = paper == cutId ? staying.first : cutId;

    // Read under the paper's own keys while it is still the paper.
    final copies = <(BrushFrameStore, BrushFrameKey, BitmapSurface)>[];
    for (final store in sheetInkStores) {
      for (final key in store.celKeysOfCut(paper)) {
        final surface = store.bakedSurfaceOrNull(key);
        if (sheetInkKeyOfCut(key, copier) case final copy?
            when surface != null) {
          copies.add((store, copy, surface));
        }
      }
    }

    snapshotRegistry(project);
    repository.updateProject(
      (current) => current.copyWith(
        linkRegistry: current.linkRegistry.copyWith(
          syncs: [
            for (final each in current.linkRegistry.syncs)
              if (each.id != sync.id)
                each
              else if (staying.length >= 2)
                each.copyWith(cuts: staying),
          ],
        ),
      ),
    );

    // The copier's keys resolve to itself now — the first of its part, or
    // a cut of its own.
    _copied.clear();
    for (final (store, key, surface) in copies) {
      store.storeBakedSurface(key, surface);
      _copied.add((store, key, surface.canvasSize));
    }
    markExecuted();
  }

  /// The copies emptied FIRST, while their keys still resolve to
  /// themselves — then the table puts the sync back, and the copier reads
  /// the paper again.
  @override
  void undoBeforeRegistry() {
    for (final (store, key, canvasSize) in _copied) {
      store.storeBakedSurface(key, BitmapSurface(canvasSize: canvasSize));
    }
  }
}
