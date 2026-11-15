import 'dart:convert';

import 'base_camp_catalog.dart';
import 'companion_quest.dart';

const _maxInt = 9007199254740991;
const _cap = 1000000000;
void _id(String s) {
  if (s.trim().isEmpty || s.length > 256) {
    throw const CampException('invalid_id');
  }
}

int _number(dynamic v, {int max = _maxInt}) {
  if (v is! int || v < 0 || v > max) {
    throw const CampException('invalid_snapshot');
  }
  return v;
}

String _string(dynamic v) {
  if (v is! String) throw const CampException('invalid_snapshot');
  _id(v);
  return v;
}

Map<String, dynamic> _map(dynamic v) {
  if (v is! Map) throw const CampException('invalid_snapshot');
  return Map<String, dynamic>.from(v);
}

T _enum<T extends Enum>(List<T> values, dynamic value) =>
    values.firstWhere((e) => e.name == value,
        orElse: () => throw const CampException('invalid_snapshot'));

class CampCreature {
  CampCreature({required this.id, required this.speciesId}) {
    _id(id);
    _id(speciesId);
  }
  final String id;
  final String speciesId;
  Map<String, dynamic> toJson() => {'id': id, 'speciesId': speciesId};
  factory CampCreature.fromJson(Map<String, dynamic> json) => CampCreature(
      id: _string(json['id']), speciesId: _string(json['speciesId']));
}

class CampException implements Exception {
  const CampException(this.code);
  final String code;
  @override
  String toString() => 'CampException($code)';
}

class CampJob {
  CampJob._(
      {required this.taskId,
      required this.workerId,
      this.targetId,
      required this.role,
      required this.remainingWorkUnits,
      required this.speedMilli,
      required this.contentId,
      required Map<CampMaterial, int> cost})
      : cost = Map.unmodifiable(cost);
  final String taskId, workerId, contentId;
  final String? targetId;
  final CampRole role;
  final int remainingWorkUnits, speedMilli;
  final Map<CampMaterial, int> cost;
  CampJob _remaining(int value) => CampJob._(
      taskId: taskId,
      workerId: workerId,
      targetId: targetId,
      role: role,
      remainingWorkUnits: value,
      speedMilli: speedMilli,
      contentId: contentId,
      cost: cost);
  Map<String, dynamic> _json() => {
        'taskId': taskId,
        'workerId': workerId,
        'targetId': targetId,
        'role': role.name,
        'remainingWorkUnits': remainingWorkUnits,
        'speedMilli': speedMilli,
        'contentId': contentId,
        'cost': {for (final e in cost.entries) e.key.name: e.value}
      };
}

class BaseCamp {
  BaseCamp._();
  factory BaseCamp.empty(
      {required int nowMs, List<CampCreature> creatures = const []}) {
    _number(nowMs);
    final c = BaseCamp._().._now = nowMs;
    c._replaceCreatures(creatures);
    for (final id in c._creatures.keys) {
      c._questInvitationAnchors[id] = nowMs;
    }
    return c;
  }
  int _now = 0;
  final _creatures = <String, CampCreature>{};
  final _materials = <CampMaterial, int>{
    for (final e in CampMaterial.values) e: 0
  };
  final _facilities = <CampFacility, int>{
    for (final e in CampFacility.values) e: 0
  };
  final _assignments = <CampRole, String>{};
  final _jobs = <CampRole, CampJob>{};
  final _food = <String, int>{}, _book = <String, int>{};
  final _learned = <String, Set<String>>{};
  final _buffs = <String, int>{};
  final _drives = <String, _Drive>{};
  final _quests = <String, CompanionQuest>{};
  final _questInvitationAnchors = <String, int>{};
  final _questVisitIds = <String>{};
  int _carryMm = 0;
  int? _lastActivity;
  final _paid = <String>{}, _finalized = <String>{};
  final _collectionRewards = <String>{};
  Map<String, CompanionQuest> get quests => Map.unmodifiable(_quests);
  int get nowMs => _now;
  Map<String, CampCreature> get creatures => Map.unmodifiable(_creatures);
  Map<CampMaterial, int> get materials => Map.unmodifiable(_materials);
  Map<CampFacility, int> get facilities => Map.unmodifiable(_facilities);
  Map<CampRole, String> get assignments => Map.unmodifiable(_assignments);
  Map<CampRole, CampJob> get jobs => Map.unmodifiable(_jobs);
  Map<String, int> get foodInventory => Map.unmodifiable(_food);
  Map<String, int> get recipeBook => Map.unmodifiable(_book);
  Map<String, Set<String>> get learnedActions => Map.unmodifiable({
        for (final e in _learned.entries)
          e.key: Set<String>.unmodifiable(e.value)
      });
  bool isBusy(String creatureId) => _jobs.values
      .any((j) => j.workerId == creatureId || j.targetId == creatureId);
  bool canUseAction(String creatureId, String actionId) =>
      _creatures.containsKey(creatureId) &&
      (_learned[creatureId]?.contains(actionId) ?? false);
  void _command(int atMs) {
    _number(atMs);
    if (atMs < _now) throw const CampException('clock_backwards');
    advanceTo(atMs);
  }

