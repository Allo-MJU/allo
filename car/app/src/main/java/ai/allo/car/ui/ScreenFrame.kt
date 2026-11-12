package ai.allo.car.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ai.allo.car.R

/** Shared app-window frame. System navigation and vehicle controls remain outside this surface. */
@Composable
fun ScreenFrame(
    title: String,
    status: String,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val short = maxHeight < 400.dp
            val compact = maxWidth < 600.dp
            val padding = if (short) 12.dp else if (compact) 20.dp else 28.dp
            Column(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(if (short) 12.dp else 24.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    AlloWordmark(Modifier.width(if (compact) 100.dp else 140.dp).height(if (short) 44.dp else 64.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(title, style = if (compact) MaterialTheme.typography.titleLarge else MaterialTheme.typography.headlineMedium,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (compact) Text(status, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    if (!compact) Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(20.dp)) {
                        Text(status, Modifier.widthIn(max = 300.dp).padding(horizontal = 20.dp, vertical = 12.dp),
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSecondaryContainer,
                            maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                content()
            }
        }
    }
}

@Composable
fun AlloWordmark(modifier: Modifier = Modifier) {
    Image(painterResource(R.drawable.allo_logo), contentDescription = "ALLO",
        modifier = modifier, contentScale = ContentScale.Fit)
}

/** A scrollable layout that uses actual app-window width, including split/compact windows. */
@Composable
fun ScreenColumns(
    art: @Composable (androidx.compose.ui.unit.Dp) -> Unit,
    details: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val layout = ReviewWindowLayout.forContent(maxWidth.value, maxHeight.value)
        val artSize = layout.artSizeDp.dp
        if (layout.stacked) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Surface(Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.surfaceContainerLow, shape = RoundedCornerShape(28.dp)) {
                    Box(Modifier.padding(20.dp), contentAlignment = Alignment.Center) { art(artSize) }
                }
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp), content = details)
                Spacer(Modifier.height(12.dp))
            }
        } else {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                Surface(Modifier.weight(.36f).fillMaxHeight(), color = MaterialTheme.colorScheme.surfaceContainerLow,
                    shape = RoundedCornerShape(32.dp)) {
                    Box(Modifier.padding(16.dp), contentAlignment = Alignment.Center) { art(artSize) }
                }
                Column(Modifier.weight(.64f).fillMaxHeight().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(24.dp), content = details)
            }
        }
    }
}

@Composable
fun ScreenAction(label: String, onClick: () -> Unit, enabled: Boolean = true, secondary: Boolean = false) {
    val modifier = Modifier.fillMaxWidth().heightIn(min = 72.dp)
    if (secondary) {
        OutlinedButton(onClick, modifier = modifier, enabled = enabled) {
            Text(label, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(vertical = 8.dp))
        }
    } else {
        Button(onClick, modifier = modifier, enabled = enabled) {
            Text(label, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(vertical = 8.dp))
        }
    }
}
