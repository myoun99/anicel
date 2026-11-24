import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart';
import 'package:anicel/src/ui/timesheet/cut_sheet_document.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

import '../../helpers/number_pad_keyboard.dart';

/// 🗣️F-386 (유저 2026-10-17): 「se트랙은 글로벌이기에 여러 컷에 걸칠수있음.
/// 그래서 컷마다 같은 대사를 이어가고있는데 어떤 컷에선 ON이지만 다음컷에선
/// OFF일수도있음. 그러니 타입 정하는곳에서 컷을 팝오버로 골라서 컷마다 타입
/// 다르게 선택할수있도록. 그게 타임시트든 화면이든 다 반영됨」.
///
/// One line of A子's runs from cut 1's last two frames into cut 2's first
/// four, and every surface that says its delivery says the one of the cut
/// it shows.
typedef _Across = ({
  EditorSessionManager s,
  Cut first,
  Cut second,
  LayerId row,
});

_Across _aLineAcrossTwoCuts() {
  final s = EditorSessionManager(initialProject: createDefaultProject());
  addTearDown(s.dispose);
  final first = s.requireActiveCut;
  s.cutVerbs.createCut();
  final second = s.requireActiveCut;
  s.selectCut(first.id);
  final row = s.activeTrack.seLayers.first.id;
  s.selectLayer(row);
  s.selectFrameIndex(first.duration - 2);
  s.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 6);
  s.seEntries.updateSelectedSeEntry(
    dialogue: 'やめて',
    fields: (
      seName: 'A子',
      seTypes: SeLineTypes.allOn,
      spacing: SeDialogueSpacing.standard,
    ),
  );
  return (s: s, first: first, second: second, row: row);
}

Frame _lineOf(_Across a) => a.s.activeTrack.seLayers.first.frames.single;

int _trackFrame(_Across a, Cut cut, int frame) => a.s.projectSettings
    .axisForTrack(a.s.activeTrack.id)
    .globalOf(cut.id, frame)!;

void _deliver(_Across a, SeLineTypes types) =>
    a.s.seEntries.updateSeEntryForLayer(
      a.row,
      _lineOf(a).id,
      dialogue: 'やめて',
      fields: (
        seName: 'A子',
        seTypes: types,
        spacing: SeDialogueSpacing.standard,
      ),
    );

String? _onCanvas(_Across a, Cut cut, int frame) =>
    a.s.seEntries.seNameTagsForCutFrame(cut, frame).single.delivery?.text;

SeLineType? _onTimesheet(_Across a, Cut cut, int row) {
  final sheet = cutSheetDocument(
    a.s,
    cut: cut,
    cutStartFrame: _trackFrame(a, cut, 0),
  );
  return sheet.columns
      .firstWhere((column) => column.layerId == a.row)
      .cells[row]
      .seType;
}

SeLineType _onConte(_Across a, Cut cut) =>
    buildConteSheetSource(a.s.repository.requireProject()).cuts
        .firstWhere((source) => source.cutId == cut.id)
        .dialogue
        .single
        .delivery;

Future<BuildContext> _contextFrom(WidgetTester tester) async {
  late BuildContext context;
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return context;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pumpAndSettle();
}

PanelFlyoutButton _picker(WidgetTester tester) =>
    tester.widget<PanelFlyoutButton>(
      find.byKey(const ValueKey<String>('se-type-cut-picker')),
    );

String _pickerLabel(WidgetTester tester) => _picker(tester).label;

/// The key of the one type pill lit — the strip of type pills, not the
/// frame-count fields' own entry pills (F-496 ③).
String _pillOn(WidgetTester tester) => tester
    .widgetList<PillStrip>(find.byType(PillStrip))
    .expand((strip) => strip.items)
    .where((item) => item.keyValue.startsWith('se-type-') && item.selected)
    .single
    .keyValue;

