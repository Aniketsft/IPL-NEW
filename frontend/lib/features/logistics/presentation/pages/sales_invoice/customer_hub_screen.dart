import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_auth_mobile/core/widgets/industrial_module_layout.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_bloc.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_event.dart';
import 'package:enterprise_auth_mobile/features/logistics/presentation/bloc/sales_invoice_state.dart';
import 'package:enterprise_auth_mobile/features/logistics/domain/models/transaction_config.dart';
import 'order_summary_screen.dart';
import 'open_invoices_screen.dart';
import 'transaction_history_screen.dart';
import 'sales_orders_list_screen.dart';
import 'amount_only_credit_note_screen.dart';

class CustomerHubScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerHubScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerHubScreen> createState() => _CustomerHubScreenState();
}

class _CustomerHubScreenState extends State<CustomerHubScreen> {
  late Map<String, dynamic> _customer;
  bool _isLoading = true;

  double _effectiveOutstanding = 0.0;
  double _creditLimit = 0.0;
  double _availableCredit = 0.0;

  int _openInvoicesCount = 0;
  double _openInvoicesSum = 0.0;

  final currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RS ',
    decimalDigits: 2,
  );

  String get _customerCode => (_customer['code'] ?? '').toString().trim();
  String get _customerName => (_customer['name'] ?? '').toString().trim();
  String get _statusFlag => (_customer['statusFlag'] ?? '1').toString().trim();
  String get _paymentTerm => (_customer['paymentTerm'] ?? 'STD').toString().trim();
  bool get _isOnHold => _statusFlag == '3';

  @override
  void initState() {
    super.initState();
    _customer = Map<String, dynamic>.from(widget.customer);
    _loadFinancials();
  }

  Future<void> _loadFinancials() async {
    setState(() => _isLoading = true);
    try {
      final code = _customerCode;
      
      // 1. Fetch fresh customer data if available in DB
      final refreshedCust = await LocalDatabaseHelper.instance.getSalesInvoiceCustomerByCode(code);
      if (refreshedCust != null) {
        _customer = Map<String, dynamic>.from(refreshedCust);
      }

      final rawLimit = _customer['creditLimit']?.toString() ?? '0';
      _creditLimit = double.tryParse(rawLimit) ?? 0.0;

      final rawOutstanding = _customer['outstandingBalance']?.toString() ?? '0';
      final baseOutstanding = double.tryParse(rawOutstanding) ?? 0.0;

      // 2. Dynamic Real-time Calculations
      final unsyncedPayments = await LocalDatabaseHelper.instance.getUnsyncedPaymentsSum(code);
      final unsyncedInvoices = await LocalDatabaseHelper.instance.getUnsyncedCreditInvoicesSum(code);

      _effectiveOutstanding = baseOutstanding - unsyncedPayments + unsyncedInvoices;
      if (_effectiveOutstanding < 0 && _effectiveOutstanding > -0.01) {
        _effectiveOutstanding = 0.0;
      }

      if (_creditLimit > 0) {
        _availableCredit = (_creditLimit - _effectiveOutstanding).clamp(0.0, double.infinity);
      } else {
        _availableCredit = 0.0;
      }

      // 3. Open Invoices Stats
      final openDocs = await LocalDatabaseHelper.instance.getOpenInvoices(customerNo: code);
      final activeOpen = openDocs.where((d) => (d['isPaid'] ?? 0) == 0).toList();
      _openInvoicesCount = activeOpen.length;
      _openInvoicesSum = activeOpen.fold(0.0, (acc, d) {
        final amt = (d['remainingAmtLCY'] as num?)?.toDouble() ?? 0.0;
        return acc + amt;
      });

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('CustomerHubScreen._loadFinancials error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Poka-Yoke: Safeguard against dirty draft cart bleed across customers
  Future<bool> _handleCartInvariantGuard() async {
    final bloc = context.read<SalesInvoiceBloc>();
    final state = bloc.state;

    if (state is SalesInvoiceLoaded && state.cartItems.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Active Draft Order'),
            ],
          ),
          content: Text(
            'You have an unsaved draft with ${state.cartItems.length} items for $_customerName.\n\n'
            'Discard this draft order to switch customers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('DISCARD & SWITCH'),
            ),
          ],
        ),
      );

      if (discard == true) {
        bloc.add(ClearCart());
        return true;
      }
      return false;
    }
    return true;
  }

  void _onSwitchCustomer() async {
    final canSwitch = await _handleCartInvariantGuard();
    if (canSwitch && mounted) {
      Navigator.pop(context, true);
    }
  }

  void _showNewTransactionSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Transaction Type',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Creating for $_customerName [$_customerCode]',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Invoice
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor.withOpacity(0.12),
                    child: Icon(Icons.receipt_long_rounded, color: theme.primaryColor),
                  ),
                  title: const Text('Standard Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('New sales order and delivery billing'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_isOnHold) {
                      _showHoldWarningDialog(onProceedCashOnly: () {
                        _startTransaction('INVOICE');
                      });
                    } else {
                      _startTransaction('INVOICE');
                    }
                  },
                ),

                // Credit Note
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withOpacity(0.12),
                    child: const Icon(Icons.description_rounded, color: Colors.orange),
                  ),
                  title: const Text('Credit Note', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Issue credit balance adjustment or reversal'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCreditNoteOptionsSheet();
                  },
                ),

                // Customer Return
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withOpacity(0.12),
                    child: const Icon(Icons.assignment_return_rounded, color: Colors.blue),
                  ),
                  title: const Text('Customer Return', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Process inventory items return and refund'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startTransaction('RETURN');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHoldWarningDialog({required VoidCallback onProceedCashOnly}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Account on HOLD'),
          ],
        ),
        content: Text(
          'Customer $_customerName is currently marked on HOLD in Sage X3.\n\n'
          'Credit sales transactions are prohibited. Only immediate Cash on Delivery (COD) or debt settlements can be processed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
            onPressed: () {
              Navigator.pop(ctx);
              onProceedCashOnly();
            },
            child: const Text('PROCEED AS CASH ONLY'),
          ),
        ],
      ),
    );
  }

  void _showCreditNoteOptionsSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Text(
                    'Select Credit Note Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.payments_outlined, color: Colors.orange),
                  title: const Text('Amount-Only Credit Note'),
                  subtitle: const Text('Adjust balance without returning physical inventory'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AmountOnlyCreditNoteScreen(
                          initialCustomer: _customer,
                          initialCustomerCode: _customerCode,
                          lockToCustomer: true,
                        ),
                      ),
                    );
                    _loadFinancials();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.replay_rounded, color: Colors.orange),
                  title: const Text('Invoice Item Reversal'),
                  subtitle: const Text('Select a previous invoice to reverse quantities'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TransactionHistoryScreen(
                          transactionType: 'INVOICE',
                          isForReversal: true,
                          initialCustomerCode: _customerCode,
                          initialCustomerName: _customerName,
                          lockToCustomer: true,
                        ),
                      ),
                    );
                    _loadFinancials();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _startTransaction(String txType) async {
    final bloc = context.read<SalesInvoiceBloc>();
    bloc.add(ClearCart());
    bloc.add(InitializeTransaction(
      transactionType: txType,
      config: TransactionConfig.forType(txType),
    ));
    bloc.add(SetCustomer(_customer));

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrderSummaryScreen()),
    );

    _loadFinancials();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canPop = await _handleCartInvariantGuard();
        if (canPop && context.mounted) {
          Navigator.pop(context, true);
        }
      },
      child: IndustrialModuleLayout(
        title: 'Customer Hub',
        extraActions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Switch Customer',
            onPressed: _onSwitchCustomer,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Ledger',
            onPressed: _loadFinancials,
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadFinancials,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Customer Hero & Financial Card
                      _buildCustomerHeroCard(theme, isDark),
                      const SizedBox(height: 16),

                      // 2. Alert Banner if Account is on HOLD
                      if (_isOnHold) ...[
                        _buildHoldAlertBanner(),
                        const SizedBox(height: 16),
                      ],

                      // 3. Operational Action Grid Header
                      Text(
                        'Customer Operations',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 4. Action Cards Grid
                      _buildOperationsGrid(theme, isDark),

                      const SizedBox(height: 24),
                      // 5. Finish Visit Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _onSwitchCustomer,
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text(
                            'FINISH VISIT / NEXT CUSTOMER',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: theme.primaryColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCustomerHeroCard(ThemeData theme, bool isDark) {
    Color statusColor = Colors.green;
    String statusText = 'CHECK';
    IconData statusIcon = Icons.check_circle_outline_rounded;

    if (_statusFlag == '2') {
      statusColor = Colors.grey;
      statusText = 'NO CHECK';
      statusIcon = Icons.info_outline_rounded;
    } else if (_statusFlag == '3') {
      statusColor = Colors.red.shade700;
      statusText = 'HOLD';
      statusIcon = Icons.error_outline_rounded;
    }

    final isOverLimit = _creditLimit > 0 && _effectiveOutstanding > _creditLimit;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Identity Strip
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _customerName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _customerCode,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: _onSwitchCustomer,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.primaryColor.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Switch',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 16, color: theme.primaryColor),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Payment Term Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _paymentTerm.toUpperCase(),
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1),

          // 3-Metric Financial Matrix Strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildFinancialColumn(
                    title: 'CREDIT LIMIT',
                    amount: _creditLimit,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                Container(width: 1, height: 36, color: isDark ? Colors.white10 : Colors.black12),
                Expanded(
                  child: _buildFinancialColumn(
                    title: 'OUTSTANDING',
                    amount: _effectiveOutstanding,
                    color: isOverLimit ? Colors.red.shade700 : (isDark ? Colors.white : Colors.black87),
                    isBold: isOverLimit,
                  ),
                ),
                Container(width: 1, height: 36, color: isDark ? Colors.white10 : Colors.black12),
                Expanded(
                  child: _buildFinancialColumn(
                    title: 'AVAIL. CREDIT',
                    amount: _availableCredit,
                    color: Colors.green.shade600,
                    isBold: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialColumn({
    required String title,
    required double amount,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          currencyFormat.format(amount),
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildHoldAlertBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACCOUNT IS ON HOLD IN SAGE X3',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Credit invoices are blocked. Process Cash sales or settle Open Invoices.',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsGrid(ThemeData theme, bool isDark) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        // 1. New Transaction
        _buildActionTile(
          theme: theme,
          title: 'New Transaction',
          subtitle: 'Invoice, Credit Note, Return',
          icon: Icons.shopping_cart_checkout_rounded,
          color: theme.primaryColor,
          onTap: _showNewTransactionSheet,
        ),

        // 2. Open Invoices
        _buildActionTile(
          theme: theme,
          title: 'Open Invoices',
          subtitle: 'Settle dues, Cash / Cheque / QR',
          badgeText: _openInvoicesCount > 0
              ? '$_openInvoicesCount Docs'
              : '0 Open',
          badgeColor: _openInvoicesCount > 0 ? Colors.green.shade700 : Colors.grey,
          icon: Icons.receipt_long_rounded,
          color: Colors.green.shade600,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OpenInvoicesScreen(
                  initialCustomerNo: _customerCode,
                  initialCustomerName: _customerName,
                  lockToCustomer: true,
                ),
              ),
            );
            _loadFinancials();
          },
        ),

        // 3. Transaction History
        _buildActionTile(
          theme: theme,
          title: 'History',
          subtitle: 'Past invoices, reprints, returns',
          icon: Icons.history_rounded,
          color: Colors.indigoAccent,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionHistoryScreen(
                  initialCustomerCode: _customerCode,
                  initialCustomerName: _customerName,
                  lockToCustomer: true,
                ),
              ),
            );
            _loadFinancials();
          },
        ),

        // 4. Sales Orders
        _buildActionTile(
          theme: theme,
          title: 'Sales Orders',
          subtitle: 'View and convert orders',
          icon: Icons.list_alt_rounded,
          color: Colors.purple,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SalesOrdersListScreen(
                  customerCode: _customerCode,
                  customerName: _customerName,
                ),
              ),
            );
            _loadFinancials();
          },
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badgeText,
    Color? badgeColor,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: badgeColor ?? color,
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
