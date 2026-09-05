// 认证相关的数据仓库
//
// 该文件包含AuthRepository类，负责处理账户信息的持久化存储和检索，
// 使用shared_preferences进行存储以确保在所有平台（特别是Linux）上的可靠性。
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '/src/core/utils/logger.dart';
import '/src/features/auth/domain/account.dart';

part 'auth_repository.g.dart';

/// 认证仓库类
///
/// 负责处理账户信息的持久化存储和检索，支持添加、获取和删除账户。
class AuthRepository {
  /// SharedPreferences实例，用于持久化存储账户信息
  final SharedPreferences _prefs;

  /// 存储账户信息的密钥
  static const _kAccountsKey = 'cyani_accounts';
  static const _kSelectedMisskeyIdKey = 'cyani_selected_misskey_id';

  /// 创建一个新的AuthRepository实例
  ///
  /// [_prefs] - SharedPreferences实例
  AuthRepository(this._prefs);

  /// 获取所有已保存的账户
  ///
  /// 返回包含所有账户的Future列表
  Future<List<Account>> getAccounts() async {
    logger.info('AuthRepository: Getting all accounts');
    final jsonString = _prefs.getString(_kAccountsKey);
    if (jsonString == null) {
      logger.info('AuthRepository: No accounts found');
      return [];
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final accounts = jsonList.map((e) => Account.fromJson(e)).toList();
      logger.info(
        'AuthRepository: Successfully retrieved ${accounts.length} accounts',
      );
      return accounts;
    } catch (e) {
      logger.error('AuthRepository: Error decoding accounts data', e);
      // 在数据损坏的情况下，返回空列表
      return [];
    }
  }

  Future<String?> getSelectedMisskeyId() async {
    logger.info('AuthRepository: Getting selected Misskey account ID');
    final id = _prefs.getString(_kSelectedMisskeyIdKey);
    logger.info('AuthRepository: Selected Misskey account ID: $id');
    return id;
  }

  Future<void> saveSelectedMisskeyId(String id) async {
    logger.info('AuthRepository: Saving selected Misskey account ID: $id');
    await _prefs.setString(_kSelectedMisskeyIdKey, id);
    logger.info(
      'AuthRepository: Successfully saved selected Misskey account ID',
    );
  }

  /// 保存或更新账户
  ///
  /// [account] - 要保存的账户实例
  Future<void> saveAccount(Account account) async {
    logger.info(
      'AuthRepository: Saving account: ${account.id} (${account.platform})',
    );
    final accounts = await getAccounts();
    // 如果存在相同ID的账户，则替换它（更新场景）
    final newAccounts = [...accounts.where((a) => a.id != account.id), account];

    try {
      await _prefs.setString(
        _kAccountsKey,
        jsonEncode(newAccounts.map((e) => e.toJson()).toList()),
      );
      logger.info('AuthRepository: Successfully saved account: ${account.id}');
    } catch (e) {
      logger.error('AuthRepository: Error saving account: ${account.id}', e);
      rethrow;
    }
  }

  /// 删除指定ID的账户
  ///
  /// [id] - 要删除的账户ID
  Future<void> removeAccount(String id) async {
    logger.info('AuthRepository: Removing account: $id');
    final accounts = await getAccounts();
    final newAccounts = accounts.where((a) => a.id != id).toList();

    try {
      await _prefs.setString(
        _kAccountsKey,
        jsonEncode(newAccounts.map((e) => e.toJson()).toList()),
      );
      logger.info('AuthRepository: Successfully removed account: $id');
      logger.info('AuthRepository: Remaining accounts: ${newAccounts.length}');
    } catch (e) {
      logger.error('AuthRepository: Error removing account: $id', e);
      rethrow;
    }
  }

  /// 按指定顺序重新排列账户
  ///
  /// [orderedIds] - 按期望顺序排列的账户ID列表
  Future<void> reorderAccounts(List<String> orderedIds) async {
    logger.info('AuthRepository: Reordering accounts (${orderedIds.length} items)');
    final accounts = await getAccounts();
    final accountMap = {for (final a in accounts) a.id: a};
    final reordered = orderedIds
        .where(accountMap.containsKey)
        .map((id) => accountMap[id]!)
        .toList();

    // 追加不在 orderedIds 中的账户（防御性处理）
    for (final a in accounts) {
      if (!orderedIds.contains(a.id)) {
        reordered.add(a);
      }
    }

    try {
      await _prefs.setString(
        _kAccountsKey,
        jsonEncode(reordered.map((e) => e.toJson()).toList()),
      );
      logger.info('AuthRepository: Successfully reordered accounts');
    } catch (e) {
      logger.error('AuthRepository: Error reordering accounts', e);
      rethrow;
    }
  }
}

/// 提供FlutterSecureStorage实例的Riverpod提供者
@Riverpod(keepAlive: true)
FlutterSecureStorage secureStorage(Ref ref) {
  return const FlutterSecureStorage();
}

/// 提供SharedPreferences实例的Riverpod提供者
/// 必须在 main() 中初始化并覆盖
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) {
  throw UnimplementedError();
}

/// 提供AuthRepository实例的Riverpod提供者
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthRepository(prefs);
}
