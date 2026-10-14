local addonName, Addon = ...
local PE = {}
Addon.PE = PE

local function debug(kind, message)
    if Addon and Addon.Debug then
        Addon:Debug(kind, message)
    end
end

PE.SUMMON_SPELL_ID = 600647
PE.SUMMON_SPELL_NAME = "Summon Callboard"
PE.CALLBOARD_NPC_NAMES = {
    "Callboard", "Call Board", "Objectives Board", "Objective Board",
    "Callboard Terminal", "Objectives Callboard"
}

local nearbyScanAt = -1
local nearbyScanResult = false
local spellKnownScanAt = -1
local spellKnownResult = false
local boardAccessUntil = 0

local function timeNow()
    return GetTime and GetTime() or 0
end

local function callboardNameMatches(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local wanted = string.lower(name)
    for i = 1, table.getn(PE.CALLBOARD_NPC_NAMES) do
        if wanted == string.lower(PE.CALLBOARD_NPC_NAMES[i]) then
            return true
        end
    end
    -- Ebonhold has changed the visible board naming more than once. Keep this
    -- deliberately narrow: a name must still explicitly identify a callboard
    -- or objective(s) board rather than matching arbitrary gossip NPCs.
    if string.find(wanted, "callboard", 1, true) or string.find(wanted, "call board", 1, true) then
        return true
    end
    if string.find(wanted, "objective", 1, true) and string.find(wanted, "board", 1, true) then
        return true
    end
    return false
end


local function gossipIsCallboard()
    if not GossipFrame or not GossipFrame.IsShown or not GossipFrame:IsShown() then
        return false
    end

    local name = UnitName and UnitName("npc") or nil
    if callboardNameMatches(name) then
        return true
    end

    if GossipFrameNpcNameText and GossipFrameNpcNameText.GetText then
        return callboardNameMatches(GossipFrameNpcNameText:GetText())
    end
    return false
end

function PE.MarkBoardAccess(duration)
    duration = tonumber(duration) or 30
    boardAccessUntil = math.max(boardAccessUntil or 0, timeNow() + duration)
end

function PE.ClearBoardAccess()
    boardAccessUntil = 0
end

function PE.HasBoardAccess()
    if PE.IsBoardVisible and PE.IsBoardVisible() then
        PE.MarkBoardAccess(30)
        return true
    end
    if gossipIsCallboard() then
        PE.MarkBoardAccess(30)
        return true
    end
    if (boardAccessUntil or 0) > timeNow() then
        local objectives = PE.GetObjectives and PE.GetObjectives() or nil
        return type(objectives) == "table" and table.getn(objectives) > 0
    end
    return false
end

local function targetIsNearbyCallboard()
    if not UnitExists or not UnitExists("target") then
        return false
    end
    if not callboardNameMatches(UnitName and UnitName("target") or nil) then
        return false
    end
    if CheckInteractDistance then
        return CheckInteractDistance("target", 3) and true or false
    end
    return true
end

function PE.IsCallboardNearby(forceScan)
    if targetIsNearbyCallboard() then
        nearbyScanAt = timeNow()
        nearbyScanResult = true
        return true
    end

    local currentTime = timeNow()
    if not forceScan and nearbyScanAt >= 0 and currentTime - nearbyScanAt < 0.25 then
        return nearbyScanResult
    end

    nearbyScanAt = currentTime
    nearbyScanResult = false
    for i = 1, table.getn(PE.CALLBOARD_NPC_NAMES) do
        if TargetByName then
            TargetByName(PE.CALLBOARD_NPC_NAMES[i], true)
        end
        if targetIsNearbyCallboard() then
            nearbyScanResult = true
            break
        end
    end
    return nearbyScanResult
end

function PE.TryInteractWithCallboard()
    -- Ebonhold's Objectives Board is a world GameObject rather than a Unit.
    -- This client exposes QueueInteract(), which has been verified to open the
    -- nearby summoned Objectives Board with no arguments.
    if type(QueueInteract) == "function" then
        local ok, result = pcall(QueueInteract)
        debug("interact", "QueueInteract result=" .. tostring(ok) .. " return=" .. tostring(result))
        return ok == true
    end
    debug("interact", "QueueInteract unavailable")
    return false
end

function PE.IsSummonSpellKnown(forceScan)
    local currentTime = timeNow()
    if not forceScan and spellKnownScanAt >= 0 and currentTime - spellKnownScanAt < 2 then
        return spellKnownResult
    end

    spellKnownScanAt = currentTime
    spellKnownResult = false

    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, PE.SUMMON_SPELL_ID)
        if ok and known then
            spellKnownResult = true
            return true
        end
    end

    if not GetNumSpellTabs or not GetSpellTabInfo then
        return false
    end

    local bookType = BOOKTYPE_SPELL or "spell"
    local tabCount = GetNumSpellTabs() or 0
    for tabIndex = 1, tabCount do
        local _, _, offset, spellCount = GetSpellTabInfo(tabIndex)
        offset = tonumber(offset) or 0
        spellCount = tonumber(spellCount) or 0
        for slot = offset + 1, offset + spellCount do
            local spellName
            if GetSpellBookItemName then
                local ok, name = pcall(GetSpellBookItemName, slot, bookType)
                if ok then
                    spellName = name
                end
            end
            if (not spellName or spellName == "") and GetSpellName then
                local ok, name = pcall(GetSpellName, slot, bookType)
                if ok then
                    spellName = name
                end
            end

            local spellID
            if GetSpellBookItemInfo then
                local ok, _, id = pcall(GetSpellBookItemInfo, slot, bookType)
                if ok then
                    spellID = tonumber(id)
                end
            end

            if spellName == PE.SUMMON_SPELL_NAME or spellID == PE.SUMMON_SPELL_ID then
                spellKnownResult = true
                return true
            end
        end
    end
    return false
