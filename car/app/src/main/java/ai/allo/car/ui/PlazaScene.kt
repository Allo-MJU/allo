package ai.allo.car.ui

import ai.allo.car.R
import ai.allo.car.dialogue.PlazaDialogue
import ai.allo.car.model.GameState
import ai.allo.car.model.PlazaPopulation
import ai.allo.car.voice.DialogueVoice
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.zIndex
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.isActive

/**
 * Parked-only local presentation. Tapping never changes ownership or selected companion.
 * The garden is full-bleed: [topInset] is what the caller overlays on its top edge (system bar and
 * navigation), [bottomInset] the system bar under the dock. Friends and bubbles stay clear of both.
 */
@Composable
internal fun PlazaScene(game: GameState, connected: Boolean, sceneHeightOverride: androidx.compose.ui.unit.Dp? = null, selectedResidents: List<String>? = null,
    topInset: androidx.compose.ui.unit.Dp = 0.dp, bottomInset: androidx.compose.ui.unit.Dp = 0.dp,
    dock: @Composable () -> Unit = {}) {
    val catalog = rememberSpeciesCatalog()
    val dialogue = remember { PlazaDialogue() }
    val available = PlazaPopulation.residents(game).filter { it in SuppliedCharacters.ids && catalog[it] != null }
    val residents = selectedResidents?.let { PlazaPopulation.selected(available, it) } ?: available
    var page by rememberSaveable(residents) { mutableIntStateOf(0) }
    val visible = PlazaPopulation.page(residents, page)
    var selected by remember(residents, page, connected) { mutableStateOf<String?>(null) }
    var line by remember(residents, page, connected) { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val voice = remember(context, lifecycleOwner) { DialogueVoice(context) }
    val speech by voice.state.collectAsState()
    val latestResidents by rememberUpdatedState(visible)
    val latestConnected by rememberUpdatedState(connected)
    DisposableEffect(voice, lifecycleOwner) {
        voice.start()
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_PAUSE) voice.stop() }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer); voice.release() }
    }
    LaunchedEffect(residents, page, connected) { voice.stop() }
    val canMove = ambientMotionAllowed(PetPose.Move, false, connected, true)
    val dark = MaterialTheme.colorScheme.surface.luminance() < .35f
    val sideInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal)
    Column {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val sceneWidth = maxWidth
                val compact = sceneWidth < 700.dp
                val naturalLawnHeight = if (compact) (sceneWidth * 1.4f).coerceIn(660.dp, 850.dp)
                    else (sceneWidth * .53f).coerceIn(440.dp, 650.dp)
                val headroom = 100.dp + topInset
                val sceneHeight = sceneHeightOverride?.coerceAtLeast((if (compact) 700.dp else 570.dp) + topInset + bottomInset)
                    ?: (naturalLawnHeight + headroom + bottomInset)
                val lawnHeight = sceneHeight - headroom - 100.dp - bottomInset
                Box(Modifier.fillMaxWidth().height(sceneHeight)) {
                    Image(painterResource(R.drawable.plaza_garden), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    Canvas(Modifier.fillMaxSize()) {
                        if (dark) drawRect(Color(0xFF0C2440).copy(alpha = .53f))
                        drawRect(Brush.verticalGradient(listOf(Color(0xFF122A22).copy(alpha = .48f), Color.Transparent),
                            endY = maxOf(size.height * .28f, (topInset + 110.dp).toPx())))
                        if (dark) listOf(.09f to .30f, .89f to .35f, .06f to .80f, .92f to .87f).forEach { (x, y) ->
                            val center = Offset(size.width * x, size.height * y)
                            drawCircle(Brush.radialGradient(listOf(Color(0xFFFFE3A1).copy(alpha = .3f), Color.Transparent), center, 22.dp.toPx()), 22.dp.toPx(), center)
                            drawCircle(Color(0xFFFFE8AE), 2.dp.toPx(), center)
                        }
                    }
                    val titleShadow = Shadow(Color.Black.copy(alpha = .55f), Offset(0f, 2f), 6f)
                    Column(Modifier.fillMaxWidth().windowInsetsPadding(sideInsets)
                        .padding(start = 24.dp, end = 24.dp, top = topInset + 8.dp)) {
                        Text(if (dark) "달빛 아래, 친구들의 쉼터" else "오늘도, 함께 놀아요", color = Color.White,
                            style = MaterialTheme.typography.titleLarge.copy(shadow = titleShadow))
                        Text(when {
                            !connected && visible.isNotEmpty() -> "마지막으로 받은 친구들이에요. 폰 연결을 확인해 주세요."
                            visible.isEmpty() -> "친구들이 놀러 올 자리예요"
                            else -> "친구를 톡 눌러 인사해 보세요"
                        }, color = Color.White.copy(alpha = .92f), style = MaterialTheme.typography.bodyMedium.copy(shadow = titleShadow))
                    }
                    if (visible.isEmpty()) Box(Modifier.align(Alignment.Center).windowInsetsPadding(sideInsets)
                        .padding(horizontal = 24.dp).widthIn(max = 560.dp)) {
                        ParkedInfoCard("광장에서 만날 친구를 기다려요", when {
                            !connected -> "폰 연결을 확인해 주세요."
                            game.collectionSummary == null || "collectionSummary" in game.invalidBlocks -> "폰의 수집 정보를 기다리고 있어요."
                            available.isNotEmpty() -> "아래 친구들에서 광장에 나올 친구를 골라 주세요."
                            else -> "폰에서 수집한 친구들이 이곳에 찾아와요."
                        })
                    }
                    Box(Modifier.align(Alignment.BottomCenter).windowInsetsPadding(sideInsets)
                        .padding(start = 24.dp, end = 24.dp, top = 14.dp, bottom = 14.dp + bottomInset).fillMaxWidth()) { dock() }
                    visible.forEachIndexed { index, id -> key(id) {
                        val species = catalog[id]!!
                        // A local clock pauses exactly where the user tapped and resumes without a jump.
                        var seconds by remember { mutableFloatStateOf(0f) }
                        val focused = selected == id
                        LaunchedEffect(canMove, focused) {
                            if (canMove && !focused) {
                                var previous = withFrameNanos { it }
                                while (isActive) {
                                    withFrameNanos { now ->
                                        seconds += ((now - previous) / 1_000_000_000f).coerceIn(0f, .1f)
                                        previous = now
                                    }
                                }
                            }
                        }
                        val position = plazaWanderPose(index, seconds, compact)
                        val moving = canMove && !focused && position.moving
                        val baseSize = if (compact) (sceneWidth * .25f).coerceIn(84.dp, 150.dp)
                            else (sceneWidth * .145f).coerceIn(120.dp, 196.dp)
                        val petSize = baseSize * (.85f + position.y * .20f)
                        val x = (sceneWidth * position.x - petSize / 2).coerceIn(0.dp, sceneWidth - petSize)
                        var bubbleHeight by remember { mutableStateOf(150.dp) }
                        val walkingY = headroom + (lawnHeight * position.y - petSize * .86f).coerceAtLeast(76.dp)
                        val y = if (focused) walkingY.coerceAtLeast(bubbleHeight + 8.dp) else walkingY
                        Column(Modifier.offset(x, y).width(petSize).zIndex(position.y), horizontalAlignment = Alignment.CenterHorizontally) {
                            Surface(onClick = {
                                if (latestConnected && id in latestResidents) {
                                    selected = id
                                    line = dialogue.next(id)
                                    line?.let { voice.replace(it) }
                                }
                            }, enabled = connected, color = Color.Transparent, shape = RoundedCornerShape(24.dp),
                                modifier = Modifier.size(petSize).semantics { contentDescription = "${species.name}에게 말 걸기" }) {
                                Box(contentAlignment = Alignment.Center) {
                                    Canvas(Modifier.fillMaxSize()) {
                                        if (focused) drawOval(Color(0xFFFFED9F).copy(alpha = .65f), Offset(size.width * .12f, size.height * .81f), Size(size.width * .76f, size.height * .14f))
                                        drawOval(Color(0xFF153420).copy(alpha = .26f), Offset(size.width * .22f, size.height * .84f), Size(size.width * .56f, size.height * .09f))
                                    }
                                    PlazaPetArt(PetSummary(species.name, "광장 친구", species, false, 0f), petSize,
                                        modifier = Modifier,
                                        connected = connected, moving = moving, facingLeft = position.facingLeft)
                                }
                            }
                            Text(species.name, Modifier.padding(vertical = 5.dp),
                                maxLines = 1, overflow = TextOverflow.Ellipsis,
                                color = if (focused) Color(0xFFFFEDB3) else Color.White,
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = if (compact) 16.sp else MaterialTheme.typography.labelLarge.fontSize,
                                    shadow = Shadow(Color.Black.copy(alpha = .75f), Offset(0f, 2f), 5f)))
                        }
                        if (focused) {
                            val bubbleWidth = (sceneWidth - 24.dp).coerceAtMost(380.dp)
                            val bubbleX = (x + petSize / 2 - bubbleWidth / 2)
                                .coerceIn(12.dp, sceneWidth - bubbleWidth - 12.dp)
                            val density = LocalDensity.current
                            val paper = if (dark) Color(0xFFE8DFC5) else Color(0xFFFFFBE9)
                            val ink = Color(0xFF304729)
                            Column(Modifier.offset(bubbleX, (y - bubbleHeight + 12.dp).coerceAtLeast(8.dp))
                                .width(bubbleWidth).zIndex(20f)
                                .onSizeChanged { bubbleHeight = with(density) { it.height.toDp() } }) {
                                Surface(onClick = { line?.let { voice.speak(it) } },
                                    enabled = connected && line != null && speech.ready,
                                    color = paper, contentColor = ink, border = BorderStroke(2.dp, ink),
                                    shape = RoundedCornerShape(42.dp), shadowElevation = 3.dp,
                                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "광장 대사 다시 듣기" }) {
                                    Column(Modifier.padding(horizontal = 26.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                        Text(species.name, style = MaterialTheme.typography.labelSmall, color = Color(0xFF657256))
                                        Text(line ?: "이 친구의 대사는 아직 준비 중이에요.", modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center,
                                            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold, lineBreak = LineBreak.Heading))
                                        Text(speech.error ?: when {
                                            line == null -> "대사를 준비하고 있어요"
                                            speech.speaking -> "누르면 멈춰요"
                                            !speech.ready -> "음성을 준비하고 있어요"
                                            else -> "누르면 다시 들어요"
                                        }, style = MaterialTheme.typography.labelSmall, color = Color(0xFF657256), textAlign = TextAlign.Center)
                                    }
                                }
                                Canvas(Modifier.fillMaxWidth().height(24.dp)) {
                                    val tip = (x + petSize / 2 - bubbleX).toPx().coerceIn(24.dp.toPx(), size.width - 24.dp.toPx())
                                    val half = 14.dp.toPx()
                                    val tail = Path().apply {
                                        moveTo(tip - half, -3.dp.toPx())
                                        quadraticBezierTo(tip - half * .5f, size.height * .7f, tip - 6.dp.toPx(), size.height)
                                        quadraticBezierTo(tip + half * .6f, size.height * .5f, tip + half, -3.dp.toPx())
                                        close()
                                    }
                                    drawPath(tail, paper)
                                    val edges = Path().apply {
                                        moveTo(tip - half, 0f)
                                        quadraticBezierTo(tip - half * .5f, size.height * .7f, tip - 6.dp.toPx(), size.height)
                                        quadraticBezierTo(tip + half * .6f, size.height * .5f, tip + half, 0f)
                                    }
                                    drawPath(edges, ink, style = Stroke(2.dp.toPx()))
                                }
                            }
                        }
                    } }
                }
            }
    }
}
