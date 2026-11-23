package com.rocgrey.sleeptongshu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.School
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.rocgrey.sleeptongshu.ui.monitoring.MonitoringScreen
import com.rocgrey.sleeptongshu.ui.health.HealthOverviewScreen
import com.rocgrey.sleeptongshu.ui.sleep.SleepDashboardScreen
import com.rocgrey.sleeptongshu.ui.trends.TrendsScreen
import com.rocgrey.sleeptongshu.ui.classroom.SleepClassroomScreen

/** 与 iOS SleepTab 枚举一致的五个 Tab。 */
enum class SleepTab(val route: String, val labelRes: Int, val icon: ImageVector) {
    SLEEP("sleep", R.string.tab_sleep, Icons.Filled.Bedtime),
    MONITORING("monitoring", R.string.tab_monitoring, Icons.Filled.GraphicEq),
    TRENDS("trends", R.string.tab_trends, Icons.Filled.Insights),
    HEALTH("health", R.string.tab_health, Icons.Filled.Favorite),
    CLASSROOM("classroom", R.string.tab_classroom, Icons.Filled.School),
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as TongshuApplication).container
        setContent {
            androidx.compose.runtime.CompositionLocalProvider(LocalAppContainer provides container) {
                RootView()
            }
        }
    }
}

@Composable
fun RootView() {
    val container = LocalAppContainer.current
    val appearance by container.preferences.appearance.collectAsStateWithLifecycle(
        initialValue = com.rocgrey.sleeptongshu.ui.theme.AppAppearance.FRESH,
    )
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    com.rocgrey.sleeptongshu.ui.theme.TongshuTheme(appearance = appearance, darkTheme = dark) {
        RootTabView()
    }
}

/** 根导航 CompositionLocal：次级页面通过它 navigate。 */
val LocalRootNav = androidx.compose.runtime.staticCompositionLocalOf<NavHostController> {
    error("NavHostController 未提供")
}

@Composable
fun RootTabView() {
    val container = LocalAppContainer.current
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route

    // 启动时恢复会话校验（与 iOS /auth/me 校验一致）
    androidx.compose.runtime.LaunchedEffect(Unit) {
        container.accountStore.restoreValidate()
        container.contentStore.refresh(force = false)
    }

    Scaffold(
        bottomBar = {
            if (currentRoute in SleepTab.entries.map { it.route }) {
                NavigationBar {
                    SleepTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.startDestinationId) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(LocalContext.current.getString(tab.labelRes)) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        androidx.compose.runtime.CompositionLocalProvider(LocalRootNav provides navController) {
        NavHost(
            navController = navController,
            startDestination = SleepTab.SLEEP.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(SleepTab.SLEEP.route) { SleepDashboardScreen() }
            composable(SleepTab.MONITORING.route) { MonitoringScreen() }
            composable(SleepTab.TRENDS.route) { TrendsScreen() }
            composable(SleepTab.HEALTH.route) { HealthOverviewScreen() }
            composable(SleepTab.CLASSROOM.route) { SleepClassroomScreen() }
            // 次级页面（各模块自行 navigate）
            composable("account") { com.rocgrey.sleeptongshu.ui.account.AccountScreen() }
            composable("breathing") { com.rocgrey.sleeptongshu.ui.classroom.BreathingScreen() }
            composable("noise") { com.rocgrey.sleeptongshu.ui.classroom.WhiteNoiseScreen() }
            composable("goodnight") { com.rocgrey.sleeptongshu.ui.classroom.GoodnightScreen() }
            composable("classroom/article/{itemId}") { entry ->
                com.rocgrey.sleeptongshu.ui.classroom.ClassroomDetailScreen(
                    itemId = entry.arguments?.getString("itemId") ?: "",
                )
            }
            composable("classroom/video/{itemId}") { entry ->
                com.rocgrey.sleeptongshu.ui.classroom.ClassroomVideoScreen(
                    itemId = entry.arguments?.getString("itemId") ?: "",
                )
            }
            composable("health/metric/{metricId}") { entry ->
                com.rocgrey.sleeptongshu.ui.health.HealthMetricDetailScreen(
                    metricId = entry.arguments?.getString("metricId") ?: "",
                )
            }
        }
        }
    }
}
