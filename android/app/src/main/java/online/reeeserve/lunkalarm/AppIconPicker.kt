package online.reeeserve.lunkalarm

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun LauncherIconPreview(icon: LauncherIcon, modifier: Modifier, cornerRadius: Dp) {
    Box(modifier.clip(RoundedCornerShape(cornerRadius))) {
        Image(painterResource(icon.artwork), contentDescription = null,
            modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = 1.5f; scaleY = 1.5f })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppIconPicker(theme: LunkTheme, selected: LauncherIcon, close: () -> Unit, choose: (LauncherIcon) -> Unit) {
    ModalBottomSheet(onDismissRequest = close, containerColor = theme.card) {
        Text("App icon", Modifier.padding(horizontal = 24.dp, vertical = 8.dp), fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold, color = theme.text)
        LazyVerticalGrid(
            columns = GridCells.Adaptive(96.dp),
            modifier = Modifier.heightIn(max = 540.dp).selectableGroup(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(LauncherIcon.entries, key = { it.id }) { icon ->
                val shape = RoundedCornerShape(14.dp)
                val isSelected = icon == selected
                Box(Modifier.heightIn(min = 108.dp).clip(shape).background(theme.field)
                    .border(1.dp, if (isSelected) theme.accent else theme.border, shape)
                    .selectable(isSelected, role = Role.RadioButton) { choose(icon) }
                    .testTag("app-icon-${icon.id}")) {
                    Column(Modifier.fillMaxWidth().align(Alignment.Center).padding(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        LauncherIconPreview(icon, Modifier.size(54.dp), 12.dp)
                        Text(icon.title, fontSize = 12.sp, color = theme.text, textAlign = TextAlign.Center)
                    }
                    if (isSelected) Icon(Icons.Default.CheckCircle, null,
                        Modifier.align(Alignment.TopEnd).padding(6.dp).size(15.dp), tint = theme.accent)
                }
            }
        }
    }
}