  void _replaceCreatures(List<CampCreature> list) {
    final map = <String, CampCreature>{};
    for (final c in list) {
      _id(c.id);
      _id(c.speciesId);
      if (map.containsKey(c.id)) {
        throw const CampException('duplicate_creature');
      }
      map[c.id] = c;
    }
    _creatures
      ..clear()
      ..addAll(map);
  }

  void syncCreatures(List<CampCreature> creatures, {required int atMs}) {
    _command(atMs);
    final next = <String, CampCreature>{};
    for (final c in creatures) {
      _id(c.id);
      _id(c.speciesId);
      if (next.containsKey(c.id)) {
        throw const CampException('duplicate_creature');
      }
      next[c.id] = c;
    }
    final removedJobs = _jobs.values
        .where((j) =>
            !next.containsKey(j.workerId) ||
            (j.targetId != null && !next.containsKey(j.targetId)) ||
            CampCatalog.roleFor(next[j.workerId]!.speciesId) != j.role)
        .toList();
    for (final j in removedJobs) {
      _refund(j);
      _jobs.remove(j.role);
      _finalized.add(j.taskId);
    }
    _creatures
      ..clear()
      ..addAll(next);
    _assignments.removeWhere((role, id) =>
        !next.containsKey(id) ||
        CampCatalog.roleFor(next[id]!.speciesId) != role);
    _buffs.removeWhere((id, _) => !next.containsKey(id));
    _quests.removeWhere((id, _) => !next.containsKey(id));
    _questInvitationAnchors.removeWhere((id, _) => !next.containsKey(id));
    for (final id in next.keys) {
      _questInvitationAnchors.putIfAbsent(id, () => atMs);
    }
  }

  void assign(CampRole role, String? creatureId, {required int atMs}) {
    _command(atMs);
    if (_assignments[role] == creatureId) return;
    if (_jobs.containsKey(role)) throw const CampException('role_busy');
    if (creatureId != null) {
      _id(creatureId);
      final c = _creatures[creatureId];
      if (c == null || CampCatalog.roleFor(c.speciesId) != role) {
        throw const CampException('invalid_worker');
      }
      if (isBusy(creatureId)) throw const CampException('creature_busy');
    }
    if (creatureId == null) {
      _assignments.remove(role);
    } else {
      _assignments[role] = creatureId;
    }
  }

  bool _duplicate(String id, CampRole role, String content, String? target) {
    _id(id);
    if (_finalized.contains(id)) throw const CampException('task_finalized');
    for (final j in _jobs.values) {
      if (j.taskId == id) {
        if (j.role == role && j.contentId == content && j.targetId == target) {
          return true;
        }
        throw const CampException('task_conflict');
      }
    }
    return false;
  }

