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
  Widget build(BuildContext context) => FutureBuilder<List<EpaperIssue>>(
    future: _issuesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('E-paper belum dapat dimuat.'));
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'E-PAPER KORAN DIGITAL',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Baca koran digital halaman demi halaman',
                          style: TextStyle(
                            color: Color(0xffa35a00),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (all.isNotEmpty)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const ValueKey('latest-published-issue'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openIssue(all.first),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Column(
                            children: [
                              Icon(Icons.event_note_outlined, size: 18),
                              Text(
                                'Edisi\nTerbit',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 14),
              if (access.hasError)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xffffeeee),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Status langganan belum dapat diverifikasi. Akses penuh dikunci sementara.',
                          style: TextStyle(
                            color: Color(0xff8b1e1e),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _accessFuture = _loadAccess();
                        }),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              if (!unlocked)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xfffff7c2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xfff5a800),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Akses E-Paper Terproteksi',
                              style: TextStyle(
                                color: Color(0xff8a4b00),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Aktifkan paket langganan untuk membaca dan mendownload semua halaman koran digital.',
                              style: TextStyle(
                                color: Color(0xff8a4b00),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: widget.onSubscribe,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff111111),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'Buka Akses',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              if (issues.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada edisi e-paper.')),
                ),
              for (final issue in issues) _issueCard(issue, unlocked),
            ],
          );
        },
      );
    },
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xff111111) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xff333333),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  Future<void> _openIssue(EpaperIssue issue) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          EpaperDetailScreen(repository: widget.repository, issueId: issue.id),
    ),
  );

  Widget _issueCard(EpaperIssue issue, bool unlocked) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('epaper-issue-${issue.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openIssue(issue),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xffeeeae2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  height: 128,
                  child: _cover(issue, unlocked),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue.edition,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
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
                          fontFamily: 'Inter',
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tanggal Terbit: ${issue.date} • ${issue.totalPages} Halaman',
                        style: const TextStyle(
                          color: Color(0xff77736d),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openIssue(issue),
                          icon: Icon(
                            unlocked ? Icons.menu_book : Icons.lock,
                            size: 14,
                          ),
                          label: const Text(
                            'Buka Koran',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xffcc6a00),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
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
      ),
    );
  }

  Widget _cover(EpaperIssue issue, bool unlocked) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (issue.coverImage?.isNotEmpty == true)
          _image(issue.coverImage!, BoxFit.cover)
        else
          const ColoredBox(color: Color(0xff222222)),
        if (!unlocked)
          Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xfff5a800),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.lock, size: 16, color: Colors.white),
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
}
