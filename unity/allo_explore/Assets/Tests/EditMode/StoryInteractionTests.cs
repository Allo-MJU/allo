using Allo.App;
using NUnit.Framework;

public class StoryInteractionTests
{
    static AppState Cabin(bool active, bool paused = false) => new AppState
    {
        view = "cabin", ready = true,
        egg = new EggState { id = "egg", active = true },
        story = new StoryState { active = active, paused = paused }
    };

    [Test]
    public void ActiveStoryBlocksEggGestureWithoutRemovingTheEgg()
    {
        var state = Cabin(true);
        Assert.IsTrue(CabinEgg.ShowEgg("cabin", state.egg));
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "egg"));
        Assert.IsNull(CabinEgg.EggIntent(state, "cabin", "egg", "petEgg", 0));
        Assert.IsNull(CabinEgg.EggIntent(state, "cabin", "egg", "placeEgg", 1));
    }

    [Test]
    public void PausedStoryRestoresCareButDoesNotOverrideOtherBusyStates()
    {
        var state = Cabin(true, true);
        Assert.IsTrue(CabinEgg.CanInteract(state, "cabin", "egg"));
        state.busy = true;
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "egg"));
        state.busy = false;
        state.egg.photoBusy = true;
        Assert.IsFalse(CabinEgg.CanInteract(state, "cabin", "egg"));
    }

    [Test]
    public void BackFirstPausesStoryThenUsesExistingNavigation()
    {
        var state = Cabin(true);
        Assert.AreEqual(AppBackAction.PauseStory, AppSession.BackActionFor(state));
        state.story.paused = true;
        Assert.AreEqual(AppBackAction.NavigateHome, AppSession.BackActionFor(state));
        state.view = "home";
        Assert.AreEqual(AppBackAction.BackgroundApp, AppSession.BackActionFor(state));
    }

    [Test]
    public void MissingStoryRetainsLegacyCareBehavior()
    {
        var state = Cabin(false);
        state.story = null;
        Assert.IsTrue(CabinEgg.CanInteract(state, "cabin", "egg"));
        Assert.AreEqual(AppBackAction.NavigateHome, AppSession.BackActionFor(state));
    }
}
