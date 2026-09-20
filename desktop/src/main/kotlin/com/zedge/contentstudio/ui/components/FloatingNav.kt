package com.zedge.contentstudio.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.zedge.contentstudio.Page
import com.zedge.contentstudio.ui.theme.BrandOnNavActive
import com.zedge.contentstudio.ui.theme.BrandNavActive
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.LaunchedEffect
import com.zedge.contentstudio.ui.theme.BrandNavBg

fun pageIcon(p: Page): ImageVector = when (p) {
    Page.HOME -> Icons.Filled.Dashboard
    Page.UPLOAD -> Icons.Filled.CloudUpload
    Page.SCHEDULE -> Icons.Filled.CalendarMonth
    Page.PINS -> Icons.Filled.PushPin
    Page.DISTRIBUTE -> Icons.Filled.Hub
    Page.GITHUB -> Icons.Filled.Code
    Page.VPN -> Icons.Filled.VpnKey
    Page.THEME -> Icons.Filled.Palette // v30.4: THEME page added in v30, branch was missing
}

/**
 * Floating pill navigation. The selected tab expands into a yellow capsule that shows its label;
 * the others collapse to icons. All transitions are spring-animated.
 */
@Composable
fun FloatingNavBar(current: Page, onSelect: (Page) -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().navigationBarsPadding().padding(start = 14.dp, end = 14.dp, top = 6.dp, bottom = 12.dp)) {
        Surface(
            shape = CircleShape,
            color = (BrandNavBg ?: MaterialTheme.colorScheme.surfaceContainerHigh).copy(alpha = 0.82f), // v27.8 "sidebar" element colour
            border = BorderStroke(1.dp, glassLine()),
            tonalElevation = 0.dp,
            shadowElevation = 18.dp,
            modifier = Modifier.fillMaxWidth(),
        ) {
            // v25: 7 tabs no longer fit on narrow phones (<= 360dp) - the last one (VPN) was clipped
            // outside the pill and could not be tapped. The row now scrolls horizontally when needed
            // (still SpaceBetween when everything fits) and auto-scrolls the selected tab into view.
            val scroll = rememberScrollState()
            LaunchedEffect(current) {
                val idx = Page.entries.indexOf(current)
                if (scroll.maxValue > 0 && idx >= 0) {
                    val target = if (idx >= Page.entries.size / 2) scroll.maxValue else 0
                    scroll.animateScrollTo(target)
                }
            }
            BoxWithConstraints(Modifier.fillMaxWidth()) {
            val minW = maxWidth
            Row(
                Modifier
                    .horizontalScroll(scroll)
                    .widthIn(min = minW)
                    .padding(horizontal = 6.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Page.entries.forEach { p ->
                    val selected = p == current
                    val bg by animateColorAsState(if (selected) BrandNavActive else Color.Transparent, tween(280), label = "bg")
                    val tint by animateColorAsState(if (selected) BrandOnNavActive else MaterialTheme.colorScheme.onSurfaceVariant, tween(280), label = "tint")
                    val scale by animateFloatAsState(if (selected) 1.08f else 0.92f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow), label = "scale")
                    Row(
                        Modifier
                            .clip(CircleShape)
                            .background(bg)
                            .clickable { onSelect(p) }
                            .animateContentSize(spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMediumLow))
                            .padding(horizontal = if (selected) 12.dp else 8.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            pageIcon(p), contentDescription = p.short,
                            modifier = Modifier.size(21.dp).graphicsLayer { scaleX = scale; scaleY = scale },
                            tint = tint,
                        )
                        AnimatedVisibility(
                            visible = selected,
                            enter = fadeIn(tween(200, delayMillis = 80)) + expandHorizontally(),
                            exit = fadeOut(tween(120)) + shrinkHorizontally(),
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Spacer(Modifier.width(7.dp))
                                Text(p.short, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = BrandOnNavActive, maxLines = 1, softWrap = false)
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
