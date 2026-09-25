import '../../models/project.dart';
import '../command.dart';
import '../project_repository.dart';

/// Writes ONE value through every member of a link group in a single
/// command, and one undo step puts each member's own previous value back.
///
/// 🚨ONE walk for every shared field: a layer's through its link mirrors
/// ([LinkMirroredLayerFieldCommand] — its name, mark and kind) and a cut's
/// through its 겸용 siblings ([LinkedCutFieldCommand] — its drawing guides
/// and its colour label). Each family was its own copy of this execute/undo
/// walk until the audit's clone scan caught them — the layer's three on
/// 2026-09-03, the cut's two on 2026-09-26. [A] addresses one member; a
/// family names its members, reads a member's field and writes it.
abstract class MirroredFieldCommand<A, T> implements Command {
  MirroredFieldCommand({required this.repository, required this.value});

  final ProjectRepository repository;
  final T value;

  /// Every member the value lands on, each once.
  List<A> membersOf(Project project);

  /// [member]'s value of the field in [project].
  T valueOf(Project project, A member);

  /// Writes [value] into [member]'s field.
  void writeTo(A member, T value);

  List<({A member, T previous})>? _targets;

  @override
  void execute() {
    final project = repository.requireProject();
    _targets ??= [
      for (final member in membersOf(project))
        (member: member, previous: valueOf(project, member)),
    ];
    for (final target in _targets!) {
      writeTo(target.member, value);
    }
  }

  @override
  void undo() {
    final targets = _targets;
    if (targets == null) {
      throw StateError('Command has not been executed.');
    }
    for (final target in targets) {
      writeTo(target.member, target.previous);
    }
  }
}
