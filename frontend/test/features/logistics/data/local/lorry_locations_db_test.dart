import 'package:enterprise_auth_mobile/features/logistics/data/local/local_database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  final helper = LocalDatabaseHelper.instance;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE ${LocalDatabaseHelper.tableLocations} (
        ${LocalDatabaseHelper.colLocCode} TEXT NOT NULL,
        ${LocalDatabaseHelper.colLocWrh} TEXT,
        ${LocalDatabaseHelper.colLocWrhName} TEXT,
        ${LocalDatabaseHelper.colLocType} TEXT,
        ${LocalDatabaseHelper.colLocTypeName} TEXT,
        ${LocalDatabaseHelper.colLocSite} TEXT NOT NULL DEFAULT 'POD',
        PRIMARY KEY (${LocalDatabaseHelper.colLocCode}, ${LocalDatabaseHelper.colLocSite})
      )
    ''');
    LocalDatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    LocalDatabaseHelper.setTestDatabase(null);
    await db.close();
  });

  test('saveLocations and getLorryLocations keep SCG lorries and WEB while filtering damage bays', () async {
    await helper.saveLocations(
      [
        {
          'site': 'SCG',
          'location': 'N3',
          'warehouse': 'N3',
          'warehouseName': '9418 DC 12 former 30',
          'locationType': 'N3',
          'plateNumber': '5308 JL 16 (former 30)',
        },
        {
          'site': 'SCG',
          'location': 'N6',
          'warehouse': 'N6',
          'warehouseName': '5308 JL 16 former 62',
          'locationType': 'N6',
          'plateNumber': '9418 DC 12 (former 62)',
        },
        {
          'site': 'SCG',
          'location': 'N8',
          'warehouse': 'N8',
          'warehouseName': '398 JN 15 former 81',
          'locationType': 'N8',
          'plateNumber': '398 JN 15 (former 81)',
        },
        {
          'site': 'SCG',
          'location': 'SCGDAM',
          'warehouse': 'SCG',
          'warehouseName': 'Consumer Shop To Shop',
          'locationType': 'CGDAM',
          'plateNumber': 'SCG Damage',
        },
        {
          'site': 'SCG',
          'location': 'WEB',
          'warehouse': 'WEB',
          'warehouseName': 'WEB',
          'locationType': 'WEB',
          'plateNumber': 'SCG-WEB',
        },
      ],
      siteCode: 'SCG',
      replaceSite: true,
    );

    final lorries = await helper.getLorryLocations(siteCode: 'scg');
    final codes = lorries.map((e) => e['location'] as String).toList();

    expect(codes, equals(['N3', 'N6', 'N8', 'WEB']));
    expect(lorries.first['locationTypeName'], equals('5308 JL 16 (former 30)'));
  });

  test('composite (location, site) primary key isolates same location codes across sites', () async {
    await helper.saveLocations(
      [
        {'location': 'WEB', 'warehouse': 'WEB', 'locationType': 'WEB', 'plateNumber': 'POD-WEB'},
      ],
      siteCode: 'POD',
      replaceSite: true,
    );
    await helper.saveLocations(
      [
        {'location': 'WEB', 'warehouse': 'WEB', 'locationType': 'WEB', 'plateNumber': 'SCG-WEB'},
      ],
      siteCode: 'SCG',
      replaceSite: true,
    );

    final podRows = await helper.getLorryLocations(siteCode: 'POD');
    final scgRows = await helper.getLorryLocations(siteCode: 'SCG');

    expect(podRows.length, equals(1));
    expect(podRows.first['locationTypeName'], equals('POD-WEB'));
    expect(scgRows.length, equals(1));
    expect(scgRows.first['locationTypeName'], equals('SCG-WEB'));

    // Refreshing POD must preserve SCG rows while replacing POD's stale entries
    await helper.saveLocations(
      [
        {'location': '57', 'warehouse': 'POD', 'locationType': 'LORRY', 'plateNumber': '2818 JL 09'},
      ],
      siteCode: 'POD',
      replaceSite: true,
    );

    final updatedPod = await helper.getLorryLocations(siteCode: 'POD');
    final untouchedScg = await helper.getLocations(siteCode: 'scg');

    expect(updatedPod.map((e) => e['location']).toList(), equals(['57']));
    expect(untouchedScg.map((e) => e['location']).toList(), equals(['WEB']));
  });
}
