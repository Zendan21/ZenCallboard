ZenCallboard regression scenarios

These files are developer regression specifications and are NOT loaded by WoW.
They document the safety invariants that future changes must preserve.

Core invariants:
1. Instance + board open + eligible instance quest + no route => instance search may reroll.
2. Instance + refresh-locked quest => zero rerolls.
3. Outdoor zone + no armed route => zero instance rerolls.
4. STOP/disarmed normal route + board open => normal route never starts.
5. PAUSE => no automation.
6. Board closed => RequestReroll must never be called.
7. Instance priority outranks Ignore Order and normal route.
8. A selected/accepted quest transitions to waiting rather than restarting search.

9. PLAYER_DEAD clears local Callboard refresh-lock history before future instance-priority decisions.

10. A real QUEST_TURNED_IN advances/clears the tracked quest even if the Callboard remains visible; board visibility only blocks disappearance-based inference.
