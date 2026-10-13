import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const display = TextStyle(
    fontSize: 30,
    height: 1.08,
    fontWeight: FontWeight.w900,
    color: Color(0xff182332),
  );
  static const headline = TextStyle(
    fontSize: 22,
    height: 1.12,
    fontWeight: FontWeight.w900,
    color: Color(0xff182332),
  );
  static const section = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.1,
    color: Color(0xff102c52),
  );
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: .5,
  );
}
