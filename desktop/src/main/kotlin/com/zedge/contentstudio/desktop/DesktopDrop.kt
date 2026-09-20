package com.zedge.contentstudio.desktop

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.awtTransferable
import java.awt.datatransfer.DataFlavor
import java.io.File

/** Drop files from Explorer anywhere on the window -> they land in the Upload page. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalComposeUiApi::class)
@Composable
fun Modifier.fileDropTarget(onFiles: (List<File>) -> Unit): Modifier {
    val cb = rememberUpdatedState(onFiles)
    val target = remember {
        object : DragAndDropTarget {
            override fun onDrop(event: DragAndDropEvent): Boolean {
                val t = runCatching { event.awtTransferable }.getOrNull() ?: return false
                if (!t.isDataFlavorSupported(DataFlavor.javaFileListFlavor)) return false
                @Suppress("UNCHECKED_CAST")
                val files = (t.getTransferData(DataFlavor.javaFileListFlavor) as? List<File>).orEmpty().filter { it.isFile }
                if (files.isEmpty()) return false
                cb.value(files)
                return true
            }
        }
    }
    return this.dragAndDropTarget(shouldStartDragAndDrop = { true }, target = target)
}
