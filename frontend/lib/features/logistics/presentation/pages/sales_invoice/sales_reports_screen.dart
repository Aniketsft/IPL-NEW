import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../../core/widgets/industrial_module_layout.dart';
import '../../../../../core/network_service.dart';
import '../../../data/repositories/transaction_history_repository.dart';
import '../../../data/repositories/sales_invoice_product_repository.dart';
import '../../../domain/services/sales_report_pdf_service.dart';
import 'pdf_preview_screen.dart';

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

  Future<void> _handleInvoiceSummary() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
    );

    if (selectedDate == null) return;

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

      final pdfService = SalesReportPdfService();
      final pdfBytes = await pdfService.generateInvoiceSummaryPdf(
        invoices: invoices,
        reportDate: DateFormat('dd MMM yyyy').format(selectedDate),
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              title: 'Invoice Summary',
              pdfBytes: pdfBytes,
            ),
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
        limit: 5000,
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
      final pdfBytes = await pdfService.generateStockPreviewPdf(
        items: items,
        warehouseLabel: selectedWarehouse == 'ALL' ? 'All Warehouses' : selectedWarehouse,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              title: 'Stock Preview',
              pdfBytes: pdfBytes,
            ),
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
    return IndustrialModuleLayout(
      title: 'Sales Reports',
      body: GridView.count(
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
        ],
      ),
    );
  }
}
