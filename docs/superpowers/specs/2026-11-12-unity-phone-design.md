# Unity phone application — approved direction

User approved 2026-11-12: all visible phone application screens in Unity; reuse current PR #93 affinity and #100 camp logic. PR #97 supplies visual reference only. The egg exists only in the vehicle-interior view, including its nested photo quest. Pleos fishing/logging rewards are planned; its upstream PR is still being revised.

## Product and visual direction
Landscape with a dominant full-screen survival camp and compact Korean controls. Latest user steering supersedes the earlier painted village: use Palworld-like practical work areas, rough timber, canvas, stone fire/cooking pot and training props, drawn as clean 2D anime-game sprites with restrained cel shading, not a 3D camp. Ninja Voltage remains the primary composition/interaction reference: thin resource HUD, right circular action rail, small facilities and bounded horizontal/vertical world panning. CookieRun production status and Slime town growth are secondary references. Three fixed facilities show real levels/jobs/materials; tap a facility to open existing worker/work controls. Cabin reuses the existing 3D car/world. Application menus, pairing fields, camp commands, inventory, dex/detail and settings are Unity UGUI. Android camera/speech/permission surfaces are platform services. Preserve canonical species IDs and existing acquisition rules.

## Behaviour
Home -> cabin, camp, friends/dex, supplies, connection/settings. Game stage does not force users out of home or camp. Egg model, affinity meter, four placement zones and speech/pet/photo/discard controls appear only in cabin. 50-point lock -> real camera photo with egg composite -> authenticated upload -> 65; 100 triggers the existing saved hatch, revealed inside cabin. Failed/discarded egg has explicit restart. Never credit an unconfirmed result. Camp consumes actual saved materials, validates fixed roles, runs build/cook/train in parallel and settles offline with existing controllers. Show locked/empty/error/pending states and actionable reasons. No seeded production inventory or fake success.

Existing distance/lookout material rules remain until the Pleos reward contract is supplied. Inventory shows actual balance; a pending activity-link state must not fabricate fishing/logging receipts. Do not invent a remote reward schema or allow Unity to mint materials.

## Architecture and boundaries
Flutter is the invisible host. GameController + BaseCampController remain authoritative. Unity receives a versioned `app` snapshot and sends `appAction` intents, never directly changes scores/materials/ownership. Existing scene/cast/route/settings messages remain for the cabin. Default Android app boots Unity, with legacy Flutter routes available only for development/non-Unity tests. Preserve data on install and avoid modifying the source PR worktrees.

## Shared bridge contract (exact names)
Envelope snapshot: `v:1,type:app,revision:int,view:string,ready:bool,busy:bool,error:string,notice:string,connected:bool,isDemo:bool,canStart:bool,sessionEnded:bool,speechAvailable:bool,photoAvailable:bool,egg:EggState,materials:MaterialState[],facilities:FacilityState[],creatures:CreatureState[],jobs:JobState[],foods:FoodState[],training:TrainingState[],dex:DexState[],rewardStatus:string,gyro:bool,reducedMotion:bool,assignments:AssignmentState[]`.
Views: `home,cabin,camp,dex,inventory,settings`. Navigation is committed by Dart and echoed in snapshot.view.
EggState: `id,phase,feedback,remainingLabel,speciesId,name,sprite` strings; `active,photoRequired,speechBusy,photoBusy` bools; `score` float; `zone,preferredZone` ints; `speechCooldown,petCooldown,moveCooldown` ints (seconds). Empty id/active=false means no egg model. Phase is core enum name. A saved hatched state uses active=false and reveals the new creature in cabin.
AssignmentState: `role,creatureId` strings. Role IDs builder/cook/trainer.
MaterialState: `id,label` strings, `count` int. IDs wood/stone/ingredient.
FacilityState: `id,label` strings; `level,woodCost,stoneCost` ints; `unlocked,canUpgrade` bools. IDs workshop/kitchen/training.
CreatureState: `id,speciesId,name,role,sprite` strings; `actions:string[]`; `foodBoostUntilMs:long`.
JobState: `id,role,label,workerId,targetId` strings; `progress:float,remainingSec:int`.
FoodState: `id,label` strings; `count,costIngredient,requiredLevel` ints; `unlocked:bool`.
TrainingState: `id,label` strings; `woodCost,stoneCost,ingredientCost,requiredLevel` ints; `unlocked:bool`.
DexState: `id,name,sprite,attribute,role,description` strings; `collected:bool,count:int`.

Intent: `v:1,type:appAction,requestId:string,action:string` plus applicable fields. Allowed actions:
- navigate(view), startEgg(tier=small|mid|large), pair(sessionId,pairCode), disconnect, refresh, endTrip
- petEgg(eggId), placeEgg(eggId,zone=0..3), speech(eggId), submitSpeech(eggId,text), photo(eggId), recoverPhoto(eggId), discardEgg(eggId)
- assign(role,creatureId), build(facility), cook(recipeId), train(actionId,targetId), cancel(role), feedFood(recipeId,creatureId), performAction(creatureId,actionId)
- settings(gyro:bool,reducedMotion:bool)
Validate version/type/request IDs, current egg identity, view=cabin for egg input, allowlists and string bounds. Cache handled request IDs (bounded); serialize cost-changing actions. Raw speech is never persisted/logged/sent in snapshots. Emit busy promptly and authoritative result after save. No raw photo or token in app snapshots.

