import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/web_seo_stub.dart'
    if (dart.library.html) 'core/web_seo_html.dart'
    as web_seo;
import 'core/design/app_breakpoints.dart';
import 'core/design/app_colors.dart';
import 'core/design/app_content_settings.dart';
import 'core/design/app_radius.dart';
import 'core/design/app_spacing.dart';
import 'core/design/app_typography.dart';
import 'core/widgets/article_share_sheet.dart';
import 'core/widgets/editorial_drawer.dart';
import 'core/widgets/magelang_logo.dart';
import 'data/mock_article_data.dart';
import 'models/article_model.dart';
import 'models/subscription_plan_model.dart';
import 'repositories/article_repository.dart';
import 'repositories/api_article_repository.dart';
import 'repositories/api_epaper_repository.dart';
import 'repositories/api_subscription_repository.dart';
import 'repositories/mock_article_repository.dart';
import 'repositories/epaper_repository.dart';
import 'repositories/mock_epaper_repository.dart';
import 'repositories/mock_subscription_repository.dart';
import 'repositories/subscription_repository.dart';
import 'screens/epaper/epaper_list_screen.dart';
import 'screens/epaper/epaper_article_screen.dart';
import 'services/admin_api_client.dart';
import 'services/reader_api_client.dart';
import 'services/share_service.dart';

void main() => runApp(const MagelangExpressApp());

String _formatArticleDate(String? value, {bool includeTime = false}) {
  final parsed = DateTime.tryParse(value?.trim() ?? '');
  if (parsed == null) return '';
  final date = parsed.toLocal();
  const months = [
    'JANUARI',
    'FEBRUARI',
    'MARET',
    'APRIL',
    'MEI',
    'JUNI',
    'JULI',
    'AGUSTUS',
    'SEPTEMBER',
    'OKTOBER',
    'NOVEMBER',
    'DESEMBER',
  ];
  final day = '${date.day} ${months[date.month - 1]} ${date.year}';
  if (!includeTime) return day;
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day • $hour:$minute';
}

DateTime? _articleTimestamp(Article article) => DateTime.tryParse(
  article.publishedAt ?? article.updatedAt ?? '',
)?.toLocal();

String _suggestedArticleSlug(String title) => title
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

Widget _articleSocialLinks(Map<String, String> links) {
  final chips = <Widget>[];
  for (final entry in links.entries) {
    final uri = Uri.tryParse(entry.value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      continue;
    }
    chips.add(
      ActionChip(
        avatar: const Icon(Icons.open_in_new, size: 16),
        label: Text(entry.key),
        onPressed: () async {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    );
  }
  if (chips.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Wrap(spacing: 8, runSpacing: 8, children: chips),
  );
}

class MagelangExpressApp extends StatefulWidget {
  const MagelangExpressApp({super.key});
  @override
  State<MagelangExpressApp> createState() => _AppState();
}

class _AppState extends State<MagelangExpressApp> {
  ThemeMode mode = ThemeMode.light;
  double fontScale = 1;
  @override
  Widget build(BuildContext context) {
    const launchAdmin = bool.fromEnvironment('ADMIN_START');
    final adminEntry = kIsWeb && web_seo.isAdminEntry();
    final homePage = HomeShell(
      onDarkMode: (value) =>
          setState(() => mode = value ? ThemeMode.dark : ThemeMode.light),
      onFontScale: (value) => setState(() => fontScale = value),
      fontScale: fontScale,
    );
    return MaterialApp(
      title: 'Magelang Ekspres',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(fontScale)),
        child: child!,
      ),
      routes: {
        '/admin': (_) => const AdminPage(),
        '/admin/login': (_) => const AdminPage(),
      },
      home: launchAdmin || adminEntry ? const AdminPage() : homePage,
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      secondary: AppColors.red,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? AppColors.paper
        : const Color(0xff10141c),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.navy,
      foregroundColor: AppColors.white,
      elevation: 0,
      titleTextStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: brightness == Brightness.light ? AppColors.ink : Colors.white,
      displayColor: brightness == Brightness.light
          ? AppColors.ink
          : Colors.white,
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.onDarkMode,
    required this.onFontScale,
    required this.fontScale,
  });

  final ValueChanged<bool> onDarkMode;
  final ValueChanged<double> onFontScale;
  final double fontScale;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int index = 0;
  String category = 'SEMUA';
  String? selectedLocation;
  final saved = <String>{};
  final useApi =
      const bool.fromEnvironment('USE_API') ||
      kIsWeb && const String.fromEnvironment('API_BASE_URL').isNotEmpty;
  late final ReaderApiClient readerClient = ReaderApiClient();
  late final EpaperRepository epaperRepository = useApi
      ? ApiEpaperRepository(client: readerClient)
      : MockEpaperRepository();
  late final ArticleRepository articleRepository = useApi
      ? ApiArticleRepository(client: readerClient)
      : MockArticleRepository();
  late final SubscriptionRepository subscriptionRepository = useApi
      ? ApiSubscriptionRepository(client: readerClient)
      : MockSubscriptionRepository();
  late final Future<List<Article>> articlesFuture = articleRepository
      .getArticles();

  Future<void> _restoreLocalSavedItems() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      saved.addAll(preferences.getStringList('savedArticleIds') ?? const []);
    });
  }

  Future<void> _persistSavedItems() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('savedArticleIds', saved.toList());
  }

  Future<void> _restoreSavedItems() async {
    try {
      final items = await readerClient.getSavedItems();
      if (!mounted) return;
      setState(() {
        saved.addAll(
          items
              .where((item) => item['itemType'] == 'article')
              .map((item) => item['itemId'].toString()),
        );
      });
    } catch (_) {
      // Local saved items remain available if the API is offline.
    }
  }

  Future<void> _loadPublicSiteSettings() async {
    try {
      final values = await readerClient.getSiteSettings();
      if (!mounted) return;
      setState(() {
        appContentSettings.value = AppContentSettings.fromJson(values);
      });
    } catch (_) {
      // Keep default content when the API is unavailable.
    }
  }

  Future<void> _restoreReaderSession() async {
    await readerClient.restoreSavedSession();
    if (!mounted || readerClient.accessToken == null) return;
    await _restoreSavedItems();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _restoreLocalSavedItems();
    if (useApi) _loadPublicSiteSettings();
    if (useApi) _restoreReaderSession();
    if (kIsWeb) {
      final query = Uri.base.queryParameters;
      final articleId = query['article'];
      final epaperArticleId = query['epaperArticle'];
      if (articleId != null) _openSharedArticle(articleId);
      if (epaperArticleId != null) {
        _openSharedEpaperArticle(epaperArticleId);
      }
    }
  }

  Future<void> _openSharedArticle(String articleId) async {
    try {
      final articles = await articlesFuture;
      final article = articles
          .where((item) => item.id == articleId || item.slug == articleId)
          .firstOrNull;
      if (article == null || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openArticle(article);
      });
    } catch (_) {
      // Keep the homepage available if a shared article is unavailable.
    }
  }

  Future<void> _openSharedEpaperArticle(String articleId) async {
    try {
      final issues = await epaperRepository.getEpaperIssues();
      final article = issues
          .expand((issue) => issue.articles)
          .where((item) => item.id == articleId)
          .firstOrNull;
      if (article == null || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EpaperArticleScreen(
              repository: epaperRepository,
              article: article,
            ),
          ),
        );
      });
    } catch (_) {
      // Keep the homepage available if a shared e-paper article is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 768;
    final persistentSidebar = width >= AppBreakpoints.desktop;
    void openDrawer() {
      scaffoldKey.currentState?.openDrawer();
    }

    final pages = [
      HomePage(
        repository: articleRepository,
        articlesFuture: articlesFuture,
        desktop: desktop,
        onMenu: openDrawer,
        category: category,
        onCategory: (value) => setState(() {
          selectedLocation = null;
          if (value == 'E-PAPER') {
            index = 1;
          } else {
            category = value;
            index = 0;
          }
        }),
        onAccount: () => setState(() => index = 2),
        onOpen: openArticle,
        onLogin: _showReaderLogin,
        saved: saved,
        onToggleSaved: (article) {
          setState(() {
            if (!saved.add(article.id)) saved.remove(article.id);
          });
          _persistSavedItems();
        },
        readerClient: useApi ? readerClient : null,
      ),
      EpaperPage(
        repository: epaperRepository,
        readerClient: useApi ? readerClient : null,
        onSubscribe: () => setState(() => index = 2),
      ),
      PlansPage(
        repository: subscriptionRepository,
        readerClient: useApi ? readerClient : null,
        embedded: true,
        onLogin: _showReaderLogin,
      ),
      AccountPage(
        onDarkMode: widget.onDarkMode,
        onFontScale: widget.onFontScale,
        fontScale: widget.fontScale,
        repository: subscriptionRepository,
        readerClient: useApi ? readerClient : null,
        signedIn: useApi && readerClient.accessToken != null,
        onLogin: _showReaderLogin,
        onSubscribe: () => setState(() => index = 2),
        onOpenSaved: _openSavedPage,
      ),
    ];
    return Scaffold(
      key: scaffoldKey,
      drawer: persistentSidebar
          ? null
          : Drawer(
              width: width < 380 ? width * 0.88 : 320,
              child: _editorialDrawer(),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (desktop)
              _desktopNavigation(onMenu: persistentSidebar ? null : openDrawer),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: persistentSidebar
                      ? Row(
                          children: [
                            SizedBox(
                              key: const ValueKey(
                                'persistent-editorial-sidebar',
                              ),
                              width: 250,
                              child: _editorialDrawer(persistent: true),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: pages[index]),
                          ],
                        )
                      : pages[index],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: index == 1
                  ? 1
                  : index == 3
                  ? 3
                  : 0,
              onDestinationSelected: (value) {
                if (value == 2) {
                  _openSavedPage();
                } else {
                  setState(() => index = value);
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.article_outlined),
                  selectedIcon: Icon(Icons.article),
                  label: 'Beranda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'E-Paper',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark_border),
                  selectedIcon: Icon(Icons.bookmark),
                  label: 'Tersimpan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Akun',
                ),
              ],
            ),
    );
  }

  EditorialDrawer _editorialDrawer({bool persistent = false}) =>
      EditorialDrawer(
        selectedIndex: index,
        selectedCategory: category,
        selectedLocation: selectedLocation,
        persistent: persistent,
        onNavigate: (value) => setState(() {
          index = value;
          if (value == 0) category = 'SEMUA';
        }),
        onSaved: _openSavedPage,
        onCategory: (value) => setState(() {
          category = value;
          selectedLocation = null;
          index = 0;
        }),
        onLocationSelected: (value) => setState(() {
          selectedLocation = value;
        }),
        onClose: persistent
            ? () {}
            : () => scaffoldKey.currentState?.closeDrawer(),
      );

  void _openSavedPage() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SavedPage(
          repository: articleRepository,
          articlesFuture: articlesFuture,
          saved: saved,
          onOpen: openArticle,
        ),
      ),
    );
  }

  Widget _desktopNavigation({VoidCallback? onMenu}) => SizedBox(
    key: const ValueKey('desktop-site-header'),
    width: double.infinity,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 5, child: ColoredBox(color: AppColors.red)),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 92),
          decoration: const BoxDecoration(
            color: AppColors.paper,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    if (onMenu != null)
                      IconButton(
                        tooltip: 'Menu',
                        onPressed: onMenu,
                        icon: const Icon(Icons.menu_rounded),
                        color: AppColors.navy,
                      ),
                    const Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'MAGELANG '),
                            TextSpan(
                              text: 'EKSPRES',
                              style: TextStyle(
                                color: AppColors.red,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          style: TextStyle(
                            color: AppColors.navy,
                            fontFamily: 'Georgia',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'BERITA DAERAH • E-PAPER DIGITAL',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontFamily: 'Arial',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.paper,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  children: [
                    for (final destination in const [
                      (label: 'BERANDA', category: 'SEMUA', page: 0),
                      (label: 'MAGELANG', category: 'MAGELANG', page: 0),
                      (label: 'JAWA TENGAH', category: 'JAWA TENGAH', page: 0),
                      (label: 'E-PAPER', category: '', page: 1),
                    ])
                      TextButton(
                        onPressed: () => setState(() {
                          index = destination.page;
                          if (destination.category.isNotEmpty) {
                            category = destination.category;
                          }
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          textStyle: const TextStyle(
                            fontFamily: 'Arial',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          padding: const EdgeInsets.only(right: 28),
                        ),
                        child: Text(destination.label),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void openArticle(Article article) {
    web_seo.showArticleMetadata(
      title: article.seoTitle?.isNotEmpty == true
          ? article.seoTitle!
          : '${article.title} | Magelang Ekspres',
      description: article.seoDescription?.isNotEmpty == true
          ? article.seoDescription!
          : article.excerpt,
      articleId: article.slug?.isNotEmpty == true ? article.slug! : article.id,
      imageUrl: article.imageUrl,
    );
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ArticlePage(
          article: article,
          subscriptionRepository: subscriptionRepository,
          readerClient: useApi ? readerClient : null,
          saved: saved.contains(article.id),
          onSaved: (value) {
            setState(() {
              if (value) {
                saved.add(article.id);
              } else {
                saved.remove(article.id);
              }
            });
            _persistSavedItems();
            if (useApi && readerClient.accessToken != null) {
              final operation = value
                  ? readerClient.saveItem(
                      itemType: 'article',
                      itemId: article.id,
                    )
                  : readerClient.removeSavedItem(
                      itemType: 'article',
                      itemId: article.id,
                    );
              operation.catchError((_) {});
            }
          },
        ),
      ),
    ).then((_) => web_seo.restoreSiteMetadata());
  }

  Future<void> _showReaderLogin() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => LoginFlow(api: readerClient)),
    );
    if (!mounted) return;
    setState(() {});
    if (readerClient.accessToken != null) await _restoreSavedItems();
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.articlesFuture,
    this.desktop = false,
    required this.category,
    required this.onCategory,
    required this.onAccount,
    this.onMenu,
    required this.onOpen,
    this.onLogin,
    this.saved = const {},
    this.onToggleSaved,
    required this.readerClient,
  });
  final Set<String> saved;
  final ValueChanged<Article>? onToggleSaved;
  final ArticleRepository repository;
  final Future<List<Article>> articlesFuture;
  final bool desktop;
  final String category;
  final ValueChanged<String> onCategory;
  final VoidCallback onAccount;
  final VoidCallback? onMenu;
  final ValueChanged<Article> onOpen;
  final VoidCallback? onLogin;
  final ReaderApiClient? readerClient;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppContentSettings>(
  valueListenable: appContentSettings,
  builder: (context, settings, _) => FutureBuilder<List<Article>>(
    future: articlesFuture,
    builder: (context, snapshot) {
      // ===== DEBUG LOG =====
      debugPrint('[HomePage] connectionState: ${snapshot.connectionState}');
      debugPrint('[HomePage] hasData: ${snapshot.hasData}');
      debugPrint('[HomePage] hasError: ${snapshot.hasError}');
      debugPrint('[HomePage] data length: ${snapshot.data?.length}');
      debugPrint('[HomePage] error: ${snapshot.error}');
      // ===== END DEBUG =====

      final allItems = List<Article>.from(snapshot.data ?? mockArticles)
            ..sort((first, second) {
              final firstDate = _articleTimestamp(first) ?? DateTime(0);
              final secondDate = _articleTimestamp(second) ?? DateTime(0);
              return secondDate.compareTo(firstDate);
            });
          final categories = <String>[
            'SEMUA',
            ...allItems
                .map((item) => item.category.trim().toUpperCase())
                .where(
                  (value) =>
                      value.isNotEmpty &&
                      value != 'OLAHRAGA' &&
                      value != 'PENDIDIKAN',
                )
                .toSet(),
          ];
          final items = category == 'SEMUA'
              ? allItems
              : allItems
                    .where((item) => item.category.toUpperCase() == category)
                    .toList();
          final feedItems = items.length > 1
              ? items.skip(1).toList()
              : const <Article>[];
          return CustomScrollView(
            slivers: [
              if (!desktop)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Menu',
                          icon: const Icon(Icons.menu_rounded),
                          onPressed: onMenu,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'MAGELANG EKSPRES',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 23,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                settings.tagline,
                                style: const TextStyle(
                                  color: Color(0xff77736d),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cari',
                          icon: const Icon(Icons.search),
                          onPressed: () => showSearch(
                            context: context,
                            delegate: ArticleSearch(repository, onOpen),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: InkWell(
                    onTap: onAccount,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfffff3b0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 14,
                            color: Color(0xffb8860b),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              settings.subscriptionTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff7a4b00),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Text(
                            'Langganan\nQRIS →',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Color(0xff7a4b00),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (allItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: _BreakingNewsTicker(
                    article: allItems.first,
                    onTap: () => onOpen(allItems.first),
                  ),
                ),

              SliverToBoxAdapter(
                child: SizedBox(
                  height: 54,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final selected = category == categories[index];
                      final label = categories[index] == 'SEMUA'
                          ? 'Semua'
                          : categories[index][0] +
                                categories[index].substring(1).toLowerCase();
                      return GestureDetector(
                        onTap: () => onCategory(categories[index]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xff111111)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xff111111)
                                  : AppColors.line,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : const Color(0xff222222),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (items.isNotEmpty)
                SliverToBoxAdapter(
                  child: HeroNewsCard(
                    article: items.first,
                    settings: settings,
                    onOpen: onOpen,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: SizedBox(
                      height: 120,
                      child: Center(
                        child: snapshot.connectionState != ConnectionState.done
                            ? const CircularProgressIndicator()
                            : Text(
                                snapshot.hasError
                                    ? 'Berita belum dapat dimuat.'
                                    : 'Berita utama akan segera tampil.',
                                style: AppTypography.headline,
                                textAlign: TextAlign.center,
                              ),
                      ),
                    ),
                  ),
                ),
              SliverList.builder(
                itemCount: feedItems.length,
                itemBuilder: (_, index) {
                  final article = feedItems[index];
                  final date = _formatArticleDate(
                    article.publishedAt ?? article.updatedAt,
                  );
                  return InkWell(
                    onTap: () => onOpen(article),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xffe8e4dd)),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 94,
                            height: 72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (article.imageUrl?.isNotEmpty == true)
                                    Image.network(
                                      article.imageUrl!,
                                      fit: BoxFit.cover,
                                      semanticLabel: article.imageAltText,
                                      errorBuilder: (_, _, _) => CustomPaint(
                                        painter: _MagelangLandscapePainter(),
                                      ),
                                    )
                                  else
                                    CustomPaint(
                                      painter: _MagelangLandscapePainter(),
                                    ),
                                  if (article.isPremium)
                                    const Positioned(
                                      top: 5,
                                      right: 5,
                                      child: Icon(
                                        Icons.lock,
                                        size: 15,
                                        color: Color(0xffffc84a),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        article.category,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (article.isPremium) const _PremiumPill(),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  article.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xff202020),
                                    fontFamily: 'Georgia',
                                    fontSize: 14,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (date.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    date,
                                    style: const TextStyle(
                                      color: Color(0xff77736d),
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Simpan',
                              icon: Icon(
                                saved.contains(article.id)
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                size: 18,
                              ),
                              onPressed: () => onToggleSaved?.call(article),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BreakingNewsTicker extends StatelessWidget {
  const _BreakingNewsTicker({required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('breaking-news-ticker'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  'KILAS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                article.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff37332d),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 17, color: AppColors.red),
          ],
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .6),
    ),
  );
}

class ArticleCard extends StatelessWidget {
  const ArticleCard({super.key, required this.article, required this.onOpen});
  final Article article;
  final ValueChanged<Article> onOpen;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: InkWell(
      onTap: () => onOpen(article),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 190,
              color: const Color(0xffd9e0e8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: 52,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .45),
                    ),
                  ),
                  if (article.isPremium)
                    const Positioned(
                      top: 14,
                      left: 14,
                      child: _Ribbon(label: 'PREMIUM'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.category.toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class HeroNewsCard extends StatelessWidget {
  const HeroNewsCard({
    super.key,
    required this.article,
    required this.settings,
    required this.onOpen,
  });
  final Article article;
  final AppContentSettings settings;
  final ValueChanged<Article> onOpen;

  @override
  Widget build(BuildContext context) {
    final compactViewport = MediaQuery.sizeOf(context).width < 600;
    final date = _formatArticleDate(article.publishedAt ?? article.updatedAt);
    final imageUrl = article.imageUrl?.isNotEmpty == true
        ? article.imageUrl!
        : settings.heroImageUrl;
    final title = settings.heroTitle.trim().isEmpty
        ? article.title
        : settings.heroTitle;
    final excerpt = settings.heroExcerpt.trim().isEmpty
        ? article.excerpt
        : settings.heroExcerpt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () => onOpen(article),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: compactViewport ? 205 : 300,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff718fa8), Color(0xff112b55)],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: imageUrl.isEmpty
                      ? CustomPaint(painter: _MagelangLandscapePainter())
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          semanticLabel: article.imageAltText,
                          errorBuilder: (_, _, _) =>
                              CustomPaint(painter: _MagelangLandscapePainter()),
                        ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xff071a38).withValues(alpha: .95),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xffc8242f),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        article.category.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                if (article.isPremium)
                  Positioned(
                    top: 18,
                    right: 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xffffc84a),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: Color(0xff302719),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date.isEmpty
                            ? article.category.toUpperCase()
                            : '${article.category.toUpperCase()}  •  $date',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compactViewport ? 20 : 27,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Georgia',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LockedHeadlineCard extends StatelessWidget {
  const LockedHeadlineCard({
    super.key,
    required this.article,
    required this.onOpen,
  });
  final Article article;
  final ValueChanged<Article> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      0,
    ),
    child: InkWell(
      onTap: () => onOpen(article),
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: AppColors.navyDeep,
          border: Border.all(color: AppColors.red, width: 2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: .3,
              child: CustomPaint(painter: _MagelangLandscapePainter()),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.navyDeep.withValues(alpha: .58),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: AppColors.white,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'HEADLINE PREMIUM',
                        style: TextStyle(
                          color: AppColors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Buka untuk melihat pilihan paket langganan.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MagelangLandscapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()..color = const Color(0xffd9b277).withValues(alpha: .72);
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .23),
      size.width * .13,
      sky,
    );
    final mountainPath = Path()
      ..moveTo(0, size.height * .48)
      ..lineTo(size.width * .62, size.height * .31)
      ..lineTo(size.width * .88, size.height * .63)
      ..lineTo(size.width, size.height * .48)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final mountain = Paint()
      ..color = const Color(0xff526e72).withValues(alpha: .88);
    canvas.drawPath(mountainPath, mountain);
    final hill = Paint()
      ..color = const Color(0xff223d46).withValues(alpha: .95);
    canvas.drawOval(
      Rect.fromLTWH(
        -size.width * .18,
        size.height * .58,
        size.width * 1.35,
        size.height * .52,
      ),
      hill,
    );
    final temple = Paint()
      ..color = const Color(0xffd7bd8c).withValues(alpha: .9);
    for (var index = 0; index < 4; index++) {
      final x = size.width * (.28 + index * .14);
      final y = size.height * (.62 - index * .025);
      canvas.drawRect(
        Rect.fromLTWH(x, y, size.width * .08, size.height * .08),
        temple,
      );
      canvas.drawCircle(
        Offset(x + size.width * .04, y),
        size.width * .04,
        temple,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondary),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _PremiumPill extends StatelessWidget {
  const _PremiumPill({this.label = 'PREMIUM'});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xfffff0c4),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock, size: 8, color: Color(0xffb86e00)),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xffb86e00),
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, required this.premium});
  final bool premium;
  @override
  Widget build(BuildContext context) => Text(
    premium ? 'PREMIUM' : 'GRATIS',
    style: TextStyle(
      color: premium ? const Color(0xff8a5a00) : Colors.green,
      fontSize: 10,
      fontWeight: FontWeight.w900,
    ),
  );
}

class ArticlePage extends StatelessWidget {
  const ArticlePage({
    super.key,
    required this.article,
    required this.subscriptionRepository,
    this.readerClient,
    required this.saved,
    required this.onSaved,
  });
  final Article article;
  final SubscriptionRepository subscriptionRepository;
  final ReaderApiClient? readerClient;
  final bool saved;
  final ValueChanged<bool> onSaved;
  @override
  Widget build(BuildContext context) {
    var isSaved = saved;
    final author = article.author?.trim() ?? '';
    final publishedDate = _formatArticleDate(
      article.publishedAt ?? article.updatedAt,
      includeTime: true,
    );
    final byline = [
      author.isEmpty ? 'Redaksi Magelang Ekspres' : author,
      if (publishedDate.isNotEmpty) publishedDate,
    ].join(' • ');
    final hasSubscription = readerClient?.accessToken == null
        ? Future.value(false)
        : readerClient!.subscriptionStatus().then(
            (status) => status['active'] == true,
          );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareArticle(context),
          ),
          StatefulBuilder(
            builder: (context, setSavedState) => IconButton(
              tooltip: isSaved
                  ? 'Hapus dari baca nanti'
                  : 'Simpan untuk baca nanti',
              icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () {
                setSavedState(() => isSaved = !isSaved);
                onSaved(isSaved);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isSaved
                          ? 'Artikel disimpan untuk dibaca nanti.'
                          : 'Artikel dihapus dari tersimpan.',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  article.category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (article.isPremium) ...[
                const SizedBox(width: 8),
                const _PremiumPill(label: 'KONTEN PREMIUM'),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            article.title,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 28,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            byline,
            style: const TextStyle(color: Color(0xff77736d), fontSize: 11),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 230,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (article.imageUrl?.isNotEmpty == true)
                  Image.network(
                    article.imageUrl!,
                    fit: BoxFit.cover,
                    semanticLabel: article.imageAltText,
                    errorBuilder: (_, _, _) =>
                        CustomPaint(painter: _MagelangLandscapePainter()),
                  )
                else
                  CustomPaint(painter: _MagelangLandscapePainter()),
                if (article.isPremium)
                  FutureBuilder<bool>(
                    future: hasSubscription,
                    builder: (context, snapshot) {
                      if (snapshot.data == true) return const SizedBox.shrink();
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.black.withValues(alpha: .38),
                            child: const Center(
                              child: Icon(
                                Icons.lock,
                                size: 52,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Positioned(
                            bottom: 16,
                            left: 16,
                            child: _Ribbon(label: 'KONTEN PREMIUM'),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!article.isPremium)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.body,
                  style: const TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 17,
                    height: 1.7,
                  ),
                ),
                _articleSocialLinks(article.socialLinks),
              ],
            )
          else
            FutureBuilder<bool>(
              future: hasSubscription,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return snapshot.data == true
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.body,
                            style: const TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 17,
                              height: 1.7,
                            ),
                          ),
                          _articleSocialLinks(article.socialLinks),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (article.excerpt.trim().isNotEmpty)
                            Text(
                              article.excerpt,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.65,
                              ),
                            ),
                          const SizedBox(height: 20),
                          Paywall(
                            repository: subscriptionRepository,
                            readerClient: readerClient,
                          ),
                        ],
                      );
              },
            ),
        ],
      ),
    );
  }

  void _shareArticle(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ArticleShareSheet(
      onSelected: (label) async {
        try {
          await ShareService.shareArticle(
            title: article.title,
            id: article.id,
            destination: label,
          );
          if (context.mounted && label == 'Salin tautan') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tautan artikel disalin.')),
            );
          }
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal membagikan artikel: $error')),
            );
          }
        }
      },
    ),
  );
}