end

local function resolvePath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local current = _G
    for part in string.gmatch(path, "[^%.]+") do
        current = current and current[part]
    end
    return current
end

local function clickFrame(target)
    if not target or (target.IsShown and not target:IsShown()) then
        return false
    end

    local ok, clicked = pcall(function()
        if target.Click then
            target:Click()
            return true
        end
        if target.GetScript then
            local handler = target:GetScript("OnClick")
            if handler then
                handler(target, "LeftButton")
                return true
            end
        end
        return false
    end)
    return ok and clicked == true
end

local function isEffectivelyVisible(frame)
    if not frame then
        return false
    end

    if frame.IsVisible then
        return frame:IsVisible() and true or false
    end

    -- Older clients may not expose IsVisible consistently. In that case,
    -- require the frame and every parent in its chain to be shown.
    local current = frame
    local depth = 0
    while current and depth < 12 do
        if current.IsShown and not current:IsShown() then
            return false
        end
        current = current.GetParent and current:GetParent() or nil
        depth = depth + 1
    end
    return true
end

local SERVICE_CANDIDATES = {
    { "ObjectivesService", "ProjectEbonhold.ObjectivesService" },
    { "CallboardService", "ProjectEbonhold.CallboardService" },
    { "CallBoardService", "ProjectEbonhold.CallBoardService" },
    { "ObjectiveService", "ProjectEbonhold.ObjectiveService" },
    { "Objectives", "ProjectEbonhold.Objectives" },
    { "Callboard", "ProjectEbonhold.Callboard" },
}

local SERVICE_METHOD_HINTS = {
    "RequestObjectives", "RequestCurrentObjectives", "GetCurrentObjectives", "GetObjectives",
    "GetActiveObjective", "RequestRerollObjectives", "RequestReroll", "CanAffordReroll",
}

local function serviceLooksUseful(service)
    if type(service) ~= "table" then return false end
    for i = 1, table.getn(SERVICE_METHOD_HINTS) do
        if type(service[SERVICE_METHOD_HINTS[i]]) == "function" then return true end
    end
    if type(service.currentObjectives) == "table" or type(service.objectives) == "table" or type(service.offers) == "table" then
        return true
    end
    return false
end

