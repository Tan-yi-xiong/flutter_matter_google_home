package com.tyx.flutter_matter_google_home

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GoogleHomeMatterAvailabilityTest {
    @Test
    fun comparesDottedVersionsByNumericSegments() {
        assertEquals(
            0,
            GoogleHomeMatterAvailabilityChecker.compareVersions("26.40.32", "26.40.32"),
        )
        assertTrue(
            GoogleHomeMatterAvailabilityChecker.compareVersions("26.40.33", "26.40.32") > 0,
        )
        assertTrue(
            GoogleHomeMatterAvailabilityChecker.compareVersions("26.39.99", "26.40.32") < 0,
        )
        assertTrue(
            GoogleHomeMatterAvailabilityChecker.compareVersions("27", "26.40.32") > 0,
        )
        assertEquals(
            0,
            GoogleHomeMatterAvailabilityChecker.compareVersions(
                "26.40.32 (260400-995630914)",
                "26.40.32",
            ),
        )
        assertTrue(
            GoogleHomeMatterAvailabilityChecker.compareVersions(
                "26.40.33-beta",
                "26.40.32",
            ) > 0,
        )
    }

    @Test
    fun timeoutResultIsUnknownAndNotReady() {
        val result = GoogleHomeMatterAvailabilityChecker.timeoutResult()

        assertEquals(false, result.isReady)
        assertEquals("unknown", result.status)
        assertEquals(
            GoogleHomeMatterAvailabilityChecker.MINIMUM_PLAY_SERVICES_VERSION,
            result.minimumPlayServicesVersion,
        )
    }
}
