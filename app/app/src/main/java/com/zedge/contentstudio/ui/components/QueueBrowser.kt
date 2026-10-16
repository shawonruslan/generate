package com.zedge.contentstudio.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.zedge.contentstudio.ChipRow
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.theme.Danger
import com.zedge.contentstudio.ui.theme.typeColor
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** Content-type filter options (key -> label). "ALL" means no type filter. */
private val TYPE_OPTIONS: List<Pair<String, String>> = listOf("ALL" to "All types") +
    listOf("RINGTONE", "WALLPAPER", "WALLPAPER_24H", "WALLPAPER_DUAL", "WALLPAPER_BATTERY", "LIVE_WALLPAPER", "CHARGING_ANIMATION")
        .map { it to ContentTypes.dayUi(if (it == "RINGTONE") "AUDIO" else it).label }

private val STATUS_OPTIONS: List<Pair<String, String>> = listOf(
    "ALL" to "Any status", "queued" to "Queued", "processing" to "Processing", "uploaded" to "Uploaded", "failed" to "Failed",
)

/** Plural label used in buttons / confirmations. */
fun typePlural(type: String): String = when (type) {
    "RINGTONE" -> "ringtones"
    "WALLPAPER" -> "wallpapers"
    "WALLPAPER_24H" -> "24H sets"
    "WALLPAPER_DUAL" -> "dual sets"
    "WALLPAPER_BATTERY" -> "battery sets"
    "LIVE_WALLPAPER" -> "live wallpapers"
    "CHARGING_ANIMATION" -> "charging animations"
    else -> "files"
}

/** Filter state + matcher shared by the browser UI and the bulk-delete action. */
data class QueueFilter(
    val query: String = "",
    val type: String = "ALL",
    val status: String = "ALL",
    val fromDay: LocalDate? = null,
    val toDay: LocalDate? = null,
) {
    val isActive: Boolean get() = query.isNotBlank() || type != "ALL" || status != "ALL" || fromDay != null || toDay != null

    fun matches(item: QueueItem): Boolean {
        if (type != "ALL" && item.contentType != type) return false
        if (status != "ALL") {
            if (status == "failed") { if (!item.isFailed) return false } else if (item.status != status) return false
        }
        if (fromDay != null || toDay != null) {
            val t = item.addedAtMs
            if (t <= 0L) return false
            val day = Instant.ofEpochMilli(t).atZone(RealTime.DHAKA).toLocalDate()
            if (fromDay != null && day.isBefore(fromDay)) return false
            if (toDay != null && day.isAfter(toDay)) return false
        }
        if (query.isNotBlank()) {
            val hay = listOf(item.title, item.name, item.tags, item.category, item.description, item.id).joinToString(" \u0001 ").lowercase()
            val terms = query.lowercase().split(Regex("\\s+")).filter { it.isNotBlank() }
            if (!terms.all { hay.contains(it) }) return false
        }
        return true
    }

    fun describe(): String = listOfNotNull(
        if (type != "ALL") "type: ${typePlural(type)}" else null,
        if (status != "ALL") "status: $status" else null,
        if (query.isNotBlank()) "search: \"$query\"" else null,
        if (fromDay != null || toDay != null) "date: ${fromDay ?: "…"} → ${toDay ?: "…"}" else null,
    ).joinToString(", ")
}

/**
 * Search / filter / bulk-delete browser for the queue of the active account.
 * - Search by name / title / tags / category / description
 * - Filter by content type, status and "added" date range (Dhaka days)
 * - "Delete all" removes every item matching the current filter (e.g. all ringtones)
 */
