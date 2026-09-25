import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';
import 'mirrored_field_command.dart';

/// Writes ONE cut field onto [cutIds] — and onto every 겸용 sibling of each —
/// in a single command, and one undo step puts every cut's own value back
/// ([MirroredFieldCommand], the walk every shared field takes).
///
/// A 겸용 pair shows ONE physical cel in two places, so a property of the
/// picture — its drawing guides, its colour label — is one answer for both.
/// [read] is the field's getter on a cut, [write] its repository setter.
class LinkedCutFieldCommand<T> extends MirroredFieldCommand<CutId, T> {
  LinkedCutFieldCommand({
    required super.repository,
    required this.cutIds,
    required super.value,
    required this.fieldName,
    required T Function(Cut cut) read,
    required CutFieldWrite<T> write,
  }) : _read = read,
       _write = write;

  final List<CutId> cutIds;
  final String fieldName;
  final T Function(Cut cut) _read;
  final CutFieldWrite<T> _write;

  /// Every cut a value picked for [cutIds] lands on: each of them and its
  /// 겸용 siblings, once each.
  static List<CutId> linkedCutsOf(Project project, List<CutId> cutIds) => [
    ...{
      for (final cutId in cutIds) ...[
        cutId,
        ...linkedCutSiblings(project, cutId: cutId),
      ],
    },
  ];

  @override
  String get description => 'Set the $fieldName of ${cutIds.join(', ')}';

  @override
  List<CutId> membersOf(Project project) => linkedCutsOf(project, cutIds);

  @override
  T valueOf(Project project, CutId member) =>
      _read(requireCut(project, member));

  @override
  void writeTo(CutId member, T value) => _write(repository, member, value);
}

/// A repository setter for one cut field.
typedef CutFieldWrite<T> =
    void Function(ProjectRepository repository, CutId cutId, T value);
