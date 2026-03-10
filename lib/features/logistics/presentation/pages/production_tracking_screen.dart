import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/sales_order.dart';
import '../../domain/entities/sales_order_detail.dart';
import '../../data/repositories/delivery_repository.dart';

const Color orange = Color(0xFFFF9800);
const Color dark800 = Color(0xFF1E1E1E);
const Color dark900 = Color(0xFF0D0D0D);
const Color darkBorder = Color(0xFF2C2C2E);

class ProductionTrackingScreen extends StatefulWidget {
  final SalesOrder order;
  final SalesOrderDetail product;

  const ProductionTrackingScreen({
    super.key,
    required this.order,
    required this.product,
  });

  @override
  State<ProductionTrackingScreen> createState() =>
      _ProductionTrackingScreenState();
}

class _ProductionTrackingScreenState extends State<ProductionTrackingScreen> {
  String _status = 'A';
  double _currentScan = 0.0;
  double _cumulativeQty = 0.0;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    // No initial data to fetch for now.
  }

  Future<void> _saveAndUpdate() async {
    if (_cumulativeQty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please scan items first')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = context.read<DeliveryRepository>();

      final payload = {
        'itemCode': widget.product.itemCode,
        'description': widget.product.description,
        'scanAmountKg': _cumulativeQty,
        'soNumber': widget.order.orderNumber,
        'customerId': widget.order.customerCode,
        'customerDescription': widget.order.customerName,
        'itemStatus': _status, // A, Q, or R
      };

      await repository.saveProductionScan(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Production data saved successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving production data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dark900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Production Tracking',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                widget.product.site ?? 'Main Plant',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: orange))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildHeaderCard(dark800),
                        const SizedBox(height: 16),
                        _buildTrackingParamsCard(dark800, orange),
                        const SizedBox(height: 16),
                        _buildScanningCard(dark800, orange),
                      ],
                    ),
                  ),
                ),
                _buildFooter(dark800, orange),
              ],
            ),
    );
  }

  Widget _buildHeaderCard(Color dark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            'Customer:',
            '${widget.order.customerCode} - ${widget.order.customerName}',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Product:',
            '${widget.product.itemCode} - ${widget.product.description}',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingParamsCard(Color dark, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildFieldRow(
            'Order Qty:',
            widget.product.quantity.toStringAsFixed(2),
          ),
          const SizedBox(height: 12),
          _buildFieldRow(
            'Manufactured Qty:',
            widget.product.manufacturedQuantity.toStringAsFixed(2),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Status',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const Spacer(),
              _buildStatusToggle(orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToggle(Color orange) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: ['Q', 'A', 'R'].map((s) {
          final isSelected = _status == s;
          return GestureDetector(
            onTap: () => setState(() => _status = s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1E1E1E)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                s,
                style: TextStyle(
                  color: isSelected ? orange : Colors.grey,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScanningCard(Color dark, Color orange) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'Current Scan',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            _currentScan.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          const Text(
            'Cumulative Scanned Quantity',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            _cumulativeQty.toStringAsFixed(2),
            style: TextStyle(
              color: orange,
              fontWeight: FontWeight.bold,
              fontSize: 48,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _currentScan = 10.0;
              _cumulativeQty += 10.0;
            }),
            icon: const Icon(Icons.grid_view_rounded),
            label: const Text(
              'Scan Quantity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Color dark, Color orange) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveAndUpdate,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2C2C2E),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save & Update',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
