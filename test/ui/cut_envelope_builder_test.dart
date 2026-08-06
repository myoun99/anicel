import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_builder.dart';

/// The envelope reads one CUT — and a 겸용 cut brings its siblings onto the
/// same sheet, because the folder they share in the studio is one envelope.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  test('a lone cut prints one CUT line, its name verbatim', () {
    final source = buildCutEnvelopeSource(
      project: session.repository.requireProject(),
      cut: session.requireActiveCut,
    );

    expect(source.cuts, hasLength(1));
    expect(source.cuts.single.name, session.requireActiveCut.name);
  });

  test('a 겸용 cut brings its siblings onto the same envelope', () {
    session.createLinkedCutFromActiveCut();

    final source = buildCutEnvelopeSource(
      project: session.repository.requireProject(),
      cut: session.requireActiveCut,
    );

    expect(source.cuts, hasLength(2));
    expect(
      source.cuts.map((line) => line.name),
      session.activeTrack.cuts.map((cut) => cut.name),
      reason:
          'track order, not "active first" — the document is about a '
          'set of cuts, so reading it must not depend on which is open',
    );
  });

  test('title falls back to the project name; the memo comes from the cut', () {
    session.updateActiveCutNote('PAN (A)→(B)');

    final source = buildCutEnvelopeSource(
      project: session.repository.requireProject(),
      cut: session.requireActiveCut,
    );

    expect(source.title, session.repository.requireProject().name);
    expect(source.note, 'PAN (A)→(B)');
  });

  test('canvas and camera sizes come through for the 解像度 block', () {
    final source = buildCutEnvelopeSource(
      project: session.repository.requireProject(),
      cut: session.requireActiveCut,
    );

    expect(source.canvasWidth, session.requireActiveCut.canvasSize.width);
    expect(
      source.cameraWidth,
      session.repository.requireProject().cameraSize.width,
    );
  });

  group('ink owner', () {
    test('a lone cut owns its own envelope ink', () {
      final cutId = session.requireActiveCut.id;

      expect(
        cutEnvelopeInkOwner(session.repository.requireProject(), cutId),
        cutId,
      );
    });

    test('겸용 siblings share ONE set of annotations', () {
      final first = session.requireActiveCut.id;
      session.createLinkedCutFromActiveCut();
      final second = session.requireActiveCut.id;
      final project = session.repository.requireProject();

      final owner = cutEnvelopeInkOwner(project, first);

      expect(
        cutEnvelopeInkOwner(project, second),
        owner,
        reason: 'one sheet, one handwriting — asking from either sibling '
            'must reach the same ink',
      );
      expect(
        owner,
        session.activeTrack.cuts.first.id,
        reason: 'the representative is the first in track order, the same '
            'order the CUT lines print in',
      );
    });
  });

  group('paper size', () {
    test('cut mode takes the canvas verbatim so the export is drop-in', () {
      final cut = session.requireActiveCut;

      final paper = cutEnvelopePaperSize(
        mode: CutEnvelopePaperMode.cut,
        cut: cut,
        formAspectRatio: CutEnvelopePresets.analog.aspectRatio,
      );

      expect(paper.width, cut.canvasSize.width);
      expect(paper.height, cut.canvasSize.height);
    });

    test('sheet mode takes the form\'s own shape', () {
      final form = CutEnvelopePresets.analog;

      final paper = cutEnvelopePaperSize(
        mode: CutEnvelopePaperMode.sheet,
        cut: session.requireActiveCut,
        formAspectRatio: form.aspectRatio,
        sheetWidth: 1320,
      );

      expect(paper.width, 1320);
      expect(paper.height, (1320 / form.aspectRatio).round());
    });

    test('the mode round-trips through JSON', () {
      for (final mode in CutEnvelopePaperMode.values) {
        expect(CutEnvelopePaperMode.fromJson(mode.toJson()), mode);
      }
      expect(
        CutEnvelopePaperMode.fromJson('nonsense'),
        CutEnvelopePaperMode.sheet,
      );
    });
  });
}
