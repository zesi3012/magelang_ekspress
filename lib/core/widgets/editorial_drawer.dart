import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../design/app_typography.dart';

class EditorialDrawer extends StatelessWidget {
  const EditorialDrawer({
    super.key,
    required this.selectedIndex,
    required this.selectedCategory,
    required this.selectedLocation,
    required this.onNavigate,
    required this.onSaved,
    required this.onCategory,
    required this.onLocationSelected,
    required this.onClose,
    this.persistent = false,
  });

  final int selectedIndex;
  final String selectedCategory;
  final String? selectedLocation;
  final ValueChanged<int> onNavigate;
  final VoidCallback onSaved;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onLocationSelected;
  final VoidCallback onClose;
  final bool persistent;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MAGELANG EKSPRES',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!persistent)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Tutup',
                    onPressed: onClose,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'NAVIGASI UTAMA',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: AppSpacing.xl),
            _item(
              Icons.home_outlined,
              'Beranda',
              selected: selectedIndex == 0,
              onTap: () => onNavigate(0),
            ),
            _item(
              Icons.menu_book_outlined,
              'E-Paper',
              selected: selectedIndex == 1,
              onTap: () => onNavigate(1),
            ),
            _item(Icons.bookmark_border, 'Tersimpan', onTap: onSaved),
            _item(
              Icons.card_membership_outlined,
              'Langganan',
              selected: selectedIndex == 2,
              onTap: () => onNavigate(2),
            ),
            _item(
              Icons.person_outline,
              'Akun',
              selected: selectedIndex == 3,
              onTap: () => onNavigate(3),
            ),
            const Divider(height: AppSpacing.xl),
            const _SectionLabel('KATEGORI BERITA'),
            _item(Icons.public, 'Nasional', category: 'NASIONAL'),
            _item(
              Icons.location_city_outlined,
              'Jawa Tengah',
              category: 'JATENG',
            ),
            _item(Icons.payments_outlined, 'Ekonomi', category: 'EKONOMI'),
            _item(
              Icons.park_outlined,
              'Kampung Inovatif',
              category: 'KAMPUNG INOVATIF',
            ),
            _item(
              Icons.school_outlined,
              'Koran Sekolah',
              category: 'KORAN SEKOLAH',
            ),
            _item(Icons.travel_explore_outlined, 'Wisata', category: 'WISATA'),
            _item(
              Icons.auto_awesome_outlined,
              'Lifestyle',
              category: 'LIFESTYLE',
            ),
            _item(Icons.edit_note_outlined, 'Opini', category: 'OPINI'),
            _item(Icons.menu_book_outlined, 'Catatan', category: 'CATATAN'),
            const Divider(height: AppSpacing.xl),
            const _SectionLabel('LOKAL'),
            _item(
              Icons.location_on_outlined,
              'Kota Magelang',
              category: 'MAGELANG KOTA',
              location: 'Kota Magelang',
            ),
            _item(
              Icons.map_outlined,
              'Kabupaten Magelang',
              category: 'KABUPATEN MAGELANG',
              location: 'Kabupaten Magelang',
            ),
            _item(
              Icons.terrain_outlined,
              'Temanggung',
              category: 'JATENG',
              location: 'Temanggung',
            ),
            _item(
              Icons.route_outlined,
              'Purworejo',
              category: 'JATENG',
              location: 'Purworejo',
            ),
          ],
        ),
      ),
    ),
  );

  Widget _item(
    IconData icon,
    String label, {
    String? category,
    String? location,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final isSelected = location != null
        ? selectedLocation == location && selectedIndex == 0
        : category == null
        ? selected
        : selectedCategory == category && selectedIndex == 0;
    return Material(
      color: isSelected
          ? AppColors.navy.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey(
          'editorial-drawer-${label.toLowerCase().replaceAll(' ', '-')}',
        ),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (category != null) {
            onCategory(category);
            if (location != null) onLocationSelected(location);
          } else {
            onTap?.call();
          }
          onClose();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.red : AppColors.navy,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? AppColors.red : AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.label.copyWith(
      color: AppColors.muted,
      letterSpacing: 1.2,
    ),
  );
}
