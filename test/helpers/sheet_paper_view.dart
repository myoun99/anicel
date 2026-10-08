import 'package:anicel/src/models/canvas_viewport.dart';

/// The view a sheet panel KEEPS — in its paper's pixels (F-294) — that shows
/// the sheet as [unitsView] says in the sheet's own units: `sheetUnitsView`
/// run backwards.
///
/// A sheet's host takes its `viewport:` in the paper's pixels, and a pin
/// that maps a sheet's own coordinates to the screen reasons in the sheet's
/// units (a timesheet row, a conte point). So the conversion lives here,
/// once: the pin writes the view it means and seeds the host with this.
/// [paperScale] is the sheet's own — `TimesheetDocumentLayout.paperScale`,
/// `ConteSheetMetrics.paperScale`.
CanvasViewport paperViewShowing(CanvasViewport unitsView, double paperScale) =>
    unitsView.copyWith(zoom: unitsView.zoom / paperScale);