local function callServiceMethod(service, names, ...)
    if type(service) ~= "table" then return false, nil, nil end
    for i = 1, table.getn(names) do
        local name = names[i]
        local fn = service[name]
        if type(fn) == "function" then
            -- Older Ebonhold services expose closure-style methods; newer Lua
            -- modules may use colon methods. Try both without assuming either.
            local ok, a, b, c, d = pcall(fn, ...)
            if ok then return true, name, a, b, c, d end
            local firstError = a
            ok, a, b, c, d = pcall(fn, service, ...)
            if ok then return true, name, a, b, c, d end
            debug("service", tostring(name) .. " failed plain=" .. tostring(firstError) .. " method=" .. tostring(a))
        end
    end
    return false, nil, nil
end

local function serviceTableField(service, fields)
    if type(service) ~= "table" then return nil, nil end
    for i = 1, table.getn(fields) do
        local value = service[fields[i]]
        if type(value) == "table" then return value, fields[i] end
    end
    return nil, nil
end

function PE.GetService()
    local root = _G.ProjectEbonhold
    if type(root) ~= "table" then
        PE.lastServicePath = nil
        return nil
    end

    for i = 1, table.getn(SERVICE_CANDIDATES) do
        local key, path = SERVICE_CANDIDATES[i][1], SERVICE_CANDIDATES[i][2]
        local service = root[key]
        if serviceLooksUseful(service) then
            PE.lastServicePath = path
            return service
        end
    end

    -- Some builds place the service methods directly on ProjectEbonhold.
    if serviceLooksUseful(root) then
        PE.lastServicePath = "ProjectEbonhold"
        return root
    end

    PE.lastServicePath = nil
    return nil
end

function PE.RequestObjectives()
    local service = PE.GetService()
    local ok, method = callServiceMethod(service, {
        "RequestObjectives", "RequestCurrentObjectives", "RefreshObjectives", "RequestCallboardObjectives", "Refresh"
    })
    if ok then
        debug("service", "objective request via " .. tostring(PE.lastServicePath) .. "." .. tostring(method))
        return true
    end
    return false
end

function PE.GetObjectives()
    local service = PE.GetService()
    local ok, method, objectives = callServiceMethod(service, {
        "GetCurrentObjectives", "GetObjectives", "GetOfferedObjectives", "GetCallboardObjectives", "GetOffers"
    })
    if ok and type(objectives) == "table" then
        PE.lastObjectivesSource = tostring(PE.lastServicePath) .. "." .. tostring(method)
        return objectives
    end
    objectives, method = serviceTableField(service, { "currentObjectives", "objectives", "offeredObjectives", "offers" })
    if type(objectives) == "table" then
        PE.lastObjectivesSource = tostring(PE.lastServicePath) .. "." .. tostring(method)
        return objectives
    end
    PE.lastObjectivesSource = nil
    return {}
end


-- Return every objective definition the client already exposes without rerolling.
-- This deliberately uses only getter-style methods and existing tables; it never
-- calls RequestRerollObjectives/RequestReroll or clicks the reroll button.
function PE.GetCatalogueCandidates()
    local service = PE.GetService()
    local sources = {}
    local seenTables = {}

    local function addTable(value, source)
        if type(value) == "table" and not seenTables[value] then
            seenTables[value] = true
            table.insert(sources, { value = value, source = source })
        end
    end

    local getterNames = {
        "GetAllObjectives", "GetObjectiveDefinitions", "GetObjectivesCatalog", "GetObjectiveCatalog",
        "GetAvailableObjectives", "GetObjectivePool", "GetCallboardQuests", "GetAllCallboardObjectives",
    }
    for i = 1, table.getn(getterNames) do
        local name = getterNames[i]
        if type(service) == "table" and type(service[name]) == "function" then
            local ok, _, value = callServiceMethod(service, { name })
            if ok then addTable(value, tostring(PE.lastServicePath) .. "." .. name) end
        end
    end

    if type(service) == "table" then
        local fieldNames = {
            "allObjectives", "objectiveDefinitions", "objectivesCatalog", "objectiveCatalog",
            "availableObjectives", "objectivePool", "callboardQuests", "questPool", "definitions",
        }
        for i = 1, table.getn(fieldNames) do addTable(service[fieldNames[i]], tostring(PE.lastServicePath) .. "." .. fieldNames[i]) end
    end

    local root = _G.ProjectEbonhold
    if type(root) == "table" then
        local rootFields = { "ObjectiveDefinitions", "ObjectivesCatalog", "ObjectiveCatalog", "CallboardQuests", "QuestPool" }
        for i = 1, table.getn(rootFields) do addTable(root[rootFields[i]], "ProjectEbonhold." .. rootFields[i]) end
    end

    -- Current offers are also free to read and are useful for passive verification.
    addTable(PE.GetObjectives(), PE.lastObjectivesSource or "current objectives")
    return sources
