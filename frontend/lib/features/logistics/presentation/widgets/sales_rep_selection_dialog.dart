import 'package:flutter/material.dart';
import '../../data/local/local_database_helper.dart';
import '../../data/models/sales_rep_model.dart';
import '../../data/repositories/sales_invoice_sync_repository.dart';

class SalesRepSelectionDialog extends StatefulWidget {
  final bool canDismiss;
  final String? userSiteCode;
  final SalesInvoiceSyncRepository? syncRepository;
  final String? username;

  const SalesRepSelectionDialog({
    super.key,
    this.canDismiss = false,
    this.userSiteCode,
    this.syncRepository,
    this.username,
  });

  static Future<List<SalesRepModel>?> show(
    BuildContext context, {
    bool canDismiss = false,
    String? userSiteCode,
    SalesInvoiceSyncRepository? syncRepository,
    String? username,
  }) {
    return showDialog<List<SalesRepModel>>(
      context: context,
      barrierDismissible: canDismiss,
      builder: (ctx) => SalesRepSelectionDialog(
        canDismiss: canDismiss,
        userSiteCode: userSiteCode,
        syncRepository: syncRepository,
        username: username,
      ),
    );
  }

  @override
  State<SalesRepSelectionDialog> createState() => _SalesRepSelectionDialogState();
}

