using System;
using System.Collections.Generic;
using System.Text;
using UnityEngine;
using UnityEngine.UI;
using Allo.Critters;
using Allo.Bridge;

namespace Allo.App
{
    /// Persistent, presentation-only story surface. Never rebuilt by vehicle snapshot ticks.
    public sealed class StoryOverlay : MonoBehaviour
    {
        static readonly Color Ink = new Color(.149f, .227f, .196f);
        static readonly Color Paper = new Color(.949f, .933f, .898f);
        static readonly Color Gold = new Color(.835f, .651f, .290f);
        static readonly Color Green = new Color(.37f, .60f, .43f);
        static readonly Color Water = new Color(.33f, .69f, .83f);
        RectTransform _root, _play, _stage, _art, _choices, _notebook;
        Text _line, _title, _notice, _guideText;
        RawImage _guide;
        string _portraitPath;
        Button _resume, _book;
        StoryVoice _voice;
        Font _font;
        Sprite _round;
        AppState _state;
        bool _blocked, _waiting;
        string _key, _bookKey, _waitingRequest, _selectedCardTopic;
        float _waitingSince;
        float _started;
        readonly List<Action<float>> _motions = new List<Action<float>>();
        readonly List<Button> _choiceButtons = new List<Button>();
        public event Action LayoutChanged;
        public static bool CapturingInput { get; private set; }
        public bool ShowingNotebook => HasManualNotebook(_state) && !ShowsStory(_state) && !_blocked;
        public void ToggleNotebook()
        {
            var story = _state?.story;
            if (story == null || _blocked || (!story.notebookOpen && !story.canOpen)) return;
            AppSession.Request("storyNotebook", new AppAction { open = !story.notebookOpen });
        }

        public void StartAvailableStory()
        {
            var story = _state?.story;
            if (_blocked || !HasManualNotebook(_state) || !story.ready || !story.canPlay || story.pending || _state.busy) return;
            if (story.paused && story.topicId == "coast_sail") Request("storyResume");
            else Request("storyStart", null, "coast_sail");
        }

        static bool CanPresent(AppState state) => state != null && state.ready && state.connected &&
            state.view == "cabin" && !state.sessionEnded && state.story != null &&
            state.egg?.photoRequired != true && state.egg?.photoBusy != true && state.egg?.speechBusy != true &&
            state.learning?.busy != true && state.learning?.recording != true;
        public static bool HasManualNotebook(AppState state) => CanPresent(state) && state.story.notebookOpen;
        public static bool ShowsStory(AppState state) => CanPresent(state) && state.story.ready &&
            state.story.active && !state.story.paused && state.story.topicId == "coast_sail";
        public static bool OwnsInput(AppState state) => HasManualNotebook(state) || ShowsStory(state);
        public static string RenderKey(StoryState story) => story == null ? "" : story.instanceId + ":" + story.nodeId + ":" + story.variant;

        static string NotebookKey(StoryState story)
        {
            if (story == null) return "";
            var key = new StringBuilder().Append(story.ready).Append(story.canPlay).Append(story.pending)
                .Append(story.paused).Append(story.instanceId).Append(story.error).Append(story.notice);
            foreach (var card in story.savedCards ?? Array.Empty<StoryCard>()) key.Append(JsonUtility.ToJson(card));
            foreach (var card in story.library ?? Array.Empty<StoryCard>()) key.Append(JsonUtility.ToJson(card));
            return key.ToString();
        }

