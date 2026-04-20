import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';
import 'package:enterprise_auth_mobile/core/widgets/standard_filter.dart';
import 'package:enterprise_auth_mobile/core/widgets/filter_input_widgets.dart';
import '../widgets/label_printing_handler.dart';
import 'production_tracking_screen.dart';
import 'package:enterprise_auth_mobile/core/utils/barcode_scanner/production_tracking_scanner.dart';

class SalesOrderDetailScreen extends StatefulWidget {
  final SalesOrder order;
  final bool isDeliveryMode;

  const SalesOrderDetailScreen({
    super.key,
    required this.order,
    this.isDeliveryMode = false,
  });

  @override
  State<SalesOrderDetailScreen> createState() => _SalesOrderDetailScreenState();
}

class _SalesOrderDetailScreenState extends State<SalesOrderDetailScreen> {
  List<SalesOrderDetail> _details = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TextEditingController _codeFilter = TextEditingController();
  final TextEditingController _descFilter = TextEditingController();
  final Set<String> _selectedItemCodes = {};
  double _tolerancePercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<DeliveryRepository>();
      
      // Fetch tolerance first
      final settings = await repository.getAppSettings();
      final results = await repository.fetchSalesOrderDetails(
        widget.order.orderNumber,
      );
      
      if (mounted) {
        setState(() {
          _tolerancePercentage = settings.tolerancePercentage ?? 0.0;
          _details = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _toggleItemPreparation(SalesOrderDetail item) async {
    // If prepared for shipment, nothing can be modified
    if (widget.order.isPreparedForShipment) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shipment is finalized and cannot be modified.'),
          ),
        );
      }
      return;
    }

