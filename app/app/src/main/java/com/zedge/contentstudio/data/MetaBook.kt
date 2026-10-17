package com.zedge.contentstudio.data

import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.Json
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject

/**
 * v22 - AI metadata sidecar JSON (same behaviour as the web panel).
 * A .json picked together with media files is parsed here; every uploaded file whose
 * name matches an entry gets title/tags/category/description saved straight into Firebase,
 * so generator.yml skips Gemini metadata for it.
 */
object MetaBook {
    val RT_CATS = listOf("LATIN","MESSAGE_TONES","OTHER","POP","RNB_SOUL","REGGAE","RELIGIOUS","ROCK","SAYINGS","ALTERNATIVE","ANIMALS","BLUES","BOLLYWOOD","CHILDREN","CLASSICAL","SOUND_EFFECTS","WORLD","COMEDY","CONTACT_RINGTONES","COUNTRY","DANCE","ELECTRONICA","GAMES","HIP_HOP","HOLIDAYS","JAZZ")
    val IMG_CATS = listOf("ANIMALS","ANIME","CARS_N_VEHICLES","COMICS","DESIGNS","DRAWINGS","ENTERTAINMENT","FUNNY","GAMES","HOLIDAYS","LOVE","MUSIC","NATURE","OTHER","PATTERNS","PEOPLE","SAYINGS","SPACE","SPIRITUAL","SPORTS","TECHNOLOGY")
    private val POLICY = Regex("(https?://|www\\.|\\.com\\b|\\.net\\b|follow (me|us)|subscribe|download (now|free|link)|telegram|whatsapp|instagram|tiktok|youtube|discount|promo code|porn|xxx|nude|naked|\\bsex\\b|nsfw|erotic|hentai|kill yourself|terrorist|nazi)", RegexOption.IGNORE_CASE)

    data class Entry(val file: String, val title: String, val tags: String, val category: String, val description: String, val keys: MutableSet<String> = LinkedHashSet(), var used: Int = 0)
    private val list = ArrayList<Entry>()
    private val dups = LinkedHashSet<String>()
    fun pathNorm(p: String): String = p.replace('\\', '/').trimStart('.', '/').lowercase()
        .replace(Regex("\\.[a-z0-9]{2,5}$"), "").replace(Regex("[^a-z0-9]+"), "_").trim('_')
    data class State(val source: String = "", val count: Int = 0, val applied: Int = 0, val missed: Int = 0, val problems: List<String> = emptyList())

    private val entries = LinkedHashMap<String, Entry>()
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    fun norm(name: String): String = name.substringAfterLast('/').substringAfterLast('\\').lowercase()
        .replace(Regex("\\.[a-z0-9]{2,5}$"), "").replace(Regex("[^a-z0-9]+"), "_").trim('_')

    private fun tags(v: Any?): List<String> {
        val raw: List<String> = when (v) {
            is JSONArray -> (0 until v.length()).map { v.optString(it) }
            null -> emptyList()
            else -> v.toString().split(',', ';', '\n', '|')
        }
        val out = LinkedHashSet<String>()
        for (t in raw) {
            val x = t.trim().removePrefix("#").replace(Regex("\\s+"), " ").lowercase()
            if (x.isEmpty() || x.length > 30) continue
            out.add(x); if (out.size >= 10) break
        }
        return out.toList()
    }

    /** Parses JSON text; returns (added, problems). Accepts an array, {files:[..]}, {items:[..]} or {"file.mp3":{..}}. */
    fun load(text: String, source: String): Pair<Int, List<String>> {
        val parsed: Any? = Json.parse(text)
        val arr: JSONArray = when {
            parsed is JSONArray -> parsed
            parsed is JSONObject && parsed.opt("files") is JSONArray -> parsed.getJSONArray("files")
            parsed is JSONObject && parsed.opt("items") is JSONArray -> parsed.getJSONArray("items")
            parsed is JSONObject -> JSONArray().also { out -> for (k in Json.keys(parsed)) { val v = parsed.optJSONObject(k) ?: JSONObject(); v.put("file", k); out.put(v) } }
            else -> throw IllegalArgumentException("JSON must be an array of {file,title,tags,category,description}")
        }
        val problems = ArrayList<String>()
        var added = 0
        for (i in 0 until arr.length()) {
            val row = arr.optJSONObject(i) ?: continue
            val file = listOf("file", "filename", "fileName", "name").map { row.optString(it, "") }.firstOrNull { it.isNotBlank() }
            if (file == null) { problems.add("#${i + 1}: missing \"file\""); continue }
            val title = row.optString("title", "").trim().replace(Regex("\\s+"), " ").take(30)
            val tg = tags(row.opt("tags"))
            val category = row.optString("category", "").trim().uppercase().replace(Regex("[\\s&\\-]+"), "_").replace(Regex("[^A-Z_]"), "")
            val description = row.optString("description", "").trim().replace(Regex("\\s+"), " ").take(200)
            val issues = ArrayList<String>()
            if (title.isEmpty()) issues.add("title missing")
            if (tg.size < 2) issues.add("needs 2-10 tags")
            if (description.isEmpty()) issues.add("description missing")
            if (POLICY.containsMatchIn("$title ${tg.joinToString(" ")} $description")) issues.add("Zedge policy: promo/link/adult wording")
            if (issues.isNotEmpty()) { problems.add("$file: ${issues.joinToString(", ")}"); continue }
            val ent = Entry(file, title, tg.joinToString(", "), category, description)
            val k = norm(file); ent.keys.add(k)
            val fp = file.replace('\\', '/')
            if (fp.contains('/')) { ent.keys.add(pathNorm(fp)); fp.split('/').dropLast(1).lastOrNull()?.let { ent.keys.add(norm("$it.x")) } }
            val folder = row.optString("folder", row.optString("dir", row.optString("directory", "")))
            if (folder.isNotBlank()) ent.keys.add(norm(folder.trimEnd('/', '\\') + ".x"))
            if (entries.containsKey(k)) dups.add(k) else entries[k] = ent
            list.add(ent)
            added++
        }
        if (dups.isNotEmpty()) problems.add("${dups.size} file name(s) repeated in JSON (e.g. \"${dups.first()}\") - matched by folder name / order instead")
        _state.value = _state.value.copy(source = source, count = list.size, problems = _state.value.problems + problems)
        return added to problems
    }

