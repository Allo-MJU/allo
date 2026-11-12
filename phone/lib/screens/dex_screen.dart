import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../ui_mode.dart';
import '../widgets/species_art.dart';

/// 수집 기록은 기기에만 저장한다. 지역이 없는 기록을 방문 이력으로 추정하지 않는다.
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
    final entries = await widget.controller.dex.all();
    return (species.all, entries);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                final c = widget.controller;
                // 주행 중(광장 흐름)이면 광장으로, 아니면 처음 화면으로
                if (!c.sessionEnded &&
                    c.game.stage != Stage.idle &&
                    plazaFlow(usesAffinity: c.usesAffinity)) {
                  context.go('/home');
                  return;
                }
                c.prepareNextFakeTrip();
                context.go('/pairing');
              }),
        ),
        body: FutureBuilder<(List<Species>, List<DexEntry>)>(
          future: _contents,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('도감을 불러오지 못했어요.'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () => setState(() {
                            _contents = _load();
                          }),
                      child: const Text('다시 시도')),
                ]),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (species, entries) = snapshot.data!;
            final owned = <String, List<DexEntry>>{};
            for (final entry in entries) {
              owned.putIfAbsent(entry.speciesId, () => []).add(entry);
            }
            final count = species.where((s) => owned.containsKey(s.id)).length;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('만난 친구 $count / ${species.length}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 180,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: species.length,
                  itemBuilder: (context, index) {
                    final friend = species[index];
                    final records = owned[friend.id] ?? const <DexEntry>[];
                    final collected = records.isNotEmpty;
                    return Card(
                      key: ValueKey('dex-${friend.id}'),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showDetails(friend, records),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (collected)
                                SpeciesArt(species: friend, size: 64)
                              else
                                const Icon(Icons.lock_outline, size: 64),
                              const SizedBox(height: 8),
                              Text(collected ? friend.nameKo : '아직 만나지 못했어요',
                                  textAlign: TextAlign.center),
                              Text(
                                  collected
                                      ? '${records.length}번 만남'
                                      : '눌러서 힌트 보기',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      );

  void _showDetails(Species species, List<DexEntry> entries) {
    final records = List<DexEntry>.of(entries)
      ..sort((a, b) => b.obtainedAt.compareTo(a.obtainedAt));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (records.isEmpty) ...[
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 12),
              const Text('아직 만나지 못한 친구'),
              const SizedBox(height: 8),
              Text(species.hint, textAlign: TextAlign.center),
            ] else ...[
              SpeciesArt(species: species),
              Text(species.nameKo,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(species.nameEn),
              const SizedBox(height: 12),
              Text(
                  '속성: ${_attribute(species.attribute)} · 등급 ${records.first.tier}'),
              Text('총 ${records.length}번 만났어요'),
              if (!widget.controller.paired)
                const Text('차량과 연결한 뒤 함께할 친구를 선택할 수 있어요.'),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => Column(children: [
                  Text(
                      '선택된 차량 친구의 관찰 기록 ${widget.controller.fishing.totalRecords}건'),
                  if (widget.controller.fishing.error != null) ...[
                    Text(widget.controller.fishing.error!),
                    TextButton(
                        onPressed: () => widget.controller.fishing.retrySave(),
                        child: const Text('낚시 저장 다시 확인')),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(children: [
                    Text('획득 날짜: ${_date(record.obtainedAt)}'),
                    Text('환경: ${_environment(record.envTags)}',
                        textAlign: TextAlign.center),
                    Text('지역: ${_region(record.regionTag)}'),
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) => FilledButton.tonal(
                        onPressed: !widget.controller.paired ||
                                widget.controller.busy ||
                                widget.controller.sessionEnded
                            ? null
                            : () async {
                                final selected = await widget.controller
                                    .selectCarCompanion(record);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                        content: Text(
                                  selected
                                      ? '이 친구를 차량 동행으로 선택했어요. 주차 후 차량에서 낚시를 시작해 주세요.'
                                      : widget.controller.error ??
                                          '친구를 선택하지 못했어요.',
                                )));
                              },
                        child: const Text('이 친구와 차량에서 함께하기'),
                      ),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: 12),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기')),
          ]),
        ),
      ),
    );
  }

  static String _attribute(Attribute value) => switch (value) {
        Attribute.normal => '일반',
        Attribute.water => '물',
        Attribute.dark => '어둠',
      };

  static String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }

  static String _region(String? tag) => switch (tag) {
        'coast' => '바닷가',
        'mountain' => '산',
        'city' => '도시',
        _ => '미확정',
      };

  static String _environment(List<String> tags) {
    const labels = {
      'rain': '비',
      'tunnel': '터널',
      'night': '밤',
      'highway': '고속도로',
      'coast': '바닷가',
      'mountain': '산',
      'city': '도시',
    };
    final names =
        tags.where(labels.containsKey).map((tag) => labels[tag]!).toSet();
    return names.isEmpty ? '기록 없음' : names.join(' · ');
  }
}
