package com.zedge.contentstudio.desktop

import android.content.Storage
import android.net.Uri
import java.awt.Window
import java.io.File
import javax.swing.JFileChooser
import javax.swing.SwingUtilities
import javax.swing.filechooser.FileNameExtensionFilter

/** Native Windows file dialogs used by every "pick file(s)" action in the app. Remembers the last folder. */
object DesktopPickers {
    private val prefs by lazy { Storage.prefs("desktop_ui") }

    private fun extensionsFor(mimes: Array<String>): List<String> {
        val out = LinkedHashSet<String>()
        for (m in mimes) {
            when {
                m == "*/*" || m == "application/octet-stream" -> return emptyList()
                m == "image/*" -> out += listOf("jpg", "jpeg", "png", "webp")
                m.startsWith("image/") -> out += m.substringAfter('/').replace("jpeg", "jpg")
                m == "audio/mpeg" || m == "audio/*" -> out += "mp3"
                m.startsWith("video/") -> out += listOf("mp4", "mov")
                m == "application/json" -> out += "json"
                m == "application/zip" || m == "application/x-zip-compressed" -> out += "zip"
                m == "application/vnd.rar" || m == "application/x-rar-compressed" -> out += "rar"
                m == "text/plain" -> out += listOf("txt", "ovpn", "conf", "json")
            }
        }
        return out.toList()
    }

    fun pick(mimes: Array<String>, multi: Boolean, onResult: (List<Uri>) -> Unit) {
        SwingUtilities.invokeLater {
            val start = prefs.getString("lastDir", null)?.let(::File)?.takeIf { it.isDirectory } ?: File(System.getProperty("user.home"))
            val chooser = JFileChooser(start)
            chooser.isMultiSelectionEnabled = multi
            chooser.fileSelectionMode = JFileChooser.FILES_ONLY
            chooser.dialogTitle = if (multi) "Select files" else "Select a file"
            val exts = extensionsFor(mimes)
            if (exts.isNotEmpty()) {
                val f = FileNameExtensionFilter(exts.joinToString(", ") { "*." + it }, *exts.toTypedArray())
                chooser.addChoosableFileFilter(f)
                chooser.fileFilter = f
            }
            chooser.isAcceptAllFileFilterUsed = true
            val owner = Window.getWindows().firstOrNull { it.isActive } ?: Window.getWindows().firstOrNull { it.isShowing }
            val r = chooser.showOpenDialog(owner)
            if (r != JFileChooser.APPROVE_OPTION) { onResult(emptyList()); return@invokeLater }
            val files = if (multi) chooser.selectedFiles.toList() else listOfNotNull(chooser.selectedFile)
            files.firstOrNull()?.parentFile?.let { prefs.edit().putString("lastDir", it.absolutePath).apply() }
            onResult(files.filter { it.isFile }.map { Uri.fromFile(it) })
        }
    }
}
