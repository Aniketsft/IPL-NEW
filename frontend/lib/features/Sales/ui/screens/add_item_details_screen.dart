import 'package:flutter/material.dart';
import '../../../../core/widgets/industrial_module_layout.dart';

/// AddItemDetailsScreen - Add item details to sales order
///
/// This screen provides a comprehensive form for adding item details to an order,
/// including quantity management, lot selection, warehouse location, pricing, and
/// VAT calculations following Material Design 3 principles.
class AddItemDetailsScreen extends StatefulWidget {
  final String? orderId;
  final String? productSkuId;

  const AddItemDetailsScreen({super.key, this.orderId, this.productSkuId});

  @override
  State<AddItemDetailsScreen> createState() => _AddItemDetailsScreenState();
}

class _AddItemDetailsScreenState extends State<AddItemDetailsScreen> {
  // Form State
  int _quantity = 1;
  final double _basePrice = 1250.00;

  double _discountPercentage = 10.00;
  String _selectedVatRate = '20.00% (Standard)';

  // Product Data
  final String _sku = 'IND-773-XYZ';
  final String _productName = 'Heavy Duty Industrial Servo Motor';
  final int _stockAvailable = 142;
  final String _lotNumber = 'LOT-2023-11-892';
  final String _warehouse = 'Main (WH-01)';
  final String _location = 'A4-S2-B12';
  final String _locationType = 'Standard Storage (Pickable)';

  // Calculated fields
  double get _discountAmount =>
      (_basePrice * _quantity) * (_discountPercentage / 100);
  double get _subtotal => (_basePrice * _quantity) - _discountAmount;
  double get _vatRate => _extractVatPercentage(_selectedVatRate);
  double get _vatAmount => _subtotal * (_vatRate / 100);
  double get _total => _subtotal + _vatAmount;

