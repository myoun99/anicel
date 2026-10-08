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

/// [cut] carrying [sibling]'s value of every field a 겸용 pair shares — each
/// field a [LinkedCutFieldCommand] writes onto the pair as one: the drawing
/// guides (`SetCutGuidesCommand`), the colour label (`UpdateCutMarkCommand`),
/// the sheet it prints on (`UpdateCutSheetKindCommand`) and its staff
/// (`UpdateCutStaffNameCommand`). A cut made 겸용 of another starts with
/// them, so the pair is one answer from its first frame.
///
/// ↩️A new 겸용 cut started with none of them — no guides, no label, the
/// 6-second sheet, nobody's name — while the first edit of any of them
/// wrote both cuts (found 2026-10-08 with F-291's per-cut staff).
Cut withLinkedCutFieldsOf(Cut cut, Cut sibling) => cut.copyWith(
  guides: sibling.guides,
  metadata: cut.metadata.copyWith(
    mark: sibling.metadata.mark,
    sheetKind: sibling.metadata.sheetKind,
    staff: sibling.metadata.staff,
  ),
);
