import 'dart:convert';
import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../widgets/species_art.dart';

const _cream = Color(0xFFF8F7EF);
const _green = Color(0xFF245D44);
const _ink = Color(0xFF213C30);
const _muted = Color(0xFF586B60);
const _pale = Color(0xFFE7EEDF);

/// Local collection only; missing weather or region is never inferred.
class DexScreen extends StatefulWidget {
  const DexScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<DexScreen> createState() => _DexScreenState();
}

class _DexScreenState extends State<DexScreen> {
  late Future<(List<Species>, List<DexEntry>)> _contents = _load();

  Future<(List<Species>, List<DexEntry>)> _load() async {
    final json = await rootBundle.loadString('assets/data/species.json');
    final species =
        SpeciesTable.fromJson(jsonDecode(json) as Map<String, dynamic>);
    return (species.all, await widget.controller.dex.all());
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _green, brightness: Brightness.light),
          scaffoldBackgroundColor: _cream,
          textTheme: Theme.of(context)
              .textTheme
              .apply(bodyColor: _ink, displayColor: _ink),
          appBarTheme: const AppBarTheme(
              backgroundColor: _cream, foregroundColor: _ink, elevation: 0),
        ),
        child: Builder(
            builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: const Text('도감'),
                    leading: IconButton(
                      tooltip: '돌아가기',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                          return;
                        }
                        widget.controller.prepareNextFakeTrip();
                        context.go('/pairing');
                      },
                    ),
                  ),
                  body: SafeArea(
                      top: false,
                      child: FutureBuilder<(List<Species>, List<DexEntry>)>(
                        future: _contents,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                                child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('도감을 불러오지 못했어요.'),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                            onPressed: () => setState(() {
                                                  _contents = _load();
                                                }),
                                            child: const Text('다시 시도'))
                                      ],
                                    )));
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final (species, entries) = snapshot.data!;
                          final owned = <String, List<DexEntry>>{};
                          for (final entry in entries) {
                            owned
                                .putIfAbsent(entry.speciesId, () => [])
                                .add(entry);
                          }
                          final count = species
                              .where((s) => owned.containsKey(s.id))
                              .length;
                          return LayoutBuilder(builder: (context, constraints) {
                            final scale =
                                MediaQuery.textScalerOf(context).scale(16) / 16;
                            final compact = constraints.maxHeight < 460 &&
                                constraints.maxWidth > constraints.maxHeight &&
                                scale <= 1.3;
                            final columns = math.max(
                                1,
                                (constraints.maxWidth /
                                        (160 + 45 * (scale - 1).clamp(0, 4)))
                                    .floor());
                            return CustomScrollView(slivers: [
                              SliverToBoxAdapter(
                                  child: Padding(
                                padding: EdgeInsets.fromLTRB(20,
                                    compact ? 8 : 12, 20, compact ? 12 : 24),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!compact) ...[
                                        const Text('ALLO · TRAVEL COLLECTION',
                                            style: TextStyle(
                                                color: _green,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.2)),
                                        const SizedBox(height: 8),
                                        Text('여행에서 만난 친구들',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w800)),
                                        const SizedBox(height: 8),
                                        Text('만난 친구 $count / ${species.length}',
                                            style:
                                                const TextStyle(color: _muted)),
                                      ],
                                      if (compact)
                                        Row(children: [
                                          Expanded(
                                              child: Text('여행에서 만난 친구들',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                          fontWeight: FontWeight
                                                              .w800))),
                                          const SizedBox(width: 12),
                                          Text(
                                              '만난 친구 $count / ${species.length}',
                                              style: const TextStyle(
                                                  color: _muted, fontSize: 13)),
                                        ]),
                                      SizedBox(height: compact ? 10 : 14),
                                      ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: species.isEmpty
                                                ? 0
                                                : count / species.length,
                                            minHeight: 6,
                                            color: _green,
                                            backgroundColor: _pale,
                                            semanticsLabel:
                                                '친구 수집 현황 $count / ${species.length}',
                                          )),
                                      if (!compact) ...[
                                        const SizedBox(height: 12),
                                        const Text(
                                            '만남의 순간을 모아 두었어요. 친구를 눌러 기록을 펼쳐 보세요.',
                                            style: TextStyle(color: _muted)),
                                      ],
                                    ]),
                              )),
                              SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: columns,
                                            mainAxisExtent: (compact
                                                    ? 180
                                                    : 220) +
                                                100 * (scale - 1).clamp(0, 6),
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12),
                                    delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                      final friend = species[index];
                                      final records = owned[friend.id] ??
                                          const <DexEntry>[];
                                      final collected = records.isNotEmpty;
                                      return Material(
                                        key: ValueKey('dex-${friend.id}'),
                                        color: collected
                                            ? Colors.white
                                            : const Color(0xFFF0F1E8),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            side: BorderSide(
                                                color: collected
                                                    ? const Color(0xFFD8E3D4)
                                                    : const Color(0xFFE0E3D9))),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                            onTap: () => _showDetails(context,
                                                friend, records, index + 1),
                                            child: Padding(
                                              padding: const EdgeInsets.all(14),
                                              child: Column(children: [
                                                Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Text(
                                                        'NO. ${(index + 1).toString().padLeft(3, '0')}',
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: _muted,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700))),
                                                const Spacer(),
                                                if (collected)
                                                  SpeciesArt(
                                                      species: friend,
                                                      size: compact ? 64 : 72)
                                                else
                                                  ExcludeSemantics(
                                                      child: ColorFiltered(
                                                          colorFilter:
                                                              const ColorFilter
                                                                  .mode(
                                                                  Color(
                                                                      0xFF9AA69A),
                                                                  BlendMode
                                                                      .srcIn),
                                                          child: SpeciesArt(
                                                              species: friend,
                                                              size: compact
                                                                  ? 64
                                                                  : 72))),
                                                const SizedBox(height: 10),
                                                Text(
                                                    collected
                                                        ? friend.nameKo
                                                        : '아직 만나지 못했어요',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                const SizedBox(height: 4),
                                                Text(
                                                    collected
                                                        ? '${records.length}번 만남'
                                                        : '눌러서 힌트 보기',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: _muted)),
                                                const Spacer(),
                                              ]),
                                            )),
                                      );
                                    }, childCount: species.length),
                                  )),
                            ]);
                          });
                        },
                      )),
                )),
      );

  void _showDetails(BuildContext context, Species species,
      List<DexEntry> entries, int number) {
    final records = List<DexEntry>.of(entries)
      ..sort((a, b) => b.obtainedAt.compareTo(a.obtainedAt));
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _cream,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 960),
        builder: (context) => _DexDetails(
            controller: widget.controller,
            species: species,
            records: records,
            number: number));
  }
}