void main() {
  test('⛔premise: the line plays in both cuts — the window\'s list, and the '
      'cut each of its frames stands in', () {
    final a = _aLineAcrossTwoCuts();
    final inFirst = a.s.seEntries.seLineCutsAt(
      a.row,
      _trackFrame(a, a.first, a.first.duration - 1),
    );
    expect([for (final cut in inFirst.cuts) cut.id], [
      a.first.id,
      a.second.id,
    ]);
    expect(inFirst.atFrame, a.first.id);
    expect(
      a.s.seEntries.seLineCutsAt(a.row, _trackFrame(a, a.second, 1)).atFrame,
      a.second.id,
    );
    expect(
      a.s.seEntries.seLineCutsAt(a.row, _trackFrame(a, a.second, 8)).cuts,
      isEmpty,
      reason: 'no line covers that frame',
    );
  });

  test('the canvas: each cut\'s picture says the line\'s delivery in it — '
      'and one undo takes the edit back', () {
    final a = _aLineAcrossTwoCuts();
    _deliver(a, SeLineTypes(byCut: {a.second.id: SeLineType.off}));

    expect(_onCanvas(a, a.first, a.first.duration - 1), 'ON');
    expect(_onCanvas(a, a.second, 1), 'OFF');

    a.s.undo();
    expect(_onCanvas(a, a.second, 1), 'ON');
  });

  test('the timesheet: cut 2\'s sheet carries OFF where the line spills in, '
      'cut 1\'s ON at its head', () {
    final a = _aLineAcrossTwoCuts();
    _deliver(a, SeLineTypes(byCut: {a.second.id: SeLineType.off}));

    expect(_onTimesheet(a, a.first, a.first.duration - 2), SeLineType.on);
    expect(_onTimesheet(a, a.second, 0), SeLineType.off);
  });

  test('the conte sheet: each cut\'s dialogue column', () {
    final a = _aLineAcrossTwoCuts();
    _deliver(a, SeLineTypes(byCut: {a.second.id: SeLineType.mono}));

    expect(_onConte(a, a.first), SeLineType.on);
    expect(_onConte(a, a.second), SeLineType.mono);
  });

  testWidgets('the TIMELINE door opens on the cut it stands in, on the '
      'deliveries the line has, and its pills set that cut alone', (
    tester,
  ) async {
    final a = _aLineAcrossTwoCuts();
    _deliver(a, SeLineTypes(own: SeLineType.off));
    a.s.selectCut(a.second.id);
    a.s.selectLayer(a.row);
    final context = await _contextFrom(tester);

    final editing = activateCellEditor(
      context,
      a.s,
      layerId: a.row,
      frameIndex: 1,
    );
    await tester.pumpAndSettle();
    expect(_pickerLabel(tester), a.second.name);
    expect(_pillOn(tester), 'se-type-off');
    await _tap(tester, 'se-type-mono');
    await _tap(tester, 'instance-edit-ok-button');
    await editing;

    expect(_lineOf(a).seTypes.inCut(a.second.id), SeLineType.mono);
    expect(_lineOf(a).seTypes.inCut(a.first.id), SeLineType.off);
  });

  testWidgets('the CONTE door opens on the cut its frame stands in; the cut '
      'picker turns the pills to another; OK writes the head\'s cut as the '
      'line\'s own', (tester) async {
    final a = _aLineAcrossTwoCuts();
    final context = await _contextFrom(tester);

    final editing = editSeEntryInstance(
      context,
      a.s,
      layerId: a.row,
      globalFrame: _trackFrame(a, a.second, 1),
    );
    await tester.pumpAndSettle();
    expect(_pickerLabel(tester), a.second.name);
    await _tap(tester, 'se-type-mono');
    expect(_pillOn(tester), 'se-type-mono');

    // The list says each cut's delivery as it now stands, the cut the pills
    // set in the accent.
    await _tap(tester, 'se-type-cut-picker');
    expect(find.text('${a.first.name} · ON'), findsOneWidget);
    expect(find.text('${a.second.name} · MONO'), findsOneWidget);
    expect(
      flyoutRowsOf(_picker(tester).entriesBuilder())
          .where((row) => row.selected)
          .map((row) => row.keyValue),
      ['se-type-cut-${a.second.id.value}'],
    );
    await _tap(tester, 'se-type-cut-${a.first.id.value}');
    expect(_pickerLabel(tester), a.first.name);
    expect(_pillOn(tester), 'se-type-on', reason: 'the first cut\'s own');
    await _tap(tester, 'se-type-off');
    await _tap(tester, 'instance-edit-ok-button');
    await editing;

    expect(
      _lineOf(a).seTypes,
      SeLineTypes(own: SeLineType.off, byCut: {a.second.id: SeLineType.mono}),
      reason: 'the cut the head plays in says the line\'s own — what a cut '
          'it reaches later carries on with',
    );
  });

  // 🗣️F-496 ③ (유저 2026-10-28): 「대사 오프셋/글자별 코마 기능」 — the
  // line's own, counted over its whole block, through either door.
  for (final timeline in [true, false]) {
    testWidgets('the ${timeline ? 'TIMELINE' : 'CONTE'} door opens the '
        'window on the line\'s spacing over its whole block, and OK writes '
        'what was typed', (tester) async {
      final a = _aLineAcrossTwoCuts();
      const own = SeDialogueSpacing(offset: 1, komaPerGlyph: 2);
      a.s.seEntries.updateSeEntryForLayer(
        a.row,
        _lineOf(a).id,
        dialogue: 'やめて',
        fields: (seName: 'A子', seTypes: SeLineTypes.allOn, spacing: own),
      );
      a.s.selectCut(a.second.id);
      a.s.selectLayer(a.row);
      final context = await _contextFrom(tester);

      final editing = timeline
          ? activateCellEditor(context, a.s, layerId: a.row, frameIndex: 1)
          : editSeEntryInstance(
              context,
              a.s,
              layerId: a.row,
              globalFrame: _trackFrame(a, a.second, 1),
            );
      await tester.pumpAndSettle();
      final preview = tester.widget<DialogueFitText>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('instance-edit-preview')),
          matching: find.byType(DialogueFitText),
        ),
      );
      expect(preview.spacing, own);
      expect(
        preview.frames,
        6,
        reason: 'both cuts\' frames of it: the offset counts from its head',
      );
      await typeOnThePad(tester, 'se-koma-per-glyph-field', '4');
      await _tap(tester, 'instance-edit-ok-button');
      await editing;

      expect(_lineOf(a).seSpacing, own.copyWith(komaPerGlyph: 4));
    });
  }
}
