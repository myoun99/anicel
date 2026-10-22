// A NUMBERED RUN OPENS AS ONE DOCUMENT, A PICTURE A PAGE (F-282).
//
// 🗣️유저 2026-10-09 (F-282, 시안 ③ · ④): 「연번은 들어갈 범위만(A2–A3) —
// 미리보기의 IN/OUT, 동영상과 같은 법」. The import window's preview pages
// through a run as this document: a picture opens when its page is asked
// for, and only the few asked for last stay open — a run can be hundreds
// of scans.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/media/viewer_document.dart';
import 'package:anicel/src/ui/media/picture_run_document.dart';

import '../../helpers/fake_pdf_document.dart';

/// One picture of a run: a fake of one page — or none, [empty] — that
/// counts how often it was let go of.
final class _Picture extends FakePdfDocument {
  _Picture(ui.Size size, {bool empty = false})
    : super(pageSizes: empty ? const [] : [size]);

  int disposals = 0;

  @override
  Future<void> dispose() async {
    disposals += 1;
    await super.dispose();
  }
}

/// A run of pictures `p0` · `p1` …, each a one-page fake of its own size,
/// and the door that opens them — a fresh picture every time it opens one.
final class _Run {
  _Run(this.sizes, {this.unreadable = const {}, this.empty = const {}});

  final List<ui.Size> sizes;

  /// The pictures the door answers null for.
  final Set<int> unreadable;

  /// The pictures that open with no page in them.
  final Set<int> empty;

  /// Every picture the door was asked to open, in order.
  final List<int> asked = [];

  final List<({int index, _Picture picture})> _opened = [];

  /// Openings held until their gate completes — a door still out.
  final Map<int, Completer<void>> held = {};

  List<String> get files => [for (var i = 0; i < sizes.length; i += 1) 'p$i'];

  /// The picture [index] opened as last.
  _Picture last(int index) =>
      _opened.lastWhere((opened) => opened.index == index).picture;

  Future<ViewerDocument?> door(String file) async {
    final index = int.parse(file.substring(1));
    asked.add(index);
    final gate = held[index];
    if (gate != null) {
      await gate.future;
    }
    if (unreadable.contains(index)) {
      return null;
    }
    final picture = _Picture(sizes[index], empty: empty.contains(index));
    _opened.add((index: index, picture: picture));
    return picture;
  }

  Future<PictureRunDocument> open() async =>
      (await PictureRunDocument.openThrough(files, door))!;
}

const _size = ui.Size(100, 50);

Future<void> _draw(PictureRunDocument run, int page) async =>
    (await run.renderPage(page, width: 10, height: 5)).dispose();