    fun clear() { entries.clear(); list.clear(); dups.clear(); _state.value = State() }

    /** Metadata fields for a queue record. Falls back to blank fields (generator.yml fills them). */
    fun fieldsFor(names: List<String?>, contentType: String?): JSONObject {
        val blank = Json.obj("title" to "", "tags" to "", "category" to "", "description" to "")
        if (entries.isEmpty()) return blank
        val cands = names.filterNotNull().filter { it.isNotBlank() }
        var e: Entry? = cands.firstNotNullOfOrNull { n -> val k = norm(n); if (k in dups) null else entries[k] }
        if (e == null) for (n in cands) {
            val fp = n.replace('\\', '/'); val pk = pathNorm(fp)
            val dir = if (fp.contains('/')) norm(fp.split('/').dropLast(1).last() + ".x") else ""
            e = list.firstOrNull { it.used == 0 && (pk in it.keys || (dir.isNotEmpty() && dir in it.keys)) }
            if (e == null && dir.length >= 3) e = list.firstOrNull { x -> x.used == 0 && x.keys.any { k -> k.length >= 3 && (k.startsWith(dir) || dir.startsWith(k)) } }
            if (e != null) break
        }
        if (e == null) for (n in cands) { val k = norm(n); if (k in dups) { e = list.firstOrNull { it.used == 0 && k in it.keys }; if (e != null) break } }
        if (e == null && dups.isNotEmpty() && list.isNotEmpty() && list.all { norm(it.file) in dups }) e = list.firstOrNull { it.used == 0 }
        if (e == null) { _state.value = _state.value.copy(missed = _state.value.missed + 1); return blank }
        e.used++
        val list = if (contentType == "RINGTONE") RT_CATS else IMG_CATS
        val category = if (e.category in list) e.category else "OTHER"
        val probs = if (category != e.category) _state.value.problems + "${e.file}: category \"${e.category.ifEmpty { "(empty)" }}\" not valid for $contentType -> OTHER" else _state.value.problems
        _state.value = _state.value.copy(applied = _state.value.applied + 1, problems = probs)
        return Json.obj(
            "title" to e.title, "tags" to e.tags, "category" to category, "description" to e.description,
            "metadataSource" to "json", "metadataFile" to _state.value.source, "metadataAppliedAt" to System.currentTimeMillis()
        )
    }

    fun promptText(): String = listOf(
        "I will give you media files for Zedge (ringtones / wallpapers / live wallpapers / charging animations).",
        "For EACH file produce metadata and return ONE JSON array only (no prose, no markdown) in exactly this shape:",
        "[",
        "  { \"file\": \"exact_file_name.mp3\", \"title\": \"Catchy Title (max 30 chars)\", \"tags\": [\"tag1\",\"tag2\",\"tag3\",\"tag4\",\"tag5\"], \"category\": \"CATEGORY\", \"description\": \"1-2 natural sentences describing the content\" }",
        "]",
        "Rules (Zedge Content Policy - mandatory):",
        "- \"file\" must be the exact file name I upload (extension included) and UNIQUE per entry - never reuse the same file name. If files sit in sub-folders, use the relative path (e.g. 01_basalt_cross/wallpaper.jpg) or add a \"folder\" field. For a wallpaper set (24H / Dual / Battery) use the FIRST image's file name.",
        "- title: original, descriptive, max 30 characters, no emojis, no ALL CAPS, no artist/brand/movie/game/character names, no copyrighted names.",
        "- tags: 2 to 10 lowercase tags, each 1-3 words, accurate to the content only. No promo words, no links, no @handles, no unrelated trending words.",
        "- description: accurate, 1-2 sentences, no links, no social handles, no 'download/subscribe/follow', no pricing.",
        "- No sexual, suggestive, violent, hateful, illegal or misleading wording anywhere.",
        "- category for RINGTONES must be one of: ${RT_CATS.filter { it != "OTHER" }.joinToString(", ")}",
        "- category for WALLPAPERS / LIVE WALLPAPERS / CHARGING ANIMATIONS must be one of: ${IMG_CATS.filter { it != "OTHER" }.joinToString(", ")}",
        "Save the result as metadata.json.",
    ).joinToString("\n")
}