  void _start(String id, CampRole role, String content, String? target,
      int workMs, Map<CampMaterial, int> cost, int level) {
    if (_jobs.containsKey(role)) throw const CampException('role_busy');
    final worker = _assignments[role];
    if (worker == null || !_creatures.containsKey(worker)) {
      throw const CampException('missing_worker');
    }
    if (isBusy(worker)) throw const CampException('creature_busy');
    if (target != null &&
        (!_creatures.containsKey(target) ||
            target == worker ||
            isBusy(target))) {
      throw const CampException('invalid_target');
    }
    for (final e in cost.entries) {
      if (_materials[e.key]! < e.value) {
        throw const CampException('insufficient_materials');
      }
    }
    for (final e in cost.entries) {
      _materials[e.key] = _materials[e.key]! - e.value;
    }
    _jobs[role] = CampJob._(
        taskId: id,
        workerId: worker,
        targetId: target,
        role: role,
        remainingWorkUnits: workMs * 1000,
        speedMilli: CampCatalog.speedMilli(level),
        contentId: content,
        cost: cost);
  }

  void startBuild(
      {required String taskId,
      required CampFacility facility,
      required int atMs}) {
    _command(atMs);
    if (_duplicate(taskId, CampRole.builder, facility.name, null)) return;
    final level = _facilities[facility]! + 1;
    if (level > CampCatalog.maxLevel) throw const CampException('max_level');
    if (facility != CampFacility.workshop &&
        _facilities[CampFacility.workshop]! < 1) {
      throw const CampException('facility_locked');
    }
    _start(
        taskId,
        CampRole.builder,
        facility.name,
        null,
        CampCatalog.buildWorkMs(level),
        CampCatalog.buildCost(level),
        _facilities[CampFacility.workshop]!);
  }

  void startCooking(
      {required String taskId, required String recipeId, required int atMs}) {
    _command(atMs);
    _id(recipeId);
    if (_duplicate(taskId, CampRole.cook, recipeId, null)) return;
    final r = CampCatalog.recipes[recipeId];
    if (r == null) throw const CampException('invalid_recipe');
    if ((_food[recipeId] ?? 0) >= _cap || (_book[recipeId] ?? 0) >= _cap) {
      throw const CampException('resource_limit');
    }
    final level = _facilities[CampFacility.kitchen]!;
    if (level < r.level) throw const CampException('facility_locked');
    _start(taskId, CampRole.cook, recipeId, null, r.workMs, r.cost, level);
  }

  void startTraining(
      {required String taskId,
      required String actionId,
      required String targetId,
      required int atMs}) {
    _command(atMs);
    _id(actionId);
    _id(targetId);
    if (_duplicate(taskId, CampRole.trainer, actionId, targetId)) return;
    final lesson = CampCatalog.lessons[actionId];
    if (lesson == null) throw const CampException('invalid_action');
    final level = _facilities[CampFacility.training]!;
    if (level < lesson.level) throw const CampException('facility_locked');
    if (_learned[targetId]?.contains(actionId) ?? false) {
      throw const CampException('already_learned');
    }
    _start(taskId, CampRole.trainer, actionId, targetId, lesson.workMs,
        lesson.cost, level);
  }

  void _refund(CampJob j) {
    for (final e in j.cost.entries) {
      if (_materials[e.key]! + e.value > _cap) {
        throw const CampException('resource_limit');
      }
    }
    for (final e in j.cost.entries) {
      _materials[e.key] = _materials[e.key]! + e.value;
    }
  }

  void cancel(CampRole role, {required int atMs}) {
    _command(atMs);
    final j = _jobs[role];
    if (j == null) return;
    _refund(j);
    _jobs.remove(role);
    _finalized.add(j.taskId);
  }

  void feedFood(
      {required String recipeId,
      required String creatureId,
      required int atMs}) {
    _command(atMs);
    _id(recipeId);
    _id(creatureId);
    if (!_creatures.containsKey(creatureId)) {
      throw const CampException('invalid_creature');
    }
    if ((_food[recipeId] ?? 0) < 1) throw const CampException('missing_food');
    if (atMs > _maxInt - 300000) throw const CampException('invalid_time');
    _food[recipeId] = _food[recipeId]! - 1;
    _buffs[creatureId] = atMs + 300000;
    final q = _quests[creatureId];
    if (q != null &&
        q.kind == CompanionQuestKind.food &&
        q.status == CompanionQuestStatus.accepted &&
        q.targetFoodId == recipeId) {
      _quests[creatureId] = q.copyWith(
          status: CompanionQuestStatus.completed, completedAtMs: atMs);
    }
  }

