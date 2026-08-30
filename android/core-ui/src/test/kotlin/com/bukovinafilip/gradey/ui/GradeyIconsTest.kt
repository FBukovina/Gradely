package com.bukovinafilip.gradey.ui

import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GradeyIconsTest {
    @Test
    fun everyCatalogEntryBuildsAsAUnique24DpVector() {
        val vectors = GradeyIcons::class.java.declaredMethods
            .filter { method ->
                Modifier.isPublic(method.modifiers) &&
                    method.parameterCount == 0 &&
                    method.returnType == ImageVector::class.java
            }
            .map { method -> method.invoke(GradeyIcons) as ImageVector }

        assertTrue("The icon catalog must not be empty", vectors.isNotEmpty())
        assertEquals(vectors.size, vectors.map(ImageVector::name).distinct().size)
        vectors.forEach { vector ->
            assertEquals(24.dp, vector.defaultWidth)
            assertEquals(24.dp, vector.defaultHeight)
            assertEquals(24f, vector.viewportWidth)
            assertEquals(24f, vector.viewportHeight)
        }
    }
}
