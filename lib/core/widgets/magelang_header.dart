import 'package:flutter/material.dart';

import '../design/app_colors.dart';

class MagelangHeader extends StatelessWidget {
  const MagelangHeader({
    super.key,
    required this.onMenu,
    required this.onSearch,
    required this.onLogin,
    this.tagline = 'Akurat, Terpercaya, dan Menginspirasi',
  });

  final VoidCallback onMenu;
  final VoidCallback onSearch;
  final VoidCallback onLogin;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 380;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ===== TOMBOL MENU =====
                IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  color: const Color(0xff272521),
                  tooltip: 'Menu',
                  onPressed: onMenu,
                ),

                // ===== LOGO "ME" (kotak gradient biru) =====
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xff2563eb),
                        Color(0xff7c3aed),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff2563eb).withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'ME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // ===== BRAND NAME + TAGLINE =====
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MAGELANG EKSPRES',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.red,
                          fontSize: narrow ? 12 : 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff77736d),
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // ===== TOMBOL PENCARIAN =====
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.search),
                  color: const Color(0xff272521),
                  tooltip: 'Cari',
                  onPressed: onSearch,
                ),

                // ===== TOMBOL LOGIN =====
                if (narrow)
                  IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.person_outline),
                    color: const Color(0xff272521),
                    tooltip: 'Masuk',
                    onPressed: onLogin,
                  )
                else
                  FilledButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.person_outline, size: 15),
                    label: const Text('Masuk'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}