  static const questIntervalMs = 172800000;
  int questInvitationAtMs(String creatureId, {required int atMs}) {
    _id(creatureId);
    _number(atMs);
    if (atMs < _now) throw const CampException('clock_backwards');
    if (!_creatures.containsKey(creatureId))
      throw const CampException('invalid_creature');
    final anchor = _questInvitationAnchors[creatureId];
    if (anchor == null) throw const CampException('missing_invitation_anchor');
    return anchor + ((atMs - anchor) ~/ questIntervalMs) * questIntervalMs;
  }

  bool questDue(String creatureId, {required int atMs}) {
    _id(creatureId);
    _number(atMs);
    if (atMs < _now) throw const CampException('clock_backwards');
    if (!_creatures.containsKey(creatureId))
      throw const CampException('invalid_creature');
    final q = _quests[creatureId];
    return q == null ||
        (q.status != CompanionQuestStatus.accepted &&
            atMs >= q.nextEligibleAtMs);
  }

  void _validateQuest(CompanionQuest q) {
    _id(q.creatureId);
    _id(q.questId);
    _id(q.templateId);
    if (q.targetFoodId != null) _id(q.targetFoodId!);
    if (q.targetPlaceId != null) _id(q.targetPlaceId!);
    if (q.completedVisitId != null) _id(q.completedVisitId!);
    _number(q.templateVersion);
    _number(q.issuedAtMs);
    _number(q.nextEligibleAtMs);
    if (q.templateVersion < 1 ||
        q.issuedAtMs > _maxInt - questIntervalMs ||
        q.nextEligibleAtMs != q.issuedAtMs + questIntervalMs ||
        q.issuedAtMs > _now ||
        (q.kind == CompanionQuestKind.food &&
            (q.targetFoodId == null ||
                !CampCatalog.recipes.containsKey(q.targetFoodId))) ||
        (q.kind != CompanionQuestKind.food && q.targetFoodId != null) ||
        (q.kind != CompanionQuestKind.travel &&
            (q.targetPlaceId != null || q.completedVisitId != null)) ||
        (q.status == CompanionQuestStatus.offered &&
            (q.acceptedAtMs != null ||
                q.completedAtMs != null ||
                q.completedVisitId != null)) ||
        (q.status != CompanionQuestStatus.offered &&
            (q.acceptedAtMs == null ||
                q.acceptedAtMs! < q.issuedAtMs ||
                q.acceptedAtMs! > _now)) ||
        (q.kind == CompanionQuestKind.travel &&
            q.status != CompanionQuestStatus.offered &&
            q.targetPlaceId == null) ||
        (q.status == CompanionQuestStatus.completed &&
            (q.completedAtMs == null ||
                q.completedAtMs! < q.acceptedAtMs! ||
                q.completedAtMs! > _now)) ||
        (q.status != CompanionQuestStatus.completed &&
            (q.completedAtMs != null || q.completedVisitId != null)) ||
        (q.kind == CompanionQuestKind.travel &&
            q.status == CompanionQuestStatus.completed &&
            q.completedVisitId == null))
      throw const CampException('invalid_snapshot');
  }

  bool offerQuest(CompanionQuest q, {required int atMs}) {
    if (!questDue(q.creatureId, atMs: atMs)) return false;
    _command(atMs);
    if (q.status != CompanionQuestStatus.offered ||
        q.issuedAtMs > atMs ||
        (_quests[q.creatureId] != null &&
            q.issuedAtMs < _quests[q.creatureId]!.nextEligibleAtMs))
      throw const CampException('invalid_quest');
    _validateQuest(q);
    _quests[q.creatureId] = q;
    return true;
  }

