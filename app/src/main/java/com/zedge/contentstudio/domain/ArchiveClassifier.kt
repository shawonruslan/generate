package com.zedge.contentstudio.domain

import com.github.junrar.Archive
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.NaturalOrder
import com.zedge.contentstudio.core.SetMeta
import com.zedge.contentstudio.data.LocalFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream

/** One media file inside a ZIP / RAR (path is the full path inside the archive). */
class ArchiveEntry(val name: String, val bytes: ByteArray, val archive: String) {
    val base: String get() = name.substringAfterLast('/')
    val dir: String get() = if (name.contains('/')) name.substringBeforeLast('/') else ""
    val size: Long get() = bytes.size.toLong()
    fun toLocalFile(): LocalFile = LocalFile(base, bytes, LocalFile.mimeFor(base))
}

/** Detected set (24H / Dual / Battery): exactly one entry per slot. */
class SetUnit(val type: String, val files: Map<String, ArchiveEntry>, val byName: Boolean, val label: String, val archive: String) {
    val meta: SetMeta get() = ContentTypes.SET_TYPES.getValue(type)
}

sealed class ImportUnit {
    class Set(val set: SetUnit) : ImportUnit()
    /** media = image | audio | video */
    class File(val media: String, val entry: ArchiveEntry) : ImportUnit()

    val title: String
        get() = when (this) {
            is Set -> set.label.ifBlank { set.archive.ifBlank { set.meta.label } }.let { if (set.label.isBlank()) "${set.meta.short} set (${it})" else "${set.meta.short}: $it" }
            is File -> entry.base
        }
}

class Classification(val units: List<ImportUnit>, val notes: List<String>, val mediaCount: Int)
class Grouping(val sets: List<SetUnit>, val leftovers: List<ArchiveEntry>, val imageCount: Int)

/**
 * Exact port of the dashboard's Smart Archive Import classification:
 *   folder with 2 images -> Dual, 4 -> 24H, 6 -> Battery; other images -> single wallpapers,
 *   mp3 -> ringtone, mp4/mov -> video. Works for ANY number of folders.
 */
object ArchiveClassifier {
    val IMG_RE = Regex("\\.(jpe?g|png|webp)$", RegexOption.IGNORE_CASE)
    val AUDIO_RE = Regex("\\.mp3$", RegexOption.IGNORE_CASE)
    val VIDEO_RE = Regex("\\.(mp4|mov)$", RegexOption.IGNORE_CASE)
    val AUX_RE = Regex("(preview|thumb|thumbnail|cover|poster|collage|mockup|screenshot)", RegexOption.IGNORE_CASE)

    fun isJunk(path: String): Boolean {
        val b = path.substringAfterLast('/')
        return b.isEmpty() || path.contains("__MACOSX/") || b.startsWith(".") || b.equals("thumbs.db", ignoreCase = true)
    }

    fun prettySetLabel(folder: String): String {
        if (folder.isBlank()) return ""
        return folder.replace(Regex("[_\\-]+"), " ").replace(Regex("\\s+"), " ").trim()
            .replace(Regex("\\b([a-z])")) { it.groupValues[1].uppercase() }
    }

    /** "set1_night.jpg" -> night, "lock.png" -> lock, "wall_2.jpg" -> 2nd slot. */
    fun detectSlot(fileBase: String, slots: List<String>): String? {
        val stem = fileBase.replace(Regex("\\.[^.]+$"), "").lowercase()
        val tokens = stem.split(Regex("[^a-z0-9]+")).filter { it.isNotEmpty() }
        for (slot in slots) {
            val words = ContentTypes.SLOT_WORDS[slot] ?: listOf(slot)
            if (words.any { it in tokens }) return slot
        }
        val m = Regex("(\\d+)$").find(stem)
        if (m != null) {
            val idx = m.groupValues[1].toInt() - 1
            if (idx >= 0 && idx < slots.size) return slots[idx]
        }
        return null
    }

    fun pickBySlotNames(files: List<ArchiveEntry>, slots: List<String>): Map<String, ArchiveEntry>? {
        val byName = LinkedHashMap<String, ArchiveEntry>()
        for (f in files) { val sl = detectSlot(f.base, slots); if (sl != null && !byName.containsKey(sl)) byName[sl] = f }
        return if (byName.size == slots.size) byName else null
    }

