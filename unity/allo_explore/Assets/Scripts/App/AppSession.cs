using System;
using Allo.Bridge;
using UnityEngine;

namespace Allo.App
{
    public enum AppBackAction { CloseExplore, NavigateHome, BackgroundApp, PauseStory }

    /// Authoritative snapshots come from Dart. The Unity side emits intents only.
    public sealed class AppSession : MonoBehaviour
    {
        static AppSession _instance;
        AppWorld _world;
        CabinEgg _egg;
        public static AppState State { get; private set; }
        public static event Action<AppState> Changed;
        public static bool StoryActive => State?.view == "cabin" && State.story != null && State.story.active && !State.story.paused;
        public static string CurrentView => State?.view ?? "home";

        public static AppBackAction BackActionFor(AppState state) => state == null
            ? AppBackAction.CloseExplore
            : state.view == "cabin" && state.story != null && state.story.active && !state.story.paused ? AppBackAction.PauseStory
            : state.view == "home" ? AppBackAction.BackgroundApp : AppBackAction.NavigateHome;

        public static bool Accepts(AppState current, AppState next) =>
            next != null && next.v == 1 && next.type == "app" &&
            (next.view == "home" || next.view == "cabin" || next.view == "camp" ||
             next.view == "dex" || next.view == "inventory" || next.view == "settings") &&
            (current == null || next.revision > current.revision);

        public static void Install()
        {
            if (_instance != null) return;
            var root = new GameObject("Unity Phone Application");
            _instance = root.AddComponent<AppSession>();
            _instance._world = root.AddComponent<AppWorld>();
            _instance._egg = root.AddComponent<CabinEgg>();
            root.AddComponent<AppUi>();
        }

        public static void Receive(AppState next)
        {
            if (!Accepts(State, next)) return;
            next.materials ??= Array.Empty<MaterialState>();
            next.facilities ??= Array.Empty<FacilityState>();
            next.creatures ??= Array.Empty<CreatureState>();
            next.assignments ??= Array.Empty<AssignmentState>();
            next.jobs ??= Array.Empty<JobState>();
            next.foods ??= Array.Empty<FoodState>();
            next.training ??= Array.Empty<TrainingState>();
            next.dex ??= Array.Empty<DexState>();
            next.egg ??= new EggState();
            State = next;
            if (Application.isPlaying)
            {
                Install();
                _instance._world.Apply(next);
                _instance._egg.SetView(next.view);
                _instance._egg.Apply(next);
            }
            Changed?.Invoke(next);
        }

        public static AppAction CreateAction(string action, AppAction body = null)
        {
            var request = body ?? new AppAction();
            request.v = 1;
            request.type = "appAction";
            request.requestId = "unity-" + Guid.NewGuid().ToString("N");
            request.action = action;
            if (action.StartsWith("story", StringComparison.Ordinal) && State?.story != null)
            {
                request.instanceId ??= State.story.instanceId;
                request.nodeId ??= State.story.nodeId;
                request.topicId ??= State.story.topicId;
                request.storyRevision = State.story.revision;
            }
            if (string.IsNullOrEmpty(request.eggId)) request.eggId = State?.egg?.id;
            return request;
        }

        public static string Request(string action, AppAction body = null)
        {
            var request = CreateAction(action, body);
            AndroidHost.Send(JsonUtility.ToJson(request));
            return request.requestId;
        }

        void OnDestroy()
        {
            if (_instance != this) return;
            _instance = null;
            State = null;
        }
    }
}
