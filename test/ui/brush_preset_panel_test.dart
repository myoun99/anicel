import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_group.dart';
import 'package:quick_animaker_v2/src/models/brush_group_id.dart';
import 'package:quick_animaker_v2/src/models/brush_preset.dart';
import 'package:quick_animaker_v2/src/models/brush_preset_id.dart';
import 'package:quick_animaker_v2/src/models/brush_pressure_curve.dart';
import 'package:quick_animaker_v2/src/models/brush_settings.dart';
import 'package:quick_animaker_v2/src/models/brush_tip_mask.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_preset_panel.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_stroke_preview.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_tip_preview.dart';

const _ink = BrushGroupId('ink');
const _paint = BrushGroupId('paint');

BrushPreset _calligraphy() {
  return BrushPreset(
    id: const BrushPresetId('preset-calligraphy'),
    name: 'Calligraphy',
    settings: BrushSettings(
      size: 14,
      hardness: 0.9,
      roundness: 0.3,
      angleDegrees: 45,
      sizePressureCurve: BrushPressureCurve.identity(),
    ),
  );
}

BrushPreset _marker() {
  return BrushPreset(
    id: const BrushPresetId('preset-marker'),
    name: 'Marker',
    settings: BrushSettings(size: 16, opacity: 0.7),
  );
}

BrushPreset _sampled() {
  return BrushPreset(
    id: const BrushPresetId('preset-sampled'),
    name: 'Sampled',
    settings: BrushSettings(
      size: 20,
      tipMask: BrushTipMask(
        id: 'test-mask',
        size: 4,
        alpha: Uint8List.fromList(List<int>.filled(16, 200)),
      ),
    ),
  );
}

/// Records every callback the panel fires, and applies the group edits to
/// its own state so folds and reorders show up on screen like they do in the
/// workspace.
class _PanelHost extends StatefulWidget {
  const _PanelHost({
    required this.groups,
    required this.presets,
    this.selectedPresetId,
    this.onPresetApplied,
    this.onPresetSaveRequested,
    this.onPresetDeleted,
    this.onPresetImportRequested,
    this.onPresetRenamed,
    this.onPresetsReordered,
    this.onGroupCreated,
    this.onGroupRenamed,
    this.onGroupDeleted,
    this.onGroupsReordered,
    this.onLibraryReset,
  });

