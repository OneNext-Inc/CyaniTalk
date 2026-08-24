// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AppearanceSettingsNotifier)
final appearanceSettingsProvider = AppearanceSettingsNotifierProvider._();

final class AppearanceSettingsNotifierProvider
    extends
        $AsyncNotifierProvider<AppearanceSettingsNotifier, AppearanceSettings> {
  AppearanceSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceSettingsNotifierHash();

  @$internal
  @override
  AppearanceSettingsNotifier create() => AppearanceSettingsNotifier();
}

String _$appearanceSettingsNotifierHash() =>
    r'2fc32606ad1bcb1f13be69d9ceae1705d19e7e65';

abstract class _$AppearanceSettingsNotifier
    extends $AsyncNotifier<AppearanceSettings> {
  FutureOr<AppearanceSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AppearanceSettings>, AppearanceSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppearanceSettings>, AppearanceSettings>,
              AsyncValue<AppearanceSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
