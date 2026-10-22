package com.myoun.anicel

import android.app.Activity
import android.os.Build
import android.view.Display

// every-screen-at-its-own-refresh-rate (user 2026-10-16: 「144fps모니터에서 봐도
// 60으로보인다던가 … 최대 프레임 주사율에 맞춰서 하고싶은데」). Flutter's engine
// draws at whatever rate the display runs - it follows the Choreographer -
// and asks for no rate of its own, so a device whose policy keeps an app that
// asks for nothing at 60 keeps a 120Hz panel at 60 under us. The window asks
// for the display's fastest mode at the size it already has: never another
// resolution, which would rescale everything for a rate.
internal fun Activity.preferTheFastestDisplayMode() {
    val display: Display = (
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
    ) ?: return
    val now = display.mode
    val fastest = display.supportedModes
        .filter {
            it.physicalWidth == now.physicalWidth &&
                it.physicalHeight == now.physicalHeight
        }
        .maxByOrNull { it.refreshRate } ?: return
    val attributes = window.attributes
    attributes.preferredDisplayModeId = fastest.modeId
    window.attributes = attributes
}
