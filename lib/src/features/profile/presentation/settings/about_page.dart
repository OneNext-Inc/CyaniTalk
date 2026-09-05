// 关于页面
//
// 该文件包含AboutPage组件，用于显示应用程序的关于信息，包括版本号、贡献者列表和GitHub链接。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/src/core/core.dart';
import '/src/core/api/network_client.dart';
import '/src/core/widgets/settings_widgets.dart';
import 'sponsor_page.dart';
import '/src/shared/widgets/cyani_loading_indicator.dart';
import '/src/shared/widgets/toast_helper.dart';

/// 应用程序的关于页面组件
///
/// 显示应用程序的版本信息、贡献者列表和GitHub链接，
/// 并在页面打开时播放音效。
class AboutPage extends ConsumerStatefulWidget {
  /// 创建一个新的AboutPage实例
  ///
  /// [key] - 组件的键，用于唯一标识组件
  const AboutPage({super.key});

  /// 创建AboutPage的状态管理对象
  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

/// AboutPage的状态管理类
class _AboutPageState extends ConsumerState<AboutPage> {
  /// 应用程序名称
  String _appName = 'Nyachi';

  /// 应用程序版本号
  String _version = '';

  /// 贡献者列表
  List<dynamic> _contributors = [];

  /// 是否正在加载贡献者数据
  bool _isLoadingContributors = true;

  /// SharedPreferences 实例
  SharedPreferences? _prefs;

  /// 缓存键
  static const String _contributorsCacheKey = 'about_contributors_cache';
  static const String _contributorsCacheTimestampKey =
      'about_contributors_cache_timestamp';
  static const Duration _cacheDuration = Duration(days: 7);

  /// 初始化页面状态
  ///
  /// 加载应用程序信息和贡献者数据。
  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _initSharedPreferences();
  }

