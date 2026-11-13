using Allo.App;
using NUnit.Framework;
using UnityEngine;

public class StoryVoiceTests
{
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