@Composable
fun QueueBrowserSection(vm: MainViewModel, items: List<QueueItem>, accountLabel: String, modifier: Modifier = Modifier) {
    var query by rememberSaveable { mutableStateOf("") }
    var type by rememberSaveable { mutableStateOf("ALL") }
    var status by rememberSaveable { mutableStateOf("ALL") }
    var fromDay by remember { mutableStateOf<LocalDate?>(null) }
    var toDay by remember { mutableStateOf<LocalDate?>(null) }
    var shown by remember { mutableIntStateOf(20) }
    var pickFor by remember { mutableStateOf<String?>(null) } // "from" | "to" | null

    val filter = QueueFilter(query, type, status, fromDay, toDay)
    val matching = remember(items, filter) { items.filter { filter.matches(it) }.sortedByDescending { it.addedAtMs } }
    val plural = typePlural(type)

    SectionCard(
        "Search & manage files in $accountLabel",
        if (filter.isActive) "${matching.size} of ${items.size} file(s) match" else "${items.size} file(s) · search by name, date or type",
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it; shown = 20 },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("Search name, title, tags…") },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            trailingIcon = if (query.isNotEmpty()) ({ IconButton(onClick = { query = "" }) { Icon(Icons.Default.Close, "Clear") } }) else null,
        )
        Spacer(Modifier.height(10.dp))
        Text("Content type", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        ChipRow(options = TYPE_OPTIONS, selected = type, onSelect = { type = it; shown = 20 })
        Spacer(Modifier.height(8.dp))
        Text("Status", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        ChipRow(options = STATUS_OPTIONS, selected = status, onSelect = { status = it; shown = 20 })
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { pickFor = "from" }, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.DateRange, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp))
                Text(fromDay?.let { "From ${RealTime.prettyKey(it.toString())}" } ?: "From date")
            }
            OutlinedButton(onClick = { pickFor = "to" }, modifier = Modifier.weight(1f)) {
                Icon(Icons.Default.DateRange, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp))
                Text(toDay?.let { "To ${RealTime.prettyKey(it.toString())}" } ?: "To date")
            }
        }
        if (filter.isActive) {
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { query = ""; type = "ALL"; status = "ALL"; fromDay = null; toDay = null; shown = 20 }) {
                    Icon(Icons.Default.Close, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Clear filters")
                }
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = { vm.deleteMatching(matching, plural, filter.describe()) },
                    enabled = matching.isNotEmpty(),
                    colors = ButtonDefaults.buttonColors(containerColor = Danger, contentColor = MaterialTheme.colorScheme.onError),
                ) {
                    Icon(Icons.Default.DeleteSweep, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                    Text("Delete all ${matching.size} $plural")
                }
            }
        } else {
            Spacer(Modifier.height(6.dp))
            Text(
                "Tip: pick a content type (e.g. Ringtone) to bulk delete every file of that type from this account.",
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(Modifier.height(12.dp))
        if (matching.isEmpty()) {
            EmptyState(if (filter.isActive) "No files match your search / filter." else "No files in this account yet.")
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                matching.take(shown).forEach { item ->
                    val added = if (item.addedAtMs > 0) RealTime.stampOf(item.addedAtMs) else "–"
                    QueueRow(
                        item,
                        subtitle = "${item.status} · $added",
                        onClick = { vm.selectedItem.value = item },
                        trailing = { StatusPill(item.status.uppercase(), if (item.isFailed) Danger else typeColor(item.dayType)) },
                    )
                }
            }
            if (matching.size > shown) {
                Spacer(Modifier.height(6.dp))
                OutlinedButton(onClick = { shown += 20 }, modifier = Modifier.fillMaxWidth()) {
                    Text("Show more (${matching.size - shown} left)", fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    val target = pickFor
    if (target != null) {
        val initial = (if (target == "from") fromDay else toDay) ?: LocalDate.now(RealTime.DHAKA)
        val state = rememberDatePickerState(initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickFor = null },
            confirmButton = {
                TextButton(onClick = {
                    val ms = state.selectedDateMillis
                    val day = ms?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }
                    if (target == "from") fromDay = day else toDay = day
                    shown = 20
                    pickFor = null
                }) { Text("OK") }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = { if (target == "from") fromDay = null else toDay = null; pickFor = null }) { Text("Clear") }
                    TextButton(onClick = { pickFor = null }) { Text("Cancel") }
                }
            },
        ) { DatePicker(state = state) }
    }
}
