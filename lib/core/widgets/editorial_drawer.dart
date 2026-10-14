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
                // ===== HEADER BRAND + TAGLINE (sesuai blueprint) =====
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MAGELANG EKSPRES',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Akurat, Terpercaya, dan Menginspirasi',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!persistent)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Tutup',
                        onPressed: onClose,
                        splashRadius: 20,
                      ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel('NAVIGASI UTAMA'),
                const Divider(height: AppSpacing.xl),

                // ===== NAVIGASI UTAMA =====
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
                const _SectionLabel('REDAKSIONAL'),

                // ===== KATEGORI REDAKSIONAL (sesuai blueprint) =====
                _item(Icons.public, 'Nasional', category: 'NASIONAL'),
                _item(
                  Icons.school_outlined,
                  'Pendidikan',
                  category: 'PENDIDIKAN',
                ),
                _item(
                  Icons.location_city_outlined,
                  'Jawa Tengah',
                  category: 'JATENG',
                ),
                _item(Icons.payments_outlined, 'Ekonomi', category: 'EKONOMI'),
                _item(
                  Icons.sports_soccer_outlined,
                  'Olahraga',
                  category: 'OLAHRAGA',
                ),
                _item(
                  Icons.park_outlined,
                  'Lingkungan',
                  category: 'LINGKUNGAN',
                ),
                _item(
                  Icons.travel_explore_outlined,
                  'Wisata',
                  category: 'WISATA',
                ),
                _item(
                  Icons.auto_awesome_outlined,
                  'Lifestyle',
                  category: 'LIFESTYLE',
                ),
                _item(Icons.edit_note_outlined, 'Opini', category: 'OPINI'),
                _item(
                  Icons.menu_book_outlined,
                  'Catatan',
                  category: 'CATATAN',
                ),
                _item(
                  Icons.lightbulb_outline,
                  'Kampung Inovatif',
                  category: 'KAMPUNG INOVATIF',
                ),
                _item(
                  Icons.article_outlined,
                  'Koran Sekolah',
                  category: 'KORAN SEKOLAH',
                ),

                const Divider(height: AppSpacing.xl),
                const _SectionLabel('LOKAL'),

                // ===== LOKAL =====
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(
          text,
          style: AppTypography.label.copyWith(
            color: AppColors.muted,
            letterSpacing: 1.2,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}