C# public model API: namespace `Allo.App`, `AppState` and child DTO names as above, `AppAction` with fields above. `AppSession.State`, `AppSession.Changed` event (`Action<AppState>`), `AppSession.Request(string action, AppAction body=null)` injects v/type/requestId and current eggId; `AppSession.Receive(AppState)` ignores older revisions. `AppSession.CurrentView` returns state.view or home. `AppSession.Install()` called once by scene builder/runtime installer.
Unity UI class `AppUi : MonoBehaviour`, world `AppWorld : MonoBehaviour` with `SetView(string)` and `Apply(AppState)`; cabin egg `CabinEgg : MonoBehaviour` with `Apply(AppState)` and `SetView(string)`. Components locate existing cabin/camera/directors via named objects/type when fields not provided. `AppSession.Install()` adds all three to its root. Only the main agent edits AppSession/shared DTO/bridge parser and scene builder.
Native inputs channel `allo/egg-input`: `speech` -> String transcript, `photo` -> Uint8List JPEG including stylized egg composite; optional cancellation -> null; failures PlatformException. Native bridge never awards points. Dart uses injected callbacks for tests and handles unconfigured API honestly.

## Verification
Keep all current Dart/core tests green. Add boundary/dispatch tests for stale egg, duplicate and malformed intents, save failures and real camp costs. Unity EditMode tests for app snapshot ordering/navigation and egg cabin-only visibility/zone selection. Android build and emulator screenshots of all new views plus actual end-to-end start/pet/move and camp/empty paths. Verify no real rewards are invented while Pleos contract is pending.

## 2D village refinement (user steering during implementation)
Camp need not use 3D; use native Unity UGUI 2D village layout. Facility selection opens real existing controls, with an explicit return to overview. Keep work-in-progress bubbles, role/worker state, materials and level changes legible on the map. No new placement rules, resource-generation rules, combat, gacha or extra facilities are implied by the references. Preserve independent panel scroll fixes and all authoritative Dart boundaries.

Reference evidence: [Ninja Voltage official developer interview](https://www.bandainamcostudios.com/en/behind-the-game/255), [Ninja Voltage village screenshot/guide](https://news.qoo-app.com/en/post/21576/qoo-guide-naruto-x-boruto-ninja-voltage-beginner-guide), [Slime official kingdom system](https://ten-sura-m.bn-ent.net/), [CookieRun Kingdom official overview](https://www.cookierun-kingdom.com/en/). These inform interaction/composition; their IP art is not imported.

## Fresh visual direction after user feedback
The first UI was rejected as overly panel-heavy and its cream/mint colors unnatural. Replace the composition with a dominant original hand-painted village, compact HUD/resource bar/icon nav and docked facility inspector. Use natural moss/olive/cedar/ochre/stone art, dark-sage/paper UI and restrained amber emphasis. Cabin uses minimal overlay docks/drawers. Preserve all already-tested commands and data rules. Original project-bound raster assets and full prompts are recorded in docs/village-art-provenance.md.

## Final village composition steering
User explicitly approved keeping building artwork but reducing its size, replacing the component-like background with a full-screen world and adding limited horizontal/vertical camera movement. They authorized discarding prior visual work to match Ninja Voltage village composition closely. The full-screen world is behind HUD, with smaller facilities and a fixed right circular action rail. Map movement is presentation only and does not change facility slots, ownership, materials or affinity.


## Latest correction: 2D baseline, survival theme only
User clarified that Ninja Voltage remains the basic 2D village screen and Palworld is ONLY the theme reference. The temporary isolated 3D camp/RenderTexture implementation is removed. The persistent full-screen 2D world and bounded horizontal/vertical panning remain; replace cottages with original crisp cel-shaded workbench, outdoor cauldron and training sprites over a woodland terrain background. Keep small facility labels, fixed thin HUD/right circular rail and existing saved rules. The cabin alone retains its existing 3D presentation.


## User-requested pre-collected examples
An explicit UNITY_DEMO_CREATURES build flag with the Unity host and actual FakeVehicleFeed enables the isolated unity-demo-examples profile. Add four existing canonical characters through local DexStore once, without materials or remote reward receipts. Default/original demo ownership, camp and incubation keys remain intact. Show up to four actual owned-character sprites on the 2D camp; marker taps select their precise identity. This exception is limited to the user's requested demonstration and does not change production acquisition rules.


## Latest dev compatibility extension
Merge latest dev 8a094f3 (#102, including #99/#91) while retaining current Unity presentation and original #93/#100 logic. The v1 app snapshot adds optional fishingRecords:int and fishingError:string. Validated intents selectCarCompanion(creatureId) and retryFishingSave() call existing GameController/FishingController APIs. Resolve the exact persisted DexEntry through the same camp ownership registry, including legacy occurrence IDs; never substitute the first record of a species. Full Unity Dex exposes the existing vehicle-companion selection, observation count and failed-save retry, with connection/session/busy gates. No new fishing reward, material conversion or remote schema is introduced.

Retain authenticated pairing retry and whole-game v2 companion/fishing/gameRevision fields. The isolated example profile also isolates the new fishing store. The local-affinity Flutter debug harness remains explicit useUnityApp:false with its controller factory, frame builder and API lifetime. Legacy exploration egg/care/props remain usable outside app presentation; accepted full-app state clears legacy egg visuals and HUD, including home-to-cabin restoration.
