import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart'
    show readProjectFile;
import 'package:anicel/src/ui/session/tvpp_import_door.dart'
    show readTvppProject;

EditorSessionManager _plainSession(Project project) =>
    EditorSessionManager(initialProject: project);

/// The session the .anicel at [path] opens as — read first, then born with
/// the file's project and settled: the one way a file becomes an open
/// project (I-7). The caller disposes it.
///
/// [make] builds the session for the project, for a test that hands it
/// something of its own (a store, the app's clipboard); [before] runs on it
/// between its birth and the settling — what the window installs before
/// the tab shows.
Future<EditorSessionManager> openedSession(
  String path, {
  String? bindTo,
  EditorSessionManager Function(Project project) make = _plainSession,
  void Function(EditorSessionManager session)? before,
}) async {
  final read = await readProjectFile(path, bindTo: bindTo);
  final session = make(read.project);
  before?.call(session);
  session.projectDoor.settle(read);
  return session;
}

/// The session the .tvpp at [path] opens as — read and converted, then
/// born with the project it became and every cel baked into it — with the
/// warnings the conversion raised; null when the file is not a TVPaint
/// project. The caller disposes it.
Future<({EditorSessionManager session, List<ImportWarning> warnings})?>
openedTvpp(
  String path, {
  EditorSessionManager Function(Project project) make = _plainSession,
}) async {
  final read = await readTvppProject(tvppPath: path);
  if (read == null) {
    return null;
  }
  final session = make(read.project);
  return (session: session, warnings: await session.tvppDoor.bake(read));
}