end

function PE.GetActiveObjective()
    local service = PE.GetService()
    local ok, method, objective = callServiceMethod(service, {
        "GetActiveObjective", "GetSelectedObjective", "GetCurrentObjective"
    })
    if ok and type(objective) == "table" then
        PE.lastActiveSource = tostring(PE.lastServicePath) .. "." .. tostring(method)
        return objective
    end
    objective, method = serviceTableField(service, { "activeObjective", "selectedObjective", "currentObjective" })
    if type(objective) == "table" then
        PE.lastActiveSource = tostring(PE.lastServicePath) .. "." .. tostring(method)
        return objective
    end
    PE.lastActiveSource = nil
    return nil
end

function PE.CanAffordReroll()
    local service = PE.GetService()
    local ok, method, result = callServiceMethod(service, { "CanAffordReroll", "CanReroll", "CanAffordRefresh" })
    if ok then
        debug("service", "affordability via " .. tostring(method) .. "=" .. tostring(result))
        return result ~= false
    end
    return true
end

function PE.GetRerollCost()
    local service = PE.GetService()
    local ok, _, result = callServiceMethod(service, { "GetRerollCost", "GetRefreshCost", "GetRerollPrice" })
    if ok then return tonumber(result) or 0 end
    if type(service) == "table" then
        return tonumber(service.rerollCost or service.refreshCost or service.rerollPrice) or 0
    end
    return 0
end

function PE.GetSummonCooldownRemaining()
    if not GetSpellCooldown then
        return 0
    end

    local function remainingFor(spell)
        local start, duration = GetSpellCooldown(spell)
        start = tonumber(start) or 0
        duration = tonumber(duration) or 0
        if start > 0 and duration > 1.5 then
            return math.max(0, start + duration - (GetTime and GetTime() or 0))
        end
        return 0
    end

    local remaining = remainingFor(PE.SUMMON_SPELL_ID)
    if remaining <= 0 then
        remaining = remainingFor(PE.SUMMON_SPELL_NAME)
    end
    return remaining
end

local BOARD_FRAME_NAMES = {
    "ObjectivesMainFrame", "CallboardMainFrame", "CallBoardMainFrame", "CallboardFrame",
    "CallBoardFrame", "ObjectivesFrame", "EbonholdCallboardFrame"
}

local OBJECTIVE_FRAME_PREFIXES = { "ObjectiveFrame", "CallboardObjectiveFrame", "CallBoardObjectiveFrame", "ObjectiveOfferFrame" }

