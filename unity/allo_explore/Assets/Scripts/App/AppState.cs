using System;

namespace Allo.App
{
    [Serializable]
    public sealed class AppState
    {
        public int v = 1;
        public string type = "app";
        public long revision;
        public string view = "home";
        public bool ready, busy, connected, isDemo, canStart, sessionEnded, speechAvailable, photoAvailable;
        public bool gyro = true, reducedMotion;
        public string error, notice, rewardStatus;
        public int fishingRecords;
        public string fishingError;
        public EggState egg;
        public LearningState learning;
        public StoryState story;
        public MaterialState[] materials = Array.Empty<MaterialState>();
        public FacilityState[] facilities = Array.Empty<FacilityState>();
        public CreatureState[] creatures = Array.Empty<CreatureState>();
        public AssignmentState[] assignments = Array.Empty<AssignmentState>();
        public JobState[] jobs = Array.Empty<JobState>();
        public FoodState[] foods = Array.Empty<FoodState>();
        public TrainingState[] training = Array.Empty<TrainingState>();
        public DexState[] dex = Array.Empty<DexState>();
    }

    [Serializable] public sealed class StoryChoice { public string id, label; }
    [Serializable] public sealed class StoryCard { public string id, title, text, topicId; }
    [Serializable] public sealed class StoryState
    {
        public bool available, active, paused, pending, canPlay, ackAccepted;
        public string ackRequestId;
        public string instanceId, topicId, title, nodeId, line, visual, variant, cardTitle, cardText, notice, invitation;
        public int revision, cardCount;
        public StoryChoice[] choices = Array.Empty<StoryChoice>();
        public StoryCard[] savedCards = Array.Empty<StoryCard>();
        public StoryCard[] library = Array.Empty<StoryCard>();
    }
    [Serializable] public sealed class EggState
    {
        public string id, phase, feedback, remainingLabel, speciesId, name, sprite;
        public bool active, photoRequired, speechBusy, photoBusy;
        public float score;
        public int zone, preferredZone, speechCooldown, petCooldown, moveCooldown;
    }
    [Serializable] public sealed class MaterialState { public string id, label; public int count; }
    [Serializable] public sealed class LearningState
    {
        public string creatureId, speciesId, name, storyId, sceneId, title, text, target, status, error, source, careActionId;
        public bool active, busy, recording, available, canNext, muted, speechAvailable;
        public long careSequence;
        public LearningCreatureState[] creatures = Array.Empty<LearningCreatureState>();
    }
    [Serializable] public sealed class LearningCreatureState { public string creatureId, speciesId, name; }
    [Serializable] public sealed class FacilityState { public string id, label; public int level, woodCost, stoneCost; public bool unlocked, canUpgrade; }
    [Serializable] public sealed class AssignmentState { public string role, creatureId; }
    [Serializable] public sealed class CreatureState
    {
        public string id, speciesId, name, role, sprite;
        public string[] actions = Array.Empty<string>();
        public long foodBoostUntilMs;
    }
    [Serializable] public sealed class JobState { public string id, role, label, workerId, targetId; public float progress; public int remainingSec; }
    [Serializable] public sealed class FoodState { public string id, label; public int count, costIngredient, requiredLevel; public bool unlocked; }
    [Serializable] public sealed class TrainingState { public string id, label; public int woodCost, stoneCost, ingredientCost, requiredLevel; public bool unlocked; }
    [Serializable] public sealed class DexState { public string id, name, sprite, attribute, role, description; public bool collected; public int count; }

    [Serializable]
    public sealed class AppAction
    {
        public int v = 1;
        public string type = "appAction";
        public string requestId, action, view, eggId, tier, role, creatureId, targetId, facility, recipeId, actionId, text, sessionId, pairCode;
        public string instanceId, nodeId, topicId;
        public int storyRevision;
        public bool blocked;
        public int zone;
        public bool gyro, reducedMotion;
    }
}
