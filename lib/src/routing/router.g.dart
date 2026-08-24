// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 提供应用程序的GoRouter实例
///
/// 定义了应用程序的所有路由配置，包括初始位置和各个页面的路由路径。
/// 使用StatefulShellRoute实现底部导航栏的状态保持。
///
/// [ref] - Riverpod的Ref，用于访问和监听状态
///
/// 返回配置好的GoRouter实例

@ProviderFor(goRouter)
final goRouterProvider = GoRouterProvider._();

/// 提供应用程序的GoRouter实例
///
/// 定义了应用程序的所有路由配置，包括初始位置和各个页面的路由路径。
/// 使用StatefulShellRoute实现底部导航栏的状态保持。
///
/// [ref] - Riverpod的Ref，用于访问和监听状态
///
/// 返回配置好的GoRouter实例

final class GoRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// 提供应用程序的GoRouter实例
  ///
  /// 定义了应用程序的所有路由配置，包括初始位置和各个页面的路由路径。
  /// 使用StatefulShellRoute实现底部导航栏的状态保持。
  ///
  /// [ref] - Riverpod的Ref，用于访问和监听状态
  ///
  /// 返回配置好的GoRouter实例
  GoRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'goRouterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$goRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return goRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$goRouterHash() => r'808179cde87945d63d6c32b48140f06378e55740';
