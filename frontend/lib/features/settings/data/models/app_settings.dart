import 'company.dart';
import 'site.dart';

class AppSettings {
  final List<Company> availableCompanies;
  final List<Site> availableSites;
  final List<int> decimalOptions;

  final String selectedCompanyId;
  final String selectedSiteId;
  final int selectedQuantityDecimals;

  // Global Synchronized Settings
  final String? dailyLotNumber;
  final String? lastLotDate; // YYYY-MM-DD
  final String? excessDefaultCustomer;
  final String? excessDefaultSalesman;
  final double? tolerancePercentage;

  AppSettings({
    required this.availableCompanies,
    required this.availableSites,
    required this.decimalOptions,
    required this.selectedCompanyId,
    required this.selectedSiteId,
    required this.selectedQuantityDecimals,
    this.dailyLotNumber,
    this.lastLotDate,
    this.excessDefaultCustomer,
    this.excessDefaultSalesman,
    this.tolerancePercentage,
  });

  factory AppSettings.mock() {
    final companies = Company.mockCompanies;
    final sites = Site.mockSites;
    return AppSettings(
      availableCompanies: companies,
      availableSites: sites,
      decimalOptions: [0, 1, 2, 3],
      selectedCompanyId: companies.first.id,
      selectedSiteId: sites.first.id,
      selectedQuantityDecimals: 2,
    );
  }

  AppSettings copyWith({
    List<Company>? availableCompanies,
    List<Site>? availableSites,
    List<int>? decimalOptions,
    String? selectedCompanyId,
    String? selectedSiteId,
    int? selectedQuantityDecimals,
    String? dailyLotNumber,
    String? lastLotDate,
    String? excessDefaultCustomer,
    String? excessDefaultSalesman,
    double? tolerancePercentage,
  }) {
    return AppSettings(
      availableCompanies: availableCompanies ?? this.availableCompanies,
      availableSites: availableSites ?? this.availableSites,
      decimalOptions: decimalOptions ?? this.decimalOptions,
      selectedCompanyId: selectedCompanyId ?? this.selectedCompanyId,
      selectedSiteId: selectedSiteId ?? this.selectedSiteId,
      selectedQuantityDecimals:
          selectedQuantityDecimals ?? this.selectedQuantityDecimals,
      dailyLotNumber: dailyLotNumber ?? this.dailyLotNumber,
      lastLotDate: lastLotDate ?? this.lastLotDate,
      excessDefaultCustomer: excessDefaultCustomer ?? this.excessDefaultCustomer,
      excessDefaultSalesman: excessDefaultSalesman ?? this.excessDefaultSalesman,
      tolerancePercentage: tolerancePercentage ?? this.tolerancePercentage,
    );
  }
}
