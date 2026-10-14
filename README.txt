ZenCallboard 1.0.74

1.0.74 refresh-safety + 1.0.71 reliability/catalogue improvements:
- Stronger dungeon/raid matching uses instance, zone, subzone and minimap names plus boss/instance aliases and quest-type metadata.
- Completed Callboard offers are excluded from automatic selection so Zen does not lock onto an already-completed objective.
- Catalogue entries now track live verification count and last-seen metadata; seeded/imported entries remain clearly marked Unverified until observed on the live board.
- Added Zen-native catalogue Export/Import with a versioned ZENCATALOG1 text format. Imports merge safely and never replace newer live metadata.
- Added per-session reroll/gold statistics alongside lifetime and last-search totals.
- Selected-quest tracking now preserves explicit selected/seen-in-log/seen-active state to reduce accidental roller restarts when Ebonhold events arrive late.
- Catalogue learning and import/export remain completely standalone; no AutoCallboard dependency is introduced.

Build an ordered Project Ebonhold Callboard quest route. ZenCallboard rolls
for the current step, selects only that quest, waits for completion, and then
moves to the next step.

Interface
- The interface follows Zen Family Activity Finder's layout and styling:
  a 60-pixel header, left action rail, central searchable catalogue, right route
  panel, flat charcoal surfaces, slate borders and gold interaction highlights.
- Settings, saved routes, quest details, the mini runner and group progress use
  the same panel, header, button, input and semantic colour treatments.

Getting started
1. Type /zencb to open the route builder.
2. Open the Callboard. ZenCallboard automatically learns every visible quest into its own catalogue.
3. ZenCallboard ships with a built-in baseline catalogue and also scans any full objective data Ebonhold exposes client-side. Opening the Callboard passively verifies/adds quests; catalogue population itself never rerolls or spends gold.
4. Search the catalogue and press + to add quests to the route.
5. Press ? beside any quest to see its exact objective, zone and quest ID.
6. Click zone headers to collapse or expand their quests.
7. Reorder route steps with Up and Down.
8. Open or summon the Callboard so its quest window is visible.
9. Press Start Route. The route cannot start while the window is closed.

Saved routes and settings
- Press Routes to save the current ordered route under a name, load a preset,
  overwrite it after editing, or delete it with a two-click confirmation.
- The Routes window can privately share the current route with a character by
  name. The recipient gets an Accept/Decline prompt, and accepted routes are
  saved as a separate named copy without interrupting their current route.
- Shift-click a player's name in chat to copy it directly into the route-share
  recipient box. The chat name keeps its normal click behaviour as well.
- Every saved-route row has its own Share button, so a preset can be sent
  directly without loading it. Share Current remains available for unsaved edits.
- Incoming routes normally show an Accept/Decline popup. They are also placed in
  a small fallback inbox: use /zencb accept or /zencb decline if no popup is visible.
- Sending a route to your own logged-in character is supported for testing.
- Route sharing includes quest order, objectives, zones and the loop setting.
  Both players need ZenCallboard installed; transfers use private addon
  whispers and are split automatically when a route is too large for one message.
- Press Settings to enable route looping, change safe auto-accept, set the
  maximum rerolls per step, adjust the reroll response delay, or choose how
  many route quests (1-20) the mini window displays.
- Settings also control automatic group sharing and live group progress.
- Auto-loop is stored with each named route when it is saved.
- The Callboard will not repeat a quest until three Callboard completion events
  have occurred after it. Repeated/shared quest IDs still advance that event window.
  Invalid short loops are refused before any reroll can spend gold.
- ZenCallboard remembers the last three Callboard completion events per character,
  even after reloading or switching saved routes, and stops safely if the current
  step is still repeat-locked.
- The board button displays its remaining summon cooldown in seconds. Near a
  permanent city Callboard it changes to Open Board and uses that board instead.

Route runner
- Start Route first looks for an in-range Callboard or Objectives Board. It opens
  permanent city boards and existing summoned boards without casting. Only when
  no usable board is nearby and Summon Callboard is learned does it cast the
  ability, interact with the new board, and start the route.
- Casting Summon Callboard manually while a route is ready also opens the new
  board and starts the route. Manual summons during an active route are detected
  and used for the current step without requiring the addon button.
- Start Route never attempts to recast Summon Callboard while the spell is on
  cooldown. It searches for the existing manually summoned board instead, so a
  cooldown cannot block starting the route or collecting the next route quest.