class Paywall extends StatelessWidget {
  const Paywall({super.key, required this.repository, this.readerClient});
  final SubscriptionRepository repository;
  final ReaderApiClient? readerClient;
  @override
  Widget build(BuildContext context) {
    final settings = appContentSettings.value;
    return Card(
      color: const Color(0xfffffcf6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xfffff0c4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: Color(0xffa36f13),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 9),
            const Center(
              child: Text(
                'Laporan Khusus Ini Terkunci',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff27231d),
                  fontFamily: 'Georgia',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              settings.subscriptionDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff69645c), fontSize: 12),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<SubscriptionPlan>>(
              future: repository.getActivePlans(),
              builder: (context, snapshot) {
                final plans = snapshot.data ?? const <SubscriptionPlan>[];
                final cheapest = plans.isEmpty
                    ? null
                    : plans.reduce(
                        (first, second) =>
                            first.price <= second.price ? first : second,
                      );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator(minHeight: 2),
                    if (snapshot.hasError)
                      const Text('Paket langganan belum dapat dimuat.'),
                    if (cheapest != null) ...[
                      Text(
                        'Mulai ${formatRupiah(cheapest.price)} • ${cheapest.durationDays} hari',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 9),
                      ...cheapest.benefits.map(
                        (benefit) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xff21856a),
                                size: 14,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  benefit,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (cheapest == null && !snapshot.hasError)
                      const Text('Paket langganan belum tersedia.'),
                    if (cheapest != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PlansPage(
                                repository: repository,
                                readerClient: readerClient,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.lock_open, size: 16),
                          label: const Text('Langganan Sekarang'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff181818),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class EpaperPage extends StatelessWidget {
  const EpaperPage({
    super.key,
    required this.repository,
    this.readerClient,
    this.onSubscribe,
  });
  final EpaperRepository repository;
  final ReaderApiClient? readerClient;
  final VoidCallback? onSubscribe;
  @override
  Widget build(BuildContext context) => EpaperListScreen(
    repository: repository,
    readerClient: readerClient,
    onSubscribe: onSubscribe,
  );
}

class SavedPage extends StatelessWidget {
  const SavedPage({
    super.key,
    required this.repository,
    required this.articlesFuture,
    required this.saved,
    required this.onOpen,
  });
  final ArticleRepository repository;
  final Future<List<Article>> articlesFuture;
  final Set<String> saved;
  final ValueChanged<Article> onOpen;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Article>>(
    future: articlesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          backgroundColor: AppColors.paper,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      final items = (snapshot.data ?? const <Article>[])
          .where((item) => saved.contains(item.id))
          .toList();
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          foregroundColor: AppColors.ink,
          title: const Text(
            'Tersimpan',
            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
          ),
        ),
        body: snapshot.hasError
            ? const Center(child: Text('Artikel tersimpan belum dapat dimuat.'))
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bacaan pilihan Anda',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${items.length} artikel tersimpan untuk dibaca kembali',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptySavedArticles(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SavedArticleCard(
                              article: items[index],
                              onTap: () => onOpen(items[index]),
                            ),
                          ),
                          childCount: items.length,
                        ),
                      ),
                    ),
                ],
              ),
      );
    },
  );
}

class _EmptySavedArticles extends StatelessWidget {
  const _EmptySavedArticles();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bookmark_outline,
              color: AppColors.navy,
              size: 36,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Belum ada artikel tersimpan',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ketuk ikon bookmark pada berita untuk menyimpannya di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _SavedArticleCard extends StatelessWidget {
  const _SavedArticleCard({required this.article, required this.onTap});

  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 104,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _savedArticleImage(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          article.category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (article.isPremium)
                        const Icon(
                          Icons.workspace_premium_outlined,
                          color: AppColors.gold,
                          size: 17,
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _formatArticleDate(
                      article.publishedAt ?? article.updatedAt,
                    ),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );

  Widget _savedArticleImage() {
    final source = article.imageUrl?.trim();
    if (source == null || source.isEmpty) {
      return const ColoredBox(
        color: AppColors.navy,
        child: Center(
          child: Icon(Icons.newspaper_outlined, color: Colors.white, size: 36),
        ),
      );
    }
    const fallback = ColoredBox(
      color: AppColors.navy,
      child: Center(
        child: Icon(Icons.newspaper_outlined, color: Colors.white, size: 36),
      ),
    );
    return source.startsWith('assets/')
        ? Image.asset(
            source,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.network(
            source,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.onDarkMode,
    required this.onFontScale,
    this.fontScale = 1,
    required this.repository,
    required this.onLogin,
    this.onSubscribe,
    this.onOpenSaved,
    this.signedIn = false,
    this.readerClient,
  });
  final ValueChanged<bool> onDarkMode;
  final ValueChanged<double> onFontScale;
  final double fontScale;
  final SubscriptionRepository repository;
  final VoidCallback onLogin;
  final VoidCallback? onSubscribe;
  final VoidCallback? onOpenSaved;
  final bool signedIn;
  final ReaderApiClient? readerClient;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Future<bool>? _premium;
  Future<List<Map<String, dynamic>>>? _invoices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signedIn != widget.signedIn) _load();
  }

