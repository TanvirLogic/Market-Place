import 'package:flutter/material.dart';
import 'package:edtech/features/profile/edit/data/country.dart';
import 'package:edtech/features/profile/edit/data/country_service.dart';

class CountryPickerField extends StatefulWidget {
  final Country? selected;
  final ValueChanged<Country> onChanged;
  final String? errorText;

  const CountryPickerField({
    super.key,
    this.selected,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<CountryPickerField> createState() => _CountryPickerFieldState();
}

class _CountryPickerFieldState extends State<CountryPickerField> {
  List<Country> _countries = CountryService().cached ?? [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_countries.isNotEmpty) return;
    setState(() => _loading = true);
    _countries = await CountryService().fetch();
    if (mounted) setState(() => _loading = false);
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CountryPickerSheet(
        countries: _countries,
        selected: widget.selected,
        onSelected: (c) {
          widget.onChanged(c);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Country',
          style: TextStyle(fontSize: 14, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _loading ? null : _openPicker,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.errorText != null ? cs.error : cs.outlineVariant,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (widget.selected != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Image.network(
                      widget.selected!.flagPng,
                      width: 24,
                      height: 16,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 24, height: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.selected!.name,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    _loading ? 'Loading countries...' : 'Select country',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(Icons.keyboard_arrow_down, color: cs.onSurface.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              widget.errorText!,
              style: TextStyle(fontSize: 11, color: cs.error),
            ),
          ),
      ],
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  final List<Country> countries;
  final Country? selected;
  final ValueChanged<Country> onSelected;

  const _CountryPickerSheet({
    required this.countries,
    this.selected,
    required this.onSelected,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  late List<Country> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.countries;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final query = q.toLowerCase();
    setState(() {
      _filtered = widget.countries.where((c) =>
        c.name.toLowerCase().contains(query) ||
        c.dialCode.contains(query),
      ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Search country...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final c = _filtered[i];
                  final isSelected = widget.selected?.name == c.name;
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Image.network(
                        c.flagPng,
                        width: 28,
                        height: 20,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(width: 28, height: 20),
                      ),
                    ),
                    title: Text(c.name),
                    trailing: Text(
                      c.dialCode,
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                    selected: isSelected,
                    selectedTileColor: cs.primary.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () => widget.onSelected(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