class _SalesRepSelectionDialogState extends State<SalesRepSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<SalesRepModel> _allReps = [];
  List<SalesRepModel> _filteredReps = [];
  final Set<String> _selectedCodes = {};
  Set<String> _initialCodes = {};
  bool _isLoading = true;
  String? _errorMessage;

  bool get _hasInitialSelection => _initialCodes.isNotEmpty;
  bool get _isSelectionModified =>
      _selectedCodes.length != _initialCodes.length ||
      !_selectedCodes.containsAll(_initialCodes);

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredReps = List.from(_allReps);
      } else {
        _filteredReps = _allReps.where((rep) {
          final codeMatch = rep.code.toLowerCase().contains(query);
          final nameMatch = rep.name.toLowerCase().contains(query);
          final siteMatch = rep.assignedSite.toLowerCase().contains(query);
          return codeMatch || nameMatch || siteMatch;
        }).toList();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Load active selections from SQLite
      final currentSelected = await LocalDatabaseHelper.instance.getSelectedSalesReps(
        username: widget.username,
      );
      final currentSelectedCodes = currentSelected
          .map((m) => (m['code'] ?? '').toString())
          .where((c) => c.isNotEmpty)
          .toSet();

      // 2. Fetch available reps (try online sync repo first if provided, then fallback to local SQLite)
      List<SalesRepModel> loadedReps = [];
      if (widget.syncRepository != null) {
        try {
          loadedReps = await widget.syncRepository!.fetchAndSyncSalesReps(
            siteCode: widget.userSiteCode,
          );
        } catch (_) {}
      }

      if (loadedReps.isEmpty) {
        final localData = await LocalDatabaseHelper.instance.getSalesReps(
          siteCode: widget.userSiteCode,
        );
        loadedReps = localData.map((m) => SalesRepModel.fromMap(m)).toList();
      }

      // If site filter gave 0 reps, fallback to all reps
      if (loadedReps.isEmpty) {
        final allLocal = await LocalDatabaseHelper.instance.getSalesReps();
        loadedReps = allLocal.map((m) => SalesRepModel.fromMap(m)).toList();
      }

      setState(() {
        _allReps = loadedReps;
        _filteredReps = List.from(loadedReps);
        _selectedCodes.addAll(currentSelectedCodes);
        _initialCodes = Set.from(currentSelectedCodes);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load sales reps: $e';
      });
    }
  }

  void _toggleSelect(SalesRepModel rep) {
    setState(() {
      if (_selectedCodes.contains(rep.code)) {
        _selectedCodes.remove(rep.code);
      } else {
        _selectedCodes.add(rep.code);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedCodes.clear();
    });
  }

  void _revertChanges() {
    setState(() {
      _selectedCodes.clear();
      _selectedCodes.addAll(_initialCodes);
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one sales representative to continue.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final selectedReps = _allReps.where((r) => _selectedCodes.contains(r.code)).toList();

    // Persist into SQLite
    await LocalDatabaseHelper.instance.saveSelectedSalesReps(
      selectedReps.map((r) => r.toMap()).toList(),
      username: widget.username,
    );

    if (mounted) {
      Navigator.of(context).pop(selectedReps);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: widget.canDismiss,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 16,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.badge_outlined,
                      color: theme.primaryColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasInitialSelection
                              ? (_isSelectionModified
                                  ? 'Update Sales Representative'
                                  : 'Verify Sales Representative')
                              : 'Sales Representative',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _hasInitialSelection
                              ? (_isSelectionModified
                                  ? 'Active selection modified. Verify to avoid mistakes.'
                                  : 'Active sales reps already selected. Verify to ensure no mistake.')
                              : 'Select one or multiple reps for transactions',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.canDismiss)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                ],
              ),
              if (_hasInitialSelection) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isSelectionModified
                        ? Colors.amber.withOpacity(0.12)
                        : Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSelectionModified
                          ? Colors.amber.withOpacity(0.4)
                          : Colors.blue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSelectionModified
                            ? Icons.warning_amber_rounded
                            : Icons.verified_user_outlined,
                        color: _isSelectionModified
                            ? Colors.amber[800]
                            : (isDark ? Colors.lightBlueAccent : theme.primaryColor),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isSelectionModified
                                  ? 'Selection Changed - Please Review'
                                  : 'Active Sales Reps Already Selected',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _isSelectionModified
                                    ? (isDark ? Colors.amber[200] : Colors.amber[900])
                                    : (isDark ? Colors.lightBlueAccent : theme.primaryColor),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isSelectionModified
                                  ? 'Active selection changed. Please make sure there are no mistakes before saving.'
                                  : 'Active sales reps are pre-selected. Please make sure there are no mistakes before confirming.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isSelectionModified)
                        TextButton(
                          onPressed: _revertChanges,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Revert', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Search Bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by code, name, or site...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? Colors.grey.shade900
                      : Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Selection Toolbar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedCodes.length} selected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selectedCodes.isNotEmpty
                          ? theme.primaryColor
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                  if (_selectedCodes.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              const Divider(height: 16),

              // Content List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
                                  const SizedBox(height: 8),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: _loadData,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _filteredReps.isEmpty
                            ? Center(
                                child: Text(
                                  'No sales representatives found.',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _filteredReps.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                                ),
                                itemBuilder: (context, index) {
                                  final rep = _filteredReps[index];
                                  final isSelected = _selectedCodes.contains(rep.code);

                                  return Material(
                                    color: isSelected
                                        ? theme.primaryColor.withOpacity(0.08)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _toggleSelect(rep),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: isSelected,
                                              activeColor: theme.primaryColor,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              onChanged: (_) => _toggleSelect(rep),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        rep.code,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                          color: isDark ? Colors.white : Colors.black87,
                                                        ),
                                                      ),
                                                      if (rep.assignedSite.isNotEmpty) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: theme.colorScheme.secondary.withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            rep.assignedSite,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                              color: theme.colorScheme.secondary,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    rep.name,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: isDark ? Colors.white70 : Colors.black87,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              if (_hasInitialSelection && _isSelectionModified)
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _revertChanges,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                        ),
                        child: const Text(
                          'REVERT',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading || _selectedCodes.isEmpty ? null : _confirmSelection,
                        icon: const Icon(Icons.save_as_outlined, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        label: Text(
                          _selectedCodes.isEmpty
                              ? 'SELECT AT LEAST ONE'
                              : 'UPDATE & SAVE (${_selectedCodes.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _isLoading || _filteredReps.isEmpty || _selectedCodes.isEmpty
                      ? null
                      : _confirmSelection,
                  icon: Icon(
                    _hasInitialSelection ? Icons.verified_outlined : Icons.check_circle_outline,
                    size: 18,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  label: Text(
                    _selectedCodes.isEmpty
                        ? 'SELECT AT LEAST ONE REP'
                        : (_hasInitialSelection
                            ? 'CONFIRM & KEEP ACTIVE (${_selectedCodes.length})'
                            : 'CONFIRM (${_selectedCodes.length}) SELECTED'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
