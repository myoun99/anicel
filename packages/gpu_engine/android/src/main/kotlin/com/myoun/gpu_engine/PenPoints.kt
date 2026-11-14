package com.myoun.gpu_engine

import android.view.MotionEvent

/**
 * Android's reader of the points the OS saw (rust/native/pen/src/points.rs,
 * H56): a touch event Flutter hears as one datum a pointer, and the samples
 * Android batched into it (`getHistorical…`), which the engine never asks
 * for (Flutter 3.47.4, AndroidTouchProcessor). Each datum's batch is written
 * before the event goes on to Flutter's view — the app hands it here from
 * the view's touch listener — handed where the engine hands Flutter the
 * pointer: `getX`/`getY`, a float made a double.
 *
 * The data are the engine's own: the pointers each action makes a datum of
 * (a press and a lift the action's pointer; a finger's lift the other
 * fingers too; a move every pointer), the time `getEventTime` gives in
 * microseconds, the pressure in the device's range, the orientation, and a
 * stylus's tilt.
 */
object PenPoints {
    init {
        // The engine's code asset, built by hook/build.dart.
        System.loadLibrary("gpu_engine")
    }

    /** Writes [event]'s batch for each pointer the engine makes a datum of. */
    fun write(event: MotionEvent) {
        val action = event.actionIndex
        val pointers = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> listOf(action)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP ->
                (0 until event.pointerCount).filter {
                    it == action || event.getToolType(it) == MotionEvent.TOOL_TYPE_FINGER
                }.sortedBy { it == action }
            MotionEvent.ACTION_MOVE -> (0 until event.pointerCount).toList()
            else -> emptyList()
        }
        val range = event.device?.getMotionRange(MotionEvent.AXIS_PRESSURE)
        val least = range?.min?.toDouble() ?: 0.0
        val most = range?.max?.toDouble() ?: 1.0
        fun part(pressure: Float): Double =
            if (most > least) (pressure - least) / (most - least) else Double.NaN
        for (p in pointers) {
            val stylus = event.getToolType(p) == MotionEvent.TOOL_TYPE_STYLUS
            for (h in 0 until event.historySize) {
                point(
                    event.getHistoricalX(p, h).toDouble(),
                    event.getHistoricalY(p, h).toDouble(),
                    event.getHistoricalEventTime(h) * 1000,
                    part(event.getHistoricalPressure(p, h)),
                    if (stylus) {
                        event.getHistoricalAxisValue(MotionEvent.AXIS_TILT, p, h).toDouble()
                    } else {
                        Double.NaN
                    },
                    event.getHistoricalAxisValue(MotionEvent.AXIS_ORIENTATION, p, h).toDouble(),
                )
            }
            point(
                event.getX(p).toDouble(),
                event.getY(p).toDouble(),
                event.eventTime * 1000,
                part(event.getPressure(p)),
                if (stylus) event.getAxisValue(MotionEvent.AXIS_TILT, p).toDouble() else Double.NaN,
                event.getAxisValue(MotionEvent.AXIS_ORIENTATION, p).toDouble(),
            )
            end(event.getPointerId(p).toLong(), event.getX(p).toDouble(), event.getY(p).toDouble())
        }
    }

    @JvmStatic
    private external fun point(
        x: Double,
        y: Double,
        micros: Long,
        pressure: Double,
        tilt: Double,
        orientation: Double,
    )

    @JvmStatic
    private external fun end(contact: Long, x: Double, y: Double)
}
