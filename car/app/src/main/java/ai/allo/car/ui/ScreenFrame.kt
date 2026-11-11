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
    Surface(modifier.fillMaxSize(), color = AlloColors.Night) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val compact = maxWidth < 600.dp
            Column(Modifier.fillMaxSize().padding(if (compact) 16.dp else 28.dp)) {
                if (compact) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        AlloWordmark(Modifier.width(84.dp).height(50.dp))
                        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    }
                    Text(status, style = MaterialTheme.typography.bodyMedium, color = AlloColors.MistDim,
                        modifier = Modifier.padding(bottom = 12.dp))
                } else {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                        AlloWordmark(Modifier.width(100.dp).height(60.dp))
                        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                        Text(status, style = MaterialTheme.typography.bodyMedium, color = AlloColors.MistDim,
                            modifier = Modifier.widthIn(max = 340.dp), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                HorizontalDivider(color = AlloColors.Track)
                Spacer(Modifier.height(16.dp))
                content()
            }
        }
    }
}

@Composable
fun AlloWordmark(modifier: Modifier = Modifier) {
    Image(painterResource(R.drawable.allo_wordmark), contentDescription = "ALLO",
        modifier = modifier, contentScale = ContentScale.Fit)
}

/** A scrollable layout that uses actual app-window width, including split/compact windows. */
@Composable
fun ScreenColumns(
    art: @Composable () -> Unit,
    details: @Composable ColumnScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val compact = maxWidth < 720.dp
        if (compact) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp)) {
                art()
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp), content = details)
                Spacer(Modifier.height(8.dp))
            }
        } else {
            // Keep the character in the visible viewport even when the detail pane is tall.
            Row(Modifier.fillMaxSize(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(32.dp)) {
                Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) { art() }
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
