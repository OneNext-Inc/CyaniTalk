import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '/src/features/auth/data/auth_repository.dart';
import '/src/features/auth/domain/account.dart';
import '/src/features/auth/domain/misskey_permissions.dart';
import '/src/core/core.dart';
import '/src/features/misskey/application/misskey_notifier.dart';
import '/src/features/profile/application/network_settings_provider.dart';
import '/src/features/http-server/miauth_local_server.dart';

part 'auth_service.g.dart';

/// MiAuth 单次检查结果
enum MiAuthCheckResult {
  /// 认证成功，已保存账户
  success,
  /// 用户尚未授权（服务器返回 ok: false）
  pending,
  /// 网络或服务器临时错误，可重试
  networkError,
}

/// 认证服务类
///
/// 负责处理用户认证流程，包括Misskey的MiAuth流程，
/// 管理认证状态和账户信息。
@Riverpod(keepAlive: true)
class AuthService extends _$AuthService {
  /// MiAuth 轮询期间为 true，用于阻止 app.dart 切换后台模式
  bool isMiAuthInProgress = false;

  /// 初始化认证服务状态
  ///
  /// 从认证仓库中获取所有已保存的账户，并将其作为初始状态。
  ///
  /// 返回包含所有账户的Future列表
  @override
  FutureOr<List<Account>> build() async {
    logger.info('初始化认证服务');
    final repository = ref.watch(authRepositoryProvider);
    final accounts = await repository.getAccounts();
    logger.info('认证服务初始化完成，加载了 ${accounts.length} 个账户');
    return accounts;
  }

  /// 启动Misskey的MiAuth认证流程
  ///
  /// 开始Misskey平台的MiAuth认证流程，生成会话ID并打开浏览器进行授权。
  /// 会检查账户数量限制，最多支持10个Misskey账户。
  ///
  /// @param host Misskey实例的主机地址
  /// @return 返回会话ID，用于后续检查认证状态
  Future<String> startMiAuth(String host) async {
    return startMiAuthWithCallback(host);
  }

