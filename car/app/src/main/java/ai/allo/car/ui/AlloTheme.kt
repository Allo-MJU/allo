package ai.allo.car.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * 시스템 주야간 설정에 따른 차량 공통 테마. 기존 먹색 야간과 흰색·녹색 주간을 지원한다.
 * 실제 창 크기에 맞춘 화면 배치와 함께 사용하며 기기 시인성 검증은 별도다.
 */
object AlloColors {
    val Night = Color(0xFF181C1E)       // 차량 먹색
    val NightRaised = Color(0xFF282F32) // 카드
    val Egg = Color(0xFFFCCC44)         // 강조: 알 노랑
    val EggDeep = Color(0xFFB4D99B)
    val Mist = Color(0xFFF4F8F5)        // 본문
    val MistDim = Color(0xFFC3CDC8)     // 보조 문구
    val Track = Color(0xFF596A61)       // 진행바 바탕
}

private val darkColors = darkColorScheme(
    primary = AlloColors.Egg,
    onPrimary = AlloColors.Night,
    secondary = AlloColors.EggDeep,
    onSecondary = AlloColors.Night,
    primaryContainer = Color(0xFF514419),
    onPrimaryContainer = Color(0xFFFFECA6),
    secondaryContainer = Color(0xFF34483B),
    onSecondaryContainer = Color(0xFFDCEFD4),
    tertiary = AlloColors.EggDeep,
    onTertiary = AlloColors.Night,
    tertiaryContainer = Color(0xFF34483B),
    onTertiaryContainer = Color(0xFFDCEFD4),
    background = AlloColors.Night,
    onBackground = AlloColors.Mist,
    surface = AlloColors.Night,
    onSurface = AlloColors.Mist,
    surfaceVariant = AlloColors.NightRaised,
    onSurfaceVariant = AlloColors.MistDim,
    surfaceContainer = AlloColors.NightRaised,
    surfaceContainerHigh = Color(0xFF30393C),
    surfaceContainerHighest = Color(0xFF384347),
    surfaceContainerLow = Color(0xFF202729),
    surfaceContainerLowest = Color(0xFF111618),
    surfaceBright = Color(0xFF384347),
    surfaceDim = AlloColors.Night,
    surfaceTint = AlloColors.EggDeep,
    outline = AlloColors.Track,
    outlineVariant = Color(0xFF3F4D46),
)

/** White surfaces with green actions; semantic text roles remain readable on every card layer. */
private val lightColors = lightColorScheme(
    primary = Color(0xFF28633F),
    onPrimary = Color.White,
    secondary = Color(0xFF4F6942),
    onSecondary = Color.White,
    primaryContainer = Color(0xFFD8EEDC),
    onPrimaryContainer = Color(0xFF102D1B),
    secondaryContainer = Color(0xFFE1ECD9),
    onSecondaryContainer = Color(0xFF20341A),
    tertiary = Color(0xFF456B55),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFD9EDDF),
    onTertiaryContainer = Color(0xFF183426),
    background = Color.White,
    onBackground = Color(0xFF1C271F),
    surface = Color.White,
    onSurface = Color(0xFF1C271F),
    surfaceVariant = Color(0xFFE6EDE3),
    onSurfaceVariant = Color(0xFF4B594D),
    surfaceContainer = Color(0xFFF0F5ED),
    surfaceContainerHigh = Color(0xFFE8F0E5),
    surfaceContainerHighest = Color(0xFFDEE9DA),
    surfaceContainerLow = Color(0xFFF6F9F3),
    surfaceContainerLowest = Color.White,
    surfaceBright = Color.White,
    surfaceDim = Color(0xFFDCE5D8),
    surfaceTint = Color(0xFF28633F),
    outline = Color(0xFF667662),
    outlineVariant = Color(0xFFC4D0BE),
)

private val type = Typography(
    displayLarge = TextStyle(fontSize = 88.sp, fontWeight = FontWeight.Bold, lineHeight = 100.sp),
    displayMedium = TextStyle(fontSize = 64.sp, fontWeight = FontWeight.Bold, lineHeight = 76.sp, letterSpacing = 4.sp),
    displaySmall = TextStyle(fontSize = 48.sp, fontWeight = FontWeight.SemiBold, lineHeight = 60.sp),
    headlineLarge = TextStyle(fontSize = 40.sp, fontWeight = FontWeight.SemiBold, lineHeight = 52.sp),
    headlineMedium = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Medium, lineHeight = 44.sp),
    titleLarge = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Normal, lineHeight = 40.sp),
    bodyLarge = TextStyle(fontSize = 24.sp, lineHeight = 34.sp),
    bodyMedium = TextStyle(fontSize = 18.sp, lineHeight = 26.sp),
    labelLarge = TextStyle(fontSize = 22.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold),
)

internal fun alloColorScheme(darkTheme: Boolean) = if (darkTheme) darkColors else lightColors

@Composable
fun AlloTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) =
    MaterialTheme(colorScheme = alloColorScheme(darkTheme), typography = type, content = content)