  bool acceptQuest(String creatureId, String questId,
      {required int atMs, String? targetPlaceId}) {
    _command(atMs);
    _id(creatureId);
    _id(questId);
    final q = _quests[creatureId];
    if (q == null ||
        q.questId != questId ||
        q.status != CompanionQuestStatus.offered ||
        atMs >= q.nextEligibleAtMs) return false;
    if (q.kind == CompanionQuestKind.travel) {
      if (targetPlaceId == null ||
          (q.targetPlaceId != null && q.targetPlaceId != targetPlaceId))
        return false;
      _id(targetPlaceId);
    } else if (targetPlaceId != null) {
      return false;
    }
    _quests[creatureId] = q.copyWith(
        status: CompanionQuestStatus.accepted,
        acceptedAtMs: atMs,
        targetPlaceId: targetPlaceId);
    return true;
  }

  bool completeStoryQuest(String creatureId, String questId,
      {required int atMs}) {
    _command(atMs);
    _id(creatureId);
    _id(questId);
    final q = _quests[creatureId];
    if (q == null ||
        q.questId != questId ||
        q.kind != CompanionQuestKind.story ||
        q.status != CompanionQuestStatus.accepted) return false;
    _quests[creatureId] =
        q.copyWith(status: CompanionQuestStatus.completed, completedAtMs: atMs);
    return true;
  }

  bool completeTravelQuest(String creatureId, String questId,
      {required int atMs,
      required String placeId,
      required String visitId,
      required int arrivedAtMs,
      required List<String> companionIds}) {
    _command(atMs);
    _id(creatureId);
    _id(questId);
    _id(placeId);
    _id(visitId);
    _number(arrivedAtMs);
    final q = _quests[creatureId];
    if (q == null ||
        q.questId != questId ||
        q.kind != CompanionQuestKind.travel ||
        q.status != CompanionQuestStatus.accepted ||
        q.targetPlaceId != placeId ||
        arrivedAtMs <= q.acceptedAtMs! ||
        arrivedAtMs > atMs ||
        !companionIds.contains(creatureId) ||
        _questVisitIds.contains(jsonEncode([creatureId, visitId])))
      return false;
    _questVisitIds.add(jsonEncode([creatureId, visitId]));
    _quests[creatureId] = q.copyWith(
        status: CompanionQuestStatus.completed,
        completedAtMs: atMs,
        completedVisitId: visitId);
    return true;
  }

  void advanceTo(int atMs) {
    _number(atMs);
    if (atMs <= _now) return;
    for (final entry in _jobs.entries.toList()) {
      final j = entry.value;
      var remaining = j.remainingWorkUnits;
      final expiry = _buffs[j.workerId] ?? 0;
      final boostedMs =
          expiry > _now ? (expiry < atMs ? expiry : atMs) - _now : 0;
      final normalMs = atMs - _now - boostedMs;
      final boostedRate = j.speedMilli * 1500 ~/ 1000;
      final neededBoost = (remaining + boostedRate - 1) ~/ boostedRate;
      if (boostedMs >= neededBoost) {
        remaining = 0;
      } else {
        remaining -= boostedMs * boostedRate;
        final needed = (remaining + j.speedMilli - 1) ~/ j.speedMilli;
        if (normalMs >= needed) {
          remaining = 0;
        } else {
          remaining -= normalMs * j.speedMilli;
        }
      }
      if (remaining == 0) {
        _complete(j);
        _jobs.remove(entry.key);
        _finalized.add(j.taskId);
      } else {
        _jobs[entry.key] = j._remaining(remaining);
      }
    }
    _now = atMs;
    _buffs.removeWhere((_, expiry) => expiry <= atMs);
  }

  void _complete(CampJob j) {
    switch (j.role) {
      case CampRole.builder:
        final f = _enum(CampFacility.values, j.contentId);
        _facilities[f] = _facilities[f]! + 1;
      case CampRole.cook:
        if ((_food[j.contentId] ?? 0) >= _cap ||
            (_book[j.contentId] ?? 0) >= _cap) {
          throw const CampException('resource_limit');
        }
        _food[j.contentId] = (_food[j.contentId] ?? 0) + 1;
        _book[j.contentId] = (_book[j.contentId] ?? 0) + 1;
      case CampRole.trainer:
        (_learned[j.targetId!] ??= <String>{}).add(j.contentId);
    }
  }

