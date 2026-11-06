import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:enterprise_auth_mobile/core/secure_storage_service.dart';
import 'package:enterprise_auth_mobile/core/services/device_info_service.dart';
import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';

/// Document type enumeration for HIPO Document Numbering.
enum HipoDocType {
  invoice('INV', 'HI'),
  creditNote('CRN', 'HC'),
  returnNote('RTN', 'HR');

  final String code;
  final String prefix;
  const HipoDocType(this.code, this.prefix);

  static HipoDocType fromString(String type) {
    final upper = type.trim().toUpperCase();
    if (upper == 'CRN' || upper.contains('CREDIT')) return HipoDocType.creditNote;
    if (upper == 'RTN' || upper.contains('RETURN')) return HipoDocType.returnNote;
    return HipoDocType.invoice;
  }
}

/// Single Source of Truth for HIPO Document Numbering.
///
/// Formula: H + Inv type + financial site + lorry number + MM + YY + 5 digits sequence number
/// Examples:
///   - Invoice:     HIPOD57112600001
///   - Credit Note: HCPOD57112600001
///   - Return Note: HRPOD57112600001
/// (Total length: 16 characters <= 20 char Sage X3 NUM_0 / BPRVCR_0 limit).
class DocumentSequenceService {
  final LocalDatabaseHelper _dbHelper;

  DocumentSequenceService({LocalDatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? LocalDatabaseHelper.instance;

  /// Atomically generates the next unique document identifier.
  Future<String> generateDocumentNumber({
    required String docType, // 'INV', 'CRN', 'RTN'
    String? salesSite,
    String? lorryCode,
    String? deviceName,
    String? deviceId,
  }) async {
    final hipoType = HipoDocType.fromString(docType);
    final prefix = hipoType.prefix;

    final db = await _dbHelper.database;

    // 1. Resolve Sales Site & Financial Site
    String effectiveSalesSite = (salesSite ?? '').trim().toUpperCase();
    if (effectiveSalesSite.isEmpty || effectiveSalesSite == 'ALL') {
      final userSite = await SecureStorageService().getSiteCode();
      effectiveSalesSite = (userSite != null && userSite.isNotEmpty && userSite != 'ALL')
          ? userSite.trim().toUpperCase()
          : 'POD';
    }
    if (effectiveSalesSite == 'IPL') {
      // Legacy poultry normalization
      effectiveSalesSite = 'POD';
    }

    final financialSite = await _dbHelper.getFinancialSiteForSalesSite(effectiveSalesSite);
    final cleanFinSite = financialSite.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

    // 2. Resolve Device ID & Device Location Record
    final resolvedDeviceId = (deviceId != null && deviceId.isNotEmpty)
        ? deviceId
        : (DeviceInfoService.instance.deviceId.isNotEmpty
            ? DeviceInfoService.instance.deviceId
            : DeviceInfoService.instance.deviceInfo);

    Map<String, dynamic>? devLoc;
    try {
      devLoc = await _dbHelper.getDeviceLocation(resolvedDeviceId);
    } catch (_) {}

    // 3. Resolve Lorry Code
    String cleanLorry = (lorryCode ?? '').trim().toUpperCase();
    if (cleanLorry.isEmpty && devLoc != null && devLoc['locationCode'] != null) {
      cleanLorry = devLoc['locationCode'].toString().trim().toUpperCase();
    }
    if (cleanLorry.isEmpty) {
      // Fallback: pick the first lorry location registered for this site
      try {
        final locs = await db.query(
          LocalDatabaseHelper.tableLocations,
          where: '${LocalDatabaseHelper.colLocType} = ? AND ${LocalDatabaseHelper.colLocSite} = ?',
          whereArgs: ['LORRY', effectiveSalesSite],
          limit: 1,
        );
        if (locs.isNotEmpty && locs.first[LocalDatabaseHelper.colLocCode] != null) {
          cleanLorry = locs.first[LocalDatabaseHelper.colLocCode].toString().trim().toUpperCase();
        }
      } catch (_) {}
    }
    // Extract numeric lorry digits (e.g. '57' from 'Lorry 57', 'LORRY57', or '57')
    String lorryNum = cleanLorry.replaceAll(RegExp(r'[^0-9]'), '');
    if (lorryNum.isEmpty) {
      lorryNum = '00';
    } else if (lorryNum.length > 4) {
      lorryNum = lorryNum.substring(lorryNum.length - 4);
    }

    // 4. Compute Month & Year (MM + YY)
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final monthYear = '$mm$yy';

    // Defensive length guard ensuring financial site <= 4 chars
    final safeFinSite = cleanFinSite.length > 4 ? cleanFinSite.substring(0, 4) : cleanFinSite;

    // 5. Atomic SQLite Transaction for Concurrency & Zero Collision
    return await db.transaction((txn) async {
      final existingRows = await txn.query(
        LocalDatabaseHelper.tableDocumentSequences,
        where: 'docType = ? AND financialSite = ? AND lorryCode = ? AND yearMonth = ?',
        whereArgs: [hipoType.code, safeFinSite, lorryNum, monthYear],
        limit: 1,
      );

      int nextSeq = 1;
      if (existingRows.isNotEmpty) {
        nextSeq = ((existingRows.first['lastSequence'] as int?) ?? 0) + 1;
        await txn.update(
          LocalDatabaseHelper.tableDocumentSequences,
          {
            'lastSequence': nextSeq,
            'updatedAt': now.toIso8601String(),
          },
          where: 'docType = ? AND financialSite = ? AND lorryCode = ? AND yearMonth = ?',
          whereArgs: [hipoType.code, safeFinSite, lorryNum, monthYear],
        );
      } else {
        // Self-healing check: inspect local database for any pre-existing numbers matching prefix
        final prefixPattern = '$prefix$safeFinSite$lorryNum$monthYear%';
        int maxExisting = 0;
        try {
          final targetTable = (hipoType == HipoDocType.invoice)
              ? LocalDatabaseHelper.tableSiInvoices
              : LocalDatabaseHelper.tableSiCreditNotes;
          final idCol = (hipoType == HipoDocType.invoice) ? 'invoiceId' : 'creditNoteId';

          final checkRows = await txn.rawQuery(
            'SELECT $idCol FROM $targetTable WHERE $idCol LIKE ? ORDER BY $idCol DESC LIMIT 10',
            [prefixPattern],
          );
          for (final row in checkRows) {
            final val = (row[idCol] ?? '').toString();
            if (val.length >= prefixPattern.length - 1) {
              final suffix = val.substring(val.length - 5);
              final parsed = int.tryParse(suffix) ?? 0;
              if (parsed > maxExisting) maxExisting = parsed;
            }
          }
        } catch (_) {}

        nextSeq = maxExisting + 1;

        await txn.insert(
          LocalDatabaseHelper.tableDocumentSequences,
          {
            'docType': hipoType.code,
            'financialSite': safeFinSite,
            'lorryCode': lorryNum,
            'deviceTag': '0',
            'yearMonth': monthYear,
            'lastSequence': nextSeq,
            'updatedAt': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final seqStr = nextSeq.toString().padLeft(5, '0');
      // Single Source of Truth Formula:
      // H + Inv type + financial site + lorry number + MM + YY + 5 digits sequence number
      final generatedId = '$prefix$safeFinSite$lorryNum$monthYear$seqStr';

      debugPrint('DocumentSequenceService: Generated [$generatedId] for ${hipoType.code} (Site: $safeFinSite, Lorry: $lorryNum, MMYY: $monthYear)');
      return generatedId;
    });
  }
}
