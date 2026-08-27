import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/widgets.dart';

/// شاشة "حول التطبيق"
/// -----------------
/// تعرض معلومات عامة عن النظام: الشعار، الاسم، الإصدار، تاريخ البناء،
/// حزمة التقنيات المستخدمة، قائمة الميزات، تحذير بيانات الدخول الافتراضية،
/// معلومات الترخيص، ورابط المستودع على GitHub.
/// التخطيط متجاوب: عمود واحد على الهواتف وعمودان على الشاشات العريضة،
/// مع إمكانية التمرير الكامل للمحتوى.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // تاريخ البناء (يتم تحديثه يدوياً مع كل إصدار).
  static const String _buildDate = '2026-08-27';

  // رابط المستودع.
  static const String _repoUrl = 'https://github.com/grocery-erp/grocery_erp';

  // معلومات حزمة التقنيات.
  static const List<_TechItem> _techStack = [
    _TechItem('Flutter', '3.27.0', Icons.flutter_dash, AppColors.primary),
    _TechItem('Dart', '3.6.0', Icons.memory, AppColors.accent),
    _TechItem('Drift (SQLite)', 'ORM', Icons.storage, AppColors.secondary),
    _TechItem('Provider', 'State', Icons.dynamic_feed, AppColors.info),
    _TechItem('GoRouter', 'Navigation', Icons.alt_route, AppColors.success),
    _TechItem('intl', 'i18n', Icons.translate, AppColors.warning),
    _TechItem('crypto', 'Hashing', Icons.enhanced_encryption, AppColors.error),
    _TechItem('Decimal', 'Math', Icons.calculate, AppColors.primaryDark),
  ];

  // قائمة الميزات البارزة.
  static const List<_FeatureItem> _features = [
    _FeatureItem(
      'يعمل دون اتصال (Offline-first)',
      'كل البيانات تُخزّن محلياً ويمكن العمل دون إنترنت.',
      Icons.cloud_off,
      AppColors.primary,
    ),
    _FeatureItem(
      'معاملات ذرية',
      'كل عملية مالية تتم داخل Transaction آمنة لا تُكسر.',
      Icons.lock,
      AppColors.success,
    ),
    _FeatureItem(
      'دعم كامل للعربية و RTL',
      'واجهة عربية بالكامل مع تخطيط من اليمين إلى اليسار.',
      Icons.text_format,
      AppColors.accent,
    ),
    _FeatureItem(
      'الوضع الفاتح والداكن',
      'تبديل تلقائي حسب النظام أو يدوي من الإعدادات.',
      Icons.dark_mode,
      AppColors.info,
    ),
    _FeatureItem(
      'نظام صلاحيات متقدم',
      '7 أدوار افتراضية و43 صلاحية موزعة على 10 وحدات.',
      Icons.admin_panel_settings,
      AppColors.secondary,
    ),
    _FeatureItem(
      'تكلفة مرجحة (WAC)',
      'حساب التكلفة بالمتوسط المرجّح بدقة Decimal بلا أخطاء تقريب.',
      Icons.analytics,
      AppColors.warning,
    ),
    _FeatureItem(
      'نسخ احتياطي محلي',
      'تصدير واستيراد كامل قاعدة البيانات بصيغة مضمّاة.',
      Icons.backup,
      AppColors.primaryDark,
    ),
    _FeatureItem(
      'سجل تدقيق كامل',
      'تتبّع كل العمليات الحساسة مع المستخدم والتوقيت.',
      Icons.history_edu,
      AppColors.error,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('حول التطبيق')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, theme),
                const SizedBox(height: 16),
                _buildInfoCard(context, theme),
                const SizedBox(height: 16),
                _buildTechSection(context, theme, isWide),
                const SizedBox(height: 16),
                _buildFeaturesSection(context, theme, isWide),
                const SizedBox(height: 16),
                _buildDefaultCredentialsWarning(context, theme),
                const SizedBox(height: 16),
                _buildLicenseSection(context, theme),
                const SizedBox(height: 16),
                _buildRepoSection(context, theme),
                const SizedBox(height: 24),
                _buildFooter(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================
  // الترويسة + الشعار
  // =====================

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.storefront,
                color: Colors.white,
                size: 52,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.appName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                _VersionChip(
                  label: 'الإصدار ${AppConstants.appVersion}',
                  icon: Icons.tag,
                  color: AppColors.primary,
                ),
                _VersionChip(
                  label: 'البناء $_buildDate',
                  icon: Icons.event,
                  color: AppColors.info,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // بطاقة معلومات سريعة
  // =====================

  Widget _buildInfoCard(BuildContext context, ThemeData theme) {
    return _AboutCard(
      title: 'معلومات التطبيق',
      icon: Icons.info_outline,
      color: AppColors.info,
      children: [
        InfoRow(
          label: 'الاسم',
          value: AppConstants.appName,
          icon: Icons.label_outline,
        ),
        InfoRow(
          label: 'الإصدار',
          value: AppConstants.appVersion,
          icon: Icons.tag,
          valueColor: AppColors.primary,
        ),
        InfoRow(
          label: 'تاريخ البناء',
          value: _buildDate,
          icon: Icons.calendar_today_outlined,
        ),
        InfoRow(
          label: 'العملة الافتراضية',
          value:
              '${AppConstants.defaultCurrency} (${AppConstants.defaultCurrencyCode})',
          icon: Icons.monetization_on_outlined,
        ),
        InfoRow(
          label: 'اللغة الافتراضية',
          value: 'العربية (${AppConstants.defaultLanguageCode})',
          icon: Icons.language,
        ),
      ],
    );
  }

  // =====================
  // قسم التقنيات
  // =====================

  Widget _buildTechSection(
    BuildContext context,
    ThemeData theme,
    bool isWide,
  ) {
    return _AboutCard(
      title: 'حزمة التقنيات',
      icon: Icons.code,
      color: AppColors.accent,
      children: [
        Text(
          'بُني هذا التطبيق باستخدام أحدث تقنيات Flutter والـ ORM الحديثة لضمان الأداء والموثوقية.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 12),
        if (isWide)
          _twoColumnGrid(_techStack, (item) => _TechChip(item: item))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _techStack.map((t) => _TechChip(item: t)).toList(),
          ),
      ],
    );
  }

  // =====================
  // قسم الميزات
  // =====================

  Widget _buildFeaturesSection(
    BuildContext context,
    ThemeData theme,
    bool isWide,
  ) {
    return _AboutCard(
      title: 'أبرز الميزات',
      icon: Icons.star_outline,
      color: AppColors.success,
      children: [
        if (isWide)
          _twoColumnGrid(_features, (item) => _FeatureTile(item: item))
        else
          Column(
            children: _features
                .map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FeatureTile(item: f),
                    ))
                .toList(),
          ),
      ],
    );
  }

  // =====================
  // تحذير بيانات الدخول الافتراضية
  // =====================

  Widget _buildDefaultCredentialsWarning(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 24),
              const SizedBox(width: 8),
              Text(
                'تنبيه أمني هام',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'يأتي التطبيق بمستخدم افتراضي للدخول الإداري الأولي:\n'
            '• اسم المستخدم: admin\n'
            '• كلمة المرور: admin123',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'يجب تغيير كلمة المرور الافتراضية فور تسجيل الدخول الأول من خلال '
            '«تغيير كلمة المرور» في شاشة الإعدادات، لتجنب الوصول غير المصرّح به.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondaryDark,
            ),
          ),
        ],
      ),
    );
  }

  // =====================
  // قسم الترخيص
  // =====================

  Widget _buildLicenseSection(BuildContext context, ThemeData theme) {
    return _AboutCard(
      title: 'الترخيص',
      icon: Icons.gavel_outlined,
      color: AppColors.secondary,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
              ),
              child: Text(
                'MIT License',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'هذا المشروع مرخّص تحت رخصة MIT. يمكنك استخدامه وتعديله وتوزيعه '
          'بحرية مع الإبقاء على إشعار حقوق النشر الأصلي.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  // =====================
  // رابط المستودع
  // =====================

  Widget _buildRepoSection(BuildContext context, ThemeData theme) {
    return _AboutCard(
      title: 'المستودع',
      icon: Icons.code_rounded,
      color: AppColors.primaryDark,
      children: [
        Row(
          children: [
            const Icon(Icons.open_in_new, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _copyRepoUrl(context),
                child: Text(
                  _repoUrl,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'اضغط على الرابط لنسخه. ساهم في تحسين المشروع عبر الإبلاغ عن الأخطاء '
          'أو إرسال اقتراحاتك.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  void _copyRepoUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: _repoUrl));
    showSuccessSnackBar(context, 'تم نسخ رابط المستودع');
  }

  Widget _buildFooter(ThemeData theme) {
    return Center(
      child: Text(
        '© 2026 ${AppConstants.appName}\nصُنع بشغف ❤️ باستخدام Flutter',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondaryLight,
        ),
      ),
    );
  }

  // =====================
  // مساعد تخطيط عمودين
  // =====================

  Widget _twoColumnGrid<T>(
    List<T> items,
    Widget Function(T) builder,
  ) {
    final half = (items.length / 2).ceil();
    final left = items.sublist(0, half);
    final right = items.sublist(half);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: left
                .map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 4),
                      child: builder(i),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: Column(
            children: right
                .map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8, right: 4),
                      child: builder(i),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
//  مكوّنات مساعدة
// ============================================================================

class _VersionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _VersionChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechItem {
  final String name;
  final String role;
  final IconData icon;
  final Color color;
  const _TechItem(this.name, this.role, this.icon, this.color);
}

class _TechChip extends StatelessWidget {
  final _TechItem item;
  const _TechChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: item.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 16, color: item.color),
          const SizedBox(width: 6),
          Text(
            item.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            item.role,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  const _FeatureItem(this.title, this.description, this.icon, this.color);
}

class _FeatureTile extends StatelessWidget {
  final _FeatureItem item;
  const _FeatureTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: item.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  بطاقة قسم
// ============================================================================

class _AboutCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _AboutCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
