import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Writes a cut's rows whole — the rows ONE edit leaves of the cut, written
/// and taken back as one write ([ProjectRepository.setCutLayers]).
///
/// 🚨For rows that change TOGETHER. A merge (I-78-Q8) changes a base's cels
/// and the cell links of the synced attach rows riding it at once; written
/// one row at a time, the always-mirror invariant
/// ([cutWithReconciledAttachedMirrors]) gives the rider an empty cel for
/// every cel of the base it meets in between, and the undo leaves them
/// behind — it only ever adds.
///
/// Every row of the cut is in [layers], so it is for an edit of rows no
/// other cut shares: a 겸용 row's existence and a conte row's place are
/// the other cuts' too, and their own commands fan them out.
class SetCutLayersCommand implements Command {
  SetCutLayersCommand({
    required this.repository,
    required this.cutId,
    required this.layers,
    required this.description,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final List<Layer> layers;

  @override
  final String description;

  List<Layer>? _before;

  @override
  void execute() {
    _before ??= requireCut(repository.requireProject(), cutId).layers;
    repository.setCutLayers(cutId: cutId, layers: layers);
  }

  @override
  void undo() {
    final before = _before;
    if (before == null) {
      throw StateError('Command has not been executed.');
    }
    repository.setCutLayers(cutId: cutId, layers: before);
  }
}
