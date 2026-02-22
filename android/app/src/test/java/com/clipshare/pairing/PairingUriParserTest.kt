package com.clipshare.pairing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PairingUriParserTest {
    @Test
    fun parsesValidUri_andNormalizesToken() {
        val info = PairingUriParser.parse(
            "greenpaste://pair?t=AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899&n=Mac%20Mini"
        )

        requireNotNull(info)
        assertEquals("aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899", info.token)
        assertEquals("Mac Mini", info.deviceName)
    }

    @Test
    fun rejectsInvalidSchemeHostAndToken() {
        assertNull(PairingUriParser.parse("https://pair?t=abcd"))
        assertNull(PairingUriParser.parse("greenpaste://wrong?t=abcd"))
        assertNull(PairingUriParser.parse("greenpaste://pair?t=abcd"))
        assertNull(
            PairingUriParser.parse(
                "greenpaste://pair?t=zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
            )
        )
    }

    @Test
    fun blankDeviceNameBecomesNull() {
        val info = PairingUriParser.parse(
            "greenpaste://pair?t=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff&n="
        )

        requireNotNull(info)
        assertNull(info.deviceName)
    }

    @Test
    fun malformedQueryEncoding_returnsNullWithoutCrashing() {
        val info = PairingUriParser.parse(
            "greenpaste://pair?t=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff&n=%"
        )

        assertNull(info)
    }

    @Test
    fun rejectsNonCanonicalUriFormsAndLegacyParamNames() {
        assertNull(
            PairingUriParser.parse(
                "greenpaste:/pair?token=ffeeddccbbaa00998877665544332211ffeeddccbbaa00998877665544332211&name=Mac Book"
            )
        )

        assertNull(
            PairingUriParser.parse(
                "greenpaste://pair?token=ffeeddccbbaa00998877665544332211ffeeddccbbaa00998877665544332211&name=Mac Book"
            )
        )
    }
}
