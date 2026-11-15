enum CompanionQuestKind { food, story, travel }

enum CompanionQuestStatus { offered, accepted, completed }

class CompanionQuest {
  const CompanionQuest(
      {required this.creatureId,
      required this.questId,
      required this.kind,
      required this.templateId,
      required this.templateVersion,
      required this.issuedAtMs,
      required this.nextEligibleAtMs,
      this.status = CompanionQuestStatus.offered,
      this.targetFoodId,
      this.targetPlaceId,
      this.acceptedAtMs,
      this.completedAtMs,
      this.completedVisitId});
  final String creatureId, questId, templateId;
  final CompanionQuestKind kind;
  final CompanionQuestStatus status;
  final int templateVersion, issuedAtMs, nextEligibleAtMs;
  final String? targetFoodId, targetPlaceId, completedVisitId;
  final int? acceptedAtMs, completedAtMs;
  CompanionQuest copyWith(
          {CompanionQuestStatus? status,
          String? targetPlaceId,
          int? acceptedAtMs,
          int? completedAtMs,
          String? completedVisitId}) =>
      CompanionQuest(
          creatureId: creatureId,
          questId: questId,
          kind: kind,
          templateId: templateId,
          templateVersion: templateVersion,
          issuedAtMs: issuedAtMs,
          nextEligibleAtMs: nextEligibleAtMs,
          status: status ?? this.status,
          targetFoodId: targetFoodId,
          targetPlaceId: targetPlaceId ?? this.targetPlaceId,
          acceptedAtMs: acceptedAtMs ?? this.acceptedAtMs,
          completedAtMs: completedAtMs ?? this.completedAtMs,
          completedVisitId: completedVisitId ?? this.completedVisitId);
  Map<String, dynamic> toJson() => {
        'creatureId': creatureId,
        'questId': questId,
        'kind': kind.name,
        'templateId': templateId,
        'templateVersion': templateVersion,
        'issuedAtMs': issuedAtMs,
        'nextEligibleAtMs': nextEligibleAtMs,
        'status': status.name,
        'targetFoodId': targetFoodId,
        'targetPlaceId': targetPlaceId,
        'acceptedAtMs': acceptedAtMs,
        'completedAtMs': completedAtMs,
        'completedVisitId': completedVisitId
      };
  factory CompanionQuest.fromJson(Map<String, dynamic> j) => CompanionQuest(
      creatureId: j['creatureId'] as String,
      questId: j['questId'] as String,
      kind: CompanionQuestKind.values.byName(j['kind'] as String),
      templateId: j['templateId'] as String,
      templateVersion: j['templateVersion'] as int,
      issuedAtMs: j['issuedAtMs'] as int,
      nextEligibleAtMs: j['nextEligibleAtMs'] as int,
      status: CompanionQuestStatus.values.byName(j['status'] as String),
      targetFoodId: j['targetFoodId'] as String?,
      targetPlaceId: j['targetPlaceId'] as String?,
      acceptedAtMs: j['acceptedAtMs'] as int?,
      completedAtMs: j['completedAtMs'] as int?,
      completedVisitId: j['completedVisitId'] as String?);
}
