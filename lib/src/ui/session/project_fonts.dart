import '../../models/project.dart';
import '../../models/project_font_file.dart';
import '../../services/command.dart';
import '../../services/commands/update_project_fonts_command.dart';
import '../../services/font_library_service.dart' show isFontLibraryFileName;
import '../text/imported_fonts.dart'
    show LetterFaceFile, compareFontFamilyNames;
import 'project_file.dart';
import 'session_roles.dart';

/// THE FONTS REGISTERED WITH THE PROJECT, AS THE SESSION WORKS THEM
/// (R9-rest, the text tool's faces): the files its letters are set with
/// while it is on screen, the registering of a font when a text is set in
/// it, and the taking of one out.
///
/// 🗣️유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데. 글꼴을 사실상
/// 등록하는거잖아. 프리미어프로처럼」 — the list is the project's own
/// (`Project.fonts`), and it changes here and nowhere else: a font joins it
/// with the text first set in it, and leaves when a person takes it out.
///
/// A collaborator of the session, as the media pool is: the list is in the
/// project, its bytes are the record's ([ProjectFile]), and this is the
/// verbs.
class ProjectFonts {
  ProjectFonts({
    required ProjectAccess project,
    required ChangeSink changes,
    required ProjectFile file,
  }) : _project = project,
       _changes = changes,
       _file = file;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ProjectFile _file;

  Project _requireProject() => _project.repository.requireProject();

  /// The font files this project carries, for whoever sets letters while
  /// it is on screen (`ImportedFonts.showCarried`) — each read from
  /// wherever its bytes are when it is asked for ([ProjectFile.fontBytes]).
  ///
  /// ⛔ONLY THE ONES THAT CAN BE READ NOW ([ProjectFile.fontsWithBytes]). A
  /// font the list names whose bytes are nowhere this machine can reach is
  /// not what its family is set with: this device's own file of that face
  /// is, where it has one — and a text set with THAT registers it, in the
  /// dead one's place ([landingWith]).
  List<LetterFaceFile> get letterFaceFiles => [
    for (final font in _file.fontsWithBytes(_requireProject()))
      (
        name: font.carriedAs,
        facts: font.facts,
        read: () => _file.fontBytes(font),
      ),
  ];

  /// This device's library is about to let go of the font files called
  /// [files]: every font this project carries under one of those names,
  /// whose bytes it has nowhere else, takes them into the session's
  /// keeping first ([ProjectFile.holdFontBytes]).
  ///
  /// 🚨★★★THIS IS WHAT STANDS WHERE A CARRIED MEDIUM'S `stageCarriedBytes`
  /// STANDS (유저 2026-08-30: 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」). [landingWith] registers a font without copying
  /// it — its bytes are the library's, under a name that means them for
  /// good, and they are immutable there. What could take them away before
  /// the project is saved is the library letting go of the file, and the
  /// library asks here before it does (`ImportedFonts`).
  Future<void> holdBytesOf(Set<String> files) => _file.holdFontBytes([
    for (final font in _requireProject().fonts)
      if (files.contains(font.carriedAs)) font,
  ]);

  /// The families this project carries a file of, as a list names them.
  List<String> get families => {
    for (final font in _requireProject().fonts) font.facts.family,
  }.toList()..sort(compareFontFamilyNames);

  /// [landing] — a text set on a cel — and WITH IT, AS ONE STEP, the
  /// registering of the files its letters are set with ([setWith]) that
  /// this project does not carry yet. [landing] itself, where there is
  /// none to register.
  ///
  /// 🚨THE FILES THE TEXT WAS JUST SET WITH, and no others: what joins the
  /// project is what the person saw their letters in. One step with the
  /// text, so the Ctrl+Z that takes the text back takes the font out of
  /// the project again — a font tried once and undone is not carried.
  ///
  /// A FAMILY RIDES WHOLE OR NOT AT ALL: one any file of which may not
  /// ride in a document that is edited (`FontFaceFacts`, R9-rest-Q1 ⓐ)
  /// registers none of its files — the list says of such a family that it
  /// stays on this device, and a project carrying half of it would be set
  /// in half of it elsewhere.
  ///
  /// A FACE HAS ONE FILE: one registered here takes the place of the file
  /// the list had for the same face — as bringing a face again does on the
  /// device (`ImportedFonts.importBytes`).
  Command landingWith(Command landing, Iterable<LetterFaceFile> setWith) {
    final project = _requireProject();
    final carried = {for (final font in project.fonts) font.carriedAs};
    final families = <String, List<LetterFaceFile>>{};
    for (final file in setWith) {
      (families[file.facts.family] ??= []).add(file);
    }
    final joining = [
      for (final files in families.values)
        if (files.every((file) => file.facts.ridesInEditedDocuments))
          for (final file in files)
            if (!carried.contains(file.name) &&
                isFontLibraryFileName(file.name))
              ProjectFontFile(carriedAs: file.name, facts: file.facts),
    ];
    if (joining.isEmpty) {
      return landing;
    }
    return oneStepOf(landing.description, [
      landing,
      UpdateProjectFontsCommand(
        repository: _project.repository,
        fonts: [
          for (final font in project.fonts)
            if (!joining.any((joined) => joined.facts.isSameFaceAs(font.facts)))
              font,
          ...joining,
        ],
      ),
    ])!;
  }

  /// Takes [family] out of the project, as one step of history — nothing,
  /// where the project carries no file of it.
  ///
  /// Its texts keep their pixels, and are set in the family again wherever
  /// a device holds it; the file lets go of the bytes at the next save,
  /// and this run's room keeps them for the undo
  /// (`ProjectFileDoor._keepWhatItLeavesBehind`).
  void takeOut(String family) {
    final fonts = _requireProject().fonts;
    final staying = [
      for (final font in fonts)
        if (font.facts.family != family) font,
    ];
    if (staying.length == fonts.length) {
      return;
    }
    _project.historyManager.execute(
      UpdateProjectFontsCommand(
        repository: _project.repository,
        fonts: staying,
        description: 'Take a font out of the project',
      ),
    );
    // Whoever shows this project hears that its fonts are others: the
    // letters of a family taken out are set in another face from this step.
    _changes.notifyChanged();
  }
}