local function frameLooksLikeObjectivesBoard(frame, name)
    if not frame or not isEffectivelyVisible(frame) then return false end
    local lname = string.lower(tostring(name or ""))
    if string.find(lname, "callboard", 1, true)
        or (string.find(lname, "objective", 1, true) and string.find(lname, "frame", 1, true)) then
        return true
    end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, table.getn(regions) do
            local region = regions[i]
            if region and region.GetText then
                local ok, value = pcall(region.GetText, region)
                local txt = ok and string.lower(tostring(value or "")) or ""
                if txt == "objectives" or txt == "objectives board"
                    or string.find(txt, "reroll selection", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function discoverVisibleBoardFrame()
    if PE.discoveredBoardFrameName then
        local cached = _G[PE.discoveredBoardFrameName]
        if frameLooksLikeObjectivesBoard(cached, PE.discoveredBoardFrameName) then
            return cached, PE.discoveredBoardFrameName
        end
    end
    if not EnumerateFrames then return nil, nil end
    local frame = EnumerateFrames()
    local checked = 0
    while frame and checked < 2500 do
        checked = checked + 1
        local name = frame.GetName and frame:GetName() or nil
        if name and frameLooksLikeObjectivesBoard(frame, name) then
            PE.discoveredBoardFrameName = name
            debug("board", "discovered Objectives UI frame=" .. tostring(name))
            return frame, name
        end
        frame = EnumerateFrames(frame)
    end
    return nil, nil
end

local function findVisibleBoardFrame()
    for i = 1, table.getn(BOARD_FRAME_NAMES) do
        local name = BOARD_FRAME_NAMES[i]
        local frame = _G[name]
        if frame and isEffectivelyVisible(frame) then return frame, name end
    end
    local dynamicFrame, dynamicName = discoverVisibleBoardFrame()
    if dynamicFrame then return dynamicFrame, dynamicName end
    return nil, nil
end

local function anyObjectiveFrameVisible()
    for p = 1, table.getn(OBJECTIVE_FRAME_PREFIXES) do
        for i = 1, 8 do
            local name = OBJECTIVE_FRAME_PREFIXES[p] .. tostring(i)
            if isEffectivelyVisible(_G[name]) then return true, name end
        end
    end
    return false, nil
end

function PE.IsBoardVisible()
    local frame, frameName = findVisibleBoardFrame()
    if frame then
        PE.lastBoardFrameName = frameName
        PE.MarkBoardAccess(30)
        return true
    end

    local objectiveVisible, objectiveName = anyObjectiveFrameVisible()
    if objectiveVisible then
        PE.lastBoardFrameName = objectiveName
        PE.MarkBoardAccess(30)
        return true
    end

    if gossipIsCallboard() then
        PE.lastBoardFrameName = "GossipFrame"
        PE.MarkBoardAccess(30)
        return true
    end
    PE.lastBoardFrameName = nil
    return false
end

function PE.ConfirmReroll()
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. tostring(i)]
        if popup and popup.IsShown and popup:IsShown() then
            debug("popup", "StaticPopup" .. tostring(i) .. " shown which=" .. tostring(popup.which))
        end
        local which = popup and tostring(popup.which or "") or ""
        local rerollPopup = which == "EBONHOLD_CONFIRM_REROLL" or string.find(string.lower(which), "reroll", 1, true)
        if popup and popup.IsShown and popup:IsShown() and rerollPopup then
            local clicked = clickFrame(_G["StaticPopup" .. tostring(i) .. "Button1"])
            debug("confirm", "reroll popup button click=" .. tostring(clicked) .. " popup=" .. tostring(i))
            return clicked
        end
    end
    return false
end

function PE.RequestReroll()
    local access = PE.HasBoardAccess()
    debug("reroll", "RequestReroll entered access=" .. tostring(access))
    if not access then
        return false, "board_closed"
    end

    local afford = PE.CanAffordReroll()
    debug("reroll", "CanAffordReroll=" .. tostring(afford) .. " cost=" .. tostring(PE.GetRerollCost()))
    if not afford then
        return false, "no_gold"
    end

    local service = PE.GetService()
    local serviceOK, serviceMethod = callServiceMethod(service, {
        "RequestRerollObjectives", "RequestReroll", "RerollObjectives", "Reroll", "RequestRefresh"
    })
    debug("service", "GetService=" .. tostring(service) .. " path=" .. tostring(PE.lastServicePath) .. " rerollMethod=" .. tostring(serviceMethod))
    if serviceOK then
        local confirmed = PE.ConfirmReroll()
        debug("reroll", "service request sent via " .. tostring(serviceMethod) .. "; immediate confirmation=" .. tostring(confirmed))
        return true
    end

    local target = resolvePath("ObjectivesMainFrame.rerollBtn")
        or resolvePath("CallboardMainFrame.rerollBtn")
        or resolvePath("CallboardMainFrame.refreshBtn")
        or resolvePath("CallboardFrame.rerollBtn")
        or resolvePath("CallboardFrame.refreshBtn")
    debug("fallback", "service unavailable; reroll/refresh button=" .. tostring(target))
    if clickFrame(target) then
        local confirmed = PE.ConfirmReroll()
        debug("fallback", "reroll button clicked; confirmation=" .. tostring(confirmed))
        return true
    end
    return false, "unavailable"
end

