package ai.allo.car.debug

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.material3.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ai.allo.car.ui.*

/** Debug-only artwork gallery. No game, ownership, Firebase, or pairing writes. */
class SuppliedCharactersActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AlloTheme {
                val catalog = rememberSpeciesCatalog()
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.windowInsetsPadding(WindowInsets.safeDrawing).padding(20.dp)) {
                        Text("제공된 원본 캐릭터 12종", style = MaterialTheme.typography.headlineSmall)
                        Text("표시 확인용 · 폰 연결 불필요 · 게임 상태 변경 없음", style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(12.dp))
                        LazyVerticalGrid(GridCells.Fixed(4), Modifier.weight(1f),
                            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(catalog.entries.values.toList(), key = { it.id }) { species ->
                                Card {
                                    Column(Modifier.fillMaxWidth().padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                        PetArt(PetSummary(species.name, "원본", species, false, 0f), 148.dp, connected = false)
                                        Text(species.name, style = MaterialTheme.typography.titleSmall)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
