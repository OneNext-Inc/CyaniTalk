// Nyachi应用程序的主组件文件
//
// 该文件包含应用程序的根组件NyachiApp，负责配置应用程序的主题、路由和整体结构。
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'package:debug_deck/debug_deck.dart';
import 'core/core.dart';
import 'core/theme/font_manager.dart';
import 'core/theme/font_refresh_notifier.dart';
import 'core/services/dynamic_color_service.dart';
import 'core/utils/deep_link_handler.dart';
import 'routing/router.dart';
import 'features/auth/application/auth_service.dart';
import 'features/misskey/application/misskey_streaming_service.dart';
import 'features/misskey/application/misskey_notifier.dart';
import 'features/misskey/application/misskey_notifications_notifier.dart';
import 'features/profile/presentation/settings/appearance_page.dart';
import 'features/welcome/application/welcome_state.dart';
import 'core/services/notification_manager.dart';
import 'features/update/application/update_notifier.dart';
import 'features/update/presentation/update_bottom_sheet.dart';
import 'core/services/sound_service.dart';
import 'core/services/timeline_cache_database.dart';
import 'shared/widgets/custom_title_bar.dart';
import 'features/profile/application/developer_settings_provider.dart';

/// Nyachi应用程序的根组件
///
/// 负责配置应用程序的主题、路由和整体结构，
/// 是整个应用程序的入口组件。
///
/// 主要功能：
/// - 管理应用程序的主题（支持亮色/暗色模式）
/// - 处理路由配置
/// - 初始化Misskey流媒体服务
/// - 响应外观设置的变化
class NyachiApp extends ConsumerStatefulWidget {
  const NyachiApp({super.key});

  @override
  ConsumerState<NyachiApp> createState() => _NyachiAppState();
}