  final List<BrushGroup> groups;
  final List<BrushPreset> presets;
  final BrushPresetId? selectedPresetId;
  final ValueChanged<BrushPreset>? onPresetApplied;
  final VoidCallback? onPresetSaveRequested;
  final ValueChanged<BrushPresetId>? onPresetDeleted;
  final VoidCallback? onPresetImportRequested;
  final void Function(BrushPresetId id, String name)? onPresetRenamed;
  final ValueChanged<List<BrushPreset>>? onPresetsReordered;
  final ValueChanged<String>? onGroupCreated;
  final void Function(BrushGroupId id, String name)? onGroupRenamed;
  final ValueChanged<BrushGroupId>? onGroupDeleted;
  final ValueChanged<List<BrushGroup>>? onGroupsReordered;
  final VoidCallback? onLibraryReset;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  late List<BrushGroup> _groups = widget.groups;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          child: SingleChildScrollView(
            child: BrushPresetPanel(
              groups: _groups,
              presets: widget.presets,
              selectedPresetId: widget.selectedPresetId,
              onPresetApplied: widget.onPresetApplied,
              onPresetSaveRequested: widget.onPresetSaveRequested,
              onPresetDeleted: widget.onPresetDeleted,
              onPresetImportRequested: widget.onPresetImportRequested,
              onPresetRenamed: widget.onPresetRenamed,
              onPresetsReordered: widget.onPresetsReordered,
              onGroupCreated: widget.onGroupCreated,
              onGroupRenamed: widget.onGroupRenamed,
              onGroupDeleted: widget.onGroupDeleted,
              onGroupsReordered: widget.onGroupsReordered == null
                  ? null
                  : (groups) {
                      widget.onGroupsReordered!(groups);
                      setState(() => _groups = groups);
                    },
              onLibraryReset: widget.onLibraryReset,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required List<BrushPreset> presets,
  List<BrushGroup> groups = const <BrushGroup>[],
  BrushPresetId? selectedPresetId,
  ValueChanged<BrushPreset>? onPresetApplied,
  VoidCallback? onPresetSaveRequested,
  ValueChanged<BrushPresetId>? onPresetDeleted,
  VoidCallback? onPresetImportRequested,
  void Function(BrushPresetId id, String name)? onPresetRenamed,
  ValueChanged<List<BrushPreset>>? onPresetsReordered,
  ValueChanged<String>? onGroupCreated,
  void Function(BrushGroupId id, String name)? onGroupRenamed,
  ValueChanged<BrushGroupId>? onGroupDeleted,
  ValueChanged<List<BrushGroup>>? onGroupsReordered,
  VoidCallback? onLibraryReset,
}) async {
  await tester.pumpWidget(
    _PanelHost(
      groups: groups,
      presets: presets,
      selectedPresetId: selectedPresetId,
      onPresetApplied: onPresetApplied,
      onPresetSaveRequested: onPresetSaveRequested,
      onPresetDeleted: onPresetDeleted,
      onPresetImportRequested: onPresetImportRequested,
      onPresetRenamed: onPresetRenamed,
      onPresetsReordered: onPresetsReordered,
      onGroupCreated: onGroupCreated,
      onGroupRenamed: onGroupRenamed,
      onGroupDeleted: onGroupDeleted,
      onGroupsReordered: onGroupsReordered,
      onLibraryReset: onLibraryReset,
    ),
  );
}

Finder _tab(String idValue) =>
    find.byKey(ValueKey<String>('brush-preset-tab-$idValue'));

Finder _row(String idValue) =>
    find.byKey(ValueKey<String>('brush-preset-chip-$idValue'));

void main() {
  testWidgets('renders icon, stroke preview, and name for every preset', (
    tester,
  ) async {
    await _pumpPanel(tester, presets: [_calligraphy(), _marker(), _sampled()]);

    // The hosting tab names the panel; the frame itself renders no title.
    expect(
      find.byKey(const ValueKey<String>('editor-panel-frame-Brushes')),
      findsOneWidget,
    );
    expect(_row('preset-calligraphy'), findsOneWidget);
    expect(_row('preset-marker'), findsOneWidget);
    expect(_row('preset-sampled'), findsOneWidget);
    expect(find.byType(BrushTipPreview), findsNWidgets(3));
    expect(find.byType(BrushStrokePreview), findsNWidgets(3));
    expect(find.text('Marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies, saves, and imports presets', (tester) async {
    final calligraphy = _calligraphy();
    final applied = <BrushPreset>[];
    var saveRequests = 0;
    var importRequests = 0;

    await _pumpPanel(
      tester,
      presets: [calligraphy, _marker()],
      onPresetApplied: applied.add,
      onPresetSaveRequested: () => saveRequests += 1,
      onPresetDeleted: (_) {},
      onPresetImportRequested: () => importRequests += 1,
    );

    // Tapping a row applies its preset.
    await tester.tap(find.text('Calligraphy'));
    await tester.pumpAndSettle();
    expect(applied.single, calligraphy);

    // The header save affordance requests a preset save.
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-save-button')),
    );
    await tester.pumpAndSettle();
    expect(saveRequests, 1);

    // The header import affordance requests a brush-file import.
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-import-button')),
    );
    await tester.pumpAndSettle();
    expect(importRequests, 1);
  });

  testWidgets('options menu deletes the selected preset', (tester) async {
    final deleted = <BrushPresetId>[];

    await _pumpPanel(
      tester,
      presets: [_calligraphy(), _marker()],
      selectedPresetId: const BrushPresetId('preset-marker'),
      onPresetDeleted: deleted.add,
    );

    // No per-row delete affordance (stray clicks cannot delete).
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete selected brush'));
    await tester.pumpAndSettle();

    expect(deleted.single, const BrushPresetId('preset-marker'));
  });

  testWidgets('options menu delete is disabled without a selection', (
    tester,
  ) async {
    final deleted = <BrushPresetId>[];

    await _pumpPanel(
      tester,
      presets: [_marker()],
      onPresetDeleted: deleted.add,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();

    final item = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const ValueKey<String>('brush-preset-menu-delete')),
    );
    expect(item.enabled, isFalse);

    await tester.tap(find.text('Delete selected brush'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
  });

  testWidgets('highlights only the selected preset row', (tester) async {
    await _pumpPanel(
      tester,
      presets: [_calligraphy(), _marker()],
      selectedPresetId: const BrushPresetId('preset-marker'),
    );

    final selectedRow = tester.widget<Material>(
      find
          .ancestor(of: _row('preset-marker'), matching: find.byType(Material))
          .first,
    );
    final unselectedRow = tester.widget<Material>(
      find
          .ancestor(
            of: _row('preset-calligraphy'),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(selectedRow.color, isNot(Colors.transparent));
    expect(unselectedRow.color, Colors.transparent);
  });

  testWidgets('shows a compact empty state without header actions', (
    tester,
  ) async {
    await _pumpPanel(tester, presets: const []);

    expect(
      find.byKey(const ValueKey<String>('editor-panel-frame-Brushes')),
      findsOneWidget,
    );
    expect(find.byType(BrushStrokePreview), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('brush-preset-save-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-preset-import-button')),
      findsNothing,
    );
    expect(find.byIcon(Icons.brush_outlined), findsOneWidget);
  });

  testWidgets('an empty group still shows its header', (tester) async {
    // The library has no presets at all, but a group the user just created
    // must be visible — otherwise there is nowhere to drag brushes into.
    await _pumpPanel(
      tester,
      presets: const [],
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
    );

    expect(_tab('ink'), findsOneWidget);
    expect(find.byIcon(Icons.brush_outlined), findsNothing);
  });

  testWidgets('omits the delete item when deletion is not wired', (
    tester,
  ) async {
    await _pumpPanel(tester, presets: [_marker()]);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-preset-view-stroke-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-preset-menu-delete')),
      findsNothing,
    );
  });

  testWidgets('view toggles hide the icon, stroke preview, and name', (
    tester,
  ) async {
    Future<void> toggle(String keyValue) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-preset-menu-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(keyValue)));
      await tester.pumpAndSettle();
    }

    await _pumpPanel(tester, presets: [_marker()]);
    expect(find.byType(BrushTipPreview), findsOneWidget);
    expect(find.byType(BrushStrokePreview), findsOneWidget);
    expect(find.text('Marker'), findsOneWidget);

    await toggle('brush-preset-view-icon-toggle');
    expect(find.byType(BrushTipPreview), findsNothing);
    expect(find.byType(BrushStrokePreview), findsOneWidget);

    await toggle('brush-preset-view-stroke-toggle');
    expect(find.byType(BrushStrokePreview), findsNothing);
    // The name falls back to a plain row label when the stroke is hidden.
    expect(find.text('Marker'), findsOneWidget);

    await toggle('brush-preset-view-icon-toggle');
    await toggle('brush-preset-view-name-toggle');
    expect(find.text('Marker'), findsNothing);
    expect(find.byType(BrushTipPreview), findsOneWidget);
  });