  /// 启动Misskey的MiAuth认证流程（带 Deep Link 回调）
  ///
  /// 生成会话ID，构建包含 `callback=nyachi-app://miauth` 的 MiAuth URL，
  /// 然后打开浏览器进行授权。浏览器授权完成后会通过 Deep Link 回调
  /// 将 session 参数带回应用，无需轮询。
  ///
  /// @param host Misskey实例的主机地址
  /// @return 返回会话ID，用于后续检查认证状态
  Future<String> startMiAuthWithCallback(String host) async {
    final sanitizedHost = _sanitizeHost(host);
    logger.info('开始Misskey MiAuth认证流程，主机: $sanitizedHost (原始: $host)');
    final accounts = await ref.read(authRepositoryProvider).getAccounts();

    final misskeyAccounts = accounts
        .where((a) => a.platform == 'misskey')
        .length;

    logger.info('当前Misskey账户数量: $misskeyAccounts');

    final session = const Uuid().v4();
    logger.debug('生成MiAuth会话ID: $session');

    final uri = Uri.https(sanitizedHost, '/miauth/$session', {
      'name': 'Nyachi',
      'permission': MisskeyPermissions.toMiAuthString(),
      'callback': 'nyachi-app://miauth',
    });

    logger.debug('生成MiAuth URL: ${uri.toString()}');

    // On some Android versions, canLaunchUrl might return false even if it works.
    // We attempt to launch and catch errors for better reliability.
    try {
      logger.info('尝试启动浏览器进行MiAuth授权');
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        logger.info('MiAuth授权页面已成功打开');
        return session;
      } else {
        logger.error('启动URL返回失败: ${uri.toString()}');
        throw Exception('无法打开浏览器进行授权');
      }
    } catch (e) {
      logger.error('启动MiAuth URL时发生错误: $e', e);
      throw Exception('授权流程启动失败: 请检查您的设备是否安装了浏览器');
    }
  }

  /// 启动 Misskey MiAuth 认证流程（桌面端：本地 HTTP 服务器回调）
  ///
  /// 在桌面端启动临时 HTTP 服务器，使用 http://127.0.0.1:{port}/miauth
  /// 作为回调 URL，等待 Misskey 服务器回调。
  ///
  /// @param host Misskey 实例的主机地址
  /// @return 返回 (session, 本地服务器实例)
  Future<(String, MiAuthLocalServer)> startMiAuthDesktop(String host) async {
    final sanitizedHost = _sanitizeHost(host);
    logger.info('开始 Misskey MiAuth 桌面端认证流程，主机: $sanitizedHost');
    final accounts = await ref.read(authRepositoryProvider).getAccounts();

    final misskeyAccounts = accounts
        .where((a) => a.platform == 'misskey')
        .length;

    logger.info('当前 Misskey 账户数量: $misskeyAccounts');

    // 启动本地 HTTP 服务器
    final server = MiAuthLocalServer();
    final callbackBaseUrl = await server.start();
    final callbackUrl = '$callbackBaseUrl?session={session}&host={host}';

    logger.info('MiAuth 本地回调服务器已启动，回调 URL: $callbackUrl');

    final session = const Uuid().v4();
    logger.debug('生成 MiAuth 会话 ID: $session');

    final uri = Uri.https(sanitizedHost, '/miauth/$session', {
      'name': 'Nyachi',
      'permission': MisskeyPermissions.toMiAuthString(),
      'callback': '$callbackBaseUrl?session=$session&host=$sanitizedHost',
    });

    logger.debug('生成 MiAuth URL: ${uri.toString()}');

    try {
      logger.info('尝试启动浏览器进行 MiAuth 授权');
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        logger.info('MiAuth 授权页面已成功打开');
        return (session, server);
      } else {
        await server.stop();
        logger.error('启动 URL 返回失败: ${uri.toString()}');
        throw Exception('无法打开浏览器进行授权');
      }
    } catch (e) {
      await server.stop();
      logger.error('启动 MiAuth URL 时发生错误: $e', e);
      throw Exception('授权流程启动失败: 请检查您的设备是否安装了浏览器');
    }
  }

  /// 检查Misskey MiAuth认证状态

  ///

  /// [host] - Misskey实例的主机地址

  /// [session] - 认证会话ID

  ///

  /// 成功时保存账户信息并刷新状态，失败时抛出异常

  /// 单次检查 MiAuth 认证状态（无内部循环，由调用方通过 Timer 轮询）
  ///
  /// [host] Misskey 实例主机地址
  /// [session] MiAuth 会话 ID
  ///
  /// 返回 [MiAuthCheckResult] 枚举：
  /// - [MiAuthCheckResult.success] 已保存账户
  /// - [MiAuthCheckResult.pending] 用户尚未授权，可继续轮询
  /// - [MiAuthCheckResult.networkError] 网络/服务器临时错误，可重试
  Future<MiAuthCheckResult> checkMiAuth(
    String host,
    String session, {
    CancelToken? cancelToken,
  }) async {
    final sanitizedHost = _sanitizeHost(host);
    logger.debug('MiAuth 单次检查: $sanitizedHost');

    final networkSettings = ref.read(networkSettingsProvider).value;
    // 使用无 RetryInterceptor 的 Dio，避免与外部轮询机制叠加
    // 超时设为 20 秒以兼容响应较慢的实例（如 hub.imikufans.com）
    final dio = Dio(BaseOptions(
      baseUrl: 'https://$sanitizedHost',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': networkSettings?.effectiveUserAgent,
        'Accept': 'application/json',
      },
    ));

    try {
      final response = await dio.post(
        '/api/miauth/$session/check',
        data: {},
        cancelToken: cancelToken,
      );

      final data = response.data;
      if (data is Map && data['ok'] == true) {
        await _handleSuccessfulAuth(data, sanitizedHost);
        return MiAuthCheckResult.success;
      }

      // ok: false — 用户尚未授权或已拒绝
      logger.debug('MiAuth 未就绪: $data');
      return MiAuthCheckResult.pending;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return MiAuthCheckResult.pending; // 被取消，静默返回
      }
      logger.warning('MiAuth 网络错误: ${e.message}');
      return MiAuthCheckResult.networkError;
    } catch (e) {
      logger.error('MiAuth 非预期错误: $e');
      return MiAuthCheckResult.networkError;
    }
  }

  Future<void> _handleSuccessfulAuth(
    Map<dynamic, dynamic> data,
    String sanitizedHost,
  ) async {
    final token = data['token'];
    final user = data['user'];

    if (token == null || user == null) {
      logger.error('MiAuth响应缺少必要字段 (token或user)');
      throw Exception('MiAuth响应缺少必要字段 (token或user)');
    }

    final accountId = '${user['id']}@$sanitizedHost';
    logger.info('MiAuth认证成功，用户: ${user['username']}, 账户ID: $accountId');

    final repository = ref.read(authRepositoryProvider);

    final account = Account(
      id: accountId, // 复合ID
      platform: 'misskey',
      host: sanitizedHost,
      username: user['username'],
      name: user['name'],
      avatarUrl: user['avatarUrl'],
      token: token,
    );

    await repository.saveAccount(account);

    // Automatically select the new account by saving the ID to repository
    // We avoid calling the provider directly to prevent CircularDependencyError
    // as SelectedMisskeyAccount depends on AuthService.
    await repository.saveSelectedMisskeyId(account.id);

    // Upate state without re-initializing the whole Notifier
    final updatedAccounts = await repository.getAccounts();
    state = AsyncData(updatedAccounts);

    logger.info('Misskey MiAuth认证流程完成');
  }

  /// 通过 Deep Link 回调完成 MiAuth 认证
  ///
  /// 当浏览器重定向到 `nyachi-app://miauth?session=...&host=...` 时，
  /// DeepLinkHandler 解析出 session 和 host，调用此方法完成认证。
  /// 只需一次 /check 调用即可获取 token，无需轮询。
  ///
  /// [host] Misskey 实例主机地址
  /// [session] MiAuth 会话 ID
  ///
  /// 返回 [MiAuthCheckResult] 枚举：成功或网络错误（不应返回 pending）
  Future<MiAuthCheckResult> completeMiAuthFromDeepLink(
    String host,
    String session,
  ) async {
    logger.info('MiAuth Deep Link 回调完成: host=$host, session=$session');
    return checkMiAuth(host, session);
  }

  /// 通过访问令牌（Access Token）直接登录 Misskey 实例
  ///
  /// 验证流程：调用 `/api/i` 端点获取当前用户信息，
  /// 验证成功后保存账户。
  ///
  /// [host] Misskey 实例主机地址
  /// [token] 用户的访问令牌
  ///
  /// 返回 true 表示登录成功，false 或抛出异常表示失败
  Future<bool> loginWithToken(String host, String token) async {
    final sanitizedHost = _sanitizeHost(host);
    logger.info('通过访问令牌登录 Misskey: $sanitizedHost');

    final networkSettings = ref.read(networkSettingsProvider).value;
    final dio = Dio(BaseOptions(
      baseUrl: 'https://$sanitizedHost',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': networkSettings?.effectiveUserAgent,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    try {
      // 使用访问令牌调用 /api/i 获取用户信息
      final response = await dio.post(
        '/api/i',
        data: {'i': token},
      );

      final data = response.data;
      if (data is Map && data['id'] != null) {
        final accountId = '${data['id']}@$sanitizedHost';
        logger.info('令牌验证成功，用户: ${data['username']}, 账户ID: $accountId');

        final account = Account(
          id: accountId,
          platform: 'misskey',
          host: sanitizedHost,
          username: data['username'],
          name: data['name'],
          avatarUrl: data['avatarUrl'],
          token: token,
        );

        await ref.read(authRepositoryProvider).saveAccount(account);
        await ref.read(authRepositoryProvider).saveSelectedMisskeyId(account.id);

        // 刷新状态
        final updatedAccounts = await ref.read(authRepositoryProvider).getAccounts();
        state = AsyncData(updatedAccounts);

        logger.info('MiAuth Token 登录完成');
        return true;
      } else {
        logger.error('令牌验证失败：响应格式异常');
        throw Exception('访问令牌无效：服务器返回异常数据');
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message;
      switch (statusCode) {
        case 401:
        case 403:
          message = '访问令牌无效或已过期';
          break;
        case 404:
          message = '实例地址错误或不支持 Misskey';
          break;
        case 500:
        case 502:
        case 503:
          message = '服务器内部错误，请稍后重试';
          break;
        default:
          message = '网络错误：${e.message}';
      }
      logger.error('MiAuth Token 登录失败: $message (HTTP $statusCode)');
      throw Exception(message);
    } catch (e) {
      if (e is Exception) rethrow;
      logger.error('MiAuth Token 登录非预期错误: $e');
      throw Exception('登录失败：$e');
    }
  }

  /// 删除指定ID的账户
  ///
  /// 删除指定ID的账户信息，删除后会刷新认证服务的状态。
  ///
  /// @param id 要删除的账户ID
  /// @return 无返回值，删除后刷新状态
  Future<void> removeAccount(String id) async {
    logger.info('删除账户，账户ID: $id');
    await ref.read(authRepositoryProvider).removeAccount(id);
    logger.debug('账户删除成功');

    logger.debug('更新认证服务状态');
    final updatedAccounts = await ref
        .read(authRepositoryProvider)
        .getAccounts();
    state = AsyncData(updatedAccounts);

    // Selected accounts will automatically re-evaluate since they watch authServiceProvider
    logger.debug('选中的账户将自动重新评估');
    logger.info('账户删除流程完成');
  }

  /// 重新排列账户顺序
  ///
  /// [orderedIds] - 按期望顺序排列的账户ID列表
  Future<void> reorderAccounts(List<String> orderedIds) async {
    logger.info('重新排列账户顺序 (${orderedIds.length} 个)');
    await ref.read(authRepositoryProvider).reorderAccounts(orderedIds);
    final updatedAccounts = await ref
        .read(authRepositoryProvider)
        .getAccounts();
    state = AsyncData(updatedAccounts);
    logger.info('账户顺序已更新');
  }

  /// 设置主用户（将指定账户移到首位，并设为选中状态）
  ///
  /// [account] 要设为主用户的账户
  Future<void> setPrimaryAccount(Account account) async {
    logger.info('设置主用户: ${account.id}');
    final repository = ref.read(authRepositoryProvider);
    final accounts = await repository.getAccounts();

    // 将目标账户移到首位，其余保持原序
    final others = accounts.where((a) => a.id != account.id).toList();
    final reordered = [account, ...others];
    await repository.reorderAccounts(reordered.map((a) => a.id).toList());

    // 设为选中账户
    await repository.saveSelectedMisskeyId(account.id);

    final updatedAccounts = await repository.getAccounts();
    state = AsyncData(updatedAccounts);
    logger.info('主用户已设置: ${account.id}');
  }

  /// 清理主机地址，提取出域名部分
  String _sanitizeHost(String host) {
    return sanitizeHost(host);
  }
}

/// 选中的Misskey账户提供者
///
/// 管理当前选中的Misskey账户，支持账户切换和自动选择逻辑。
@Riverpod(keepAlive: true)
class SelectedMisskeyAccount extends _$SelectedMisskeyAccount {
  /// 初始化选中的Misskey账户
  ///
  /// 从存储中获取上次选中的Misskey账户ID，如果存在则返回对应的账户，
  /// 否则返回第一个可用的Misskey账户。
  /// 初始化时同时设置缓存管理器和笔记缓存管理器的当前账户ID。
  ///
  /// @return 返回选中的Misskey账户，如果没有则返回null
  @override
  FutureOr<Account?> build() async {
    final accounts = await ref.watch(authServiceProvider.future);

    final repository = ref.read(authRepositoryProvider);

    final selectedId = await repository.getSelectedMisskeyId();

    Account? selectedAccount;
    if (selectedId != null) {
      try {
        selectedAccount = accounts.firstWhere((a) => a.id == selectedId);
      } catch (e) {
        logger.warning('AuthService: Selected account not found, falling back', e);
      }
    }

    selectedAccount ??= accounts
          .where((a) => a.platform == 'misskey')
          .firstOrNull;

    // 设置缓存管理器的当前账户ID
    if (selectedAccount != null) {
      cacheManager.setCurrentAccountId(selectedAccount.id);
      MisskeyTimelineNotifier.cacheManager.setCurrentAccountId(
        selectedAccount.id,
      );
    } else {
      cacheManager.setCurrentAccountId(null);
      MisskeyTimelineNotifier.cacheManager.setCurrentAccountId(null);
    }

    return selectedAccount;
  }

  /// 选择Misskey账户
  ///
  /// 选择指定的Misskey账户作为当前活动账户，并保存选择状态。
  /// 同时更新缓存管理器和笔记缓存管理器的当前账户ID以实现缓存隔离。
  ///
  /// @param account 要选择的账户，必须是Misskey平台的账户
  /// @return 无返回值
  Future<void> select(Account account) async {
    if (account.platform != 'misskey') return;

    state = AsyncData(account);

    await ref.read(authRepositoryProvider).saveSelectedMisskeyId(account.id);

    // 设置缓存管理器的当前账户ID
    cacheManager.setCurrentAccountId(account.id);

    // 设置笔记缓存管理器的当前账户ID
    MisskeyTimelineNotifier.cacheManager.setCurrentAccountId(account.id);
  }
}

@riverpod
Account? selectedAccount(Ref ref) {
  final accountsAsync = ref.watch(authServiceProvider);

  return accountsAsync.maybeWhen(
    data: (accounts) => accounts.isNotEmpty ? accounts.first : null,

    orElse: () => null,
  );
}