function PE.SelectObjective(index)
    if not index then
        return false
    end

    local service = PE.GetService()
    local ok, method = callServiceMethod(service, { "SelectObjective", "ChooseObjective" }, index)
    if ok then
        debug("service", "objective selection via " .. tostring(method) .. " index=" .. tostring(index))
        return true
    end

    if ProjectEbonhold and ProjectEbonhold.sendToServer and ProjectEbonhold.CS
        and ProjectEbonhold.CS.REQUEST_SELECT_OBJECTIVE then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_SELECT_OBJECTIVE, tostring(index - 1))
        return true
    end

    for p = 1, table.getn(OBJECTIVE_FRAME_PREFIXES) do
        local frame = _G[OBJECTIVE_FRAME_PREFIXES[p] .. tostring(index)]
        if frame and clickFrame(frame.selectBtn or frame.selectButton or frame.chooseBtn or frame.chooseButton) then
            return true
        end
        if frame and clickFrame(frame) then return true end
    end
    return false
end

function PE.CloseBoard()
    if ProjectEbonhold then
        local uiCandidates = { ProjectEbonhold.ObjectivesUI, ProjectEbonhold.CallboardUI, ProjectEbonhold.CallBoardUI }
        for i = 1, table.getn(uiCandidates) do
            local ui = uiCandidates[i]
            if type(ui) == "table" then
                local ok = callServiceMethod(ui, { "HideObjectives", "HideCallboard", "Hide", "Close" })
                if ok then return end
            end
        end
    end
    for i = 1, table.getn(BOARD_FRAME_NAMES) do
        local frame = _G[BOARD_FRAME_NAMES[i]]
        if frame and frame.Hide then frame:Hide(); return end
    end
end

function PE.HideBoardVisuals()
    -- Keep the genuine Ebonhold Callboard fully alive and fully rendered, but park
    -- its top-level presentation off-screen. Alpha/child cloaking looked cleaner,
    -- but it interfered with Ebonhold's live offer/update path on some clients and
    -- could make Zen reroll forever without ever observing the wanted quest.
    PE.parkedBoardFrames = PE.parkedBoardFrames or {}

    local function parkFrame(frame, label)
        if not frame or not isEffectivelyVisible(frame) or PE.parkedBoardFrames[frame] then return end
        if not (frame.GetNumPoints and frame.GetPoint and frame.ClearAllPoints and frame.SetPoint) then return end

        local state = {
            label = label,
            points = {},
            mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or nil,
            alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        }
        local count = frame:GetNumPoints() or 0
        for i = 1, count do
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
            state.points[#state.points + 1] = { point, relativeTo, relativePoint, x, y }
        end
        PE.parkedBoardFrames[frame] = state

        if frame.SetClampedToScreen then pcall(frame.SetClampedToScreen, frame, false) end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -3000, -3000)
        if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
        debug("board", "parked Callboard frame off-screen=" .. tostring(label or (frame.GetName and frame:GetName()) or "unnamed"))
    end

    local frame, frameName = findVisibleBoardFrame()
    parkFrame(frame, frameName)

    for i = 1, table.getn(BOARD_FRAME_NAMES) do
        parkFrame(_G[BOARD_FRAME_NAMES[i]], BOARD_FRAME_NAMES[i])
    end

    -- QueueInteract can also expose a greeting/gossip shell. Park that shell too,
    -- but do not touch child controls or their alpha/state.
    parkFrame(_G.GossipFrame, "GossipFrame")

    if EnumerateFrames then
        local candidate = EnumerateFrames()
        local checked = 0
        while candidate and checked < 2500 do
            checked = checked + 1
            if isEffectivelyVisible(candidate) and candidate.GetRegions then
                local hasGreeting, hasGoodbye, hasReroll = false, false, false
                local regions = { candidate:GetRegions() }
                for r = 1, table.getn(regions) do
                    local region = regions[r]
                    if region and region.GetText then
                        local ok, value = pcall(region.GetText, region)
                        local txt = ok and string.lower(tostring(value or "")) or ""
                        if string.find(txt, "greetings,", 1, true) then hasGreeting = true end
                        if txt == "goodbye" then hasGoodbye = true end
                        if string.find(txt, "reroll selection", 1, true) then hasReroll = true end
                    end
                end
                if hasGreeting or hasGoodbye or hasReroll then
                    parkFrame(candidate, candidate.GetName and candidate:GetName() or "Callboard shell")
                end
            end
            candidate = EnumerateFrames(candidate)
        end
    end
