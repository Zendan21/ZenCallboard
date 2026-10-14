-- ZenCallboard offline regression specification.
-- Intentionally not listed in ZenCallboard.toc.
local scenarios = {
  {
    name = "instance board open eligible no route",
    given = { instance=true, board=true, locked=false, routeArmed=false, paused=false },
    expect = { mode="INSTANCE_PRIORITY", mayReroll=true, normalRoute=false },
  },
  {
    name = "instance refresh locked",
    given = { instance=true, board=true, locked=true, routeArmed=false, paused=false },
    expect = { mayReroll=false, reason="REFRESH_LOCK" },
  },
  {
    name = "outdoor disarmed",
    given = { instance=false, board=true, routeArmed=false, paused=false },
    expect = { mayReroll=false, normalRoute=false },
  },
  {
    name = "paused freezes everything",
    given = { instance=true, board=true, locked=false, routeArmed=true, paused=true },
    expect = { mayReroll=false, maySelect=false, mayAccept=false },
  },
  {
    name = "board closed never spends",
    given = { instance=true, board=false, locked=false, routeArmed=true, paused=false },
    expect = { mayReroll=false, reason="BOARD_CLOSED" },
  },
  {
    name = "instance priority beats route",
    given = { instance=true, board=true, locked=false, routeArmed=true, ignoreOrder=true, paused=false },
    expect = { priority="INSTANCE" },
  },
}
return scenarios
