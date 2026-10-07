package com.bukovinafilip.gradey.domain

object TodayStudentNames {
    fun resolve(
        schoolFullName: String?,
        activeLinkedAccountDisplayName: String?,
    ): String? = sequenceOf(schoolFullName, activeLinkedAccountDisplayName)
        .mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }
        .firstOrNull()
}