    fun makeSet(type: String, files: List<ArchiveEntry>, label: String, archive: String): SetUnit {
        val slots = ContentTypes.SET_TYPES.getValue(type).slots
        val byName = pickBySlotNames(files, slots)
        if (byName != null) return SetUnit(type, byName, true, label, archive)
        val ordered = LinkedHashMap<String, ArchiveEntry>()
        slots.forEachIndexed { i, sl -> ordered[sl] = files[i] }
        return SetUnit(type, ordered, false, label, archive)
    }

    private fun byDir(imgs: List<ArchiveEntry>): Map<String, List<ArchiveEntry>> {
        val m = LinkedHashMap<String, MutableList<ArchiveEntry>>()
        for (e in imgs) m.getOrPut(e.dir) { ArrayList() }.add(e)
        return m.keys.sortedWith(NaturalOrder).associateWith { k -> m.getValue(k).sortedWith(compareBy(NaturalOrder) { it.base }) }
    }

    /** Folder with exactly N images = one set; otherwise chunk N at a time in natural order. */
    fun groupIntoSets(entries: List<ArchiveEntry>, type: String, archive: String): Grouping {
        val slots = ContentTypes.SET_TYPES.getValue(type).slots
        val n = slots.size
        val imgs = entries.filter { !isJunk(it.name) && IMG_RE.containsMatchIn(it.name) }
        val sets = ArrayList<SetUnit>()
        val leftovers = ArrayList<ArchiveEntry>()
        for ((dir, files) in byDir(imgs)) {
            val folderLabel = prettySetLabel(dir.substringAfterLast('/'))
            if (files.size == n) { sets.add(makeSet(type, files, folderLabel, archive)); continue }
            if (files.size > n && files.size < 2 * n) {
                val main = files.filter { !AUX_RE.containsMatchIn(it.base) }
                val aux = files.filter { AUX_RE.containsMatchIn(it.base) }
                if (main.size == n) { sets.add(makeSet(type, main, folderLabel, archive)); leftovers.addAll(aux); continue }
                val picked = pickBySlotNames(files, slots)
                if (picked != null) {
                    val used = picked.values.toSet()
                    sets.add(SetUnit(type, picked, true, folderLabel, archive))
                    leftovers.addAll(files.filter { it !in used }); continue
                }
            }
            var k = 0
            var i = 0
            while (i + n <= files.size) {
                sets.add(makeSet(type, files.subList(i, i + n), if (folderLabel.isNotBlank()) "$folderLabel #${k + 1}" else "", archive))
                i += n; k++
            }
            leftovers.addAll(files.drop((files.size / n) * n))
        }
        return Grouping(sets, leftovers, imgs.size)
    }

    fun classify(entries: List<ArchiveEntry>, archiveName: String, fallbackType: String?): Classification {
        val units = ArrayList<ImportUnit>()
        val notes = ArrayList<String>()
        val media = entries.filter { !isJunk(it.name) && (IMG_RE.containsMatchIn(it.name) || AUDIO_RE.containsMatchIn(it.name) || VIDEO_RE.containsMatchIn(it.name)) }
        media.filter { AUDIO_RE.containsMatchIn(it.name) }.sortedWith(compareBy(NaturalOrder) { it.name }).forEach { units.add(ImportUnit.File("audio", it)) }
        media.filter { VIDEO_RE.containsMatchIn(it.name) }.sortedWith(compareBy(NaturalOrder) { it.name }).forEach { units.add(ImportUnit.File("video", it)) }
        val imgs = media.filter { IMG_RE.containsMatchIn(it.name) }
        val dirs = byDir(imgs)
        for ((dir, sorted) in dirs) {
            var files = sorted
            val label = prettySetLabel(dir.substringAfterLast('/'))
            var type = ContentTypes.COUNT_TO_SET_TYPE[files.size]
            if (type == null && dir.isNotEmpty()) {
                val main = files.filter { !AUX_RE.containsMatchIn(it.base) }
                if (main.size != files.size && ContentTypes.COUNT_TO_SET_TYPE.containsKey(main.size)) {
                    notes.add("$label: ignored ${files.size - main.size} preview/cover image(s)")
                    files = main
                    type = ContentTypes.COUNT_TO_SET_TYPE[files.size]
                }
            }
            if (type != null && dir.isNotEmpty()) { units.add(ImportUnit.Set(makeSet(type, files, label, archiveName))); continue }
            if (type != null && dir.isEmpty() && dirs.size == 1) { units.add(ImportUnit.Set(makeSet(type, files, "", archiveName))); continue }
            if (fallbackType != null && ContentTypes.isSet(fallbackType)) {
                val flat = files.map { ArchiveEntry(it.base, it.bytes, it.archive) }
                val g = groupIntoSets(flat, fallbackType, archiveName)
                g.sets.forEachIndexed { i, st -> units.add(ImportUnit.Set(SetUnit(fallbackType, st.files, st.byName, if (label.isNotBlank()) "$label #${i + 1}" else "", archiveName))) }
                if (g.leftovers.isNotEmpty()) notes.add("${label.ifBlank { "root" }}: ${g.leftovers.size} image(s) left over (not a full ${ContentTypes.SET_TYPES.getValue(fallbackType).short} set) - skipped")
                continue
            }
            if (dir.isNotEmpty() && files.size > 1) notes.add("$label: ${files.size} images is not a set size (2 / 4 / 6) - queued as single wallpapers")
            files.forEach { units.add(ImportUnit.File("image", it)) }
        }
        return Classification(units, notes, media.size)
    }

