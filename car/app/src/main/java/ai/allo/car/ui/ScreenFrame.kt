package ai.allo.car.ui

import androidx.compose.foundation.Image
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
    Surface(modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val compact = maxWidth < 600.dp
            val short = maxHeight < 400.dp
            val padding = if (short) 12.dp else if (compact) 16.dp else 28.dp
            Column(Modifier.fillMaxSize().padding(padding)) {
                if (compact) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        AlloWordmark(Modifier.width(if (short) 84.dp else 110.dp).height(if (short) 38.dp else 50.dp))
                        Text(title, style = if (short) MaterialTheme.typography.labelLarge else MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Text(status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(bottom = if (short) 4.dp else 12.dp), maxLines = if (short) 1 else 2, overflow = TextOverflow.Ellipsis)
                } else {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                        AlloWordmark(Modifier.width(if (short) 94.dp else 132.dp).height(if (short) 42.dp else 60.dp))
                        Text(title, style = if (short) MaterialTheme.typography.labelLarge else MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(status, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.widthIn(max = 340.dp), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Spacer(Modifier.height(if (short) 8.dp else 16.dp))
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
        val compact = maxWidth < 720.dp
        val artSize = if (compact) minOf(240.dp, maxWidth, maxHeight * .4f)
            else minOf(240.dp, (maxWidth - 32.dp) / 2, maxHeight)
        if (compact) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)) {
                art(artSize)
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp), content = details)
                Spacer(Modifier.height(8.dp))
            }
        } else {
            // Keep the character in the visible viewport even when the detail pane is tall.
            Row(Modifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(32.dp)) {
                Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) { art(artSize) }
                Column(Modifier.weight(1f).fillMaxHeight().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically), content = details)
            }
        }
    }
}

@Composable
fun ScreenAction(label: String, onClick: () -> Unit, enabled: Boolean = true, secondary: Boolean = false) {
    val modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp)
    if (secondary) {
        OutlinedButton(onClick, modifier = modifier, enabled = enabled) {
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    } else {
        Button(onClick, modifier = modifier, enabled = enabled) {
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}