void main() {
  test('a page per picture — the first opens with the run, the rest only '
      'when their page is asked for', () async {
    final run = _Run(List.filled(3, _size));
    final doc = await run.open();

    expect(doc.pageCount, 3);
    expect(doc.framesPerSecond, isNull, reason: 'paged by hand, as a book');
    expect(
      doc.drawnAtAnySize,
      isFalse,
      reason: 'its pages are pictures: past their pixels, none more',
    );
    expect(run.asked, [0]);

    await _draw(doc, 2);

    expect(run.asked, [0, 2]);
  });

  test('a page not yet opened answers the first picture\'s size; drawn, its '
      'own — and it is drawn in its own shape at the scale it was asked',
      () async {
    final run = _Run([_size, _size, const ui.Size(40, 80)]);
    final doc = await run.open();
    expect(doc.pageSize(2), _size);

    final image = await doc.renderPage(2, width: 200, height: 100);
    addTearDown(image.dispose);

    expect(
      run.last(2).renderRequests,
      [(0, 80, 160)],
      reason: 'asked at twice the first picture\'s width: twice its own',
    );
    expect((image.width, image.height), (80, 160));
    expect(doc.pageSize(2), const ui.Size(40, 80));
  });

  test('past keptOpen the picture asked for longest ago is let go — and '
      'opens again when it is asked for again', () async {
    const kept = PictureRunDocument.keptOpen;
    final run = _Run(List.filled(kept + 2, _size));
    final doc = await run.open();

    for (var page = 1; page <= kept; page += 1) {
      await _draw(doc, page);
    }

    expect(run.last(0).disposals, 1, reason: 'p0 was asked for first');
    expect(
      [for (var page = 1; page <= kept; page += 1) run.last(page).disposals],
      everyElement(0),
    );

    await _draw(doc, 0);

    expect(run.asked.where((page) => page == 0), hasLength(2));
    expect(run.last(1).disposals, 1, reason: 'now p1 is the oldest');

    await _draw(doc, 1);

    expect(
      run.asked.where((page) => page == 1),
      hasLength(2),
      reason: 'a picture opened on an ask opens again, too',
    );
  });

  test('a picture a render is still reading is never let go under it',
      () async {
    const kept = PictureRunDocument.keptOpen;
    final run = _Run(List.filled(kept + 2, _size));
    final doc = await run.open();
    run.last(0).holdRender(0);
    final reading = doc.renderPage(0, width: 10, height: 5);
    await pumpEventQueue();

    for (var page = 1; page <= kept; page += 1) {
      await _draw(doc, page);
    }

    expect(run.last(0).disposals, 0, reason: 'p0 is still being read');
    expect(run.last(1).disposals, 1, reason: 'the next oldest goes');
    run.last(0).releaseRender(0);
    (await reading).dispose();
    expect(run.last(0).disposals, 0);
  });

  test('🚨one passed over while a render read it goes once the render ends: '
      'the run holds keptOpen again', () async {
    const kept = PictureRunDocument.keptOpen;
    final run = _Run(List.filled(kept + 1, _size));
    final doc = await run.open();
    for (var page = 1; page < kept; page += 1) {
      await _draw(doc, page);
    }
    final reads = <Future<ui.Image>>[];
    for (var page = 0; page < kept; page += 1) {
      run.last(page).holdRender(0);
      reads.add(doc.renderPage(page, width: 10, height: 5));
    }
    await pumpEventQueue();

    await _draw(doc, kept);

    expect(
      [for (var page = 0; page <= kept; page += 1) run.last(page).disposals],
      everyElement(0),
      reason: 'every one but the newest is being read',
    );

    run.last(0).releaseRender(0);
    (await reads.first).dispose();

    expect(run.last(0).disposals, 1, reason: 'read no more, the oldest goes');
    for (var page = 1; page < kept; page += 1) {
      run.last(page).releaseRender(0);
      (await reads[page]).dispose();
    }
    expect(
      [for (var page = 1; page <= kept; page += 1) run.last(page).disposals],
      everyElement(0),
    );
  });

  test('a picture asked for again is the newest: the one asked for longest '
      'ago goes in its place', () async {
    const kept = PictureRunDocument.keptOpen;
    final run = _Run(List.filled(kept + 1, _size));
    final doc = await run.open();
    for (var page = 1; page < kept; page += 1) {
      await _draw(doc, page);
    }

    await _draw(doc, 0);
    await _draw(doc, kept);

    expect(run.last(0).disposals, 0, reason: 'asked for again since');
    expect(run.last(1).disposals, 1);
    expect(run.asked.where((page) => page == 0), hasLength(1));
  });

  test('one opening per picture, however many asks are out at once',
      () async {
    final run = _Run(List.filled(3, _size));
    final doc = await run.open();
    run.held[2] = Completer<void>();

    final first = doc.renderPage(2, width: 10, height: 5);
    final second = doc.renderPage(2, width: 10, height: 5);
    await pumpEventQueue();
    run.held.remove(2)!.complete();
    (await first).dispose();
    (await second).dispose();

    expect(run.asked, [0, 2]);
    expect(run.last(2).renderRequests, hasLength(2));
  });

  test('a picture that cannot be read fails its own page, not the run — '
      'one that opens with no page in it is let go', () async {
    final run = _Run(List.filled(4, _size), unreadable: {1}, empty: {2});
    final doc = await run.open();

    await expectLater(
      doc.renderPage(1, width: 10, height: 5),
      throwsStateError,
    );
    await expectLater(
      doc.renderPage(2, width: 10, height: 5),
      throwsStateError,
    );
    expect(run.last(2).disposals, 1);
    await _draw(doc, 3);
  });

  test('no run opens without its first picture', () async {
    final none = _Run(const []);
    expect(await PictureRunDocument.openThrough(none.files, none.door), isNull);
    final unread = _Run([_size, _size], unreadable: {0});
    expect(
      await PictureRunDocument.openThrough(unread.files, unread.door),
      isNull,
    );
    final blank = _Run([_size, _size], empty: {0});
    expect(
      await PictureRunDocument.openThrough(blank.files, blank.door),
      isNull,
    );
    expect(blank.last(0).disposals, 1);
  });

  test('let go, the run lets go of every picture it holds — and of one '
      'still on its way open, when it arrives', () async {
    final run = _Run(List.filled(3, _size));
    final doc = await run.open();
    await _draw(doc, 1);
    run.held[2] = Completer<void>();
    final arriving = doc.renderPage(2, width: 10, height: 5);
    await pumpEventQueue();

    await doc.dispose();

    expect([run.last(0).disposals, run.last(1).disposals], [1, 1]);
    run.held.remove(2)!.complete();
    await expectLater(arriving, throwsStateError);
    expect(run.last(2).disposals, 1);
  });

  test('two asks waiting on one picture when the run is let go: it is let '
      'go of once', () async {
    final run = _Run(List.filled(3, _size));
    final doc = await run.open();
    run.held[2] = Completer<void>();
    final first = doc.renderPage(2, width: 10, height: 5);
    final second = doc.renderPage(2, width: 10, height: 5);
    await pumpEventQueue();

    await doc.dispose();
    run.held.remove(2)!.complete();

    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(run.last(2).disposals, 1);
  });

  test('a region is read from its picture\'s own page', () async {
    final run = _Run(List.filled(3, _size));
    final doc = await run.open();

    await doc.readRegionRgba(2, (left: 1, top: 2, width: 3, height: 4));

    expect(run.last(2).regionReads, [(0, 1, 2, 3, 4)]);
  });
}
