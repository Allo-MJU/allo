package ai.allo.car.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import kotlin.test.*

class AlloThemeTest {
    private fun contrast(a: Color, b: Color): Float {
        val x=a.luminance(); val y=b.luminance()
        return (maxOf(x,y)+0.05f)/(minOf(x,y)+0.05f)
    }

    @Test fun `light uses white surfaces and green controls while dark keeps its existing palette`() {
        val light=alloColorScheme(false); val dark=alloColorScheme(true)
        assertTrue(light.surface.luminance() > .95f)
        assertTrue(light.primary.green > light.primary.red && light.primary.green > light.primary.blue)
        assertEquals(Color(0xFF181C1E),dark.surface)
        assertEquals(Color(0xFFFCCC44),dark.primary)
    }

    @Test fun `body secondary labels and button labels remain legible in both themes`() {
        for (dark in listOf(false,true)) {
            val c=alloColorScheme(dark)
            val pairs=listOf(
                c.onSurface to c.surface, c.onSurfaceVariant to c.surface,
                c.onSurface to c.surfaceContainer, c.onSurfaceVariant to c.surfaceContainerHigh,
                c.onPrimary to c.primary, c.onPrimaryContainer to c.primaryContainer,
                c.onSecondary to c.secondary, c.onSecondaryContainer to c.secondaryContainer)
            pairs.forEach { (foreground, background) ->
                assertTrue(contrast(foreground,background) >= 4.5f,"dark=$dark foreground=$foreground background=$background")
            }
        }
    }

    @Test fun `accent code text and progress fill stay distinguishable from their surfaces`() {
        for (dark in listOf(false,true)) {
            val c=alloColorScheme(dark)
            assertTrue(contrast(c.primary,c.surface) >= 4.5f)
            assertTrue(contrast(c.primary,c.surfaceContainerHighest) >= 3f)
        }
    }
}
