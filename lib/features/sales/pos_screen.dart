import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../../domain/services/sales_service.dart';
import '../shared/widgets.dart';

/// شاشة نقطة البيع (الكاشير)
/// -------------------------
/// - تخطيط متجاوب: على الشاشات العريضة تظهر السلة كلوحة جانبية،
///   وعلى الهواتف تظهر السلة كشريط سفلي مع لوحة منبثقة.
/// - بحث فوري بالاسم/الباركود (مع تأخير 300ms لتقليل الاستعلامات).
/// - إدخال الباركود كاملاً ثم Enter يضيف المنتج مباشرة للسلة.
/// - شبكة منتجات ببطاقات تعرض الاسم والسعر والمخزون (مع تحذير نقص المخزون).
/// - سلة قابلة للتعديل (زيادة/إنقاص/إزالة) مع أزرار كبيرة مناسبة للمس.
/// - دعم الدفع نقدي / آجل / مختلط مع الخصم وحساب الباقي والمتبقي.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<Product> _products = [];
  final List<Customer> _customers = [];
  final List<CartItem> _cart = [];

  // ===== حالة الفاتورة =====
  int? _selectedCustomerId;
  String _paymentType = PaymentType.cash;
  bool _paidTouched = false; // هل عدّل المستخدم حقل المدفوع يدوياً؟
  bool _preventNegativeStock = true;
  bool _allowOverpayment = false;

  // ===== حالة الواجهة =====
  bool _loadingProducts = true;
  bool _processing = false;
  bool _showMobileCart = false;

  // =====================
  // دورة الحياة
  // =====================

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCustomers();
    _refreshProducts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  // =====================
  // حسابات الإجماليات
  // =====================

  num get _subtotal => _cart.fold<num>(0, (sum, item) => sum + item.total);

  num get _discount =>
      math.max(0, num.tryParse(_discountController.text.trim()) ?? 0);

  num get _total => math.max(0, _subtotal - _discount);

  /// المدفوع فعلياً (البيع الآجل لا يدفع نقدياً عند الفاتورة)
  num get _paid {
    if (_paymentType == PaymentType.credit) return 0;
    return math.max(0, num.tryParse(_paidController.text.trim()) ?? 0);
  }

  /// الباقي المطلوب رده للعميل
  num get _change => _paid - _total;

  /// المتبقي كدين على العميل
  num get _remaining {
    if (_paymentType == PaymentType.credit) return _total;
    if (_paymentType == PaymentType.mixed) return math.max(0, _total - _paid);
    return 0;
  }

  /// هل الفاتورة تحتاج عميلاً (بيع آجل كلي أو جزئي)؟
  bool get _needsCustomer => _remaining > 0;

  CartItem? _findCartItem(int productId) {
    for (final item in _cart) {
      if (item.product.id == productId) return item;
    }
    return null;
  }

  num _qtyInCart(int productId) => _findCartItem(productId)?.quantity ?? 0;

  // =====================
  // تحميل البيانات
  // =====================

  Future<void> _loadSettings() async {
    try {
      final settings = await ServiceLocator.database.settingDao.getSettings();
      if (!mounted || settings == null) return;
      setState(() {
        _preventNegativeStock = settings.preventNegativeStock;
        _allowOverpayment = settings.allowOverpayment;
      });
    } catch (_) {
      // تجاهل - سنستخدم القيم الافتراضية
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await ServiceLocator.database.customerDao.getAll();
      if (!mounted) return;
      setState(() {
        _customers
          ..clear()
          ..addAll(customers.where((c) => c.isActive));
        // إلغاء اختيار عميل لم يعد موجوداً/نشطاً
        if (_selectedCustomerId != null &&
            !_customers.any((c) => c.id == _selectedCustomerId)) {
          _selectedCustomerId = null;
        }
      });
    } catch (_) {
      // قائمة العملاء اختيارية - نتجاهل الخطأ
    }
  }

  Future<void> _refreshProducts() async {
    final query = _searchController.text.trim();
    try {
      final List<Product> products;
      if (query.isEmpty) {
        products = await ServiceLocator.database.productDao.getActive();
      } else {
        products = await ServiceLocator.database.productDao.search(query);
      }
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(products);
        _loadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProducts = false);
      showErrorSnackBar(context, 'تعذر تحميل المنتجات: $e');
    }
  }

  // =====================
  // البحث والباركود
  // =====================

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      _refreshProducts,
    );
  }

  /// عند الضغط على Enter: إن كان النص باركوداً مطابقاً يضاف المنتج مباشرة
  Future<void> _onSearchSubmitted(String value) async {
    final query = value.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      _refreshProducts();
      return;
    }

    Product? product;
    try {
      product = await ServiceLocator.database.productDao.findByBarcode(query);
    } catch (_) {
      product = null;
    }
    if (!mounted) return;

    if (product != null) {
      _searchController.clear();
      _addToCart(product);
      _refreshProducts();
      return;
    }
    _refreshProducts();
  }

  // =====================
  // عمليات السلة
  // =====================

  void _addToCart(Product product) {
    final existing = _findCartItem(product.id);
    if (existing != null) {
      _incrementQuantity(existing);
      return;
    }
    if (_preventNegativeStock && product.currentStock <= 0) {
      showErrorSnackBar(
          context, 'المنتج "${product.name}" غير متوفر في المخزون');
      return;
    }
    setState(() {
      _cart.add(CartItem(
        product: product,
        quantity: 1,
        unitPrice: product.sellingPrice,
      ));
      _syncPaidField();
    });
  }

  void _incrementQuantity(CartItem item) {
    if (_preventNegativeStock &&
        item.quantity + 1 > item.product.currentStock) {
      showWarningSnackBar(
        context,
        'لا يمكن تجاوز المخزون المتاح من "${item.product.name}" '
        '(${FormatUtils.formatQuantity(item.product.currentStock)})',
      );
      return;
    }
    setState(() {
      item.quantity += 1;
      _syncPaidField();
    });
  }

  void _decrementQuantity(CartItem item) {
    if (item.quantity <= 1) {
      _removeFromCart(item);
      return;
    }
    setState(() {
      item.quantity -= 1;
      _syncPaidField();
    });
  }

  void _removeFromCart(CartItem item) {
    setState(() {
      _cart.removeWhere((c) => c.product.id == item.product.id);
      _syncPaidField();
    });
  }

  /// تعديل الكمية يدوياً (مفيد للمنتجات الموزونة - كميات عشرية)
  Future<void> _editQuantity(CartItem item) async {
    final controller = TextEditingController(
      text: item.quantity == item.quantity.truncate()
          ? item.quantity.truncate().toString()
          : item.quantity.toString(),
    );
    final num? value = await showDialog<num>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          item.product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          ],
          decoration: const InputDecoration(
            labelText: 'الكمية المطلوبة',
            hintText: 'مثال: 1 أو 1.5',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(num.tryParse(controller.text.trim())),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;

    if (value <= 0) {
      _removeFromCart(item);
      return;
    }
    if (_preventNegativeStock && value > item.product.currentStock) {
      showWarningSnackBar(
        context,
        'الكمية تتجاوز المخزون المتاح '
        '(${FormatUtils.formatQuantity(item.product.currentStock)})',
      );
      return;
    }
    setState(() {
      item.quantity = value;
      _syncPaidField();
    });
  }

  void _setPaymentType(String type) {
    if (_paymentType == type) return;
    setState(() {
      _paymentType = type;
      _paidTouched = false;
      if (type == PaymentType.credit) {
        _paidController.clear();
      } else {
        _syncPaidField();
      }
    });
  }

  /// تعبئة حقل المدفوع بكامل المبلغ
  void _fillPaidWithTotal() {
    setState(() {
      _paidTouched = false;
      _syncPaidField(force: true);
    });
  }

  /// مزامنة حقل المدفوع مع الإجمالي تلقائياً (للدفع النقدي)
  void _syncPaidField({bool force = false}) {
    if (!force && _paidTouched) return;
    if (!force && _paymentType != PaymentType.cash) return;
    final t = _total;
    _paidController.text =
        t == t.truncate() ? t.truncate().toString() : t.toStringAsFixed(2);
  }

  Future<void> _confirmClearCart() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'إفراغ السلة',
      message: 'هل تريد إزالة جميع المنتجات من السلة؟',
      confirmText: 'إفراغ',
      isDanger: true,
    );
    if (!mounted || confirmed != true) return;
    _clearCart();
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _discountController.clear();
      _paidController.clear();
      _paidTouched = false;
      _selectedCustomerId = null;
      _paymentType = PaymentType.cash;
      _showMobileCart = false;
    });
  }

  // =====================
  // إتمام البيع
  // =====================

  Future<void> _completeSale() async {
    if (_processing || _cart.isEmpty) return;

    // 1) التحقق من الخصم
    final discount = _discount;
    if (discount > _subtotal) {
      showErrorSnackBar(context, 'قيمة الخصم لا يمكن أن تتجاوز مجموع الفاتورة');
      return;
    }

    // 2) التحقق من الكميات مقابل المخزون
    if (_preventNegativeStock) {
      for (final item in _cart) {
        if (item.quantity > item.product.currentStock) {
          showErrorSnackBar(
            context,
            'الكمية المطلوبة من "${item.product.name}" '
            '(${FormatUtils.formatQuantity(item.quantity)}) تتجاوز المخزون المتاح '
            '(${FormatUtils.formatQuantity(item.product.currentStock)})',
          );
          return;
        }
      }
    }

    final total = _total;
    final paid = _paid;

    // 3) التحقق من الدفع
    if (_paymentType == PaymentType.cash && paid < total) {
      showErrorSnackBar(context, 'المبلغ المدفوع أقل من الإجمالي المستحق');
      return;
    }
    if (_paymentType == PaymentType.mixed &&
        paid > total &&
        !_allowOverpayment) {
      showErrorSnackBar(context, 'المبلغ المدفوع أكبر من الإجمالي المستحق');
      return;
    }

    // 4) البيع الآجل يتطلب عميلاً
    if (_needsCustomer && _selectedCustomerId == null) {
      showErrorSnackBar(context, 'البيع الآجل يتطلب اختيار عميل أولاً');
      return;
    }

    // 5) المستخدم الحالي
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      showErrorSnackBar(context, 'انتهت الجلسة، يرجى تسجيل الدخول من جديد');
      return;
    }

    setState(() => _processing = true);
    try {
      final result = await ServiceLocator.salesService.createSale(
        userId: user.id,
        cart: List<CartItem>.of(_cart),
        customerId: _selectedCustomerId,
        discount: discount,
        tax: 0,
        paymentType: _paymentType,
        paidAmount: paid,
        requireStock: _preventNegativeStock,
      );
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        'تم إتمام البيع بنجاح — فاتورة ${result.sale.invoiceNumber} '
        'بمبلغ ${FormatUtils.formatMoneyAr(result.sale.total)}',
      );
      _clearCart();
      // تحديث المخزون المعروض وأرصدة العملاء بعد البيع
      await _refreshProducts();
      await _loadCustomers();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildProductArea()),
              _buildSideCartPanel(constraints),
            ],
          );
        }
        return _buildMobileLayout(constraints);
      },
    );
  }

  // ---------------------
  // منطقة المنتجات
  // ---------------------

  Widget _buildProductArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          _buildSearchBar(),
          const SizedBox(height: 10),
          Expanded(child: _buildProductGrid()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (_) => _onSearchChanged(),
            onSubmitted: _onSearchSubmitted,
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الباركود...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    tooltip: 'مسح البحث',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _refreshProducts();
                    },
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'تحديث قائمة المنتجات',
          onPressed: _refreshProducts,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    if (_loadingProducts) {
      return const LoadingIndicator(message: 'جارٍ تحميل المنتجات...');
    }
    if (_products.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message: searching
            ? 'لا توجد منتجات مطابقة لبحثك'
            : 'لا توجد منتجات نشطة بعد',
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshProducts,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.2,
        ),
        itemCount: _products.length,
        itemBuilder: (context, index) => _buildProductCard(_products[index]),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final qtyInCart = _qtyInCart(product.id);
    final stockLevel = product.currentStock;
    final outOfStock = stockLevel <= 0;
    final lowStock = !outOfStock && stockLevel <= product.minimumStock;
    final disabled = outOfStock && _preventNegativeStock;

    final stockColor = outOfStock
        ? AppColors.error
        : lowStock
            ? AppColors.secondary
            : AppColors.textSecondaryLight;
    final stockText = outOfStock
        ? 'نفذ المخزون'
        : lowStock
            ? 'مخزون منخفض: ${FormatUtils.formatQuantity(stockLevel)}'
            : 'المتاح: ${FormatUtils.formatQuantity(stockLevel)}';

    return Card(
      key: ValueKey('product-${product.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : () => _addToCart(product),
        child: Stack(
          children: [
            Opacity(
              opacity: disabled ? 0.55 : 1,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      FormatUtils.formatMoneyAr(product.sellingPrice),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          outOfStock
                              ? Icons.error_outline
                              : lowStock
                                  ? Icons.warning_amber_rounded
                                  : Icons.inventory_2_outlined,
                          size: 14,
                          color: stockColor,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            stockText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: stockColor,
                              fontWeight: (outOfStock || lowStock) && !disabled
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (qtyInCart > 0)
              PositionedDirectional(
                top: 6,
                end: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    FormatUtils.formatQuantity(qtyInCart),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------
  // لوحة السلة الجانبية (شاشات عريضة)
  // ---------------------

  Widget _buildSideCartPanel(BoxConstraints constraints) {
    final theme = Theme.of(context);
    return Container(
      width: math.min(420.0, constraints.maxWidth * 0.42),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: BorderDirectional(
          start: BorderSide(color: theme.dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(-3, 0),
          ),
        ],
      ),
      child: _buildCartScaffold(showClose: false),
    );
  }

  // ---------------------
  // تخطيط الهاتف: شريط سفلي + لوحة منبثقة
  // ---------------------

  Widget _buildMobileLayout(BoxConstraints constraints) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _buildProductArea()),
            if (_cart.isNotEmpty) _buildMobileCartBar(),
          ],
        ),
        if (_showMobileCart) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showMobileCart = false),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildMobileCartSheet(constraints),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileCartBar() {
    final totalQuantity =
        _cart.fold<num>(0, (sum, item) => sum + item.quantity);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Badge(
                  label: Text('${_cart.length}'),
                  backgroundColor: AppColors.secondary,
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${FormatUtils.formatQuantity(totalQuantity)} عنصر في السلة',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    Text(
                      FormatUtils.formatMoneyAr(_total),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () => setState(() => _showMobileCart = true),
                icon: const Icon(Icons.reorder),
                label: const Text('السلة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCartSheet(BoxConstraints constraints) {
    final theme = Theme.of(context);
    final panelHeight = math.min(constraints.maxHeight * 0.92, 760.0);
    return Material(
      elevation: 12,
      color: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: panelHeight,
        child: _buildCartScaffold(showClose: true),
      ),
    );
  }

  // ---------------------
  // هيكل السلة المشترك
  // ---------------------

  Widget _buildCartScaffold({required bool showClose}) {
    return Column(
      children: [
        _buildCartHeader(showClose: showClose),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: _cart.isEmpty
              ? const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message: 'السلة فارغة، انقر على أي منتج لإضافته',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  children: [
                    for (final item in _cart) _buildCartTile(item),
                    const SizedBox(height: 8),
                    _buildCartSummaryCard(),
                  ],
                ),
        ),
        _buildCheckoutBar(),
      ],
    );
  }

  Widget _buildCartHeader({required bool showClose}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'سلة البيع',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${_cart.length} ${_cart.length == 1 ? 'منتج' : 'منتجات'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          if (_cart.isNotEmpty)
            IconButton(
              tooltip: 'إفراغ السلة',
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: AppColors.error),
              onPressed: _confirmClearCart,
            ),
          if (showClose)
            IconButton(
              tooltip: 'إغلاق',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _showMobileCart = false),
            ),
        ],
      ),
    );
  }

  Widget _buildCartTile(CartItem item) {
    final overStock =
        _preventNegativeStock && item.quantity > item.product.currentStock;
    return Container(
      key: ValueKey('cart-${item.product.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              IconButton(
                tooltip: 'إزالة من السلة',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 22),
                onPressed: () => _removeFromCart(item),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${FormatUtils.formatMoneyAr(item.unitPrice)} × '
                      '${FormatUtils.formatQuantity(item.quantity)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      FormatUtils.formatMoneyAr(item.total),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              _buildQuantityStepper(item),
            ],
          ),
          if (overStock)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.error),
                  SizedBox(width: 4),
                  Text(
                    'الكمية تتجاوز المخزون المتاح',
                    style: TextStyle(fontSize: 11, color: AppColors.error),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuantityStepper(CartItem item) {
    final canIncrease =
        !_preventNegativeStock || item.quantity < item.product.currentStock;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'إنقاص الكمية',
          icon: const Icon(Icons.remove_circle_outline),
          color: AppColors.error,
          iconSize: 28,
          onPressed: () => _decrementQuantity(item),
        ),
        Tooltip(
          message: 'تعديل الكمية',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _editQuantity(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                color: AppColors.primary.withValues(alpha: 0.06),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    FormatUtils.formatQuantity(item.quantity),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.edit,
                    size: 13,
                    color: AppColors.textSecondaryLight,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'زيادة الكمية',
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.primary,
          iconSize: 28,
          onPressed: canIncrease ? () => _incrementQuantity(item) : null,
        ),
      ],
    );
  }

  // ---------------------
  // تفاصيل الدفع
  // ---------------------

  Widget _buildCartSummaryCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // العميل
        DropdownButtonFormField<int?>(
          value: _selectedCustomerId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'العميل',
            helperText: 'اختياري - مطلوب للبيع الآجل',
            prefixIcon: Icon(Icons.person_outline),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('عميل نقدي'),
            ),
            ..._customers.map(
              (customer) => DropdownMenuItem<int?>(
                value: customer.id,
                child: Text(
                  customer.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _selectedCustomerId = value),
        ),
        const SizedBox(height: 12),

        // نوع الدفع
        _buildPaymentSelector(),
        if (_needsCustomer && _selectedCustomerId == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: const [
                Icon(Icons.info_outline, size: 14, color: AppColors.secondary),
                SizedBox(width: 4),
                Text(
                  'البيع الآجل يتطلب اختيار عميل',
                  style: TextStyle(fontSize: 11, color: AppColors.secondary),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // الخصم والمدفوع
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _discountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'الخصم',
                  hintText: '0',
                  prefixIcon: Icon(Icons.discount_outlined),
                ),
                onChanged: (_) {
                  // مزامنة المدفوع إن لم يعدّله المستخدم يدوياً
                  if (!_paidTouched && _paymentType == PaymentType.cash) {
                    _syncPaidField();
                  }
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _paymentType == PaymentType.credit
                  ? _buildCreditInfoTile()
                  : TextFormField(
                      controller: _paidController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'المبلغ المدفوع',
                        hintText: '0',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'دفع كامل المبلغ',
                          icon: const Icon(Icons.request_quote_outlined),
                          onPressed: _cart.isEmpty ? null : _fillPaidWithTotal,
                        ),
                      ),
                      onChanged: (_) {
                        _paidTouched = true;
                        setState(() {});
                      },
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // الإجماليات
        _buildTotalsCard(),
      ],
    );
  }

  Widget _buildCreditInfoTile() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5)),
        color: AppColors.secondary.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: AppColors.secondaryDark, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'البيع الآجل - كامل المبلغ دين على العميل',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.secondaryDark,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSelector() {
    final options = <(String, String, IconData)>[
      (PaymentType.cash, 'نقدي', Icons.payments_outlined),
      (PaymentType.credit, 'آجل', Icons.schedule_outlined),
      (PaymentType.mixed, 'مختلط', Icons.account_balance_wallet_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                  end: i == options.length - 1 ? 0 : 6),
              child: _buildPaymentOption(options[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentOption((String, String, IconData) option) {
    final (type, label, icon) = option;
    final selected = _paymentType == type;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _setPaymentType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? AppColors.primary : Theme.of(context).dividerColor,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color:
                  selected ? AppColors.primary : AppColors.textSecondaryLight,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color:
                    selected ? AppColors.primary : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsCard() {
    final change = _change;
    final remaining = _remaining;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          InfoRow(
            label: 'المجموع الفرعي',
            value: FormatUtils.formatMoneyAr(_subtotal),
          ),
          if (_discount > 0)
            InfoRow(
              label: 'الخصم',
              value: '- ${FormatUtils.formatMoneyAr(_discount)}',
              valueColor: AppColors.error,
            ),
          const Divider(height: 16),
          Row(
            children: [
              const Text(
                'الإجمالي المستحق',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                FormatUtils.formatMoneyAr(_total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (_paymentType != PaymentType.credit && change > 0)
            InfoRow(
              label: 'الباقي للعميل',
              icon: Icons.savings_outlined,
              value: FormatUtils.formatMoneyAr(change),
              valueColor: AppColors.success,
            ),
          if (remaining > 0 && _paymentType == PaymentType.mixed)
            InfoRow(
              label: 'المتبقي (دين على العميل)',
              icon: Icons.credit_score_outlined,
              value: FormatUtils.formatMoneyAr(remaining),
              valueColor: AppColors.secondary,
            ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    Text(
                      FormatUtils.formatMoneyAr(_total),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed:
                        (_cart.isEmpty || _processing) ? null : _completeSale,
                    icon: _processing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.point_of_sale),
                    label: Text(_processing ? 'جارٍ الحفظ...' : 'إتمام البيع'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