  @override
  Widget build(BuildContext context) {
    return IndustrialModuleLayout(
      title: 'ADD ITEM DETAIL',
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Stack(
      children: [
        // Main scrollable content
        SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 100, // Space for sticky bottom bar
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contextual Header
              _buildContextualHeader(context),
              const SizedBox(height: 24),

              // Selected Product Card
              _buildProductCard(),
              const SizedBox(height: 24),

              // Form Content
              _buildFormContent(),
              const SizedBox(height: 24),

              // Financial Summary Card
              _buildFinancialSummary(),
            ],
          ),
        ),

        // Sticky Bottom Action Bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildActionBar(context),
        ),
      ],
    );
  }

  /// Build contextual header with back button and title
  Widget _buildContextualHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back Button
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
          label: Text(
            'Return to Order #${widget.orderId ?? "ORD-8821"}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF003461), // primary
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: const Size(44, 44),
          ),
        ),
        const SizedBox(height: 8),

        // Title
        Text(
          'Add Item Detail',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
      ],
    );
  }

  /// Build product card with SKU and stock info
  Widget _buildProductCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF), // surface-container-lowest
        border: Border.all(color: const Color(0xFFC2C6D1)), // outline-variant
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SKU and Stock Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SKU: $_sku',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFCAE3F5), // secondary-container
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'In Stock: $_stockAvailable',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4E6675), // on-secondary-container
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Product Name
          Text(_productName, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }

  /// Build main form with quantity, lot, location, and pricing fields
  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quantity Stepper
        _buildQuantityStepper(),
        const SizedBox(height: 16),

        // Lot Number (Selectable)
        _buildLotNumberField(),
        const SizedBox(height: 16),

        // Warehouse & Location Grid
        Row(
          children: [
            Expanded(
              child: _buildReadOnlyField(label: 'Warehouse', value: _warehouse),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildReadOnlyField(label: 'Location', value: _location),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Location Type
        _buildReadOnlyField(label: 'Location Type', value: _locationType),
        const SizedBox(height: 16),

        // Base Price
        _buildReadOnlyField(
          label: 'Base Price',
          value: '\$${_basePrice.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 16),

        // Discount Row
        Row(
          children: [
            Expanded(
              child: _buildEditableField(
                label: 'Discount %',
                value: _discountPercentage.toStringAsFixed(2),
                suffix: '%',
                onChanged: (value) {
                  setState(() {
                    _discountPercentage = double.tryParse(value) ?? 0;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildReadOnlyField(
                label: 'Discount Amt',
                value: '-\$${_discountAmount.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // VAT Row
        Row(
          children: [
            Expanded(child: _buildVatRateDropdown()),
            const SizedBox(width: 12),
            Expanded(
              child: _buildReadOnlyField(
                label: 'VAT Amt',
                value: '+\$${_vatAmount.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build quantity stepper widget
  Widget _buildQuantityStepper() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quantity',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF424750), // on-surface-variant
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF727781)), // outline
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFFFFFFF),
          ),
          child: Row(
            children: [
              // Decrease Button
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (_quantity > 1) _quantity--;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: const Color(0xFF727781)),
                      ),
                    ),
                    child: const Icon(Icons.remove),
                  ),
                ),
              ),

              // Quantity Input
              Expanded(
                flex: 2,
                child: TextField(
                  textAlign: TextAlign.center,
                  readOnly: true,
                  controller: TextEditingController(text: _quantity.toString()),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Increase Button
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _quantity++;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: const Color(0xFF727781)),
                      ),
                    ),
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build lot number selectable field
  Widget _buildLotNumberField() {
    return InkWell(
      onTap: () {
        // TODO: Implement lot selection dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lot selection coming soon')),
        );
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF727781)),
          borderRadius: BorderRadius.circular(4),
          color: const Color(0xFFFFFFFF),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lot Number',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: const Color(0xFF424750)),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _lotNumber,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF424750)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build editable text field with label
  Widget _buildEditableField({
    required String label,
    required String value,
    String? suffix,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: const Color(0xFF424750)),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF727781)),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFFFFFFF),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: value),
                  textAlign: TextAlign.right,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  suffix,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF424750),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build read-only text field
  Widget _buildReadOnlyField({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: const Color(0xFF424750)),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFC2C6D1),
            ), // outline-variant
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFF3F3F6), // surface-container-low
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// Build VAT rate dropdown
  Widget _buildVatRateDropdown() {
    final vatOptions = ['20.00% (Standard)', '5.00% (Reduced)', '0.00% (Zero)'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VAT Rate',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: const Color(0xFF424750)),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF727781)),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFFFFFFF),
          ),
          child: DropdownButton<String>(
            value: _selectedVatRate,
            isExpanded: true,
            underline: const SizedBox(),
            items: vatOptions.map((String option) {
              return DropdownMenuItem<String>(
                value: option,
                child: Text(
                  option,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedVatRate = newValue ?? _selectedVatRate;
              });
            },
          ),
        ),
      ],
    );
  }

  /// Build financial summary card
  Widget _buildFinancialSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFC2C6D1)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),

            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Subtotal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal (excl. VAT)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF424750),
                ),
              ),
              Text(
                '\$${_subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0xFFC2C6D1)),
          ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total (incl. VAT)',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '\$${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF003461), // primary
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build sticky bottom action bar
  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border(top: BorderSide(color: const Color(0xFFC2C6D1))),
      ),
      child: Row(
        children: [
          // Cancel Button
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFC2C6D1)),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),

          // Add to Order Button
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => _handleAddToOrder(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003461), // primary
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 2,
              ),
              child: const Text(
                'Add to Order',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle Add to Order action
  void _handleAddToOrder() {
    // TODO: Implement order item addition logic
    // This would typically:
    // 1. Validate all form inputs
    // 2. Create an OrderItem object
    // 3. Call a service/provider to add the item to the order
    // 4. Show success feedback
    // 5. Navigate back or clear the form

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $_quantity × $_productName to order'),
        duration: const Duration(seconds: 2),
      ),
    );

    // Navigate back after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Extract VAT percentage from the selected option
  double _extractVatPercentage(String vatOption) {
    return double.tryParse(vatOption.split('%')[0].trim()) ?? 0;
  }
}
