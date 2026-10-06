import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_font_file.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool's faces): THE FONT FILES REGISTERED WITH A
/// PROJECT — 유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데. 글꼴을
/// 사실상 등록하는거잖아」. The project's own list of what it carries.
void main() {
  const regular = ProjectFontFile(
    carriedAs: 'ab12-cd34-font-1.ttf',
    facts: FontFaceFacts(
      family: 'Probe Sans',
      weight: 400,
      italic: false,
      fsType: 8,
    ),
  );
  const bold = ProjectFontFile(
    carriedAs: 'ef56-ab78-font-2.otf',
    facts: FontFaceFacts(
      family: 'Probe Sans',
      weight: 700,
      italic: true,
      fsType: 0,
    ),
  );

  Project project({List<ProjectFontFile> fonts = const []}) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 6),
    tracks: const [],
    fonts: fonts,
  );

  test('a project carries none until one is registered', () {
    expect(project().fonts, isEmpty);
  });

  test('🚨the fonts come back from the project\'s json as they went: the '
      'name each is carried under, and what each said of itself — in the '
      'order they were registered', () {
    final written = project(fonts: const [bold, regular]);

    final read = Project.fromJson(written.toJson());

    expect(read.fonts, [bold, regular]);
    expect(read, written);
    expect(read.hashCode, written.hashCode);
  });

  test('🚨a project that carries none writes no word of fonts: it keeps the '
      'json it had before fonts could be carried — and reads back from it', () {
    final json = project().toJson();

    expect(json.containsKey('fonts'), isFalse);
    expect(Project.fromJson(json).fonts, isEmpty);
  });

  test('two projects that differ in their fonts alone are not the same '
      'project — an edit of the list is an edit', () {
    expect(project(fonts: const [regular]), isNot(project()));
    expect(
      project(fonts: const [regular]),
      isNot(project(fonts: const [bold])),
    );
    expect(
      project(fonts: const [regular, bold]),
      isNot(project(fonts: const [bold, regular])),
      reason: 'the order they were registered in is theirs',
    );
    expect(project(fonts: const [regular]), project(fonts: const [regular]));
  });

  test('copyWith keeps the fonts unless it is told others', () {
    final carrying = project(fonts: const [regular]);

    expect(carrying.copyWith(name: 'Q').fonts, [regular]);
    expect(carrying.copyWith(fonts: const []).fonts, isEmpty);
    expect(carrying.copyWith(fonts: const [bold]).fonts, [bold]);
  });

  test('the list handed to a project is the project\'s own: it cannot be '
      'changed under it', () {
    final handed = [regular];
    final carrying = project(fonts: handed);

    handed.add(bold);

    expect(carrying.fonts, [regular]);
    expect(() => carrying.fonts.add(bold), throwsUnsupportedError);
  });

  group('one font file of a project', () {
    test('is its name and its facts: another name, or other facts, is '
        'another', () {
      expect(
        regular,
        const ProjectFontFile(
          carriedAs: 'ab12-cd34-font-1.ttf',
          facts: FontFaceFacts(
            family: 'Probe Sans',
            weight: 400,
            italic: false,
            fsType: 8,
          ),
        ),
      );
      expect(
        regular,
        isNot(ProjectFontFile(carriedAs: 'other.ttf', facts: regular.facts)),
      );
      expect(
        regular,
        isNot(ProjectFontFile(carriedAs: regular.carriedAs, facts: bold.facts)),
      );
      expect(
        regular.hashCode,
        ProjectFontFile(carriedAs: regular.carriedAs, facts: regular.facts)
            .hashCode,
      );
    });

    test('comes back from its own json — a font that said nothing of '
        'embedding too', () {
      const silent = ProjectFontFile(
        carriedAs: 'x-y-font-9.ttc',
        facts: FontFaceFacts(
          family: '고딕',
          weight: 500,
          italic: false,
          fsType: null,
        ),
      );

      for (final font in [regular, bold, silent]) {
        expect(ProjectFontFile.fromJson(font.toJson()), font);
      }
    });
  });
}
