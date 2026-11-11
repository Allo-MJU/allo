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
 * 차 화면 공통 테마. #92 차량 화면 설계의 먹색·본문·강조색을 사용한다.
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

private val colors = darkColorScheme(
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

@Composable
fun AlloTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = colors, typography = type, content = content)
