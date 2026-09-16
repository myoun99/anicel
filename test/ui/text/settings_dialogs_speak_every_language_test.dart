import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨F-37 — the settings dialogs do not hardcode English.
///
/// 유저 2026-08-28: 「로컬라이즈 잔여 — **특히 환경설정 저장 쪽**」. The save
/// section had four: `Every`, `Default` twice, and `Empty now` — and
/// `autosaveDefault` was already sitting in the table, **translated into
/// all five languages and read by nobody**. A key nothing uses is the same
/// bug as a key that does not exist, and harder to see. (🪦It became that
/// again on 2026-09-08 when the recordings-folder row went, and was
/// deleted in five languages with the row.)
///
/// 🚨THE INSTRUMENT WAS THE HOLE (2026-08-31). This scanned `Text('…')` and
/// nothing else, so it went green while the autosave section's six section
/// headings shouted `label: 'Autosave'` at a Japanese user — and
/// `autosaveTitle` sat in the table, translated five ways, read by nobody,
/// **the exact bug the paragraph above was written about, surviving the
/// test written to stop it.** 유저 caught it by eye: 「Autosave가 아니라
/// 그부분도 자동저장이라고 번역」.
///
/// So the scan follows the STRING TO THE SCREEN, not one widget's name: a
/// `Text(…)` and every argument that a widget renders — `label`, `help`,
/// `title`, `tooltip`, `hintText`, `message`, `labelText`, `semanticLabel`,
/// `fieldLabel`, `confirmLabel`, `actionLabel`, `placeholder`, `emptyError`.
/// ⚠️It reads the file WHOLE rather than line by line, because `help:` and
/// its string sit on different lines and a per-line scan cannot see across
/// the break — which is how six of them hid.
///
/// ⛔SCOPED TO THE DIALOGS, and the number says why. A scan of the whole of
/// `lib/src/ui` on 2026-08-31 found **205** hardcoded strings — 39 in the
/// shortcut registry, 21 in the import dialog, 19 in the top strip. Those
/// are real and they are the rest of F-37; turning them all red today would
/// make this a wall rather than a ratchet, and the user's emphasis was the
/// settings.
void main() {
  /// Literals that are the SAME in every language, so a key would buy
  /// nothing but indirection.
  ///
  /// ⛔Each is a symbol or a unit, not a word. If a translator would ever
  /// change it, it does not belong here.
  const universal = <String>{
    'ms', // the unit, written 'ms' in every language this app ships
    // 유저 2026-08-31: 「즉 **업계 용어부분쪽 관련 말고는** 다 번역」. Each
    // of these is an abbreviation an animator reads the same in any
    // language, and a translator asked to render them would be guessing.
    'AA', // anti-aliasing, on the resample toggle
    'RGB',
    'SE',
    'Wintab',
    // 현장 용어, and the code already said so where it lives: the Fx button
    // carries 「Untranslated on purpose — 현장 용어 stays in the original」.
    'fx',
    'Fx',
    'N', // the comma count button, a number in every language
    'X',
    'Y', // the transform axes
    'V', // the storyboard's V column, a sheet letter
  };

  /// Every shape in which a literal reaches the screen from these files.
  ///
  /// ⚠️`[^'$]` keeps interpolations out: `'${size.width}×${size.height}'`
  /// is arithmetic wearing quotes, not a sentence anyone translates.
  final onScreen = <RegExp>[
    RegExp(r"""Text\(\s*(?:const\s+)?'([^'$]*)'"""),
    RegExp(
      '''(?:label|help|title|tooltip|hintText|message|labelText'''
      '''|semanticLabel|fieldLabel|confirmLabel|actionLabel'''
      // ⚠️THE LIST GREW ONCE ALREADY, and the miss was silent. The brush
      // preset panel names its dialogs through `fieldLabel:` and
      // `confirmLabel:`, so eight strings sat outside a scan that had read
      // the file — 218 where the truth was 226. ★When a widget invents a
      // new way to be handed a word, this list is what has to learn it.
      r"""|placeholder|emptyError):\s*(?:const\s+)?'([^'$]*)'""",
    ),
  ];

  test('a settings dialog reads its words from AppStrings', () {
    final hasLetter = RegExp('[A-Za-z]');
    final offenders = <String>[];
    for (final file in Directory(
      'lib/src/ui/dialogs',
    ).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      final source = file.readAsStringSync();
      for (final pattern in onScreen) {
        for (final match in pattern.allMatches(source)) {
          final text = match.group(1)!;
          // A '×' or a bare number is not English — it is punctuation, and
          // it reads the same to everyone.
          if (!hasLetter.hasMatch(text) || universal.contains(text)) {
            continue;
          }
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('$relative:$line  "$text"');
        }
      }
    }
    // ⚠️A scan that finds nothing because its regex broke would pass this
    // test silently. The corpus is known to contain translated calls, so
    // prove the reader reached the files at all.
    expect(
      File(
        'lib/src/ui/dialogs/autosave_settings_section.dart',
      ).readAsStringSync(),
      contains('AppText.strings.autosaveTitle'),
      reason: 'the scanned corpus is not what this test thinks it is',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'add a key to AppStrings (all five languages) and read it here — '
          'a dialog that speaks English to a Japanese user is the one place '
          'the fallback table cannot help, because nothing is missing',
    );
  });

  /// 🚨THE REST OF F-37, COUNTED — and the number only goes down.
  ///
  /// The scan above is a WALL: `lib/src/ui/dialogs` is clean and must stay
  /// clean. Everywhere else is still 200-odd strings, and a wall there would
  /// be a wall rather than a ratchet — nobody could add a panel.
  ///
  /// ⛔A count is a weak instrument and it is chosen on purpose, because the
  /// alternative was worse: a hand-kept list of 「files that are clean now」
  /// goes stale the moment a file is split or renamed, and this repo has
  /// already retired one of those (`every_button_claims_its_press_test` says
  /// so in its own words). A number cannot be renamed.
  ///
  /// ⚠️IT ONLY CATCHES THE DIRECTION. Adding one English literal while
  /// translating another leaves the total unmoved and passes. What it does
  /// catch is the thing that actually happens: a new panel arriving with a
  /// dozen literals, months after anyone remembers F-37 exists.
  ///
  /// ⚠️AND IT COUNTS SOME CORRECT LINES AS DEBT. The shortcut registry and
  /// the menu bar are `const`, so their ENGLISH lives at the call site by
  /// contract and the other languages are keyed by id — 42 lines this scan
  /// reads as untranslated are the English row itself. The number is a
  /// CEILING, not a debt figure; the contract those files really owe is in
  /// `every_action_has_a_word_in_every_language_test`, which asks the
  /// question a count cannot: 「is every id answered」.
  ///
  /// 🚨AND THE NUMBER COMES FROM THIS TEST, NEVER FROM A SIBLING SCRIPT.
  /// I set it once from a scratch counter that scanned the same corpus with
  /// the same regexes — and was six too high, because its `ui/debug/`
  /// exclusion had a broken escape. Six English strings could have come back
  /// and this would have stayed green. ★Run it, read the count out of the
  /// failure, put THAT in.
  ///
  /// ★WHEN YOU TRANSLATE SOMETHING, LOWER THIS NUMBER. That is the ratchet.
  ///
  /// 86 (I-15, 2026-09-11): the English row of the held 「이동」 shortcut
  /// (`canvas-pan-hold`), the registry contract above; its other four
  /// languages are keyed by id.
  ///
  /// 94 (I-19, 2026-09-13): the English rows of eleven new registry actions
  /// (cut, copy, both pastes, delete, clear pixels, save, save as, solo, zoom
  /// in and out) — the same contract — less what the buttons and menu items
  /// that now read those names stopped hardcoding.
  ///
  /// 102 (I-19, 2026-09-13, the tools): every rail tool and tile became an
  /// action and the colour edit's other three verbs joined Clear Pixels —
  /// twelve English rows by the same contract, less the four retired with
  /// M, L, V and the old Ctrl+T. The shape tiles add none: their names are
  /// composed from words the tables already hold.
  /// 95 (F-124, 2026-09-16, the export window): the file bar's words, the
  /// render queue's header and job states, the cut grid's All and the format
  /// availability's two reasons went into the tables. ⚠️Most of that window's
  /// English never showed here at all — it lives in interpolations and
  /// ternaries this scan cannot see (「Exported 2 frames.」), which is why
  /// seven is all a 84-string round moves the number.
  /// 92 (F-37, 2026-09-15, the lanes — 유저 F-37-Q1: 「전부 번역 — 레인
  /// 이름도 한국어로」): the Transform, Name Tag and Audio lane headers
  /// stopped hardcoding their names and read the tables like every other
  /// lane. `tlTransformGroup` and `tlNameTagGroup` had been tabled in five
  /// languages and read by nobody, which is why a round that tables the
  /// lane vocabulary moves this number by three.
  ///
  /// 88 (empty-state-law, 2026-09-16 — 유저 empty-state-law-Q1: 「공용 위젯
  /// 하나 + 짧은 한 줄」): the render queue, the presets and the media pool
  /// stopped hardcoding the line they show when they are empty, and the
  /// prompt widget they each wrote one of went with them.
  const untranslatedElsewhere = 88;

  test('🚨F-37: the rest of lib/src/ui only ever gets more translated', () {
    final hasLetter = RegExp('[A-Za-z]');
    var found = 0;
    final worst = <String, int>{};
    for (final file in Directory('lib/src/ui').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      // ⛔The dialogs are the wall above, not part of the count — a number
      // that included them could be paid down by translating elsewhere while
      // a dialog quietly went back to English.
      //
      // ⛔AND THE BRUSH SMOKE SCREEN IS NOT UI. `brush_v1_scope_guard_test`
      // proves it is wired into no production route; its six buttons are a
      // developer's harness. `ui/debug/` is there for the same reason — the
      // Input Inspector is one of the `edit-*` menu toggles nobody tabled,
      // and translating a diagnostic would make it
      // read differently depending on who opened it.
      //
      // ↩️The TOGGLES are tabled now (유저 2026-09-15,
      // diagnostic-menu-language-Q1: 「메뉴 항목만 번역」): the seven `edit-*`
      // entries speak the program language like every menu entry, and what
      // they open — the overlays under `ui/debug/` — stays English, which is
      // what this exclusion still keeps.
      if (path.contains('/ui/dialogs/') ||
          path.endsWith('/brush_canvas_smoke_screen.dart') ||
          path.contains('/ui/debug/')) {
        continue;
      }
      final source = file.readAsStringSync();
      final relative = path.substring(path.indexOf('lib/'));
      for (final pattern in onScreen) {
        for (final match in pattern.allMatches(source)) {
          final text = match.group(1)!;
          if (!hasLetter.hasMatch(text) || universal.contains(text)) {
            continue;
          }
          found += 1;
          worst[relative] = (worst[relative] ?? 0) + 1;
        }
      }
    }
    // ⛔A scan that broke and found nothing would look like a triumph.
    expect(found, greaterThan(0), reason: 'the scan reached no files');
    final top =
        (worst.keys.toList()..sort((a, b) => worst[b]!.compareTo(worst[a]!)))
            .take(5)
            .map((k) => '$k ${worst[k]}')
            .join(' · ');
    expect(
      found,
      lessThanOrEqualTo(untranslatedElsewhere),
      reason:
          'F-37: $found hardcoded strings outside the dialogs, was '
          '$untranslatedElsewhere. Worst: $top',
    );
    expect(
      found,
      greaterThanOrEqualTo(untranslatedElsewhere - 12),
      reason:
          'the count fell to $found — lower `untranslatedElsewhere` to $found '
          'so the ground you just took cannot be given back',
    );
  });
}
