import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

class ArticleShareSheet extends StatelessWidget {
  const ArticleShareSheet({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Wrap(
        runSpacing: AppSpacing.sm,
        children: [
          const Text(
            'Bagikan artikel',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _option(context, Icons.chat, 'WhatsApp'),
              _option(context, Icons.alternate_email, 'X / Twitter'),
              _option(context, Icons.facebook, 'Facebook'),
              _option(context, Icons.ios_share, 'Lainnya'),
              _option(context, Icons.link, 'Salin tautan'),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _option(BuildContext context, IconData icon, String label) => InkWell(
    onTap: () {
      Navigator.pop(context);
      onSelected(label);
    },
    child: SizedBox(
      width: 56,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.white,
            child: Icon(icon, size: 19),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
  );
}
