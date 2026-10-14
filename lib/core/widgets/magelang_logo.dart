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
  Widget build(BuildContext context) => ValueListenableBuilder<AppContentSettings>(
        valueListenable: appContentSettings,
        builder: (context, settings, _) => _buildLogo(context, settings),
      );

  Widget _buildLogo(BuildContext context, AppContentSettings settings) {
    final url = settings.logoUrl.trim();
    final boxSize = width ?? (compact ? 36.0 : 64.0);
    final imageWidth = width ?? (compact ? 142.0 : 260.0);
    final imageHeight = height ?? (compact ? 48.0 : 112.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isEmpty) _buildMEBox(boxSize) else _buildImageLogo(url, imageWidth, imageHeight, settings),
        if (settings.tagline.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 4, top: compact ? 1 : 4),
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

  Widget _buildMEBox(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff2563eb), Color(0xff7c3aed)],
          ),
          borderRadius: BorderRadius.circular(compact ? 8.0 : 16.0),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff2563eb).withOpacity(0.3),
              blurRadius: compact ? 6 : 12,
              offset: Offset(0, compact ? 2 : 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          'ME',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 14 : 28,
            fontWeight: FontWeight.w900,
            letterSpacing: compact ? -0.5 : -1,
          ),
        ),
      );

  Widget _buildImageLogo(String url, double w, double h, AppContentSettings settings) =>
      Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.contain,
        semanticLabel: settings.brandName,
        errorBuilder: (_, _, _) => Image.asset(
          'docx_pdf/logo.jpeg',
          width: w,
          height: h,
          fit: BoxFit.contain,
          semanticLabel: settings.brandName,
        ),
      );
}