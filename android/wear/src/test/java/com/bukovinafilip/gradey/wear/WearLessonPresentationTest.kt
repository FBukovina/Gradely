package com.bukovinafilip.gradey.wear

import com.bukovinafilip.gradey.model.NextLessonWidgetChangeKind
import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class WearLessonPresentationTest {
    private val expectedChanges = linkedMapOf(
        NextLessonWidgetChangeKind.NONE to WearLessonChangePresentation(
            label = null,
            isCanceled = false,
        ),
        NextLessonWidgetChangeKind.CANCELED to WearLessonChangePresentation(
            label = WearLessonPresentationLabel.CANCELED,
            isCanceled = true,
        ),
        NextLessonWidgetChangeKind.SUBSTITUTION to WearLessonChangePresentation(
            label = WearLessonPresentationLabel.SUBSTITUTION,
            isCanceled = false,
        ),
        NextLessonWidgetChangeKind.ROOM_CHANGED to WearLessonChangePresentation(
            label = WearLessonPresentationLabel.ROOM_CHANGED,
            isCanceled = false,
        ),
        NextLessonWidgetChangeKind.ADDED to WearLessonChangePresentation(
            label = WearLessonPresentationLabel.ADDED,
            isCanceled = false,
        ),
    )

    @Test
    fun changePresentation_mapsEveryPayloadKind() {
        assertThat(expectedChanges.keys)
            .containsExactlyElementsIn(NextLessonWidgetChangeKind.values().toList())

        expectedChanges.forEach { (kind, expected) ->
            assertThat(kind.toWearLessonChangePresentation()).isEqualTo(expected)
        }
    }

    @Test
    fun currentComplicationPresentation_mapsEveryPayloadKind() {
        expectedChanges.forEach { (kind, expectedChange) ->
            assertThat(
                wearComplicationLessonPresentation(
                    position = WearComplicationPosition.CURRENT,
                    changeKind = kind,
                ),
            ).isEqualTo(
                WearComplicationLessonPresentation(
                    compactFields = WearComplicationCompactFields(
                        titleToken = expectedCurrentTitleTokens.getValue(kind),
                        bodyRole = WearComplicationCompactBodyRole.BOUNDED_SUBJECT,
                    ),
                    change = expectedChange,
                ),
            )
        }
    }

    @Test
    fun nextComplicationPresentation_mapsEveryPayloadKind() {
        expectedChanges.forEach { (kind, expectedChange) ->
            assertThat(
                wearComplicationLessonPresentation(
                    position = WearComplicationPosition.NEXT,
                    changeKind = kind,
                ),
            ).isEqualTo(
                WearComplicationLessonPresentation(
                    compactFields = WearComplicationCompactFields(
                        titleToken = expectedNextTitleTokens.getValue(kind),
                        bodyRole = WearComplicationCompactBodyRole.BOUNDED_SUBJECT,
                    ),
                    change = expectedChange,
                ),
            )
        }
    }

    @Test
    fun localizedCompactTitles_arePresentAndAtMostSevenKotlinCharacters() {
        listOf("values", "values-cs").forEach { qualifier ->
            val strings = stringsFor(qualifier)
            compactResourceNames.forEach { resourceName ->
                val token = strings[resourceName]
                assertWithMessage("$qualifier/$resourceName is present")
                    .that(token)
                    .isNotNull()
                assertWithMessage("$qualifier/$resourceName is not blank")
                    .that(token.orEmpty().isNotBlank())
                    .isTrue()
                assertWithMessage("$qualifier/$resourceName is at most 7 Kotlin characters")
                    .that(token.orEmpty().length)
                    .isAtMost(WearComplicationCompactTokenMaxLength)
            }
        }
    }

    @Test
    fun compactSubjectToken_preservesShortSubjectsAndBoundsLongSubjectsToSevenCharacters() {
        assertThat("MAT".toWearComplicationCompactToken()).isEqualTo("MAT")
        assertThat("Mathematics".toWearComplicationCompactToken()).isEqualTo("Mathema")
        assertThat("Mathematics".toWearComplicationCompactToken().length)
            .isEqualTo(WearComplicationCompactTokenMaxLength)
    }

    private fun stringsFor(qualifier: String): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(sourceStringsFile(qualifier))
        val nodes = document.getElementsByTagName("string")
        return buildMap {
            repeat(nodes.length) { index ->
                val node = nodes.item(index)
                val name = node.attributes?.getNamedItem("name")?.nodeValue ?: return@repeat
                put(name, node.textContent)
            }
        }
    }

    private fun sourceStringsFile(qualifier: String): File {
        val workingDirectory = File(System.getProperty("user.dir") ?: ".")
        return listOf(
            File(workingDirectory, "wear/src/main/res/$qualifier/strings.xml"),
            File(workingDirectory, "src/main/res/$qualifier/strings.xml"),
            File(workingDirectory, "android/wear/src/main/res/$qualifier/strings.xml"),
        ).firstOrNull(File::isFile)
            ?: error("Cannot find Wear $qualifier/strings.xml from $workingDirectory")
    }

    private companion object {
        val expectedCurrentTitleTokens = linkedMapOf(
            NextLessonWidgetChangeKind.NONE to WearComplicationCompactTitleToken.NOW,
            NextLessonWidgetChangeKind.CANCELED to WearComplicationCompactTitleToken.NOW_CANCELED,
            NextLessonWidgetChangeKind.SUBSTITUTION to WearComplicationCompactTitleToken.NOW_SUBSTITUTION,
            NextLessonWidgetChangeKind.ROOM_CHANGED to WearComplicationCompactTitleToken.NOW_ROOM_CHANGED,
            NextLessonWidgetChangeKind.ADDED to WearComplicationCompactTitleToken.NOW_ADDED,
        )
        val expectedNextTitleTokens = linkedMapOf(
            NextLessonWidgetChangeKind.NONE to WearComplicationCompactTitleToken.NEXT,
            NextLessonWidgetChangeKind.CANCELED to WearComplicationCompactTitleToken.NEXT_CANCELED,
            NextLessonWidgetChangeKind.SUBSTITUTION to WearComplicationCompactTitleToken.NEXT_SUBSTITUTION,
            NextLessonWidgetChangeKind.ROOM_CHANGED to WearComplicationCompactTitleToken.NEXT_ROOM_CHANGED,
            NextLessonWidgetChangeKind.ADDED to WearComplicationCompactTitleToken.NEXT_ADDED,
        )
        val compactResourceNames = listOf(
            "wear_complication_now",
            "wear_complication_next",
            "wear_compact_now_canceled",
            "wear_compact_now_substitution",
            "wear_compact_now_room_changed",
            "wear_compact_now_added",
            "wear_compact_next_canceled",
            "wear_compact_next_substitution",
            "wear_compact_next_room_changed",
            "wear_compact_next_added",
        )
    }
}
