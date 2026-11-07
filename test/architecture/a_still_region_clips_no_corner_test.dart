import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WHAT A STILL REGION HOLDS IS NOT CLIPPED TO A CORNER
/// (`lib/src/ui/widgets/superellipse_clip.dart`, 「Not inside a still
/// region」) — what lies inside the shape is left alone, and what reaches
/// its corners fills the shape itself, cut by a rectangle
/// (`SuperellipseCut.drawRSuperellipseCut`).
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2): 「그림 안의
/// 자르기를 『자르지 않고 그 모양으로 칠하는』 그리기로 다시 짠다」. A clip
/// written tomorrow inside a dock clips perfectly in a test, so what gives
/// one away is what it is written as: a `SuperellipseClip`, a clip with an
/// anti-aliased edge handed to a box or a material, or a canvas clipped to a
/// superellipse. A rectangle's clip is exact on the device (`clip-blocks` 0)
/// and is not scanned; nor is a canvas clipped to a path — the artwork's,
/// the sheets' and the camera's outlines, which are no corner — so a hover
/// clipped to its shape's path is held by its own test
/// (`the_blend_chip_wears_a_rail_plate_test`).
void main() {
  test('no corner clip under lib/ outside the ledger — and every ledger '
      'entry still is one', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._cornerClips(libPath(file), file.readAsStringSync()),
      ],
      _clippedOnPurpose.keys,
      unledgered:
          'what a still region holds is not clipped to a corner: leave what '
          'lies inside alone, and fill the shape where something reaches '
          'it (`drawRSuperellipseCut`). One that must clip goes in the '
          'ledger, with why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_clippedOnPurpose);
  });

  test('the scan sees each way of writing a corner clip, and not a '
      'rectangle\'s, a path\'s, a hit test, a declaration or one in a '
      'comment', () {
    const planted = '''
final a = SuperellipseClip(shape: s, child: c);
final b = Material(shape: s, clipBehavior: Clip.antiAlias, child: c);
final c = Container(decoration: d, clipBehavior: Clip.antiAliasWithSaveLayer);
void d(Canvas canvas) => canvas..clipPath(p)..clipRSuperellipse(r);
final e = SuperellipseHit(shape: s, child: c);
final f = Stack(clipBehavior: Clip.hardEdge, children: []);
void g(Canvas canvas) => canvas.clipRect(r, doAntiAlias: false);
// final h = SuperellipseClip(shape: s, child: c);
class SuperellipseClip { const SuperellipseClip({super.key}); }
''';
    expect(_cornerClips('planted.dart', planted), [
      'planted.dart #1',
      'planted.dart #2',
      'planted.dart #3',
      'planted.dart #4',
    ]);
  });
}

/// Corner clips that clip on purpose, by `path #k` — the k-th in its file.
const _clippedOnPurpose = <String, String>{
  'lib/src/ui/canvas/canvas_capsule.dart #1':
      'the transport\'s capsule: its playhead\'s tip reaches into the corner '
      'at the first and the last frame (CanvasCapsule.clipped)',
  'lib/src/ui/workspace/workspace_rail.dart #1':
      'a rail group\'s floating body over whatever it holds — live, its '
      'dock\'s region standing inside the clip',
  'lib/src/ui/workspace/workspace_docks.dart #1':
      'the floating bottom region over whatever it holds — live, its '
      'dock\'s region standing inside the clip',
  'lib/src/ui/widgets/anchored_popup.dart #1':
      'a popup — drawn live, never from an image',
  'lib/src/ui/widgets/app_window.dart #1':
      'a window — drawn live, never from an image',
  'lib/src/ui/export/export_cels_board.dart #1':
      'the export window\'s board — drawn live, never from an image',
  'lib/src/ui/export/export_cels_board.dart #2':
      'a block of the export window\'s board — drawn live, never from an '
      'image',
  'lib/src/ui/export/export_dialog.dart #1':
      'the export window\'s preview well — drawn live, never from an image',
  'lib/src/ui/export/export_settings_modules.dart #1':
      'a module of the export window — drawn live, never from an image',
  'lib/src/ui/editor_workspace.dart #1':
      'a faced strip button: the InkWell\'s hover ink is a rectangle the '
      'material\'s clip rounds — whether hover becomes a fill is '
      'a-live-dock-frame-costs-a-whole-draw-Q12',
  'lib/src/ui/panels/tool_size_preset_panel.dart #1':
      'a size cell: the InkWell\'s hover ink is a rectangle the material\'s '
      'clip rounds — a-live-dock-frame-costs-a-whole-draw-Q12',
  'lib/src/ui/widgets/pill_strip.dart #1':
      'the strip\'s ground and its hover ink — '
      'a-live-dock-frame-costs-a-whole-draw-Q12',
  'lib/src/ui/widgets/group_tab.dart #1':
      'the tab\'s hover ink on its own material — '
      'a-live-dock-frame-costs-a-whole-draw-Q12',
  'lib/src/ui/widgets/color_swatch_button.dart #1':
      'a CIRCLE (`CircleBorder`), not a superellipse — its hover ink on the '
      'material\'s clip, and a circle\'s clip was not probed',
};

final _cornerClip = RegExp(
  r'(?<![\w.])SuperellipseClip\((?!\{)|'
  r'clipBehavior:\s*Clip\.antiAlias|'
  r'\.clipRSuperellipse\(',
);

/// Each corner clip written in [source], by `path #k`, the k-th in the
/// file.
List<String> _cornerClips(String path, String source) {
  final found = _cornerClip.allMatches(withoutComments(source)).length;
  return [for (var k = 1; k <= found; k += 1) '$path #$k'];
}
