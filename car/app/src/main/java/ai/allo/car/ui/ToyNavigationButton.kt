package ai.allo.car.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Figma Components / v2 Toy / Button (48:109), Large size for vehicle touch. */
@Composable
internal fun ToyNavigationButton(label: String, selected: Boolean, dark: Boolean, onClick: () -> Unit) {
    ToyButton(label, onClick, primary = selected, dark = dark, selected = selected)
}

/** Shared action surface: navigation and ordinary actions use the same Toy design tokens. */
@Composable
internal fun ToyButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    primary: Boolean = false, enabled: Boolean = true, selected: Boolean? = null,
    dark: Boolean = MaterialTheme.colorScheme.surface.luminance() < .35f) {
    val interaction = remember { MutableInteractionSource() }
    val held by interaction.collectIsPressedAsState()
    val pressed = enabled && held
    val face = when { !enabled -> if (dark) Color(0xFF25362B) else Color(0xFFDDE6DE); primary -> Color(0xFF42664C); dark -> Color(0xFF35483A); else -> Color(0xFFF4EFDF) }
    val lip = when { !enabled -> if (dark) Color(0xFF25362B) else Color(0xFFDDE6DE); primary -> Color(0xFF304D39); dark -> Color(0xFF25362B); else -> Color(0xFFB3B8A2) }
    val ink = when { !enabled -> if (dark) Color(0xFFA9BFB2) else Color(0xFFB3B8A2); primary -> Color(0xFFFFF9E9); dark -> Color(0xFFF4F8F5); else -> Color(0xFF42664C) }
    val shape = RoundedCornerShape(24.dp)
    // The outer hit area stays 72dp in both states; only the face moves down 1dp.
    val input = if (selected != null) Modifier.selectable(selected, enabled = enabled,
        interactionSource = interaction, indication = null, role = Role.Tab, onClick = onClick)
        else Modifier.clickable(enabled = enabled, interactionSource = interaction,
            indication = null, role = Role.Button, onClick = onClick)
    Box(modifier.height(72.dp).width(IntrinsicSize.Max).then(input),
        contentAlignment = Alignment.TopCenter) {
        if (enabled) Box(Modifier.fillMaxWidth().height(70.dp).offset(y = 2.dp).background(lip, shape))
        Box(Modifier.fillMaxWidth().offset(y = if (!enabled) 2.dp else if (pressed) 1.dp else 0.dp).height(70.dp)
            .clip(shape).background(face).drawWithCache {
                val top = Brush.verticalGradient(listOf(Color.White.copy(alpha = .10f), Color.Transparent), 0f, 5.dp.toPx())
                val bottom = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .06f)), size.height - 8.dp.toPx(), size.height)
                onDrawWithContent {
                    drawContent()
                    if (enabled) { drawRect(top); drawRect(bottom) }
                }
            }.padding(horizontal = 32.dp), contentAlignment = Alignment.Center) {
            Text(label, color = ink, fontWeight = FontWeight.Bold, fontSize = 20.sp,
                lineHeight = 26.sp, letterSpacing = 0.sp, maxLines = 2, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}
