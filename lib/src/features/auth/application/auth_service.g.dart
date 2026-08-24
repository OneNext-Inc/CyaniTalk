// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 认证服务类
///
/// 负责处理用户认证流程，包括Misskey的MiAuth流程，
/// 管理认证状态和账户信息。

@ProviderFor(AuthService)
final authServiceProvider = AuthServiceProvider._();

/// 认证服务类
///
/// 负责处理用户认证流程，包括Misskey的MiAuth流程，
/// 管理认证状态和账户信息。
final class AuthServiceProvider
    extends $AsyncNotifierProvider<AuthService, List<Account>> {
  /// 认证服务类
  ///
  /// 负责处理用户认证流程，包括Misskey的MiAuth流程，
  /// 管理认证状态和账户信息。
  AuthServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authServiceHash();

  @$internal
  @override
  AuthService create() => AuthService();
}

String _$authServiceHash() => r'94fe4663207b28225f1c908ba2f339027cc2489a';

/// 认证服务类
///
/// 负责处理用户认证流程，包括Misskey的MiAuth流程，
/// 管理认证状态和账户信息。

abstract class _$AuthService extends $AsyncNotifier<List<Account>> {
  FutureOr<List<Account>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Account>>, List<Account>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Account>>, List<Account>>,
              AsyncValue<List<Account>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 选中的Misskey账户提供者
///
/// 管理当前选中的Misskey账户，支持账户切换和自动选择逻辑。

@ProviderFor(SelectedMisskeyAccount)
final selectedMisskeyAccountProvider = SelectedMisskeyAccountProvider._();

/// 选中的Misskey账户提供者
///
/// 管理当前选中的Misskey账户，支持账户切换和自动选择逻辑。
final class SelectedMisskeyAccountProvider
    extends $AsyncNotifierProvider<SelectedMisskeyAccount, Account?> {
  /// 选中的Misskey账户提供者
  ///
  /// 管理当前选中的Misskey账户，支持账户切换和自动选择逻辑。
  SelectedMisskeyAccountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedMisskeyAccountProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedMisskeyAccountHash();

  @$internal
  @override
  SelectedMisskeyAccount create() => SelectedMisskeyAccount();
}

String _$selectedMisskeyAccountHash() =>
    r'c190af268f56bc317c326846ce4af2c8f465051c';

/// 选中的Misskey账户提供者
///
/// 管理当前选中的Misskey账户，支持账户切换和自动选择逻辑。

abstract class _$SelectedMisskeyAccount extends $AsyncNotifier<Account?> {
  FutureOr<Account?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Account?>, Account?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Account?>, Account?>,
              AsyncValue<Account?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(selectedAccount)
final selectedAccountProvider = SelectedAccountProvider._();

final class SelectedAccountProvider
    extends $FunctionalProvider<Account?, Account?, Account?>
    with $Provider<Account?> {
  SelectedAccountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedAccountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedAccountHash();

  @$internal
  @override
  $ProviderElement<Account?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Account? create(Ref ref) {
    return selectedAccount(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Account? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Account?>(value),
    );
  }
}

String _$selectedAccountHash() => r'8ee48b014145c2905604890b91a3e8b3ab03159b';
