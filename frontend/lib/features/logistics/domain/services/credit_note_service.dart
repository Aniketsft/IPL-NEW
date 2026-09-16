import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/models/credit_note_model.dart';

typedef DbProvider = Future<Database> Function();

class CreditNoteService {
  final DbProvider _dbProvider;

  CreditNoteService({DbProvider? dbProvider})
      : _dbProvider = dbProvider ?? (() => LocalDatabaseHelper.instance.database);

  Future<CreditNoteModel> createReversalCreditNote({
    required String invoiceId,
    required String createdBy,
    String? deviceId,
  }) async {
    final db = await _dbProvider();

    // 1. Fetch origin invoice
    final invRows = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );

    if (invRows.isEmpty) {
      throw StateError('Original invoice $invoiceId not found.');
    }

    final invoice = invRows.first;
    if ((invoice['isReversed'] as int? ?? 0) == 1) {
      throw StateError('Invoice $invoiceId has already been reversed.');
    }

    // 2. Fetch original payments to mirror settlement method
    final payments = await db.query(
      LocalDatabaseHelper.tableSiPayments,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );

    String settlementType = CreditNoteRefundMethod.cash;
    Map<String, dynamic>? primaryPayment;
    if (payments.isNotEmpty) {
      primaryPayment = payments.first;
      settlementType = (primaryPayment['method'] as String? ?? 'CASH').toUpperCase();
    }

    // 3. Fetch invoice lines
    final lines = await db.query(
      LocalDatabaseHelper.tableSiInvoiceLines,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      orderBy: 'lineId ASC',
    );