  /// 初始化 SharedPreferences
  Future<void> _initSharedPreferences() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _fetchContributors();
    } catch (e) {
      logger.error('AboutPage: Error initializing SharedPreferences: $e');
      _fetchContributors();
    }
  }

  /// 释放资源
  ///
  ///  dispose音频播放器资源。
  @override
  void dispose() {
    super.dispose();
  }

  /// 初始化应用程序包信息
  ///
  /// 获取应用程序的版本号和构建号。
  Future<void> _initPackageInfo() async {
    try {
      logger.info('AboutPage: Initializing package info');
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _appName = "Nyachi";
        _version = '${info.version}+${info.buildNumber}';
      });
      logger.info(
        'AboutPage: Package info initialized successfully: version=$_version',
      );
    } catch (e) {
      logger.error('AboutPage: Error initializing package info: $e');
    }
  }

  /// 获取GitHub贡献者列表
  ///
  /// 优先从缓存加载贡献者数据，如果缓存过期则从GitHub API获取。
  Future<void> _fetchContributors() async {
    try {
      // 优先从缓存加载
      final cachedContributors = await _loadContributorsFromCache();
      if (cachedContributors != null) {
        if (mounted) {
          setState(() {
            _contributors = cachedContributors;
            _isLoadingContributors = false;
          });
        }
        logger.info(
          'AboutPage: Loaded ${cachedContributors.length} contributors from cache',
        );
        // 后台更新缓存
        _refreshContributorsInBackground();
        return;
      }

      // 缓存过期或不存在，从API获取
      logger.info('AboutPage: Fetching GitHub contributors from API');
      final dio = NetworkClient().createDio(host: 'api.github.com');
      final response = await dio.get(
        '/repos/CyaniAgent/Nyachi/contributors',
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final contributors = response.data;
      await _saveContributorsToCache(contributors);

      if (mounted) {
        setState(() {
          _contributors = contributors;
          _isLoadingContributors = false;
        });
      }
      logger.info(
        'AboutPage: Successfully fetched ${contributors.length} contributors from API',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingContributors = false;
        });
      }
      logger.error('AboutPage: Error fetching contributors: $e');
    }
  }

  /// 从缓存加载贡献者数据
  Future<List<dynamic>?> _loadContributorsFromCache() async {
    if (_prefs == null) return null;

    try {
      final cachedData = _prefs!.getString(_contributorsCacheKey);
      final cachedTimestamp = _prefs!.getInt(_contributorsCacheTimestampKey);

      if (cachedData != null && cachedTimestamp != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
        if (DateTime.now().difference(cacheTime) < _cacheDuration) {
          final contributors = jsonDecode(cachedData);
          return contributors;
        }
      }
    } catch (e) {
      logger.error('AboutPage: Error loading contributors from cache: $e');
    }
    return null;
  }

  /// 保存贡献者数据到缓存
  Future<void> _saveContributorsToCache(List<dynamic> contributors) async {
    if (_prefs == null) return;

    try {
      await _prefs!.setString(_contributorsCacheKey, jsonEncode(contributors));
      await _prefs!.setInt(
        _contributorsCacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      logger.debug('AboutPage: Contributors saved to cache');
    } catch (e) {
      logger.error('AboutPage: Error saving contributors to cache: $e');
    }
  }

  /// 后台刷新贡献者数据
  Future<void> _refreshContributorsInBackground() async {
    try {
      logger.info('AboutPage: Refreshing contributors in background');
      final dio = NetworkClient().createDio(host: 'api.github.com');
      final response = await dio.get(
        '/repos/CyaniAgent/Nyachi/contributors',
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final contributors = response.data;
      await _saveContributorsToCache(contributors);

      if (mounted) {
        setState(() {
          _contributors = contributors;
        });
      }
      logger.info('AboutPage: Background refresh completed');
    } catch (e) {
      logger.error(
        'AboutPage: Error refreshing contributors in background: $e',
      );
    }
  }

  /// 打开GitHub项目页面
  ///
  /// 在外部浏览器中打开项目的GitHub仓库页面。
  Future<void> _launchGitHub() async {
    try {
      logger.info('AboutPage: Launching GitHub project page');
      final url = Uri.parse('https://github.com/CyaniAgent/Nyachi');
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          logger.warning('AboutPage: Failed to launch GitHub page');
          showToast(title: 'about_github_launch_error'.tr(), type: ToastificationType.error);
        }
      } else {
        logger.info('AboutPage: GitHub page launched successfully');
      }
    } catch (e) {
      logger.error('AboutPage: Error launching GitHub page: $e');
      if (mounted) {
        showToast(title: 'about_github_launch_error'.tr(), type: ToastificationType.error);
      }
    }
  }

  /// 打开赞助页面
  ///
  /// 导航到应用内的赞助页面。
  void _launchSponsorPage() {
    try {
      logger.info('AboutPage: Launching sponsor page');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SponsorPage()),
      );
      logger.info('AboutPage: Sponsor page launched successfully');
    } catch (e) {
      logger.error('AboutPage: Error launching sponsor page: $e');
      if (mounted) {
        showToast(title: 'about_sponsor_launch_error'.tr(), type: ToastificationType.error);
      }
    }
  }

  /// 构建关于页面的UI界面
  ///
  /// [context] - 构建上下文，包含组件树的信息
  ///
  /// 返回一个包含应用程序信息、贡献者列表和GitHub链接的Scaffold组件
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('about_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          // 应用信息部分
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Image.asset(
                  'assets/icons/logo/desktop/logo-desktop-transparent.png',
                  width: 80,
                  height: 80,
                  errorBuilder: (_, _, _) => const Icon(Icons.error, size: 80),
                ),
                const SizedBox(height: 16),
                Text(
                  _appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Version $_version',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),

          // 链接部分
          SettingsCardGroup(
            children: [
              SettingsTile(
                icon: Icons.code,
                iconColor: Theme.of(context).colorScheme.primary,
                title: 'about_github'.tr(),
                subtitle: 'about_github_description'.tr(),
                onTap: _launchGitHub,
              ),
              SettingsTile(
                icon: Icons.favorite,
                iconColor: Theme.of(context).colorScheme.tertiary,
                title: 'about_sponsor'.tr(),
                subtitle: 'about_sponsor_description'.tr(),
                onTap: _launchSponsorPage,
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_isLoadingContributors)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CyaniLoadingIndicator()),
            )
          else if (_contributors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('about_no_contributors'.tr()),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: _contributors.length,
                itemBuilder: (_, index) {
                  final contributor = _contributors[index];
                  return Column(
                    children: [
                      CircleAvatar(
                        backgroundImage: NetworkImage(
                          contributor['avatar_url'],
                        ),
                        radius: 30,
                        onBackgroundImageError: (_, _) {},
                        child: const Icon(Icons.person, color: Colors.transparent),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contributor['login'],
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                },
              ),
            ),

          const SizedBox(height: 16),


          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'about_copyright'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

}