  void _load() {
    final client = widget.readerClient;
    if (!widget.signedIn || client == null) {
      _premium = null;
      _invoices = null;
      return;
    }
    _premium = client.subscriptionStatus().then(
      (status) => status['active'] == true,
    );
    _invoices = client.getInvoices();
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: 'Georgia',
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final client = widget.readerClient;
    final signedIn = widget.signedIn && client != null;
    final name = signedIn ? client.accountDisplayName : 'Tamu';
    final email = signedIn
        ? (client.currentUserEmail ?? '')
        : 'Masuk untuk sinkronisasi';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const Text(
          'PROFIL PENGGUNA',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xff111111),
              foregroundColor: Colors.white,
              child: Text(
                name.characters.firstOrNull?.toUpperCase() ?? 'T',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(email, style: const TextStyle(fontSize: 11)),
                  FutureBuilder<bool>(
                    future: _premium,
                    builder: (context, snapshot) {
                      final status = snapshot.hasError
                          ? 'Status langganan tidak tersedia'
                          : !snapshot.hasData
                          ? 'Memeriksa langganan...'
                          : snapshot.data == true
                          ? 'Pelanggan Premium'
                          : 'Pembaca Gratis';
                      return Text(
                        status,
                        style: const TextStyle(
                          color: Color(0xff77736d),
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: widget.onSubscribe,
          icon: const Icon(Icons.workspace_premium, size: 16),
          label: const Text('Upgrade ke Subscriber Premium (QRIS)'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff111111),
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(child: _section('Riwayat Transaksi QRIS')),
            const SizedBox(width: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _invoices,
              builder: (context, snapshot) => Flexible(
                child: Text(
                  '${snapshot.data?.length ?? 0} Transaksi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ],
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _invoices,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Riwayat transaksi belum dapat dimuat.',
                  style: TextStyle(color: Color(0xff8b1e1e), fontSize: 11),
                ),
              );
            }
            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Icon(Icons.history, color: Color(0xff999999)),
                    SizedBox(height: 4),
                    Text(
                      'Belum ada riwayat transaksi',
                      style: TextStyle(color: Color(0xff999999), fontSize: 11),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      item['packageName']?.toString() ??
                          item['packageId']?.toString() ??
                          'Langganan',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${item['id']} • ${item['status']}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: Text(
                      formatRupiah((item['amount'] as num?)?.toInt() ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            );
          },
        ),
        _section('Pengaturan & Preferensi'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.contrast),
          title: const Text(
            'Tema Gelap (Dark Mode)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          value: Theme.of(context).brightness == Brightness.dark,
          onChanged: widget.onDarkMode,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.text_fields),
          title: const Text(
            'Ukuran teks artikel',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          trailing: DropdownButton<double>(
            value: widget.fontScale,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: .9, child: Text('Kecil')),
              DropdownMenuItem(value: 1, child: Text('Sedang')),
              DropdownMenuItem(value: 1.15, child: Text('Besar')),
            ],
            onChanged: (value) {
              if (value != null) widget.onFontScale(value);
            },
          ),
        ),
        _tile(
          Icons.bookmark_border,
          'Artikel Tersimpan',
          'Berita yang disimpan untuk dibaca nanti',
          widget.onOpenSaved,
        ),
        _tile(
          Icons.manage_accounts_outlined,
          signedIn ? 'Ganti Akun / Masuk / Daftar' : 'Masuk / Daftar',
          'Sinkronkan berita tersimpan dan langganan',
          widget.onLogin,
        ),
      ],
    );
  }
}

class PlansPage extends StatefulWidget {
  const PlansPage({
    super.key,
    required this.repository,
    this.readerClient,
    this.embedded = false,
    this.onLogin,
  });
  final SubscriptionRepository repository;
  final ReaderApiClient? readerClient;
  final bool embedded;
  final Future<void> Function()? onLogin;

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  late final Future<List<SubscriptionPlan>> _plansFuture = widget.repository
      .getActivePlans();
  String? _selectedId;
  Map<String, dynamic>? _invoice;
  bool _busy = false;

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: 'Georgia',
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _row(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  Map<String, dynamic>? get _paymentMethod {
    final methods = appContentSettings.value.paymentMethods
        .where((method) => method['enabled'] == true)
        .toList();
    return methods.where((method) => method['id'] == 'qris').firstOrNull ??
        methods.firstOrNull;
  }

  Future<void> _checkout(SubscriptionPlan plan) async {
    final client = widget.readerClient;
    final messenger = ScaffoldMessenger.of(context);
    if (client == null || client.accessToken == null) {
      await widget.onLogin?.call();
      if (!mounted) return;
      if (widget.readerClient?.accessToken == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Masuk terlebih dahulu untuk checkout.'),
          ),
        );
        return;
      }
    }
    final method = _paymentMethod;
    if (method == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Belum ada metode pembayaran aktif.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final invoice = await widget.readerClient!.checkout(
        plan.id,
        paymentMethod: method['id'].toString(),
      );
      if (mounted) setState(() => _invoice = invoice);
    } on ReaderApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<SubscriptionPlan>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Paket belum dapat dimuat.'));
        }
        final plans = snapshot.data ?? const <SubscriptionPlan>[];
        if (plans.isEmpty) {
          return const Center(child: Text('Paket langganan belum tersedia.'));
        }
        final selected =
            plans.where((plan) => plan.id == _selectedId).firstOrNull ??
            plans.first;
        final invoice = _invoice;
        final base = invoice == null
            ? selected.price
            : (invoice['baseAmount'] as num?)?.toInt() ?? selected.price;
        final code = (invoice?['uniqueCode'] as num?)?.toInt();
        final total = (invoice?['amount'] as num?)?.toInt() ?? selected.price;
        final method = _paymentMethod;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _title('1. Pilih Paket Langganan'),
            for (final plan in plans)
              GestureDetector(
                onTap: invoice != null
                    ? null
                    : () => setState(() => _selectedId = plan.id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: plan.id == selected.id
                          ? const Color(0xff111111)
                          : AppColors.line,
                      width: plan.id == selected.id ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            formatRupiah(plan.price),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final benefit in plan.benefits)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check,
                                size: 12,
                                color: Color(0xff21856a),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  benefit,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff555555),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            _title('2. Rincian Tagihan'),
            _row('Harga Paket Dasar:', formatRupiah(base)),
            if (code != null)
              _row(
                'Kode Unik Verifikasi:',
                '+ ${formatRupiah(code)}',
                color: AppColors.red,
              ),
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL YANG HARUS DIBAYAR:',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        formatRupiah(total),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (code != null)
                  FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: total.toString()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nominal disalin.')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Salin'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff111111),
                    ),
                  ),
              ],
            ),
            if (invoice != null) ...[
              const SizedBox(height: 6),
              _title('3. Pembayaran Aman'),
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      color: AppColors.red,
                      child: Text(
                        '${invoice['paymentMethodName'] ?? method?['name'] ?? 'Pembayaran online'} • PEMBAYARAN DIGITAL',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${invoice['paymentInstructions'] ?? method?['instructions'] ?? ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Invoice ${invoice['id']} • menunggu konfirmasi otomatis dari gateway',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xff77736d),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        final paymentUrl = Uri.tryParse(
                          invoice['paymentUrl']?.toString() ?? '',
                        );
                        if (paymentUrl == null ||
                            !await launchUrl(
                              paymentUrl,
                              mode: LaunchMode.platformDefault,
                            )) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Halaman pembayaran belum dapat dibuka.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: const Text('Buka Pembayaran Midtrans'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff111111),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _checkout(selected),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: Text(_busy ? 'Memproses...' : 'Lanjut ke Pembayaran'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff111111),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
    if (widget.embedded) {
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Langganan & Checkout QRIS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Langganan & Checkout QRIS')),
      body: body,
    );
  }
}

String formatRupiah(int value) =>
    'Rp${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match.group(1)}.')}';

class ArticleSearch extends SearchDelegate<Article?> {
  ArticleSearch(this.repository, this.onOpen);
  final ArticleRepository repository;
  final ValueChanged<Article> onOpen;
  @override
  Widget? buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));
  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];
  @override
  Widget buildResults(BuildContext context) => _list();
  @override
  Widget buildSuggestions(BuildContext context) => _list();
  Widget _list() => FutureBuilder<List<Article>>(
    future: repository.searchArticles(query),
    builder: (context, snapshot) {
      final items = snapshot.data ?? const <Article>[];
      return ListView(
        children: items
            .map(
              (item) => ListTile(
                title: Text(item.title),
                onTap: () {
                  close(context, item);
                  onOpen(item);
                },
              ),
            )
            .toList(),
      );
    },
  );
}

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      return Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xffeef2ff), Color(0xfff4f7ff)],
                ),
              ),
            ),
          ),
          Positioned(
            left: -100,
            top: -135,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0xffa9c0fb),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -110,
            bottom: -150,
            child: Container(
              width: 360,
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xffa8e1f2).withValues(alpha: .72),
                borderRadius: BorderRadius.circular(180),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 16 : 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Container(
                  height: compact ? null : 600,
                  constraints: BoxConstraints(minHeight: compact ? 0 : 600),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x263a4d74),
                        blurRadius: 36,
                        offset: Offset(0, 22),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: compact
                      ? _authFormPanel(child, compact: true)
                      : Row(
                          children: [
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 600,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xffbce8f8),
                                      Color(0xfff9fcff),
                                      Color(0xffa9bdfa),
                                    ],
                                    stops: [0, .52, 1],
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(56),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: const Color(0xff1d2638),
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 440,
                                        ),
                                        child: Text(
                                          description,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: const Color(0xff58657b),
                                            fontSize: 15,
                                            height: 1.7,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.public_rounded,
                                            color: Color(0xff2f68c7),
                                            size: 19,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'MAGELANG EKSPRES',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              color: const Color(0xff45658f),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 450, child: _authFormPanel(child)),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _authFormPanel(Widget child, {bool compact = false}) => Container(
    constraints: BoxConstraints(minHeight: compact ? 0 : 600),
    color: const Color(0xfffbf9ff),
    padding: EdgeInsets.all(compact ? 24 : 40),
    child: child,
  );
}

