# Unity phone application — approved direction

User approved 2026-11-12: all visible phone application screens in Unity; reuse current PR #93 affinity and #100 camp logic. PR #97 supplies visual reference only. The egg exists only in the vehicle-interior view, including its nested photo quest. Pleos fishing/logging rewards are planned; its upstream PR is still being revised.

## Product and visual direction
Landscape, warm cream/cocoa/mint toy world, chunky rounded controls, Korean copy, large legible actions, one yellow primary action per surface. Home is a 3D camp with collected friends and three visible facilities; cabin reuses the existing 3D car/world. All application menus, pairing fields, camp commands, inventory, dex/detail and settings are Unity UGUI. Android camera/speech/permission surfaces are platform services. Preserve canonical species IDs and existing acquisition rules.

## Behaviour
Home -> cabin, camp, friends/dex, supplies, connection/settings. Game stage does not force users out of home or camp. Egg model, affinity meter, four placement zones and speech/pet/photo/discard controls appear only in cabin. 50-point lock -> real camera photo with egg composite -> authenticated upload -> 65; 100 triggers the existing saved hatch, revealed inside cabin. Failed/discarded egg has explicit restart. Never credit an unconfirmed result. Camp consumes actual saved materials, validates fixed roles, runs build/cook/train in parallel and settles offline with existing controllers. Show locked/empty/error/pending states and actionable reasons. No seeded production inventory or fake success.

Existing distance/lookout material rules remain until the Pleos reward contract is supplied. Inventory shows actual balance; a pending activity-link state must not fabricate fishing/logging receipts. Do not invent a remote reward schema or allow Unity to mint materials.

## Architecture and boundaries
Flutter is the invisible host. GameController + BaseCampController remain authoritative. Unity receives a versioned `app` snapshot and sends `appAction` intents, never directly changes scores/materials/ownership. Existing scene/cast/route/settings messages remain for the cabin. Default Android app boots Unity, with legacy Flutter routes available only for development/non-Unity tests. Preserve data on install and avoid modifying the source PR worktrees.

## Shared bridge contract (exact names)
Envelope snapshot: `v:1,type:app,revision:int,view:string,ready:bool,busy:bool,error:string,notice:string,connected:bool,isDemo:bool,canStart:bool,sessionEnded:bool,speechAvailable:bool,photoAvailable:bool,egg:EggState,materials:MaterialState[],facilities:FacilityState[],creatures:CreatureState[],jobs:JobState[],foods:FoodState[],training:TrainingState[],dex:DexState[],rewardStatus:string`.
Views: `home,cabin,camp,dex,inventory,settings`. Navigation is committed by Dart and echoed in snapshot.view.
EggState: `id,phase,feedback,remainingLabel` strings; `active,photoRequired,speechBusy,photoBusy` bools; `score` float; `zone,preferredZone` ints; `speechCooldown,petCooldown,moveCooldown` ints (seconds). Empty id/active=false means no egg model. Phase is core enum name. A saved hatched state uses active=false and reveals the new creature in cabin.
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

C# public model API: namespace `Allo.App`, `AppState` and child DTO names as above, `AppAction` with fields above. `AppSession.State`, `AppSession.Changed` event, `AppSession.Request(string action, AppAction body=null)` injects v/type/requestId and current eggId; `AppSession.Receive(AppState)` ignores older revisions. `AppSession.CurrentView` returns state.view or home. `AppSession.Install()` called once by scene builder/runtime installer.
Unity UI class `AppUi : MonoBehaviour`, world `AppWorld : MonoBehaviour` with `SetView(string)` and `Apply(AppState)`; cabin egg `CabinEgg : MonoBehaviour` with `Apply(AppState)` and `SetView(string)`. Components locate existing cabin/camera/directors via named objects/type when fields not provided. `AppSession.Install()` adds all three to its root. Only the main agent edits AppSession/shared DTO/bridge parser and scene builder.
Native inputs channel `allo/egg-input`: `speech` -> String transcript, `photo` -> Uint8List JPEG including stylized egg composite; optional cancellation -> null; failures PlatformException. Native bridge never awards points. Dart uses injected callbacks for tests and handles unconfigured API honestly.

## Verification
Keep all current Dart/core tests green. Add boundary/dispatch tests for stale egg, duplicate and malformed intents, save failures and real camp costs. Unity EditMode tests for app snapshot ordering/navigation and egg cabin-only visibility/zone selection. Android build and emulator screenshots of all new views plus actual end-to-end start/pet/move and camp/empty paths. Verify no real rewards are invented while Pleos contract is pending.
