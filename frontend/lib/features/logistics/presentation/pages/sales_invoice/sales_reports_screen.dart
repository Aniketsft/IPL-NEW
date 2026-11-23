import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../../core/network_service.dart';
import '../../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../auth/presentation/bloc/auth_state.dart';
import '../../../data/repositories/transaction_history_repository.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../../domain/services/sales_report_pdf_service.dart';
import '../../widgets/print_or_preview_dialog.dart';

class SalesReportsScreen extends StatefulWidget {
  final List<String> permissions;

  const SalesReportsScreen({
    super.key,
    required this.permissions,
  });

  @override
  State<SalesReportsScreen> createState() => _SalesReportsScreenState();
}

class _SalesReportsScreenState extends State<SalesReportsScreen> {
  bool _isLoadingInvoice = false;
  bool _isLoadingStock = false;
  bool _isLoadingEod = false;
  DateTime _selectedDate = DateTime.now();

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _canSelectPreviousDate(BuildContext context, {bool listen = false}) {
    final Set<String> perms = Set<String>.from(widget.permissions);
    try {
      final bloc = listen ? context.watch<AuthBloc>() : context.read<AuthBloc>();
      final authState = bloc.state;
      if (authState is Authenticated) {
        perms.addAll(authState.permissions);
      }
    } catch (_) {}

    return perms.contains('logistics.reports.previous_date.read') ||
        perms.contains('logistics.reports.previous_date.update') ||
        perms.contains('logistics.reports.previous_date.create') ||
        perms.contains('logistics.reports.previous_date') ||
        perms.contains('admin') ||
        perms.contains('*');
  }

  DateTime _effectiveReportDate(bool canSelectPreviousDate) {
    final now = DateTime.now();
    if (!canSelectPreviousDate) {
      return DateTime(now.year, now.month, now.day);
    }
    return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
  }

  Future<void> _pickReportDate() async {
    if (!_canSelectPreviousDate(context)) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleInvoiceSummary() async {
    final bool canPickPast = _canSelectPreviousDate(context);
    final selectedDate = _effectiveReportDate(canPickPast);

    setState(() => _isLoadingInvoice = true);

    try {
      final startDate = DateFormat('yyyy-MM-dd').format(selectedDate) + 'T00:00:00';
      final endDate = DateFormat('yyyy-MM-dd').format(selectedDate) + 'T23:59:59';
      
      final repo = TransactionHistoryRepository();
      final invoices = await repo.getTransactions(
        startDate: startDate,
        endDate: endDate,
        limit: 1000,
      );

      if (invoices.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No invoices found for selected date.')),
          );
        }
        return;
      }

      final productRows = await repo.getSalesSummaryRows(
        startDate: startDate,
        endDate: endDate,
      );

      final pdfService = SalesReportPdfService();

      if (mounted) {
        setState(() => _isLoadingInvoice = false);
        await PrintOrPreviewDialog.show(
          context: context,
          title: 'Invoice Summary',
          subtitle: DateFormat('dd MMM yyyy').format(selectedDate),
          onGeneratePdf: () => pdfService.generateInvoiceSummaryPdf(
            invoices: invoices,
            reportDate: DateFormat('dd MMM yyyy').format(selectedDate),
            productRows: productRows,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingInvoice = false);
      }
    }
  }