end

function PE.RestoreBoardVisualsInvisible()
    if not PE.parkedBoardFrames then return end
    PE.invisibleRestoredBoardFrames = PE.invisibleRestoredBoardFrames or {}

    for frame, state in pairs(PE.parkedBoardFrames) do
        if frame then
            if frame.ClearAllPoints and frame.SetPoint then
                pcall(frame.ClearAllPoints, frame)
                for i = 1, table.getn(state.points or {}) do
                    local pt = state.points[i]
                    pcall(frame.SetPoint, frame, pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            -- Put the genuine frame back where Ebonhold expects it for selection,
            -- but keep only the top-level presentation transparent. We do this
            -- only after the wanted offer has already been found, never while
            -- rerolling/reading offers.
            if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
            if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
            PE.invisibleRestoredBoardFrames[frame] = state
        end
    end
    PE.parkedBoardFrames = {}
end

function PE.RestoreBoardVisuals()
    local function restoreSet(frames)
        if not frames then return end
        for frame, state in pairs(frames) do
            if frame then
                if frame.ClearAllPoints and frame.SetPoint then
                    pcall(frame.ClearAllPoints, frame)
                    for i = 1, table.getn(state.points or {}) do
                        local pt = state.points[i]
                        pcall(frame.SetPoint, frame, pt[1], pt[2], pt[3], pt[4], pt[5])
                    end
                end
                if frame.SetAlpha then pcall(frame.SetAlpha, frame, state.alpha or 1) end
                if frame.EnableMouse and state.mouse ~= nil then pcall(frame.EnableMouse, frame, state.mouse) end
            end
        end
    end

    restoreSet(PE.parkedBoardFrames)
    restoreSet(PE.invisibleRestoredBoardFrames)
    PE.parkedBoardFrames = {}
    PE.invisibleRestoredBoardFrames = {}
end

function PE.GetCompatibilityDiagnostics()
    local lines = {}
    local root = _G.ProjectEbonhold
    local service = PE.GetService()
    local frame, frameName = findVisibleBoardFrame()
    local objectiveVisible, objectiveFrameName = anyObjectiveFrameVisible()
    local objectives = PE.GetObjectives()
    local active = PE.GetActiveObjective()
    local methodNames = {}
    if type(service) == "table" then
        local names = {
            "RequestObjectives", "RequestCurrentObjectives", "GetCurrentObjectives", "GetObjectives",
            "GetActiveObjective", "RequestRerollObjectives", "RequestReroll", "Reroll",
            "CanAffordReroll", "GetRerollCost", "SelectObjective"
        }
        for i = 1, table.getn(names) do
            if type(service[names[i]]) == "function" then methodNames[#methodNames + 1] = names[i] end
        end
    end
    lines[#lines + 1] = "ProjectEbonhold=" .. tostring(type(root)) .. " service=" .. tostring(PE.lastServicePath or "none")
    lines[#lines + 1] = "service methods=" .. (#methodNames > 0 and table.concat(methodNames, ",") or "none detected")
    lines[#lines + 1] = "board frame=" .. tostring(frameName or objectiveFrameName or PE.lastBoardFrameName or "none") .. " visible=" .. tostring(frame ~= nil or objectiveVisible)
    lines[#lines + 1] = "gossip npc=" .. tostring(UnitName and UnitName("npc") or "nil") .. " gossipCallboard=" .. tostring(gossipIsCallboard())
    lines[#lines + 1] = "objectives=" .. tostring(type(objectives) == "table" and table.getn(objectives) or 0) .. " source=" .. tostring(PE.lastObjectivesSource or "none") .. " active=" .. tostring(type(active))
    lines[#lines + 1] = "sendToServer=" .. tostring(type(root) == "table" and type(root.sendToServer) or "nil") .. " selectOpcode=" .. tostring(type(root) == "table" and root.CS and root.CS.REQUEST_SELECT_OBJECTIVE or "nil")
    return lines
end