- When running, the large route builder is replaced by a movable, resizable mini
  window showing the current and upcoming route quests, summon cooldown and a
  clear STOP button. The current quest is highlighted in yellow.
- STOP immediately ends automation and returns to the route builder.
- Accepted route quests are automatically shared with the party or raid when
  the quest is shareable.
- Press Group on the mini runner to open a live, scrollable progress roster.
  Members report objective totals such as 6/10, Complete or Quest not found.
- Live progress uses WoW addon messages, so each tracked group member needs
  ZenCallboard installed. Anyone without it appears as No addon data.
- A refreshed offer list is searched immediately instead of waiting out a stale
  reroll timeout, making normal Callboard searches substantially faster.
- The exact current route quest advances automatically when the quest log or
  quest completion event reports it complete.
- Ebonhold active-objective transitions are also tracked, so reopening the
  Callboard after finishing a quest immediately begins searching for the next
  route step even when no normal quest-log completion event was emitted.
- If the client blocks automatic interaction, move closer and interact with the
  Callboard manually. Paid rerolls remain blocked until its window is visible.

Commands
/zencb                 Toggle the route builder
/zencb start           Start or resume the route
/zencb pause           Pause automation
/zencb next            Mark the current step complete and advance
/zencb reset           Return to route step 1
/zencb group           Toggle the live group-progress roster
/zencb share NAME      Privately share the current route with that character
/zencb accept          Accept and save the latest incoming shared route
/zencb decline         Decline the latest incoming shared route
/zencb catalog         Refresh the catalogue from bundled + free Ebonhold client data
/zencb export          Open a copyable Zen catalogue export
/zencb import          Open the Zen catalogue import window
/zencb status          Show current route status
/zencb help            Show command help

Important
- ZenCallboard maintains its own learned Callboard catalogue and has no dependency on any other Callboard addon.
- Catalogue population never spends gold. Refresh List only reads bundled/client data and visible offers. Paid rerolls happen only while actually searching for a requested route or instance quest.
- ZenCallboard only auto-accepts a quest when its ID or title matches the
  current route step.
- Completing a step with automatic detection or /zencb next updates the remembered
  three-quest repeat lockout.
- If this client does not emit QUEST_TURNED_IN, use the Next button after you
  finish a step. ZenCallboard also detects completed quests leaving the log.


Group synchronization
- Group Progress warns when a member is out of range and their quest state may be stale.
- Refresh / Sync requests fresh quest progress and links members on the same ordered route to the furthest current step.
- A member joining mid-route can open Group Progress and press Refresh / Sync to catch up.
- The route roller stops immediately if the Callboard window is closed, preventing further reroll spending.

- Group sync now automatically re-announces route/progress after login, /reload, roster changes, and quest-log changes.

- Group route consistency now checks both the ordered route and current step. Different routes block Start Route; matching routes are synced to the furthest step before running.


Credits & Inspiration
- Special thanks to Disarrayed for the original inspiration, ideas, and concepts that helped shape ZenCallboard.

RENAMED FROM RAVIOLI
--------------------
ZenCallboard is the renamed continuation of RavioliCallboard. Existing RavioliCallboardDB routes and settings are imported automatically. /zencb is the primary command. The hidden group-sync protocol remains compatible with RavioliCallboard during the rollout.


Version 1.0.74
- Hardened Project Ebonhold Callboard compatibility around recent server/client changes. ZenCallboard now recognizes several Callboard/Objectives service and frame naming variants and supports both closure-style and colon-style service methods.
- Added /zencb doctor (or /zencb compat) to print the currently detected Ebonhold service, methods, board frame and objective source for quick troubleshooting if Ebonhold changes the custom API again.
- Existing routes, group sync protocol and rename migration remain unchanged.


1.0.67: Added persistent Ebonhold repeat refresh-lock safety. Instance/raid priority will not reroll for a quest that Zen knows is still within the three-different-quest repeat block. Known Callboard turn-ins are tracked even when accepted manually.


1.0.71 safety/roller improvements:
- Hard reroll safety cap defaults to 25 per search and applies to route and instance searches.
- Tracks reroll spend per run plus persistent lifetime totals.
- Mini runner shows state, reroll count, and current-run spend.
- Live objective learning only reprocesses the catalogue when the offer signature changes.
- Instance detection cache is invalidated on zone/instance changes for more reliable dungeon/raid priority.
- Roller state is tracked explicitly (SEARCHING, REROLLING, SELECTED, PAUSED, SAFETY_STOP, etc.).

