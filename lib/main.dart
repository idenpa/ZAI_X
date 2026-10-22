import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zai_x/app/app_style.dart';
import 'package:zai_x/models/db/comic_download_info.dart';
import 'package:zai_x/models/db/download_status.dart';
import 'package:zai_x/models/db/local_favorite.dart';
import 'package:zai_x/models/db/novel_download_info.dart';
import 'package:zai_x/services/app_settings_service.dart';
import 'package:zai_x/app/log.dart';
import 'package:zai_x/app/utils.dart';
import 'package:zai_x/models/db/comic_history.dart';
import 'package:zai_x/models/db/novel_history.dart';
import 'package:zai_x/services/comic_download_service.dart';
import 'package:zai_x/services/novel_download_service.dart';
import 'package:zai_x/services/novel_font_service.dart';
import 'package:zai_x/services/db_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zai_x/routes/app_pages.dart';
import 'package:zai_x/services/local_storage_service.dart';
import 'package:zai_x/services/user_service.dart';
import 'package:zai_x/widgets/status/app_loadding_widget.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      [],
      "com.xycz.zmhx",
      onSecondWindow: (args) {
        Log.logPrint(args);
      },
    );
  }

  // 1. 初始化 Hive 并复用原版路径和 Box
  await Hive.initFlutter();
  var dir = await getApplicationSupportDirectory();
  var settingsBox = await Hive.openBox(
    "LocalStorage",
    path: dir.path,
  );

  // 2. 读取记忆的宽高
  double savedWidth = settingsBox.get('window_width', defaultValue: 975.0);
  double savedHeight = settingsBox.get('window_height', defaultValue: 880.0);

  // 3. 初始化窗口管理器
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    // ✅ 全局开启关闭拦截，确保关窗前有时间落盘或执行隐藏
    await windowManager.setPreventClose(true);

    WindowOptions windowOptions = WindowOptions(
      size: Size(savedWidth, savedHeight),
      minimumSize: const Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 初始化其他服务
  await initServices();

  // 设置状态栏为透明
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemUiOverlayStyle systemUiOverlayStyle = const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  );
  SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);

  runApp(const DMZJApp());
}

Future initServices() async {
  Utils.packageInfo = await PackageInfo.fromPlatform();
  Log.d("Init LocalStorage Service");
  await Get.put(LocalStorageService()).init();

  Log.d("Init User Service");
  Get.put(UserService()).init();

  Hive.registerAdapter(ComicHistoryAdapter());
  Hive.registerAdapter(NovelHistoryAdapter());
  Hive.registerAdapter(DownloadStatusAdapter());
  Hive.registerAdapter(ComicDownloadInfoAdapter());
  Hive.registerAdapter(NovelDownloadInfoAdapter());
  Hive.registerAdapter(LocalFavoriteAdapter());
  await Get.put(DBService()).init();

  await Get.put(NovelFontService()).init();
  Get.put(AppSettingsService());
  Get.put(ComicDownloadService()).init();
  Get.put(NovelDownloadService()).init();
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

class DMZJApp extends StatefulWidget {
  const DMZJApp({super.key});

  @override
  State<DMZJApp> createState() => _DMZJAppNState();
}

class _DMZJAppNState extends State<DMZJApp> with WindowListener, WidgetsBindingObserver {
  final box = Hive.box('LocalStorage');
  
  // ✅ 核心优化：在内存中缓存的尺寸，避免退出时跨语言请求导致卡顿
  Size _currentWindowSize = const Size(975.0, 880.0);

  @override
  void initState() {
    super.initState();
    // 1. 注册生命周期监听（用于兜底唤醒）
    WidgetsBinding.instance.addObserver(this);
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    // 移除监听
    WidgetsBinding.instance.removeObserver(this);
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // ✅ 监听生命周期（当点击 Dock 图标时，系统会触发 resumed）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && Platform.isMacOS) {
      await _showWindowIfNeeded();
    }
  }

  // ✅ 拖拽时仅更新内存变量，速度极快，无卡顿
  @override
  void onWindowResize() {
    super.onWindowResize();
    windowManager.getSize().then((size) {
      _currentWindowSize = size;
    });
  }

  // 将内存里的尺寸写入 Hive 磁盘
  Future<void> _saveCurrentWindowSize() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await box.put('window_width', _currentWindowSize.width);
      await box.put('window_height', _currentWindowSize.height);
    }
  }

  // 通用唤醒逻辑
  Future<void> _showWindowIfNeeded() async {
    if (Platform.isMacOS) {
      if (!await windowManager.isVisible()) {
        await windowManager.show();
        await windowManager.focus();
      }
    }
  }

  // 失焦时顺手存一次
  @override
  void onWindowBlur() async {
    super.onWindowBlur();
    await _saveCurrentWindowSize();
  }

  // ✅ 核心闭环：分平台处理关闭
  @override
  void onWindowClose() async {
    if (Platform.isMacOS) {
      // 🍏 Mac 端：等待存盘完毕后隐藏窗口
      await _saveCurrentWindowSize();
      await windowManager.hide(); 
    } else {
      // 🪟 Windows 端：不等待存盘，直接把任务丢给后台，瞬间退出！
      _saveCurrentWindowSize(); // 👈 注意：这里去掉了 await
      await windowManager.destroy(); 
    }
  }

  // Mac 点击 Dock 栏图标重新唤醒窗口
  @override
  void onWindowFocus() async {
    super.onWindowFocus();
    await _showWindowIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ZAI-X',
      scrollBehavior: AppScrollBehavior(),
      theme: AppStyle.lightTheme,
      darkTheme: AppStyle.darkTheme,
      themeMode:
          ThemeMode.values[Get.find<AppSettingsService>().themeMode.value],
      initialRoute: AppPages.kIndex,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale("zh", "CN"),
      supportedLocales: const [Locale("zh", "CN")],
      getPages: AppPages.routes,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(
        loadingBuilder: ((msg) => const AppLoaddingWidget()),
        builder: (context, child) => Obx(
          () => MediaQuery(
            data: AppSettingsService.instance.useSystemFontSize.value
                ? MediaQuery.of(context)
                : MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.0)),
            child: child!,
          ),
        ),
      ),
    );
  }
}