  void _award(int count) {
    for (final m in CampMaterial.values) {
      final reserved =
          _jobs.values.fold<int>(0, (n, j) => n + (j.cost[m] ?? 0));
      if (_materials[m]! + reserved + count > _cap) {
        throw const CampException('resource_limit');
      }
    }
    for (final m in CampMaterial.values) {
      _materials[m] = _materials[m]! + count;
    }
  }

  bool recordDrive(
      {required String sessionId,
      required int ts,
      required double distanceM,
      required int atMs,
      bool baselineOnly = false}) {
    _command(atMs);
    _id(sessionId);
    _number(ts);
    if (!distanceM.isFinite || distanceM < 0 || distanceM > 1e12) {
      throw const CampException('invalid_distance');
    }
    final prev = _drives[sessionId];
    if (prev != null && ts <= prev.ts) return false;
    final observedMm = (distanceM * 1000).floor();
    final high = prev == null || observedMm > prev.distanceMm
        ? observedMm
        : prev.distanceMm;
    final delta = prev == null || baselineOnly ? 0 : high - prev.distanceMm;
    final total = _carryMm + delta;
    final award = total ~/ 1000000;
    _award(award);
    _carryMm = total % 1000000;
    _drives[sessionId] = _Drive(ts, high);
    return true;
  }

  bool recordLookOut({required String eventId, required int atMs}) {
    _command(atMs);
    _id(eventId);
    if (_paid.contains(eventId) ||
        (_lastActivity != null && atMs - _lastActivity! < 60000)) {
      return false;
    }
    _award(1);
    _lastActivity = atMs;
    _paid.add(eventId);
    return true;
  }