    /** "3 x 24H Wallpaper Set, 2 single wallpaper(s), 1 ringtone(s)" */
    fun describe(units: List<ImportUnit>): String {
        val c = HashMap<String, Int>()
        for (u in units) { val k = when (u) { is ImportUnit.Set -> u.set.type; is ImportUnit.File -> u.media }; c[k] = (c[k] ?: 0) + 1 }
        val parts = ArrayList<String>()
        for (t in listOf("WALLPAPER_24H", "WALLPAPER_DUAL", "WALLPAPER_BATTERY")) c[t]?.let { parts.add("$it x ${ContentTypes.SET_TYPES.getValue(t).label}") }
        c["image"]?.let { parts.add("$it single wallpaper(s)") }
        c["audio"]?.let { parts.add("$it ringtone(s)") }
        c["video"]?.let { parts.add("$it video(s)") }
        return parts.joinToString(", ")
    }
}

/** Reads every non-directory entry of a ZIP or RAR into memory (media-only, junk skipped). */
object ArchiveReader {
    suspend fun read(file: LocalFile): List<ArchiveEntry> = withContext(Dispatchers.IO) {
        val b = file.bytes
        val isRar = b.size > 4 && b[0] == 0x52.toByte() && b[1] == 0x61.toByte() && b[2] == 0x72.toByte() && b[3] == 0x21.toByte()
        val isZip = b.size > 2 && b[0] == 0x50.toByte() && b[1] == 0x4B.toByte()
        when {
            isRar || (!isZip && file.lower.endsWith(".rar")) -> readRar(b, file.name)
            isZip || file.lower.endsWith(".zip") -> readZip(b, file.name)
            else -> throw IllegalArgumentException("Only .zip and .rar archives are supported")
        }
    }

    private fun wanted(name: String): Boolean =
        !ArchiveClassifier.isJunk(name) && (ArchiveClassifier.IMG_RE.containsMatchIn(name) || ArchiveClassifier.AUDIO_RE.containsMatchIn(name) || ArchiveClassifier.VIDEO_RE.containsMatchIn(name))

    private fun readZip(bytes: ByteArray, archive: String): List<ArchiveEntry> {
        val out = ArrayList<ArchiveEntry>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zis ->
            var e = zis.nextEntry
            while (e != null) {
                if (!e.isDirectory && wanted(e.name)) {
                    val bos = ByteArrayOutputStream(maxOf(1024, e.size.toInt().coerceAtLeast(0)))
                    zis.copyTo(bos)
                    out.add(ArchiveEntry(e.name, bos.toByteArray(), archive))
                }
                zis.closeEntry()
                e = zis.nextEntry
            }
        }
        if (out.isEmpty() && bytes.size < 22) throw IllegalArgumentException("Not a valid ZIP file")
        return out
    }

    private fun readRar(bytes: ByteArray, archive: String): List<ArchiveEntry> {
        val out = ArrayList<ArchiveEntry>()
        Archive(ByteArrayInputStream(bytes)).use { rar ->
            if (rar.isEncrypted) throw IllegalArgumentException("Encrypted RAR archives are not supported")
            var fh = rar.nextFileHeader()
            while (fh != null) {
                val name = (fh.fileName ?: "").replace('\\', '/')
                if (!fh.isDirectory && wanted(name)) {
                    val bos = ByteArrayOutputStream()
                    rar.extractFile(fh, bos)
                    out.add(ArchiveEntry(name, bos.toByteArray(), archive))
                }
                fh = rar.nextFileHeader()
            }
        }
        return out
    }
}