    final creditNoteId = 'CN-$invoiceId';
    final now = DateTime.now().toIso8601String();
    final grandTotal = (invoice['grandTotal'] as num?)?.toDouble() ?? 0.0;
    if (grandTotal <= 0) {
      throw StateError('Cannot reverse invoice: amount must be greater than zero.');
    }
    final salesSite = (invoice['salesSite'] as String?) ?? 'SCG';
    final customerCode = (invoice['customerCode'] as String?) ?? '';
    final customerName = (invoice['customerName'] as String?) ?? '';

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: CreditNoteType.reversal,
      x3CreditNoteType: 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: grandTotal,
      originalInvoiceId: invoiceId,
      settlementType: settlementType,
      reference: invoiceId,
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
    );

    await db.transaction((txn) async {
      // A. Insert credit note header
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      // B. Insert lean credit note lines & replenish stock
      int lineNo = 1000;
      for (final line in lines) {
        final originLineId = line['lineId'] as int;
        final qty = (line['quantity'] as num?)?.toDouble() ?? 0.0;

        await txn.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': qty,
          'originInvoiceId': invoiceId,
          'originLineNo': originLineId,
        });

        // Replenish stock
        final sku = line['sku'] as String?;
        final lotNumber = line['lotNumber'] as String?;
        final warehouse = line['warehouse'] as String?;
        final location = line['location'] as String?;

        if (sku != null && lotNumber != null && warehouse != null && location != null) {
          final updated = await txn.rawUpdate(
            '''
            UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
            SET totalQty = totalQty + ? 
            WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ?
            ''',
            [qty, sku, lotNumber, warehouse, location],
          );

          if (updated == 0) {
            await txn.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
              'itemCode': sku,
              'itemName': line['name'] ?? '',
              'lotNumber': lotNumber,
              'warehouse': warehouse,
              'location': location,
              'totalQty': qty,
              'taxLevel': line['taxRule'] ?? '',
              'cce0': line['cce0'] ?? '',
              'isSynced': 1,
              'createdAt': now,
            });
          }
        }

        lineNo += 1000;
      }

      // C. Insert refund record
      await txn.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
        'creditNoteId': creditNoteId,
        'method': settlementType,
        'amount': grandTotal,
        'bankCode': primaryPayment?['bankCode'],
        'bankName': primaryPayment?['bankName'],
        'chequeNumber': primaryPayment?['chequeNumber'],
        'chequeDate': primaryPayment?['chequeDate'],
      });

      // D. Mark origin invoice and lines as reversed
      await txn.update(
        LocalDatabaseHelper.tableSiInvoices,
        {'isReversed': 1},
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );

      await txn.update(
        LocalDatabaseHelper.tableSiInvoiceLines,
        {'isReversed': 1},
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
    });

    return creditNote;
  }

  /// Creates a credit note for a **partial** invoice reversal.
  ///
  /// [selectedLines] is a list of maps, each containing:
  ///   - 'lineId' (String): the original invoice line ID
  ///   - 'reversedQty' (double): how much quantity to reverse
  Future<CreditNoteModel> createPartialReversalCreditNote({
    required String invoiceId,
    required List<Map<String, dynamic>> selectedLines,
    required String createdBy,
    String? deviceId,
  }) async {
    if (selectedLines.isEmpty) {
      throw ArgumentError('At least one line must be selected for partial reversal.');
    }

    final db = await _dbProvider();

    // 1. Fetch origin invoice header
    final invRows = await db.query(
      LocalDatabaseHelper.tableSiInvoices,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invRows.isEmpty) throw StateError('Original invoice $invoiceId not found.');
    final invoice = invRows.first;
    if ((invoice['isReversed'] as int? ?? 0) == 1) {
      throw StateError('Invoice $invoiceId has already been fully reversed.');
    }

    // 2. Fetch original payments to mirror settlement method
    final payments = await db.query(
      LocalDatabaseHelper.tableSiPayments,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    String settlementType = CreditNoteRefundMethod.cash;
    Map<String, dynamic>? primaryPayment;
    if (payments.isNotEmpty) {
      primaryPayment = payments.first;
      settlementType = (primaryPayment['method'] as String? ?? 'CASH').toUpperCase();
    }

    // 3. Fetch all original invoice lines
    final allLines = await db.query(
      LocalDatabaseHelper.tableSiInvoiceLines,
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
    );
    final allLinesMap = {for (final l in allLines) l['lineId'].toString(): l};

    // 4. Pre-flight guard: check already-reversed quantities per line
    for (final sel in selectedLines) {
      final lineId = sel['lineId'].toString();
      final requestedQty = (sel['reversedQty'] as num).toDouble();
      final originalLine = allLinesMap[lineId];
      if (originalLine == null) throw StateError('Line $lineId not found in invoice $invoiceId.');
      final originalQty = (originalLine['quantity'] as num?)?.toDouble() ?? 0.0;

      final alreadyReversed = await db.rawQuery(
        'SELECT COALESCE(SUM(reversedQty), 0) as total FROM ${LocalDatabaseHelper.tableSiInvoiceLineReversals} WHERE invoiceId = ? AND lineId = ?',
        [invoiceId, lineId],
      );
      final alreadyQty = (alreadyReversed.first['total'] as num?)?.toDouble() ?? 0.0;
      final remaining = originalQty - alreadyQty;

      if (requestedQty <= 0) throw ArgumentError('Reversed quantity for line $lineId must be positive.');
      if (requestedQty > remaining) {
        throw StateError('Cannot reverse $requestedQty of line $lineId — only $remaining remaining.');
      }
    }

    // 5. Compute grand total from selected lines with pro-rated VAT and discount
    double grandTotal = 0.0;
    final creditNoteLineItems = <Map<String, dynamic>>[];
    for (final sel in selectedLines) {
      final lineId = sel['lineId'].toString();
      final reversedQty = (sel['reversedQty'] as num).toDouble();
      final originalLine = allLinesMap[lineId]!;
      final originalQty = (originalLine['quantity'] as num?)?.toDouble() ?? 1.0;
      final ratio = reversedQty / originalQty;

      final basePrice = (originalLine['basePrice'] as num?)?.toDouble() ?? 0.0;
      final discountAmount = ((originalLine['discountAmountFlat'] ?? originalLine['discountAmount']) as num?)?.toDouble() ?? 0.0;
      final vatAmount = (originalLine['vatAmount'] as num?)?.toDouble() ?? 0.0;

      final lineTotal = basePrice * reversedQty;
      final lineDisc = discountAmount * ratio;
      final lineVat = vatAmount * ratio;
      final lineNet = lineTotal - lineDisc + lineVat;
      grandTotal += lineNet;

      creditNoteLineItems.add({
        'lineId': lineId,
        'reversedQty': reversedQty,
        'originalLine': originalLine,
        'lineNet': lineNet,
      });
    }

    if (grandTotal <= 0) {
      throw StateError('Cannot create partial reversal credit note: total amount must be greater than zero.');
    }

    final creditNoteId = 'CN-P-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    final salesSite = (invoice['salesSite'] as String?) ?? 'SCG';
    final customerCode = (invoice['customerCode'] as String?) ?? '';
    final customerName = (invoice['customerName'] as String?) ?? '';

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: CreditNoteType.reversal,
      x3CreditNoteType: 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: grandTotal,
      originalInvoiceId: invoiceId,
      settlementType: settlementType,
      reference: invoiceId,
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
    );

    await db.transaction((txn) async {
      // A. Insert credit note header
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      int lineNo = 1000;
      for (final item in creditNoteLineItems) {
        final lineId = item['lineId'] as String;
        final reversedQty = item['reversedQty'] as double;
        final originalLine = item['originalLine'] as Map<String, dynamic>;

        // B. Insert credit note line
        await txn.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': reversedQty,
          'originInvoiceId': invoiceId,
          'originLineNo': lineId,
        });

        // C. Record this reversal in tbl_si_invoice_line_reversals
        await txn.insert(LocalDatabaseHelper.tableSiInvoiceLineReversals, {
          'invoiceId': invoiceId,
          'lineId': lineId,
          'reversedQty': reversedQty,
          'reversalCreditNoteId': creditNoteId,
          'createdAt': now,
        });

        // D. Replenish stock (partial quantity only — atomically with credit note insert)
        final sku = originalLine['sku'] as String?;
        final lotNumber = originalLine['lotNumber'] as String?;
        final warehouse = originalLine['warehouse'] as String?;
        final location = originalLine['location'] as String?;
        if (sku != null && lotNumber != null && warehouse != null && location != null) {
          final updated = await txn.rawUpdate(
            'UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} SET totalQty = totalQty + ? WHERE itemCode = ? AND lotNumber = ? AND warehouse = ? AND location = ?',
            [reversedQty, sku, lotNumber, warehouse, location],
          );
          if (updated == 0) {
            await txn.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
              'itemCode': sku,
              'itemName': originalLine['name'] ?? '',
              'lotNumber': lotNumber,
              'warehouse': warehouse,
              'location': location,
              'totalQty': reversedQty,
              'taxLevel': originalLine['taxRule'] ?? '',
              'cce0': originalLine['cce0'] ?? '',
              'isSynced': 1,
              'createdAt': now,
            });
          }
        }

        lineNo += 1000;
      }

      // E. Insert refund record
      await txn.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
        'creditNoteId': creditNoteId,
        'method': settlementType,
        'amount': grandTotal,
        'bankCode': primaryPayment?['bankCode'],
        'bankName': primaryPayment?['bankName'],
        'chequeNumber': primaryPayment?['chequeNumber'],
        'chequeDate': primaryPayment?['chequeDate'],
      });

      // F. Check if ALL lines are now fully reversed → flip isReversed = 1, else isPartiallyReversed = 1
      bool allFullyReversed = true;
      for (final originalLine in allLines) {
        final lineId = originalLine['lineId'].toString();
        final originalQty = (originalLine['quantity'] as num?)?.toDouble() ?? 0.0;
        final reversalRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(reversedQty), 0) as total FROM ${LocalDatabaseHelper.tableSiInvoiceLineReversals} WHERE invoiceId = ? AND lineId = ?',
          [invoiceId, lineId],
        );
        final totalReversed = (reversalRows.first['total'] as num?)?.toDouble() ?? 0.0;
        if (totalReversed < originalQty) {
          allFullyReversed = false;
          break;
        }
      }

      await txn.update(
        LocalDatabaseHelper.tableSiInvoices,
        allFullyReversed
            ? {'isReversed': 1, 'isPartiallyReversed': 0}
            : {'isPartiallyReversed': 1},
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
    });

    return creditNote;
  }

  Future<CreditNoteModel> createStandaloneCreditNote({
    required String salesSite,
    required String customerCode,
    required String customerName,
    required String refundMethod,
    required double refundAmount,
    required List<CreditNoteLineModel> items,
    required String createdBy,
    String? deviceId,
    String? reference,
  }) async {
    final methodUpper = refundMethod.toUpperCase();
    if (methodUpper == 'QR' || methodUpper.contains('QR')) {
      throw ArgumentError('QR Code refund is strictly disabled for Credit Notes.');
    }

    if (refundAmount <= 0) {
      throw ArgumentError('Credit note refund amount must be greater than zero.');
    }

    if (items.isEmpty) {
      throw ArgumentError('Standalone credit note must contain at least one product.');
    }

    final db = await _dbProvider();
    final creditNoteId = 'CN-ST-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: CreditNoteType.standalone,
      x3CreditNoteType: 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: refundAmount,
      settlementType: methodUpper,
      reference: reference,
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
    );

    await db.transaction((txn) async {
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      int lineNo = 1000;
      for (final item in items) {
        await txn.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': item.quantity,
          'standaloneSku': item.standaloneSku ?? item.sku,
          'standaloneName': item.standaloneName ?? item.name,
          'standaloneSalesUnit': item.standaloneSalesUnit ?? item.salesUnit,
          'standalonePrice': item.standalonePrice ?? item.price,
          'standaloneTaxRule': item.standaloneTaxRule ?? item.taxRule,
          'standaloneLot': item.standaloneLot ?? item.lot,
          'standaloneWarehouse': item.standaloneWarehouse ?? item.warehouse,
          'standaloneCce0': item.standaloneCce0 ?? item.cce0,
        });

        // Replenish stock
        final sku = item.standaloneSku ?? item.sku;
        final lot = item.standaloneLot ?? item.lot;
        final wh = item.standaloneWarehouse ?? item.warehouse;
        final loc = 'LOC1'; // default location if not specified

        if (sku.isNotEmpty && lot.isNotEmpty && wh.isNotEmpty) {
          final updated = await txn.rawUpdate(
            '''
            UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
            SET totalQty = totalQty + ? 
            WHERE itemCode = ? AND lotNumber = ? AND warehouse = ?
            ''',
            [item.quantity, sku, lot, wh],
          );

          if (updated == 0) {
            await txn.insert(LocalDatabaseHelper.tableSalesInvoiceItemStockDetails, {
              'itemCode': sku,
              'itemName': item.standaloneName ?? item.name,
              'lotNumber': lot,
              'warehouse': wh,
              'location': loc,
              'totalQty': item.quantity,
              'taxLevel': item.standaloneTaxRule ?? item.taxRule,
              'cce0': item.standaloneCce0 ?? item.cce0,
              'isSynced': 1,
              'createdAt': now,
            });
          }
        }

        lineNo += 1000;
      }

      await txn.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
        'creditNoteId': creditNoteId,
        'method': methodUpper,
        'amount': refundAmount,
      });
    });

    return creditNote;
  }

  Future<CreditNoteModel> createAmountOnlyCreditNote({
    required String salesSite,
    required String customerCode,
    required String customerName,
    required double refundAmount,
    required List<String> linkedInvoiceIds,
    List<CreditNoteLineModel> returnedItems = const [],
    required String createdBy,
    String? deviceId,
    String? reference,
  }) async {
    if (linkedInvoiceIds.isEmpty) {
      throw ArgumentError('Amount-only credit note requires at least 1 linked invoice.');
    }

    if (refundAmount <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }

    final db = await _dbProvider();

    // Check available balance across linked invoices
    final placeholders = List.filled(linkedInvoiceIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT invoiceId, grandTotal 
      FROM ${LocalDatabaseHelper.tableSiInvoices} 
      WHERE invoiceId IN ($placeholders)
      ''',
      linkedInvoiceIds,
    );

    double totalBalance = 0.0;
    for (final r in rows) {
      totalBalance += (r['grandTotal'] as num?)?.toDouble() ?? 0.0;
    }

    if (refundAmount > totalBalance) {
      throw ArgumentError(
        'Refund amount ($refundAmount) exceeds linked invoice total balance ($totalBalance).',
      );
    }

    final creditNoteId = 'CN-AMT-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();

    final creditNote = CreditNoteModel(
      creditNoteId: creditNoteId,
      creditNoteType: CreditNoteType.amountOnly,
      x3CreditNoteType: 'CRN',
      salesSite: salesSite,
      customerCode: customerCode,
      customerName: customerName,
      currency: 'MUR',
      grandTotal: refundAmount,
      linkedInvoiceIds: linkedInvoiceIds,
      settlementType: CreditNoteRefundMethod.cash,
      reference: reference ?? linkedInvoiceIds.join(','),
      isSynced: 0,
      createdAt: now,
      createdBy: createdBy,
      deviceId: deviceId,
    );

    await db.transaction((txn) async {
      await txn.insert(LocalDatabaseHelper.tableSiCreditNotes, creditNote.toMap());

      await txn.insert(LocalDatabaseHelper.tableSiCreditNoteRefunds, {
        'creditNoteId': creditNoteId,
        'method': CreditNoteRefundMethod.cash,
        'amount': refundAmount,
      });

      int lineNo = 1000;
      for (final item in returnedItems) {
        await txn.insert(LocalDatabaseHelper.tableSiCreditNoteLines, {
          'creditNoteId': creditNoteId,
          'lineNo': lineNo,
          'quantity': item.quantity,
          'originInvoiceId': item.originInvoiceId,
          'originLineNo': item.originLineNo,
          'standaloneSku': item.standaloneSku ?? item.sku,
          'standaloneName': item.standaloneName ?? item.name,
          'standaloneSalesUnit': item.standaloneSalesUnit ?? item.salesUnit,
          'standalonePrice': item.standalonePrice ?? item.price,
          'standaloneTaxRule': item.standaloneTaxRule ?? item.taxRule,
          'standaloneLot': item.standaloneLot ?? item.lot,
          'standaloneWarehouse': item.standaloneWarehouse ?? item.warehouse,
          'standaloneCce0': item.standaloneCce0 ?? item.cce0,
        });

        // Add back to stock
        final sku = item.standaloneSku ?? item.sku;
        final lot = item.standaloneLot ?? item.lot;
        final wh = item.standaloneWarehouse ?? item.warehouse;
        if (sku.isNotEmpty && lot.isNotEmpty && wh.isNotEmpty) {
          await txn.rawUpdate(
            '''
            UPDATE ${LocalDatabaseHelper.tableSalesInvoiceItemStockDetails} 
            SET totalQty = totalQty + ? 
            WHERE itemCode = ? AND lotNumber = ? AND warehouse = ?
            ''',
            [item.quantity, sku, lot, wh],
          );
        }

        lineNo += 1000;
      }
    });

    return creditNote;
  }

  /// Backward-compatible alias for createAmountOnlyCreditNote
  Future<CreditNoteModel> createCashOnlyCreditNote({
    required String salesSite,
    required String customerCode,
    required String customerName,
    required double refundAmount,
    required List<String> linkedInvoiceIds,
    List<CreditNoteLineModel> returnedItems = const [],
    required String createdBy,
    String? deviceId,
    String? reference,
  }) => createAmountOnlyCreditNote(
    salesSite: salesSite,
    customerCode: customerCode,
    customerName: customerName,
    refundAmount: refundAmount,
    linkedInvoiceIds: linkedInvoiceIds,
    returnedItems: returnedItems,
    createdBy: createdBy,
    deviceId: deviceId,
    reference: reference,
  );
}
