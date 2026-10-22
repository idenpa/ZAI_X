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

  // 1. 初始化 Hive 并复用原版路径
  await Hive.initFlutter();
  var dir = await getApplicationSupportDirectory();
  
  // ✅ 核心优化 1：给窗口数据建立专属的独立小箱子，彻底隔离原版大文件的 I/O 竞争
  var settingsBox = await Hive.openBox("WindowSettings", path: dir.path);

  // 2. 读取记忆的宽高
  double savedWidth = settingsBox.get('window_width', defaultValue: 975.0);
  double savedHeight = settingsBox.get('window_height', defaultValue: 880.0);

  // 3. 初始化窗口管理器
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    // ✅ 仅对 Mac 开启关闭拦截，Windows 端放开拦截，实现系统级秒退！
    if (Platform.isMacOS) {
      await windowManager.setPreventClose(true);
    }

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
  // ✅ 使用专属的独立小箱子，不再碰 LocalStorage
  final box = Hive.box('WindowSettings'); 
  
  // 内存缓存尺寸
  Size _currentWindowSize = const Size(975.0, 880.0);
  
  // 防抖定时器
  Timer? _resizeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
      windowManager.getSize().then((size) {
        _currentWindowSize = size;
      });
    }
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && Platform.isMacOS) {
      await _showWindowIfNeeded();
    }
  }

  // ✅ 核心优化 2：500ms 防抖 + 脏检查（只有尺寸真的变了才落盘，移动窗口绝对不写磁盘！）
  @override
  void onWindowResize() {
    super.onWindowResize();
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 500), () async {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final newSize = await windowManager.getSize();
        
        // 如果尺寸没变，说明只是移动了位置，直接 return，彻底榨干多余的性能开销！
        if (newSize.width == _currentWindowSize.width && 
            newSize.height == _currentWindowSize.height) {
          return;
        }
        
        _currentWindowSize = newSize;
        await box.put('window_width', _currentWindowSize.width);
        await box.put('window_height', _currentWindowSize.height);
      }
    });
  }

  Future<void> _showWindowIfNeeded() async {
    if (Platform.isMacOS) {
      if (!await windowManager.isVisible()) {
        await windowManager.show();
        await windowManager.focus();
      }
    }
  }

  // ⚠️ 注意：这里删掉了 onWindowBlur，失焦不再触发无意义的存盘。

  @override
  void onWindowClose() async {
    // Windows 已经关闭拦截，不会进这里，直接走系统级秒退。
    if (Platform.isMacOS) {
      // Mac 隐藏前，获取最新尺寸强制存一次（防止拖拽瞬间点关闭没被 Timer 捕获）
      final size = await windowManager.getSize();
      await box.put('window_width', size.width);
      await box.put('window_height', size.height);
      
      await windowManager.hide(); 
    }
  }

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