        public void Initialize(RectTransform safe, Font font, Sprite round)
        {
            _font = font; _round = round;
            _voice = gameObject.AddComponent<StoryVoice>();
            _root = Box("Story presentation", safe, Vector2.zero, Vector2.one, new Vector2(14, 20), new Vector2(-126, -78));
            _root.gameObject.AddComponent<Image>().color = new Color(.07f,.12f,.10f,.82f);
            _book = Button(_root, "돌봄으로", ToggleNotebook, Paper);
            Place(_book.transform, new Vector2(1, 1), new Vector2(1, 1), new Vector2(-216, -64), new Vector2(-8, -8));
            _play = Box("Story play", _root, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            var heading = Box("Story heading", _play, new Vector2(.35f, 1), Vector2.one, new Vector2(0, -110), new Vector2(-8, 0));
            _title = Text(heading, "", 25, TextAnchor.MiddleLeft, Paper);
            Place(_title.transform, Vector2.zero, Vector2.one, Vector2.zero, new Vector2(-220, 0));
            _resume = Button(heading, "돌봄으로", () => Request("storyPause"), Paper);
            Place(_resume.transform, new Vector2(1, 0), Vector2.one, new Vector2(-210, 0), Vector2.zero);
            _stage = Box("Experiment stage", _play, new Vector2(.29f, 0), Vector2.one, new Vector2(0, 222), new Vector2(-8, -116));
            var stageBg = _stage.gameObject.AddComponent<Image>(); stageBg.sprite = _round; stageBg.type = Image.Type.Sliced; stageBg.color = new Color(.08f, .17f, .19f, .87f); stageBg.raycastTarget = false;
            _art = Box("Experiment art", _stage, new Vector2(.5f,.5f), new Vector2(.5f,.5f), new Vector2(-340,-125), new Vector2(340,125));
            var dock = Box("Story dialogue dock", _play, Vector2.zero, new Vector2(1, 0), new Vector2(8, 0), new Vector2(-8, 212));
            var bg = dock.gameObject.AddComponent<Image>(); bg.sprite = _round; bg.type = Image.Type.Sliced; bg.color = Paper;
            _line = Text(dock, "", 30, TextAnchor.MiddleLeft, Ink);
            Place(_line.transform, new Vector2(0, 1), Vector2.one, new Vector2(24, -86), new Vector2(-24, -8));
            _choices = Box("Story choices", dock, Vector2.zero, Vector2.one, new Vector2(16, 8), new Vector2(-16, -92));
            var noticePanel = Box("Story guide note", _play, new Vector2(0, 0), new Vector2(.29f, 1), new Vector2(8, 220), new Vector2(-12, -325));
            var noteBg = noticePanel.gameObject.AddComponent<Image>(); noteBg.sprite=_round; noteBg.type=Image.Type.Sliced; noteBg.color=new Color(.08f,.17f,.19f,.92f); noteBg.raycastTarget=false;
            _notice = Text(noticePanel, "", 21, TextAnchor.MiddleLeft, Paper);
            _notice.resizeTextForBestFit = true; _notice.resizeTextMinSize = 15; _notice.resizeTextMaxSize = 21;
            Place(_notice.transform, Vector2.zero, Vector2.one, new Vector2(14,8), new Vector2(-14,-8));
            // Fit only inside this bounded viewport, never against the full story surface.
            var portrait = Box("Story guide viewport", _play, new Vector2(0,0), new Vector2(.29f,1), new Vector2(20,338),new Vector2(-20,-175));
            portrait.gameObject.AddComponent<RectMask2D>();
            var artwork = Box("Story guide artwork", portrait, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            _guide = artwork.gameObject.AddComponent<RawImage>(); _guide.raycastTarget=false; _guide.color=Color.clear;
            var aspect = artwork.gameObject.AddComponent<AspectRatioFitter>(); aspect.aspectMode=AspectRatioFitter.AspectMode.FitInParent; aspect.aspectRatio=1;
            var guideLabel = Box("Story guide label", _play, new Vector2(0,0), new Vector2(.29f,0), new Vector2(8,300),new Vector2(-12,338));
            var labelBg = guideLabel.gameObject.AddComponent<Image>(); labelBg.sprite=_round; labelBg.type=Image.Type.Sliced; labelBg.color=new Color(.08f,.17f,.19f,.92f); labelBg.raycastTarget=false;
            _guideText = Text(guideLabel,"길싹이 · 이야기 안내",23,TextAnchor.MiddleCenter,Paper);
            _notebook = Box("Travel notebook", _root, Vector2.zero, Vector2.one, new Vector2(8, 8), new Vector2(-8, -76));
            var bookBg = _notebook.gameObject.AddComponent<Image>(); bookBg.sprite = _round; bookBg.type = Image.Type.Sliced; bookBg.color = Paper;
            _play.gameObject.SetActive(false); _notebook.gameObject.SetActive(false); _root.gameObject.SetActive(false);
        }

        public void Apply(AppState state, bool blocked)
        {
            var wasNotebook = ShowingNotebook;
            _state = state; _blocked = blocked;
            if (!HasManualNotebook(state)) { _selectedCardTopic = null; _bookKey = null; }
            Refresh();
            if (wasNotebook != ShowingNotebook) LayoutChanged?.Invoke();
        }

        void Refresh()
        {
            if (_root == null) return;
            var visible = OwnsInput(_state) && !_blocked;
            _root.gameObject.SetActive(visible);
            CapturingInput = visible;
            var playing = visible && ShowsStory(_state);
            _voice.Present(_state?.story, playing);
            _play.gameObject.SetActive(playing);
            _notebook.gameObject.SetActive(visible && !playing);
            if (!visible) return;
            var s = _state.story;
            if (_waiting && !string.IsNullOrEmpty(_waitingRequest) && s.ackRequestId == _waitingRequest) { _waiting=false; _waitingRequest=null; }
            _book.interactable = true;
            _book.gameObject.SetActive(!playing);
            if (!playing && _bookKey != NotebookKey(s))
            {
                var card = Array.Find(s.savedCards ?? Array.Empty<StoryCard>(), c => c.topicId == _selectedCardTopic);
                if (card != null) ShowCard(card); else BuildNotebook();
            }
            if (!playing) return;
            UpdateGuide();
            var key = RenderKey(s);
            if (key != _key)
            {
                _key = key; _waiting = false;
                _started = Time.unscaledTime;
                BuildChoices(s);
                BuildArt(s.visual, s.variant);
            }
            _title.gameObject.SetActive(string.IsNullOrEmpty(_state.error) && string.IsNullOrEmpty(_state.notice) && !_state.busy);
            _title.text = s.title + (s.nodeId == "prediction" ? "\n<size=18>내 예상 고르기</size>" : "\n<size=18>상상 탐험 · 화면 속 실험</size>");
            _line.text = s.line;
            _notice.text = !string.IsNullOrEmpty(s.notice) ? s.notice : !string.IsNullOrEmpty(s.cardTitle) && (s.nodeId == "saved" || s.nodeId == "more") ? s.cardTitle + "\n\n" + s.cardText : !string.IsNullOrEmpty(s.prediction) ? "내 예상\n" + s.prediction : "같은 배·바람·시간,\n돛만 바꾸어 보자.";
            foreach (var button in _choiceButtons) button.interactable = !_waiting && !s.pending && s.canPlay;
            _resume.interactable = true;
        }

        void Update()
        {
            if (_waiting && Time.unscaledTime - _waitingSince > 5f) { _waiting=false; _waitingRequest=null; Refresh(); }
            if (_art == null || !_play.gameObject.activeInHierarchy) return;
            var scale = Mathf.Min(_stage.rect.width / 700f, _stage.rect.height / 270f);
            _art.localScale = Vector3.one * Mathf.Max(.1f, scale);
            var t = _state != null && _state.reducedMotion ? 1f : Mathf.Clamp01((Time.unscaledTime - _started) / 1.8f);
            foreach (var motion in _motions) motion(t);
        }

        void OnDisable() { CapturingInput = false; if (_voice != null) _voice.Present(null, false); }
        void OnDestroy() { if (_root != null) { if(Application.isPlaying) Destroy(_root.gameObject); else DestroyImmediate(_root.gameObject); } CapturingInput = false; }

        void Request(string action, string actionId = null, string topicId = null)
        {
            var s = _state?.story;
            if (s == null || _blocked || !OwnsInput(_state)) return;
            if ((action == "storyStart" || action == "storyReplay") && topicId != "coast_sail") return;
            if (action == "storyResume" && s.topicId != "coast_sail") return;
            if (action != "storyPause" && action != "storyClose" && (!s.ready || !s.canPlay || s.pending || _state.busy)) return;
            if (action == "storyStart" && s.paused && topicId == null) action = "storyResume";
            if (action == "storyChoose")
            {
                if (_waiting || s.pending) return;
                _waiting = true; _waitingSince = Time.unscaledTime;
                foreach (var b in _choiceButtons) b.interactable = false;
            }
            if (action == "storyChoose" || action == "storyPause" || action == "storyClose") _voice.Stop();
            var requestId = AppSession.Request(action, new AppAction { instanceId = s.instanceId, nodeId = s.nodeId, storyRevision = s.revision, actionId = actionId, topicId = topicId ?? s.topicId });
            if(action == "storyChoose") _waitingRequest=requestId;
            Refresh();
        }

        void UpdateGuide()
        {
            var narration = _voice.Narrator(_state?.story);
            var path = NarratorPortrait(narration);
            _guideText.text = narration != null ? NarratorName(narration) + " · 이야기 안내" : "이야기 안내";
            if(path==_portraitPath || !Application.isPlaying) return;
            _portraitPath=path; _guide.color=Color.clear; _guide.texture=null;
            if (string.IsNullOrEmpty(path)) return;
            StartCoroutine(SpriteLoader.Load(path, art=>
            {
                if(_guide==null || _portraitPath!=path) return;
                _guide.texture=art[ArtPose.Idle];_guide.color=Color.white;
                _guide.GetComponent<AspectRatioFitter>().aspectRatio=art.Aspect;
            }));
        }

        public static string NarratorPortrait(string species)
        {
            // Only use this narrator's own bundled artwork; never substitute a companion.
            switch (species)
            {
                case "road_sprout": case "puddle_pip": case "highway_comet":
                    return "species/" + species + ".png";
                default: return null;
            }
        }

        static string NarratorName(string species)
        {
            switch (species)
            {
                case "road_sprout": return "길싹이";
                case "bridge_hopper": return "다리뛰기";
                case "mountain_sprite": return "산정령";
                case "puddle_pip": return "웅덩이삐약";
                case "tide_keeper": return "물결지기";
                case "tunnel_moth": return "터널나방";
                case "star_owl": return "별부엉이";
                case "highway_comet": return "고속혜성";
                default: return "이야기 친구";
            }
        }

        void BuildChoices(StoryState s)
        {
            Clear(_choices); _choiceButtons.Clear();
            var choices = s.choices ?? Array.Empty<StoryChoice>();
            for (int i = 0; i < Math.Min(2, choices.Length); i++)
            {
                var choice = choices[i];
                var button = Button(_choices, choice.label, () => Request("storyChoose", choice.id), i == 0 ? Gold : new Color(.77f,.87f,.80f));
                Place(button.transform, new Vector2(i / (float)choices.Length, 0), new Vector2((i+1) / (float)choices.Length, 1), new Vector2(5,0), new Vector2(-5,0));
                _choiceButtons.Add(button);
            }
        }

        void BuildNotebook()
        {
            Clear(_notebook); _selectedCardTopic=null; _bookKey=NotebookKey(_state.story);
            var s=_state.story;
            var title=Text(_notebook,"탐험 노트",28,TextAnchor.MiddleLeft,Ink);
            Place(title.transform,new Vector2(0,1),Vector2.one,new Vector2(22,-54),new Vector2(-22,-8));
            var content=ScrollContent(_notebook,60,12);
            if (!s.ready)
            {
                NotebookRow(content,string.IsNullOrEmpty(s.error) ? "탐험 노트를 불러오고 있어요." : "탐험 노트를 불러오지 못했어요. 다시 불러와 주세요.");
                var retry=Button(content,"다시 불러오기",()=>AppSession.Request("storyRetry"),Gold);
                RowHeight(retry.transform,64); retry.interactable=!string.IsNullOrEmpty(s.error);
                return;
            }
            NotebookRow(content,"같은 바람에서 돛을 바꾸어 보는 상상 실험이에요.");
            if (s.paused && s.topicId == "coast_sail")
            {
                var resume=Button(content,"이어 하기",()=>Request("storyResume"),Gold);
                RowHeight(resume.transform,64); resume.interactable=s.canPlay && !s.pending;
                var close=Button(content,"탐험 마치기",()=>Request("storyClose"),new Color(.78f,.88f,.79f));
                RowHeight(close.transform,64);
            }
            if (!string.IsNullOrEmpty(s.notice)) NotebookRow(content,s.notice);
            var saved=s.savedCards ?? Array.Empty<StoryCard>();
            foreach (var item in s.library ?? Array.Empty<StoryCard>())
            {
                if (item.topicId != "coast_sail") continue;
                var card=Array.Find(saved,c=>c.topicId==item.topicId);
                AddNotebookCard(content,item,card,s);
            }
            foreach (var card in saved)
            {
                if (Array.Exists(s.library ?? Array.Empty<StoryCard>(), item=>item.topicId==card.topicId && item.topicId=="coast_sail")) continue;
                AddNotebookCard(content,card,card,s);
            }
        }

        void AddNotebookCard(RectTransform content,StoryCard item,StoryCard card,StoryState s)
        {
            var button=Button(content,(card != null ? "발견 · " : "상상 탐험 · ")+item.title,
                ()=>{if(card != null) ShowCard(card); else Request("storyStart",null,item.topicId);},
                card != null ? new Color(.78f,.88f,.79f) : Gold);
            RowHeight(button.transform,76);
            button.interactable=card != null || (item.topicId=="coast_sail" && s.canPlay && !s.paused && !s.pending && !_state.busy);
        }

        void ShowCard(StoryCard card)
        {
            Clear(_notebook); _selectedCardTopic=card.topicId; _bookKey=NotebookKey(_state.story);
            var title=Text(_notebook,"발견 카드 · "+card.title,28,TextAnchor.MiddleLeft,Ink);
            Place(title.transform,new Vector2(0,1),Vector2.one,new Vector2(22,-54),new Vector2(-22,-8));
            var content=ScrollContent(_notebook,60,92);
            bool personal=!string.IsNullOrEmpty(card.prediction) || !string.IsNullOrEmpty(card.firstAction) || !string.IsNullOrEmpty(card.observation) || !string.IsNullOrEmpty(card.principle) || !string.IsNullOrEmpty(card.nextQuestion);
            if (!personal) NotebookRow(content,card.text);
            else
            {
                EvidenceRow(content,"내 예상",card.prediction);
                EvidenceRow(content,"먼저 해본 것",card.firstAction);
                EvidenceRow(content,"비교한 결과",card.observation);
                EvidenceRow(content,"알아본 원리",string.IsNullOrEmpty(card.principle) ? card.text : card.principle);
                EvidenceRow(content,"다음에 생각해 볼 것",card.nextQuestion);
            }
            var back=Button(_notebook,"목록으로",BuildNotebook,new Color(.78f,.88f,.79f));
            Place(back.transform,Vector2.zero,new Vector2(.5f,0),new Vector2(20,12),new Vector2(-8,80));
            var replay=Button(_notebook,"다시 실험하기",()=>
            {
                var intent=CardReplayIntent(_state,card);
                if (intent != null) Request(intent.action,null,intent.topicId);
            },Gold);
            Place(replay.transform,new Vector2(.5f,0),new Vector2(1,0),new Vector2(8,12),new Vector2(-20,80));
            replay.interactable=CardReplayIntent(_state,card) != null;
        }

        public static AppAction CardReplayIntent(AppState state,StoryCard card) =>
            !HasManualNotebook(state) || card?.topicId != "coast_sail" || !state.story.ready ||
            !state.story.canPlay || state.story.paused || state.story.pending || state.busy ? null :
            new AppAction { action="storyStart", topicId=card.topicId };

        void EvidenceRow(RectTransform content,string label,string value)
        { if (!string.IsNullOrEmpty(value)) NotebookRow(content,label+": "+value); }
        void NotebookRow(RectTransform content,string value)
        {
            var text=Text(content,value,27,TextAnchor.UpperLeft,Ink); text.lineSpacing=1.15f;
            text.gameObject.AddComponent<LayoutElement>().minHeight=64;
        }
        static void RowHeight(Transform item,float height)
        { var layout=item.gameObject.AddComponent<LayoutElement>();layout.minHeight=layout.preferredHeight=height; }
        RectTransform ScrollContent(RectTransform parent,float top,float bottom)
        {
            var scrollRoot=Box("Notebook scroll",parent,Vector2.zero,Vector2.one,new Vector2(18,bottom),new Vector2(-18,-top));
            var scroll=scrollRoot.gameObject.AddComponent<ScrollRect>(); scroll.horizontal=false;scroll.movementType=ScrollRect.MovementType.Clamped;
            var viewport=Box("Notebook viewport",scrollRoot,Vector2.zero,Vector2.one,Vector2.zero,new Vector2(-22,0));
            viewport.gameObject.AddComponent<Image>().color=Color.clear;viewport.gameObject.AddComponent<RectMask2D>();
            var content=Box("Notebook rows",viewport,new Vector2(0,1),Vector2.one,Vector2.zero,Vector2.zero);content.pivot=new Vector2(.5f,1);
            var layout=content.gameObject.AddComponent<VerticalLayoutGroup>();layout.spacing=16;layout.padding=new RectOffset(8,12,12,12);
            layout.childControlWidth=true;layout.childControlHeight=true;layout.childForceExpandWidth=true;layout.childForceExpandHeight=false;
            var fit=content.gameObject.AddComponent<ContentSizeFitter>();fit.verticalFit=ContentSizeFitter.FitMode.PreferredSize;
            scroll.viewport=viewport;scroll.content=content;
            var track=Box("Notebook scrollbar",scrollRoot,new Vector2(1,0),Vector2.one,new Vector2(-12,0),Vector2.zero);
            track.gameObject.AddComponent<Image>().color=new Color(.72f,.72f,.65f,.45f);
            var handle=Box("Notebook scroll handle",track,Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero);handle.gameObject.AddComponent<Image>().color=Green;
            var bar=track.gameObject.AddComponent<Scrollbar>();bar.handleRect=handle;bar.targetGraphic=handle.GetComponent<Image>();bar.direction=Scrollbar.Direction.BottomToTop;
            scroll.verticalScrollbar=bar;scroll.verticalScrollbarVisibility=ScrollRect.ScrollbarVisibility.AutoHide;
            return content;
        }

        // Flat toy theatre. All movement is normalized, deterministic presentation of the authored result.
        void BuildArt(string topic, string variant)
        {
            Clear(_art); _motions.Clear();
            bool both = variant == "both", a = variant != "b";
            if (both)
            {
                var left = ArtGroup(-170, .48f); var right = ArtGroup(170, .48f);
                DrawExperiment(left, topic, true); DrawExperiment(right, topic, false);
                Caption(_art, "두 가지 결과를 나란히 비교해 보자", 0, -106, 21);
            }
            else DrawExperiment(_art, topic, a);
            if (variant == "neutral") _motions.Clear();
        }
        RectTransform ArtGroup(float x, float scale)
        {
            var r = Box("Comparison", _art, new Vector2(.5f,.5f),new Vector2(.5f,.5f),new Vector2(x-340,-125),new Vector2(x+340,125)); r.localScale = Vector3.one*scale; return r;
        }
        void DrawExperiment(RectTransform p, string topic, bool a)
        {
            switch(topic)
            {
                case "coast_sail":
                    Shape(p, "Sea", 0,-68,640,45,Water);
                    var boat=Group(p,"Mail boat",-210,-15);
                    Shape(boat,"Hull",0,-23,108,34,new Color(.68f,.38f,.21f));
                    Shape(boat,"Mast",0,22,6,90,Paper);
                    Shape(boat,"Sail",28,35,a?67:12,65,Gold,2);
                    Shape(boat,"Letter",-22,2,28,20,Paper);
                    _motions.Add(t=>boat.anchoredPosition=new Vector2(Mathf.Lerp(-210,a?200:-100,t),-15));
                    Caption(p,a?"돛 펼치기 · 같은 바람":"돛 접기 · 같은 바람",0,95); break;
                case "road_seed":
                    Shape(p,"Ground",0,-88,640,16,Green);
                    var seed=Group(p,"Seed",-160,60); Shape(seed,"Seed body",0,0,24,32,Gold,1);
                    if(a) { var wing=Shape(seed,"Wing",26,15,66,17,Paper,1); wing.localEulerAngles=new Vector3(0,0,25); }
                    _motions.Add(t=>seed.anchoredPosition=new Vector2(Mathf.Lerp(-160,a?180:-120,t),Mathf.Lerp(60,-65,a?t*t:Mathf.Min(1,t*2))));
                    Caption(p,a?"날개 있는 씨앗":"둥근 씨앗",0,108); break;
                case "mountain_soil":
                    Shape(p,"Soil hill",-40,-20,310,155,new Color(.57f,.37f,.23f),2);
                    if(a) for(int i=0;i<7;i++) { var blade=Shape(p,"Grass",-170+i*40,-69+i*17,9,30,Green); blade.localEulerAngles=new Vector3(0,0,-18); }
                    Rain(p,-180,85,6);
                    for(int i=0;i<(a?3:12);i++){ var soil=Shape(p,"Washed soil",140+i*10,-70,8,8,new Color(.65f,.42f,.24f),1); var start=soil.anchoredPosition; _motions.Add(t=>soil.anchoredPosition=start+new Vector2(t*35,-t*8)); }
                    Caption(p,a?"풀 있는 언덕 · 흙이 덜 씻겨 감":"맨흙 언덕 · 흙이 더 씻겨 감",0,105); break;
                case "city_bridge":
                    Shape(p,"Left support",-220,-46,35,105,Green); Shape(p,"Right support",220,-46,35,105,Green);
                    if(a) Shape(p,"Center support",0,-46,35,105,Green);
                    for(int i=0;i<9;i++) Shape(p,"Deck",-220+i*55,a?15:15-Mathf.Sin(i/8f*Mathf.PI)*28,58,13,Gold);
                    var train=Group(p,"Cookie train",-180,42); Shape(train,"Train",0,0,75,40,Water); Shape(train,"Cookie",0,26,28,28,Gold,1);
                    Shape(train,"Wheel",-22,-25,18,18,Ink,1);Shape(train,"Wheel",22,-25,18,18,Ink,1);
                    _motions.Add(t=>train.anchoredPosition=new Vector2(Mathf.Lerp(-180,a?180:0,t),a?42:42-Mathf.Sin(t*Mathf.PI/2)*28));
                    Caption(p,a?"가운데 받침 있음":"가운데 받침 없음",0,105); break;
                case "tunnel_shadow":
                    Shape(p,"Screen",205,0,170,190,Paper);
                    Bunny(p,205,-20,a?1.5f:.65f,Ink);
                    Bunny(p,0,-30,.45f,Gold);
                    Shape(p,"Light",a?-80:-220,-20,35,35,Gold,1);
                    Caption(p,a?"빛 가까이 · 큰 그림자":"빛 멀리 · 작은 그림자",0,110); break;
                case "rain_path":
                    Shape(p,"Surface",0,-30,560,70,a?new Color(.53f,.36f,.24f):new Color(.43f,.48f,.51f));
                    Rain(p,-220,95,9);
                    for(int i=0;i<10;i++){ var drop=Shape(p,"Water route",-200+i*42,-7,10,14,Water,1);var origin=drop.anchoredPosition; _motions.Add(t=>drop.anchoredPosition=origin+(a?new Vector2(0,-t*50):new Vector2(t*70,0))); }
                    Caption(p,a?"흙길 · 물이 틈으로 스며듦":"포장길 · 물이 표면으로 흐름",0,112); break;
                case "night_stars":
                    Shape(p,"Night sky",0,0,620,200,a?new Color(.06f,.10f,.23f):new Color(.42f,.48f,.59f));
                    for(int i=0;i<22;i++){var c=i%4==0?Paper:a?new Color(.8f,.84f,.64f):new Color(.46f,.51f,.60f); Shape(p,"Star",-275+(i*83)%550,15+(i*37)%75,i%4==0?8:4,i%4==0?8:4,c,1);}
                    for(int i=0;i<9;i++)Shape(p,"Town",-260+i*65,-65,38,25+(i%3)*12,Ink);
                    Caption(p,a?"주변 조명 낮음":"주변 조명 높음",0,118); break;
                case "highway_view":
                    Shape(p,"Road",0,-80,640,18,Paper);
                    var mountain=Shape(p,"Far mountain",110,20,170,100,new Color(.47f,.65f,.67f),2);
                    var tree=Group(p,"Near tree",140,-8);Shape(tree,"Trunk",0,-30,12,70,new Color(.57f,.37f,.23f));Shape(tree,"Leaves",0,12,80,95,Green,2);
                    _motions.Add(t=>{mountain.anchoredPosition=new Vector2(110-t*45,20);tree.anchoredPosition=new Vector2(140-t*360,-8);});
                    var marker=Shape(p,"Observation marker",a?140:110,a?80:90,22,22,Gold,1);
                    _motions.Add(t=>marker.anchoredPosition=new Vector2(a?140-t*360:110-t*45,a?80:90));
                    Caption(p,a?"가까운 나무 관찰":"먼 산 관찰",0,118); break;
                default: Caption(p,"작은 실험을 준비했어",0,0); break;
            }
        }
        void Rain(RectTransform p,float x,float y,int count)
        { for(int i=0;i<count;i++){var d=Shape(p,"Raindrop",x+i*43,y,7,16,Water,1);var origin=d.anchoredPosition;_motions.Add(t=>d.anchoredPosition=origin+new Vector2(0,-t*110));} }
        void Bunny(RectTransform p,float x,float y,float scale,Color c)
        { var r=Group(p,"Rabbit",x,y);r.localScale=Vector3.one*scale;Shape(r,"Body",0,0,48,60,c,1);Shape(r,"Head",0,38,40,38,c,1);Shape(r,"Ear",-12,73,12,55,c,1);Shape(r,"Ear",12,73,12,55,c,1); }
        RectTransform Group(RectTransform p,string name,float x,float y) => Box(name,p,new Vector2(.5f,.5f),new Vector2(.5f,.5f),new Vector2(x,y),new Vector2(x,y));
        void Caption(RectTransform p,string value,float x,float y,int size=23)
        {var t=Text(p,value,size,TextAnchor.MiddleCenter,Paper);Place(t.transform,new Vector2(.5f,.5f),new Vector2(.5f,.5f),new Vector2(x-330,y-17),new Vector2(x+330,y+17));}
        RectTransform Shape(RectTransform p,string name,float x,float y,float w,float h,Color c,int kind=0)
        {var r=Box(name,p,new Vector2(.5f,.5f),new Vector2(.5f,.5f),new Vector2(x-w/2,y-h/2),new Vector2(x+w/2,y+h/2));var g=r.gameObject.AddComponent<StoryShape>();g.color=c;g.kind=kind;g.raycastTarget=false;return r;}
        static RectTransform Box(string name,Transform parent,Vector2 min,Vector2 max,Vector2 low,Vector2 high)
        {var go=new GameObject(name,typeof(RectTransform));go.transform.SetParent(parent,false);Place(go.transform,min,max,low,high);return(RectTransform)go.transform;}
        static void Place(Transform t,Vector2 min,Vector2 max,Vector2 low,Vector2 high)
        {var r=(RectTransform)t;r.anchorMin=min;r.anchorMax=max;r.offsetMin=low;r.offsetMax=high;}
        Text Text(Transform parent,string value,int size,TextAnchor align,Color color)
        {var r=Box("Text",parent,Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero);var t=r.gameObject.AddComponent<Text>();t.font=_font;t.text=value;t.fontSize=size;t.alignment=align;t.color=color;t.raycastTarget=false;t.supportRichText=true;t.horizontalOverflow=HorizontalWrapMode.Wrap;t.verticalOverflow=VerticalWrapMode.Truncate;return t;}
        Button Button(Transform parent,string label,Action action,Color color)
        {var r=Box(label,parent,Vector2.zero,Vector2.one,Vector2.zero,Vector2.zero);var image=r.gameObject.AddComponent<Image>();image.sprite=_round;image.type=Image.Type.Sliced;image.color=color;var button=r.gameObject.AddComponent<Button>();button.targetGraphic=image;button.onClick.AddListener(()=>action());var text=Text(r,label,25,TextAnchor.MiddleCenter,Ink);Place(text.transform,Vector2.zero,Vector2.one,new Vector2(10,6),new Vector2(-10,-6));return button;}
        static void Clear(Transform parent){for(int i=parent.childCount-1;i>=0;i--){var child=parent.GetChild(i);child.gameObject.SetActive(false);if(Application.isPlaying) Destroy(child.gameObject);else DestroyImmediate(child.gameObject);}}
    }

    /// Simple original toy shapes; no asset downloads or external rendering dependency.
    public sealed class StoryShape : Graphic
    {
        public int kind;
        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();var r=rectTransform.rect;
            if(kind==1)
            { vh.AddVert(r.center,color,Vector2.zero);const int n=32;for(int i=0;i<n;i++){float a=i*Mathf.PI*2/n;vh.AddVert(r.center+new Vector2(Mathf.Cos(a)*r.width/2,Mathf.Sin(a)*r.height/2),color,Vector2.zero);}for(int i=0;i<n;i++)vh.AddTriangle(0,i+1,(i+1)%n+1); }
            else if(kind==2)
            {vh.AddVert(new Vector2(r.xMin,r.yMin),color,Vector2.zero);vh.AddVert(new Vector2(r.xMax,r.yMin),color,Vector2.zero);vh.AddVert(new Vector2(r.center.x,r.yMax),color,Vector2.zero);vh.AddTriangle(0,1,2);}
            else {vh.AddVert(new Vector2(r.xMin,r.yMin),color,Vector2.zero);vh.AddVert(new Vector2(r.xMax,r.yMin),color,Vector2.zero);vh.AddVert(new Vector2(r.xMax,r.yMax),color,Vector2.zero);vh.AddVert(new Vector2(r.xMin,r.yMax),color,Vector2.zero);vh.AddTriangle(0,1,2);vh.AddTriangle(0,2,3);}
        }
    }
}
