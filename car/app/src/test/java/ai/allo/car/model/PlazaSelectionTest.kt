package ai.allo.car.model

import kotlin.test.*

class PlazaSelectionTest {
    private val available = (1..12).map { "pet$it" }
    @Test fun `defaults take six but explicit empty remains empty`() {
        assertEquals(available.take(6), PlazaPopulation.selected(available, null))
        assertEquals(emptyList(), PlazaPopulation.selected(available, emptyList()))
    }
    @Test fun `six limit allows deselect before replacement`() {
        val full = PlazaPopulation.selected(available, null)
        assertEquals(full, PlazaPopulation.toggle(available, full, "pet7"))
        val removed = PlazaPopulation.toggle(available, full, "pet1")
        assertEquals(full.drop(1) + "pet7", PlazaPopulation.toggle(available, removed, "pet7"))
    }
    @Test fun `unowned duplicate stale selections are filtered`() {
        assertEquals(listOf("pet3"), PlazaPopulation.selected(available, listOf("gone", "pet3", "pet3")))
        assertEquals(emptyList(), PlazaPopulation.toggle(emptyList(), available, "pet1"))
        assertEquals(listOf("pet3"), PlazaPopulation.toggle(available, listOf("pet3"), "unknown"))
    }
}