1.0.74: Refresh Safety upgrade. Cooldown history now tracks the last three completion events (including repeated/shared quest IDs), catalogue/details show per-quest cooldown remaining, duplicate completion callbacks are de-duplicated, and disappearing objectives require a short confirmed absence outside the visible Callboard before counting as completion.


1.0.75 diagnostics:
- /zencb why explains the current automation mode, board/instance state, target, refresh lock, rerolls, spend, and next action.
- Tests/SafetyScenarios.lua documents the gold-safety and priority invariants for regression testing and is not loaded by WoW.


1.0.76 refresh reset handling:
- PLAYER_DEAD now clears Zen's local three-completion Callboard refresh history because Ebonhold resets that server-side lock on death/prestige.
- Death still retains the protection that prevents a disappearing Board quest from being counted as completed.
- /zencb refreshreset manually clears only the local refresh-lock history as a fallback for server prestige/reset paths that do not emit PLAYER_DEAD.


1.0.77 persistent-Callboard completion fix:
- QUEST_TURNED_IN is now authoritative even when the summoned Ebonhold Callboard remains visible.
- Completing a tracked Board quest immediately clears/advances its waiting state; Zen no longer waits for the Board/active objective to despawn.
- If the Board is still open, the next eligible route/instance search may proceed immediately.
- Board-visible protection still applies to inferred quest disappearance, preventing rerolls/replacements from being miscounted as completions.


1.0.82 recovery:
- Rebuilt again from 1.0.77 after identifying the exact 1.0.81 runtime error: UI.lua called nonexistent global makeCheck().
- Uses the stable UI's actual checkbox helper (makeCheckbox) for the auto-open option.
- Because UI creation no longer aborts at Settings construction, the left runner controls, catalogue labels, bottom controls, route manager, and Settings footer can all finish constructing.
- No custom hotkey-capture UI is included. Summon Callboard is exposed through WoW's native Key Bindings.
- Manual summons continue the active route session; optional auto-open remains available.


1.0.83:
- Fixed auto-open-after-summon getting stuck at "Waiting for the Callboard to appear...".
  The pending board interaction is now processed even when the normal route is not armed.
- This lets the summon -> detect spawned board -> interact/open flow complete, after which
  the normal route or dungeon/raid instance-priority logic can take over.
- Window title is pinned to this build's version because this 3.3.5 environment was returning
  stale addon metadata and displaying 1.0.80 despite the newer code being loaded.


1.0.84 Callboard open detection:
- Auto-open waits for the summoned NPC to become targetable and retries interaction for up to 20 seconds.
- Manual Callboard opening is detected from the actual Objectives/Callboard frame becoming visible, not only GOSSIP_SHOW.
- GOSSIP_SHOW and visibility-poll detection now feed the same board-open handler.
- Added interaction diagnostics for target discovery failures.
- Hotkey-in-Settings remains intentionally deferred until board opening is stable.


1.0.85:
- Ebonhold's summoned Objectives Board is now treated correctly as a world GameObject, not a targetable Unit.
- Removed futile TargetByName/InteractUnit attempts for the summoned board.
- After summon, Zen asks for one physical click on the board and waits up to 30 seconds.
- Added dynamic discovery/caching of the visible Ebonhold Objectives UI frame by frame name and identifying text.
- Once the Objectives UI appears, Zen automatically recognizes it and hands control to the normal route/instance-priority reroll logic.


1.0.86:
- Added real automatic interaction with Ebonhold's summoned Objectives Board using QueueInteract().
- QueueInteract() was verified in-client to open the nearby Objectives Board with no arguments.
- Auto-open now retries QueueInteract safely through pcall while the pending summon/open flow is active.
- Removed the temporary instruction requiring a physical click on the board.
- Manual board-open frame detection from 1.0.85 remains as a fallback.


1.0.87:
- Added Summon Callboard hotkey control directly to ZenCallboard Settings.
- Click the binding button, then press a key or Ctrl/Alt/Shift combination.
- Escape cancels capture; Backspace/Delete or the Clear button removes the binding.
- The editor uses WoW's native ZENCALLBOARD_SUMMON binding and SaveBindings rather than creating another secure action button.
- Binding changes are blocked during combat.
- The verified QueueInteract() automatic Callboard opening from 1.0.86 is unchanged.


