import 'package:flutter/material.dart';

import '../../models/epaper_model.dart';
import '../../repositories/epaper_repository.dart';
import '../../services/reader_api_client.dart';
import 'epaper_detail_screen.dart';

class EpaperListScreen extends StatefulWidget {
  const EpaperListScreen({
    super.key,
    required this.repository,
    this.readerClient,
    this.onSubscribe,
  });
  final EpaperRepository repository;
  final ReaderApiClient? readerClient;
  final VoidCallback? onSubscribe;

  @override
  State<EpaperListScreen> createState() => _EpaperListScreenState();
}

class _EpaperListScreenState extends State<EpaperListScreen> {
  late Future<List<EpaperIssue>> _issuesFuture;
  late Future<bool> _accessFuture;
  String? _date;

  @override
  void initState() {
    super.initState();
    _issuesFuture = widget.repository.getEpaperIssues();
    _accessFuture = _loadAccess();
  }

  Future<bool> _loadAccess() {
    final client = widget.readerClient;
    if (client == null || client.accessToken == null) {
      return Future.value(false);
    }
    return client.subscriptionStatus().then((status) {
      final active = status['active'] == true;
      widget.repository.setMockSubscriptionActive(active);
      return active;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfffffefa),
        body: SafeArea(
          child: FutureBuilder<List<EpaperIssue>>(
            future: _issuesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Column(
                  children: [
                    _buildHeader(),
                    _buildTabs(),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    _buildHeader(),
                    _buildTabs(),
                    const Expanded(
                      child: Center(
                        child: Text('E-paper belum dapat dimuat.'),
                      ),
                    ),
                  ],
                );
              }
              final all = snapshot.data ?? [];
              final dates = all.map((issue) => issue.date).toSet().toList();
              final issues = _date == null
                  ? all
                  : all.where((issue) => issue.date == _date).toList();
              return FutureBuilder<bool>(
                future: _accessFuture,
                builder: (context, access) {
                  final unlocked = access.data == true;
                  return Column(
                    children: [
                      _buildHeader(),
                      _buildTabs(),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          children: [
                            // ===== ARSIP HEADER =====
                            _buildArchiveHeader(),
                            const SizedBox(height: 16),

                            // ===== DATE FILTER =====
                            _buildDateFilter(dates),
                            const SizedBox(height: 16),

                            // ===== ACCESS ERROR =====
                            if (access.hasError) _buildAccessError(),

                            // ===== LOCKED BANNER =====
                            if (!unlocked) _buildLockedBanner(),

                            const SizedBox(height: 16),

                            // ===== EMPTY STATE =====
                            if (issues.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                  child: Text(
                                    'Belum ada edisi e-paper.',
                                    style: TextStyle(
                                      color: Color(0xff77736d),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),

                            // ===== ISSUE CARDS =====
                            for (final issue in issues)
                              _issueCard(issue, unlocked),

                            const SizedBox(height: 20),

                            // ===== DOWNLOAD PANEL =====
                            _buildDownloadPanel(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      );

  // ===== HEADER =====
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xff2563eb), Color(0xff7c3aed)],
              ),
              borderRadius: BorderRadius.circular(8),
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
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MAGELANG EKSPRES',
                  style: TextStyle(
                    color: Color(0xffb91c1c),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Akurat, Terpercaya, dan Menginspirasi',
                  style: TextStyle(
                    color: Color(0xff77736d),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            color: const Color(0xff272521),
            tooltip: 'Cari',
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // ===== TAB NAVIGASI =====
  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xfffffefa),
        border: Border(bottom: BorderSide(color: Color(0xffe8e4dd))),
      ),
      child: Row(
        children: [
          _tabItem('Beranda'),
          _tabItem('Lokal'),
          _tabItem('Terbaru'),
          _tabItem('E-Paper', active: true),
          _tabItem('Tersimpan'),
        ],
      ),
    );
  }

  Widget _tabItem(String label, {bool active = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xff272521) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xff77736d),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ===== ARSIP HEADER =====
  Widget _buildArchiveHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Arsip E-Paper Magelang Ekspres',
          style: TextStyle(
            color: Color(0xff272521),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Koleksi e-paper harian',
          style: TextStyle(
            color: Color(0xff77736d),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ===== DATE FILTER =====
  Widget _buildDateFilter(List<String> dates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pilih tanggal atau halaman',
          style: TextStyle(
            color: Color(0xff77736d),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip('Semua Tanggal', _date == null, () {
                setState(() => _date = null);
              }),
              for (final date in dates)
                _chip(date, _date == date, () {
                  setState(() => _date = date);
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xff272521) : const Color(0xfff5f3ee),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xffe8e4dd)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xff272521),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );

  // ===== ACCESS ERROR =====
  Widget _buildAccessError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffffeeee),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff8b1e1e).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Status langganan belum dapat diverifikasi. Akses penuh dikunci sementara.',
              style: TextStyle(
                color: Color(0xff8b1e1e),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _accessFuture = _loadAccess();
            }),
            child: const Text(
              'Coba lagi',
              style: TextStyle(
                color: Color(0xff8b1e1e),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== LOCKED BANNER =====
  Widget _buildLockedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff112b55), Color(0xff274d7d)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.workspace_premium,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akses E-Paper Terproteksi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Aktifkan paket langganan untuk membaca dan mendownload semua halaman koran digital.',
                  style: TextStyle(
                    color: Color(0xffffc0a0),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: widget.onSubscribe,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffd9b277),
              foregroundColor: const Color(0xff112b55),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Buka Akses',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== ISSUE CARD =====
  Widget _issueCard(EpaperIssue issue, bool unlocked) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('epaper-issue-${issue.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openIssue(issue),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffe8e4dd)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  height: 130,
                  child: _cover(issue, unlocked),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue.edition.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Color(0xffb91c1c),
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (issue.id == 'epaper-2026-08-13') ...[
                        const SizedBox(height: 4),
                        const Text(
                          'SOROTAN: KAMPUNG INOVATIF • HALAMAN 6',
                          style: TextStyle(
                            color: Color(0xff288040),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        issue.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w900,
                          color: Color(0xff272521),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tanggal Terbit: ${issue.date} • ${issue.totalPages} Halaman',
                        style: const TextStyle(
                          color: Color(0xff77736d),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _openIssue(issue),
                              icon: Icon(
                                unlocked ? Icons.menu_book : Icons.lock,
                                size: 14,
                              ),
                              label: const Text(
                                'Baca versi e-paper',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff272521),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _openIssue(issue),
                            icon: const Icon(Icons.grid_view, size: 14),
                            label: const Text(
                              'Grid',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              side: const BorderSide(color: Color(0xff272521)),
                              foregroundColor: const Color(0xff272521),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
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

  // ===== COVER IMAGE =====
  Widget _cover(EpaperIssue issue, bool unlocked) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (issue.coverImage?.isNotEmpty == true)
              _image(issue.coverImage!, BoxFit.cover)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff112b55), Color(0xff274d7d)],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'ME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            if (!unlocked)
              Container(
                color: Colors.black.withOpacity(0.4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xffd9b277),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock,
                      size: 18,
                      color: Color(0xff112b55),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _image(String source, BoxFit fit) => source.startsWith('assets/')
      ? Image.asset(
          source,
          fit: fit,
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black87),
        )
      : Image.network(
          source,
          fit: fit,
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black87),
        );

  // ===== DOWNLOAD PANEL =====
  Widget _buildDownloadPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff112b55), Color(0xff274d7d)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.download_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unduh E-Paper (PDF)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Terlindungi & Berwatermark',
                      style: TextStyle(
                        color: Color(0xffffc0a0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Unduh e-paper dalam format PDF berkualitas tinggi untuk dibaca kapan saja secara offline. Setiap e-paper dilindungi watermark dinamis berisi email dan waktu unduh untuk keamanan konten.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                // trigger download
              },
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text(
                'Unduh PDF',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffd9b277),
                foregroundColor: const Color(0xff112b55),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== NAVIGATION =====
  Future<void> _openIssue(EpaperIssue issue) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              EpaperDetailScreen(repository: widget.repository, issueId: issue.id),
        ),
      );
}