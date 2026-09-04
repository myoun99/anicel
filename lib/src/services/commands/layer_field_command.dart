import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// One layer field: what to call it, how to read it off a layer, and how
/// to write it. The write closure carries its own cut addressing, because
/// some of these fields are cut-addressed and some reach track-owned rows
/// with no cut at all.
typedef LayerField<T> = ({
  /// What the field is called when the command names ITSELF.
  String name,

  /// The command's own description, when the caller gave it one — a
  /// lane drag says what it edited, not which field it wrote.
  String? label,
  T Function(Layer layer) read,
  void Function(T value) write,
});

/// Writes ONE layer field and puts it back on undo — the plain twin of
/// [LinkMirroredLayerFieldCommand], for the fields that are NOT shared
/// across a link's members.
///
/// ⛔SIX COMMANDS WROTE THIS WALK OUT (the audit's clone scan,
/// 2026-09-04): the timesheet flag, the fill-reference flag, the
/// transform track, the effects, the audio clips and the instructions.
///
/// The pair that has to agree is execute's `??=` and undo's throw. The
/// `??=` is what makes a RE-executed command keep its FIRST previous
/// value rather than the one it just wrote, so undo walks all the way
/// back rather than restoring what the command itself put there.
///
/// ⚠️This doc used to say the failure was "redo-then-undo". It is not:
/// undo puts the old value back, so the redo's read sees the same thing
/// and `=` agrees with `??=` (measured 2026-09-05 — the mutant survives
/// that sequence). What distinguishes them is executing again while the
/// NEW value is standing, which is the sequence the test drives.
///
/// ⚠️The anywhere lookup is deliberate: layer ids are globally unique and
/// track-owned SE rows are not in any cut's layer list, but they carry
/// these fields like every other row (unified layer controls).
class LayerFieldCommand<T> implements Command {
  LayerFieldCommand({
    required this.repository,
    required this.layerId,
    required this.value,
    required LayerField<T> field,
  }) : _field = field;

  final ProjectRepository repository;
  final LayerId layerId;
  final T value;
  final LayerField<T> _field;

  T? _previous;
  bool _hasExecuted = false;

  @override
  String get description =>
      _field.label ?? 'Update layer ${_field.name} $layerId';

  @override
  void execute() {
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    _previous ??= _field.read(layer);
    _field.write(value);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previous = _previous;
    if (!_hasExecuted || previous == null) {
      throw StateError('Command has not been executed.');
    }
    requireLayerAnywhere(repository.requireProject(), layerId);
    _field.write(previous);
  }
}
