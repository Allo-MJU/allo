import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';

import '../game/game_controller.dart';

/// General phone controls. The controller alone owns points and quest outcomes.
class AffinityInputPanel extends StatefulWidget {
  const AffinityInputPanel({super.key, required this.controller});
  final GameController controller;

  @override
  State<AffinityInputPanel> createState() => _AffinityInputPanelState();
}

class _AffinityInputPanelState extends State<AffinityInputPanel> {
  String? _notice;

  Future<void> _talk() async {
    final c = widget.controller;
    final eggId = c.eggId;
    var draft = '';
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알에게 말 걸기'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('지금은 글로 마음을 전해요. 이름·학교·주소는 쓰지 마세요.'),
            TextField(
              onChanged: (value) => draft = value,
              autofocus: true,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '알에게 전할 말'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, draft.trim()),
              child: const Text('말 전하기')),
        ],
      ),
    );
    draft = ''; // Do not retain the text after the dialog closes.
    if (!mounted ||
        text == null ||
        text.isEmpty ||
        c.eggId != eggId ||
        c.sessionEnded) {
      return;
    }
    await c.submitEggSpeech(text);
  }

  Future<void> _recoverPhoto() async {
    final c = widget.controller;
    final eggId = c.eggId;
    await c.recoverEggPhoto();
    if (!mounted || c.eggId != eggId) return;
    setState(() => _notice = c.game.photoQuestCompleted
        ? '사진 확인이 끝났어요. 다시 마음을 쌓아 봐요.'
        : c.error == null
            ? '아직 확인된 사진이 없어요.'
            : null);
  }

  Future<void> _discard() async {
    final c = widget.controller;
    final eggId = c.eggId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이번 알을 보낼까요?'),
        content: const Text('이번 알의 품기는 끝나요. 함께하는 친구와 낚시 기록은 남아요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 품기')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('알 보내기')),
        ],
      ),
    );
    if (confirmed == true && mounted && c.eggId == eggId && !c.sessionEnded) {
      await c.discardEgg();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final round = c.affinityRound;
    final phase = c.game.affinityPhase;
    final available = !c.busy &&
        !c.endingSession &&
        !c.sessionEnded &&
        !c.speechBusy &&
        !c.photoBusy;
    final editable = available &&
        phase == 'incubating' &&
        c.game.stage == Stage.incubating &&
        round != null;
    final terminal = c.game.stage == Stage.failed;
    String cooldown(int ms, String label) =>
        ms > 0 ? '$label · ${(ms / 1000).ceil()}초 후' : label;
    final status = switch (phase) {
      'photoRequired' => '사진 퀘스트 · 마음 50점에서 잠시 기다려요',
      'resultPending' => '부화 결과 저장 중 · 아직 부화가 확정되지 않았어요',
      'hatched' => '새 친구가 깨어났어요',
      'failed' => '이번 품기가 끝났어요. 다음 알과 다시 만나봐요.',
      'discarded' => '이번 알을 보냈어요. 친구와 낚시 기록은 그대로예요.',
      _ => round == null ? '차량 신호를 기다리고 있어요' : '함께 마음을 쌓는 중',
    };
    final feedback = switch (c.eggFeedback) {
      EggFeedback.positive => '마음을 전했어요',
      EggFeedback.negative => '조금 더 다정한 말을 생각해 볼까요?',
      EggFeedback.neutral => '...',
      EggFeedback.vibration => '아직 반응이 없어요. 잠시 후 다시 해 봐요.',
      _ => '',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('호감도 ${(c.game.affinityScore ?? 0).toStringAsFixed(1)} / 100',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: ((c.game.affinityScore ?? 0) / 100).clamp(0, 1),
              semanticsLabel: '호감도'),
          const SizedBox(height: 8),
          Text(status, key: const Key('affinity-status')),
          if (phase == 'incubating') ...[
            if (c.game.photoQuestCompleted) const Text('사진 퀘스트 완료'),
            if (feedback.isNotEmpty) Text(feedback),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('pet-egg'),
              onPressed: editable && round.petRemainingMs == 0
                  ? () => c.petEgg()
                  : null,
              icon: const Icon(Icons.favorite),
              label: Text(cooldown(round?.petRemainingMs ?? 0, '쓰다듬기')),
            ),
            const SizedBox(height: 12),
            Text(cooldown(round?.moveRemainingMs ?? 0, '알을 놓을 구역')),
            const Text('편안한 자리를 찾아봐요. 같은 자리는 이동으로 세지 않아요.'),
            Wrap(
                spacing: 8,
                children: List.generate(
                    4,
                    (zone) => ChoiceChip(
                          key: Key('egg-zone-$zone'),
                          label: Text('구역 ${zone + 1}'),
                          selected: round?.currentZone == zone,
                          onSelected: editable &&
                                  round.moveRemainingMs == 0 &&
                                  round.currentZone != zone
                              ? (_) => c.placeEgg(zone)
                              : null,
                        ))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('talk-egg'),
              onPressed:
                  editable && c.eggApi != null && round.speechRemainingMs == 0
                      ? _talk
                      : null,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(c.speechBusy
                  ? '말 확인 중…'
                  : cooldown(round?.speechRemainingMs ?? 0, '말 걸기 · 글로 입력')),
            ),
            if (c.eggApi == null)
              const Text('말 확인 기능이 아직 연결되지 않았어요. 쓰다듬기와 구역 배치는 할 수 있어요.'),
          ],
          if (phase == 'photoRequired') ...[
            const SizedBox(height: 12),
            const Text('사진을 확인하면 다시 마음을 쌓을 수 있어요. 지금은 쓰다듬기·구역 배치·말 걸기를 쉬어요.'),
            const Text('사진 촬영·합성 화면은 아직 준비 중이에요.'),
            OutlinedButton.icon(
              key: const Key('recover-egg-photo'),
              onPressed: available && c.eggApi != null ? _recoverPhoto : null,
              icon: const Icon(Icons.refresh),
              label: Text(c.photoBusy ? '사진 확인 중…' : '이미 보낸 사진 다시 확인'),
            ),
            if (c.eggApi == null) const Text('사진 확인 기능이 아직 연결되지 않았어요.'),
          ],
          if (_notice != null && phase == 'photoRequired') Text(_notice!),
          if (phase == 'resultPending' && c.error != null)
            OutlinedButton(
                onPressed: available ? () => c.endSession() : null,
                child: const Text('부화 저장 다시 시도')),
          if (terminal)
            FilledButton(
                onPressed: c.canStart && available
                    ? () => c.startIncubating(c.game.eggTier, useAffinity: true)
                    : null,
                child: const Text('다음 알 품기')),
          if (round != null && !round.isTerminal)
            TextButton(
                onPressed: available ? _discard : null,
                child: const Text('이번 알 보내기')),
        ]),
      ),
    );
  }
}