  bool grantCollectionReward(String tripId, {required int atMs}) {
    _id(tripId);
    _command(atMs);
    if (_collectionRewards.contains(tripId)) return false;
    final count = _food['berry_snack'] ?? 0;
    if (count > _cap - 3) throw const CampException('resource_cap');
    _food['berry_snack'] = count + 3;
    _collectionRewards.add(tripId);
    return true;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'questInvitationAnchors':
            Map<String, int>.from(_questInvitationAnchors),
        'quests': {for (final e in _quests.entries) e.key: e.value.toJson()},
        'questVisitIds': _questVisitIds.toList(),
        'nowMs': _now,
        'creatures': [for (final c in _creatures.values) c.toJson()],
        'materials': {for (final e in _materials.entries) e.key.name: e.value},
        'facilities': {
          for (final e in _facilities.entries) e.key.name: e.value
        },
        'assignments': {
          for (final e in _assignments.entries) e.key.name: e.value
        },
        'jobs': [for (final j in _jobs.values) j._json()],
        'foodInventory': Map<String, int>.from(_food),
        'recipeBook': Map<String, int>.from(_book),
        'learnedActions': {
          for (final e in _learned.entries) e.key: e.value.toList()
        },
        'buffs': Map<String, int>.from(_buffs),
        'drives': {
          for (final e in _drives.entries)
            e.key: {'ts': e.value.ts, 'distanceMm': e.value.distanceMm}
        },
        'driveCarryMm': _carryMm,
        'lastActivity': _lastActivity,
        'paidActivityIds': _paid.toList(),
        'collectionRewardTripIds': _collectionRewards.toList(),
        'finalizedTaskIds': _finalized.toList()
      };
  factory BaseCamp.fromJson(Map<String, dynamic> json) {
    try {
      return _parse(json);
    } on CampException {
      rethrow;
    } catch (_) {
      throw const CampException('invalid_snapshot');
    }
  }
  static BaseCamp _parse(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const CampException('invalid_snapshot');
    final c = BaseCamp._().._now = _number(json['nowMs']);
    final cs = json['creatures'];
    if (cs is! List) throw const CampException('invalid_snapshot');
    c._replaceCreatures(cs.map((v) => CampCreature.fromJson(_map(v))).toList());
    for (final e in _map(json['questInvitationAnchors'] ?? {}).entries) {
      if (!c._creatures.containsKey(e.key))
        throw const CampException('invalid_snapshot');
      final anchor = _number(e.value);
      if (anchor > c._now) throw const CampException('invalid_snapshot');
      c._questInvitationAnchors[e.key] = anchor;
    }
    for (final e in _map(json['quests'] ?? {}).entries) {
      final q = CompanionQuest.fromJson(_map(e.value));
      if (e.key != q.creatureId || !c._creatures.containsKey(e.key))
        throw const CampException('invalid_snapshot');
      c._validateQuest(q);
      c._quests[e.key] = q;
    }
    final visits = json['questVisitIds'] ?? [];
    if (visits is! List) throw const CampException('invalid_snapshot');
    for (final v in visits) {
      if (v is! String || v.length > 4000)
        throw const CampException('invalid_snapshot');
      final pair = jsonDecode(v);
      if (pair is! List || pair.length != 2)
        throw const CampException('invalid_snapshot');
      _string(pair[0]);
      _string(pair[1]);
      if (jsonEncode(pair) != v || !c._questVisitIds.add(v))
        throw const CampException('invalid_snapshot');
    }
    for (final q in c._quests.values) {
      if (q.completedVisitId != null &&
          !c._questVisitIds
              .contains(jsonEncode([q.creatureId, q.completedVisitId])))
        throw const CampException('invalid_snapshot');
    }
    final materials = _map(json['materials']);
    final facilities = _map(json['facilities']);
    if (materials.length != CampMaterial.values.length ||
        facilities.length != CampFacility.values.length) {
      throw const CampException('invalid_snapshot');
    }
    for (final e in materials.entries) {
      c._materials[_enum(CampMaterial.values, e.key)] =
          _number(e.value, max: _cap);
    }
    for (final e in facilities.entries) {
      c._facilities[_enum(CampFacility.values, e.key)] =
          _number(e.value, max: 3);
    }
    for (final e in _map(json['assignments']).entries) {
      final role = _enum(CampRole.values, e.key);
      final id = _string(e.value);
      if (!c._creatures.containsKey(id) ||
          CampCatalog.roleFor(c._creatures[id]!.speciesId) != role) {
        throw const CampException('invalid_snapshot');
      }
      c._assignments[role] = id;
    }
    void countMap(dynamic raw, Map<String, int> out) {
      for (final e in _map(raw).entries) {
        if (!CampCatalog.recipes.containsKey(e.key)) {
          throw const CampException('invalid_snapshot');
        }
        out[e.key] = _number(e.value, max: _cap);
      }
    }

    countMap(json['foodInventory'], c._food);
    countMap(json['recipeBook'], c._book);
    for (final e in _map(json['learnedActions']).entries) {
      _id(e.key);
      if (e.value is! List) throw const CampException('invalid_snapshot');
      final set = <String>{};
      for (final a in e.value as List) {
        final id = _string(a);
        if (!CampCatalog.lessons.containsKey(id) || !set.add(id)) {
          throw const CampException('invalid_snapshot');
        }
      }
      c._learned[e.key] = set;
    }
    for (final e in _map(json['buffs']).entries) {
      if (!c._creatures.containsKey(e.key)) {
        throw const CampException('invalid_snapshot');
      }
      final expiry = _number(e.value);
      if (expiry <= c._now || expiry - c._now > 300000) {
        throw const CampException('invalid_snapshot');
      }
      c._buffs[e.key] = expiry;
    }
    for (final e in _map(json['drives']).entries) {
      _id(e.key);
      final d = _map(e.value);
      final distanceMm = _number(d['distanceMm'], max: 1000000000000000);
      c._drives[e.key] = _Drive(_number(d['ts']), distanceMm);
    }
    c._carryMm = _number(json['driveCarryMm'], max: 999999);
    if (json['lastActivity'] != null) {
      c._lastActivity = _number(json['lastActivity']);
      if (c._lastActivity! > c._now) {
        throw const CampException('invalid_snapshot');
      }
    }
    void ids(dynamic raw, Set<String> set) {
      if (raw is! List) throw const CampException('invalid_snapshot');
      for (final v in raw) {
        if (!set.add(_string(v))) throw const CampException('invalid_snapshot');
      }
    }

    ids(json['paidActivityIds'], c._paid);
    ids(json['collectionRewardTripIds'] ?? [], c._collectionRewards);
    for (final e in c._food.entries) {
      final rewarded =
          e.key == 'berry_snack' ? c._collectionRewards.length * 3 : 0;
      if (e.value > (c._book[e.key] ?? 0) + rewarded) {
        throw const CampException('invalid_snapshot');
      }
    }
    ids(json['finalizedTaskIds'], c._finalized);
    if ((c._lastActivity == null) != c._paid.isEmpty) {
      throw const CampException('invalid_snapshot');
    }
    final jobs = json['jobs'];
    if (jobs is! List) throw const CampException('invalid_snapshot');
    final reserved = <String>{};
    for (final raw in jobs) {
      final j = _map(raw);
      final role = _enum(CampRole.values, j['role']);
      final taskId = _string(j['taskId']);
      final worker = _string(j['workerId']);
      final content = _string(j['contentId']);
      final target = j['targetId'] == null ? null : _string(j['targetId']);
      final remaining = _number(j['remainingWorkUnits']);
      final speed = _number(j['speedMilli']);
      if (remaining == 0 ||
          ![1000, 1250, 1500].contains(speed) ||
          speed >
              CampCatalog.speedMilli(
                  c._facilities[CampCatalog.facilityFor(role)]!) ||
          c._jobs.containsKey(role) ||
          c._finalized.contains(taskId) ||
          c._jobs.values.any((x) => x.taskId == taskId) ||
          c._assignments[role] != worker ||
          !reserved.add(worker)) {
        throw const CampException('invalid_snapshot');
      }
      if (role == CampRole.trainer) {
        if (target == null ||
            !c._creatures.containsKey(target) ||
            !reserved.add(target) ||
            !CampCatalog.lessons.containsKey(content) ||
            (c._learned[target]?.contains(content) ?? false)) {
          throw const CampException('invalid_snapshot');
        }
      } else if (target != null) {
        throw const CampException('invalid_snapshot');
      }
      Map<CampMaterial, int> expected;
      int maxWork;
      if (role == CampRole.builder) {
        final f = _enum(CampFacility.values, content);
        final targetLevel = c._facilities[f]! + 1;
        if (targetLevel > 3 ||
            (f != CampFacility.workshop &&
                c._facilities[CampFacility.workshop]! < 1)) {
          throw const CampException('invalid_snapshot');
        }
        expected = CampCatalog.buildCost(targetLevel);
        maxWork = CampCatalog.buildWorkMs(targetLevel);
      } else if (role == CampRole.cook) {
        final r = CampCatalog.recipes[content];
        if (r == null ||
            c._facilities[CampFacility.kitchen]! < r.level ||
            (c._food[content] ?? 0) >= _cap ||
            (c._book[content] ?? 0) >= _cap) {
          throw const CampException('invalid_snapshot');
        }
        expected = r.cost;
        maxWork = r.workMs;
      } else {
        final l = CampCatalog.lessons[content]!;
        if (c._facilities[CampFacility.training]! < l.level) {
          throw const CampException('invalid_snapshot');
        }
        expected = l.cost;
        maxWork = l.workMs;
      }
      final cost = <CampMaterial, int>{};
      for (final e in _map(j['cost']).entries) {
        cost[_enum(CampMaterial.values, e.key)] = _number(e.value, max: _cap);
      }
      if (remaining > maxWork * 1000 ||
          cost.length != expected.length ||
          expected.entries.any((e) => cost[e.key] != e.value)) {
        throw const CampException('invalid_snapshot');
      }
      c._jobs[role] = CampJob._(
          taskId: taskId,
          workerId: worker,
          targetId: target,
          role: role,
          remainingWorkUnits: remaining,
          speedMilli: speed,
          contentId: content,
          cost: cost);
    }
    for (final m in CampMaterial.values) {
      final reserved =
          c._jobs.values.fold<int>(0, (n, j) => n + (j.cost[m] ?? 0));
      if (c._materials[m]! + reserved > _cap) {
        throw const CampException('invalid_snapshot');
      }
    }
    return c;
  }
}

class _Drive {
  const _Drive(this.ts, this.distanceMm);
  final int ts;
  final int distanceMm;
}
