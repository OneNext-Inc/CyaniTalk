// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'font_settings_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 字体设置状态管理器

@ProviderFor(FontSettingsNotifier)
final fontSettingsProvider = FontSettingsNotifierProvider._();

/// 字体设置状态管理器
final class FontSettingsNotifierProvider
    extends $AsyncNotifierProvider<FontSettingsNotifier, FontSettings> {
  /// 字体设置状态管理器
  FontSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fontSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fontSettingsNotifierHash();

  @$internal
  @override
  FontSettingsNotifier create() => FontSettingsNotifier();
}

String _$fontSettingsNotifierHash() =>
    r'7709b4a7f9357eb2fd062f3ba1830e7902d1cd05';

/// 字体设置状态管理器

abstract class _$FontSettingsNotifier extends $AsyncNotifier<FontSettings> {
  FutureOr<FontSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<FontSettings>, FontSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<FontSettings>, FontSettings>,
              AsyncValue<FontSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 提供当前字体族名的 Provider

@ProviderFor(currentFontFamily)
final currentFontFamilyProvider = CurrentFontFamilyProvider._();

/// 提供当前字体族名的 Provider

final class CurrentFontFamilyProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// 提供当前字体族名的 Provider
  CurrentFontFamilyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentFontFamilyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentFontFamilyHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return currentFontFamily(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$currentFontFamilyHash() => r'c322f6870e8dde01c5783a9b6a62cd3eae5da5b5';
