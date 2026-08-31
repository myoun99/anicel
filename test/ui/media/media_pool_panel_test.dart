import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';

class _Callbacks {
  var importRequests = 0;
  final renamed = <(String, String)>[];
  final relinked = <(String, String)>[];

  /// What the relink handed on besides the path.
  ///
  /// Relink is the answer this app gives when a reference stops resolving,
  /// so it is where a durable grant matters most — and it used to throw
  /// the picker's token away, which made a relink work for one session and
  /// be refused at the next launch.
  final relinkGrants = <List<Object?>>[];
  final removed = <String>[];
  final promoted = <String>[];
  var promoteResult = true;
  final opened = <MediaAsset>[];
  bool removeResult = true;
  Set<String> referencedPaths = {};
  Set<String> existingPaths = {};
}

Future<void> _pump(
  WidgetTester tester,
  _Callbacks callbacks, {
  List<MediaAsset> assets = const [],
  Future<String?> Function()? picker,
  Map<String, int> storedBytes = const {},
  Map<String, int> conformBytes = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          child: MediaPoolPanel(
            assets: assets,
            isAssetReferenced: callbacks.referencedPaths.contains,
            onImportRequested: () => callbacks.importRequests += 1,
            onRenameAsset: (path, name) => callbacks.renamed.add((path, name)),
            onRelinkAsset: (oldPath, newPath, grants) {
              callbacks.relinked.add((oldPath, newPath));
              callbacks.relinkGrants.add(grants);
            },
            onRemoveAsset: (path) {
              callbacks.removed.add(path);
              return callbacks.removeResult;
            },
            onExportAssetWav: (_) async => true,
            onPromoteAsset: (path) async {
              callbacks.promoted.add(path);
              return callbacks.promoteResult;
            },
            onOpenAsset: callbacks.opened.add,
            audioFilePicker: picker,
            storedBytes: storedBytes,
            conformBytes: conformBytes,
            // RELINK-2: the panel no longer probes the disk — the session
            // caches the answer and hands down the MISSING set. The suite
            // still declares which paths exist, so the inversion happens
            // here rather than in every test.
            missingPaths: {
              for (final asset in assets)
                if (!callbacks.existingPaths.contains(asset.path)) asset.path,
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const foot = r'C:\snd\foot.wav';

  testWidgets('empty pool shows the guidance text', (tester) async {
    await _pump(tester, _Callbacks());
    expect(
      find.byKey(const ValueKey<String>('media-browser-empty')),
      findsOneWidget,
    );
  });

  testWidgets('rows show name/path with missing and linked badges', (
    tester,
  ) async {
    final callbacks = _Callbacks()
      ..referencedPaths = {foot}
      // clap exists on disk; foot is the missing one.
      ..existingPaths = {r'C:\snd\clap.wav'};
    await _pump(
      tester,
      callbacks,
      assets: const [
        MediaAsset(path: foot, name: '발소리'),
        MediaAsset(path: r'C:\snd\clap.wav', name: 'clap.wav'),
      ],
    );

    expect(find.text('발소리'), findsOneWidget);
    // The subtitle now leads with which one it is (유저 2026-08-31), so the
    // path rides behind it rather than standing alone.
    expect(find.textContaining(foot), findsOneWidget);
    expect(find.textContaining('Linked'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('media-asset-missing-$foot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('media-asset-linked-$foot')),
      findsOneWidget,
    );
    // The existing, unlinked asset carries neither badge.
    expect(
      find.byKey(
        const ValueKey<String>(r'media-asset-missing-C:\snd\clap.wav'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>(r'media-asset-linked-C:\snd\clap.wav')),
      findsNothing,
    );
  });

  testWidgets('the row drags its chip from the POINTER', (tester) async {
    // 🚨Not a look: the drop targets are handed `details.offset`, which is
    // the pointer MINUS this anchor, and it is the only position they get.
    // Anchored to the child — the default — a drop on a timeline layer row
    // would name a frame up to this row's width off, silently, because the
    // grab happened somewhere inside a 260px row.
    await _pump(
      tester,
      _Callbacks()..existingPaths = {foot},
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    final draggable = tester.widget<Draggable<MediaAssetDragData>>(
      find.byKey(const ValueKey<String>('media-asset-row-$foot')),
    );
    expect(draggable.dragAnchorStrategy, same(pointerDragAnchorStrategy));
  });

  testWidgets('the import button asks for the import WINDOW, not a picker', (
    tester,
  ) async {
    // It used to open an OS picker here and copy whatever came back. The
    // panel now asks its host to open the one import window, which is
    // where copy-or-reference and multi-select live.
    final callbacks = _Callbacks();
    await _pump(tester, callbacks, picker: () async => foot);

    await tester.tap(find.byKey(const ValueKey<String>('media-import-button')));
    await tester.pumpAndSettle();

    expect(callbacks.importRequests, 1);
  });

  testWidgets('rename flows through the dialog', (tester) async {
    final callbacks = _Callbacks()..existingPaths = {foot};
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-rename')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('media-rename-field')),
      '발소리',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('media-rename-save-button')),
    );
    await tester.pumpAndSettle();

    expect(callbacks.renamed, [(foot, '발소리')]);
  });

  testWidgets('relink picks the new file', (tester) async {
    const moved = r'C:\snd\moved\foot.wav';
    final callbacks = _Callbacks();
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
      picker: () async => moved,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-relink')),
    );
    await tester.pumpAndSettle();

    expect(callbacks.relinked, [(foot, moved)]);
  });

  testWidgets('open in viewer: the row menu item and a double-click both '
      'hand the asset out', (tester) async {
    final callbacks = _Callbacks()..existingPaths = {foot};
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open')),
    );
    await tester.pumpAndSettle();
    expect(callbacks.opened.map((asset) => asset.path), [foot]);

    await tester.tap(find.text('foot.wav'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('foot.wav'));
    await tester.pumpAndSettle();
    expect(callbacks.opened, hasLength(2));
  });

  testWidgets('remove: refused removals explain themselves', (tester) async {
    final callbacks = _Callbacks()..removeResult = false;
    await _pump(
      tester,
      callbacks,
      assets: const [MediaAsset(path: foot, name: 'foot.wav')],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-remove')),
    );
    await tester.pumpAndSettle();

    expect(callbacks.removed, [foot]);
    expect(find.textContaining('Still linked'), findsOneWidget);
  });

  // The other half of importing by reference: the row where a user who
  // referenced a file decides the project should own it after all.
  group('keep inside the project file', () {
    Future<void> tapPromote(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('media-asset-menu-$foot')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('media-asset-menu-promote')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hands the path to the host and says nothing on success', (
      tester,
    ) async {
      final callbacks = _Callbacks();
      await _pump(
        tester,
        callbacks,
        assets: const [MediaAsset(path: foot, name: 'foot.wav')],
      );

      await tapPromote(tester);

      expect(callbacks.promoted, [foot]);
      expect(find.textContaining('Nothing to take in'), findsNothing);
    });

    /// 🪦**This used to assert a REFUSAL NOTICE, and both halves of that
    /// are gone.**
    ///
    /// The notice said「이미 파일 안에 있거나, 항상 참조로 남는 종류
    /// (동영상)」— false since 2026-08-14, when the per-kind ceiling died —
    /// and it existed only to explain a menu item offered on rows that had
    /// nothing to promote. 유저 2026-08-31 reported the wording as a 낡은
    /// 안내창 and asked for the item to go instead: 「그걸 텍스트로 적어두고
    /// 품어진 파일이면 프로젝트 파일에 품기 안뜨도록」.
    ///
    /// So the assertion moved with the design: a carried row does not
    /// OFFER the verb, which is a stronger property than explaining it.
    testWidgets('a carried row does not offer the verb at all', (tester) async {
      final callbacks = _Callbacks();
      await _pump(
        tester,
        callbacks,
        assets: const [MediaAsset(path: foot, name: 'foot.wav', carried: true)],
      );

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();

      expect(
        find.text('Keep inside the project file'),
        findsNothing,
        reason:
            'the row already says「In the project」— an item whose only '
            'possible answer is「nothing to do」is not a verb',
      );
      expect(callbacks.promoted, isEmpty);
    });
  });

  group('what a row says a file costs', () {
    testWidgets('🚨the CONFORM is shown beside the sound', (tester) async {
      // 유저 2026-08-30, answering `conform-in-project`: 「가시화정책에 따라
      // 미디어풀 패널에서 해당파일의 컨폼파일 크기 표시할것」. A conform is
      // several times the sound itself, and until now it was a number only
      // the settings dialog knew — as one lump for the whole container.
      await _pump(
        tester,
        _Callbacks()..existingPaths = {foot},
        assets: const [MediaAsset(path: foot, name: 'foot.wav')],
        storedBytes: const {foot: 55 * 1024 * 1024},
        conformBytes: const {foot: 660 * 1024 * 1024},
      );

      expect(find.textContaining('55 MB + 660 MB'), findsOneWidget);
    });

    testWidgets('and a file with no conform says only its own size', (
      tester,
    ) async {
      // ⛔Not a dash, not a zero. Most of the pool is images, and a column
      // that announced「+ 0 KB」on every one of them would be noise about
      // something that does not apply.
      await _pump(
        tester,
        _Callbacks()..existingPaths = {foot},
        assets: const [MediaAsset(path: foot, name: 'foot.wav')],
        storedBytes: const {foot: 55 * 1024 * 1024},
      );

      expect(find.textContaining('55 MB'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });
  });
}
