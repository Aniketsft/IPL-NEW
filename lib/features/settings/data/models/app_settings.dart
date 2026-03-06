import 'company.dart';
import 'site.dart';

class AppSettings {
  final List<Company> availableCompanies;
  final List<Site> availableSites;
  final List<int> decimalOptions;

  final String selectedCompanyId;
  final String selectedSiteId;
  final int selectedQuantityDecimals;

  AppSettings({
    required this.availableCompanies,
    required this.availableSites,
    required this.decimalOptions,
    required this.selectedCompanyId,
    required this.selectedSiteId,
    required this.selectedQuantityDecimals,
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
  }) {
    return AppSettings(
      availableCompanies: availableCompanies ?? this.availableCompanies,
      availableSites: availableSites ?? this.availableSites,
      decimalOptions: decimalOptions ?? this.decimalOptions,
      selectedCompanyId: selectedCompanyId ?? this.selectedCompanyId,
      selectedSiteId: selectedSiteId ?? this.selectedSiteId,
      selectedQuantityDecimals:
          selectedQuantityDecimals ?? this.selectedQuantityDecimals,
    );
  }
}