/// NyachiApp的状态管理类
///
/// 负责管理应用程序的状态，包括主题缓存和外观设置。
class _NyachiAppState extends ConsumerState<NyachiApp>
    with WidgetsBindingObserver {
  /// 缓存的亮色主题
  ThemeData? _cachedLightTheme;

  /// 缓存的暗色主题
  ThemeData? _cachedDarkTheme;

  /// 缓存的亮色外观设置
  AppearanceSettings? _cachedLightSettings;

  /// 缓存的暗色外观设置
  AppearanceSettings? _cachedDarkSettings;

  /// 缓存的亮色动态 ColorScheme（用于缓存键比较）
  ColorScheme? _cachedLightDynamicScheme;

  /// 缓存的暗色动态 ColorScheme
  ColorScheme? _cachedDarkDynamicScheme;

  /// 标题栏 controller，仅创建一次
  final TitleBarController _titleBarController = TitleBarController();

  @override
  void initState() {
    super.initState();
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);

    // 初始化动态取色服务（实时监听系统主题色变化）
    DynamicColorService.instance.initialize();

    // 初始化 Deep Link 处理器（监听 nyachi-app:// URL Scheme 回调）
    DeepLinkHandler.instance.initialize();

    // 初始化性能监控
    performanceMonitor.initialize();

    // 初始化 debug_deck（默认关闭，由开发者模式开关控制）
    DebugTools.init(enabled: false);

    // 延迟检查更新（等待 UI 就绪）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateProvider.notifier).checkForUpdate(silent: true);
    });

    // 延迟检测 SQLite 并触发启动刷新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTimelinesOnStartup();
    });
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    // 清理动态取色服务
    DynamicColorService.instance.dispose();
    // 清理 Deep Link 处理器
    DeepLinkHandler.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    logger.debug('NyachiApp: 应用生命周期状态变化: $state');

    if (state == AppLifecycleState.resumed) {
      // 应用回到前台时刷新数据
      logger.info('NyachiApp: 应用回到前台，恢复实时心跳...');

      // 恢复前台心跳频率 (30s)
      ref
          .read(misskeyStreamingServiceProvider.notifier)
          .setBackgroundMode(false);

      // 重新连接 Misskey 流媒体服务
      ref.read(misskeyStreamingServiceProvider.notifier).reconnect();

      // 刷新 Misskey 各种 Provider (如果已挂载)
      ref.invalidate(misskeyNotificationsProvider);
      _refreshTimelinesOnStartup();
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // MiAuth 轮询期间不切换后台模式，保持前台心跳
      if (ref.read(authServiceProvider.notifier).isMiAuthInProgress) {
        logger.info('NyachiApp: MiAuth 进行中，忽略后台事件');
        return;
      }
      // 应用进入后台：降低心跳频率省电，保留通知流/时间线流
      logger.info('NyachiApp: 应用进入后台，降低心跳频率...');
      ref
          .read(misskeyStreamingServiceProvider.notifier)
          .setBackgroundMode(true);
    }

    if (state == AppLifecycleState.detached) {
      // 应用完全退出时清理资源
      logger.info('NyachiApp: 应用正在退出，清理资源...');

      // 保存所有缓存到持久化存储
      try {
        MisskeyTimelineNotifier.cacheManager.saveAllToStorage();
        logger.info('NyachiApp: 缓存已保存到持久化存储');
      } catch (e) {
        logger.warning('NyachiApp: 保存缓存失败: $e');
      }

      // 清理Misskey流媒体服务
      ref.read(misskeyStreamingServiceProvider.notifier).dispose();
      // 清理通知管理器
      ref.read(notificationManagerProvider).stop();
      logger.info('NyachiApp: 资源清理完成');
    }
  }

  /// 启动时检测 SQLite 并触发时间线刷新
  Future<void> _refreshTimelinesOnStartup() async {
    try {
      final shouldRefresh = await TimelineCacheDatabase().shouldRefresh('Home');
      if (!shouldRefresh) return;

      logger.info('NyachiApp: SQLite 记录过期，触发 Home 时间线刷新');
      ref.read(misskeyTimelineProvider('Home').notifier).refresh();
    } catch (e) {
      if (e.toString().contains('disposed')) return;
      logger.warning('NyachiApp: 启动刷新失败: $e');
    }
  }

  /// 构建应用程序的UI
  ///
  /// 加载外观设置，初始化服务，并根据设置构建应用程序界面。
  ///
  /// @param context 构建上下文
  /// @return 返回MaterialApp.router组件，作为应用程序的根组件
  @override
  Widget build(BuildContext context) {
    logger.info('NyachiApp: 初始化应用程序');

    final goRouter = ref.watch(goRouterProvider);
    logger.debug('NyachiApp: 加载路由配置');

    // 监听欢迎页完成状态，触发路由刷新
    ref.listen(welcomeCompletedProvider, (prev, next) {
      routerRefreshNotifier.value++;
    });

    // 监听开发者模式变化，关闭开发者模式时自动禁用 debug_deck
    ref.listen(developerSettingsProvider, (prev, next) {
      next.whenData((isDevMode) {
        if (!isDevMode) {
          DebugTools.setEnabled(false);
          logger.info('NyachiApp: debug_deck 已禁用（开发者模式关闭）');
        }
      });
    });

    // Get appearance settings
    final appearanceSettingsAsync = ref.watch(appearanceSettingsProvider);

    // Initialize Misskey Streaming Service at app level
    logger.debug('NyachiApp: 初始化Misskey流媒体服务');
    ref.watch(misskeyStreamingServiceProvider);

    // 监听字体刷新状态以触发重建
    ref.watch(fontRefreshProvider);

    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final toastConfig = ToastificationConfig(
      alignment: isDesktop ? Alignment.topRight : Alignment.topCenter,
      animationDuration: const Duration(milliseconds: 300),
      applyMediaQueryViewInsets: false,
    );

    return appearanceSettingsAsync.when(
      loading: () => const ColoredBox(color: Color(0xFFF0F0F0)),
      error: (error, stack) {
        logger.error('NyachiApp: 加载外观设置失败', error);
        // 使用默认设置
        const defaultSettings = AppearanceSettings(
          displayMode: ThemeMode.system,
          useDynamicColor: true,
          useCustomColor: false,
          primaryColor: null,
        );
        final theme = _buildTheme(defaultSettings, Brightness.light);
        return GlobalFontRefresher(
          child: _UpdateHandler(
            child: ToastificationWrapper(
              config: toastConfig,
              child: MaterialApp.router(
                routerConfig: goRouter,
                title: 'Nyachi',
                theme: theme,
                darkTheme: _buildTheme(defaultSettings, Brightness.dark),
                themeMode: defaultSettings.displayMode,
                debugShowCheckedModeBanner: false,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                builder: (context, child) => child!,
              ),
            ),
          ),
        );
      },
      data: (appearanceSettings) {
        logger.debug(
          'NyachiApp: 加载外观设置 - 显示模式: ${appearanceSettings.displayMode}, 动态色彩: ${appearanceSettings.useDynamicColor}',
        );

        // ── 动态取色策略 ──
        // Android/macOS/Linux: DynamicColorBuilder（自动监听壁纸/系统主题变化）
        // Windows: DynamicColorService（原生 WM_DWMCOLORIZATIONCOLORCHANGED 推送）
        // 两者通过 ListenableBuilder 同时监听，任一变化触发重建
        final isWindows = Platform.isWindows;
        final colorService = DynamicColorService.instance;

        // Windows 端：监听原生推送的 accent color 变化
        // 非 Windows 端：ListenableBuilder 仍挂载但 accentColor 很少变化，
        //   真正的 scheme 更新由 DynamicColorBuilder 驱动
        final rebuildTrigger = isWindows
            ? Listenable.merge([colorService.accentColor])
            : ValueNotifier<int>(0); // Android/macOS/Linux: 由 DynamicColorBuilder 驱动

        return ListenableBuilder(
          listenable: rebuildTrigger,
          builder: (context, _) {
            // 使用 DynamicColorBuilder 获取系统动态 ColorScheme
            // Android/macOS/Linux: 返回完整 CorePalette/accent 方案
            // Windows/旧版 Android: 返回 null，fallback 到 DynamicColorService 或种子色
            return DynamicColorBuilder(
              builder: (ColorScheme? builderLight, ColorScheme? builderDark) {
                // 确定最终的动态 ColorScheme
                ColorScheme? lightScheme;
                ColorScheme? darkScheme;

                if (appearanceSettings.useDynamicColor) {
                  if (isWindows) {
                    // Windows: 优先用 DynamicColorBuilder，fallback 到 DynamicColorService
                    lightScheme = builderLight ?? colorService.lightScheme;
                    darkScheme = builderDark ?? colorService.darkScheme;
                  } else {
                    // Android/macOS/Linux: 直接使用 DynamicColorBuilder
                    lightScheme = builderLight;
                    darkScheme = builderDark;
                  }

                  // 协调品牌色：将自定义 secondary/tertiary 微调至匹配动态 primary
                  if (lightScheme != null) {
                    lightScheme = lightScheme.harmonized();
                  }
                  if (darkScheme != null) {
                    darkScheme = darkScheme.harmonized();
                  }
                }

                // 构建主题
                final theme = _buildTheme(appearanceSettings, Brightness.light, dynamicColorScheme: lightScheme);
                final darkTheme = _buildTheme(appearanceSettings, Brightness.dark, dynamicColorScheme: darkScheme);

            final useCustomTitleBar =
                isDesktop && appearanceSettings.useCustomTitleBar;

            // 非自定义标题栏时恢复系统标题栏
            if (isDesktop && !useCustomTitleBar) {
              windowManager.setTitleBarStyle(TitleBarStyle.normal);
            }

            logger.debug('NyachiApp: 构建MaterialApp');

            Widget app = GlobalFontRefresher(
              child: _UpdateHandler(
                child: ToastificationWrapper(
                  config: toastConfig,
                  child: MaterialApp.router(
                    routerConfig: goRouter,
                    title: 'Nyachi',
                    theme: theme,
                    darkTheme: darkTheme,
                    themeMode: appearanceSettings.displayMode,
                    debugShowCheckedModeBanner: false,
                    localizationsDelegates: context.localizationDelegates,
                    supportedLocales: context.supportedLocales,
                    locale: context.locale,
                    builder: (context, child) {
                      Widget content;
                      if (useCustomTitleBar) {
                        content = Stack(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                top: M3ETitleBarTokens.standard.height,
                              ),
                              child: child!,
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: ListenableBuilder(
                                listenable: _titleBarController,
                                builder: (context, _) =>
                                    CustomTitleBar(controller: _titleBarController),
                              ),
                            ),
                          ],
                        );
                      } else {
                        content = child!;
                      }
                      // debug_deck 浮动调试面板（始终挂载，通过 ValueListenableBuilder 驱动重建）
                      // 使用两层 ValueListenableBuilder 分别监听 enabled 和 overlayHidden：
                      // - 外层监听 enabledListenable：控制 Offstage 挂载/卸载，避免 widget 树替换
                      // - 内层监听 overlayHidden：确保 showOverlay()/hideOverlay() 触发 rebuild
                      // 这样彻底避免 DebugToolsHost 条件渲染导致的 node.built 断言失败
                      return Stack(
                        children: [
                          content,
                          ValueListenableBuilder<bool>(
                            valueListenable: DebugTools.enabledListenable,
                            builder: (context, enabled, _) {
                              return ValueListenableBuilder<bool>(
                                valueListenable: DebugTools.overlayHidden,
                                builder: (context, _, _) {
                                  return Offstage(
                                    offstage: !enabled,
                                    child: const DebugOverlay(),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );

            if (useCustomTitleBar) {
              app = TitleBarScope(controller: _titleBarController, child: app);
            }

            return app;
          },
          ); // DynamicColorBuilder
        },
        ); // ListenableBuilder
      },
    );
  }

  /// 构建主题
  ///
  /// 根据用户的外观设置构建主题，支持深色模式、动态色彩和自定义颜色。
  /// 会缓存构建结果，避免重复计算。
  ///
  /// @param settings 用户的外观设置，包含显示模式、动态色彩和自定义颜色选项
  /// @param brightness 主题亮度，Brightness.light或Brightness.dark
  /// @param dynamicColorScheme 系统动态取色方案（可选）
  /// @return 返回构建的ThemeData对象
  ThemeData _buildTheme(AppearanceSettings settings, Brightness brightness, {ColorScheme? dynamicColorScheme}) {
    final isDark = brightness == Brightness.dark;
    final themeCache = isDark ? _cachedDarkTheme : _cachedLightTheme;
    final cachedSettings = isDark ? _cachedDarkSettings : _cachedLightSettings;
    final cachedScheme = isDark ? _cachedDarkDynamicScheme : _cachedLightDynamicScheme;

    // 缓存键 = settings + dynamicColorScheme（accent color 变化时 scheme 会变）
    final schemeMatch = dynamicColorScheme == null
        ? cachedScheme == null
        : (cachedScheme != null &&
            dynamicColorScheme.primary.toARGB32() == cachedScheme.primary.toARGB32());

    if (cachedSettings == settings && schemeMatch && themeCache != null) {
      return themeCache;
    }

    // 解析 ColorScheme：优先使用系统动态色，否则用种子色生成
    ColorScheme colorScheme;
    if (settings.useDynamicColor && dynamicColorScheme != null) {
      colorScheme = dynamicColorScheme;
    } else {
      final seedColor = settings.useCustomColor && settings.primaryColor != null
          ? settings.primaryColor!
          : const Color(0xFF39C5BB);
      colorScheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    }

    // 获取字体ID
    final fontFamilyId = settings.fontFamily ?? 'linar_sans';
    final isSystemFont = fontFamilyId.isEmpty || fontFamilyId == 'system';

    // 获取基础 TextTheme
    final baseTextTheme = SauceTypography.createTextTheme(
      Theme.of(context).platform,
    );

    // 应用字体 — 使用 colorScheme.onSurface 确保跟随动态取色
    TextTheme textTheme;
    String? effectiveFontFamily;

    if (isSystemFont) {
      textTheme = baseTextTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      );
      effectiveFontFamily = null;
    } else if (fontFamilyId == 'linar_sans') {
      textTheme = baseTextTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      );
      effectiveFontFamily = 'Linar Sans';
    } else {
      final coloredTextTheme = baseTextTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      );

      final dynamicTextTheme = FontManager.getTextTheme(
        fontFamilyId,
        coloredTextTheme,
      );
      if (dynamicTextTheme != null) {
        textTheme = dynamicTextTheme;
        effectiveFontFamily = fontFamilyId;
      } else {
        textTheme = coloredTextTheme;
        effectiveFontFamily = 'Linar Sans';
      }
    }

    final theme = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: effectiveFontFamily,
      textTheme: textTheme,
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surface,
      ),
      appBarTheme: const AppBarTheme(
        scrolledUnderElevation: 3,
      ),
      badgeTheme: const BadgeThemeData(),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        showDragHandle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      checkboxTheme: const CheckboxThemeData(),
      chipTheme: const ChipThemeData(),
      datePickerTheme: const DatePickerThemeData(),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
      dividerTheme: const DividerThemeData(),
      dropdownMenuTheme: const DropdownMenuThemeData(),
      expansionTileTheme: const ExpansionTileThemeData(),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(),
      iconButtonTheme: const IconButtonThemeData(),
      inputDecorationTheme: const InputDecorationThemeData(
        filled: true,
        border: OutlineInputBorder(),
      ),
      listTileTheme: const ListTileThemeData(),
      menuTheme: const MenuThemeData(),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
      ),
      popupMenuTheme: const PopupMenuThemeData(),
      progressIndicatorTheme: const ProgressIndicatorThemeData(),
      radioTheme: const RadioThemeData(),
      segmentedButtonTheme: const SegmentedButtonThemeData(),
      sliderTheme: const SliderThemeData(),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: const SwitchThemeData(),
      tabBarTheme: const TabBarThemeData(),
      timePickerTheme: const TimePickerThemeData(),
      tooltipTheme: const TooltipThemeData(),
    );

    final platform = Theme.of(context).platform;
    final isDesktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    final semanticColors = DesktopSemanticColors.fromColorScheme(
      theme.colorScheme,
      isDesktop: isDesktop,
    );
    const switchTokens = M3ESwitchTokens.standard;
    final adjustedTheme = isDesktop
        ? theme.copyWith(
            scaffoldBackgroundColor: semanticColors.appBackground,
            canvasColor: semanticColors.appBackground,
            extensions: [
              ...theme.extensions.values,
              semanticColors,
              switchTokens,
              M3ETitleBarTokens.standard,
              M3EShapeTokens.standard,
              M3ESliderTokens.standard,
              M3EMenuTokens.standard,
              M3ESoundPickerTokens.standard,
            ],
          )
        : theme.copyWith(
            extensions: [
              ...theme.extensions.values,
              semanticColors,
              switchTokens,
              M3ETitleBarTokens.standard,
              M3EShapeTokens.standard,
              M3ESliderTokens.standard,
              M3EMenuTokens.standard,
              M3ESoundPickerTokens.standard,
            ],
          );

    // 缓存主题和设置
    if (isDark) {
      _cachedDarkTheme = adjustedTheme;
      _cachedDarkSettings = settings;
      _cachedDarkDynamicScheme = dynamicColorScheme;
    } else {
      _cachedLightTheme = adjustedTheme;
      _cachedLightSettings = settings;
      _cachedLightDynamicScheme = dynamicColorScheme;
    }

    return adjustedTheme;
  }
}

class _UpdateHandler extends ConsumerStatefulWidget {
  final Widget child;

  const _UpdateHandler({required this.child});

  @override
  ConsumerState<_UpdateHandler> createState() => _UpdateHandlerState();
}

class _UpdateHandlerState extends ConsumerState<_UpdateHandler> {
  bool _hasShownUpdate = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(updateProvider, (prev, next) {
      if (next.state == UpdateState.updateAvailable && !_hasShownUpdate) {
        _hasShownUpdate = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(
              ref
                  .read(soundServiceProvider)
                  .playAppUpdate(),
            );
            showUpdateBottomSheet(context, next.update!);
          }
        });
      }
    });
    return widget.child;
  }
}