1.0.88 hotkey protection fix:
- The Zen hotkey no longer invokes CastSpellByName from addon Lua.
- Assigning the hotkey now creates a native Blizzard spell binding with SetBindingSpell("Summon Callboard").
- This lets Blizzard's secure binding system cast the spell from the hardware keypress and avoids the "ZenCallboard has been blocked from an action only available to the Blizzard UI" popup.
- Removed the obsolete ZENCALLBOARD_SUMMON addon binding handler/Bindings.xml path.
- Auto-open via the verified QueueInteract() flow is unchanged.


1.0.89 hidden Callboard mode:
- Added Settings > Keep Callboard window hidden while searching.
- Zen still opens/initializes the Ebonhold Objectives Board with QueueInteract(), then hides the visual board frame and continues using the live Objectives service/access.
- Hidden mode can reroll/process offers while Ebonhold still reports active board access; it does not bypass the server's proximity/access rules.
- Normal visible mode keeps the existing strict no-visible-board/no-reroll gold-safety behavior.
- Manual/instance-priority detection, cooldown checks, repeat locks, gold tracking, and route logic continue to run in hidden mode.


1.0.90 hidden-window presentation fix:
- Fixed hidden Callboard mode exposing the underlying blank Blizzard Gossip/Greeting window.
- QueueInteract can open both the Ebonhold Objectives UI and GossipFrame; Zen now hides both visual layers in hidden mode.
- Added PE.HideBoardVisuals() so hidden mode only suppresses presentation and does not deliberately close/reset the live Callboard service session.
- Visible Callboard mode is unchanged.


1.0.91 hidden-board shell fix:
- Hidden mode still initializes the real Callboard normally with QueueInteract; it does not use a fake/background replacement.
- Fixed Ebonhold's blank 'Greetings ... / Goodbye' interaction shell remaining visible when the custom Objectives layer is hidden.
- The visual scrubber now detects that custom interaction shell by its greeting/goodbye text as well as GossipFrame.
- Visual hiding is repeated briefly after initialization because Ebonhold can create/show the interaction shell one UI tick after the Objectives window.
- No close/goodbye action is invoked, preserving the live board session used for hidden rerolls.


1.0.92 hidden-mode architecture fix:
- Hidden mode no longer calls :Hide() on the real Callboard/Objectives UI.
- The real Ebonhold Callboard remains shown/active internally and is made invisible with alpha 0 instead.
- Mouse input is disabled on cloaked Callboard/greeting frames so an invisible window does not block clicks.
- This preserves the same live UI/session state used by visible mode, allowing objective requests/rerolls to continue normally.
- Zen restores original alpha/mouse state when hidden mode is disabled or the route is stopped.


1.0.93 hidden-mode visual cleanup:
- Fixed the Reroll Selection / Cost control remaining partially visible in hidden mode.
- Zen now cloaks the complete child-frame tree of detected Callboard frames, not just the parent.
- Independently-parented Callboard controls are also detected by Reroll Selection / Cost text and made transparent.
- Frames remain shown internally, preserving the live Ebonhold Callboard session and background reroll behavior.


1.0.94 hidden-mode tooltip fix:
- Fixed the remaining Reroll Selection / Cost / coin display appearing when hovering the invisible live Callboard.
- Hidden mode now suppresses GameTooltip only when its text identifies the Callboard/Objectives reroll UI.
- The real Callboard remains shown internally, preserving the working hidden reroll session.
- Other normal game tooltips are left untouched.


1.0.95 safety / hidden acceptance / hotkey QoL:
- Summon Callboard hotkey now acts as Start-if-needed: if a route exists but is disarmed, a successful summon automatically arms/starts it, then opens the board and continues normally. If already running, it simply continues the active route.
- Hidden mode no longer treats the cached HasBoardAccess grace period as permission to spend gold.
- Added GOSSIP_CLOSED handling to revoke board access and cancel pending rerolls immediately when the interaction ends.
- A summoned hidden-board session is also revoked when the Summon Callboard cooldown completes after having started, preventing rerolls from continuing after the summoned GameObject expires.
- Fixed hidden-mode quest acquisition tracking: because the cloaked real board remains technically shown, acceptance timeout now preserves the selected quest in hidden mode instead of incorrectly returning to the roller.
- Hidden-mode setting now persists correctly through SavedVariables/profile loading.


