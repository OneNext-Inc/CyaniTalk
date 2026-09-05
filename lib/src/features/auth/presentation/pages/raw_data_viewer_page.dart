import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Nyachi/src/features/auth/domain/account.dart';
import 'package:Nyachi/src/features/profile/presentation/widgets/user_details_view.dart';
import 'package:Nyachi/src/shared/widgets/cyani_loading_indicator.dart';
import 'package:Nyachi/src/shared/widgets/error_state.dart';

/// 原始数据查看器页面（移动端独立页面）
///
/// 展示指定账户的原始 JSON 数据，支持滚动查看和文本选择。
/// 桌面端由 showAdaptiveSheet → SideSheet 承载，移动端 push 此页面。
class RawDataViewerPage extends ConsumerWidget {
  final Account account;

  const RawDataViewerPage({super.key, required this.account});

  /// 移动端通过 MaterialPageRoute 打开
  static void open(BuildContext context, Account account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RawDataViewerPage(account: account),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(userDetailsProvider(account));
    final displayName = (account.name != null && account.name!.isNotEmpty)
        ? account.name!
        : (account.username ?? 'Unknown');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'accounts_raw_data_title'.tr(
            namedArgs: {'username': displayName},
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'accounts_copy_data'.tr(),
            onPressed: detailsAsync.hasValue
                ? () {
                    final jsonString = const JsonEncoder.withIndent('  ')
                        .convert(detailsAsync.value);
                    Clipboard.setData(ClipboardData(text: jsonString));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('accounts_data_copied'.tr()),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
      body: detailsAsync.when(
        data: (data) => _buildContent(context, data),
        loading: () => const Center(child: CyaniLoadingIndicator()),
        error: (err, _) => Center(
          child: ErrorState(message: err.toString()),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, dynamic data) {
    final theme = Theme.of(context);
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(data);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        jsonString,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'JetBrainsMono',
          height: 1.5,
        ),
      ),
    );
  }
}