class LoginFlow extends StatefulWidget {
  const LoginFlow({super.key, this.api});
  final ReaderApiClient? api;
  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<LoginFlow> {
  late final ReaderApiClient api = widget.api ?? ReaderApiClient();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final code = TextEditingController();
  bool secondStep = false;
  bool obscurePassword = true;
  bool rememberMe = false;
  bool acceptsTerms = false;
  bool registerMode = false;
  bool loading = false;
  String? challengeToken;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.white,
    appBar: AppBar(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.navy,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Kembali',
        onPressed: () => Navigator.maybePop(context),
      ),
      elevation: 0,
    ),
    body: SafeArea(
      child: _AuthFrame(
        title: secondStep
            ? 'Satu langkah lagi untuk masuk'
            : 'Berita pilihan, akses tepercaya',
        description: secondStep
            ? 'Verifikasi identitas Anda untuk melanjutkan ke akun Magelang Ekspres.'
            : 'Masuk atau buat akun untuk menyimpan berita, menikmati artikel premium, dan mengelola langganan.',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: secondStep ? _verification() : _loginForm(),
        ),
      ),
    ),
  );

  Widget _loginForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        registerMode ? 'Buat Akun Pembaca' : 'Masuk ke Akun Anda',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        registerMode
            ? 'Daftar untuk menyimpan berita dan mengelola langganan.'
            : 'Akses berita premium dan kelola langganan dengan mudah.',
        style: TextStyle(color: AppColors.muted, fontSize: 13),
      ),
      const SizedBox(height: AppSpacing.xl),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Email',
          hintText: 'contoh@email.com',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: password,
        obscureText: obscurePassword,
        decoration: InputDecoration(
          labelText: 'Kata sandi',
          hintText: 'Masukkan password Anda',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: obscurePassword
                ? 'Tampilkan password'
                : 'Sembunyikan password',
            icon: Icon(
              obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => obscurePassword = !obscurePassword),
          ),
        ),
      ),
      if (registerMode) ...[
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: confirmPassword,
          obscureText: obscurePassword,
          decoration: const InputDecoration(
            labelText: 'Ulangi kata sandi',
            border: OutlineInputBorder(),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: acceptsTerms,
            onChanged: (value) => setState(() => acceptsTerms = value ?? false),
            title: const Text('Saya menyetujui syarat dan ketentuan.'),
          ),
        ),
      ] else
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: rememberMe,
                  onChanged: (value) =>
                      setState(() => rememberMe = value ?? false),
                ),
                const Expanded(
                  child: Text('Ingat saya', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            TextButton(
              onPressed: loading ? null : _forgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Lupa kata sandi?',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            error!,
            style: const TextStyle(color: AppColors.red, fontSize: 12),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          onPressed: loading ? null : _continueLogin,
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(registerMode ? 'DAFTAR' : 'MASUK'),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              registerMode ? 'atau daftar dengan' : 'atau masuk dengan',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _feedback(
                'Login Google tersedia setelah provider autentikasi dikonfigurasi.',
              ),
              icon: const Icon(Icons.g_mobiledata),
              label: const Text('Google'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _feedback(
                'Login Apple tersedia setelah provider autentikasi dikonfigurasi.',
              ),
              icon: const Icon(Icons.apple),
              label: const Text('Apple'),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
      Center(
        child: TextButton(
          onPressed: () => setState(() {
            registerMode = !registerMode;
            error = null;
            confirmPassword.clear();
            acceptsTerms = false;
          }),
          child: Text(
            registerMode
                ? 'Sudah punya akun?  Masuk'
                : 'Belum punya akun?  Daftar sekarang',
          ),
        ),
      ),
    ],
  );

  Widget _verification() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Verifikasi keamanan',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        'Masukkan kode verifikasi yang diberikan oleh pemilik situs.',
        style: TextStyle(color: AppColors.muted, fontSize: 13),
      ),
      const SizedBox(height: AppSpacing.xl),
      TextField(
        controller: code,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Kode verifikasi',
          prefixIcon: Icon(Icons.verified_user_outlined),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: loading ? null : _verifyLogin,
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('VERIFIKASI'),
        ),
      ),
    ],
  );

  Future<void> _continueLogin() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Email/username dan password wajib diisi.');
      return;
    }
    if (registerMode && password.text != confirmPassword.text) {
      setState(() => error = 'Konfirmasi kata sandi belum sama.');
      return;
    }
    if (registerMode && !acceptsTerms) {
      setState(() => error = 'Setujui syarat dan ketentuan untuk mendaftar.');
      return;
    }
    setState(() {
      error = null;
      loading = true;
    });
    try {
      if (widget.api == null) {
        if (email.text.trim() != 'admin@magelangekspres.local' ||
            password.text != 'ubah-password-development') {
          throw const ReaderApiException('Email atau password demo salah.');
        }
        if (!mounted) return;
        setState(() {
          loading = false;
          challengeToken = 'local-demo';
          secondStep = true;
        });
        return;
      }
      if (registerMode) {
        await api.register(email.text.trim(), password.text);
        if (!mounted) return;
        setState(() {
          loading = false;
          registerMode = false;
          error = 'Registrasi berhasil. Silakan masuk.';
        });
        return;
      }
      challengeToken = await api.login(email.text.trim(), password.text);
      if (!mounted) return;
      setState(() {
        loading = false;
        secondStep = true;
      });
    } on ReaderApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            'Tidak dapat terhubung ke layanan akun. Periksa koneksi dan coba lagi.';
      });
    }
  }

  Future<void> _forgotPassword() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Isi email terlebih dahulu.');
      return;
    }
    setState(() {
      error = null;
      loading = true;
    });
    try {
      await api.forgotPassword(email.text.trim());
      if (!mounted) return;
      setState(() => loading = false);
      _feedback('Instruksi reset akan dikirim jika akun terdaftar.');
    } on ReaderApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.message;
      });
    }
  }

  Future<void> _verifyLogin() async {
    if (code.text.trim().isEmpty) {
      setState(() => error = 'Kode verifikasi wajib diisi.');
      return;
    }
    final challenge = challengeToken;
    if (challenge == null) {
      setState(() => error = 'Sesi verifikasi sudah kedaluwarsa.');
      return;
    }
    setState(() {
      error = null;
      loading = true;
    });
    try {
      if (widget.api == null) {
        if (code.text.trim() != '123456') {
          throw const ReaderApiException('Kode demo salah.');
        }
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Login berhasil.')));
        return;
      }
      await api.verify(challenge, code.text.trim(), rememberMe: rememberMe);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Login berhasil.')));
    } on ReaderApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.message;
      });
    }
  }

  void _feedback(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final api = AdminApiClient();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final code = TextEditingController();
  String? challenge;
  String? role;
  String section = 'Dashboard';
  bool loading = false;
  bool registerMode = false;
  bool obscurePassword = true;
  String registrationRole = 'Author';
  bool premiumOnly = false;
  String articleSearch = '';
  String customerSearch = '';
  String subscriptionSearch = '';
  List<Map<String, dynamic>> articles = [];
  Future<void>? articlesLoadFuture;
  String? articlesLoadError;
  bool articlesLoaded = false;
  bool articlesLoading = false;
  int articlesLoadGeneration = 0;
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> adminCategories = [];
  List<Map<String, dynamic>> plans = [];
  List<Map<String, dynamic>> payments = [];
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> notifications = [];
  int unreadNotifications = 0;
  List<Map<String, dynamic>> epapers = [];
  Map<String, dynamic>? dashboard;
  String? error;
  bool savingSiteSettings = false;
  String? selectedEpaperPdfName;
  String? selectedEpaperPrivateFileName;
  final contentFields = <String, TextEditingController>{
    for (final entry in AppContentSettings.defaults.toJson().entries)
      entry.key: TextEditingController(
        text: entry.value is List
            ? (entry.value as List).join(', ')
            : entry.value.toString(),
      ),
  };

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    code.dispose();
    for (final controller in contentFields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: role == null ? _login() : _cms());

  Widget _login() => _AuthFrame(
    title: challenge == null
        ? 'Cepat, efisien, dan produktif'
        : 'Akun Anda tetap terlindungi',
    description: challenge == null
        ? 'Ruang kerja redaksi untuk mengelola berita, e-paper, pelanggan, dan langganan.'
        : 'Verifikasi dua langkah diperlukan sebelum membuka dashboard redaksi.',
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            challenge != null
                ? 'Verifikasi dua langkah'
                : registerMode
                ? 'Daftar akun redaksi'
                : 'Masuk ke CMS',
            style: TextStyle(
              fontFamily: 'Inter',
              color: const Color(0xff1d2638),
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            challenge != null
                ? 'Kode 6 digit telah dikirim ke email akun admin Anda. Kode berlaku selama 5 menit.'
                : registerMode
                ? _registrationRoleDescription
                : 'Gunakan akun admin untuk mengelola konten.',
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          if (challenge == null) ...[
            if (registerMode) ...[
              DropdownButtonFormField<String>(
                initialValue: registrationRole,
                decoration: const InputDecoration(
                  labelText: 'Jenis akun',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Admin',
                    child: Text('Admin - redaksi & publikasi'),
                  ),
                  DropdownMenuItem(
                    value: 'Author',
                    child: Text('Author - draft & review'),
                  ),
                ],
                onChanged: loading
                    ? null
                    : (value) =>
                          setState(() => registrationRole = value ?? 'Author'),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: 'Kata sandi',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: obscurePassword
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => obscurePassword = !obscurePassword),
                ),
              ),
            ),
            if (registerMode) ...[
              const SizedBox(height: 14),
              TextField(
                controller: confirmPassword,
                obscureText: obscurePassword,
                decoration: const InputDecoration(
                  labelText: 'Ulangi kata sandi',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ] else
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kode verifikasi',
                hintText: '6 digit',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: loading
                  ? null
                  : challenge != null
                  ? _verifyAdmin
                  : registerMode
                  ? _registerAdmin
                  : _loginAdmin,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      challenge != null
                          ? 'VERIFIKASI'
                          : registerMode
                          ? 'DAFTARKAN AKUN'
                          : 'MASUK',
                    ),
            ),
          ),
          if (challenge != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: loading
                    ? null
                    : () => setState(() {
                        challenge = null;
                        code.clear();
                        error = null;
                      }),
                child: const Text('Kembali ke login'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: loading
                    ? null
                    : () => setState(() {
                        registerMode = !registerMode;
                        error = null;
                        confirmPassword.clear();
                      }),
                child: Text(
                  registerMode
                      ? 'Sudah punya akun admin? Masuk'
                      : 'Belum punya akun admin? Daftar',
                ),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _cms() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      final nav = _nav();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            SizedBox(
              width: 248,
              child: ColoredBox(
                color: _roleSidebarColor,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cmsBrand(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(children: nav),
                        ),
                      ),
                      _logoutTile(),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(72),
                child: AppBar(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xff12213a),
                  elevation: 0,
                  titleSpacing: compact ? 0 : 24,
                  title: Text(
                    section,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xff12213a),
                    ),
                  ),
                  actions: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded),
                          tooltip: 'Notifikasi',
                          onPressed: _showNotifications,
                        ),
                        if (unreadNotifications > 0)
                          Positioned(
                            right: 6,
                            top: 7,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xffe7eef9),
                      child: Icon(
                        Icons.person_outline,
                        color: Color(0xff123b77),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!compact)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _roleDisplayName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _roleScope,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff77849a),
                            ),
                          ),
                        ],
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'logout') {
                          _logout();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'logout', child: Text('Keluar')),
                      ],
                    ),
                  ],
                ),
              ),
              drawer: compact
                  ? Drawer(
                      backgroundColor: _roleSidebarColor,
                      surfaceTintColor: Colors.transparent,
                      child: SafeArea(
                        child: ListView(
                          children: [
                            _cmsBrand(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Column(children: nav),
                            ),
                            _logoutTile(),
                          ],
                        ),
                      ),
                    )
                  : null,
              body: _content(),
            ),
          ),
        ],
      );
    },
  );

  List<Widget> _nav() => _sectionsForRole
      .map(
        (item) => ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(
            _icon(item),
            color: item == section ? Colors.white : Colors.white60,
            size: 20,
          ),
          title: Text(
            item,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          selected: item == section,
          selectedTileColor: AppColors.navy,
          onTap: () {
            setState(() => section = item);
            if (item == 'Artikel') _loadArticles();
            if (item == 'Dashboard') _loadDashboard();
            if (item == 'Langganan') _loadPlans();
            if (item == 'Pembayaran') _loadPayments();
            if (item == 'Notifikasi') _loadNotifications();
            if (item == 'Kategori') _loadAdminCategories();
            if (item == 'E-Paper') _loadEpapers();
            if (item == 'Pelanggan') _loadCustomers();
            if (item == 'Pengaturan') _loadSiteSettings();
          },
        ),
      )
      .toList();

  Widget _logoutTile() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: const Icon(
        Icons.logout_rounded,
        color: Colors.white60,
        size: 20,
      ),
      title: Text(
        'Keluar',
        style: TextStyle(
          fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: _logout,
    ),
  );

  void _logout() {
    setState(() {
      role = null;
      api.accessToken = null;
      challenge = null;
      section = 'Dashboard';
      _resetArticleCache();
    });
  }

  void _resetArticleCache() {
    articlesLoadGeneration++;
    articlesLoadFuture = null;
    articlesLoaded = false;
    articlesLoading = false;
    articlesLoadError = null;
    articles = [];
  }

  List<String> get _sectionsForRole {
    if (role == 'Super Admin') {
      return const [
        'Dashboard',
        'Artikel',
        'E-Paper',
        'Kategori',
        'Pelanggan',
        'Langganan',
        'Pembayaran',
        'Notifikasi',
        'Pengaturan',
        'Akun',
      ];
    }
    if (role == 'Editor') {
      return const [
        'Dashboard',
        'Artikel',
        'E-Paper',
        'Kategori',
        'Notifikasi',
        'Akun',
      ];
    }
    return const ['Dashboard', 'Artikel', 'E-Paper', 'Akun'];
  }

  Color get _roleSidebarColor {
    switch (role) {
      case 'Super Admin':
        return AppColors.navyDeep;
      case 'Editor':
        return AppColors.navyDeep;
      default:
        return AppColors.navyDeep;
    }
  }

  String get _roleBrandLabel {
    switch (role) {
      case 'Super Admin':
        return 'SUPER ADMIN PANEL';
      case 'Editor':
        return 'CMS REDAKSI';
      default:
        return 'RUANG PENULIS';
    }
  }

  String get _roleDisplayName => role == 'Editor' ? 'Admin' : role ?? 'Admin';

  String get _roleScope {
    switch (role) {
      case 'Super Admin':
        return 'Semua modul & konfigurasi';
      case 'Editor':
        return 'Redaksi & publikasi';
      default:
        return 'Draft & kirim review';
    }
  }

  String get _registrationRoleDescription {
    switch (registrationRole) {
      case 'Admin':
        return 'Akun redaksi untuk review, publikasi, dan e-paper.';
      default:
        return 'Akun penulis untuk membuat draft dan mengirim review.';
    }
  }

  Widget _cmsBrand() => Container(
  padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
  decoration: const BoxDecoration(
    border: Border(
      bottom: BorderSide(color: Color(0x33ffffff), width: 1),
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Logo bulat dengan latar putih
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: MagelangLogo(compact: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'MAGELANG ',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: const Color(0xffdcecff),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      TextSpan(
                        text: 'EKSPRES',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.red,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Akurat, Terpercaya, Menginspirasi',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      // Label panel (SUPER ADMIN PANEL, CMS REDAKSI, dll.)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Text(
          _roleBrandLabel,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xffdcecff),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ),
    ],
  ),
);

  IconData _icon(String item) =>
      {
        'Dashboard': Icons.dashboard_outlined,
        'Artikel': Icons.article_outlined,
        'E-Paper': Icons.menu_book_outlined,
        'Kategori': Icons.category_outlined,
        'Pelanggan': Icons.groups_outlined,
        'Langganan': Icons.card_membership_outlined,
        'Pembayaran': Icons.payments_outlined,
        'Notifikasi': Icons.notifications_none,
        'Pengaturan': Icons.settings_outlined,
        'Akun': Icons.manage_accounts_outlined,
      }[item] ??
      Icons.circle_outlined;

  Widget _content() {
    if (section == 'Dashboard') return _dashboardView();
    if (section == 'Artikel') return _articleTable();
    if (section == 'Langganan') return _subscriptionTable();
    if (section == 'Kategori') return _categoryTable();
    if (section == 'E-Paper') return _epaperTable();
    if (section == 'Pelanggan') return _customerTable();
    if (section == 'Pembayaran') return _paymentTable();
    if (section == 'Notifikasi') return _notificationView();
    if (section == 'Pengaturan') return _settingsView();
    if (section == 'Akun') {
      return _AccountSettingsView(
        key: const ValueKey('account-settings'),
        api: api,
        onToast: _toast,
      );
    }
    return _modulePreview(section);
  }

  Future<void> _loadCustomers() async {
    try {
      final values = await api.customers();
      if (mounted) setState(() => customers = values);
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final result = await api.notifications();
      if (!mounted) return;
      setState(() {
        notifications = (result['items'] as List).cast<Map<String, dynamic>>();
        unreadNotifications = (result['unread'] as num?)?.toInt() ?? 0;
      });
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _showNotifications() async {
    await _loadNotifications();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black12,
      builder: (dialogContext) => Dialog(
        alignment: Alignment.topRight,
        insetPadding: const EdgeInsets.fromLTRB(0, 86, 20, 20),
        child: SizedBox(
          width: 390,
          height: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                child: Row(
                  children: [
                    Text(
                      'Notifikasi',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: unreadNotifications == 0
                          ? null
                          : () async {
                              await api.markNotificationsRead();
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              await _loadNotifications();
                            },
                      child: const Text('Tandai sudah dibaca'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: notifications.isEmpty
                    ? const Center(child: Text('Belum ada notifikasi.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final item = notifications[index];
                          final isUnread = item['read'] != true;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xffeaf1fc),
                              child: Icon(
                                item['type'] == 'payment'
                                    ? Icons.payments_outlined
                                    : Icons.notifications_none_rounded,
                                color: AppColors.navy,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item['title']?.toString() ?? 'Aktivitas',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isUnread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              item['message']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: isUnread
                                ? const Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: AppColors.red,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationView() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Notifikasi',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: unreadNotifications == 0
                    ? null
                    : () async {
                        await api.markNotificationsRead();
                        await _loadNotifications();
                      },
                child: const Text('Tandai sudah dibaca'),
              ),
              IconButton(
                tooltip: 'Muat ulang notifikasi',
                onPressed: _loadNotifications,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 14),
      Card(
        child: notifications.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Belum ada notifikasi.')),
              )
            : Column(
                children: notifications
                    .map(
                      (item) => ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xffeaf1fc),
                          child: Icon(
                            Icons.notifications_none_rounded,
                            color: AppColors.navy,
                          ),
                        ),
                        title: Text(item['title']?.toString() ?? 'Aktivitas'),
                        subtitle: Text(item['message']?.toString() ?? ''),
                        trailing: item['read'] == true
                            ? null
                            : const Icon(
                                Icons.circle,
                                size: 8,
                                color: AppColors.red,
                              ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );

  Widget _customerTable() {
    final query = customerSearch.trim().toLowerCase();
    final visible = customers.where((customer) {
      if (query.isEmpty) return true;
      return customer.values.any(
        (value) => value.toString().toLowerCase().contains(query),
      );
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pelanggan',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${visible.length} pelanggan terdaftar',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (role == 'Super Admin')
                  FilledButton.icon(
                    onPressed: () => _showCustomerForm(),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                    label: const Text('Tambah pelanggan'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loadCustomers,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Muat ulang'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xffe4e9f1)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => customerSearch = value),
                      decoration: InputDecoration(
                        hintText: 'Cari nama atau email pelanggan...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xfff6f8fb),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Belum ada data pelanggan.'),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 42,
                        dataRowMinHeight: 62,
                        dataRowMaxHeight: 70,
                        columnSpacing: 28,
                        headingTextStyle: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                        columns: const [
                          DataColumn(label: Text('PELANGGAN')),
                          DataColumn(label: Text('EMAIL')),
                          DataColumn(label: Text('PERAN')),
                          DataColumn(label: Text('STATUS')),
                          DataColumn(label: Text('VERIFIKASI')),
                          DataColumn(label: Text('AKSI')),
                        ],
                        rows: visible.map((customer) {
                          final name = customer['name']?.toString() ?? '-';
                          return DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 170,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: const Color(
                                          0xffe8f0fb,
                                        ),
                                        child: Text(
                                          name.isEmpty ? '?' : name[0],
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            color: AppColors.navy,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          name,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(customer['email']?.toString() ?? '-'),
                              ),
                              DataCell(
                                Text(customer['role']?.toString() ?? '-'),
                              ),
                              DataCell(
                                _customerStatusBadge(customer['status']),
                              ),
                              DataCell(
                                _badge(
                                  customer['verified'] == true
                                      ? 'Terverifikasi'
                                      : 'Belum verifikasi',
                                  customer['verified'] == true
                                      ? const Color(0xff2c9b61)
                                      : const Color(0xffe38b29),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Detail pelanggan',
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                        size: 19,
                                      ),
                                      color: const Color(0xff2d6db5),
                                      onPressed: () =>
                                          _showCustomerDetail(customer),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit pelanggan',
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                      ),
                                      color: const Color(0xffc47a20),
                                      onPressed: () =>
                                          _showCustomerForm(customer: customer),
                                    ),
                                    if (role == 'Super Admin')
                                      IconButton(
                                        tooltip: 'Hapus pelanggan',
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 19,
                                        ),
                                        color: const Color(0xffc43b45),
                                        onPressed: () =>
                                            _deleteCustomer(customer),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _customerStatusBadge(Object? value) => _badge(
    value?.toString() ?? 'Terdaftar',
    value == 'Aktif' ? const Color(0xff2c9b61) : const Color(0xff3970b9),
  );

  Future<void> _showCustomerDetail(Map<String, dynamic> customer) async {
    if (role != 'Super Admin') return;
    try {
      final detail = await api.customer(customer['email'].toString());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: const Color(0xfff7f9fc),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PELANGGAN  /  DETAIL',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              detail['name']?.toString() ?? 'Detail pelanggan',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: const Color(0xff14233b),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup detail',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xffe4e9f1)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xffe8f0fb),
                          child: Text(
                            (detail['name']?.toString().isNotEmpty ?? false)
                                ? detail['name'].toString()[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail['email']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _customerStatusBadge(detail['status']),
                                  _badge(
                                    detail['verified'] == true
                                        ? 'Terverifikasi'
                                        : 'Belum verifikasi',
                                    detail['verified'] == true
                                        ? const Color(0xff2c9b61)
                                        : const Color(0xffe38b29),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _detailTile('Peran', detail['role'] ?? 'Reader'),
                      _detailTile(
                        'Status akun',
                        detail['status'] ?? 'Terdaftar',
                      ),
                      _detailTile(
                        'Email',
                        detail['verified'] == true
                            ? 'Terverifikasi'
                            : 'Belum terverifikasi',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Widget _detailTile(String label, Object? value) => Container(
    width: 210,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffe4e9f1)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Future<void> _showCustomerForm({Map<String, dynamic>? customer}) async {
    if (role != 'Super Admin') return;
    final editing = customer != null;
    final email = TextEditingController(
      text: customer?['email']?.toString() ?? '',
    );
    final password = TextEditingController();
    var subscriber = customer?['status'] == 'Aktif';
    var verified = customer?['verified'] == true;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xfff7f9fc),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 22, 18, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PELANGGAN  /  ${editing ? 'EDIT' : 'BARU'}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              editing ? 'Edit pelanggan' : 'Tambah pelanggan',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: const Color(0xff14233b),
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup form',
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xffe4e9f1)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xffe8f0fb),
                                child: Icon(
                                  Icons.person_outline,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  editing
                                      ? 'Perbarui akses dan status pelanggan.'
                                      : 'Buat akun pelanggan baru.',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: email,
                          readOnly: editing,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email pelanggan',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: password,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: editing
                                ? 'Kata sandi baru (opsional)'
                                : 'Kata sandi',
                            helperText: editing
                                ? 'Kosongkan jika tidak ingin mengganti kata sandi.'
                                : 'Minimal 8 karakter.',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'STATUS AKUN',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xffe4e9f1)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                title: const Text('Pelanggan aktif'),
                                subtitle: const Text(
                                  'Izinkan akses dan langganan pada akun ini.',
                                ),
                                value: subscriber,
                                onChanged: (value) =>
                                    setDialogState(() => subscriber = value),
                              ),
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              SwitchListTile(
                                title: const Text('Email terverifikasi'),
                                subtitle: const Text(
                                  'Tandai alamat email sebagai terverifikasi.',
                                ),
                                value: verified,
                                onChanged: (value) =>
                                    setDialogState(() => verified = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('BATAL'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                if (email.text.trim().isEmpty ||
                                    (!editing && password.text.length < 8)) {
                                  _toast(
                                    'Email wajib diisi dan password minimal 8 karakter.',
                                  );
                                  return;
                                }
                                setDialogState(() => saving = true);
                                try {
                                  if (editing) {
                                    await api.updateCustomer(
                                      email: email.text.trim(),
                                      password: password.text,
                                      subscriber: subscriber,
                                      emailVerified: verified,
                                    );
                                  } else {
                                    await api.createCustomer(
                                      email: email.text.trim(),
                                      password: password.text,
                                      subscriber: subscriber,
                                      emailVerified: verified,
                                    );
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                  await _loadCustomers();
                                  if (mounted) {
                                    _toast('Data pelanggan berhasil disimpan.');
                                  }
                                } catch (exception) {
                                  setDialogState(() => saving = false);
                                  if (mounted) _toast(exception.toString());
                                }
                              },
                        icon: Icon(
                          editing
                              ? Icons.save_outlined
                              : Icons.person_add_alt_1,
                          size: 18,
                        ),
                        label: Text(
                          saving
                              ? 'MENYIMPAN...'
                              : editing
                              ? 'SIMPAN PERUBAHAN'
                              : 'TAMBAH PELANGGAN',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    email.dispose();
    password.dispose();
  }

  Future<void> _deleteCustomer(Map<String, dynamic> customer) async {
    if (role != 'Super Admin') return;
    final email = customer['email']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus pelanggan?'),
        content: Text('Akun $email akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.deleteCustomer(email);
      await _loadCustomers();
      if (mounted) _toast('Pelanggan berhasil dihapus.');
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _loadSiteSettings() async {
    try {
      final values = await api.siteSettings();
      if (!mounted) return;
      for (final entry in contentFields.entries) {
        final value = values[entry.key];
        entry.value.text = value is List
            ? value.join(', ')
            : value?.toString() ?? '';
      }
      appContentSettings.value = AppContentSettings.fromJson(values);
      setState(() {});
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _saveSiteSettings() async {
    setState(() => savingSiteSettings = true);
    final values = <String, dynamic>{
      for (final entry in contentFields.entries)
        if (entry.key != 'hotTopics') entry.key: entry.value.text.trim(),
      'hotTopics': appContentSettings.value.hotTopics,
      'paymentMethods': appContentSettings.value.paymentMethods,
    };
    try {
      final saved = await api.saveSiteSettings(values);
      appContentSettings.value = AppContentSettings.fromJson(saved);
      if (mounted) _toast('Pengaturan beranda berhasil disimpan.');
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    } finally {
      if (mounted) setState(() => savingSiteSettings = false);
    }
  }

  Future<void> _pickAndUploadImage(String fieldKey) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: 'Pilih gambar',
      );
      if (result.isEmpty) return;
      final file = result.first;
      final bytes = await file.readAsBytes();
      setState(() => loading = true);
      final uploaded = await api.uploadMedia(
        bytes: bytes,
        fileName: file.name,
        kind: 'image',
      );
      if (!mounted) return;
      setState(
        () => contentFields[fieldKey]!.text = uploaded['url'].toString(),
      );
      _toast('Gambar berhasil diunggah. Simpan pengaturan untuk menerapkan.');
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _clearUnusedImage(String fieldKey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus gambar?'),
        content: const Text(
          'Gambar akan dilepas dari pengaturan. File dihapus jika tidak dipakai konten lain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final oldUrl = contentFields[fieldKey]!.text.trim();
    setState(() => contentFields[fieldKey]!.clear());
    await _saveSiteSettings();
    if (oldUrl.contains('/media/')) {
      final fileName = Uri.tryParse(oldUrl)?.pathSegments.last;
      if (fileName != null && fileName.startsWith('media-')) {
        try {
          await api.deleteMedia(fileName);
        } catch (exception) {
          if (mounted) _toast(exception.toString());
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _editHotTopic([int? index]) async {
    final topics = [...appContentSettings.value.hotTopics];
    final controller = TextEditingController(
      text: index == null ? '' : topics[index],
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(index == null ? 'Tambah topik' : 'Edit topik'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          decoration: const InputDecoration(labelText: 'Nama topik'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    if (index == null) {
      if (topics.length >= 8) {
        _toast('Maksimal 8 topik hangat.');
        return;
      }
      topics.add(value.trim());
    } else {
      topics[index] = value.trim();
    }
    appContentSettings.value = AppContentSettings.fromJson({
      ...appContentSettings.value.toJson(),
      'hotTopics': topics,
    });
    setState(() {});
  }

  Future<void> _editPaymentMethod([int? index]) async {
    final methods = appContentSettings.value.paymentMethods
        .map(Map<String, dynamic>.from)
        .toList();
    final current = index == null ? null : methods[index];
    final name = TextEditingController(text: current?['name']?.toString());
    final instructions = TextEditingController(
      text: current?['instructions']?.toString(),
    );
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          index == null ? 'Tambah metode pembayaran' : 'Edit metode pembayaran',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 48,
              decoration: const InputDecoration(labelText: 'Nama metode'),
            ),
            TextField(
              controller: instructions,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Instruksi pembayaran',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, [
              name.text.trim(),
              instructions.text.trim(),
            ]),
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
    name.dispose();
    instructions.dispose();
    if (result == null || result.first.isEmpty) return;
    final id =
        current?['id']?.toString() ??
        result.first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final method = <String, dynamic>{
      'id': id,
      'name': result.first,
      'instructions': result[1],
      'enabled': current?['enabled'] ?? true,
    };
    if (index == null) {
      if (methods.length >= 8) {
        _toast('Maksimal 8 metode pembayaran.');
        return;
      }
      if (methods.any((item) => item['id'] == id)) {
        _toast('Nama metode tersebut sudah digunakan.');
        return;
      }
      methods.add(method);
    } else {
      methods[index] = method;
    }
    appContentSettings.value = AppContentSettings.fromJson({
      ...appContentSettings.value.toJson(),
      'paymentMethods': methods,
    });
    setState(() {});
  }

  void _deletePaymentMethod(int index) {
    final methods = [...appContentSettings.value.paymentMethods]
      ..removeAt(index);
    appContentSettings.value = AppContentSettings.fromJson({
      ...appContentSettings.value.toJson(),
      'paymentMethods': methods,
    });
    setState(() {});
  }

  void _deleteHotTopic(int index) {
    final topics = [...appContentSettings.value.hotTopics]..removeAt(index);
    appContentSettings.value = AppContentSettings.fromJson({
      ...appContentSettings.value.toJson(),
      'hotTopics': topics,
    });
    setState(() {});
  }

  Widget _contentField(String key, String label, {int maxLines = 1}) =>
      TextField(
        controller: contentFields[key],
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      );

  Widget _settingsSectionTitle(String title, String subtitle, IconData icon) =>
      Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xffeaf1fc),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: const Color(0xff2d62ad), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: const Color(0xff14233b),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _settingsView() => ColoredBox(
    color: const Color(0xfff4f7fb),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pengaturan Frontend',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xff14233b),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Kelola identitas dan konten yang tampil kepada pembaca.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _badge('KONFIGURASI CMS', const Color(0xff3970b9)),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9f1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xffeaf1fc),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.navy,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Konfigurasi redaksi',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Identitas media, headline, e-paper, langganan, dan metode pembayaran dalam satu ruang kerja.',
                        style: TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
                if (role == 'Super Admin')
                  const Icon(Icons.lock_open_outlined, color: AppColors.muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9f1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsSectionTitle(
                  'Identitas Media',
                  'Nama publik, tagline, dan logo media.',
                  Icons.storefront_outlined,
                ),
                const SizedBox(height: 16),
                _contentField('brandName', 'Nama media'),
                const SizedBox(height: 12),
                _contentField('tagline', 'Tagline'),
                const SizedBox(height: 12),
                _contentField('logoUrl', 'URL logo'),
                const SizedBox(height: 12),
                _mediaPreview(
                  contentFields['logoUrl']!.text,
                  const MagelangLogo(compact: true),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: loading
                          ? null
                          : () => _pickAndUploadImage('logoUrl'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('PILIH LOGO'),
                    ),
                    OutlinedButton.icon(
                      onPressed: contentFields['logoUrl']!.text.isEmpty
                          ? null
                          : () => _clearUnusedImage('logoUrl'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('HAPUS LOGO'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9f1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsSectionTitle(
                  'Headline Beranda',
                  'Judul, ringkasan, gambar utama, dan topik.',
                  Icons.newspaper_outlined,
                ),
                const SizedBox(height: 16),
                _contentField('heroLabel', 'Label headline'),
                const SizedBox(height: 12),
                _contentField('heroTitle', 'Judul pengganti (opsional)'),
                const SizedBox(height: 12),
                _contentField(
                  'heroExcerpt',
                  'Ringkasan pengganti (opsional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _contentField('heroImageUrl', 'URL gambar headline'),
                const SizedBox(height: 10),
                _mediaPreview(
                  contentFields['heroImageUrl']!.text,
                  const Icon(Icons.image_outlined, size: 42),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: loading
                          ? null
                          : () => _pickAndUploadImage('heroImageUrl'),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('UNGGAH GAMBAR HEADLINE'),
                    ),
                    OutlinedButton.icon(
                      onPressed: contentFields['heroImageUrl']!.text.isEmpty
                          ? null
                          : () => _clearUnusedImage('heroImageUrl'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('HAPUS GAMBAR'),
                    ),
                    ...appContentSettings.value.hotTopics.indexed.map(
                      (entry) => InputChip(
                        label: Text(entry.$2),
                        onPressed: () => _editHotTopic(entry.$1),
                        onDeleted: () => _deleteHotTopic(entry.$1),
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Tambah topik'),
                      onPressed: () => _editHotTopic(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9f1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsSectionTitle(
                  'E-Paper',
                  'Judul edisi dan gambar sampul digital.',
                  Icons.menu_book_outlined,
                ),
                const SizedBox(height: 16),
                _contentField('epaperTitle', 'Judul e-paper'),
                const SizedBox(height: 12),
                _contentField('epaperCoverImageUrl', 'URL cover e-paper'),
                const SizedBox(height: 10),
                _mediaPreview(
                  contentFields['epaperCoverImageUrl']!.text,
                  const Icon(Icons.menu_book_outlined, size: 42),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: loading
                      ? null
                      : () => _pickAndUploadImage('epaperCoverImageUrl'),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('UNGGAH COVER E-PAPER'),
                ),
                OutlinedButton.icon(
                  onPressed: contentFields['epaperCoverImageUrl']!.text.isEmpty
                      ? null
                      : () => _clearUnusedImage('epaperCoverImageUrl'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('HAPUS COVER'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9f1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsSectionTitle(
                  'Ajakan Berlangganan',
                  'Teks penawaran akses premium untuk pembaca.',
                  Icons.card_membership_outlined,
                ),
                const SizedBox(height: 16),
                _contentField('subscriptionTitle', 'Judul paywall'),
                const SizedBox(height: 12),
                _contentField(
                  'subscriptionDescription',
                  'Deskripsi paywall',
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xffe4e9f1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsSectionTitle(
                  'Metode Pembayaran',
                  'Aktifkan dan atur instruksi pembayaran.',
                  Icons.payments_outlined,
                ),
                const SizedBox(height: 8),
                ...appContentSettings.value.paymentMethods.indexed.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.$2['name']?.toString() ?? 'Metode baru'),
                    subtitle: Text(
                      entry.$2['instructions']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    leading: Switch(
                      value: entry.$2['enabled'] == true,
                      onChanged: (enabled) {
                        final methods = appContentSettings.value.paymentMethods
                            .map(Map<String, dynamic>.from)
                            .toList();
                        methods[entry.$1]['enabled'] = enabled;
                        appContentSettings.value = AppContentSettings.fromJson({
                          ...appContentSettings.value.toJson(),
                          'paymentMethods': methods,
                        });
                        setState(() {});
                      },
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Edit metode pembayaran',
                          onPressed: () => _editPaymentMethod(entry.$1),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Hapus metode pembayaran',
                          onPressed: () => _deletePaymentMethod(entry.$1),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _editPaymentMethod(),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah metode'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: savingSiteSettings ? null : _saveSiteSettings,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              savingSiteSettings ? 'MENYIMPAN...' : 'SIMPAN PENGATURAN',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _mediaPreview(String url, Widget fallback) => Container(
    height: 92,
    width: double.infinity,
    alignment: Alignment.center,
    color: const Color(0xffeef3f9),
    child: url.trim().isEmpty
        ? fallback
        : Image.network(
            url.trim(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback,
          ),
  );

  Widget _paymentTable() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pembayaran',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${payments.length} transaksi dari frontend',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Muat ulang pembayaran',
                onPressed: _loadPayments,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xffe4e9f1)),
            ),
            child: payments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Belum ada transaksi pembayaran.'),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 42,
                      dataRowMinHeight: 62,
                      dataRowMaxHeight: 70,
                      columnSpacing: 28,
                      headingTextStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      columns: const [
                        DataColumn(label: Text('NO.')),
                        DataColumn(label: Text('NAMA PELANGGAN')),
                        DataColumn(label: Text('TANGGAL')),
                        DataColumn(label: Text('PAKET')),
                        DataColumn(label: Text('NOMINAL')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('AKSI')),
                      ],
                      rows: payments.asMap().entries.map((entry) {
                        final invoice = entry.value;
                        final status =
                            invoice['status']?.toString() ?? 'pending';
                        final createdAt =
                            invoice['createdAt']?.toString() ?? '-';
                        return DataRow(
                          cells: [
                            DataCell(Text('${entry.key + 1}')),
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Row(
                                  children: [
                                    const CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Color(0xffe8f0fb),
                                      child: Icon(
                                        Icons.person_outline,
                                        color: AppColors.navy,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        invoice['customerName']?.toString() ??
                                            invoice['userId']?.toString() ??
                                            '-',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(Text(createdAt.split('T').first)),
                            DataCell(
                              Text(invoice['packageName']?.toString() ?? '-'),
                            ),
                            DataCell(
                              Text(
                                formatRupiah(
                                  (invoice['amount'] as num?)?.round() ?? 0,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DataCell(_paymentStatusBadge(status)),
                            DataCell(
                              IconButton(
                                tooltip: status == 'paid'
                                    ? 'Pembayaran terkonfirmasi'
                                    : 'Konfirmasi pembayaran',
                                icon: Icon(
                                  status == 'paid'
                                      ? Icons.check_circle_outline
                                      : Icons.verified_outlined,
                                  size: 19,
                                ),
                                color: status == 'paid'
                                    ? const Color(0xff2c9b61)
                                    : const Color(0xff2d6db5),
                                onPressed:
                                    status == 'paid' || role != 'Super Admin'
                                    ? null
                                    : () => _confirmPayment(invoice),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ),
      ),
    ],
  );

  Widget _paymentStatusBadge(String status) => _badge(
    status == 'paid' ? 'Lunas' : 'Menunggu',
    status == 'paid' ? const Color(0xff2c9b61) : const Color(0xffe38b29),
  );

  Widget _modulePreview(String module) {
    final samples = <String, List<String>>{
      'Pelanggan': [
        'Pembaca Setia - pembaca@example.com - Aktif',
        'Dina Lestari - dina@example.com - Trial',
      ],
      'Pembayaran': [
        'INV-2026-001 - Premium 1 Bulan - Lunas',
        'INV-2026-002 - Premium 1 Tahun - Menunggu',
      ],
      'Notifikasi': [
        'Breaking News: Latsarmil Kopdes Didesak Dihentikan',
        'Promo: Paket tahunan lebih hemat',
      ],
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          module,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text('Contoh data $module untuk simulasi workflow blueprint.'),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: (samples[module] ?? ['Belum ada data'])
                .map(
                  (item) => ListTile(
                    leading: Icon(_icon(module)),
                    title: Text(item),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _toast('Detail $module dibuka.'),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _categoryTable() => FutureBuilder<void>(
    future: adminCategories.isEmpty ? _loadAdminCategories() : null,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting || loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Container(
        color: const Color(0xfff5f7fb),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 40),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xff2e73dc),
                    borderRadius: BorderRadius.circular(29),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1f2e73dc),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.format_list_bulleted_rounded,
                    color: Colors.white,
                    size: 29,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${adminCategories.length} Kategori Aktif',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: const Color(0xff14233b),
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Kelola pengelompokan berita agar konten mudah ditemukan\ndan disesuaikan dengan kebutuhan redaksi.',
                        style: const TextStyle(
                          color: Color(0xff7d899d),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfff1fbf7),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: Color(0xff2bbf83),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            'Mudah disesuaikan',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: const Color(0xff8b93a1),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _newCategory,
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('Tambah'),
                        ),
                        IconButton(
                          tooltip: 'Muat ulang kategori',
                          onPressed: _loadAdminCategories,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 34),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1120
                    ? 4
                    : constraints.maxWidth >= 760
                    ? 3
                    : constraints.maxWidth >= 500
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - ((columns - 1) * 16)) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: adminCategories
                      .asMap()
                      .entries
                      .map(
                        (entry) => SizedBox(
                          width: width,
                          child: _categoryCard(entry.value, entry.key),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      );
    },
  );

  Widget _categoryCard(Map<String, dynamic> category, int index) {
    final name = category['name']?.toString() ?? 'Tanpa nama';
    final slug = category['slug']?.toString() ?? '-';
    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d172640),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xffedf4ff),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _categoryIcon(name, index),
              size: 25,
              color: const Color(0xff3478df),
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: const Color(0xff172640),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '/$slug',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff8994a6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (role == 'Super Admin')
                IconButton(
                  tooltip: 'Hapus kategori',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: const Color(0xffc43b45),
                  onPressed: () => _deleteCategory(slug),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String name, int index) {
    final normalized = name.toLowerCase();
    if (normalized.contains('olahraga')) return Icons.sports_soccer_outlined;
    if (normalized.contains('ekonomi')) return Icons.show_chart_outlined;
    if (normalized.contains('pendidikan')) return Icons.school_outlined;
    if (normalized.contains('politik')) return Icons.account_balance_outlined;
    if (normalized.contains('lifestyle')) {
      return Icons.self_improvement_outlined;
    }
    if (normalized.contains('e-paper')) return Icons.menu_book_outlined;
    const fallback = [
      Icons.newspaper_outlined,
      Icons.location_city_outlined,
      Icons.public_outlined,
      Icons.forum_outlined,
    ];
    return fallback[index % fallback.length];
  }

  Widget _dashboardView() {
    final counts =
        (dashboard?['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (counts['articles'] as num?)?.toInt() ?? articles.length;
    final drafts = (counts['drafts'] as num?)?.toInt() ?? 0;
    final published = (counts['published'] as num?)?.toInt() ?? 0;
    final reviews = (counts['reviews'] as num?)?.toInt() ?? 0;
    final publishedToday = (counts['publishedToday'] as num?)?.toInt() ?? 0;
    final activeSubscribers =
        (counts['activeSubscribers'] as num?)?.toInt() ?? 0;
    final conversionRate = (counts['conversionRate'] as num?)?.toDouble() ?? 0;
    return FutureBuilder<void>(
      future: dashboard == null ? _loadDashboard() : null,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Container(
          color: const Color(0xfff5f7fb),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 36),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: TextStyle(
                          color: Color(0xff14233b),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ringkasan kinerja harian',
                        style: TextStyle(color: Color(0xff7d899d)),
                      ),
                    ],
                  ),
                  if (role != 'Author') _periodSelector(),
                ],
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 800;
                  final cards = role == 'Author'
                      ? [
                          _metric(
                            'Artikel Saya',
                            total,
                            Icons.article_outlined,
                            const Color(0xff2563eb),
                            'Semua tulisan Anda',
                          ),
                          _metric(
                            'Draft Saya',
                            drafts,
                            Icons.edit_note_rounded,
                            const Color(0xff123e80),
                            'Siap dilanjutkan',
                          ),
                          _metric(
                            'Menunggu Review',
                            reviews,
                            Icons.hourglass_top_rounded,
                            const Color(0xfff28c28),
                            'Di meja redaksi',
                          ),
                          _metric(
                            'Sudah Terbit',
                            published,
                            Icons.check_circle_outline,
                            const Color(0xff2da663),
                            'Tayang di pembaca',
                          ),
                        ]
                      : role == 'Editor'
                      ? [
                          _metric(
                            'Terbit Hari Ini',
                            publishedToday,
                            Icons.article_outlined,
                            const Color(0xff2563eb),
                            'Artikel tayang',
                          ),
                          _metric(
                            'Perlu Review',
                            reviews,
                            Icons.rate_review_outlined,
                            const Color(0xfff28c28),
                            'Menunggu keputusan',
                          ),
                          _metric(
                            'Draft',
                            drafts,
                            Icons.edit_note_rounded,
                            const Color(0xff123e80),
                            'Belum dikirim',
                          ),
                          _metric(
                            'E-Paper Terbit',
                            (counts['epapers'] as num?)?.toInt() ?? 0,
                            Icons.menu_book_outlined,
                            const Color(0xffd88918),
                            'Status terbit',
                          ),
                        ]
                      : [
                          _metric(
                            'Artikel Aktif Hari Ini',
                            publishedToday,
                            Icons.article_outlined,
                            const Color(0xff2563eb),
                            'Terbit hari ini',
                          ),
                          _metric(
                            'Pelanggan Aktif',
                            activeSubscribers,
                            Icons.people_outline,
                            const Color(0xff0f9f8a),
                            'Aktif saat ini',
                          ),
                          _metric(
                            'E-Paper Terbit',
                            (counts['epapers'] as num?)?.toInt() ?? 0,
                            Icons.menu_book_outlined,
                            const Color(0xffd88918),
                            'Status terbit',
                          ),
                          _metric(
                            'Konversi Langganan',
                            '${conversionRate.toStringAsFixed(2)}%',
                            Icons.trending_up_rounded,
                            const Color(0xff7c4dcc),
                            'Dari pembaca terdaftar',
                          ),
                        ];
                  return wide
                      ? Row(
                          children: cards
                              .map(
                                (card) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: card,
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : Wrap(spacing: 12, runSpacing: 12, children: cards);
                },
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final traffic = _panel(
                    title: 'Traffic (Kunjungan)',
                    subtitle: '7 hari terakhir',
                    child: SizedBox(height: 220, child: _trafficChart()),
                  );
                  final status = _panel(
                    title: role == 'Author'
                        ? 'Status Artikel Saya'
                        : 'Artikel Berdasarkan Status',
                    child: _statusChart(total, drafts, reviews, published),
                  );
                  if (role == 'Author') return status;
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: traffic),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: status),
                          ],
                        )
                      : Column(children: [traffic, status]);
                },
              ),
              const SizedBox(height: 16),
              _panel(
                title: role == 'Author'
                    ? 'Tulisan Terbaru Saya'
                    : 'Artikel Terbaru',
                action: TextButton(
                  onPressed: () => setState(() => section = 'Artikel'),
                  child: const Text('Lihat semua'),
                ),
                child: _recentArticles(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _epaperTable() => FutureBuilder<void>(
    future: epapers.isEmpty ? _loadEpapers() : null,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting || loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Container(
        color: const Color(0xfff5f7fb),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 36),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'E-Paper',
                  style: TextStyle(
                    color: Color(0xff14233b),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _editEpaper(null),
                  icon: const Icon(Icons.add),
                  label: const Text('TAMBAH E-PAPER'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Kelola edisi koran digital, akses pelanggan, dan file PDF.',
              style: TextStyle(color: Color(0xff7d899d), fontSize: 12),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xffe4e9f1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Cari edisi e-paper...',
                            prefixIcon: const Icon(Icons.search, size: 19),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xfff6f8fb),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _loadEpapers,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Muat ulang'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 42,
                      dataRowMinHeight: 62,
                      dataRowMaxHeight: 70,
                      columnSpacing: 30,
                      headingTextStyle: const TextStyle(
                        color: Color(0xff7c8799),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      columns: const [
                        DataColumn(label: Text('NO.')),
                        DataColumn(label: Text('EDISI')),
                        DataColumn(label: Text('TANGGAL TERBIT')),
                        DataColumn(label: Text('HALAMAN')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('AKSES')),
                        DataColumn(label: Text('AKSI')),
                      ],
                      rows: epapers.asMap().entries.map((entry) {
                        final item = entry.value;
                        final status = item['status']?.toString() ?? 'draft';
                        return DataRow(
                          cells: [
                            DataCell(Text('${entry.key + 1}')),
                            DataCell(
                              SizedBox(
                                width: 250,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xffeaf0fa),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Icon(
                                        Icons.menu_book_outlined,
                                        color: Color(0xff2e5d9a),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        item['edition']?.toString() ??
                                            item['title']?.toString() ??
                                            '-',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(Text(item['date']?.toString() ?? '-')),
                            DataCell(
                              Text('${item['totalPages'] ?? 0} halaman'),
                            ),
                            DataCell(_statusBadge(status)),
                            DataCell(
                              _badge(
                                item['downloadAllowed'] == true
                                    ? 'Pelanggan'
                                    : 'Preview',
                                const Color(0xff3970b9),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Detail e-paper',
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 19,
                                    ),
                                    color: const Color(0xff2d6db5),
                                    onPressed: () => _showEpaperDetail(item),
                                  ),
                                  if (role != 'Author' ||
                                      item['status'] != 'published')
                                    IconButton(
                                      tooltip: 'Edit e-paper',
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                      ),
                                      color: const Color(0xffc47a20),
                                      onPressed: () => _editEpaper(item),
                                    ),
                                  if (role != 'Author')
                                    IconButton(
                                      tooltip: 'Hapus e-paper',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 19,
                                      ),
                                      color: const Color(0xffc43b45),
                                      onPressed: () =>
                                          _confirmDeleteEpaper(item),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _periodSelector() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffdce3ee)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Rentang Waktu', style: TextStyle(fontSize: 11)),
        SizedBox(width: 12),
        Text('Hari Ini', style: TextStyle(fontWeight: FontWeight.w700)),
        Icon(Icons.keyboard_arrow_down, size: 18),
      ],
    ),
  );

  Widget _metric(
    String label,
    Object? value,
    IconData icon,
    Color color,
    String change,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffe4e9f1)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff7d899d)),
              ),
              const SizedBox(height: 5),
              Text(
                '$value',
                style: const TextStyle(
                  color: Color(0xff15233c),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(change, style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _panel({
    required String title,
    String? subtitle,
    Widget? action,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffe4e9f1)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xff1a2942),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xff8994a6)),
              ),
            ],
            const Spacer(),
            ?action,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget _trafficChart() {
    final values = ((dashboard?['traffic'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return CustomPaint(
      painter: _TrafficChartPainter(values),
      child: const SizedBox.expand(),
    );
  }

  Widget _statusChart(int total, int drafts, int reviews, int published) {
    final safeTotal = total == 0 ? 1 : total;
    return Row(
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: CustomPaint(
            painter: _StatusChartPainter(
              drafts / safeTotal,
              reviews / safeTotal,
              published / safeTotal,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text('Total Artikel', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusLegend('Draft', drafts, const Color(0xff123e80)),
              _statusLegend('Review', reviews, const Color(0xfff28c28)),
              _statusLegend('Terbit', published, const Color(0xff2da663)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusLegend(String label, int value, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(width: 9, height: 9, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _recentArticles() {
    if (articles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Text('Belum ada artikel untuk ditampilkan.'),
      );
    }
    final recent = [...articles]
      ..sort((a, b) {
        final aDate = DateTime.tryParse(
          (a['publishedAt'] ?? a['updatedAt'])?.toString() ?? '',
        );
        final bDate = DateTime.tryParse(
          (b['publishedAt'] ?? b['updatedAt'])?.toString() ?? '',
        );
        return (bDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aDate ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
    return Column(
      children: recent.take(6).map((item) {
        final status = item['status']?.toString() ?? 'draft';
        final statusColor = status == 'published'
            ? const Color(0xff2da663)
            : const Color(0xfff28c28);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xffedf2fa),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.article_outlined, color: Color(0xff315b91)),
          ),
          title: Text(
            item['title']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Text(
            '${item['category'] ?? '-'} • ${item['author'] ?? '-'}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status == 'published' ? 'Terbit' : 'Draft',
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _articleTable() => Builder(
    builder: (context) {
      if (articlesLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (articlesLoadError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Artikel gagal dimuat: $articlesLoadError'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadArticles(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        );
      }
      final visible = premiumOnly
          ? articles.where((item) => item['isPremium'] == true).toList()
          : articles;
      final searched = articleSearch.trim().isEmpty
          ? visible
          : visible
                .where(
                  (item) =>
                      '${item['title']} ${item['category']} ${item['author']}'
                          .toLowerCase()
                          .contains(articleSearch.trim().toLowerCase()),
                )
                .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 36),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Artikel',
                style: const TextStyle(
                  color: Color(0xff14233b),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              FilledButton.icon(
                onPressed: _newArticle,
                icon: const Icon(Icons.add),
                label: const Text('TAMBAH ARTIKEL'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Kelola berita, status publikasi, dan akses premium.',
            style: TextStyle(color: Color(0xff7d899d), fontSize: 12),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xffe4e9f1)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => articleSearch = value),
                        decoration: InputDecoration(
                          hintText: 'Cari artikel...',
                          prefixIcon: const Icon(Icons.search, size: 19),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xfff6f8fb),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    _articleFilter('Semua', !premiumOnly, () {
                      setState(() => premiumOnly = false);
                    }),
                    _articleFilter('Premium', premiumOnly, () {
                      setState(() => premiumOnly = true);
                    }),
                    OutlinedButton.icon(
                      onPressed: () => _loadArticles(force: true),
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Muat ulang'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (searched.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      articleSearch.trim().isNotEmpty
                          ? 'Artikel tidak ditemukan.'
                          : role == 'Author'
                          ? 'Belum ada artikel untuk akun Anda.'
                          : 'Belum ada artikel.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 42,
                      dataRowMinHeight: 62,
                      dataRowMaxHeight: 70,
                      columnSpacing: 28,
                      headingTextStyle: const TextStyle(
                        color: Color(0xff7c8799),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      columns: const [
                        DataColumn(label: Text('NO.')),
                        DataColumn(label: Text('JUDUL ARTIKEL')),
                        DataColumn(label: Text('PENULIS')),
                        DataColumn(label: Text('KATEGORI')),
                        DataColumn(label: Text('AKSES')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('AKSI')),
                      ],
                      rows: searched.asMap().entries.map((entry) {
                        final item = entry.value;
                        return DataRow(
                          cells: [
                            DataCell(Text('${entry.key + 1}')),
                            DataCell(
                              SizedBox(
                                width: 280,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: const Color(0xffeaf0fa),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.article_outlined,
                                        size: 17,
                                        color: Color(0xff2e5d9a),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        item['title']?.toString() ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(Text(item['author']?.toString() ?? '-')),
                            DataCell(Text(item['category']?.toString() ?? '-')),
                            DataCell(_accessBadge(item['isPremium'] == true)),
                            DataCell(_statusAction(item)),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Riwayat revisi',
                                    icon: const Icon(
                                      Icons.history_outlined,
                                      size: 19,
                                    ),
                                    color: const Color(0xff63758d),
                                    onPressed: () =>
                                        _showArticleRevisions(item),
                                  ),
                                  if (_articleWorkflowActions(item).isNotEmpty)
                                    PopupMenuButton<String>(
                                      tooltip: 'Workflow artikel',
                                      onSelected: (action) =>
                                          _handleArticleWorkflowAction(
                                            item,
                                            action,
                                          ),
                                      itemBuilder: (_) =>
                                          _articleWorkflowActions(item)
                                              .map(
                                                (entry) =>
                                                    PopupMenuItem<String>(
                                                      value: entry.$1,
                                                      child: Text(entry.$2),
                                                    ),
                                              )
                                              .toList(),
                                    ),
                                  IconButton(
                                    tooltip: 'Detail artikel',
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 19,
                                    ),
                                    color: const Color(0xff2d6db5),
                                    onPressed: () => _showArticleDetail(item),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit artikel',
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 19,
                                    ),
                                    color: const Color(0xffc47a20),
                                    onPressed: () => _editArticle(item),
                                  ),
                                  IconButton(
                                    tooltip: 'Hapus artikel',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 19,
                                    ),
                                    color: const Color(0xffc43b45),
                                    onPressed: () => _confirmDelete(item),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _articleFilter(String label, bool selected, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? const Color(0xffeaf1fc) : Colors.white,
          foregroundColor: selected
              ? const Color(0xff1d5faf)
              : const Color(0xff65748b),
          side: BorderSide(
            color: selected ? const Color(0xff4c83d4) : const Color(0xffdbe2ec),
          ),
        ),
        child: Text(label),
      );

  Widget _accessBadge(bool premium) => _badge(
    premium ? 'Premium' : 'Gratis',
    premium ? const Color(0xff7851c9) : const Color(0xff3970b9),
  );

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'published' => ('Terbit', const Color(0xff2c9b61)),
      'review' => ('Review', const Color(0xffe38b29)),
      'ready' => ('Siap terbit', const Color(0xff3970b9)),
      'scheduled' => ('Terjadwal', const Color(0xff7851c9)),
      'rejected' => ('Ditolak', const Color(0xffc43b45)),
      'archived' => ('Arsip', const Color(0xff68778c)),
      _ => ('Draft', const Color(0xffe38b29)),
    };
    return _badge(label, color);
  }

  Widget _statusAction(Map<String, dynamic> item) {
    return _statusBadge(item['status']?.toString() ?? 'draft');
  }

  List<(String, String)> _articleWorkflowActions(Map<String, dynamic> article) {
    final status = article['status']?.toString() ?? 'draft';
    if (role == 'Author' && {'draft', 'rejected'}.contains(status)) {
      return [('submit-review', 'Kirim untuk review')];
    }
    if (role != 'Author') {
      return switch (status) {
        'review' => [
          ('approve', 'Setujui untuk diterbitkan'),
          ('reject', 'Tolak dengan catatan'),
        ],
        'ready' => [
          ('publish', 'Terbitkan sekarang'),
          ('schedule', 'Jadwalkan terbit'),
        ],
        'published' => [('archive', 'Arsipkan')],
        _ => const [],
      };
    }
    return const [];
  }

  Future<void> _handleArticleWorkflowAction(
    Map<String, dynamic> article,
    String action,
  ) async {
    final id = article['id']?.toString() ?? '';
    try {
      switch (action) {
        case 'submit-review':
          await api.submitArticleForReview(id);
        case 'approve':
          await api.approveArticle(id);
        case 'reject':
          final note = TextEditingController();
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Tolak artikel'),
              content: TextField(
                controller: note,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Catatan untuk penulis *',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('BATAL'),
                ),
                FilledButton(
                  onPressed: () {
                    if (note.text.trim().isEmpty) {
                      _toast('Catatan penolakan wajib diisi.');
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('TOLAK'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await api.rejectArticle(id, note: note.text.trim());
          } else {
            note.dispose();
            return;
          }
          note.dispose();
        case 'publish':
          await api.publishArticle(id);
        case 'schedule':
          final now = DateTime.now();
          final date = await showDatePicker(
            context: context,
            initialDate: now.add(const Duration(days: 1)),
            firstDate: now,
            lastDate: DateTime(now.year + 5),
          );
          if (date == null || !mounted) return;
          final time = await showTimePicker(
            context: context,
            initialTime: const TimeOfDay(hour: 9, minute: 0),
          );
          if (time == null) return;
          final scheduledAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          if (!scheduledAt.isAfter(DateTime.now())) {
            _toast('Waktu publikasi harus berada di masa mendatang.');
            return;
          }
          await api.scheduleArticle(id, scheduledAt);
        case 'archive':
          await api.archiveArticle(id);
      }
      await _loadArticles(force: true);
      await _loadDashboard();
      if (!mounted) return;
      _toast(switch (action) {
        'submit-review' => 'Artikel dikirim ke antrean review.',
        'approve' => 'Artikel siap diterbitkan.',
        'reject' => 'Artikel ditolak dan catatan dikirim ke penulis.',
        'publish' => 'Artikel berhasil diterbitkan.',
        'schedule' => 'Jadwal publikasi berhasil disimpan.',
        'archive' => 'Artikel berhasil diarsipkan.',
        _ => 'Workflow artikel diperbarui.',
      });
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _showArticleRevisions(Map<String, dynamic> article) async {
    try {
      final revisions = await api.articleRevisions(
        article['id']?.toString() ?? '',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Riwayat revisi artikel'),
          content: SizedBox(
            width: 520,
            child: revisions.isEmpty
                ? const Text('Belum ada riwayat revisi.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: revisions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final revision = revisions[index];
                      final snapshot = revision['snapshot'] is Map
                          ? revision['snapshot'] as Map
                          : const {};
                      final createdAt = DateTime.tryParse(
                        revision['createdAt']?.toString() ?? '',
                      )?.toLocal();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          snapshot['title']?.toString() ??
                              article['title']?.toString() ??
                              'Artikel',
                        ),
                        subtitle: Text(
                          '${revision['status'] ?? 'draft'} • '
                          '${revision['actor'] ?? '-'}\n'
                          '${revision['note'] ?? ''}',
                        ),
                        trailing: Text(
                          createdAt == null
                              ? '-'
                              : '${createdAt.day.toString().padLeft(2, '0')}/'
                                    '${createdAt.month.toString().padLeft(2, '0')}/'
                                    '${createdAt.year}\n'
                                    '${createdAt.hour.toString().padLeft(2, '0')}:'
                                    '${createdAt.minute.toString().padLeft(2, '0')}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('TUTUP'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  void _showArticleDetail(Map<String, dynamic> article) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xfff7f9fc),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ARTIKEL  /  DETAIL',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            article['title']?.toString() ?? 'Detail artikel',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: const Color(0xff14233b),
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup detail',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusBadge(article['status']?.toString() ?? 'draft'),
                    _accessBadge(article['isPremium'] == true),
                    _badge(
                      article['category']?.toString() ?? '-',
                      const Color(0xff2d6db5),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xffe1e7f0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ringkasan',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        article['excerpt']?.toString() ?? '-',
                        style: const TextStyle(
                          color: Color(0xff667386),
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Divider(height: 28),
                      Text(
                        'Isi artikel',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        article['body']?.toString() ??
                            'Isi artikel belum tersedia.',
                        style: const TextStyle(fontSize: 15, height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _articleMeta(
                      Icons.person_outline,
                      'Penulis',
                      article['author']?.toString() ?? '-',
                    ),
                    const SizedBox(width: 24),
                    _articleMeta(
                      Icons.schedule_outlined,
                      'Diperbarui',
                      article['updatedAt']?.toString().split('T').first ?? '-',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _articleMeta(IconData icon, String label, String value) => Expanded(
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _confirmDelete(Map<String, dynamic> article) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus artikel?'),
        content: Text(
          'Artikel "${article['title']}" akan dihapus dari CMS dan tidak dapat dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffc43b45),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.deleteArticle(article['id'].toString());
      await _loadArticles(force: true);
      await _loadDashboard();
      _toast('Artikel berhasil dihapus.');
    } catch (e) {
      _toast(e.toString());
    }
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );

  Widget _subscriptionTable() => FutureBuilder<void>(
    future: plans.isEmpty ? _loadPlans() : null,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting || loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final query = subscriptionSearch.trim().toLowerCase();
      final visiblePlans = plans.where((plan) {
        if (query.isEmpty) return true;
        return '${plan['name']} ${plan['id']} ${plan['benefits']}'
            .toLowerCase()
            .contains(query);
      }).toList();
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paket Langganan',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${plans.length} paket aktif untuk pelanggan',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (role == 'Super Admin')
                    FilledButton.icon(
                      onPressed: () => _showSubscriptionPlanForm(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Tambah paket'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xffe4e9f1)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 300,
                            child: TextField(
                              onChanged: (value) =>
                                  setState(() => subscriptionSearch = value),
                              decoration: InputDecoration(
                                hintText: 'Cari paket langganan...',
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  size: 19,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xfff6f8fb),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: _loadPlans,
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: const Text('Muat ulang'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (visiblePlans.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            plans.isEmpty
                                ? 'Belum ada paket langganan.'
                                : 'Paket tidak ditemukan.',
                          ),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 42,
                          dataRowMinHeight: 62,
                          dataRowMaxHeight: 70,
                          columnSpacing: 28,
                          headingTextStyle: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                          columns: const [
                            DataColumn(label: Text('PAKET')),
                            DataColumn(label: Text('DURASI')),
                            DataColumn(label: Text('NOMINAL')),
                            DataColumn(label: Text('BENEFIT')),
                            DataColumn(label: Text('AKSI')),
                          ],
                          rows: visiblePlans.map((plan) {
                            final benefits =
                                (plan['benefits'] as List? ?? const [])
                                    .map((item) => item.toString())
                                    .toList();
                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 190,
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 17,
                                          backgroundColor: Color(0xffeaf1fc),
                                          child: Icon(
                                            Icons.card_membership_outlined,
                                            color: AppColors.navy,
                                            size: 19,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                plan['name']?.toString() ?? '-',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                plan['id']?.toString() ?? '-',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  _subscriptionInfo(
                                    '${plan['durationDays'] ?? 0} hari',
                                    Icons.schedule_outlined,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    formatRupiah(
                                      (plan['price'] as num?)?.round() ?? 0,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 250,
                                    child: Text(
                                      benefits.isEmpty
                                          ? 'Belum ada benefit'
                                          : benefits.join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit paket',
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 19,
                                        ),
                                        color: const Color(0xffc47a20),
                                        onPressed: role == 'Super Admin'
                                            ? () => _showSubscriptionPlanForm(
                                                plan: plan,
                                              )
                                            : null,
                                      ),
                                      if (role == 'Super Admin')
                                        IconButton(
                                          tooltip: 'Hapus paket',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                          ),
                                          color: const Color(0xffc43b45),
                                          onPressed: () =>
                                              _deleteSubscriptionPlan(plan),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _subscriptionInfo(String label, IconData icon) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: 6),
      Text(label),
    ],
  );

  Future<void> _showSubscriptionPlanForm({Map<String, dynamic>? plan}) async {
    if (role != 'Super Admin') return;
    final editing = plan != null;
    final id = TextEditingController(text: plan?['id']?.toString() ?? '');
    final name = TextEditingController(text: plan?['name']?.toString() ?? '');
    final duration = TextEditingController(
      text: plan?['durationDays']?.toString() ?? '',
    );
    final price = TextEditingController(text: plan?['price']?.toString() ?? '');
    final benefits = TextEditingController(
      text: (plan?['benefits'] as List? ?? const []).join(', '),
    );
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            editing ? 'Edit paket langganan' : 'Tambah paket langganan',
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: id,
                    readOnly: editing,
                    decoration: const InputDecoration(
                      labelText: 'ID paket',
                      hintText: 'premium_1_month',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nama paket',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: duration,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Durasi (hari)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Harga',
                            prefixText: 'Rp ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: benefits,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Benefit (pisahkan dengan koma)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('BATAL'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final durationValue = int.tryParse(duration.text);
                      final priceValue = int.tryParse(price.text);
                      if (id.text.trim().isEmpty ||
                          name.text.trim().isEmpty ||
                          durationValue == null ||
                          durationValue <= 0 ||
                          priceValue == null ||
                          priceValue <= 0) {
                        _toast('Lengkapi nama, durasi, dan harga paket.');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final benefitValues = benefits.text
                            .split(',')
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList();
                        if (editing) {
                          await api.updateSubscriptionPlan(
                            id: id.text.trim(),
                            name: name.text.trim(),
                            durationDays: durationValue,
                            price: priceValue,
                            benefits: benefitValues,
                          );
                        } else {
                          await api.createSubscriptionPlan(
                            id: id.text.trim(),
                            name: name.text.trim(),
                            durationDays: durationValue,
                            price: priceValue,
                            benefits: benefitValues,
                          );
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _loadPlans();
                        if (mounted) _toast('Paket berhasil disimpan.');
                      } catch (exception) {
                        setDialogState(() => saving = false);
                        if (mounted) _toast(exception.toString());
                      }
                    },
              child: Text(editing ? 'SIMPAN PERUBAHAN' : 'TAMBAH PAKET'),
            ),
          ],
        ),
      ),
    );
    id.dispose();
    name.dispose();
    duration.dispose();
    price.dispose();
    benefits.dispose();
  }

  Future<void> _deleteSubscriptionPlan(Map<String, dynamic> plan) async {
    if (role != 'Super Admin') return;
    final id = plan['id']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus paket?'),
        content: Text('Paket ${plan['name'] ?? id} akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.deleteSubscriptionPlan(id);
      await _loadPlans();
      if (mounted) _toast('Paket berhasil dihapus.');
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _loginAdmin() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      challenge = await api.login(email.text, password.text);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _registerAdmin() async {
    if (email.text.trim().isEmpty || password.text.length < 8) {
      setState(
        () => error = 'Email wajib diisi dan kata sandi minimal 8 karakter.',
      );
      return;
    }
    if (password.text != confirmPassword.text) {
      setState(() => error = 'Konfirmasi kata sandi belum sama.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await api.registerAdmin(
        email: email.text.trim(),
        password: password.text,
        role: registrationRole,
      );
      if (!mounted) return;
      setState(() {
        registerMode = false;
        error = null;
      });
      _toast('Akun admin berhasil dibuat. Silakan masuk.');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _verifyAdmin() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      role = await api.verify(challenge!, code.text);
      section = 'Dashboard';
      await _loadArticles();
      await _loadDashboard();
      await _loadNotifications();
      if (role == 'Super Admin' || role == 'Editor') {
        await _loadCategories();
      }
      if (role == 'Super Admin') await _loadPlans();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadArticles({bool force = false}) {
    if (api.accessToken == null) {
      if (mounted) {
        setState(() {
          articlesLoaded = true;
          articlesLoadError = 'Sesi admin berakhir. Silakan masuk kembali.';
        });
      }
      return Future<void>.value();
    }
    final activeRequest = articlesLoadFuture;
    if (activeRequest != null) return activeRequest;
    if (articlesLoaded && !force) return Future<void>.value();
    if (mounted) {
      setState(() {
        articlesLoaded = false;
        articlesLoadError = null;
        articlesLoading = true;
      });
    }
    final request = _fetchArticles();
    articlesLoadFuture = request;
    return request;
  }

  Future<void> _fetchArticles() async {
    final generation = articlesLoadGeneration;
    try {
      final values = await api.adminArticles();
      if (mounted && generation == articlesLoadGeneration) {
        setState(() {
          articles = values;
          articlesLoaded = true;
          articlesLoadError = null;
        });
      }
    } catch (e) {
      if (mounted && generation == articlesLoadGeneration) {
        setState(() {
          articlesLoaded = true;
          articlesLoadError = e.toString();
        });
      }
    } finally {
      if (mounted && generation == articlesLoadGeneration) {
        setState(() => articlesLoading = false);
      }
      if (generation == articlesLoadGeneration) articlesLoadFuture = null;
    }
  }

  Future<void> _loadDashboard() async {
    if (api.accessToken == null) return;
    try {
      final value = await api.dashboard();
      if (mounted) setState(() => dashboard = value);
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _loadCategories() async {
    if (api.accessToken == null) return;
    try {
      final values = await api.categories();
      if (mounted) setState(() => categories = values);
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _loadAdminCategories() async {
    if (api.accessToken == null) return;
    try {
      final values = await api.adminCategories();
      if (mounted) {
        setState(() {
          adminCategories = values;
          categories = values;
        });
      }
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _loadPlans() async {
    if (api.accessToken == null) return;
    try {
      final values = await api.subscriptionPlans();
      if (mounted) setState(() => plans = values);
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _loadPayments() async {
    if (api.accessToken == null) return;
    try {
      final values = await api.payments();
      if (mounted) setState(() => payments = values);
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _confirmPayment(Map<String, dynamic> invoice) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi pembayaran'),
        content: const Text(
          'Pastikan dana sudah diterima sebelum mengaktifkan langganan pelanggan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DANA DITERIMA'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await api.confirmPayment(invoice['id'].toString());
      await _loadPayments();
      if (mounted) _toast('Pembayaran dikonfirmasi dan langganan diaktifkan.');
    } catch (exception) {
      if (mounted) _toast(exception.toString());
    }
  }

  Future<void> _loadEpapers() async {
    if (api.accessToken == null) return;
    try {
      final values = await api.adminEpapers();
      if (mounted) setState(() => epapers = values);
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  Future<void> _editEpaper(Map<String, dynamic>? issue) async {
    final originalPdfName = issue?['privateFileName']?.toString();
    selectedEpaperPdfName = issue?['privateFileName']?.toString();
    selectedEpaperPrivateFileName = issue?['privateFileName']?.toString();
    final title = TextEditingController(
      text: issue?['title']?.toString() ?? 'MAGELANG EKSPRES',
    );
    final edition = TextEditingController(text: issue?['edition']?.toString());
    final date = TextEditingController(
      text: issue?['date']?.toString() ?? '30/06/2026',
    );
    final pages = TextEditingController(text: '${issue?['totalPages'] ?? 8}');
    var downloadAllowed = issue?['downloadAllowed'] == true;
    final action = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xfff7f9fc),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          contentPadding: EdgeInsets.zero,
          titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'E-Paper  ›  ${issue == null ? 'Tambah E-Paper' : 'Edit E-Paper'}',
                style: const TextStyle(fontSize: 11, color: Color(0xff718096)),
              ),
              const SizedBox(height: 7),
              const Text(
                'Upload E-Paper',
                style: TextStyle(
                  color: Color(0xff14233b),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 980,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final uploadPanel = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editorLabel('Tanggal Edisi *'),
                      TextField(
                        controller: date,
                        decoration: _editorDecoration('30/06/2026').copyWith(
                          suffixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _editorLabel('File E-Paper (PDF) *'),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xfff7f9fc),
                          border: Border.all(color: const Color(0xffd9e1ec)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_outlined,
                              color: Color(0xffc43b45),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedEpaperPdfName ??
                                    (issue == null
                                        ? 'Belum ada file PDF dipilih'
                                        : 'PDF edisi tersimpan'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Pilih PDF',
                              icon: const Icon(Icons.upload_file_outlined),
                              onPressed: () async {
                                try {
                                  final result = await FilePicker.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: const ['pdf'],
                                    dialogTitle: 'Pilih PDF e-paper',
                                  );
                                  if (result.isEmpty) return;
                                  final file = result.first;
                                  final bytes = await file.readAsBytes();
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() => loading = true);
                                  final uploaded = await api.uploadMedia(
                                    bytes: bytes,
                                    fileName: file.name,
                                    kind: 'pdf',
                                  );
                                  selectedEpaperPdfName = file.name;
                                  selectedEpaperPrivateFileName =
                                      uploaded['fileName']?.toString();
                                  if (dialogContext.mounted) {
                                    setDialogState(() => loading = false);
                                  }
                                  if (mounted) {
                                    _toast(
                                      'PDF berhasil diunggah ke penyimpanan privat.',
                                    );
                                  }
                                } catch (exception) {
                                  if (dialogContext.mounted) {
                                    setDialogState(() => loading = false);
                                  }
                                  if (mounted) _toast(exception.toString());
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _editorLabel('Jumlah Halaman'),
                      TextField(
                        controller: pages,
                        keyboardType: TextInputType.number,
                        decoration: _editorDecoration('8 halaman'),
                      ),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Izinkan Unduh untuk Pelanggan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        value: downloadAllowed,
                        onChanged: (value) =>
                            setDialogState(() => downloadAllowed = value),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: selectedEpaperPrivateFileName == null
                              ? null
                              : () => _toast(
                                  'PDF siap disimpan bersama metadata edisi.',
                                ),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('UNGGAH E-PAPER'),
                        ),
                      ),
                    ],
                  );
                  final managementPanel = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editorLabel('Judul Edisi *'),
                      TextField(
                        controller: title,
                        decoration: _editorDecoration('MAGELANG EKSPRES'),
                      ),
                      const SizedBox(height: 16),
                      _editorLabel('Nama Edisi *'),
                      TextField(
                        controller: edition,
                        decoration: _editorDecoration('Edisi 30 Juni 2026'),
                      ),
                      const SizedBox(height: 18),
                      _editorLabel('Paket Langganan'),
                      _managementPlanPreview(),
                      const SizedBox(height: 16),
                      _editorLabel('Pelanggan Terbaru'),
                      _customerPreview(),
                    ],
                  );
                  return constraints.maxWidth >= 760
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: uploadPanel),
                            const SizedBox(width: 24),
                            Expanded(flex: 2, child: managementPanel),
                          ],
                        )
                      : Column(
                          children: [
                            uploadPanel,
                            const SizedBox(height: 24),
                            managementPanel,
                          ],
                        );
                },
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(28, 12, 28, 22),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('BATAL'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'draft'),
              child: const Text('SIMPAN DRAFT'),
            ),
            if (role != 'Author')
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'publish'),
                child: const Text('TERBITKAN'),
              ),
          ],
        ),
      ),
    );
    if (action == null) {
      title.dispose();
      edition.dispose();
      date.dispose();
      pages.dispose();
      selectedEpaperPdfName = null;
      selectedEpaperPrivateFileName = null;
      return;
    }
    final totalPages = int.tryParse(pages.text) ?? 0;
    final missingPdf =
        action == 'publish' && selectedEpaperPrivateFileName == null;
    if (title.text.trim().isEmpty ||
        edition.text.trim().isEmpty ||
        date.text.trim().isEmpty ||
        totalPages <= 0 ||
        missingPdf) {
      _toast(
        missingPdf
            ? 'Pilih dan unggah PDF sebelum menerbitkan e-paper.'
            : 'Judul, edisi, tanggal, dan jumlah halaman wajib diisi.',
      );
    } else {
      try {
        String? id = issue?['id']?.toString();
        if (issue == null) {
          final created = await api.createEpaper(
            title: title.text.trim(),
            edition: edition.text.trim(),
            date: date.text.trim(),
            totalPages: totalPages,
            downloadAllowed: downloadAllowed,
            privateFileName: selectedEpaperPrivateFileName,
          );
          id = created['id']?.toString();
        } else {
          await api.updateEpaper(
            issue['id'].toString(),
            title: title.text.trim(),
            edition: edition.text.trim(),
            date: date.text.trim(),
            totalPages: totalPages,
            downloadAllowed: downloadAllowed,
            privateFileName: selectedEpaperPrivateFileName,
          );
        }
        if (action == 'publish' && id != null) await api.publishEpaper(id);
        if (originalPdfName != null &&
            originalPdfName != selectedEpaperPrivateFileName) {
          await api.deleteMedia(originalPdfName);
        }
        await _loadEpapers();
        _toast(
          action == 'publish'
              ? 'E-paper berhasil diterbitkan.'
              : 'Draft e-paper tersimpan.',
        );
      } catch (e) {
        _toast(e.toString());
      }
    }
    title.dispose();
    edition.dispose();
    date.dispose();
    pages.dispose();
    selectedEpaperPdfName = null;
    selectedEpaperPrivateFileName = null;
  }

  void _showEpaperDetail(Map<String, dynamic> issue) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(issue['edition']?.toString() ?? 'Detail E-Paper'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusBadge(issue['status']?.toString() ?? 'draft'),
            const SizedBox(height: 14),
            Text('Tanggal terbit: ${issue['date'] ?? '-'}'),
            Text('Jumlah halaman: ${issue['totalPages'] ?? 0}'),
            Text(
              'Akses unduh: ${issue['downloadAllowed'] == true ? 'Pelanggan' : 'Preview'}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('TUTUP'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteEpaper(Map<String, dynamic> issue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus e-paper?'),
        content: Text(
          'Edisi "${issue['edition'] ?? issue['title']}" akan dihapus dari CMS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffc43b45),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.deleteEpaper(issue['id'].toString());
      await _loadEpapers();
      _toast('E-paper berhasil dihapus.');
    } catch (e) {
      _toast(e.toString());
    }
  }

  Widget _managementPlanPreview() => Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffd9e1ec)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Column(
      children: [
        ListTile(
          dense: true,
          title: Text(
            'Premium 1 Bulan',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          subtitle: Text('30 hari', style: TextStyle(fontSize: 10)),
          trailing: Text('Rp49.000', style: TextStyle(fontSize: 10)),
        ),
        Divider(height: 1),
        ListTile(
          dense: true,
          title: Text(
            'Premium 1 Tahun',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          subtitle: Text('365 hari', style: TextStyle(fontSize: 10)),
          trailing: Text('Rp499.000', style: TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );

  Widget _customerPreview() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff7f9fc),
      border: Border.all(color: const Color(0xffd9e1ec)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Column(
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 14,
            child: Icon(Icons.person, size: 15),
          ),
          title: Text(
            'Pelanggan aktif',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'Status subscription tersinkron',
            style: TextStyle(fontSize: 10),
          ),
          trailing: Icon(Icons.chevron_right, size: 18),
        ),
      ],
    ),
  );

  Future<void> _newCategory() async {
    final name = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah Kategori'),
        content: TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama kategori *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('BATAL'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                _toast('Nama kategori wajib diisi.');
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
    if (result == true) {
      try {
        await api.createCategory(name.text.trim());
        await _loadAdminCategories();
        _toast('Kategori berhasil ditambahkan.');
      } catch (e) {
        _toast(e.toString());
      }
    }
    name.dispose();
  }

  Future<void> _deleteCategory(String slug) async {
    try {
      await api.deleteCategory(slug);
      await _loadAdminCategories();
      _toast('Kategori berhasil dihapus.');
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _newArticle() => _editArticle(null);

  Future<void> _editArticle(Map<String, dynamic>? article) async {
    final title = TextEditingController(text: article?['title']?.toString());
    final excerpt = TextEditingController(
      text: article?['excerpt']?.toString(),
    );
    final body = TextEditingController(text: article?['body']?.toString());
    final imageUrl = TextEditingController(
      text: article?['mainImageUrl']?.toString(),
    );
    final blurredImageUrl = TextEditingController(
      text: article?['mainImageBlurUrl']?.toString(),
    );
    final imageAltText = TextEditingController(
      text: article?['mainImageAltText']?.toString(),
    );
    final slug = TextEditingController(
      text: article?['slug']?.toString().trim().isNotEmpty == true
          ? article!['slug'].toString()
          : _suggestedArticleSlug(article?['title']?.toString() ?? ''),
    );
    final seoTitle = TextEditingController(
      text: article?['seoTitle']?.toString(),
    );
    final seoDescription = TextEditingController(
      text: article?['seoDescription']?.toString(),
    );
    final existingSocialLinks = article?['socialLinks'] is Map
        ? (article!['socialLinks'] as Map).map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : <String, String>{};
    final youtubeUrl = TextEditingController(
      text: existingSocialLinks['YouTube'],
    );
    final instagramUrl = TextEditingController(
      text: existingSocialLinks['Instagram'],
    );
    final tiktokUrl = TextEditingController(
      text: existingSocialLinks['TikTok'],
    );
    final facebookUrl = TextEditingController(
      text: existingSocialLinks['Facebook'],
    );
    final websiteUrl = TextEditingController(
      text: existingSocialLinks['Website'],
    );
    Map<String, String> socialLinks() => {
      if (youtubeUrl.text.trim().isNotEmpty) 'YouTube': youtubeUrl.text.trim(),
      if (instagramUrl.text.trim().isNotEmpty)
        'Instagram': instagramUrl.text.trim(),
      if (tiktokUrl.text.trim().isNotEmpty) 'TikTok': tiktokUrl.text.trim(),
      if (facebookUrl.text.trim().isNotEmpty)
        'Facebook': facebookUrl.text.trim(),
      if (websiteUrl.text.trim().isNotEmpty) 'Website': websiteUrl.text.trim(),
    };
    var slugManuallyEdited = article?['slug']?.toString().isNotEmpty == true;
    var selectedCategory =
        article?['category']?.toString() ??
        (categories.isNotEmpty
            ? categories.first['name'].toString()
            : 'BERITA UTAMA');
    var premium = article?['isPremium'] == true;
    final action = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          contentPadding: EdgeInsets.zero,
          titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Artikel  ›  ${article == null ? 'Tambah Artikel' : 'Edit Artikel'}',
                style: const TextStyle(fontSize: 11, color: Color(0xff718096)),
              ),
              const SizedBox(height: 7),
              Text(
                article == null ? 'Editor Artikel' : 'Edit Artikel',
                style: const TextStyle(
                  color: Color(0xff14233b),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 980,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final left = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editorLabel('Judul Artikel *'),
                      TextField(
                        controller: title,
                        maxLength: 120,
                        decoration: _editorDecoration('Masukkan judul artikel'),
                        onChanged: (value) {
                          if (!slugManuallyEdited) {
                            slug.text = _suggestedArticleSlug(value);
                          }
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 14),
                      _editorLabel('Kategori *'),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        decoration: _editorDecoration('Pilih kategori'),
                        items:
                            (categories.isEmpty
                                    ? [
                                        {'name': 'BERITA UTAMA'},
                                      ]
                                    : categories)
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item['name'].toString(),
                                    child: Text(item['name'].toString()),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => setDialogState(
                          () => selectedCategory = value ?? selectedCategory,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _editorLabel('Akses Konten'),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Premium')),
                          ButtonSegment(value: false, label: Text('Gratis')),
                        ],
                        selected: {premium},
                        onSelectionChanged: (value) =>
                            setDialogState(() => premium = value.first),
                      ),
                      const SizedBox(height: 18),
                      _editorLabel('Foto Artikel'),
                      TextField(
                        controller: imageUrl,
                        decoration: _editorDecoration('URL foto utama'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 8),
                      _editorLabel('Alt Text Foto'),
                      TextField(
                        controller: imageAltText,
                        maxLength: 180,
                        decoration: _editorDecoration(
                          'Deskripsi singkat untuk aksesibilitas',
                        ),
                      ),
                      if (premium) ...[
                        const SizedBox(height: 8),
                        _editorLabel('Foto Blur untuk Guest Premium'),
                        TextField(
                          controller: blurredImageUrl,
                          decoration: _editorDecoration('URL thumbnail blur'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _mediaPreview(
                        imageUrl.text,
                        const Icon(Icons.image_outlined, size: 42),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              try {
                                final result = await FilePicker.pickFiles(
                                  type: FileType.image,
                                  dialogTitle: 'Pilih foto artikel',
                                );
                                if (result.isEmpty) return;
                                final file = result.first;
                                final bytes = await file.readAsBytes();
                                if (!dialogContext.mounted) return;
                                setDialogState(() => loading = true);
                                final uploaded = await api.uploadMedia(
                                  bytes: bytes,
                                  fileName: file.name,
                                  kind: 'image',
                                );
                                imageUrl.text = uploaded['url'].toString();
                                if (dialogContext.mounted) {
                                  setDialogState(() => loading = false);
                                }
                              } catch (exception) {
                                if (dialogContext.mounted) {
                                  setDialogState(() => loading = false);
                                }
                                if (mounted) _toast(exception.toString());
                              }
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('PILIH FOTO'),
                          ),
                          OutlinedButton.icon(
                            onPressed: imageUrl.text.isEmpty
                                ? null
                                : () {
                                    imageUrl.clear();
                                    setDialogState(() {});
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('HAPUS FOTO'),
                          ),
                        ],
                      ),
                    ],
                  );
                  final right = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _editorLabel('Konten Artikel *'),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xffd9e1ec)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xfff7f9fc),
                                border: Border(
                                  bottom: BorderSide(color: Color(0xffd9e1ec)),
                                ),
                              ),
                              child: Row(
                                children: const [
                                  Text(
                                    'Paragraf',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  SizedBox(width: 18),
                                  Icon(Icons.format_bold, size: 17),
                                  SizedBox(width: 14),
                                  Icon(Icons.format_italic, size: 17),
                                  SizedBox(width: 14),
                                  Icon(Icons.format_underlined, size: 17),
                                  SizedBox(width: 14),
                                  Icon(Icons.format_align_left, size: 17),
                                  SizedBox(width: 14),
                                  Icon(Icons.format_list_bulleted, size: 17),
                                ],
                              ),
                            ),
                            TextField(
                              controller: body,
                              minLines: 11,
                              maxLines: 15,
                              decoration: const InputDecoration(
                                hintText: 'Tulis konten artikel di sini...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _editorLabel('Ringkasan Artikel *'),
                      TextField(
                        controller: excerpt,
                        maxLines: 3,
                        decoration: _editorDecoration(
                          'Tulis ringkasan singkat untuk kartu berita',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 18),
                      _editorLabel('Tautan Sosial untuk Pembaca'),
                      TextField(
                        controller: youtubeUrl,
                        keyboardType: TextInputType.url,
                        decoration: _editorDecoration(
                          'URL YouTube (https://...)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: instagramUrl,
                        keyboardType: TextInputType.url,
                        decoration: _editorDecoration(
                          'URL Instagram (https://...)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: tiktokUrl,
                        keyboardType: TextInputType.url,
                        decoration: _editorDecoration(
                          'URL TikTok (https://...)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: facebookUrl,
                        keyboardType: TextInputType.url,
                        decoration: _editorDecoration(
                          'URL Facebook (https://...)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: websiteUrl,
                        keyboardType: TextInputType.url,
                        decoration: _editorDecoration(
                          'URL situs lain (https://...)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tautan hanya ditampilkan setelah artikel premium terbuka. Gunakan alamat HTTPS.',
                        style: TextStyle(
                          color: Color(0xff667386),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Divider(),
                      const SizedBox(height: 10),
                      _editorLabel('SEO Pencarian & Google News'),
                      TextField(
                        controller: slug,
                        maxLength: 140,
                        decoration: _editorDecoration('slug-url-artikel').copyWith(
                          prefixText: '/berita/',
                          helperText:
                              'URL unik dan stabil; hanya huruf kecil, angka, dan tanda hubung.',
                        ),
                        onChanged: (_) {
                          slugManuallyEdited = true;
                          setDialogState(() {});
                        },
                      ),
                      TextField(
                        controller: seoTitle,
                        maxLength: 70,
                        decoration: _editorDecoration(
                          'Judul SEO • ${title.text.trim()} | Magelang Ekspres',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      TextField(
                        controller: seoDescription,
                        maxLength: 160,
                        minLines: 2,
                        maxLines: 3,
                        decoration: _editorDecoration(
                          'Deskripsi SEO • ${excerpt.text.trim()}',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xfff7f9fc),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xffd9e1ec)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pratinjau hasil pencarian',
                              style: TextStyle(
                                color: Color(0xff667386),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              seoTitle.text.trim().isEmpty
                                  ? '${title.text.trim()} | Magelang Ekspres'
                                  : seoTitle.text.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff176b38),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              seoDescription.text.trim().isEmpty
                                  ? excerpt.text.trim()
                                  : seoDescription.text.trim(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff4b5563),
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'magelangekspres.com/berita/${slug.text.trim().isEmpty ? _suggestedArticleSlug(title.text) : slug.text.trim()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff667386),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 24),
                            Expanded(flex: 2, child: right),
                          ],
                        )
                      : Column(
                          children: [left, const SizedBox(height: 22), right],
                        );
                },
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(28, 12, 28, 22),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('BATAL'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'preview'),
              child: const Text('TINJAU'),
            ),
            if (role == 'Author')
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext, 'submit_review'),
                child: const Text('KIRIM REVIEW'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'draft'),
              child: const Text('SIMPAN DRAFT'),
            ),
            if (role != 'Author' && article?['status'] == 'ready')
              FilledButton.icon(
                icon: const Icon(Icons.send, size: 16),
                onPressed: () => Navigator.pop(dialogContext, 'publish'),
                label: const Text('TERBITKAN'),
              ),
          ],
        ),
      ),
    );
    if (action == null) {
      title.dispose();
      excerpt.dispose();
      body.dispose();
      imageUrl.dispose();
      blurredImageUrl.dispose();
      imageAltText.dispose();
      slug.dispose();
      seoTitle.dispose();
      seoDescription.dispose();
      youtubeUrl.dispose();
      instagramUrl.dispose();
      tiktokUrl.dispose();
      facebookUrl.dispose();
      websiteUrl.dispose();
      return;
    }
    if (title.text.trim().isEmpty ||
        excerpt.text.trim().isEmpty ||
        body.text.trim().isEmpty) {
      _toast('Judul, ringkasan, dan isi wajib diisi.');
    } else if (action == 'preview') {
      _showArticlePreview(
        title.text.trim(),
        selectedCategory,
        excerpt.text.trim(),
        body.text.trim(),
        premium,
      );
    } else {
      try {
        String? createdId = article?['id']?.toString();
        if (article == null) {
          final created = await api.createArticle(
            title: title.text.trim(),
            category: selectedCategory,
            excerpt: excerpt.text.trim(),
            body: body.text.trim(),
            premium: premium,
            imageUrl: imageUrl.text.trim(),
            blurredImageUrl: blurredImageUrl.text.trim(),
            imageAltText: imageAltText.text.trim(),
            slug: slug.text.trim(),
            seoTitle: seoTitle.text.trim(),
            seoDescription: seoDescription.text.trim(),
            socialLinks: socialLinks(),
          );
          createdId = created['id']?.toString();
        } else {
          await api.updateArticle(
            article['id'].toString(),
            title: title.text.trim(),
            category: selectedCategory,
            excerpt: excerpt.text.trim(),
            body: body.text.trim(),
            premium: premium,
            imageUrl: imageUrl.text.trim(),
            blurredImageUrl: blurredImageUrl.text.trim(),
            imageAltText: imageAltText.text.trim(),
            slug: slug.text.trim(),
            seoTitle: seoTitle.text.trim(),
            seoDescription: seoDescription.text.trim(),
            socialLinks: socialLinks(),
          );
        }
        if (action == 'submit_review' && createdId != null) {
          await api.submitArticleForReview(createdId);
        }
        if (action == 'publish' && createdId != null) {
          await api.publishArticle(createdId);
        }
        await _loadArticles(force: true);
        _toast(switch (action) {
          'publish' => 'Artikel berhasil diterbitkan.',
          'submit_review' => 'Artikel dikirim ke antrean review.',
          _ => 'Draft tersimpan.',
        });
      } catch (e) {
        _toast(e.toString());
      }
    }
    title.dispose();
    excerpt.dispose();
    body.dispose();
    imageUrl.dispose();
    blurredImageUrl.dispose();
    imageAltText.dispose();
    slug.dispose();
    seoTitle.dispose();
    seoDescription.dispose();
    youtubeUrl.dispose();
    instagramUrl.dispose();
    tiktokUrl.dispose();
    facebookUrl.dispose();
    websiteUrl.dispose();
  }

  Widget _editorLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xff34445d),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  InputDecoration _editorDecoration(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    filled: true,
    fillColor: const Color(0xfff8fafc),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xffd9e1ec)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xffd9e1ec)),
    ),
  );

  void _showArticlePreview(
    String title,
    String category,
    String excerpt,
    String body,
    bool premium,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xffc8242f),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  excerpt,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Divider(height: 28),
                Text(body),
                if (premium) ...[
                  const SizedBox(height: 18),
                  _accessBadge(true),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('TUTUP'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _TrafficChartPainter extends CustomPainter {
  _TrafficChartPainter(this.data);

  final List<Map<String, dynamic>> data;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffe8edf4)
      ..strokeWidth = 1;
    for (var index = 1; index < 5; index++) {
      final y = size.height * index / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final visits = data
        .map((item) => (item['visits'] as num?)?.toDouble() ?? 0)
        .toList();
    final pointCount = visits.length.clamp(2, 7);
    final maxVisits = visits.fold<double>(
      1,
      (max, value) => value > max ? value : max,
    );
    final points = List.generate(pointCount, (index) {
      final value = index < visits.length ? visits[index] : 0;
      final x = size.width * index / (pointCount - 1);
      final y = size.height * (.12 + (1 - value / maxVisits) * .68);
      return Offset(x, y);
    });
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = const Color(0xff2b6fd6).withValues(alpha: .08),
    );
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      linePath.lineTo(points[index].dx, points[index].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xff2864c3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final marker = points.last;
    canvas.drawCircle(marker, 4, Paint()..color = const Color(0xff2864c3));
    canvas.drawCircle(marker, 2, Paint()..color = Colors.white);
    final labels = data.isEmpty
        ? const ['-', '-', '-', '-', '-', '-']
        : data.map((item) => item['date'].toString().substring(5)).toList();
    for (var index = 0; index < labels.length; index++) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: const TextStyle(fontSize: 9, color: Color(0xff8b97a8)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x =
          size.width * index / (labels.length - 1) - textPainter.width / 2;
      textPainter.paint(canvas, Offset(x, size.height - 15));
    }
  }

  @override
  bool shouldRepaint(covariant _TrafficChartPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _StatusChartPainter extends CustomPainter {
  const _StatusChartPainter(this.draft, this.review, this.published);

  final double draft;
  final double review;
  final double published;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final values = [draft, review, published];
    final colors = [
      const Color(0xff123e80),
      const Color(0xfff28c28),
      const Color(0xff2da663),
    ];
    var start = -1.5708;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] * 6.28318;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        Paint()
          ..color = colors[index]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20,
      );
      start += sweep;
    }
    canvas.drawCircle(center, radius - 11, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _StatusChartPainter oldDelegate) =>
      oldDelegate.draft != draft ||
      oldDelegate.review != review ||
      oldDelegate.published != published;
}

class _AccountSettingsView extends StatefulWidget {
  const _AccountSettingsView({
    super.key,
    required this.api,
    required this.onToast,
  });
  final AdminApiClient api;
  final void Function(String message) onToast;

  @override
  State<_AccountSettingsView> createState() => _AccountSettingsViewState();
}

class _AccountSettingsViewState extends State<_AccountSettingsView> {
  final email = TextEditingController();
  final emailPassword = TextEditingController();
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  String role = '';
  bool loading = true;
  bool savingEmail = false;
  bool savingPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    email.dispose();
    emailPassword.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final account = await widget.api.account();
      if (!mounted) return;
      setState(() {
        email.text = account['email']?.toString() ?? '';
        role = account['role']?.toString() ?? '';
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() => loading = false);
      widget.onToast(exception.toString());
    }
  }

  Future<void> _saveEmail() async {
    if (emailPassword.text.isEmpty) {
      widget.onToast('Masukkan kata sandi saat ini untuk mengubah email.');
      return;
    }
    setState(() => savingEmail = true);
    try {
      await widget.api.updateAccountEmail(
        email: email.text.trim(),
        currentPassword: emailPassword.text,
      );
      emailPassword.clear();
      widget.onToast('Email akun berhasil diperbarui.');
    } catch (exception) {
      widget.onToast(exception.toString());
    } finally {
      if (mounted) setState(() => savingEmail = false);
    }
  }

  Future<void> _savePassword() async {
    if (newPassword.text.length < 8) {
      widget.onToast('Kata sandi baru minimal 8 karakter.');
      return;
    }
    if (newPassword.text != confirmPassword.text) {
      widget.onToast('Konfirmasi kata sandi tidak sama.');
      return;
    }
    setState(() => savingPassword = true);
    try {
      await widget.api.changePassword(
        currentPassword: currentPassword.text,
        newPassword: newPassword.text,
      );
      currentPassword.clear();
      newPassword.clear();
      confirmPassword.clear();
      widget.onToast('Kata sandi berhasil diubah.');
    } catch (exception) {
      widget.onToast(exception.toString());
    } finally {
      if (mounted) setState(() => savingPassword = false);
    }
  }

  Widget _card(String title, String subtitle, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffe4e9f1)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xff14233b),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xff7d899d), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final displayRole = role == 'Editor' ? 'Admin' : role;
    return ColoredBox(
      color: const Color(0xfff4f7fb),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        children: [
          Text(
            'Pengaturan Akun',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xff14233b),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Role: $displayRole',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                _card('Email', 'Email digunakan untuk masuk ke CMS.', [
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration('Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailPassword,
                    obscureText: true,
                    decoration: _decoration('Kata sandi saat ini'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: savingEmail ? null : _saveEmail,
                    child: Text(savingEmail ? 'MENYIMPAN...' : 'SIMPAN EMAIL'),
                  ),
                ]),
                const SizedBox(height: 16),
                _card('Kata Sandi', 'Gunakan minimal 8 karakter.', [
                  TextField(
                    controller: currentPassword,
                    obscureText: true,
                    decoration: _decoration('Kata sandi saat ini'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: _decoration('Kata sandi baru'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPassword,
                    obscureText: true,
                    decoration: _decoration('Ulangi kata sandi baru'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: savingPassword ? null : _savePassword,
                    child: Text(
                      savingPassword ? 'MENYIMPAN...' : 'UBAH KATA SANDI',
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
