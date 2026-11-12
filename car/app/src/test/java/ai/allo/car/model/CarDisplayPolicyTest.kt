package ai.allo.car.model

import kotlin.test.*

class CarDisplayPolicyTest {
    @Test fun `unverified or restricted state never exposes parking or pairing controls`() {
        assertEquals(CarScreen.Driving, CarDisplayPolicy.screen(false, false))
        assertEquals(CarScreen.Driving, CarDisplayPolicy.screen(true, false))
        assertEquals(CarScreen.Pairing, CarDisplayPolicy.screen(false, true))
        assertEquals(CarScreen.Parked, CarDisplayPolicy.screen(true, true))
    }

    @Test fun `configured sharing reopens only after actual driving to parking`() {
        val transition = ParkedShareTransition()
        assertFalse(transition.update(false, null, null, true))
        assertFalse(transition.update(true, true, true, true)) // First open is explicit.
        assertFalse(transition.update(true, false, false, true))
        assertFalse(transition.update(true, null, null, true))
        assertFalse(transition.update(true, true, false, true))
        assertTrue(transition.update(true, true, true, true))
        assertFalse(transition.update(true, true, true, true)) // Back/resume must not loop.
    }

    @Test fun `no previous connection means no automatic sharing`() {
        val transition = ParkedShareTransition()
        transition.update(true, false, false, false)
        assertFalse(transition.update(true, true, true, false))
        assertFalse(transition.update(true, true, true, true))
    }
}
