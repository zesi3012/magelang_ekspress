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
                IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  color: const Color(0xff272521),
                  tooltip: 'Menu',
                  onPressed: onMenu,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'MAGELANG EKSPRES',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.red,
                          fontSize: narrow ? 8 : 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'KORAN DIGITAL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xff202020),
                          fontFamily: 'Georgia',
                          fontSize: narrow ? 17 : 21,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff77736d),
                          fontSize: 8,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
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
