import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_content_settings.dart';

class MagelangLogo extends StatelessWidget {
  const MagelangLogo({
    super.key,
    this.compact = false,
    this.dark = false,
    this.width,
    this.height,
  });

  final bool compact;
  final bool dark;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppContentSettings>(
        valueListenable: appContentSettings,
        builder: (context, settings, _) => _build(context, settings),
      );

  Widget _build(BuildContext context, AppContentSettings settings) {
    final url = settings.logoUrl.trim();
    final imageWidth = width ?? (compact ? 142.0 : 260.0);
    final imageHeight = height ?? (compact ? 48.0 : 112.0);
    Widget fallback() => Image.asset(
      'docx_pdf/logo.jpeg',
      width: imageWidth,
      height: imageHeight,
      fit: BoxFit.contain,
      semanticLabel: settings.brandName,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isEmpty)
          fallback()
        else
          Image.network(
            url,
            width: imageWidth,
            height: imageHeight,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback(),
          ),
        if (settings.tagline.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 1),
            child: Text(
              settings.tagline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white : AppColors.red,
                fontSize: compact ? 8 : 11,
                fontStyle: FontStyle.italic,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}