class _DexDetails extends StatefulWidget {
  const _DexDetails(
      {required this.controller,
      required this.species,
      required this.records,
      required this.number});
  final GameController controller;
  final Species species;
  final List<DexEntry> records;
  final int number;
  @override
  State<_DexDetails> createState() => _DexDetailsState();
}

class _DexDetailsState extends State<_DexDetails> {
  String? _pending;
  String? _message;
  bool _failed = false;
  bool _retrying = false;

  Future<void> _retrySave() async {
    setState(() {
      _retrying = true;
      _message = null;
    });
    try {
      await widget.controller.fishing.retrySave();
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
        });
      }
    }
  }

  Future<void> _select(DexEntry record) async {
    setState(() {
      _pending = jsonEncode(record.toJson());
      _message = null;
    });
    final selected = await widget.controller.selectCarCompanion(record);
    if (!mounted) return;
    setState(() {
      _pending = null;
      _failed = !selected;
      _message = selected
          ? '이 친구를 차량 동행으로 선택했어요.'
          : widget.controller.error ?? '친구를 선택하지 못했어요. 연결 상태를 확인해 주세요.';
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) =>
                LayoutBuilder(builder: (context, constraints) {
                  final collected = widget.records.isNotEmpty;
                  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                  final portrait =
                      Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('NO. ${widget.number.toString().padLeft(3, '0')}',
                        style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2)),
                    const SizedBox(height: 16),
                    Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                            color: _pale, shape: BoxShape.circle),
                        child: collected
                            ? SpeciesArt(species: widget.species, size: 130)
                            : ExcludeSemantics(
                                child: ColorFiltered(
                                    colorFilter: const ColorFilter.mode(
                                        Color(0xFF9AA69A), BlendMode.srcIn),
                                    child: SpeciesArt(
                                        species: widget.species, size: 130)))),
                    const SizedBox(height: 20),
                    Text(collected ? widget.species.nameKo : '아직 만나지 못한 친구',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    if (collected) ...[
                      const SizedBox(height: 6),
                      Text(widget.species.nameEn,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted)),
                      const SizedBox(height: 12),
                      _badge('속성: ${_attribute(widget.species.attribute)}'),
                      const SizedBox(height: 12),
                      Text('총 ${widget.records.length}번 만났어요',
                          style: const TextStyle(color: _muted)),
                    ] else ...[
                      const SizedBox(height: 16),
                      Text(widget.species.hint, textAlign: TextAlign.center)
                    ],
                  ]);
                  final records = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('우리의 만남 기록',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text('각 만남의 친구를 차량 동행으로 선택할 수 있어요.',
                            style: TextStyle(color: _muted)),
                        if (!widget.controller.paired)
                          const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text('차량과 연결한 뒤 함께할 친구를 선택할 수 있어요.'))
                        else if (widget.controller.sessionEnded ||
                            widget.controller.endingSession)
                          const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text('차량 연결이 끝났어요. 다시 연결한 뒤 선택해 주세요.')),
                        if (_message != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Text(_message!,
                                      style: TextStyle(
                                          color: _failed
                                              ? const Color(0xFF9D302A)
                                              : _green)))),
                        if (widget.controller.fishing.error != null ||
                            widget.controller.fishing.hasPendingWrite) ...[
                          const SizedBox(height: 12),
                          Text(
                              widget.controller.fishing.error ??
                                  '친구 활동의 저장을 확인하고 있어요.',
                              style: const TextStyle(color: Color(0xFF9D302A))),
                          TextButton(
                              onPressed: _retrying ||
                                      _pending != null ||
                                      widget.controller.busy
                                  ? null
                                  : _retrySave,
                              child: Text(
                                  _retrying ? '저장을 확인하고 있어요…' : '저장 다시 확인')),
                        ],
                        const SizedBox(height: 16),
                        for (final record in widget.records)
                          _record(context, record),
                      ]);
                  return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      child: Column(children: [
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                                label: const Text('닫기'))),
                        if (collected &&
                            constraints.maxWidth >= 700 &&
                            scale <= 1.5)
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 4, child: portrait),
                                const SizedBox(width: 28),
                                Expanded(flex: 6, child: records)
                              ])
                        else ...[
                          portrait,
                          if (collected) ...[
                            const SizedBox(height: 28),
                            records
                          ]
                        ],
                      ]));
                })),
      ));

  Widget _record(BuildContext context, DexEntry record) {
    final c = widget.controller;
    final selected = c.fishing.isSelected(record);
    final inCar = selected && c.fishing.companionLocation == 'car';
    final pending = _pending == jsonEncode(record.toJson());
    final disabled = _retrying ||
        _pending != null ||
        c.busy ||
        !c.paired ||
        c.sessionEnded ||
        c.endingSession ||
        c.fishing.hasPendingWrite;
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: inCar ? _green : const Color(0xFFD8E3D4),
                width: inCar ? 2 : 1)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _badge('등급 ${record.tier}'),
            if (selected) _badge(inCar ? '선택된 차량 친구' : '폰에서 함께하는 친구')
          ]),
          const SizedBox(height: 14),
          _detail(
              Icons.calendar_today_outlined, '획득 날짜', _date(record.obtainedAt)),
          _detail(Icons.place_outlined, '지역', _region(record.regionTag)),
          _detail(Icons.cloud_outlined, '날씨',
              record.envTags.contains('rain') ? '비' : '기록 없음'),
          _detail(Icons.landscape_outlined, '환경', _environment(record.envTags)),
          _detail(Icons.menu_book_outlined, '관찰 기록',
              '${c.fishing.recordsFor(record)}건'),
          const SizedBox(height: 10),
          FilledButton.tonal(
              onPressed: disabled || inCar ? null : () => _select(record),
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
              child: Text(
                  pending
                      ? '친구를 선택하고 있어요…'
                      : inCar
                          ? '차량 동행으로 선택됨'
                          : c.busy
                              ? '잠시 기다려 주세요'
                              : '이 친구와 차량에서 함께하기',
                  textAlign: TextAlign.center)),
        ]));
  }
}

Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration:
        BoxDecoration(color: _pale, borderRadius: BorderRadius.circular(12)),
    child: Text(text,
        style: const TextStyle(color: _green, fontWeight: FontWeight.w600)));
Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: _muted),
      const SizedBox(width: 8),
      Expanded(child: Text('$label: $value'))
    ]));
String _attribute(Attribute value) => switch (value) {
      Attribute.normal => '일반',
      Attribute.water => '물',
      Attribute.dark => '어둠'
    };
String _date(DateTime date) {
  final local = date.toLocal();
  return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
}

String _region(String? tag) => switch (tag) {
      'coast' => '바닷가',
      'mountain' => '산',
      'city' => '도시',
      _ => '미확정'
    };
String _environment(List<String> tags) {
  const labels = {
    'rain': '비',
    'tunnel': '터널',
    'night': '밤',
    'highway': '고속도로',
    'coast': '바닷가',
    'mountain': '산',
    'city': '도시'
  };
  final names =
      tags.where(labels.containsKey).map((tag) => labels[tag]!).toSet();
  return names.isEmpty ? '기록 없음' : names.join(' · ');
}
