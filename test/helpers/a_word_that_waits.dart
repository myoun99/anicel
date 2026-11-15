import 'package:anicel/src/native/engine_faces.dart';
import 'package:flutter_test/flutter_test.dart';

/// A LETTER NO BUNDLED FACE HAS — an emoji. A word that holds it is not the
/// GPU engine's to set (`bakeWordOnEngine`): Flutter rasters it and its
/// bake is read back, the one wait a frame grid's tile still makes for a
/// word (`TimelineGridTileStore.tileFor`).
///
/// What a test names a cel by to have a tile WAIT for its word — queued,
/// stood in for, drawn off the paint — as every word never seen before
/// did till 2026-11-15 (a-grid-row-paints-its-cells-on-a-canvas-beside-
/// its-tiles-Q3 · Q4: the engine bakes a word in the paint that asks).
const String aLetterNoBundledFaceHas = '😀';

/// Reads the engine's faces before a file's tests, so a word the engine
/// sets is baked in the ask from the first of them: till they are read —
/// once a process — every word waits, whichever test happens to ask first.
void readTheEnginesFacesFirst() => setUpAll(EngineFaces.bundled);