1.0.96 hidden-mode + hotkey correction:
- Reworked hidden mode again: Zen no longer alpha-hides the Callboard or recursively alters its child controls.
- The genuine, normally-rendered Ebonhold Callboard is instead parked far off-screen. This keeps the exact visible-mode UI/update path alive internally while making it unseen and non-interactive to the player.
- This addresses hidden mode reaching the reroll cap because the wanted quest was never observed/selected.
- Summon Callboard spell-success events are now processed even while Zen is paused.
- If a route exists and is not running, pressing the Summon Callboard hotkey immediately arms AND starts the Route Runner, then opens the board. If already running, it continues normally.
- Existing hidden-board despawn/GOSSIP_CLOSED safety remains in place.


1.0.97 hidden-board reuse QoL:
- After Zen successfully accepts a quest in hidden mode, it now releases/closes the hidden UI interaction instead of leaving the real Callboard parked off-screen.
- This does not despawn the summoned world Callboard. If the quest is completed before the board expires, right-clicking that same board opens a fresh interaction and Zen can immediately search/roll for the next route step.
- Clears stale board-access/reroll state when the accepted quest releases the hidden interaction.


1.0.100 recovery baseline:
- Rebuilt directly from the intact ZenCallboard 1.0.97 source tree.
- Discards all 1.0.98 and 1.0.99 code changes.
- Restores the full Main.lua route, instance-priority, hidden-board, reroll, quest, group, and event logic from 1.0.97.
- No new behavior has been added in this recovery build; this is intentionally a clean return to the last intact baseline before redesigning the fast-completion/right-click resume feature.


1.0.103 hidden quest-selection fix:
- Rebuilt directly from confirmed-working 1.0.100; 1.0.101/1.0.102 reuse experiments are not included.
- Hidden mode continues rerolling with the genuine Callboard parked off-screen.
- When the wanted offer is actually found, Zen temporarily restores the genuine Callboard to its normal position immediately before SelectObjective().
- This preserves Ebonhold's normal quest-detail/AcceptQuest handshake, which appears to depend on the live Callboard presentation being in its normal state even though service rerolls do not.
- The board is not re-hidden during pending acceptance; the existing hidden-mode acceptance cleanup then closes/releases it after QUEST_ACCEPTED.
- No changes to matching, offer indexes, reroll limits, catalogue, UI/profile startup, or completion logic.


1.0.104 hidden-mode flicker fix:
- Keeps the 1.0.103 hidden quest-selection fix.
- When the wanted quest is found, the genuine Callboard is restored to its normal coordinates for Ebonhold's SelectObjective handshake but its top-level frame remains transparent and non-interactive.
- The normal frame alpha/mouse state is restored during the existing post-accept cleanup.
- Hidden rerolling itself is unchanged and continues with the board parked off-screen.


1.0.105 fast-completion / same-board reuse:
- Fixed accepted Callboard quests remaining stuck as the active route step while the physical Callboard was still present.
- Once Zen has genuinely observed the accepted quest in the quest log or as Ebonhold's active objective, disappearance now counts as completion after a short 0.75s settle window even if the Callboard still exists and even while the player remains in combat.
- The route advances immediately to the next step instead of waiting for combat to end or the summoned Callboard to despawn.
- Death/prestige protection remains intact, and replacement handling for a different accepted Board quest remains unchanged.
- Built on 1.0.104, preserving the working hidden reroll/selection behavior.


1.0.106 instance quest reminder:
- Added a movable on-screen warning when inside a supported dungeon/raid without its eligible Callboard quest in the quest log.
- Independent of Route Runner state, so it warns even when no route is currently running.
- Automatically disappears within about one second when the quest is acquired or when leaving the instance.
- Close X dismisses it for the current instance visit; entering a different supported instance resets the dismissal.
- Suppressed when the relevant instance quest is already completed/repeat-locked.
- Uses the existing throttled main loop and checks only once per second.


1.0.107 raid quest reminder fix:
- Fixed the 1.0.106 reminder being declared before the quest-log helper functions it called; under Lua lexical scoping those calls resolved incorrectly and the reminder never worked reliably.
- Reminder now specifically checks supported raids, independent of Route Runner state.
- If the raid has a known Callboard quest and none of that raid's Callboard quests are in the quest log, a movable warning appears.
- The warning automatically disappears within about one second after the quest enters the quest log or after leaving the raid.
- The X dismisses it for the current raid visit; entering another raid (or leaving and returning) resets the reminder.