  Future<void> _handleStockPreview() async {
    final bool canPickPast = _canSelectPreviousDate(context);
    final selectedDate = _effectiveReportDate(canPickPast);
    final isHistoricalDate = !_isSameDay(selectedDate, DateTime.now());
    final formattedDate = DateFormat('dd MMM yyyy').format(selectedDate);

    setState(() => _isLoadingStock = true);

    try {
      final repo = SalesInvoiceProductRepository(context.read<NetworkService>());
      final warehouses = await repo.getDistinctWarehouses();

      if (mounted) {
        setState(() => _isLoadingStock = false);
      }

      final selectedWarehouse = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Select Warehouse',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  title: const Text('All Warehouses', style: TextStyle(fontWeight: FontWeight.bold)),
                  leading: const Icon(Icons.warehouse),
                  onTap: () => Navigator.pop(context, 'ALL'),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: warehouses.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(warehouses[index]),
                        leading: const Icon(Icons.location_on_outlined),
                        onTap: () => Navigator.pop(context, warehouses[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (selectedWarehouse == null) return;

      if (mounted) {
        setState(() => _isLoadingStock = true);
      }

      final items = await repo.getSalesInvoiceProducts(
        warehouse: selectedWarehouse,
        stockStatus: 'ALL',
        limit: 10000,
      );

      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No stock found for selected warehouse.')),
          );
        }
        return;
      }

      final pdfService = SalesReportPdfService();

      if (mounted) {
        setState(() => _isLoadingStock = false);
        await PrintOrPreviewDialog.show(
          context: context,
          title: 'Stock Preview',
          subtitle: '${selectedWarehouse == 'ALL' ? 'All Warehouses' : selectedWarehouse} • $formattedDate',
          onGeneratePdf: () => pdfService.generateStockPreviewPdf(
            items: items,
            warehouseLabel: selectedWarehouse == 'ALL' ? 'All Warehouses' : selectedWarehouse,
            reportDate: formattedDate,
            isHistoricalDate: isHistoricalDate,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingStock = false);
      }
    }
  }

  Future<void> _handleEodReport() async {
    final bool canPickPast = _canSelectPreviousDate(context);
    final selectedDate = _effectiveReportDate(canPickPast);

    setState(() => _isLoadingEod = true);

    try {
      final repo = TransactionHistoryRepository();
      final eodData = await repo.getEodReportData(selectedDate);

      final pdfService = SalesReportPdfService();

      if (mounted) {
        setState(() => _isLoadingEod = false);
        await PrintOrPreviewDialog.show(
          context: context,
          title: 'End of Day Summary',
          subtitle: DateFormat('dd MMM yyyy').format(selectedDate),
          onGeneratePdf: () => pdfService.generateEodReportPdf(eodData),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingEod = false);
      }
    }
  }

  Widget _buildReportTile({
    required String title,
    required IconData icon,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(color: theme.primaryColor),
                      )
                    : Icon(
                        icon,
                        size: 40,
                        color: theme.primaryColor,
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool canPickPast = _canSelectPreviousDate(context, listen: true);
    final DateTime activeDate = _effectiveReportDate(canPickPast);
    final bool isToday = _isSameDay(activeDate, DateTime.now());
    final String formattedDate = DateFormat('EEE, dd MMM yyyy').format(activeDate);

    return IndustrialModuleLayout(
      title: 'Sales Reports',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: canPickPast ? _pickReportDate : null,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: canPickPast
                          ? theme.primaryColor.withValues(alpha: 0.4)
                          : (isDark ? Colors.white12 : Colors.black12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (canPickPast ? theme.primaryColor : Colors.grey)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          canPickPast ? Icons.calendar_month_rounded : Icons.lock_outline_rounded,
                          color: canPickPast ? theme.primaryColor : Colors.grey,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'REPORT DATE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              canPickPast
                                  ? 'Tap to select a previous date'
                                  : 'Default: Current date only',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canPickPast && !isToday)
                        TextButton(
                          onPressed: () => setState(() => _selectedDate = DateTime.now()),
                          child: const Text('Today', style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      else if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'TODAY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      if (canPickPast)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.edit_calendar_outlined, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.9,
              children: [
                _buildReportTile(
                  title: 'Invoice Summary',
                  icon: Icons.receipt_long_rounded,
                  isLoading: _isLoadingInvoice,
                  onTap: _handleInvoiceSummary,
                ),
                _buildReportTile(
                  title: 'Stock Preview',
                  icon: Icons.inventory_2_rounded,
                  isLoading: _isLoadingStock,
                  onTap: _handleStockPreview,
                ),
                _buildReportTile(
                  title: 'End of Day',
                  icon: Icons.point_of_sale_rounded,
                  isLoading: _isLoadingEod,
                  onTap: _handleEodReport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
