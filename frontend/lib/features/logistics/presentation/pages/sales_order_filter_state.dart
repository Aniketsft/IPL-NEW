/// Lightweight persistent filter state for [ViewSalesOrderScreen].
/// Survives navigation push/pop within the same app session.
class SalesOrderFilterState {
  static DateTime? selectedDate;
  static String status = 'open';
  static String? selectedCustomerCode;
  static String? selectedSalesmanCode;
  static String poTypeFilter = 'ALL';
  static String searchQuery = '';

  static void reset() {
    selectedDate = null;
    status = 'open';
    selectedCustomerCode = null;
    selectedSalesmanCode = null;
    poTypeFilter = 'ALL';
    searchQuery = '';
  }
}