    // In regular mode, closed production orders are locked.
    // In delivery mode, we are dealing with closed production orders, so we allow them.
    if (!widget.isDeliveryMode && widget.order.isClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Production is closed and cannot be modified.'),
        ),
      );
      return;
    }

    final bool currentStatus = widget.isDeliveryMode ? item.isValidated : item.isPrepared;
    String? choice;

    if (currentStatus) {
      // Removing status logic (Simple Confirmation)
      final String title = widget.isDeliveryMode ? 'Remove Validation' : 'Remove Prepared Status';
      final String content = widget.isDeliveryMode
          ? 'Are you sure you want to remove the shipment validation from this item?'
          : 'Are you sure you want to remove the prepared status from this item?';
      
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(content, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
      if (confirmed == true) choice = 'just_mark';
    } else {
      // Adding status logic
      if (widget.isDeliveryMode) {
        // Validation flow (Simple Confirmation for now)
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Validate for Shipment', style: TextStyle(color: Colors.white)),
            content: const Text('Are you sure you want to validate this item for shipment?', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm', style: TextStyle(color: Colors.orange)),
              ),
            ],
          ),
        );
        if (confirmed == true) choice = 'just_mark';
      } else {
        // Preparation flow (CONSOLIDATED PROMPT)
        choice = await LabelPrintingHandler.showPreparationPrompt(
          context: context,
          item: item,
        );
      }
    }

    if (choice != null && choice != 'cancel') {
      if (mounted) setState(() => _isLoading = true);
      try {
        // Step 1: Update status in repository
        await context.read<DeliveryRepository>().updateItemPreparationStatus(
          soNumber: widget.order.orderNumber,
          itemCode: item.itemCode,
          isPrepared: !currentStatus,
          isValidation: widget.isDeliveryMode,
        );

        // Step 2: Handle Printing/Preview if adding prepared status
        if (!currentStatus && !widget.isDeliveryMode) {
          if (choice == 'preview') {
            await LabelPrintingHandler.showLabelPreview(
              context: context,
              item: item,
              onPrintRequested: (item, auditId) => LabelPrintingHandler.printLabel(
                context: context,
                item: item,
                auditId: auditId,
              ),
            );
          } else if (choice == 'print') {
            await LabelPrintingHandler.printLabel(
              context: context,
              item: item,
            );
          }
        }

        _fetchDetails();
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update status: $e')),
          );
        }
      }
    }
  }

  void _toggleSelection(String itemCode) {
    setState(() {
      if (_selectedItemCodes.contains(itemCode)) {
        _selectedItemCodes.remove(itemCode);
      } else {
        _selectedItemCodes.add(itemCode);
      }
    });
  }

  void _toggleSelectAll() {
    final filtered = _filteredDetails;
    // Only select items that aren't already locked
    final selectables = filtered.where((item) {
      final itemStatus = widget.isDeliveryMode ? item.isValidated : item.isPrepared;
      return !(itemStatus ||
          widget.order.isPreparedForShipment ||
          (!widget.isDeliveryMode && widget.order.isClosed));
    }).map((e) => e.itemCode).toList();

    setState(() {
      if (_selectedItemCodes.length >= selectables.length && selectables.every((code) => _selectedItemCodes.contains(code))) {
        _selectedItemCodes.clear();
      } else {
        _selectedItemCodes.addAll(selectables);
      }
    });
  }

  Future<void> _bulkUpdateStatus() async {
    if (_selectedItemCodes.isEmpty) return;

    final String title = widget.isDeliveryMode ? 'Bulk Validate' : 'Bulk Prepare';
    final String content = 'Are you sure you want to ${widget.isDeliveryMode ? 'validate' : 'prepare'} ${_selectedItemCodes.length} selected items?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (mounted) setState(() => _isLoading = true);
      try {
        final List<String> codesToUpdate = _selectedItemCodes.toList();
        await context.read<DeliveryRepository>().bulkUpdateItemStatus(
          soNumber: widget.order.orderNumber,
          itemCodes: codesToUpdate,
          status: true,
          isValidation: widget.isDeliveryMode,
        );
        
        _selectedItemCodes.clear();
        await _fetchDetails();
        
        // --- NEW: Printing Prompt for Production Mode ---
        if (mounted && !widget.isDeliveryMode && codesToUpdate.isNotEmpty) {
          final bool? printAll = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('Print Labels?', style: TextStyle(color: Colors.white)),
              content: Text('Marked ${codesToUpdate.length} items as Prepared. Would you like to print labels for these items now?', style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO', style: TextStyle(color: Colors.grey))),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('YES, PRINT ALL', style: TextStyle(color: Colors.orange))),
              ],
            ),
          );

          if (printAll == true) {
            // Filter details to find the exact objects for the items we just prepared
            final itemsToPrint = _details.where((d) => codesToUpdate.contains(d.itemCode)).toList();
            for (var item in itemsToPrint) {
              if (!mounted) break;
              await LabelPrintingHandler.printLabel(context: context, item: item);
            }
          }
        }

        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update status: $e')),
          );
        }
      }
    }
  }

  Future<void> _prepareForShipment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Prepare for Shipment',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to mark this order as PREPARED FOR SHIPMENT? This will lock the order.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Finalize Shipment',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      await repository.updateShipmentPreparationStatus(
        soNumber: widget.order.orderNumber,
        isPrepared: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order marked as Prepared for Shipment')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to prepare shipment: $e';
      });
    }
  }

  Future<void> _closeOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Close Production',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to close this Production? This will mark it as completed.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Close Production',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final repository = context.read<DeliveryRepository>();
      await repository.closeOrder(widget.order.orderNumber, 'system');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Production closed successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate status change
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to close Production: $e';
      });
    }
  }

  List<SalesOrderDetail> get _filteredDetails {
    return _details.where((d) {
      final matchCode = d.itemCode.toLowerCase().contains(
        _codeFilter.text.toLowerCase(),
      );
      final matchDesc = d.description.toLowerCase().contains(
        _descFilter.text.toLowerCase(),
      );
      return matchCode && matchDesc;
    }).toList()..sort((a, b) {
      final aStat = widget.isDeliveryMode ? a.isValidated : a.isPrepared;
      final bStat = widget.isDeliveryMode ? b.isValidated : b.isPrepared;
      if (aStat == bStat) return 0;
      return aStat ? 1 : -1;
    });
  }

  bool get _isAllItemsPrepared =>
      _details.isNotEmpty && _details.every((d) => widget.isDeliveryMode ? d.isValidated : d.isPrepared);

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF9800);
    const dark800 = Color(0xFF1E1E1E);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: Text(widget.order.orderNumber),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Main Plant',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderInfo(),
          StandardFilter(
            searchController: _codeFilter,
            searchHint: 'Product Code...',
            onSearchChanged: (_) => setState(() {}),
            hasActiveFilters: _descFilter.text.isNotEmpty,
            onReset: () {
              _codeFilter.clear();
              _descFilter.clear();
              setState(() {});
            },
            filterBuilder: (context, setModalState) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  // Row 1: Delivery Date + Customer (read-only)
                  Row(
                    children: [
                      FilterDatePicker(
                        label: 'Del. Date',
                        value: widget.order.date,
                        onTap: () {}, // read-only
                      ),
                      const SizedBox(width: 12),
                      FilterPickerTile(
                        label: 'Customer',
                        value: widget.order.customerName.isNotEmpty
                            ? widget.order.customerName
                            : null,
                        icon: Icons.business,
                        onTap: () {}, // read-only
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 2: Sales Man (REP2_0)
                  Row(
                    children: [
                      FilterPickerTile(
                        label: 'Salesman',
                        value: widget.order.salesManCode2.isNotEmpty
                            ? widget.order.salesManCode2
                            : null,
                        icon: Icons.person_outline,
                        onTap: () {}, // read-only
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Status toggle (read-only)
                  FilterSegmentedToggle(
                    label: 'Order Status',
                    value: widget.order.isClosed ? 'closed' : 'open',
                    options: const ['open', 'closed'],
                    onChanged: (_) {}, // read-only
                  ),
                  const SizedBox(height: 16),
                  // Editable product description filter
                  FilterSearchInput(
                    controller: _descFilter,
                    hint: 'Product Description...',
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Checkbox(
                    value: _selectedItemCodes.length == _filteredDetails.where((item) {
                      final itemStatus = widget.isDeliveryMode ? item.isValidated : item.isPrepared;
                      return !(itemStatus || widget.order.isPreparedForShipment || (!widget.isDeliveryMode && widget.order.isClosed));
                    }).length && _selectedItemCodes.isNotEmpty,
                    onChanged: (val) => _toggleSelectAll(),
                    activeColor: orange,
                    checkColor: Colors.black,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Product',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
                const Text(
                  'Ordered',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(width: 24),
                const Text(
                  'Remaining',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredDetails.length,
                    itemBuilder: (context, index) {
                      return _buildProductCard(
                        _filteredDetails[index],
                        orange,
                        dark800,
                      );
                    },
                  ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    const orange = Color(0xFFFF9800);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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
                      widget.order.customerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.order.customerCode,
                      style: TextStyle(
                        color: orange.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(
                isClosed: widget.order.isClosed,
                isPreparedForShipment: widget.order.isPreparedForShipment,
                isDeliveryMode: widget.isDeliveryMode,
                orange: orange,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildCompactInfo(
                'PO NUMBER',
                widget.order.purchaseOrderNumber ?? 'N/A',
              ),
              const SizedBox(width: 32),
              _buildCompactInfo('DELIVERY DATE', widget.order.deliveryDate),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(SalesOrderDetail item, Color orange, Color dark800) {
    final itemStatus = widget.isDeliveryMode ? item.isValidated : item.isPrepared;
    final isLocked = itemStatus ||
        widget.order.isPreparedForShipment ||
        (!widget.isDeliveryMode && widget.order.isClosed);

    return InkWell(
      onLongPress: (widget.order.isPreparedForShipment || (!widget.isDeliveryMode && widget.order.isClosed))
          ? null
          : () => _toggleItemPreparation(item),
      onTap: () async {
        if (!widget.isDeliveryMode && widget.order.isClosed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Production is closed and cannot be modified.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        if (widget.order.isPreparedForShipment) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Shipment is finalized and cannot be modified.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        if (itemStatus) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.isDeliveryMode
                    ? 'Item is already validated. Long-press to remove validation.'
                    : 'Cannot access prepared item. Long-press to remove status.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ProductionTrackingScreen(order: widget.order, product: item),
          ),
        );
        if (result == true) {
          _fetchDetails();
        }
      },
      child: Opacity(
        opacity: isLocked ? 0.4 : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _selectedItemCodes.contains(item.itemCode),
                          onChanged: (val) => _toggleSelection(item.itemCode),
                          activeColor: orange,
                          checkColor: Colors.black,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.itemCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            item.barcodeType.toLowerCase().contains('variable') ? 'VW' : 'FW',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.formatQuantity(item.quantity)} ${item.unit}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Builder(builder: (context) {
                        final effectiveLimit = item.quantity * (1 + _tolerancePercentage / 100);
                        final effectiveRemaining = effectiveLimit - item.manufacturedQuantity;
                        return Text(
                          '${item.formatQuantity(effectiveRemaining)} ${item.unit}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: effectiveRemaining < 0 ? Colors.green : Colors.red,
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (itemStatus)
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          widget.isDeliveryMode ? 'Validated' : 'Prepared',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(),
                  Text(
                    'Scanned: ${item.formatQuantity(item.scannedQuantity)} ${item.unit}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(orange),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (widget.order.isPreparedForShipment) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: const Center(
            child: Text(
              'SHIPMENT PREPARED',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      );
    }

    if (!widget.isDeliveryMode && widget.order.isClosed) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: const Center(
            child: Text(
              'THIS ORDER IS CLOSED',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      );
    }

    final isAllPrepared = _isAllItemsPrepared;

    if (_selectedItemCodes.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _bulkUpdateStatus,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              '${widget.isDeliveryMode ? 'VALIDATE' : 'PREPARE'} (${_selectedItemCodes.length}) SELECTED',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: widget.isDeliveryMode
                ? ElevatedButton(
                    onPressed: (_isLoading || !isAllPrepared)
                        ? null
                        : _prepareForShipment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: 0.05,
                      ),
                      foregroundColor: Colors.black,
                      disabledForegroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'Prepare for Shipment',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  )
                : (isAllPrepared
                    ? ElevatedButton(
                        onPressed: _isLoading ? null : _closeOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C2C2E),
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.05,
                          ),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white24,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Close Production',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ProductionTrackingScanner(
                                      order: widget.order,
                                      details: _details,
                                    ),
                                  ),
                                ).then((_) => _fetchDetails()),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text(
                          'Scan Product to Track',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      )),
          ),
          if (!isAllPrepared && !_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isDeliveryMode
                        ? 'Validate all items by long-press to prepare shipment'
                        : 'Scan or prepare all items to close production',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
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

class _StatusBadge extends StatelessWidget {
  final bool isClosed;
  final bool isPreparedForShipment;
  final bool isDeliveryMode;
  final Color orange;

  const _StatusBadge({
    required this.isClosed,
    required this.isPreparedForShipment,
    required this.isDeliveryMode,
    required this.orange,
  });

  @override
  Widget build(BuildContext context) {
    if (isDeliveryMode && isPreparedForShipment) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.green.withValues(alpha: 0.3),
          ),
        ),
        child: const Text(
          'PREPARED',
          style: TextStyle(
            color: Colors.green,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isClosed ? Colors.white10 : orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isClosed ? Colors.white24 : orange.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        isClosed ? 'CLOSED' : 'OPEN',
        style: TextStyle(
          color: isClosed ? Colors.white60 : orange,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
