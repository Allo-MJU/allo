using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Allo.App;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

public class AppUiVillageSelectionTests
{
    const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    GameObject _root;
    AppUi _ui;
    AppState _state, _previous;
    [SetUp] public void SetUp()
    {
        _previous = AppSession.State;
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, null);
        _state = JsonUtility.FromJson<AppState>("{\"revision\":1,\"view\":\"home\",\"ready\":true,\"villageSelectionReady\":true,\"villageCreatureIds\":[\"friend-4\"],\"creatures\":[{\"id\":\"friend-0\",\"speciesId\":\"road_sprout\",\"name\":\"첫 친구\"},{\"id\":\"friend-1\",\"speciesId\":\"road_sprout\",\"name\":\"두 번째 친구\"},{\"id\":\"friend-2\",\"name\":\"친구 3\"},{\"id\":\"friend-3\",\"name\":\"친구 4\"},{\"id\":\"friend-4\",\"name\":\"친구 5\"}]}");
        AppSession.Receive(_state);
        _root = new GameObject("Village selection test"); _ui = _root.AddComponent<AppUi>();
        if (Get<RectTransform>("_safe") == null) Call("Awake");
        Call("OnState", _state); Build();
    }
    [TearDown] public void TearDown()
    {
        Object.DestroyImmediate(_root);
        typeof(AppSession).GetProperty(nameof(AppSession.State)).SetValue(null, _previous);
    }
    [Test] public void MapRendersSelectedExactOwnedIdsOnly()
    {
        CollectionAssert.AreEqual(new[] { "friend-4" }, Get<Dictionary<string, RectTransform>>("_villageFriends").Keys);
        var empty = JsonUtility.FromJson<AppState>(JsonUtility.ToJson(_state).Replace("[\"friend-4\"]", "[]"));
        Call("OnState", empty); Build();
        Assert.IsEmpty(Get<Dictionary<string, RectTransform>>("_villageFriends"));
    }
    [Test] public void SelectorLimitsToFourAndCancelKeepsAuthoritativeSelection()
    {
        ButtonNamed("마을 친구 선택").onClick.Invoke(); Build();
        foreach (var id in new[] { "friend-0", "friend-1", "friend-2" }) Choice(id).onClick.Invoke();
        Build();
        Assert.IsFalse(Choice("friend-3").interactable);
        Assert.IsTrue(_root.GetComponentsInChildren<Text>().Any(t => t.text == "선택 4 / 4"));
        ButtonNamed("취소").onClick.Invoke(); Build();
        Assert.IsNull(Named("Village friend selector"));
        CollectionAssert.AreEqual(new[] { "friend-4" }, Get<Dictionary<string, RectTransform>>("_villageFriends").Keys);
    }
    [Test] public void SaveKeepsDraftAndOldMapUntilConfirmedSnapshot()
    {
        ButtonNamed("마을 친구 선택").onClick.Invoke(); Build();
        Choice("friend-4").onClick.Invoke(); Build();
        Assert.IsTrue(_root.GetComponentsInChildren<Text>().Any(t => t.text == "선택 0 / 4"));
        ButtonNamed("저장").onClick.Invoke();
        CollectionAssert.AreEqual(new[] { "friend-4" }, Get<Dictionary<string, RectTransform>>("_villageFriends").Keys);
        var failed = JsonUtility.FromJson<AppState>(JsonUtility.ToJson(_state)); failed.revision++; failed.error = "저장 실패";
        Call("OnState", failed); Build();
        Assert.NotNull(Named("Village friend selector"));
        Assert.IsTrue(ButtonNamed("저장").interactable);
    }
    [Test] public void NativeBackClosesSelectionAndKeepsConfirmedFriends()
    {
        ButtonNamed("마을 친구 선택").onClick.Invoke(); Build();
        Choice("friend-4").onClick.Invoke(); Build();
        Allo.Bridge.FlutterBridge.HandleBack(); Build();
        Assert.IsNull(Named("Village friend selector"));
        CollectionAssert.AreEqual(new[] { "friend-4" }, Get<Dictionary<string, RectTransform>>("_villageFriends").Keys);
    }
    void Build()
    {
        var content = Get<RectTransform>("_content");
        foreach (Transform child in content.Cast<Transform>().ToArray()) Object.DestroyImmediate(child.gameObject);
        Call("BuildVillageMap", 0f, true); Canvas.ForceUpdateCanvases();
    }
    Button Choice(string id) => Named("Village choice " + id).GetComponent<Button>();
    Transform Named(string name) => _root.GetComponentsInChildren<Transform>().SingleOrDefault(t => t.name == name);
    Button ButtonNamed(string text) => _root.GetComponentsInChildren<Button>().SingleOrDefault(b => b.GetComponentInChildren<Text>()?.text == text);
    T Get<T>(string name) => (T)typeof(AppUi).GetField(name, Private).GetValue(_ui);
    void Call(string name, params object[] args) => typeof(AppUi).GetMethod(name, Private).Invoke(_ui, args);
}