1.0.108 raid-entry reminder fix:
- Raid reminder now uses ZenCallboard's bundled raid catalogue, so it does not wait for the learned catalogue/Callboard to become populated.
- The actual player quest log is checked directly by quest ID and title.
- Reminder checks begin only after ZenCallboard initialization, avoiding an early nil/uninitialized scan.
- PLAYER_ENTERING_WORLD and all zone-change events invalidate the instance cache and force an immediate fresh reminder check.
- The check remains independent of Route Runner and Callboard state and repeats once per second while inside the raid.


1.0.109 raid reminder completion fix:
- Once Zen sees the correct Callboard quest in your quest log during a raid visit, that raid is marked satisfied.
- Killing the final boss and having Ebonhold remove the completed quest from the quest log will no longer trigger a false missing-quest warning.
- IsQuestFlaggedCompleted is also checked as a backup for UI reload/relog cases.
- Entering a different supported raid clears the visit-specific satisfied state so the new raid can warn normally.


1.0.110 raid reminder visit reset:
- Leaving the raid now fully resets the raid reminder visit state.
- The remembered "quest was seen" state and manual dismissal are both cleared on exit.
- Re-entering the same raid after an instance/raid reset therefore performs a fresh quest-log check and warns again if the Callboard quest is missing.
- Boss completion still stays quiet for as long as you remain inside that raid.


1.0.111 raid QoL fixes:
- Summoning/opening the Callboard inside a recognized dungeon/raid no longer auto-arms or starts the normal Route Runner when it was previously stopped. Instance priority runs by itself to fetch the local instance quest.
- If Route Runner was already explicitly armed before entering, its existing state is preserved.
- Raid missing-quest reminder body now uses a fixed-width, word-wrapped text area so long raid/quest names wrap inside the popup instead of running off one line.


1.0.112 Ignore Order cooldown behaviour:
- Ignore Order no longer shows route cooldown/CD indicators in the mini route, catalogue rows, or quest detail availability.
- Normal route repeat-lock advisory checks are skipped while Ignore Order is enabled.
- The live Callboard is authoritative in Ignore Order: the first visible offered quest that belongs to the route is selected immediately, regardless of the nominal current step's cooldown history.
- Instance-priority refresh-lock protection is unchanged; this applies only to Ignore Order route mode.

1.0.113: Optional EbonAPI 2.1 integration.
- Direct ZenCallboard peer whispers use EbonAPI's queued whisper transport when installed.
- Existing group/raid messages remain group-scoped for privacy and compatibility.
- Existing group sync, route sharing, quest logic and UI remain unchanged.
- Without EbonAPI, legacy communication still works.
- Both clients should install EbonAPI for its whisper transport.

1.0.114 - Optional EbonAPI community route sharing
- /zencb community status: verify EbonAPI is ready.
- /zencb community publish: publish current route using EbonAPI shared data.
- /zencb community import: import locally available community route as SAVED route without activating it.
- Explicit opt-in; no community route is applied automatically.
- Existing direct route sharing and group sync remain unchanged.
- EbonAPI shares can take time to propagate.

1.0.115 Community Routes browser:
- Main window Community Routes button opens a movable route directory.
- Lists all EbonAPI ZenCallboard shares currently synchronized locally.
- Shows author, route name, step count and preview of quest order.
- Share My Route publishes under a character-specific share key.
- Import Selected saves a separate named route; never starts/replaces active route.
- Refresh requests EbonAPI share synchronization; remote updates may take time.
- EbonAPI is optional. No change to Callboard automation or group sync.

1.0.116 - Embedded ZenStylingPack 1.1.0
- Bundles the supplied styling pack in an isolated Addon.ZenStyle namespace.
- Replaces default ZenCallboard panel/button surfaces with styling-pack surfaces.
- Appearance button opens the pack's full theme/accent/opacity/scale/font editor.
- Uses EbonAPI's shared account appearance and local change event when available.
- Local appearance settings are retained when EbonAPI is unavailable.
- Preserves existing ZenCallboard layout, automation, group sync and community routes.
- In-game visual testing is required for all six themes and secure buttons.
