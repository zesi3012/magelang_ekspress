import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:magelang_express/core/design/app_colors.dart';
import 'package:magelang_express/main.dart';
import 'package:magelang_express/models/article_model.dart';
import 'package:magelang_express/models/epaper_model.dart' as epaper_model;
import 'package:magelang_express/repositories/mock_article_repository.dart';
import 'package:magelang_express/repositories/mock_epaper_repository.dart';
import 'package:magelang_express/repositories/mock_subscription_repository.dart';
import 'package:magelang_express/services/reader_api_client.dart';
import 'package:magelang_express/screens/epaper/epaper_list_screen.dart';
import 'package:magelang_express/screens/epaper/epaper_viewer_screen.dart';

void setPhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('beranda tampil tanpa menunggu respons artikel', (tester) async {
    setPhoneViewport(tester);
    final pendingArticles = Completer<List<Article>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            repository: MockArticleRepository(),
            articlesFuture: pendingArticles.future,
            category: 'SEMUA',
            onCategory: (_) {},
            onAccount: () {},
            onOpen: (_) {},
            readerClient: null,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('MAGELANG EKSPRES'), findsOneWidget);
    expect(find.text('KILAS'), findsOneWidget);
    expect(
      find.text('Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik'),
      findsWidgets,
    );
  });

  testWidgets('menampilkan identitas dan navigasi Magelang Ekspres', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-site-header')), findsNothing);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('E-Paper'), findsOneWidget);
    expect(find.text('Tersimpan'), findsOneWidget);
    expect(find.text('Akun'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('MAGELANG EKSPRES'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('drawer beranda membuka menu navigasi blueprint', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu').first);
    await tester.pumpAndSettle();

    expect(find.text('NAVIGASI UTAMA'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editorial-drawer-beranda')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editorial-drawer-tersimpan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editorial-drawer-langganan')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editorial-drawer-akun')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editorial-drawer-e-paper')));
    await tester.pumpAndSettle();

    expect(find.byType(EpaperListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu lokal hanya menandai lokasi yang dipilih', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    final temanggung = find.byKey(
      const ValueKey('editorial-drawer-temanggung'),
    );
    final purworejo = find.byKey(const ValueKey('editorial-drawer-purworejo'));
    await tester.ensureVisible(temanggung);
    await tester.tap(temanggung);
    await tester.pumpAndSettle();

    Text locationText(Finder item, String label) => tester.widget<Text>(
      find.descendant(of: item, matching: find.text(label)),
    );
    expect(locationText(temanggung, 'Temanggung').style?.color, AppColors.red);
    expect(
      locationText(purworejo, 'Purworejo').style?.color,
      isNot(AppColors.red),
    );

    await tester.ensureVisible(purworejo);
    await tester.tap(purworejo);
    await tester.pumpAndSettle();

    expect(
      locationText(temanggung, 'Temanggung').style?.color,
      isNot(AppColors.red),
    );
    expect(locationText(purworejo, 'Purworejo').style?.color, AppColors.red);
    expect(tester.takeException(), isNull);
  });

  testWidgets('berita KILAS membuka artikel terkait', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('breaking-news-ticker')));
    await tester.pumpAndSettle();

    expect(find.byType(ArticlePage), findsOneWidget);
    expect(find.text('Laporan Khusus Ini Terkunci'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('akun pembaca tidak menampilkan tombol dashboard redaksi', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Akun'));
    await tester.pumpAndSettle();

    expect(find.text('PROFIL PENGGUNA'), findsOneWidget);
    expect(find.text('DASHBOARD REDAKSI'), findsNothing);
  });

  testWidgets('pilihan ukuran teks menunjukkan skala yang sedang diterapkan', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Akun'));
    await tester.pumpAndSettle();
    var fontSize = tester.widget<DropdownButton<double>>(
      find.byType(DropdownButton<double>),
    );
    expect(fontSize.value, 1);

    await tester.tap(find.text('Sedang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Besar').last);
    await tester.pumpAndSettle();

    fontSize = tester.widget<DropdownButton<double>>(
      find.byType(DropdownButton<double>),
    );
    expect(fontSize.value, 1.15);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registrasi menghentikan loading dan memberi pesan saat gagal', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(
      MaterialApp(home: LoginFlow(api: _FailingRegistrationClient())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Belum punya akun?  Daftar sekarang'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'reader@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password-kuat');
    await tester.enterText(find.byType(TextField).at(2), 'password-kuat');
    await tester.tap(find.byType(Checkbox).last);
    await tester.tap(find.text('DAFTAR'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Tidak dapat terhubung ke layanan akun. Periksa koneksi dan coba lagi.',
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('akun menampilkan identitas dan status pengguna yang login', (
    tester,
  ) async {
    setPhoneViewport(tester);
    final client = _AccountTestReaderApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountPage(
            onDarkMode: (_) {},
            onFontScale: (_) {},
            repository: MockSubscriptionRepository(),
            onLogin: () {},
            signedIn: true,
            readerClient: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zesi'), findsOneWidget);
    expect(find.text('zesi@gmail.com'), findsOneWidget);
    expect(find.text('Pelanggan Premium'), findsOneWidget);
  });

  testWidgets('desktop menampilkan navigasi situs tanpa bottom bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(871, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    final desktopHeader = find.byKey(const ValueKey('desktop-site-header'));
    expect(desktopHeader, findsOneWidget);
    expect(tester.getSize(desktopHeader).width, 871);
    expect(find.text('BERITA DAERAH • E-PAPER DIGITAL'), findsOneWidget);
    expect(find.text('MAGELANG'), findsOneWidget);
    expect(find.text('JAWA TENGAH'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop lebar menampilkan sidebar navigasi permanen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('persistent-editorial-sidebar')),
      findsOneWidget,
    );
    expect(find.text('Tersimpan'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login CMS dapat digulir di viewport pendek', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 323);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AdminPage()));
    await tester.pumpAndSettle();

    expect(find.text('Masuk ke CMS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('membuka artikel premium dan menampilkan paywall', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    final premiumTitle = find.descendant(
      of: find.byType(HeroNewsCard),
      matching: find.text(
        'Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik',
      ),
    );
    await tester.ensureVisible(premiumTitle);
    await tester.tap(premiumTitle);
    await tester.pumpAndSettle();

    expect(find.byType(ArticlePage), findsOneWidget);
    expect(find.text('Laporan Khusus Ini Terkunci'), findsOneWidget);
    expect(find.text('Langganan Sekarang'), findsOneWidget);
  });

  testWidgets('membuka viewer e-paper dan menampilkan indikator halaman', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('E-Paper'));
    await tester.pumpAndSettle();
    expect(find.byType(EpaperListScreen), findsOneWidget);
    expect(find.text('Buka Koran'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('epaper-issue-epaper-2026-08-13')),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETAIL E-PAPER'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('latest-published-issue')));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL E-PAPER'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buka Koran').first);
    await tester.pumpAndSettle();
    expect(find.text('DETAIL E-PAPER'), findsOneWidget);
    await tester.tap(find.text('BUKA E-PAPER'));
    await tester.pumpAndSettle();

    expect(find.text('HALAMAN 1 / 8'), findsOneWidget);
    expect(find.byTooltip('PDF belum tersedia'), findsOneWidget);
    expect(find.text('DAFTAR ARTIKEL'), findsOneWidget);
  });

  testWidgets('preview e-paper menjelaskan PDF belum tersedia', (tester) async {
    setPhoneViewport(tester);
    final issue = epaper_model.EpaperIssue(
      id: 'preview',
      title: 'MAGELANG EKSPRES',
      edition: 'Pratinjau Blueprint',
      date: '29 Juni 2026',
      totalPages: 1,
      downloadAvailable: false,
      isSamplePreview: true,
      pages: const [
        epaper_model.EpaperPage(
          pageNumber: 1,
          label: 'BERITA UTAMA',
          accentColor: 0xffc8242f,
          articleIds: [],
        ),
      ],
      articles: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EpaperViewerScreen(
          repository: MockEpaperRepository(),
          issue: issue,
        ),
      ),
    );

    await tester.tap(find.byTooltip('PDF belum tersedia'));
    await tester.pump();

    expect(find.text('PDF edisi belum diunggah oleh redaksi.'), findsOneWidget);
  });

  testWidgets('menyimpan artikel dan menampilkannya di halaman tersimpan', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setPhoneViewport(tester);
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();

    final articleTitle = find.descendant(
      of: find.byType(HeroNewsCard),
      matching: find.text(
        'Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik',
      ),
    );
    await tester.ensureVisible(articleTitle);
    await tester.tap(articleTitle);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pump();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MagelangExpressApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Akun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artikel Tersimpan'));
    await tester.pumpAndSettle();

    expect(find.text('Bacaan pilihan Anda'), findsOneWidget);
    expect(
      find.text('1 artikel tersimpan untuk dibaca kembali'),
      findsOneWidget,
    );
    final savedTitle = tester.widget<Text>(find.text('Tersimpan').first);
    expect(savedTitle.style?.color, AppColors.ink);
    expect(
      find.text('Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik'),
      findsOneWidget,
    );
    await tester.tap(
      find.text('Budidaya Maggot di Jambon, Cara Kurangi Sampah Organik'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ArticlePage), findsOneWidget);
  });
}

class _AccountTestReaderApiClient extends ReaderApiClient {
  _AccountTestReaderApiClient() : super(baseUrl: 'https://example.test') {
    accessToken = 'test-reader-token';
    currentUserEmail = 'zesi@gmail.com';
    currentUserRole = 'Reader';
  }

  @override
  Future<Map<String, dynamic>> subscriptionStatus() async => {
    'active': true,
    'subscription': {'endDate': '2026-12-31T00:00:00Z'},
  };
}

class _FailingRegistrationClient extends ReaderApiClient {
  _FailingRegistrationClient() : super(baseUrl: 'https://example.test');

  @override
  Future<void> register(String email, String password) async {
    throw StateError('Network unavailable');
  }
}
