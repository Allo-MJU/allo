package ai.allo.car.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * 차 화면 공통 테마. 임시 톤이다 — D 아트·브랜드 색이 정해지면 여기만 바꾼다.
 * 차량 화면은 2560px 로 넓고 멀리서 보므로 글자를 폰보다 크게 잡는다.
 */
object AlloColors {
    val Night = Color(0xFF12142B)       // 배경: 밤하늘 남색
    val NightRaised = Color(0xFF1D2142) // 카드
    val Egg = Color(0xFFFFC857)         // 강조: 알 노랑
    val EggDeep = Color(0xFFF29E4C)
    val Mist = Color(0xFFE8E9F3)        // 본문
    val MistDim = Color(0xFFA9ACC6)     // 보조 문구
    val Track = Color(0xFF2E3360)       // 진행바 바탕
}

private val colors = darkColorScheme(
    primary = AlloColors.Egg,
    onPrimary = AlloColors.Night,
    secondary = AlloColors.EggDeep,
    background = AlloColors.Night,
    onBackground = AlloColors.Mist,
    surface = AlloColors.Night,
    onSurface = AlloColors.Mist,
    surfaceVariant = AlloColors.NightRaised,
    onSurfaceVariant = AlloColors.MistDim,
)

private val type = Typography(
    displayLarge = TextStyle(fontSize = 88.sp, fontWeight = FontWeight.Bold, lineHeight = 100.sp),
    displayMedium = TextStyle(fontSize = 64.sp, fontWeight = FontWeight.Bold, lineHeight = 76.sp, letterSpacing = 4.sp),
    displaySmall = TextStyle(fontSize = 48.sp, fontWeight = FontWeight.SemiBold, lineHeight = 60.sp),
    headlineLarge = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.SemiBold, lineHeight = 52.sp),
    headlineMedium = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Medium, lineHeight = 44.sp),
    titleLarge = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Normal, lineHeight = 40.sp),
    bodyLarge = TextStyle(fontSize = 24.sp, lineHeight = 34.sp),
    labelLarge = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.SemiBold),
)

@Composable
fun AlloTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = colors, typography = type, content = content)
