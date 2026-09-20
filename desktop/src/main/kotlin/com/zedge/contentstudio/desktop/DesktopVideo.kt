package com.zedge.contentstudio.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.SwingPanel
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uk.co.caprica.vlcj.factory.discovery.NativeDiscovery
import uk.co.caprica.vlcj.player.component.EmbeddedMediaPlayerComponent
import java.awt.Desktop
import java.net.URI

/** VLC (libvlc) is used for inline playback when installed; otherwise a poster that opens the system player. */
object VlcSupport {
    val available: Boolean by lazy { runCatching { NativeDiscovery().discover() }.getOrDefault(false) }
}

@Composable
fun DesktopVideoSurface(url: String, modifier: Modifier = Modifier, muted: Boolean = true, loop: Boolean = true) {
    val vlc = remember { VlcSupport.available }
    if (vlc) {
        val component = remember(url) { EmbeddedMediaPlayerComponent() }
        DisposableEffect(component) { onDispose { runCatching { component.release() } } }
        LaunchedEffect(url) {
            runCatching {
                val mp = component.mediaPlayer()
                mp.audio().setMute(muted)
                mp.controls().setRepeat(loop)
                mp.media().play(url)
            }
        }
        Box(modifier.background(Color.Black)) {
            SwingPanel(background = Color.Black, factory = { component }, modifier = Modifier.fillMaxSize())
        }
    } else {
        Box(
            modifier.background(Brush.verticalGradient(listOf(Color(0xFF1B1F3A), Color(0xFF0B0E1C))))
                .clickable { runCatching { Desktop.getDesktop().browse(URI(url)) } },
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.PlayCircle, null, Modifier.size(56.dp), tint = Color.White.copy(alpha = 0.92f))
                Spacer(Modifier.height(8.dp))
                Text("Open video", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Text("Install VLC for inline preview", color = Color.White.copy(alpha = 0.6f), fontSize = 9.sp, textAlign = TextAlign.Center)
            }
        }
    }
}
