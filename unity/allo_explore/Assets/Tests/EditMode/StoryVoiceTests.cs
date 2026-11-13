using Allo.App;
using NUnit.Framework;
using UnityEngine;

public class StoryVoiceTests
{
    [Test] public void BuiltExploreSceneHasOneEnabledAudioListener()
    {
        var scene = UnityEditor.SceneManagement.EditorSceneManager.OpenScene("Assets/Scenes/Explore.unity", UnityEditor.SceneManagement.OpenSceneMode.Additive);
        try
        {
            var count = 0;
            foreach (var root in scene.GetRootGameObjects())
                foreach (var listener in root.GetComponentsInChildren<AudioListener>())
                    if (listener.enabled) count++;
            Assert.AreEqual(1, count, "Narration requires one active listener in the exported scene.");
        }
        finally { UnityEditor.SceneManagement.EditorSceneManager.CloseScene(scene, true); }
    }

    [Test] public void NarratorPortraitNeverSubstitutesAnotherSpecies()
    {
        Assert.AreEqual("species/road_sprout.png", StoryOverlay.NarratorPortrait("road_sprout"));
        Assert.AreEqual("species/puddle_pip.png", StoryOverlay.NarratorPortrait("puddle_pip"));
        Assert.AreEqual("species/highway_comet.png", StoryOverlay.NarratorPortrait("highway_comet"));
        foreach (var species in new[]{"tide_keeper","mountain_sprite","bridge_hopper","tunnel_moth","star_owl"})
            Assert.IsNull(StoryOverlay.NarratorPortrait(species));
    }
    [Test] public void CatalogRejectsChangedTextAndUnmatchedEndings()
    {
        var catalog = JsonUtility.FromJson<StoryVoiceCatalog>(Resources.Load<TextAsset>("StoryVoice/catalog").text);
        Assert.AreEqual(102, catalog.entries.Length);
        var state = new StoryState { topicId="road_seed",nodeId="intro",line="여긴 상상 작업실이야. 씨앗 모형이 여행을 준비해." };
        Assert.AreEqual("road_sprout",catalog.Find(state).species);
        state.line += "!"; Assert.IsNull(catalog.Find(state));
        Assert.IsNull(catalog.Find(new StoryState {topicId="rain_path",nodeId="ending",line="물방울 여행 지도 완성! 땅속 길도 있었네."}));
        Assert.IsNull(catalog.Find(new StoryState {topicId="night_stars",nodeId="ending",line="별이 숨은 게 아니라 빛에 가려 보였구나."}));
        foreach (var entry in catalog.entries) Assert.NotNull(Resources.Load<AudioClip>(entry.resource), entry.resource);
    }
    [Test] public void VehicleUpdatesDoNotReplayButResumeAndNewSessionsDo()
    {
        var cursor = new StoryVoiceCursor();
        var s = new StoryState {instanceId="a",topicId="road_seed",nodeId="intro",line="안녕"};
        Assert.IsTrue(cursor.Enter(s,true));
        s.revision++; Assert.IsFalse(cursor.Enter(s,true));
        Assert.IsFalse(cursor.Enter(s,false)); Assert.IsTrue(cursor.Enter(s,true));
        s.nodeId="choose"; Assert.IsTrue(cursor.Enter(s,true));
        s.instanceId="b"; Assert.IsTrue(cursor.Enter(s,true));
    }
}