  testWidgets('the rail lists groups in order with the root tab last', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _paint, name: 'Paint'),
        BrushGroup(id: _ink, name: 'Ink'),
      ],
      presets: [
        // Library ORDER puts the loose preset first; the GROUP list decides
        // the rail, so the leftovers tab still comes last.
        _marker(),
        _calligraphy().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
      ],
    );

    double top(Finder finder) => tester.getTopLeft(finder).dy;

    expect(top(_tab('paint')), lessThan(top(_tab('ink'))));
    expect(top(_tab('ink')), lessThan(top(_tab('root'))));
  });

  testWidgets('one tab at a time — the list shows only its group', (
    tester,
  ) async {
    final applied = <BrushPreset>[];
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
        _marker(),
      ],
      onPresetApplied: applied.add,
    );

    // Opens on the first tab.
    expect(_row('preset-calligraphy'), findsOneWidget);
    expect(_row('preset-sampled'), findsNothing);
    expect(_row('preset-marker'), findsNothing);

    await tester.tap(_tab('paint'));
    await tester.pumpAndSettle();
    expect(_row('preset-sampled'), findsOneWidget);
    expect(_row('preset-calligraphy'), findsNothing);

    await tester.tap(_tab('root'));
    await tester.pumpAndSettle();
    expect(_row('preset-marker'), findsOneWidget);

    // Rows stay tappable wherever the rail has landed.
    await tester.tap(find.text('Marker'));
    await tester.pumpAndSettle();
    expect(applied.single.id, const BrushPresetId('preset-marker'));
  });

  testWidgets('the tab menu keeps to its corner', (tester) async {
    // A bare PopupMenuButton carries an IconButton's 48px minimum tap
    // target. On a 26px rail that covers the whole tab, so every click
    // meant to open a group opens its menu instead.
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: [_calligraphy().copyWith(groupId: _ink)],
      onGroupRenamed: (_, _) {},
    );

    final menu = tester.getSize(
      find.byKey(const ValueKey<String>('brush-preset-tab-ink-menu')),
    );
    final tab = tester.getSize(_tab('ink'));

    expect(menu.width, lessThan(tab.width));
    expect(menu.height, lessThan(tab.height));
  });

  testWidgets('rail tabs drop their tooltips while being dragged', (
    tester,
  ) async {
    // A Tooltip is an OverlayPortal, and reordering re-parents items by
    // global key. If autoscroll revives one mid-layout the portal adds
    // itself to the overlay right then and takes the rail down with
    // "a _RenderLayoutBuilder was mutated in performLayout".
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [_calligraphy().copyWith(groupId: _ink)],
      onGroupsReordered: (_) {},
    );

    expect(find.byType(Tooltip), findsWidgets);

    final drag = await tester.startGesture(tester.getCenter(_tab('ink')));
    await tester.pump(const Duration(milliseconds: 100));
    // The rail uses an immediate drag listener, so it takes movement past
    // the slop rather than a hold.
    await drag.moveBy(const Offset(0, 24));
    await tester.pump();
    await drag.moveBy(const Offset(0, 24));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('brush-preset-tab-rail')),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
      reason: 'nothing in a dragging tab may reach for the overlay',
    );

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the open tab follows the selected brush', (tester) async {
    // Opening the panel should land where you are painting from, not on
    // whatever tab happens to be first.
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
      ],
      selectedPresetId: const BrushPresetId('preset-sampled'),
    );

    expect(_row('preset-sampled'), findsOneWidget);
    expect(_row('preset-calligraphy'), findsNothing);
  });

  testWidgets('no root tab when every brush is filed', (tester) async {
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: [_calligraphy().copyWith(groupId: _ink)],
    );

    expect(_tab('ink'), findsOneWidget);
    expect(_tab('root'), findsNothing);
  });

  testWidgets('the group menu renames the group', (tester) async {
    final renames = <(BrushGroupId, String)>[];
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: [_calligraphy().copyWith(groupId: _ink)],
      onGroupRenamed: (id, name) => renames.add((id, name)),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-tab-ink-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename group'));
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey<String>('brush-preset-group-rename-text-field'),
    );
    expect(tester.widget<TextField>(field).controller!.text, 'Ink');
    await tester.enterText(field, 'Inking');
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-group-rename-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(renames.single, (_ink, 'Inking'));
  });

  testWidgets('deleting a group confirms and names the member count', (
    tester,
  ) async {
    final deleted = <BrushGroupId>[];
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _marker().copyWith(groupId: _ink),
      ],
      onGroupDeleted: deleted.add,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-tab-ink-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();

    // The count is what makes this safe to click: it says what goes away.
    expect(
      find.text('Delete "Ink" and the 2 brushes inside it?'),
      findsOneWidget,
    );
    expect(deleted, isEmpty);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('brush-preset-group-delete-cancel-button'),
      ),
    );
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-tab-ink-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('brush-preset-group-delete-confirm-button'),
      ),
    );
    await tester.pumpAndSettle();

    expect(deleted.single, _ink);
  });

  testWidgets('an empty group deletes without a member count', (tester) async {
    final deleted = <BrushGroupId>[];
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: const [],
      onGroupDeleted: deleted.add,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-tab-ink-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();

    expect(find.text('Delete the empty group "Ink"?'), findsOneWidget);
  });

  testWidgets('the root section carries no group menu', (tester) async {
    // "Default" is not an entity — it cannot be renamed or deleted.
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _marker(),
      ],
      onGroupRenamed: (_, _) {},
      onGroupDeleted: (_) {},
    );

    expect(_tab('root'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('brush-preset-tab-root-menu')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-preset-tab-ink-menu')),
      findsOneWidget,
    );
  });

  testWidgets('the options menu creates a group', (tester) async {
    final created = <String>[];
    await _pumpPanel(tester, presets: [_marker()], onGroupCreated: created.add);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey<String>('brush-preset-group-new-text-field'),
    );
    expect(tester.widget<TextField>(field).controller!.text, 'New Group');
    await tester.enterText(field, 'Sketch');
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-group-new-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(created.single, 'Sketch');
  });

  testWidgets('resetting the library confirms first', (tester) async {
    var resets = 0;
    await _pumpPanel(
      tester,
      presets: [_marker()],
      onLibraryReset: () => resets += 1,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset brush library'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-preset-reset-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-reset-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(resets, 0);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset brush library'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-reset-confirm-button')),
    );
    await tester.pumpAndSettle();
    expect(resets, 1);
  });

  testWidgets('options menu renames the selected preset', (tester) async {
    final renames = <(BrushPresetId, String)>[];
    await _pumpPanel(
      tester,
      presets: [_calligraphy(), _marker()],
      selectedPresetId: const BrushPresetId('preset-marker'),
      onPresetRenamed: (id, name) => renames.add((id, name)),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename selected brush'));
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey<String>('brush-preset-rename-text-field'),
    );
    expect(tester.widget<TextField>(field).controller!.text, 'Marker');

    // An empty name keeps the dialog open with an error.
    await tester.enterText(field, '   ');
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-rename-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('brush-preset-rename-dialog')),
      findsOneWidget,
    );
    expect(renames, isEmpty);

    await tester.enterText(field, 'Wet wash');
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-rename-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(renames.single, (const BrushPresetId('preset-marker'), 'Wet wash'));
    expect(
      find.byKey(const ValueKey<String>('brush-preset-rename-dialog')),
      findsNothing,
    );
  });

  testWidgets('rename is disabled without a selection', (tester) async {
    await _pumpPanel(tester, presets: [_marker()], onPresetRenamed: (_, _) {});

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();

    final item = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const ValueKey<String>('brush-preset-menu-rename')),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('dragging a row reorders the library', (tester) async {
    final reordered = <List<BrushPreset>>[];
    final calligraphy = _calligraphy();
    final marker = _marker();
    final sampled = _sampled();
    await _pumpPanel(
      tester,
      presets: [calligraphy, marker, sampled],
      onPresetsReordered: reordered.add,
    );

    // Drag the first row down past the second (rows are 36px tall).
    await tester.drag(
      find.byKey(
        const ValueKey<String>('brush-preset-entry-preset-calligraphy'),
      ),
      const Offset(0, 44),
    );
    await tester.pumpAndSettle();

    expect(reordered, isNotEmpty);
    expect(reordered.last.map((preset) => preset.id.value), [
      'preset-marker',
      'preset-calligraphy',
      'preset-sampled',
    ]);
  });

  testWidgets('a row drag stays inside its own group', (tester) async {
    // One tab shows one group, so a row can only move within it — crossing
    // groups is what dragging onto a tab is for.
    final reordered = <List<BrushPreset>>[];
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _marker().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
      ],
      onPresetsReordered: reordered.add,
    );

    await tester.drag(
      find.byKey(
        const ValueKey<String>('brush-preset-entry-preset-calligraphy'),
      ),
      const Offset(0, 44),
    );
    await tester.pumpAndSettle();

    expect(reordered, isNotEmpty);
    final moved = reordered.last.firstWhere(
      (preset) => preset.id == const BrushPresetId('preset-calligraphy'),
    );
    expect(moved.groupId, _ink);
    // Inside Ink the order flipped; Paint's brush never moved.
    expect(
      reordered.last.map((preset) => preset.id.value),
      containsAllInOrder(['preset-marker', 'preset-calligraphy']),
    );
  });

  testWidgets('dragging a tab reorders the groups', (tester) async {
    final reordered = <List<BrushGroup>>[];
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
      ],
      onGroupsReordered: reordered.add,
    );

    // Tabs are 26px; drag Paint above Ink.
    await tester.drag(
      find.byKey(const ValueKey<String>('brush-preset-tab-entry-paint')),
      const Offset(0, -32),
    );
    await tester.pumpAndSettle();

    expect(reordered, isNotEmpty);
    expect(reordered.last.map((group) => group.id.value), ['paint', 'ink']);
    // Members follow their group by reference — the preset list is not
    // touched at all.
    expect(_tab('paint'), findsOneWidget);
  });

  testWidgets('holding a dragged brush over a tab opens that tab', (
    tester,
  ) async {
    // The move-between-groups gesture. A tab that only accepted a DROP
    // would lose the ordering; opening it lets the brush be placed.
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _marker().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
      ],
      onPresetsReordered: (_) {},
      onGroupsReordered: (_) {},
    );
    expect(_row('preset-calligraphy'), findsOneWidget);
    expect(_row('preset-sampled'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('brush-preset-entry-preset-calligraphy'),
        ),
      ),
    );
    // Nudge past the touch slop so the reorder engages, then hover the
    // other tab and wait out the spring delay.
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(tester.getCenter(_tab('paint')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(_row('preset-sampled'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a brush merely passing over the rail changes nothing', (
    tester,
  ) async {
    // Crossing the rail on the way somewhere must not flip through every
    // tab it touches, so the switch waits.
    await _pumpPanel(
      tester,
      groups: const [
        BrushGroup(id: _ink, name: 'Ink'),
        BrushGroup(id: _paint, name: 'Paint'),
      ],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _sampled().copyWith(groupId: _paint),
      ],
      onPresetsReordered: (_) {},
      onGroupsReordered: (_) {},
    );

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('brush-preset-entry-preset-calligraphy'),
        ),
      ),
    );
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(_tab('paint')));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(_row('preset-calligraphy'), findsOneWidget);
    expect(_row('preset-sampled'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the root tab never starts a drag', (tester) async {
    final reordered = <List<BrushGroup>>[];
    await _pumpPanel(
      tester,
      groups: const [BrushGroup(id: _ink, name: 'Ink')],
      presets: [
        _calligraphy().copyWith(groupId: _ink),
        _marker(),
      ],
      onGroupsReordered: reordered.add,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('brush-preset-tab-entry-root')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();

    expect(reordered, isEmpty);
  });

  testWidgets('no rail at all when there are no groups', (tester) async {
    await _pumpPanel(tester, presets: [_calligraphy(), _marker()]);

    expect(_tab('root'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('brush-preset-tab-rail')),
      findsNothing,
    );
    expect(find.byType(BrushStrokePreview), findsNWidgets(2));
  });

  testWidgets('the last visible element cannot be hidden', (tester) async {
    Future<void> toggle(String keyValue) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-preset-menu-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>(keyValue)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
    }

    await _pumpPanel(tester, presets: [_marker()]);
    await toggle('brush-preset-view-icon-toggle');
    await toggle('brush-preset-view-name-toggle');

    // Only the stroke preview is left; its toggle must be disabled.
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')),
    );
    await tester.pumpAndSettle();
    final strokeToggle = tester.widget<CheckedPopupMenuItem<Object?>>(
      find.byKey(const ValueKey<String>('brush-preset-view-stroke-toggle')),
    );
    expect(strokeToggle.enabled, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-view-stroke-toggle')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BrushStrokePreview), findsOneWidget);
  });
}
