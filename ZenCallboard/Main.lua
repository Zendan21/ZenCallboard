local ADDON_NAME, Addon = ...
local Core = Addon.Core
local PE = Addon.PE
local UI = Addon.UI
local Group = Addon.Group

local PREFIX = "|cffb58cffZenCallboard:|r "
local eventFrame = CreateFrame("Frame")

Addon.db = nil
Addon.profile = nil
Addon.profileKey = nil
Addon.running = false
Addon.paused = false
Addon.routeSessionArmed = false
Addon.instanceAutoActive = false
Addon.statusMessage = "Ready."
Addon.rerollCount = 0
Addon.sessionCost = 0
Addon.goldBeforeReroll = nil
Addon.lastLearnedObjectiveSignature = nil
Addon.runnerState = "IDLE"
Addon.pendingReroll = nil
Addon.pendingAccept = nil
Addon.waitingKey = nil
Addon.waitingSeenInLog = false
Addon.waitingSeenActiveObjective = false
Addon.waitingWasComplete = false
Addon.closeBoardAt = nil
Addon.nextActionAt = nil
Addon.nextObjectiveRequestAt = nil
Addon.lastBoardVisible = false
Addon.pendingBoardOpen = nil
Addon.lastSummonCooldownRemaining = nil
Addon.lastRecordedCompletionKey = nil
Addon.lastRecordedCompletionAt = 0
Addon.waitingMissingAt = nil
Addon.waitingMissingKey = nil
Addon.deathProtectionUntil = 0
local recordCompletionEvent
local knownKeyForQuestID
Addon.initialized = false
Addon.diagnosticRoll = false
Addon.diagnosticLastSignature = nil
Addon.discoveryActive = false
Addon.discoveryConfirmUntil = nil
Addon.discoveryNoNewStreak = 0
Addon.discoveryLastSignature = nil
Addon.discoveryLastKnownCount = 0
Addon.passiveLearnUntil = nil

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(message or ""))
    end
end

local function now()
    return GetTime and GetTime() or 0
end

local function routeCount()
    return Addon.profile and table.getn(Addon.profile.route or {}) or 0
end

local function currentKey()
    if not Addon.profile then
        return nil
    end
    return Addon.profile.route[Addon.profile.currentStep]
end

local INSTANCE_ZONE_ALIASES = {
    ["naxxramas"] = 3456,
    ["naxx"] = 3456,
    ["ulduar"] = 4273,
    ["obsidian sanctum"] = 4493,
    ["the obsidian sanctum"] = 4493,
    ["oculus"] = 4228,
    ["the oculus"] = 4228,
    ["nexus"] = 4265,
    ["the nexus"] = 4265,
    ["halls of lightning"] = 4272,
    ["azjol-nerub"] = 4277,
    ["azjol nerub"] = 4277,
    ["ahn'kahet"] = 4494,
    ["ahn'kahet: the old kingdom"] = 4494,
    ["drak'tharon keep"] = 4196,
    ["gundrak"] = 4416,
    ["utgarde keep"] = 206,
    ["utgarde pinnacle"] = 1196,
    ["eye of eternity"] = 4500,
    ["the eye of eternity"] = 4500,
}

local RAID_ZONE_IDS = { [3456] = true, [4273] = true, [4493] = true, [4500] = true }
local INSTANCE_MATCH_ALIASES = {
    [3456] = { "naxxramas", "kel'thuzad", "kelthuzad" },
    [4273] = { "ulduar", "yogg-saron", "yogg saron" },
    [4493] = { "obsidian sanctum", "sartharion" },
    [4500] = { "eye of eternity", "malygos" },
    [4228] = { "oculus", "eregos" },
    [4265] = { "nexus", "keristrasza" },
    [4272] = { "halls of lightning", "loken" },
    [4277] = { "azjol-nerub", "azjol nerub", "anub'arak", "anubarak" },
    [4494] = { "ahn'kahet", "old kingdom", "volazj" },
    [4196] = { "drak'tharon", "tharon'ja", "tharonja" },
    [4416] = { "gundrak", "gal'darah", "galdarah" },
    [206] = { "utgarde keep", "ingvar" },
    [1196] = { "utgarde pinnacle", "ymiron" },
}

local function normalizedInstanceName(value)
    value = Core.NormalizeTitle(value or "")
    return string.gsub(value, "^the%s+", "")
end

local function zoneIDForInstanceName(name)
    local normalized = normalizedInstanceName(name)
    if normalized == "" then
        return nil
    end

    local zoneID = INSTANCE_ZONE_ALIASES[normalized]
    if zoneID then
        return zoneID, Core.ZONE_NAMES[zoneID] or name
    end

    -- Some Ebonhold builds append difficulty/wing text to the instance name.
    for alias, aliasZoneID in pairs(INSTANCE_ZONE_ALIASES) do
        local normalizedAlias = normalizedInstanceName(alias)
        if string.find(normalized, normalizedAlias, 1, true) then
            return aliasZoneID, Core.ZONE_NAMES[aliasZoneID] or name
        end
    end
    return nil
end

local cachedInstanceScanAt = -1
local cachedInstanceZoneID = nil
local cachedInstanceZoneName = nil
local lastInstanceDebugKey = nil

local function currentInstanceZoneID()
    local scanNow = now()
    if cachedInstanceScanAt >= 0 and scanNow - cachedInstanceScanAt < 1.0 then
        return cachedInstanceZoneID, cachedInstanceZoneName
    end
    cachedInstanceScanAt = scanNow

    local inInstance = false
    local instanceType = nil
    if IsInInstance then
        local ok, inside, kind = pcall(IsInInstance)
        if ok then
            inInstance = inside == true or tonumber(inside) == 1
            instanceType = kind
        end
    end

    local names = {}
    local function addName(source, value)
        if type(value) == "string" and value ~= "" then
            for index = 1, table.getn(names) do
                if names[index].value == value then
                    return
                end
            end
            table.insert(names, { source = source, value = value })
        end
    end

    if GetInstanceInfo then
        local ok, name, kind = pcall(GetInstanceInfo)
        if ok then
            addName("GetInstanceInfo", name)
            if (not instanceType or instanceType == "none") and type(kind) == "string" then
                instanceType = kind
            end
        end
    end
    if GetRealZoneText then
        local ok, value = pcall(GetRealZoneText)
        if ok then addName("GetRealZoneText", value) end
    end
    if GetZoneText then
        local ok, value = pcall(GetZoneText)
        if ok then addName("GetZoneText", value) end
    end
    if GetSubZoneText then
        local ok, value = pcall(GetSubZoneText)
        if ok then addName("GetSubZoneText", value) end
    end
    if GetMinimapZoneText then
        local ok, value = pcall(GetMinimapZoneText)
        if ok then addName("GetMinimapZoneText", value) end
    end

    -- Only names from the explicit dungeon/raid alias table are eligible.
    -- Outdoor catalogue zones such as Wintergrasp, Icecrown, Storm Peaks and
    -- Crystalsong must never trigger instance-priority mode.
    for index = 1, table.getn(names) do
        local item = names[index]
        local zoneID, zoneName = zoneIDForInstanceName(item.value)
        if zoneID then
            cachedInstanceZoneID = zoneID
            cachedInstanceZoneName = zoneName
            local debugKey = tostring(zoneID) .. "|" .. tostring(item.source) .. "|" .. tostring(item.value)
                .. "|" .. tostring(inInstance) .. "|" .. tostring(instanceType)
            if debugKey ~= lastInstanceDebugKey then
                lastInstanceDebugKey = debugKey
                Addon:Debug("instance",
                    "detected instance zoneID=" .. tostring(zoneID)
                    .. " zone=" .. tostring(zoneName)
                    .. " source=" .. tostring(item.source)
                    .. " reported=" .. tostring(item.value)
                    .. " inInstance=" .. tostring(inInstance)
                    .. " type=" .. tostring(instanceType))
            end
            return zoneID, zoneName
        end
    end

    cachedInstanceZoneID = nil
    cachedInstanceZoneName = nil

    if inInstance or instanceType == "raid" or instanceType == "party" then
        local reported = {}
        for index = 1, table.getn(names) do
            table.insert(reported, tostring(names[index].source) .. "=" .. tostring(names[index].value))
        end
        local debugKey = "unmatched|" .. table.concat(reported, "|")
            .. "|" .. tostring(inInstance) .. "|" .. tostring(instanceType)
        if debugKey ~= lastInstanceDebugKey then
            lastInstanceDebugKey = debugKey
            Addon:Debug("instance",
                "instance detected but no Callboard zone alias matched: "
                .. table.concat(reported, " | ")
                .. " inInstance=" .. tostring(inInstance)
                .. " type=" .. tostring(instanceType))
        end
    else
        lastInstanceDebugKey = nil
    end
    return nil
end

local lastContextDebugKey = nil

local function contextPriorityKey()
    if not Addon.db or not Addon.db.knownQuests then
        return nil
    end
    local zoneID, zoneName = currentInstanceZoneID()
    if not zoneID then
        Addon.contextInstanceZoneID = nil
        Addon.contextHandledKey = nil
        lastContextDebugKey = nil
        return nil
    end

    if Addon.contextInstanceZoneID ~= zoneID then
        Addon.contextInstanceZoneID = zoneID
        Addon.contextHandledKey = nil
    end

    local normalKey = currentKey()
    local candidates = {}
    for key, quest in pairs(Addon.db.knownQuests) do
        if tonumber(quest.zoneOrSort) == zoneID and key ~= normalKey then
            table.insert(candidates, key)
        end
    end
    table.sort(candidates, function(left, right)
        local lq = Addon.db.knownQuests[left]
        local rq = Addon.db.knownQuests[right]
        return Core.NormalizeTitle(Core.QuestTitle(lq)) < Core.NormalizeTitle(Core.QuestTitle(rq))
    end)

    local contextDebugKey = tostring(zoneID) .. "|" .. tostring(table.getn(candidates))
        .. "|" .. tostring(normalKey) .. "|" .. tostring(Addon.contextHandledKey)
    if contextDebugKey ~= lastContextDebugKey then
        lastContextDebugKey = contextDebugKey
        Addon:Debug("context", "instance=" .. tostring(zoneName)
            .. " zoneID=" .. tostring(zoneID)
            .. " candidateCount=" .. tostring(table.getn(candidates))
            .. " normalRoute=" .. tostring(normalKey))
    end

    for index = 1, table.getn(candidates) do
        local key = candidates[index]
        local completed = false
        local quest = Addon.db.knownQuests[key]
        local questID = quest and Core.QuestID(quest)
        if questID and IsQuestFlaggedCompleted then
            local ok, value = pcall(IsQuestFlaggedCompleted, questID)
            completed = ok and (value == true or tonumber(value) == 1)
        end
        if key ~= Addon.contextHandledKey and not completed then
            return key, zoneName
        end
    end
    return nil
end

local function currentInstanceContext()
    local zoneID, zoneName = currentInstanceZoneID()
    if not zoneID then
        Addon.contextInstanceZoneID = nil
        Addon.contextHandledKey = nil
        return nil
    end
    if Addon.contextInstanceZoneID ~= zoneID then
        Addon.contextInstanceZoneID = zoneID
        Addon.contextHandledKey = nil
    end
    return zoneID, zoneName
end

local function instanceRepeatLockState(zoneID)
    if not zoneID or not Addon.db or type(Addon.db.knownQuests) ~= "table" then
        return nil, 0
    end
    local foundCandidate = false
    local lockedKey = nil
    local smallestRemaining = Core.REPEAT_LOCKOUT_COUNT
    for key, quest in pairs(Addon.db.knownQuests) do
        if tonumber(quest.zoneOrSort) == tonumber(zoneID) then
            foundCandidate = true
            local remaining = Core.RepeatLockRemaining(Addon.profile and Addon.profile.recentCompletedQuests, key)
            if remaining <= 0 then
                return nil, 0 -- at least one eligible quest exists for this instance
            end
            if not lockedKey or remaining < smallestRemaining then
                lockedKey = key
                smallestRemaining = remaining
            end
        end
    end
    if foundCandidate and lockedKey then
        return lockedKey, smallestRemaining
    end
    return nil, 0
end

local function objectiveMatchesInstance(quest, zoneID)
    if type(quest) ~= "table" or not zoneID then return false end
    if tonumber(quest.zoneOrSort or quest.zoneId or quest.zoneID) == tonumber(zoneID) then
        return true
    end
    local wantedType = RAID_ZONE_IDS[tonumber(zoneID)] and 3 or 2
    local questType = tonumber(quest.questType or quest.type)
    if questType and questType > 0 and questType ~= wantedType then return false end
    local blob = Core.NormalizeTitle(Core.QuestTitle(quest) .. " " .. tostring(quest.objectiveText or quest.description or quest.text or ""))
    local aliases = INSTANCE_MATCH_ALIASES[tonumber(zoneID)] or {}
    for i = 1, table.getn(aliases) do
        if string.find(blob, Core.NormalizeTitle(aliases[i]), 1, true) then return true end
    end
    return false
end

local function findInstanceObjective(objectives, zoneID)
    if type(objectives) ~= "table" or not zoneID then return nil end
    for index = 1, table.getn(objectives) do
        local quest = objectives[index]
        local questID = Core.QuestID(quest)
        local completed = false
        if questID and IsQuestFlaggedCompleted then
            local ok, value = pcall(IsQuestFlaggedCompleted, questID)
            completed = ok and (value == true or tonumber(value) == 1)
        end
        if not completed and objectiveMatchesInstance(quest, zoneID) then
            return index, Core.QuestKey(quest)
        elseif completed and objectiveMatchesInstance(quest, zoneID) then
            Addon:Debug("context", "skipping completed instance offer " .. tostring(Core.QuestTitle(quest)) .. " #" .. tostring(questID))
        end
    end
    return nil
end

local function priorityKey()
    local contextKey = contextPriorityKey()
    return contextKey or currentKey(), contextKey ~= nil
end

local function routeContainsKey(wantedKey)
    if not wantedKey or not Addon.profile or type(Addon.profile.route) ~= "table" then
        return false
    end
    for index = 1, table.getn(Addon.profile.route) do
        if Addon.profile.route[index] == wantedKey then
            return true
        end
    end
    return false
end

local function objectiveIsCompleted(quest)
    local questID = Core.QuestID(quest)
    if not questID or not IsQuestFlaggedCompleted then return false end
    local ok, value = pcall(IsQuestFlaggedCompleted, questID)
    return ok and (value == true or tonumber(value) == 1)
end

local function firstOfferedRouteQuest(objectives)
    if type(objectives) ~= "table" or not Addon.profile or Addon.profile.ignoreOrder ~= true then return nil end
    for offerIndex = 1, table.getn(objectives) do
        local objective = objectives[offerIndex]
        local offeredKey = Core.QuestKey(objective)
        if offeredKey and routeContainsKey(offeredKey) and not objectiveIsCompleted(objective) then
            return offerIndex, offeredKey
        end
    end
    return nil
end

local function questForKey(key)
    return key and Addon.db and Addon.db.knownQuests[key] or nil
end

local function questLabel(key)
    local quest = questForKey(key)
    if not quest then
        return tostring(key or "unknown quest")
    end
    return Core.QuestTitle(quest) ~= "" and Core.QuestTitle(quest) or tostring(key)
end

local function coinText(copper)
    if not copper or copper <= 0 then
        return nil
    end
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. " copper"
end

local function ensureGoldStats()
    if not Addon.profile then return nil end
    Addon.profile.goldStats = Addon.profile.goldStats or { totalSpent = 0, rerolls = 0, lastSearchSpent = 0, lastSearchRerolls = 0, sessionSpent = 0, sessionRerolls = 0 }
    return Addon.profile.goldStats
end

local function beginRerollGoldTracking()
    Addon.goldBeforeReroll = GetMoney and tonumber(GetMoney()) or nil
end

local function syncRerollGoldTracking()
    if Addon.goldBeforeReroll == nil then return 0 end
    local before = tonumber(Addon.goldBeforeReroll) or 0
    Addon.goldBeforeReroll = nil
    local current = GetMoney and tonumber(GetMoney()) or before
    local delta = math.max(0, math.floor(before - current))
    if delta <= 0 then
        delta = math.max(0, math.floor(tonumber(PE.GetRerollCost and PE.GetRerollCost() or 0) or 0))
    end
    if delta > 0 then
        Addon.sessionCost = math.max(0, math.floor((Addon.sessionCost or 0) + delta))
        local stats = ensureGoldStats()
        if stats then
            stats.totalSpent = math.max(0, math.floor((stats.totalSpent or 0) + delta))
            stats.rerolls = math.max(0, math.floor((stats.rerolls or 0) + 1))
            stats.sessionSpent = math.max(0, math.floor((stats.sessionSpent or 0) + delta))
            stats.sessionRerolls = math.max(0, math.floor((stats.sessionRerolls or 0) + 1))
        end
    end
    return delta
end

local function finalizeSearchSpend()
    syncRerollGoldTracking()
    local stats = ensureGoldStats()
    if stats then
        stats.lastSearchSpent = math.max(0, math.floor(Addon.sessionCost or 0))
        stats.lastSearchRerolls = math.max(0, math.floor(Addon.rerollCount or 0))
    end
end

local function setRunnerState(state)
    Addon.runnerState = state or "IDLE"
end

function Addon:SetStatus(message, announce)
    message = tostring(message or "")
    if self.statusMessage ~= message then
        self.statusMessage = message
        if announce then
            Print(message)
        end
        if UI and UI.Refresh then
            UI:Refresh()
        end
    end
end


-- 1.0.9 diagnostic logging. Stored in SavedVariables so /reload will not
-- erase the trace while we isolate the Ebonhold Callboard reroll path.
local function ensureDebugLog()
    if not Addon.db then
        return nil
    end
    Addon.db.debugLog = Addon.db.debugLog or {}
    return Addon.db.debugLog
end

function Addon:Debug(kind, message)
    local log = ensureDebugLog()
    if not log then
        return
    end
    table.insert(log, {
        time = now(),
        kind = tostring(kind or "info"),
        message = tostring(message or ""),
    })
    while table.getn(log) > 250 do
        table.remove(log, 1)
    end
end

function Addon:ClearDebugLog()
    if self.db then
        self.db.debugLog = {}
    end
end

local debugFrame
local debugEdit

local function buildDebugText()
    local lines = {}
    table.insert(lines, "ZenCallboard diagnostics")
    table.insert(lines, "Version: 1.0.74")
    table.insert(lines, "Generated: " .. tostring(date and date("%Y-%m-%d %H:%M:%S") or "unknown"))
    table.insert(lines, "")
    local log = Addon.db and Addon.db.debugLog or {}
    if table.getn(log) == 0 then
        table.insert(lines, "(debug log is empty)")
    else
        for i = 1, table.getn(log) do
            local e = log[i]
            table.insert(lines, string.format("[%03d] %.3f [%s] %s", i, tonumber(e.time) or 0, tostring(e.kind or "info"), tostring(e.message or "")))
        end
    end
    return table.concat(lines, "\n")
end

function Addon:ShowDebugLog()
    if not debugFrame then
        debugFrame = CreateFrame("Frame", "ZenCallboardDebugFrame", UIParent)
        debugFrame:SetWidth(700)
        debugFrame:SetHeight(460)
        debugFrame:SetPoint("CENTER")
        debugFrame:SetFrameStrata("DIALOG")
        debugFrame:SetMovable(true)
        debugFrame:EnableMouse(true)
        debugFrame:RegisterForDrag("LeftButton")
        debugFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        debugFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        local bg = debugFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(debugFrame)
        bg:SetTexture(0.03, 0.04, 0.05, 0.96)

        local title = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("ZenCallboard Diagnostics")

        local hint = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 14, -36)
        hint:SetText("Diagnostic information for troubleshooting ZenCallboard. Ctrl+A then Ctrl+C to copy.")

        local scroll = CreateFrame("ScrollFrame", "ZenCallboardDebugScroll", debugFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -58)
        scroll:SetPoint("BOTTOMRIGHT", -34, 48)

        debugEdit = CreateFrame("EditBox", "ZenCallboardDebugEdit", scroll)
        debugEdit:SetMultiLine(true)
        debugEdit:SetAutoFocus(false)
        debugEdit:SetFontObject(ChatFontNormal)
        debugEdit:SetWidth(635)
        debugEdit:SetTextInsets(4, 4, 4, 4)
        debugEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        debugEdit:SetScript("OnTextChanged", function() scroll:UpdateScrollChildRect() end)
        scroll:SetScrollChild(debugEdit)

        local refresh = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
        refresh:SetWidth(90)
        refresh:SetHeight(24)
        refresh:SetPoint("BOTTOMLEFT", 14, 14)
        refresh:SetText("Refresh")
        refresh:SetScript("OnClick", function()
            debugEdit:SetText(buildDebugText())
        end)

        local clear = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
        clear:SetWidth(90)
        clear:SetHeight(24)
        clear:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
        clear:SetText("Clear")
        clear:SetScript("OnClick", function()
            Addon:ClearDebugLog()
            Addon:Debug("debug", "log cleared by user")
            debugEdit:SetText(buildDebugText())
        end)

        local close = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
        close:SetWidth(90)
        close:SetHeight(24)
        close:SetPoint("BOTTOMRIGHT", -14, 14)
        close:SetText("Close")
        close:SetScript("OnClick", function() debugFrame:Hide() end)
    end

    debugEdit:SetText(buildDebugText())
    debugFrame:Show()
    debugEdit:SetFocus()
    debugEdit:HighlightText()
end

local function resetRuntime()
    Addon.pendingReroll = nil
    Addon.pendingAccept = nil
    Addon.waitingKey = nil
    Addon.waitingSeenInLog = false
    Addon.waitingSeenActiveObjective = false
    Addon.waitingWasComplete = false
    Addon.closeBoardAt = nil
    Addon.nextActionAt = nil
    Addon.rerollCount = 0
    Addon.sessionCost = 0
    Addon.diagnosticRoll = false
    Addon.diagnosticLastSignature = nil
end

local function cleanRouteName(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function getQuestLogEntry(index)
    if not GetQuestLogTitle then
        return nil
    end

    local title, _, _, fourth, fifth, sixth, seventh, eighth, ninth = GetQuestLogTitle(index)
    if not title then
        return nil
    end

    local wrathQuestID = tonumber(ninth)
    if wrathQuestID and wrathQuestID > 0 then
        return {
            title = title,
            isHeader = fifth,
            isComplete = seventh,
            questID = wrathQuestID,
        }
    end

    return {
        title = title,
        isHeader = fourth,
        isComplete = sixth,
        questID = tonumber(eighth),
    }
end

local function questMatchesKey(questID, title, key)
    local wanted = questForKey(key)
    if not wanted then
        return false
    end

    local wantedID = Core.QuestID(wanted)
    questID = tonumber(questID)
    if wantedID and questID and questID > 0 then
        return wantedID == questID
    end

    local wantedTitle = Core.NormalizeTitle(Core.QuestTitle(wanted))
    local actualTitle = Core.NormalizeTitle(title)
    return wantedTitle ~= "" and wantedTitle == actualTitle
end

local function findQuestInLog(key)
    if not GetNumQuestLogEntries then
        return nil
    end

    for index = 1, GetNumQuestLogEntries() do
        local entry = getQuestLogEntry(index)
        if entry and not entry.isHeader and questMatchesKey(entry.questID, entry.title, key) then
            return index, entry
        end
    end
    return nil
end

local function activeObjectiveMatches(key)
    local active = PE.GetActiveObjective()
    return active and Core.QuestKey(active) == key
end

local function questIsFlaggedCompleted(key)
    if not IsQuestFlaggedCompleted then
        return false
    end
    local quest = questForKey(key)
    local questID = quest and Core.QuestID(quest)
    if not questID then
        return false
    end
    local ok, completed = pcall(IsQuestFlaggedCompleted, questID)
    return ok and (completed == true or tonumber(completed) == 1)
end

-- Raid Callboard quest reminder ------------------------------------------------
-- This deliberately does not depend on Route Runner state. If the player enters
-- a supported raid and none of that raid's known Callboard quests are in the
-- quest log, show a reminder.
local raidQuestReminderFrame
local raidReminderDismissedZoneID
local raidReminderLastZoneID
local raidReminderSatisfiedZoneID
local raidReminderNextCheckAt = 0

local function missingRaidCallboardQuest()
    local zoneID, zoneName = currentInstanceZoneID()
    if not zoneID then return nil end

    -- Require an actual raid when the client exposes instance type. Ebonhold can
    -- occasionally report nil/none briefly during zoning, so a known raid alias
    -- remains a valid fallback and will be rechecked every second.
    local inInstance, instanceType = false, nil
    if IsInInstance then
        local ok, inside, kind = pcall(IsInInstance)
        if ok then
            inInstance = inside == true or tonumber(inside) == 1
            instanceType = kind
        end
    end
    if instanceType and instanceType ~= "none" and instanceType ~= "raid" then
        return nil
    end
    if not RAID_ZONE_IDS[tonumber(zoneID)] then return nil end

    -- Use the bundled catalogue here, not learnedQuests. The whole point of this
    -- reminder is that it must work immediately on entering the raid, before the
    -- player has opened a Callboard or learned anything this session.
    local candidates = {}
    if type(Addon.BuiltinCatalog) == "table" then
        for index = 1, table.getn(Addon.BuiltinCatalog) do
            local quest = Addon.BuiltinCatalog[index]
            if tonumber(quest.zoneOrSort) == tonumber(zoneID)
                and tonumber(quest.questType) == 3 then
                table.insert(candidates, {
                    key = tostring(quest.questId or quest.questID or quest.title),
                    quest = quest,
                })
            end
        end
    end

    -- Fall back to the live catalogue if a future raid is learned before the
    -- bundled baseline is updated.
    if table.getn(candidates) == 0 and Addon.db and type(Addon.db.knownQuests) == "table" then
        for key, quest in pairs(Addon.db.knownQuests) do
            if tonumber(quest.zoneOrSort) == tonumber(zoneID)
                and (tonumber(quest.questType) == 3 or RAID_ZONE_IDS[tonumber(zoneID)]) then
                table.insert(candidates, { key = key, quest = quest })
            end
        end
    end
    if table.getn(candidates) == 0 then return nil end

    table.sort(candidates, function(a,b)
        return Core.NormalizeTitle(Core.QuestTitle(a.quest))
            < Core.NormalizeTitle(Core.QuestTitle(b.quest))
    end)

    -- Once we have seen the correct raid quest during this raid visit, the
    -- reminder is satisfied for the rest of the visit. Boss completion can
    -- remove Ebonhold's quest from the quest log immediately; that must NOT
    -- turn a successful run into a new "quest missing" warning.
    if raidReminderSatisfiedZoneID == zoneID then
        return nil, zoneID, zoneName
    end

    -- Check the actual quest book directly by ID/title. Also check the normal
    -- completion flag so a UI reload/relog after killing the boss remains quiet.
    for n=1,table.getn(candidates) do
        local wanted = candidates[n].quest
        local wantedID = tonumber(wanted.questId or wanted.questID)
        local wantedTitle = Core.NormalizeTitle(Core.QuestTitle(wanted))

        if wantedID and IsQuestFlaggedCompleted then
            local ok, completed = pcall(IsQuestFlaggedCompleted, wantedID)
            if ok and (completed == true or tonumber(completed) == 1) then
                raidReminderSatisfiedZoneID = zoneID
                return nil, zoneID, zoneName
            end
        end

        if GetNumQuestLogEntries and GetQuestLogTitle then
            for q=1,GetNumQuestLogEntries() do
                local entry = getQuestLogEntry(q)
                if entry and not entry.isHeader then
                    if (wantedID and tonumber(entry.questID) == wantedID)
                        or (wantedTitle ~= "" and Core.NormalizeTitle(entry.title) == wantedTitle) then
                        raidReminderSatisfiedZoneID = zoneID
                        return nil, zoneID, zoneName
                    end
                end
            end
        end
    end

    local chosen=candidates[1]
    return chosen.key, zoneID, zoneName, chosen.quest
end

local function ensureRaidQuestReminder()
    if raidQuestReminderFrame then return raidQuestReminderFrame end

    local f = CreateFrame("Frame", "ZenCallboardRaidQuestReminder", UIParent)
    f:SetWidth(460)
    f:SetHeight(96)
    f:SetPoint("TOP", UIParent, "TOP", 0, -135)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(0.025, 0.03, 0.04, 0.94)

    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    top:SetHeight(2)
    top:SetTexture(0.85, 0.58, 0.08, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText("ZenCallboard — Raid Quest Missing")

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    body:SetWidth(410)
    body:SetHeight(52)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    if body.SetWordWrap then body:SetWordWrap(true) end
    f.body = body

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function()
        raidReminderDismissedZoneID = raidReminderLastZoneID
        f:Hide()
    end)

    f:Hide()
    raidQuestReminderFrame = f
    return f
end

local function updateRaidQuestReminder(force)
    local scanNow = now()
    if not force and scanNow < raidReminderNextCheckAt then return end
    raidReminderNextCheckAt = scanNow + 1.0

    local key, zoneID, zoneName, reminderQuest = missingRaidCallboardQuest()
    local f = ensureRaidQuestReminder()

    if raidReminderLastZoneID ~= zoneID then
        -- Leaving a raid ends the reminder visit completely. This intentionally
        -- clears both a manual dismissal and the "quest was seen" latch, so a
        -- reset/re-entry always performs a fresh quest-log check.
        raidReminderDismissedZoneID = nil
        raidReminderSatisfiedZoneID = nil
        raidReminderLastZoneID = zoneID
    end

    if not key then
        f:Hide()
        return
    end
    if raidReminderDismissedZoneID == zoneID then
        f:Hide()
        return
    end

    local label = reminderQuest and Core.QuestTitle(reminderQuest) or questLabel(key)
    f.body:SetText("You are in " .. tostring(zoneName or "a supported raid")
        .. " but the Callboard quest " .. tostring(label)
        .. " is not in your quest log. Grab it before continuing.")
    f:Show()
end

local function detailQuestIdentity()
    local questID
    if GetQuestID then
        local ok, value = pcall(GetQuestID)
        if ok then
            questID = tonumber(value)
        end
    end

    local title
    if GetTitleText then
        local ok, value = pcall(GetTitleText)
        if ok and type(value) == "string" then
            title = value
        end
    end
    return questID, title
end

local function learnCurrentObjectives()
    if not Addon.db then
        return 0, {}
    end

    local objectives = PE.GetObjectives()
    local signature = Core.ObjectiveSignature(objectives)
    if signature == Addon.lastLearnedObjectiveSignature then
        return 0, objectives
    end
    Addon.lastLearnedObjectiveSignature = signature
    local added = 0
    for i = 1, table.getn(objectives) do
        local objective = objectives[i]
        if type(objective) == "table" then objective._liveSeen = true end
        if Core.LearnQuest(Addon.db, objective) then added = added + 1 end
        if type(objective) == "table" then objective._liveSeen = nil end
    end
    if added > 0 and UI and UI.Refresh then
        UI:Refresh()
    end
    return added, objectives
end

local function initializeProfile()
    Addon.profileKey = Core.ProfileKey()
    Addon.db.profiles[Addon.profileKey] = Core.MergeProfile(Addon.db.profiles[Addon.profileKey])
    Addon.profile = Addon.db.profiles[Addon.profileKey]
end

local function repeatRuleMessage(key)
    local questText = key and (questLabel(key) .. " is too close to its previous occurrence. ") or ""
    return questText .. "The Callboard requires three Callboard completion events between repeats; space repeated quests at least four route steps apart."
end

local function currentQuestIsRepeatLocked()
    local key = currentKey()
    return key and Core.IsQuestRepeatLocked(Addon.profile and Addon.profile.recentCompletedQuests, key), key
end

local function validateRouteStart(requireBoard)
    -- 1.0.14: log every startup gate. More importantly, repeat-lock state is
    -- no longer a Start-button blocker: processBoard() already owns that rule,
    -- so stale/history data cannot prevent the route engine from starting.
    Addon:Debug("validate", "begin running=" .. tostring(Addon.running)
        .. " profile=" .. tostring(Addon.profile ~= nil)
        .. " routeCount=" .. tostring(routeCount())
        .. " currentStep=" .. tostring(Addon.profile and Addon.profile.currentStep)
        .. " autoLoop=" .. tostring(Addon.profile and Addon.profile.autoLoop)
        .. " requireBoard=" .. tostring(requireBoard))

    if Addon.running then
        Addon:Debug("validate", "REJECT already running")
        Addon:SetStatus("The route is already running. Use the mini window to stop it.", true)
        if UI and UI.ShowMini then
            UI:ShowMini()
        end
        return false
    end
    if not Addon.profile then
        Addon:Debug("validate", "REJECT profile unavailable")
        Addon:SetStatus("Cannot start Route Runner: profile is unavailable.", true)
        return false
    end
    if routeCount() == 0 then
        Addon:Debug("validate", "REJECT active route contains 0 quests")
        Addon:SetStatus("Cannot start Route Runner: active route contains 0 quests.", true)
        return false
    end
    if Addon.profile.currentStep > routeCount() then
        Addon:Debug("validate", "REJECT route complete")
        Addon:SetStatus("Route complete. Reset it to run again.", true)
        return false
    end
    -- 1.0.14: route repeat/history checks are advisory at startup.
    -- The known-good board roller must be allowed to enter the running state;
    -- processBoard() can enforce per-step repeat rules later. Wrap both checks
    -- so an Ebonhold/Lua compatibility error cannot silently kill StartRoute().
    local repeatOK, validRepeatSpacing, repeatKey = pcall(Core.ValidateRouteRepeatSpacing, Addon.profile.route, Addon.profile.autoLoop)
    Addon:Debug("validate", "repeatSpacing pcall=" .. tostring(repeatOK) .. " valid=" .. tostring(validRepeatSpacing) .. " repeatKey=" .. tostring(repeatKey))
    if repeatOK and not validRepeatSpacing then
        Addon:Debug("validate", "WARN invalid loop spacing; allowing startup")
    elseif not repeatOK then
        Addon:Debug("validate", "WARN repeat-spacing check errored; allowing startup error=" .. tostring(validRepeatSpacing))
    end

    local lockOK, repeatLocked, lockedKey = pcall(currentQuestIsRepeatLocked)
    Addon:Debug("validate", "repeatLock pcall=" .. tostring(lockOK) .. " locked=" .. tostring(repeatLocked) .. " lockedKey=" .. tostring(lockedKey) .. " (advisory)")
    if not lockOK then
        Addon:Debug("validate", "WARN repeat-lock check errored; allowing startup error=" .. tostring(repeatLocked))
    end
    if requireBoard and not PE.IsBoardVisible() then
        Addon:Debug("validate", "REJECT board required but not visible")
        Addon:SetStatus("Open the Callboard window before starting the route.", true)
        return false
    end
    Addon:Debug("validate", "PASS")
    return true
end

function Addon:GetCurrentRouteQuest()
    return questForKey(currentKey())
end

function Addon:AddRouteQuest(key)
    if not self.profile or not questForKey(key) then
        return false
    end
    if Core.RouteContains(self.profile.route, key) then
        self:SetStatus("That quest is already in the route.")
        return false
    end
    table.insert(self.profile.route, key)
    if self.profile.currentStep > table.getn(self.profile.route) then
        self.profile.currentStep = table.getn(self.profile.route)
    end
    self:SetStatus("Added: " .. questLabel(key))
    UI:Refresh()
    return true
end

function Addon:RemoveRouteStep(index)
    local count = routeCount()
    if not self.profile or not index or index < 1 or index > count then
        return
    end

    self:PauseRoute(nil)
    table.remove(self.profile.route, index)
    if index < self.profile.currentStep then
        self.profile.currentStep = self.profile.currentStep - 1
    end
    self.profile.currentStep = math.max(1, math.min(self.profile.currentStep, routeCount() + 1))
    resetRuntime()
    self:SetStatus("Route step removed.")
    UI:Refresh()
end

function Addon:MoveRouteStep(fromIndex, toIndex)
    local count = routeCount()
    if not self.profile or not fromIndex or not toIndex or fromIndex < 1 or fromIndex > count or toIndex < 1 or toIndex > count or fromIndex == toIndex then
        return
    end

    self:PauseRoute(nil)
    local key = table.remove(self.profile.route, fromIndex)
    table.insert(self.profile.route, toIndex, key)

    local current = self.profile.currentStep
    if current == fromIndex then
        current = toIndex
    elseif fromIndex < current and current <= toIndex then
        current = current - 1
    elseif toIndex <= current and current < fromIndex then
        current = current + 1
    end
    self.profile.currentStep = current
    resetRuntime()
    self:SetStatus("Route reordered.")
    UI:Refresh()
end

function Addon:SetCurrentStep(index)
    if not self.profile or not index or index < 1 or index > routeCount() then
        return
    end
    self:PauseRoute(nil)
    resetRuntime()
    self.profile.currentStep = index
    self:SetStatus("Current step set to " .. tostring(index) .. ": " .. questLabel(currentKey()))
    UI:Refresh()
end

function Addon:SyncGroupStep(index, sourceName)
    if not self.profile or routeCount() == 0 then
        return false
    end
    index = tonumber(index)
    if not index or index < 1 or index > routeCount() then
        return false
    end
    local current = tonumber(self.profile.currentStep) or 1
    if index <= current then
        return false
    end

    local wasRunning = self.running == true
    self.profile.currentStep = index
    self.pendingReroll = nil
    self.pendingAccept = nil
    self.waitingKey = nil
    self.waitingSeenInLog = false
    self.waitingSeenActiveObjective = false
    self.waitingWasComplete = false
    self.waitingMissingAt = nil
    self.waitingMissingKey = nil
    self.rerollCount = 0
    self.nextActionAt = now()
    self.routeObservedSignature = nil

    local key = currentKey()
    if Group and Group.SetTrackedQuest then
        Group:SetTrackedQuest(key)
    end

    local source = sourceName and (" from " .. tostring(sourceName)) or ""
    self:Debug("group", "synced route step " .. tostring(current) .. " -> " .. tostring(index) .. source)
    if wasRunning then
        self.running = true
        self:SetStatus("Group synced to step " .. tostring(index) .. ": " .. questLabel(key) .. ".", true)
    else
        self:SetStatus("Group synced to step " .. tostring(index) .. ": " .. questLabel(key) .. ".", true)
    end
    if UI and UI.Refresh then
        UI:Refresh()
    end
    return true
end

function Addon:ClearRoute()
    self:PauseRoute(nil)
    self.profile.route = {}
    self.profile.currentStep = 1
    self.profile.activeRouteName = nil
    resetRuntime()
    self:SetStatus("Route cleared.")
    UI:Refresh()
end

function Addon:ResetRoute()
    self:PauseRoute(nil)
    self.profile.currentStep = 1
    resetRuntime()
    self:SetStatus("Route reset to step 1.")
    UI:Refresh()
end

-- Route quality tools: preflight, lightweight recording, and portable route codes.
function Addon:PreflightRoute(route)
    route = route or (self.profile and self.profile.route) or {}
    local report = { total = table.getn(route), locked = 0, unverified = 0, missing = 0 }
    for i = 1, table.getn(route) do
        local key = route[i]
        local quest = self.db and self.db.knownQuests and self.db.knownQuests[key] or nil
        if not quest then
            report.missing = report.missing + 1
        else
            if not quest.liveSeen and not quest.verified and not (tonumber(quest.seen) and tonumber(quest.seen) > 0) then
                report.unverified = report.unverified + 1
            end
            if Core.IsQuestRepeatLocked(self.profile and self.profile.recentCompletedQuests, key) then
                report.locked = report.locked + 1
            end
        end
    end
    return report
end

function Addon:PrintRoutePreflight()
    local r = self:PreflightRoute()
    Print("Route preflight: " .. tostring(r.total) .. " quest(s), " .. tostring(r.locked) .. " refresh-locked, "
        .. tostring(r.unverified) .. " unverified, " .. tostring(r.missing) .. " missing from catalogue.")
    return r
end

local function routeCodeEscape(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A")
end
local function routeCodeUnescape(value)
    return tostring(value or ""):gsub("%%0A", "\n"):gsub("%%7[Cc]", "|"):gsub("%%25", "%%")
end

function Addon:ExportRouteCode(name, route, autoLoop)
    name = cleanRouteName(name or (self.profile and self.profile.activeRouteName) or "Zen Route")
    route = route or (self.profile and self.profile.route) or {}
    local parts = { "ZENROUTE1", routeCodeEscape(name), autoLoop and "1" or ((self.profile and self.profile.autoLoop) and "1" or "0") }
    for i = 1, table.getn(route) do table.insert(parts, routeCodeEscape(route[i])) end
    return table.concat(parts, "|")
end

function Addon:ImportRouteCode(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local parts = {}
    for token in string.gmatch(text .. "|", "(.-)|") do table.insert(parts, token) end
    if parts[1] ~= "ZENROUTE1" then return false, "Not a ZENROUTE1 route code" end
    local name = cleanRouteName(routeCodeUnescape(parts[2]))
    if name == "" then name = "Imported Route" end
    local route = {}
    for i = 4, table.getn(parts) do
        local key = routeCodeUnescape(parts[i])
        if key ~= "" and self.db and self.db.knownQuests and self.db.knownQuests[key] then table.insert(route, key) end
    end
    if table.getn(route) == 0 then return false, "Route code contained no quests known to this catalogue" end
    self.profile.savedRoutes = self.profile.savedRoutes or {}
    local base, candidate, n = name, name, 2
    while self.profile.savedRoutes[candidate] do candidate = base .. " (" .. tostring(n) .. ")"; n = n + 1 end
    self.profile.savedRoutes[candidate] = { route = Core.CopyRoute(route), autoLoop = parts[3] == "1" }
    self:SetStatus("Imported route code as: " .. candidate .. ".", true)
    if UI and UI.RefreshRouteManager then UI:RefreshRouteManager() end
    return true, candidate
end

function Addon:ToggleRouteRecording()
    self.routeRecording = not self.routeRecording
    if self.routeRecording then
        self.routeRecordingDraft = {}
        self:SetStatus("Route recording started. Accept Callboard quests normally; Zen will record them in order.", true)
    else
        local count = table.getn(self.routeRecordingDraft or {})
        if count > 0 then
            self.profile.route = Core.CopyRoute(self.routeRecordingDraft)
            self.profile.currentStep = 1
            self.profile.activeRouteName = nil
            self:SetStatus("Route recording stopped: " .. tostring(count) .. " quest(s) loaded into the active route. Save it when ready.", true)
            if UI and UI.Refresh then UI:Refresh() end
        else
            self:SetStatus("Route recording stopped; no Callboard quests were recorded.", true)
        end
    end
end

function Addon:RecordAcceptedRouteQuest(key)
    if not self.routeRecording or not key then return end
    self.routeRecordingDraft = self.routeRecordingDraft or {}
    if self.routeRecordingDraft[table.getn(self.routeRecordingDraft)] ~= key then
        table.insert(self.routeRecordingDraft, key)
        self:SetStatus("Recorded route quest " .. tostring(table.getn(self.routeRecordingDraft)) .. ": " .. questLabel(key) .. ".", true)
    end
end

function Addon:SaveCurrentRoute(name)
    name = cleanRouteName(name)
    if name == "" then
        self:SetStatus("Enter a name before saving the route.", true)
        return false
    end
    if routeCount() == 0 then
        self:SetStatus("Add quests before saving a route.", true)
        return false
    end

    self.profile.savedRoutes = self.profile.savedRoutes or {}
    self.profile.savedRoutes[name] = {
        route = Core.CopyRoute(self.profile.route),
        autoLoop = self.profile.autoLoop == true,
    }
    self.profile.activeRouteName = name
    self:SetStatus("Saved route: " .. name .. ".", true)
    if UI and UI.RefreshRouteManager then
        UI:RefreshRouteManager()
    end
    UI:Refresh()
    return true
end

function Addon:ShareCurrentRoute(target, name)
    if not self.profile or not Group or not Group.QueueRouteShare then
        self:SetStatus("Route sharing is unavailable.", true)
        return false
    end
    name = cleanRouteName(name)
    if name == "" then
        name = self.profile.activeRouteName or "Shared Route"
    end
    local ok, reason = Group:QueueRouteShare(
        target,
        name,
        Core.CopyRoute(self.profile.route),
        self.profile.autoLoop == true
    )
    if not ok then
        self:SetStatus(reason or "Could not share the route.", true)
        return false
    end
    self:SetStatus("Sending route " .. name .. " privately to " .. tostring(target) .. "...", true)
    return true
end

function Addon:ShareSavedRoute(name, target)
    name = cleanRouteName(name)
    local saved = self.profile and self.profile.savedRoutes and self.profile.savedRoutes[name]
    if not saved then
        self:SetStatus("Saved route not found: " .. name .. ".", true)
        return false
    end
    if not Group or not Group.QueueRouteShare then
        self:SetStatus("Route sharing is unavailable.", true)
        return false
    end
    local ok, reason = Group:QueueRouteShare(
        target,
        name,
        Core.CopyRoute(saved.route),
        saved.autoLoop == true
    )
    if not ok then
        self:SetStatus(reason or "Could not share the route.", true)
        return false
    end
    self:SetStatus("Sending saved route " .. name .. " privately to " .. tostring(target) .. "...", true)
    return true
end

function Addon:LoadSavedRoute(name)
    name = cleanRouteName(name)
    local saved = self.profile and self.profile.savedRoutes and self.profile.savedRoutes[name]
    if not saved then
        self:SetStatus("Saved route not found: " .. name .. ".", true)
        return false
    end

    self:PauseRoute(nil)
    resetRuntime()
    self.profile.route = Core.CopyRoute(saved.route)
    self.profile.currentStep = 1
    self.profile.autoLoop = saved.autoLoop == true
    self.profile.activeRouteName = name
    self:SetStatus("Loaded route: " .. name .. (self.profile.autoLoop and " (auto-loop on)." or "."), true)
    UI.selectedRouteIndex = nil
    UI.routeOffset = 0
    UI:Refresh()
    if UI and UI.RefreshSettings then
        UI:RefreshSettings()
    end
    return true
end

function Addon:DeleteSavedRoute(name)
    name = cleanRouteName(name)
    if not self.profile or not self.profile.savedRoutes or not self.profile.savedRoutes[name] then
        return false
    end
    self.profile.savedRoutes[name] = nil
    if self.profile.activeRouteName == name then
        self.profile.activeRouteName = nil
    end
    self:SetStatus("Deleted saved route: " .. name .. ".", true)
    if UI and UI.RefreshRouteManager then
        UI:RefreshRouteManager()
    end
    UI:Refresh()
    return true
end

function Addon:ApplySettings(autoLoop, autoAccept, maxRerolls, rerollDelay, miniQuestCount, autoShare, showGroupProgress, ignoreOrder, launcherShown, launcherLocked, launcherOpacity, autoOpenSummonedBoard, hideCallboardWhileRunning)
    if not self.profile then
        return
    end
    local requestedAutoLoop = autoLoop and true or false
    local validRepeatSpacing, repeatKey = Core.ValidateRouteRepeatSpacing(self.profile.route, requestedAutoLoop)
    self.profile.autoLoop = requestedAutoLoop and validRepeatSpacing
    self.profile.autoAccept = autoAccept and true or false
    self.profile.ignoreOrder = ignoreOrder and true or false
    self.profile.autoShare = autoShare and true or false
    self.profile.showGroupProgress = showGroupProgress and true or false
    self.profile.autoOpenSummonedBoard = autoOpenSummonedBoard and true or false
    self.profile.hideCallboardWhileRunning = hideCallboardWhileRunning and true or false
    self.profile.launcher = self.profile.launcher or {}
    self.profile.launcher.shown = launcherShown and true or false
    self.profile.launcher.locked = launcherLocked and true or false
    local opacityPercent = math.max(10, math.min(100, math.floor(tonumber(launcherOpacity) or ((self.profile.launcher.opacity or 0.65) * 100))))
    self.profile.launcher.opacity = opacityPercent / 100
    if UI and UI.RefreshLauncher then UI:RefreshLauncher() end
    if Group then
        if self.profile.showGroupProgress then
            if Group.ScheduleAutoResync then
                Group:ScheduleAutoResync(0.2)
            end
        elseif Group.DisableSync then
            Group:DisableSync()
        end
    end
    self.profile.maxRerolls = math.max(1, math.min(100, math.floor(tonumber(maxRerolls) or self.profile.maxRerolls)))
    self.profile.rerollDelay = math.max(0.5, math.min(10, tonumber(rerollDelay) or self.profile.rerollDelay))
    self.profile.miniQuestCount = math.max(1, math.min(20, math.floor(tonumber(miniQuestCount) or self.profile.miniQuestCount or 5)))
    if requestedAutoLoop and not validRepeatSpacing then
        self:SetStatus("Settings saved, but auto-loop was left off. " .. repeatRuleMessage(repeatKey), true)
    else
        self:SetStatus("Settings saved" .. (self.profile.autoLoop and "; route will loop." or "."), true)
    end
    if UI and UI.RefreshSettings then
        UI:RefreshSettings()
    end
    UI:Refresh()
end

function Addon:PauseRoute(message)
    syncRerollGoldTracking()
    setRunnerState("PAUSED")
    self.running = false
    self.paused = true

    -- Freeze every automation wake-up path while preserving the current route,
    -- current step and waiting quest so Start can resume from the same place.
    self.pendingReroll = nil
    self.pendingBoardOpen = nil
    self.nextActionAt = nil
    self.nextRunningBoardInteractAt = nil
    self.nextObjectiveRequestAt = nil
    self.closeBoardAt = nil

    if message then
        self:SetStatus(message, true)
    end
    self:Debug("pause", "automation frozen; waitingKey=" .. tostring(self.waitingKey)
        .. " currentStep=" .. tostring(self.profile and self.profile.currentStep))
    if UI and UI.Refresh then
        UI:Refresh()
    end
end

function Addon:StartRoute()
    if not self.routeSessionArmed then
        self.running = false
        self.paused = false
        self.pendingBoardOpen = nil
        self.pendingReroll = nil
        self.nextActionAt = nil
        self:Debug("session", "StartRoute ignored because Route Runner is not armed")
        return false
    end

    -- 1.0.58: gold-safety gate. A route may only be ARMED while the actual
    -- Callboard/Objectives UI is visibly open at the instant Start Route is
    -- clicked. Do not use HasBoardAccess() here: that value intentionally has
    -- a grace period and can remain true after the board has closed.
    local wasPaused = self.paused == true
    self:ClearDebugLog()
    self.paused = false
    self:Debug("start", "StartRoute entered resumedFromPause=" .. tostring(wasPaused))

    local boardOpenNow = PE.IsBoardVisible and PE.IsBoardVisible() or false
    local boardAccessNow = PE.HasBoardAccess and PE.HasBoardAccess() or false
    self:Debug("safety", "start gate boardVisible=" .. tostring(boardOpenNow) .. " boardAccess=" .. tostring(boardAccessNow))
    -- Group state is advisory at startup. A party/raid must never be able to
    -- prevent the local Callboard runner from starting. Fresh addon peers still
    -- synchronize when possible; stale/missing/different-route peers simply fall
    -- back to solo behavior for this run.
    if Group and Group.IsSyncActive and Group:IsSyncActive() and Group.IsRouteReady then
        local ready, groupState = Group:IsRouteReady()
        if not ready then
            if groupState and groupState.stepMismatch and groupState.furthestStep then
                local currentStep = self.profile and (tonumber(self.profile.currentStep) or 1) or 1
                if groupState.furthestStep > currentStep then
                    self:Debug("group", "startup advisory: syncing local step " .. tostring(currentStep)
                        .. " -> " .. tostring(groupState.furthestStep) .. " and continuing")
                    self:SyncGroupStep(groupState.furthestStep, "group")
                else
                    self:Debug("group", "startup advisory: group step mismatch; continuing local route")
                end
                if Group.RefreshAndSync then
                    Group:RefreshAndSync()
                end
            elseif groupState and groupState.routeMismatch then
                self:Debug("group", "startup advisory: different route detected; continuing in solo mode")
            elseif groupState and groupState.unknown then
                self:Debug("group", "startup advisory: stale/incomplete group data; continuing in solo mode")
            else
                self:Debug("group", "startup advisory: group not ready; continuing in solo mode")
            end
            if UI and UI.RefreshGroupProgress then
                UI:RefreshGroupProgress()
            end
        end
    end

    if not boardOpenNow then
        -- Explicitly disarm everything so a later GOSSIP_SHOW cannot wake an
        -- earlier Start Route click and begin spending in the background.
        self.running = false
        self.diagnosticRoll = false
        self.pendingReroll = nil
        self.nextActionAt = nil
        self.waitingKey = nil
        self.pendingAccept = nil
        self:SetStatus("Open the Callboard first, then press Start Route. No rerolls were started.", true)
        self:Debug("safety", "BLOCKED: Callboard was not visibly open; route left disarmed")
        if UI and UI.Refresh then
            UI:Refresh()
        end
        return false
    end

    if not validateRouteStart(false) then
        return false
    end

    self.running = true
    self.diagnosticRoll = false
    self.rerollCount = 0
    self.sessionCost = 0
    self.goldBeforeReroll = nil
    setRunnerState("SEARCHING")
    self.pendingReroll = nil
    self.diagnosticLastSignature = nil
    self.nextActionAt = now()
    self.waitingKey = nil
    self.waitingIsContext = false
    self.waitingIgnoreOrder = false
    self.pendingAccept = nil

    local key = currentKey()
    self:Debug("start", "route runner started step=" .. tostring(self.profile.currentStep) .. " target=" .. tostring(key) .. " label=" .. tostring(questLabel(key)))
    self:Debug("state", "boardVisible=" .. tostring(PE.IsBoardVisible and PE.IsBoardVisible() or false) .. " boardAccess=" .. tostring(PE.HasBoardAccess and PE.HasBoardAccess() or false))
    self:SetStatus("Running step " .. tostring(self.profile.currentStep) .. ": " .. questLabel(key) .. ".", true)
    if UI and UI.ShowMini then
        UI:ShowMini()
    end
    UI:Refresh()
    return true
end

local function tryInteractWithCallboard()
    if PE.TryInteractWithCallboard then
        return PE.TryInteractWithCallboard()
    end
    return false
end

function Addon:BeginBoardOpenFlow(startRouteAfterOpen)
    if startRouteAfterOpen and not self.routeSessionArmed then
        self:Debug("session", "route-start board flow rejected because session is not armed")
        return false
    end
    if self.paused and not startRouteAfterOpen then
        self:Debug("pause", "ignored board-open automation while paused")
        return false
    end
    if startRouteAfterOpen and not validateRouteStart(false) then
        return false
    end

    if startRouteAfterOpen and UI and UI.ShowMini then
        UI:ShowMini()
    end

    if PE.IsBoardVisible() then
        if startRouteAfterOpen then
            return self:StartRoute()
        end
        self:SetStatus("Callboard is already open.")
        return true
    end

    local nearbyBoard = PE.IsCallboardNearby and PE.IsCallboardNearby(true) or false
    local canSummon = PE.IsSummonSpellKnown and PE.IsSummonSpellKnown() or true
    local summonCooldown = PE.GetSummonCooldownRemaining and PE.GetSummonCooldownRemaining() or 0
    self.pendingBoardOpen = {
        startRoute = startRouteAfterOpen == true,
        expiresAt = now() + 30,
        nextInteractAt = now() + 0.35,
        canSummon = canSummon,
        summonOnCooldown = summonCooldown > 0,
    }
    if nearbyBoard then
        self:SetStatus("Opening the nearby Callboard...", true)
    elseif summonCooldown > 0 then
        self:SetStatus("Callboard is on cooldown. Looking for the existing board...", true)
    elseif canSummon then
        self:SetStatus(startRouteAfterOpen
            and "Summoning and opening the Callboard..."
            or "Waiting for the Callboard to appear...", true)
    else
        self:SetStatus("Summon Callboard is not learned. Move close to a city Callboard and try again.", true)
    end
    tryInteractWithCallboard()
    return true
end

function Addon:BeginStartFlow()
    self:PrintRoutePreflight()
    -- Start always exits Pause first, even if route validation later fails.
    self.paused = false
    self.routeSessionArmed = true
    self:Debug("session", "Route Runner explicitly armed by Start")
    return self:BeginBoardOpenFlow(true)
end

function Addon:StopRouteAndReturn()
    syncRerollGoldTracking()
    setRunnerState("STOPPED")
    self.running = false
    self.paused = false
    self.routeSessionArmed = false
    self.instanceAutoActive = false
    self.pendingBoardOpen = nil
    self.pendingReroll = nil
    self.pendingAccept = nil
    self.waitingKey = nil
    self.waitingIsContext = false
    self.waitingIgnoreOrder = false
    self.nextActionAt = nil
    self.nextRunningBoardInteractAt = nil
    self.closeBoardAt = nil
    self:SetStatus("Route fully stopped and disarmed. Use Route Runner > Start to run again.", true)
    self:Debug("session", "Route Runner fully disarmed by STOP")

    -- STOP is a complete disarm and exit from the compact runner.
    -- Zen window; leave the addon UI closed so the player can return to play.
    if UI then
        if UI.miniFrame then
            UI.miniFrame:Hide()
        end
        if UI.groupProgressFrame then
            UI.groupProgressFrame:Hide()
        end
    end
end

function Addon:FinishIgnoreOrderQuest(reason)
    setRunnerState("SEARCHING")
    local key = self.waitingKey
    if key then
        recordCompletionEvent(key, "runner")
    end
    self.pendingReroll = nil
    self.pendingAccept = nil
    self.waitingKey = nil
    self.waitingIsContext = false
    self.waitingIgnoreOrder = false
    self.waitingSeenInLog = false
    self.waitingSeenActiveObjective = false
    self.waitingWasComplete = false
    self.waitingMissingAt = nil
    self.waitingMissingKey = nil
    self.rerollCount = 0
    self.nextActionAt = now()
    self.routeObservedSignature = nil
    self:Debug("ignore-order", "completed key=" .. tostring(key) .. " reason=" .. tostring(reason))
    self:SetStatus("Ignore Order: quest complete. Open the Callboard for the next matching route quest.", true)
    if UI and UI.Refresh then
        UI:Refresh()
    end
end

function Addon:FinishContextQuest(reason)
    setRunnerState(self.routeSessionArmed and "SEARCHING" or "IDLE")
    local key = self.waitingKey
    if key then
        self.contextHandledKey = key
        recordCompletionEvent(key, "runner")
    end
    self.pendingReroll = nil
    self.pendingAccept = nil
    self.waitingKey = nil
    self.waitingIsContext = false
    self.waitingSeenInLog = false
    self.waitingSeenActiveObjective = false
    self.waitingWasComplete = false
    self.waitingMissingAt = nil
    self.waitingMissingKey = nil
    self.rerollCount = 0
    self.nextActionAt = now()
    self.routeObservedSignature = nil

    local routeKey = currentKey()
    self:Debug("context", "instance priority quest completed reason=" .. tostring(reason)
        .. " routeArmed=" .. tostring(self.routeSessionArmed)
        .. " returning_to_route=" .. tostring(routeKey))
    if not self.routeSessionArmed then
        self.instanceAutoActive = false
        self.running = false
        self:SetStatus("Instance Callboard quest complete.", true)
    elseif routeKey then
        self:SetStatus("Instance Callboard quest complete. Returning to route step "
            .. tostring(self.profile.currentStep) .. ": " .. questLabel(routeKey) .. ".", true)
    else
        self:SetStatus("Instance Callboard quest complete. Route complete.", true)
    end
    if UI and UI.Refresh then
        UI:Refresh()
    end
end

local function completeWaitingQuest(reason)
    if Addon.waitingIsContext then
        Addon:FinishContextQuest(reason)
    elseif Addon.waitingIgnoreOrder then
        Addon:FinishIgnoreOrderQuest(reason)
    else
        Addon:AdvanceRoute(reason)
    end
end

function Addon:AdvanceRoute(reason)
    setRunnerState("SEARCHING")
    if not self.profile or routeCount() == 0 then
        return
    end

    local completedKey = currentKey()
    local completedTitle = questLabel(completedKey)
    if Group and Group.MarkTrackedComplete then
        Group:MarkTrackedComplete(completedKey)
    end
    recordCompletionEvent(completedKey, "route")
    self.profile.currentStep = self.profile.currentStep + 1
    self.pendingReroll = nil
    self.pendingAccept = nil
    self.waitingKey = nil
    self.waitingSeenInLog = false
    self.waitingSeenActiveObjective = false
    self.waitingWasComplete = false
    self.waitingMissingAt = nil
    self.waitingMissingKey = nil
    self.rerollCount = 0
    self.nextActionAt = now()

    if self.profile.currentStep > routeCount() and self.running and self.profile.autoLoop then
        self.profile.currentStep = 1
        self.rerollCount = 0
        self.nextActionAt = now()
        self:SetStatus("Finished " .. completedTitle .. ". Looping to step 1: " .. questLabel(currentKey()) .. ".", true)
    elseif self.profile.currentStep > routeCount() then
        self.running = false
        self:SetStatus("Route complete. Finished: " .. completedTitle .. ".", true)
    else
        self:SetStatus("Completed " .. completedTitle .. ". Next: " .. questLabel(currentKey()) .. ".", true)
        if self.running and not PE.IsBoardVisible() then
            self:SetStatus("Next step " .. tostring(self.profile.currentStep) .. ": " .. questLabel(currentKey()) .. ". Open the Callboard.")
        end
    end
    UI:Refresh()
end

function Addon:StopCatalogDiscovery(message)
    self.discoveryActive = false
    self.discoveryConfirmUntil = nil
    self.pendingReroll = nil
    if message then self:SetStatus(message, true) end
    if UI and UI.Refresh then UI:Refresh() end
end

local function importCatalogueTable(value, depth, visited)
    if type(value) ~= "table" or depth > 4 or visited[value] then return 0 end
    visited[value] = true
    local added = 0
    -- Try the table itself as a quest first.
    if Core.QuestKey(value) and Core.QuestTitle(value) ~= "" then
        if Core.LearnQuest(Addon.db, value) then added = added + 1 end
        return added
    end
    local scanned = 0
    for _, child in pairs(value) do
        if type(child) == "table" then
            added = added + importCatalogueTable(child, depth + 1, visited)
            scanned = scanned + 1
            if scanned >= 2000 then break end
        end
    end
    return added
end

function Addon:RefreshFreeCatalog(silent)
    if not self.db then return 0 end
    local before = table.getn(Core.BuildCatalog(self.db, ""))
    local seeded = self.SeedBuiltinCatalog and self:SeedBuiltinCatalog() or 0
    local harvested = 0
    local sources = PE.GetCatalogueCandidates and PE.GetCatalogueCandidates() or {}
    local visited = {}
    for i = 1, table.getn(sources) do
        harvested = harvested + importCatalogueTable(sources[i].value, 0, visited)
    end
    -- Reading visible offers is free; never reroll for catalogue population.
    if PE.IsBoardVisible and PE.IsBoardVisible() then learnCurrentObjectives() end
    local after = table.getn(Core.BuildCatalog(self.db, ""))
    self:Debug("catalog", "free refresh before=" .. tostring(before) .. " after=" .. tostring(after)
        .. " seeded=" .. tostring(seeded) .. " harvested=" .. tostring(harvested)
        .. " sources=" .. tostring(table.getn(sources)))
    if not silent then
        self:SetStatus("Catalogue refreshed for free: " .. tostring(after) .. " known quest(s), "
            .. tostring(math.max(0, after - before)) .. " newly added. No rerolls used.", true)
    end
    if UI and UI.Refresh then UI:Refresh() end
    return after - before
end

function Addon:BeginCatalogDiscovery()
    return self:RefreshFreeCatalog(false)
end

local function processCatalogDiscovery()
    -- Kept as a compatibility no-op. Catalogue discovery never spends gold.
    Addon.discoveryActive = false
end

local function beginWaitingForQuest(key, isContext, isIgnoreOrder)
    finalizeSearchSpend()
    setRunnerState("SELECTED")
    local quest = questForKey(key)
    if Group and Group.SetTrackedQuest then
        Group:SetTrackedQuest(key)
    end
    Addon.waitingKey = key
    Addon.waitingIsContext = isContext == true
    Addon.waitingIgnoreOrder = isIgnoreOrder == true
    Addon.waitingSeenInLog = false
    Addon.waitingSeenActiveObjective = false
    Addon.waitingWasComplete = false
    Addon.pendingAccept = {
        key = key,
        questID = quest and Core.QuestID(quest),
        title = quest and Core.QuestTitle(quest) or "",
        selectedAt = now(),
        seenInLog = false,
        seenActiveObjective = false,
        expiresAt = now() + 12,
    }
    Addon.closeBoardAt = now() + 1
    if Addon.waitingIsContext then
        Addon:SetStatus("Selected instance priority: " .. questLabel(key) .. ". Waiting for acceptance.", true)
        Addon:Debug("context", "selected instance priority key=" .. tostring(key))
    elseif Addon.waitingIgnoreOrder then
        Addon:SetStatus("Ignore Order: selected " .. questLabel(key) .. ". Waiting for acceptance.", true)
        Addon:Debug("ignore-order", "selected first visible route quest key=" .. tostring(key))
    else
        Addon:SetStatus("Selected step " .. tostring(Addon.profile.currentStep) .. ": " .. questLabel(key) .. ". Waiting for acceptance.", true)
    end
end

local function processDiagnosticRoll()
    local okLearn, learnedCount, objectives = pcall(learnCurrentObjectives)
    if not okLearn then
        Addon:Debug("error", "learnCurrentObjectives failed: " .. tostring(learnedCount))
        Addon.running = false
        Addon.diagnosticRoll = false
        Addon:SetStatus("TEST ROLLER ERROR: objective read failed. Use /zencb debug.", true)
        return
    end

    objectives = objectives or {}
    if table.getn(objectives) == 0 then
        if not Addon.diagnosticLoggedNoObjectives then
            Addon.diagnosticLoggedNoObjectives = true
            Addon:Debug("objectives", "no objective data available")
        end
        if not Addon.nextObjectiveRequestAt or now() >= Addon.nextObjectiveRequestAt then
            Addon.nextObjectiveRequestAt = now() + 0.5
            local okReq, result = pcall(PE.RequestObjectives)
            Addon:Debug("objectives", "RequestObjectives pcall=" .. tostring(okReq) .. " result=" .. tostring(result))
        end
        Addon:SetStatus("TEST ROLLER: board detected; waiting for objective data.")
        return
    end
    Addon.diagnosticLoggedNoObjectives = false

    local signature = Core.ObjectiveSignature(objectives)
    if signature ~= Addon.diagnosticObservedSignature then
        Addon.diagnosticObservedSignature = signature
        Addon:Debug("objectives", "count=" .. tostring(table.getn(objectives)) .. " signature=" .. tostring(signature))
        for i = 1, table.getn(objectives) do
            local q = objectives[i]
            Addon:Debug("objective" .. tostring(i), "id=" .. tostring(Core.QuestID(q)) .. " title=" .. tostring(Core.QuestTitle(q)))
        end
    end

    if Addon.pendingReroll then
        local okConfirm, confirmed = pcall(PE.ConfirmReroll)
        if confirmed or not okConfirm then
            Addon:Debug("confirm", "pending confirmation pcall=" .. tostring(okConfirm) .. " clicked=" .. tostring(confirmed))
        end
        if signature == Addon.pendingReroll.signature and now() < Addon.pendingReroll.expiresAt then
            Addon:SetStatus("TEST ROLLER: reroll " .. tostring(Addon.rerollCount) .. "/15 requested; waiting for offers to change.")
            return
        end

        if signature ~= Addon.pendingReroll.signature then
            Addon:Debug("reroll", "signature changed " .. tostring(Addon.pendingReroll.signature) .. " -> " .. tostring(signature))
            Addon:SetStatus("TEST ROLLER: board changed after reroll " .. tostring(Addon.rerollCount) .. "/15.")
        else
            Addon:Debug("timeout", "signature unchanged after timeout: " .. tostring(signature))
            Addon:SetStatus("TEST ROLLER: response timeout; retrying after reroll " .. tostring(Addon.rerollCount) .. "/15.")
        end
        Addon.pendingReroll = nil
        Addon.nextActionAt = now() + 0.20
        return
    end

    if Addon.nextActionAt and now() < Addon.nextActionAt then
        return
    end

    if Addon.rerollCount >= 15 then
        Addon.running = false
        Addon.diagnosticRoll = false
        Addon:Debug("complete", "15 rerolls requested successfully")
        Addon:SetStatus("TEST ROLLER COMPLETE: 15 rerolls were requested successfully.", true)
        return
    end

    local service = PE.GetService and PE.GetService() or nil
    Addon:Debug("service", "service=" .. tostring(service) .. " RequestRerollObjectives=" .. tostring(service and service.RequestRerollObjectives) .. " CanAffordReroll=" .. tostring(service and service.CanAffordReroll))
    Addon:Debug("state", "before request visible=" .. tostring(PE.IsBoardVisible and PE.IsBoardVisible() or false) .. " access=" .. tostring(PE.HasBoardAccess and PE.HasBoardAccess() or false) .. " afford=" .. tostring(PE.CanAffordReroll and PE.CanAffordReroll() or "unknown"))

    Addon.diagnosticLastSignature = signature
    local callOk, ok, reason = pcall(PE.RequestReroll)
    Addon:Debug("reroll", "PE.RequestReroll pcall=" .. tostring(callOk) .. " ok=" .. tostring(ok) .. " reason=" .. tostring(reason))
    if not callOk then
        Addon.running = false
        Addon.diagnosticRoll = false
        Addon:SetStatus("TEST ROLLER LUA ERROR requesting reroll. Use /zencb debug.", true)
        return
    end
    if not ok then
        Addon.running = false
        Addon.diagnosticRoll = false
        Addon:SetStatus("TEST ROLLER FAILED before reroll " .. tostring(Addon.rerollCount + 1) .. ": " .. tostring(reason or "request unavailable") .. ". Use /zencb debug.", true)
        return
    end

    Addon.rerollCount = Addon.rerollCount + 1
    Addon.pendingReroll = {
        signature = signature,
        expiresAt = now() + (Addon.profile and Addon.profile.rerollDelay or 1.6),
    }
    Addon.nextActionAt = Addon.pendingReroll.expiresAt
    Addon:Debug("reroll", "request accepted locally for reroll " .. tostring(Addon.rerollCount) .. "; waiting for board change")
    Addon:SetStatus("TEST ROLLER: reroll " .. tostring(Addon.rerollCount) .. "/15 requested; waiting for offers to change.", true)
end

local function processBoard()
    -- Gold-safety runtime gate: never request another reroll after the actual
    -- Callboard/Objectives window has been closed. Do not rely on cached board
    -- access here because that intentionally lingers for a short grace period.
    local visibleForRoll = PE.IsBoardVisible and PE.IsBoardVisible() or false
    local hiddenBoardMode = Addon.profile and Addon.profile.hideCallboardWhileRunning == true
    -- Hidden mode keeps the genuine Objectives frame technically shown at alpha
    -- zero. Do NOT fall back to HasBoardAccess() here: its grace cache can outlive
    -- the summoned GameObject and would allow paid rerolls after despawn.
    local accessibleForRoll = visibleForRoll
    if not visibleForRoll and not accessibleForRoll then
        -- Normal mode remains strict: never spend with the real board UI closed.
        -- Hidden mode is allowed only while Ebonhold still reports live objective
        -- access from the recently opened nearby board.
        Addon:Debug("safety", "Callboard not visible; reroll blocked without stopping route")
        Addon.pendingReroll = nil
        Addon.nextActionAt = nil
        Addon:SetStatus("Route active — open the Callboard when the next roll is needed.")
        return
    end

    local key, isContext
    local instanceZoneID, instanceZoneName
    if not Addon.routeSessionArmed then
        instanceZoneID, instanceZoneName = currentInstanceContext()
        isContext = instanceZoneID ~= nil
        if not instanceZoneID then
            Addon.instanceAutoActive = false
            Addon.running = false
            Addon:SetStatus("No recognized dungeon/raid Callboard context is active here.")
            return
        end
        -- Do not require this instance quest to already exist in the learned
        -- catalogue. The live Ebonhold objective payload carries zoneOrSort,
        -- so instance-only mode can discover the matching quest while rolling.
        key = contextPriorityKey()
    else
        key, isContext = priorityKey()
        if not key then
            Addon.running = false
            Addon:SetStatus("Route complete.", true)
            return
        end
    end

    if isContext then
        local lockedKey, remaining = instanceRepeatLockState(instanceZoneID)
        if lockedKey then
            Addon.pendingReroll = nil
            Addon.nextActionAt = nil
            Addon.rerollCount = 0
            local noun = remaining == 1 and "Callboard quest completion" or "Callboard quest completions"
            local message = "Instance quest refresh-locked: " .. questLabel(lockedKey)
                .. ". Complete " .. tostring(remaining) .. " more " .. noun
                .. " before it can appear again. No rerolls used."
            if Addon.lastRepeatLockWarningKey ~= lockedKey then
                Addon:Debug("repeat", "BLOCK instance reroll target=" .. tostring(lockedKey)
                    .. " remaining=" .. tostring(remaining) .. " zoneID=" .. tostring(instanceZoneID))
                Addon.lastRepeatLockWarningKey = lockedKey
            end
            Addon:SetStatus(message, true)
            return
        end
    end

    if Addon.profile.ignoreOrder == true and not isContext then
        -- Ignore Order deliberately ignores route-step repeat/cooldown state.
        -- The live Callboard is authoritative: if any quest from the route is
        -- visibly offered, select it immediately. Do not calculate or display a
        -- cooldown warning for the nominal current route step.
        Addon.lastRepeatLockWarningKey = nil
    elseif key and Core.IsQuestRepeatLocked(Addon.profile.recentCompletedQuests, key) then
        -- Ordered route mode keeps the historical warning advisory; instance
        -- priority above retains its hard no-gold safety block.
        if Addon.lastRepeatLockWarningKey ~= key then
            Addon.lastRepeatLockWarningKey = key
            Addon:Debug("repeat", "warning only: target=" .. tostring(key) .. " is present in recentCompletedQuests; continuing route search")
        end
    else
        Addon.lastRepeatLockWarningKey = nil
    end

    local _, objectives = learnCurrentObjectives()
    if table.getn(objectives) == 0 then
        Addon:Debug(isContext and "context" or "route",
            "step=" .. tostring(Addon.profile.currentStep) .. " target=" .. tostring(key) .. " objective_count=0")
        if not Addon.nextObjectiveRequestAt or now() >= Addon.nextObjectiveRequestAt then
            Addon.nextObjectiveRequestAt = now() + 1
            PE.RequestObjectives()
        end
        Addon:SetStatus("Callboard is open; waiting for quest offers.")
        return
    end

    local signature = Core.ObjectiveSignature(objectives)
    if signature ~= Addon.routeObservedSignature then
        Addon.routeObservedSignature = signature
        Addon:Debug("board", (isContext and "instance priority" or ("route step=" .. tostring(Addon.profile.currentStep)))
            .. " target=" .. tostring(key) .. " signature=" .. tostring(signature))
        for i = 1, table.getn(objectives) do
            local q = objectives[i]
            Addon:Debug("offer" .. tostring(i), "id=" .. tostring(Core.QuestID(q)) .. " title=" .. tostring(Core.QuestTitle(q)))
        end
    end
    if Addon.pendingReroll then
        -- The confirmation popup can appear a frame after the reroll request.
        -- Keep checking only while this specific request is pending.
        PE.ConfirmReroll()
        if signature == Addon.pendingReroll.signature then
            if now() < Addon.pendingReroll.expiresAt then
                return
            end
            Addon:Debug("reroll", "route response timeout with unchanged signature=" .. tostring(signature))
        else
            -- The offers have already refreshed. Discard the old response
            -- timeout so the new list is searched on the next fast update.
            Addon:Debug("reroll", "route board changed " .. tostring(Addon.pendingReroll.signature) .. " -> " .. tostring(signature))
            Addon.nextActionAt = now() + 0.10
        end
        syncRerollGoldTracking()
        Addon.pendingReroll = nil
    end

    local index
    local selectedKey = key
    local ignoreOrderMatch = false

    if isContext and not Addon.routeSessionArmed then
        index, selectedKey = findInstanceObjective(objectives, instanceZoneID)
        if index and selectedKey then
            key = selectedKey
            Addon:Debug("context", "live instance offer matched zoneID=" .. tostring(instanceZoneID)
                .. " key=" .. tostring(selectedKey) .. " offer=" .. tostring(index))
        end
    elseif not isContext and Addon.profile.ignoreOrder == true then
        index, selectedKey = firstOfferedRouteQuest(objectives)
        ignoreOrderMatch = index ~= nil
        if index then
            Addon:Debug("ignore-order", "first visible route match key=" .. tostring(selectedKey)
                .. " offer=" .. tostring(index))
        end
    else
        local exactIndex = Core.FindObjective(objectives, key)
        if exactIndex and not objectiveIsCompleted(objectives[exactIndex]) then
            index = exactIndex
        elseif exactIndex then
            Addon:Debug("match", "skipping completed offer target=" .. tostring(key) .. " offer=" .. tostring(exactIndex))
        end
    end

    if index then
        Addon:Debug("match", "found target=" .. tostring(selectedKey) .. " at offer=" .. tostring(index))
        if Addon.profile.autoAccept ~= true then
            finalizeSearchSpend()
            setRunnerState("FOUND")
            Addon.pendingReroll = nil
            Addon.nextActionAt = nil
            Addon:SetStatus("Found " .. questLabel(selectedKey) .. ". Auto-accept is OFF; select/accept it manually.", true)
            return
        end
        Addon:Debug("match", "auto-accept ON; selecting offer=" .. tostring(index))
        if hiddenBoardMode and PE.RestoreBoardVisualsInvisible then
            -- Restore the genuine board to its normal coordinates for Ebonhold's
            -- selection handshake, but keep the top-level presentation transparent
            -- so the player does not see the Callboard flash onto the screen.
            Addon.hideBoardVisualsUntil = nil
            PE.RestoreBoardVisualsInvisible()
            Addon:Debug("select", "restored hidden Callboard invisibly for objective selection")
        end
        if PE.SelectObjective(index) then
            Addon:Debug("select", "SelectObjective succeeded for target=" .. tostring(selectedKey))
            beginWaitingForQuest(selectedKey, isContext, ignoreOrderMatch)
        else
            Addon:Debug("select", "SelectObjective FAILED for target=" .. tostring(selectedKey) .. " offer=" .. tostring(index))
            Addon:SetStatus("Found " .. questLabel(selectedKey) .. " but could not select it.", true)
            Addon.nextActionAt = now() + 0.75
        end
        return
    end

    if Addon.nextActionAt and now() < Addon.nextActionAt then
        return
    end
    if Addon.rerollCount >= Addon.profile.maxRerolls then
        local missingLabel = (isContext and not key) and ((instanceZoneName or "current instance") .. " Callboard quest") or questLabel(key)
        finalizeSearchSpend()
        setRunnerState("SAFETY_STOP")
        Addon:PauseRoute("Safety stop: reached the " .. tostring(Addon.profile.maxRerolls) .. " reroll cap without finding " .. missingLabel .. ".")
        return
    end

    local rerollTarget = key or (isContext and ("zone:" .. tostring(instanceZoneID))) or "unknown"
    Addon:Debug("reroll", "requesting route reroll " .. tostring(Addon.rerollCount + 1) .. "/" .. tostring(Addon.profile.maxRerolls) .. " target=" .. tostring(rerollTarget) .. " signature=" .. tostring(signature))
    beginRerollGoldTracking()
    local callOk, ok, reason = pcall(PE.RequestReroll)
    Addon:Debug("reroll", "PE.RequestReroll pcall=" .. tostring(callOk) .. " ok=" .. tostring(ok) .. " reason=" .. tostring(reason))
    if not callOk then
        Addon.goldBeforeReroll = nil
        Addon:PauseRoute("Lua error while requesting a Callboard reroll. Use /zencb debug.")
        return
    end
    if not ok then
        Addon.goldBeforeReroll = nil
        if reason == "no_gold" then
            Addon:PauseRoute("Not enough gold to continue rerolling.")
        elseif reason == "board_closed" then
            Addon:PauseRoute("The Callboard window closed. Reopen it before restarting the route.")
        else
            Addon:PauseRoute("Could not reroll. Check that the Callboard is open.")
        end
        return
    end

    Addon.rerollCount = Addon.rerollCount + 1
    setRunnerState("REROLLING")
    Addon.pendingReroll = {
        signature = signature,
        expiresAt = now() + Addon.profile.rerollDelay,
    }
    Addon:Debug("reroll", "route reroll accepted count=" .. tostring(Addon.rerollCount) .. "; waiting for board change")
    Addon.nextActionAt = Addon.pendingReroll.expiresAt
    local cost = coinText(Addon.sessionCost)
    Addon:SetStatus("Reroll " .. tostring(Addon.rerollCount) .. "/" .. tostring(Addon.profile.maxRerolls)
        .. " for " .. (isContext and "[Instance] " or (Addon.profile.ignoreOrder and "[Any Route Quest]" or ""))
        .. (Addon.profile.ignoreOrder and not isContext and "" or ((isContext and not key) and ((instanceZoneName or "current instance") .. " quest") or questLabel(key)))
        .. (cost and " | Spent: " .. cost or ""))
end

local function updateWaitingState()
    if not Addon.waitingKey then
        return false
    end

    local waitingKey = Addon.waitingKey
    local activeObjective = PE.GetActiveObjective()
    local activeMatches = activeObjective and Core.QuestKey(activeObjective) == waitingKey
    if activeMatches then
        Addon.waitingSeenActiveObjective = true
        if Addon.pendingAccept then Addon.pendingAccept.seenActiveObjective = true end
    end

    local _, entry = findQuestInLog(waitingKey)
    if entry then
        Addon.waitingSeenInLog = true
        if Addon.pendingAccept then Addon.pendingAccept.seenInLog = true end
        if entry.isComplete == true or tonumber(entry.isComplete) == 1 then
            Addon.waitingWasComplete = true
            recordCompletionEvent(waitingKey, "quest log complete")
            completeWaitingQuest("Quest log marked complete")
            return false
        end
    end

    if questIsFlaggedCompleted(waitingKey) then
        Addon.waitingWasComplete = true
        recordCompletionEvent(waitingKey, "completion flag")
        completeWaitingQuest("Quest completion flag detected")
        return false
    end

    -- Once an accepted Callboard quest has genuinely been observed in the quest
    -- log or as Ebonhold's active objective, its disappearance is a completion
    -- signal even if the physical/summoned Callboard is still present.
    --
    -- Older logic refused to advance while the Board was visible. On Ebonhold
    -- that meant a fast-completed quest could remain stuck as the active route
    -- step until combat ended or the Callboard despawned, preventing reuse of
    -- the same summoned board for the next step.
    local disappeared = (Addon.waitingSeenActiveObjective and not activeMatches)
        or (Addon.waitingSeenInLog and not entry)
    if disappeared then
        if now() < (Addon.deathProtectionUntil or 0) then
            Addon.waitingMissingAt = nil
            Addon.waitingMissingKey = nil
            return true
        end
        if Addon.waitingMissingKey ~= waitingKey then
            Addon.waitingMissingKey = waitingKey
            Addon.waitingMissingAt = now()
            Addon:Debug("waiting", "accepted Callboard quest disappeared; confirming completion key="
                .. tostring(waitingKey) .. " boardVisible="
                .. tostring(PE.IsBoardVisible and PE.IsBoardVisible() or false))
            return true
        end
        -- Keep a short settle window for private-server quest-log/objective
        -- updates, but do not tie it to combat state or Board visibility.
        if now() - (Addon.waitingMissingAt or now()) >= 0.75 then
            Addon.waitingWasComplete = true
            recordCompletionEvent(waitingKey, "confirmed accepted-quest disappearance")
            completeWaitingQuest("Callboard quest completion confirmed while board remains available")
            return false
        end
        return true
    else
        Addon.waitingMissingAt = nil
        Addon.waitingMissingKey = nil
    end

    if entry or activeMatches then
        Addon:SetStatus(Addon.waitingIsContext
            and ("Active instance priority: " .. questLabel(waitingKey) .. ".")
            or ("Active step " .. tostring(Addon.profile.currentStep) .. ": " .. questLabel(waitingKey) .. "."))
        return true
    end

    if Addon.pendingAccept and now() > Addon.pendingAccept.expiresAt then
        if activeObjectiveMatches(Addon.waitingKey) then
            Addon.pendingAccept = nil
            Addon:SetStatus(Addon.waitingIsContext
                and ("Active instance priority: " .. questLabel(Addon.waitingKey) .. ".")
                or ("Active step " .. tostring(Addon.profile.currentStep) .. ": " .. questLabel(Addon.waitingKey) .. "."))
            return true
        end

        -- Some Ebonhold Callboard objectives (notably certain Winterspring
        -- objectives) do not reliably surface through QUEST_ACCEPTED/the normal
        -- quest log immediately. If the board has closed after a successful
        -- SelectObjective(), keep tracking the selected route step instead of
        -- discarding it and accidentally returning to the roller.
        if (Addon.profile and Addon.profile.hideCallboardWhileRunning)
            or not (PE.IsBoardVisible and PE.IsBoardVisible()) then
            Addon.pendingAccept = nil
            Addon:Debug("accept", "normal acceptance signal timed out with board closed; preserving waitingKey=" .. tostring(Addon.waitingKey))
            Addon:SetStatus(Addon.waitingIsContext
                and ("Selected instance priority: " .. questLabel(Addon.waitingKey) .. ". Waiting for completion.")
                or ("Selected step " .. tostring(Addon.profile.currentStep) .. ": " .. questLabel(Addon.waitingKey) .. ". Waiting for completion."), true)
            return true
        end

        Addon.pendingAccept = nil
        Addon.waitingKey = nil
        Addon.waitingSeenActiveObjective = false
        Addon:SetStatus("Quest acceptance was not confirmed; retrying current route step.", true)
        Addon.nextActionAt = now()
        return false
    end
    return true
end

local function handleObservedBoardOpen(source)
    if not PE.IsBoardVisible or not PE.IsBoardVisible() then
        return false
    end
    if PE.MarkBoardAccess then PE.MarkBoardAccess(30) end
    if Addon.pendingBoardOpen then
        local pending = Addon.pendingBoardOpen
        Addon.pendingBoardOpen = nil
        Addon:Debug("board", "board visibility detected via " .. tostring(source))
        if pending.startRoute and Addon.routeSessionArmed then
            Addon:StartRoute()
            return true
        end
    end
    PE.RequestObjectives()
    Addon.nextObjectiveRequestAt = now() + 0.75
    Addon.passiveLearnUntil = now() + 2.5
    learnCurrentObjectives()
    if Addon.profile and Addon.profile.hideCallboardWhileRunning and PE.HideBoardVisuals and not Addon.pendingAccept then
        PE.MarkBoardAccess(30)
        PE.HideBoardVisuals()
        Addon.hideBoardVisualsUntil = now() + 1.5
        Addon:Debug("board", "Callboard parked off-screen; continuing through the normal live board session")
    end
    if Addon.routeSessionArmed then
        if Addon.running then Addon.nextActionAt = now() + 0.10 end
    elseif not Addon.discoveryActive then
        local contextZoneID, contextZone = currentInstanceContext()
        if contextZoneID then
            Addon.instanceAutoActive = true
            Addon.running = true
            Addon.rerollCount = 0
            Addon.sessionCost = 0
            setRunnerState("INSTANCE_SEARCH")
            Addon.nextActionAt = now() + 0.10
            Addon:SetStatus("Instance priority: looking for the " .. tostring(contextZone or "current instance") .. " Callboard quest.", true)
        end
    end
    return true
end

local function processPendingBoardOpen()
    local pending = Addon.pendingBoardOpen
    if not pending then
        return
    end

    if PE.IsBoardVisible() then
        handleObservedBoardOpen("pending auto-open")
        Addon:SetStatus("Callboard opened.")
        return
    end

    if now() > pending.expiresAt then
        Addon.pendingBoardOpen = nil
        if pending.summonOnCooldown then
            Addon:SetStatus("The existing Callboard could not be reached. Move closer to it and press Start Route again; the cooldown will not be recast.", true)
        elseif not pending.canSummon then
            Addon:SetStatus("No nearby city Callboard was found, and Summon Callboard is not learned. Move closer to a city board and try again.", true)
        else
            Addon:SetStatus(pending.startRoute
                and "Could not open the Callboard automatically. Interact with it, then press Start Route again."
                or "Could not find an interactable Callboard. Move closer and try again.", true)
        end
        return
    end

    if now() >= pending.nextInteractAt then
        pending.nextInteractAt = now() + 0.75
        local interacted = tryInteractWithCallboard()
        if interacted and not pending.openNoticeShown then
            pending.openNoticeShown = true
            Addon:SetStatus("Opening the summoned Objectives Board...", true)
        end
    end
end

local function summonSpellMatches(spellName, arg3, arg4, arg5)
    local spellID = tonumber(arg5) or tonumber(arg4) or tonumber(arg3)
    return spellID == PE.SUMMON_SPELL_ID or spellName == PE.SUMMON_SPELL_NAME
end

local function beginDetectedSummon()
    if Addon.paused then
        -- A deliberate Summon Callboard keypress is also an explicit request to
        -- resume/start automation.
        Addon.paused = false
        Addon:Debug("pause", "detected Callboard summon cleared Pause")
    end

    local hasRoute = routeCount() > 0
    local instanceZoneID, instanceZoneName = currentInstanceContext()
    local instanceOnlySummon = instanceZoneID ~= nil and not Addon.routeSessionArmed

    -- Inside a recognized dungeon/raid, summoning the Callboard is an instance-
    -- priority action unless the player had already explicitly armed Route Runner.
    -- Do not silently start the normal route just because the player is fetching
    -- the local raid quest.
    if not instanceOnlySummon then
        if not Addon.routeSessionArmed and hasRoute then
            Addon.routeSessionArmed = true
            Addon:Debug("session", "Summon Callboard hotkey armed Route Runner automatically")
        end
        if hasRoute and not Addon.running then
            Addon.running = true
            Addon.instanceAutoActive = false
            setRunnerState("RUNNING")
            Addon.nextActionAt = now()
            Addon:Debug("session", "Summon Callboard hotkey started Route Runner immediately")
            Addon:SetStatus("Route started from Summon Callboard hotkey; opening the board...", true)
        end
    else
        Addon.instanceAutoActive = true
        Addon.running = true
        setRunnerState("INSTANCE_SEARCH")
        Addon.nextActionAt = now()
        Addon:Debug("session", "Callboard summoned inside recognized instance; normal Route Runner left disarmed")
        Addon:SetStatus("Instance priority: looking for the " .. tostring(instanceZoneName or "current instance") .. " Callboard quest.", true)
    end

    -- Track the lifetime of this summoned-board session. The spell cooldown is
    -- the best client-visible lifetime signal Ebonhold exposes for the GameObject.
    Addon.hiddenSummonedBoardSession = true
    Addon.hiddenSummonSawCooldown = false

    if Addon.profile and Addon.profile.autoOpenSummonedBoard then
        Addon:BeginBoardOpenFlow((not instanceOnlySummon) and Addon.routeSessionArmed and hasRoute)
        Addon:Debug("summon", "auto-open requested for summoned Callboard")
    end

    if not Addon.routeSessionArmed then
        Addon:Debug("session", "Callboard summoned with no runnable route; instance priority remains available")
        return
    end
    if not hasRoute then
        return
    end

    if Addon.pendingBoardOpen then
        Addon.pendingBoardOpen.startRoute = true
        Addon.pendingBoardOpen.expiresAt = now() + 12
        Addon.pendingBoardOpen.nextInteractAt = now()
        return
    end

    if Addon.running then
        Addon:BeginBoardOpenFlow(false)
        Addon.nextActionAt = now()
        Addon.routeObservedSignature = nil
        Addon:SetStatus("Callboard summon detected. Continuing the active route...", true)
        return
    end

    if Addon:BeginBoardOpenFlow(true) then
        Addon:SetStatus("Callboard summoned. Route started automatically; opening the board...", true)
    end
end

local function handleSummonSpellSucceeded(unit, spellName, arg3, arg4, arg5)
    if unit ~= "player" or not summonSpellMatches(spellName, arg3, arg4, arg5) then
        return
    end
    beginDetectedSummon()
end

local function processSummonCooldownTransition()
    if not PE.GetSummonCooldownRemaining then
        return
    end
    local remaining = PE.GetSummonCooldownRemaining()
    local previous = Addon.lastSummonCooldownRemaining
    Addon.lastSummonCooldownRemaining = remaining
    if Addon.hiddenSummonedBoardSession then
        if remaining > 1 then
            Addon.hiddenSummonSawCooldown = true
        elseif Addon.hiddenSummonSawCooldown and remaining <= 0 then
            Addon.hiddenSummonedBoardSession = false
            Addon.hiddenSummonSawCooldown = false
            Addon.pendingReroll = nil
            Addon.nextActionAt = nil
            if PE.ClearBoardAccess then PE.ClearBoardAccess() end
            if Addon.profile and Addon.profile.hideCallboardWhileRunning then
                Addon:SetStatus("Summoned Callboard expired. Rerolling stopped; summon it again to continue.", true)
                Addon:Debug("safety", "summon cooldown ended; hidden-board reroll permission revoked")
            end
        end
    end
    if previous ~= nil and previous <= 0 and remaining > 1 then
        beginDetectedSummon()
    end
end

local nextHudUpdateAt = 0

local function tick()
    if not Addon.initialized then
        return
    end
    updateRaidQuestReminder(false)

    -- Button labels and spell cooldown text are cosmetic; refresh them at 2 Hz
    -- instead of on every route-engine tick.
    if now() >= nextHudUpdateAt then
        nextHudUpdateAt = now() + 0.5
        if UI and UI.UpdateSummonCooldown then
            UI:UpdateSummonCooldown()
        end
        if UI and UI.UpdateStartAction then
            UI:UpdateStartAction()
        end
    end
    if Addon.paused and not Addon.discoveryActive then
        return
    end

    if Addon.profile and not Addon.profile.hideCallboardWhileRunning
        and PE.RestoreBoardVisuals then
        PE.RestoreBoardVisuals()
    end

    -- Ebonhold's custom Callboard does not reliably emit GOSSIP_SHOW when
    -- opened manually. Detect the actual Objectives frame becoming visible.
    -- The live invisible Callboard can still cause Ebonhold/Blizzard to populate
    -- GameTooltip from its Reroll control. Suppress only Callboard-related tooltip
    -- content while hidden mode is active.
    if Addon.profile and Addon.profile.hideCallboardWhileRunning and GameTooltip and GameTooltip:IsShown() then
        local callboardTooltip = false
        for i = 1, 12 do
            local line = _G["GameTooltipTextLeft" .. tostring(i)]
            local txt = line and line.GetText and string.lower(tostring(line:GetText() or "")) or ""
            if string.find(txt, "reroll selection", 1, true)
                or string.find(txt, "objectives board", 1, true)
                or (i <= 3 and string.find(txt, "cost:", 1, true)) then
                callboardTooltip = true
                break
            end
        end
        if callboardTooltip then
            GameTooltip:Hide()
        end
    end

    if Addon.hideBoardVisualsUntil and now() <= Addon.hideBoardVisualsUntil
        and Addon.profile and Addon.profile.hideCallboardWhileRunning and PE.HideBoardVisuals then
        PE.HideBoardVisuals()
    elseif Addon.hideBoardVisualsUntil and now() > Addon.hideBoardVisualsUntil then
        Addon.hideBoardVisualsUntil = nil
    end

    local boardVisibleNow = PE.IsBoardVisible and PE.IsBoardVisible() or false
    if boardVisibleNow and not Addon.lastObservedBoardVisible then
        handleObservedBoardOpen("visibility poll")
    end
    Addon.lastObservedBoardVisible = boardVisibleNow

    local passiveLearning = Addon.passiveLearnUntil and now() <= Addon.passiveLearnUntil

    -- Ebonhold's custom Objectives window can become visible a fraction after
    -- GOSSIP_SHOW fires. Do not make instance-priority automation depend on
    -- winning that timing race: while the normal route is disarmed, a visible
    -- Callboard inside a recognized dungeon/raid may arm instance-only mode.
    -- This deliberately cannot fall back to the normal route.
    if not Addon.routeSessionArmed and not Addon.instanceAutoActive and not Addon.discoveryActive then
        local boardVisible = PE.IsBoardVisible and PE.IsBoardVisible() or false
        if boardVisible then
            local contextZoneID, contextZone = currentInstanceContext()
            if contextZoneID then
                Addon.instanceAutoActive = true
                Addon.running = true
                Addon.rerollCount = 0
                Addon.sessionCost = 0
                Addon.goldBeforeReroll = nil
                setRunnerState("INSTANCE_SEARCH")
                Addon.pendingReroll = nil
                Addon.nextActionAt = now() + 0.10
                Addon.passiveLearnUntil = nil
                passiveLearning = false
                Addon:Debug("context", "instance-only mode recovered from visible Callboard zone="
                    .. tostring(contextZone) .. " zoneID=" .. tostring(contextZoneID))
                Addon:SetStatus("Instance priority: looking for the " .. tostring(contextZone or "current instance") .. " Callboard quest.", true)
            end
        end
    end

    -- Pending Callboard interaction must run even when the normal route is
    -- disarmed. Auto-open-after-summon deliberately creates this pending flow,
    -- and returning before processing it left Zen stuck on
    -- "Waiting for the Callboard to appear...".
    if Addon.pendingBoardOpen then
        processPendingBoardOpen()
    end

    if not Addon.routeSessionArmed and not Addon.instanceAutoActive and not Addon.discoveryActive and not passiveLearning and not Addon.pendingBoardOpen then
        return
    end

    if Addon.discoveryActive then
        processCatalogDiscovery()
        return
    end

    if passiveLearning and not Addon.routeSessionArmed and not Addon.instanceAutoActive then
        if PE.IsBoardVisible and PE.IsBoardVisible() then
            learnCurrentObjectives()
            if not Addon.nextObjectiveRequestAt or now() >= Addon.nextObjectiveRequestAt then
                Addon.nextObjectiveRequestAt = now() + 0.75
                PE.RequestObjectives()
            end
        end
        return
    end

    processSummonCooldownTransition()
    if Group and Group.Tick then
        Group:Tick()
    end

    if Addon.pendingBoardOpen then
        processPendingBoardOpen()
    end

    if not Addon.running and not Addon.pendingBoardOpen then
        return
    end

    local boardVisible = PE.IsBoardVisible()
    -- The route roller only needs the real Objectives window. HasBoardAccess()
    -- can call GetObjectives() and was duplicating service work every hot tick.
    local boardAccessible = boardVisible
    -- Never promote cached HasBoardAccess() into reroll permission in hidden mode.
    -- The cache is useful for diagnostics, but not for spending gold.
    if boardVisible and not Addon.lastBoardVisible then
        PE.RequestObjectives()
        Addon.nextObjectiveRequestAt = now() + 1
    end
    Addon.lastBoardVisible = boardVisible

    if Addon.closeBoardAt and now() >= Addon.closeBoardAt then
        Addon.closeBoardAt = nil
        PE.CloseBoard()
    end

    if boardVisible then
        learnCurrentObjectives()
    end

    if Addon.diagnosticRoll then
        if Addon.diagnosticLastBoardAccessible ~= boardAccessible then
            Addon.diagnosticLastBoardAccessible = boardAccessible
            Addon:Debug("board", "visible=" .. tostring(boardVisible) .. " accessible=" .. tostring(boardAccessible))
        end
        if not boardAccessible then
            Addon:SetStatus("TEST ROLLER: open the Callboard to begin raw rerolls.")
            return
        end
        local okDiag, diagErr = pcall(processDiagnosticRoll)
        if not okDiag then
            Addon:Debug("fatal", "processDiagnosticRoll error: " .. tostring(diagErr))
            Addon.running = false
            Addon.diagnosticRoll = false
            Addon:SetStatus("TEST ROLLER LUA ERROR. Type /zencb debug and copy the report.", true)
        end
        return
    end

    if Addon.waitingKey and updateWaitingState() then
        return
    end

    local key, isContext
    if not Addon.routeSessionArmed then
        local instanceZoneID = currentInstanceContext()
        isContext = instanceZoneID ~= nil
        if not instanceZoneID then
            Addon.instanceAutoActive = false
            Addon.running = false
            return
        end
        key = contextPriorityKey() -- may be nil until the matching live offer is discovered
    else
        key, isContext = priorityKey()
        if not key then
            Addon.running = false
            Addon:SetStatus("Route complete.", true)
            return
        end
    end

    -- In instance-only mode the current target may not be learned yet, so a
    -- previously active *non-instance* Callboard quest must not block the live
    -- board search.  This was the 1.0.64 stall: key=nil while discovering the
    -- raid quest made any existing active objective look like a conflict, so
    -- processBoard() was never reached and no reroll was requested.
    local _, entry
    local activeObjective = PE.GetActiveObjective()
    local activeKey = activeObjective and Core.QuestKey(activeObjective) or nil

    if isContext and not Addon.routeSessionArmed then
        local instanceZoneID = currentInstanceContext()
        local activeZoneID = tonumber(activeObjective and (activeObjective.zoneOrSort or activeObjective.zoneId or activeObjective.zoneID))
        if activeObjective and instanceZoneID and activeZoneID == tonumber(instanceZoneID) then
            local instanceKey = activeKey
            if instanceKey then
                _, entry = findQuestInLog(instanceKey)
                Addon.waitingKey = instanceKey
                Addon.waitingIsContext = true
                Addon.waitingSeenInLog = entry ~= nil
                Addon.waitingSeenActiveObjective = true
                Addon.waitingMissingAt = nil
                Addon.waitingMissingKey = nil
                Addon.waitingWasComplete = entry and (entry.isComplete == true or tonumber(entry.isComplete) == 1) or false
                updateWaitingState()
                return
            end
        end
        -- Any active objective from another zone is deliberately ignored here.
        -- Instance priority owns the visible Callboard and is allowed to reroll
        -- until a live offer matches the dungeon/raid zone.
    else
        if Addon.profile.ignoreOrder ~= true then
            _, entry = findQuestInLog(key)
        end
        if entry or activeKey == key then
            Addon.waitingKey = key
            Addon.waitingIsContext = isContext == true
            Addon.waitingSeenInLog = entry ~= nil
            Addon.waitingSeenActiveObjective = activeKey == key
            Addon.waitingMissingAt = nil
            Addon.waitingMissingKey = nil
            Addon.waitingWasComplete = entry and (entry.isComplete == true or tonumber(entry.isComplete) == 1) or false
            updateWaitingState()
            return
        end

        if activeObjective and activeKey and activeKey ~= key then
            if Addon.profile.ignoreOrder == true and not isContext and routeContainsKey(activeKey) then
                Addon.waitingKey = activeKey
                Addon.waitingIgnoreOrder = true
                Addon.waitingIsContext = false
                Addon.waitingSeenActiveObjective = true
                Addon.waitingSeenInLog = findQuestInLog(activeKey) ~= nil
                updateWaitingState()
                return
            end
            Addon:SetStatus("Waiting for the previous active Callboard quest to clear: " .. Core.QuestTitle(activeObjective) .. ".")
            return
        end
    end

    if not boardAccessible then
        Addon:SetStatus(isContext
            and ("Instance priority: " .. questLabel(key) .. ". Open or summon the Callboard.")
            or (Addon.profile.ignoreOrder
                and "Ignore Order: open or summon the Callboard to find any quest from the route."
                or ("Running step " .. tostring(Addon.profile.currentStep) .. ": " .. questLabel(key) .. ". Open or summon the Callboard.")))
        if not Addon.nextRunningBoardInteractAt or now() >= Addon.nextRunningBoardInteractAt then
            Addon.nextRunningBoardInteractAt = now() + 0.4
            if PE.IsCallboardNearby and PE.IsCallboardNearby() then
                tryInteractWithCallboard()
            end
        end
        return
    end
    Addon.nextRunningBoardInteractAt = nil
    processBoard()
end

local function handleQuestDetail()
    local pending = Addon.pendingAccept
    if not pending or now() > pending.expiresAt or not Addon.profile.autoAccept then
        return
    end

    local questID, title = detailQuestIdentity()
    if not questMatchesKey(questID, title, pending.key) then
        return
    end

    if AcceptQuest then
        AcceptQuest()
        Addon:SetStatus("Accepted route quest: " .. questLabel(pending.key) .. ".")
    end
end

local function acceptedQuestID(arg1, arg2)
    local first = tonumber(arg1)
    local second = tonumber(arg2)
    if second and second > 0 then
        return second
    end
    if first and first > 0 then
        local entry = getQuestLogEntry(first)
        if entry and entry.questID then
            return entry.questID
        end
        return first
    end
    return nil
end

local function releaseHiddenBoardAfterQuestAccepted()
    if not (Addon.profile and Addon.profile.hideCallboardWhileRunning) then return end

    -- Hidden mode parks the genuine Callboard off-screen while searching. Once a
    -- quest has been accepted we no longer need to hold that interaction open.
    -- Restore its real position first, then close only the UI interaction. The
    -- summoned world Callboard remains in place, so the player can right-click it
    -- again after completing the quest and Zen will observe a fresh board-open.
    Addon.hideBoardVisualsUntil = nil
    if PE.RestoreBoardVisuals then PE.RestoreBoardVisuals() end
    if PE.CloseBoard then PE.CloseBoard() end
    if PE.ClearBoardAccess then PE.ClearBoardAccess() end
    Addon.lastBoardVisible = false
    Addon.pendingReroll = nil
    Addon.nextObjectiveRequestAt = nil
    Addon.routeObservedSignature = nil
    Addon:Debug("board", "hidden search released Callboard UI after quest acceptance; physical board remains reusable")
end

local function handleQuestAccepted(arg1, arg2)
    local questID = acceptedQuestID(arg1, arg2)
    local acceptedKnownKey = knownKeyForQuestID and knownKeyForQuestID(questID) or nil
    if acceptedKnownKey then Addon:RecordAcceptedRouteQuest(acceptedKnownKey) end
    local key = Addon.waitingKey or currentKey()
    if not key then
        return
    end
    if Addon.waitingKey and acceptedKnownKey and acceptedKnownKey ~= Addon.waitingKey then
        Addon:Debug("waiting", "active Board quest replaced by accepted quest key=" .. tostring(acceptedKnownKey)
            .. " previous=" .. tostring(Addon.waitingKey))
        Addon.waitingKey = nil
        Addon.waitingIsContext = false
        Addon.waitingIgnoreOrder = false
        Addon.waitingSeenInLog = false
        Addon.waitingSeenActiveObjective = false
        Addon.waitingWasComplete = false
        Addon.waitingMissingAt = nil
        Addon.waitingMissingKey = nil
        Addon.pendingAccept = nil
        Addon:SetStatus("Callboard quest replaced by another accepted Board quest. No completion was recorded.", true)
        return
    end
    local questLogIndex, entry = findQuestInLog(key)
    local title = entry and entry.title or nil
    if questMatchesKey(questID, title, key) then
        Addon.waitingKey = key
        Addon.waitingSeenInLog = true
        Addon.waitingSeenActiveObjective = activeObjectiveMatches(key) and true or false
        Addon.pendingAccept = nil
        setRunnerState("WAITING")
        if Group and Group.QueueAutoShare then
            local quest = questForKey(key)
            Group:QueueAutoShare(
                key,
                questID or (entry and entry.questID) or (quest and Core.QuestID(quest)),
                title or (quest and Core.QuestTitle(quest)) or "",
                questLogIndex
            )
        end
        Addon:SetStatus(Addon.waitingIsContext
            and ("Active instance priority: " .. questLabel(key) .. ".")
            or ("Active step " .. tostring(Addon.profile.currentStep) .. ": " .. questLabel(key) .. "."), true)
        releaseHiddenBoardAfterQuestAccepted()
    end
end

knownKeyForQuestID = function(questID)
    questID = tonumber(questID)
    if not questID or not Addon.db or type(Addon.db.knownQuests) ~= "table" then
        return nil
    end
    for key, quest in pairs(Addon.db.knownQuests) do
        if tonumber(Core.QuestID(quest)) == questID then
            return key
        end
    end
    return nil
end

recordCompletionEvent = function(key, source)
    if not key or not Addon.profile then return false end
    local t = now()
    -- QUEST_COMPLETE, QUEST_TURNED_IN and the runner's own completion path can
    -- all describe the same single event. Keep duplicate callbacks from
    -- advancing Ebonhold's three-event cooldown more than once.
    if Addon.lastRecordedCompletionKey == key and (t - (Addon.lastRecordedCompletionAt or 0)) < 4 then
        Addon:Debug("repeat", "ignored duplicate completion key=" .. tostring(key) .. " source=" .. tostring(source))
        return false
    end
    Addon.profile.recentCompletedQuests = Core.RecordCompletedQuest(Addon.profile.recentCompletedQuests, key)
    Addon.lastRecordedCompletionKey = key
    Addon.lastRecordedCompletionAt = t
    Addon:Debug("repeat", "recorded completion event key=" .. tostring(key) .. " source=" .. tostring(source)
        .. " historyCount=" .. tostring(table.getn(Addon.profile.recentCompletedQuests)))
    return true
end

local function resetRefreshHistory(reason)
    if not Addon.profile then return end
    local previous = type(Addon.profile.recentCompletedQuests) == "table"
        and table.getn(Addon.profile.recentCompletedQuests) or 0
    Addon.profile.recentCompletedQuests = {}
    Addon.lastRecordedCompletionKey = nil
    Addon.lastRecordedCompletionAt = nil
    Addon.lastRepeatLockWarningKey = nil
    Addon:Debug("repeat", "refresh history reset reason=" .. tostring(reason) .. " previousCount=" .. tostring(previous))
    if UI and UI.Refresh then UI:Refresh() end
    if UI and UI.RefreshMini then UI:RefreshMini() end
end

local function handleQuestTurnedIn(questID)
    -- QUEST_TURNED_IN is authoritative even if Ebonhold leaves the Callboard
    -- summoned/open. Record the completion, then clear/advance the runner now;
    -- never wait for the Board or active-objective object to despawn.
    local observedKey = knownKeyForQuestID(questID)
    if observedKey then
        recordCompletionEvent(observedKey, "QUEST_TURNED_IN")
    end

    local waitingKey = Addon.waitingKey
    local key = waitingKey or currentKey()
    if key and questMatchesKey(questID, nil, key) then
        Addon.waitingWasComplete = true
        Addon.pendingAccept = nil
        Addon.waitingMissingAt = nil
        Addon.waitingMissingKey = nil
        completeWaitingQuest("QUEST_TURNED_IN while Callboard may remain open")
        -- If the Board is still visible, let the next route/instance decision
        -- run immediately instead of waiting for a new GOSSIP_SHOW/open cycle.
        if PE.IsBoardVisible and PE.IsBoardVisible() and (Addon.routeSessionArmed or Addon.instanceAutoActive) then
            Addon.nextActionAt = now()
            Addon.nextObjectiveRequestAt = nil
            Addon.routeObservedSignature = nil
        end
    elseif observedKey then
        -- A manually accepted/completed known Board quest still changes the
        -- server refresh window. Clear stale active/waiting observations if
        -- they refer to this same quest.
        if Addon.waitingKey == observedKey then
            Addon.waitingKey = nil
            Addon.waitingSeenInLog = false
            Addon.waitingSeenActiveObjective = false
            Addon.waitingMissingAt = nil
            Addon.waitingMissingKey = nil
        end
    end
end

local function handleQuestComplete()
    if not Addon.waitingKey then
        return
    end
    local questID, title = detailQuestIdentity()
    if questMatchesKey(questID, title, Addon.waitingKey) then
        Addon.waitingWasComplete = true
        completeWaitingQuest("QUEST_COMPLETE")
    end
end


function Addon:ExplainWhy()
    local lines = {}
    local function add(label, value)
        table.insert(lines, tostring(label) .. ": " .. tostring(value))
    end

    local boardOpen = PE.IsBoardVisible and PE.IsBoardVisible() or false
    local zoneID, zoneName = currentInstanceContext()
    local contextKey = zoneID and contextPriorityKey() or nil
    local routeKey = currentKey()
    local targetKey = nil
    local mode = "IDLE"

    if self.paused then
        mode = "PAUSED"
    elseif self.instanceAutoActive or (boardOpen and zoneID and not self.routeSessionArmed) then
        mode = "INSTANCE PRIORITY"
        targetKey = contextKey
    elseif self.routeSessionArmed then
        mode = self.running and "ROUTE" or "ROUTE ARMED"
        targetKey = routeKey
    end

    add("Mode", mode)
    add("Board", boardOpen and "OPEN" or "CLOSED")
    add("Runner state", self.runnerState or (self.running and "RUNNING" or "IDLE"))
    add("Paused", self.paused and "YES" or "NO")
    add("Route armed", self.routeSessionArmed and "YES" or "NO")
    add("Instance", zoneID and ((zoneName or "recognized") .. " [" .. tostring(zoneID) .. "]") or "none recognized")

    if targetKey then
        add("Target", questLabel(targetKey))
    elseif mode == "INSTANCE PRIORITY" then
        add("Target", "matching live offer for " .. tostring(zoneName or zoneID))
    elseif routeKey then
        add("Route target", questLabel(routeKey))
    else
        add("Target", "none")
    end

    if zoneID then
        local lockedKey, remaining = instanceRepeatLockState(zoneID)
        if lockedKey and remaining and remaining > 0 then
            add("Refresh", "LOCKED — " .. tostring(remaining) .. " completion" .. (remaining == 1 and "" or "s") .. " remaining (" .. questLabel(lockedKey) .. ")")
        else
            add("Refresh", "AVAILABLE / no known lock")
        end
    elseif targetKey and self.profile then
        local remaining = Core.RepeatLockRemaining(self.profile.recentCompletedQuests, targetKey)
        add("Refresh", remaining > 0 and ("LOCKED — " .. tostring(remaining) .. " remaining") or "AVAILABLE")
    else
        add("Refresh", "n/a")
    end

    local objectives = PE.GetObjectives and PE.GetObjectives() or {}
    add("Offers visible", type(objectives) == "table" and table.getn(objectives) or 0)
    add("Rerolls", tostring(self.rerollCount or 0) .. "/" .. tostring((self.profile and self.profile.maxRerolls) or 0))
    add("Current spend", Core.FormatMoney and Core.FormatMoney(self.sessionCost or 0) or tostring(self.sessionCost or 0))

    local nextAction
    if self.paused then
        nextAction = "none — automation is paused"
    elseif not boardOpen then
        nextAction = "open the Callboard; Zen will not spend gold while it is closed"
    elseif zoneID and not self.routeSessionArmed then
        local lockedKey = instanceRepeatLockState(zoneID)
        if lockedKey then
            nextAction = "none — instance quest is refresh-locked"
        elseif self.pendingReroll then
            nextAction = "waiting for reroll response"
        else
            nextAction = "inspect live offers; reroll if none match this instance"
        end
    elseif not self.routeSessionArmed then
        nextAction = "none — normal route is disarmed"
    elseif self.pendingReroll then
        nextAction = "waiting for reroll response"
    elseif self.waitingKey then
        nextAction = "waiting for quest completion: " .. questLabel(self.waitingKey)
    elseif self.running then
        nextAction = "inspect live offers for route target"
    else
        nextAction = "press Start to run the route"
    end
    add("Next action", nextAction)

    Print("ZenCallboard — Why")
    for i = 1, table.getn(lines) do Print(lines[i]) end
    self:Debug("why", table.concat(lines, " | "))
    return lines
end

local function showHelp()
    Print("/zencb - toggle route builder")
    Print("/zencb start | pause | next | reset | refreshreset | record | preflight | why | route export | route import CODE | group | share NAME | catalog | export | import | status | doctor | debug | help")
end

-- Zen Menu runtime registration.
-- Metadata remains the primary discovery path, but this guarantees integration
-- on clients where custom .toc metadata is not enumerated reliably.
local function RegisterWithZenMenu()
    local registration = {
        addon = "ZenCallboard",
        folder = "ZenCallboard",
        key = "ZenCallboard",
        title = "Zen Callboard",
        description = "Build and run synchronized Project Ebonhold Callboard quest routes.",
        icon = "Interface\\AddOns\\ZenCallboard\\Textures\\CallboardIcon",
        open = "ZenCallboard_Open",
        settings = "ZenCallboard_OpenSettings",
        launcherFrames = { "ZenCallboardFloatingLauncher" },
        category = "Utility",
        order = 100,
        integrationVersion = 1,
    }

    if ZenMenu and type(ZenMenu.RegisterAddon) == "function" then
        ZenMenu:RegisterAddon("ZenCallboard", registration)
        return true
    elseif RavioliMenu and type(RavioliMenu.RegisterAddon) == "function" then
        RavioliMenu:RegisterAddon("ZenCallboard", registration)
        return true
    end

    ZenMenuPendingRegistrations = ZenMenuPendingRegistrations or {}
    table.insert(ZenMenuPendingRegistrations, registration)
    RavioliMenuPendingRegistrations = RavioliMenuPendingRegistrations or {}
    table.insert(RavioliMenuPendingRegistrations, registration)
    return false
end

-- Zen Menu integration API.
-- These globals are intentionally small/stable entry points advertised in the .toc.
function ZenCallboard_Open()
    if UI and UI.Create then
        UI:Create()
    end
    if UI and UI.frame and UI.frame:IsShown() then
        UI:Refresh()
    elseif UI and UI.ShowMain then
        UI:ShowMain()
    elseif UI and UI.Toggle then
        UI:Toggle()
    end
end

function ZenCallboard_OpenSettings()
    if UI and UI.Create then
        UI:Create()
    end
    if UI and UI.ShowMain then
        UI:ShowMain()
    end
    if UI and UI.ToggleSettings then
        if not UI.settingsFrame or not UI.settingsFrame:IsShown() then
            UI:ToggleSettings()
        else
            UI:RefreshSettings()
            UI.settingsFrame:Raise()
        end
    end
end

-- Legacy integration aliases retained for users upgrading from RavioliCallboard.
RavioliCallboard_Open = ZenCallboard_Open
RavioliCallboard_OpenSettings = ZenCallboard_OpenSettings

local catalogTransferFrame
local catalogTransferEdit
local catalogTransferAction

function Addon:ShowCatalogTransfer(mode)
    mode = mode == "import" and "import" or "export"
    if not catalogTransferFrame then
        catalogTransferFrame = CreateFrame("Frame", "ZenCallboardCatalogTransferFrame", UIParent)
        catalogTransferFrame:SetWidth(720); catalogTransferFrame:SetHeight(470); catalogTransferFrame:SetPoint("CENTER")
        catalogTransferFrame:SetFrameStrata("TOOLTIP"); catalogTransferFrame:SetMovable(true); catalogTransferFrame:EnableMouse(true)
        catalogTransferFrame:RegisterForDrag("LeftButton")
        catalogTransferFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        catalogTransferFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local bg = catalogTransferFrame:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0.03,0.04,0.05,0.97)
        catalogTransferFrame.title = catalogTransferFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        catalogTransferFrame.title:SetPoint("TOPLEFT",14,-12)
        catalogTransferFrame.hint = catalogTransferFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        catalogTransferFrame.hint:SetPoint("TOPLEFT",14,-38); catalogTransferFrame.hint:SetWidth(650); catalogTransferFrame.hint:SetJustifyH("LEFT")
        local scroll=CreateFrame("ScrollFrame","ZenCallboardCatalogTransferScroll",catalogTransferFrame,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",14,-66); scroll:SetPoint("BOTTOMRIGHT",-32,52)
        catalogTransferEdit=CreateFrame("EditBox",nil,scroll); catalogTransferEdit:SetMultiLine(true); catalogTransferEdit:SetAutoFocus(false)
        catalogTransferEdit:SetFontObject("ChatFontNormal"); catalogTransferEdit:SetWidth(650); catalogTransferEdit:SetScript("OnEscapePressed",function() catalogTransferFrame:Hide() end)
        scroll:SetScrollChild(catalogTransferEdit)
        catalogTransferAction=CreateFrame("Button",nil,catalogTransferFrame,"UIPanelButtonTemplate")
        catalogTransferAction:SetWidth(110); catalogTransferAction:SetHeight(24); catalogTransferAction:SetPoint("BOTTOMRIGHT",-126,14)
        local close=CreateFrame("Button",nil,catalogTransferFrame,"UIPanelButtonTemplate"); close:SetWidth(100); close:SetHeight(24); close:SetPoint("BOTTOMRIGHT",-14,14); close:SetText("Close")
        close:SetScript("OnClick",function() catalogTransferFrame:Hide() end)
        catalogTransferAction:SetScript("OnClick",function()
            if catalogTransferFrame.mode == "import" then
                local added, merged, err = Core.ImportCatalogueText(Addon.db, catalogTransferEdit:GetText() or "")
                if err then Addon:SetStatus("Catalogue import failed: "..tostring(err)..".",true)
                else Addon:SetStatus("Catalogue import complete: "..tostring(added).." added, "..tostring(merged).." merged.",true); if UI and UI.Refresh then UI:Refresh() end; catalogTransferFrame:Hide() end
            else
                catalogTransferEdit:HighlightText(); catalogTransferEdit:SetFocus()
            end
        end)
    end
    catalogTransferFrame.mode=mode
    catalogTransferAction:SetScript("OnClick",function()
        if catalogTransferFrame.mode == "import" then
            local added, merged, err = Core.ImportCatalogueText(Addon.db, catalogTransferEdit:GetText() or "")
            if err then Addon:SetStatus("Catalogue import failed: "..tostring(err)..".",true)
            else Addon:SetStatus("Catalogue import complete: "..tostring(added).." added, "..tostring(merged).." merged.",true); if UI and UI.Refresh then UI:Refresh() end; catalogTransferFrame:Hide() end
        else
            catalogTransferEdit:HighlightText(); catalogTransferEdit:SetFocus()
        end
    end)
    if mode == "export" then
        catalogTransferFrame.title:SetText("ZenCallboard Catalogue Export")
        catalogTransferFrame.hint:SetText("Ctrl+A then Ctrl+C to copy. Imports merge with the local catalogue; they never replace newer live data.")
        catalogTransferEdit:SetText(Core.ExportCatalogue(self.db)); catalogTransferAction:SetText("Select All")
    else
        catalogTransferFrame.title:SetText("ZenCallboard Catalogue Import")
        catalogTransferFrame.hint:SetText("Paste a ZENCATALOG1 export below, then press Import. Existing entries are merged rather than deleted.")
        catalogTransferEdit:SetText(""); catalogTransferAction:SetText("Import")
    end
    catalogTransferEdit:SetCursorPosition(0); catalogTransferFrame:Show(); catalogTransferFrame:Raise()
end

function Addon:ShowRouteCodeTransfer(mode)
    mode = mode == "import" and "import" or "export"
    self:ShowCatalogTransfer("export") -- ensure the reusable transfer frame exists
    catalogTransferFrame.mode = "route_" .. mode
    if mode == "export" then
        catalogTransferFrame.title:SetText("ZenCallboard Route Code")
        catalogTransferFrame.hint:SetText("Copy this ZENROUTE1 code to share the active route without requiring the other player to be online.")
        catalogTransferEdit:SetText(self:ExportRouteCode())
        catalogTransferAction:SetText("Select All")
    else
        catalogTransferFrame.title:SetText("Import ZenCallboard Route Code")
        catalogTransferFrame.hint:SetText("Paste a ZENROUTE1 code below, then press Import. It will be added to Saved Routes.")
        catalogTransferEdit:SetText("")
        catalogTransferAction:SetText("Import")
    end
    catalogTransferAction:SetScript("OnClick", function()
        if catalogTransferFrame.mode == "route_import" then
            local ok, reason = Addon:ImportRouteCode(catalogTransferEdit:GetText() or "")
            if not ok then Addon:SetStatus("Route import failed: " .. tostring(reason) .. ".", true)
            else catalogTransferFrame:Hide() end
        else
            catalogTransferEdit:HighlightText(); catalogTransferEdit:SetFocus()
        end
    end)
    catalogTransferEdit:SetCursorPosition(0); catalogTransferFrame:Show(); catalogTransferFrame:Raise()
end

local function handleSlash(input)
    input = Core.NormalizeTitle(input)
    if input == "" or input == "show" or input == "toggle" then
        UI:Toggle()
    elseif input == "start" then
        Addon:BeginStartFlow()
    elseif input == "pause" or input == "stop" then
        Addon:PauseRoute("Paused by user.")
    elseif input == "next" or input == "advance" then
        Addon:AdvanceRoute("Slash command")
    elseif input == "reset" then
        Addon:ResetRoute()
    elseif input == "group" then
        if UI and UI.ToggleGroupProgress then
            UI:ToggleGroupProgress()
        end
    elseif string.sub(input, 1, 5) == "link " then
        local name = string.sub(input, 6)
        if Group and Group.SetLinkedMember and Group:SetLinkedMember(name, true) then
            Addon:SetStatus("Linked Callboard sync with " .. tostring(name) .. ".", true)
        else
            Addon:SetStatus("Could not link that group member.", true)
        end
    elseif string.sub(input, 1, 7) == "unlink " then
        local name = string.sub(input, 8)
        if Group and Group.SetLinkedMember and Group:SetLinkedMember(name, false) then
            Addon:SetStatus("Unlinked Callboard sync with " .. tostring(name) .. ".", true)
        else
            Addon:SetStatus("Could not unlink that group member.", true)
        end
    elseif string.sub(input, 1, 6) == "share " then
        Addon:ShareCurrentRoute(string.sub(input, 7))
    elseif input == "community publish" then
        local name = Addon.profile and Addon.profile.activeRouteName or "Community Route"
        local ok, detail = Group:PublishCommunityRoute(name,
            Addon.profile and Core.CopyRoute(Addon.profile.route) or {},
            Addon.profile and Addon.profile.autoLoop == true)
        Addon:SetStatus(ok and "Published route to EbonAPI community sharing."
            or ("Community publish failed: " .. tostring(detail)), true)
    elseif input == "community import" then
        local ok, detail = Group:ImportCommunityRoute()
        Addon:SetStatus(ok and ("Imported community route as " .. tostring(detail) .. ".")
            or ("Community import failed: " .. tostring(detail)), true)
    elseif input == "community status" then
        Addon:SetStatus(Group:InitEbonAPI() and "EbonAPI community sharing is available."
            or "EbonAPI is not installed or not ready.", true)
    elseif input == "accept" then
        if not Group or not Group.AcceptLatestIncomingRoute or not Group:AcceptLatestIncomingRoute() then
            Addon:SetStatus("No shared route is waiting for acceptance.", true)
        end
    elseif input == "decline" then
        if not Group or not Group.DeclineLatestIncomingRoute or not Group:DeclineLatestIncomingRoute() then
            Addon:SetStatus("No shared route is waiting for a response.", true)
        end
    elseif input == "discover" or input == "scan" or input == "catalog" or input == "refresh" then
        Addon:RefreshFreeCatalog(false)
    elseif input == "export" or input == "catalog export" then
        Addon:ShowCatalogTransfer("export")
    elseif input == "import" or input == "catalog import" then
        Addon:ShowCatalogTransfer("import")
    elseif input == "record" then
        Addon:ToggleRouteRecording()
    elseif input == "preflight" then
        Addon:PrintRoutePreflight()
    elseif input == "route export" then
        Addon:ShowRouteCodeTransfer("export")
    elseif string.sub(input, 1, 13) == "route import " then
        local ok, reason = Addon:ImportRouteCode(string.sub(input, 14))
        if not ok then Addon:SetStatus("Route import failed: " .. tostring(reason) .. ".", true) end
    elseif input == "route import" then
        Addon:ShowRouteCodeTransfer("import")
    elseif input == "status" then
        Print(Addon.statusMessage)
    elseif input == "why" then
        Addon:ExplainWhy()
    elseif input == "refreshreset" then
        resetRefreshHistory("manual /zencb refreshreset")
        Addon:SetStatus("Callboard refresh-lock history cleared.", true)
    elseif input == "doctor" or input == "compat" then
        local lines = PE.GetCompatibilityDiagnostics and PE.GetCompatibilityDiagnostics() or { "compatibility diagnostics unavailable" }
        Print("Ebonhold Callboard compatibility check:")
        for i = 1, table.getn(lines) do
            Print(lines[i])
            Addon:Debug("doctor", lines[i])
        end
    elseif input == "debug" or input == "log" then
        Addon:ShowDebugLog()
    elseif input == "debug clear" or input == "log clear" then
        Addon:ClearDebugLog()
        Addon:Debug("debug", "log cleared by slash command")
        Print("Debug log cleared.")
    elseif input == "help" then
        showHelp()
    else
        Print("Unknown command: " .. input)
        showHelp()
    end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Migrate routes/settings from the former RavioliCallboard name.
        if type(ZenCallboardDB) ~= "table" and type(RavioliCallboardDB) == "table" then
            ZenCallboardDB = RavioliCallboardDB
        end
        Addon.db = Core.MergeDatabase(ZenCallboardDB)
        if Addon.SeedBuiltinCatalog then Addon:SeedBuiltinCatalog() end
        ZenCallboardDB = Addon.db
        RavioliCallboardDB = ZenCallboardDB

        SLASH_ZENCALLBOARD1 = "/zencb"
        SLASH_ZENCALLBOARD2 = "/zencallboard"
        SlashCmdList.ZENCALLBOARD = handleSlash
        RegisterWithZenMenu()
    elseif event == "PLAYER_LOGIN" then
        initializeProfile()
        Addon:RefreshFreeCatalog(true)
        if Group and Group.IsEnabled and Group:IsEnabled() and Group.ScheduleAutoResync then
            Group:ScheduleAutoResync(1.0)
        end
        RegisterWithZenMenu()
        local uiReady, uiError = pcall(UI.Create, UI)
        if not uiReady then
            Addon.uiInitError = tostring(uiError or "Unknown UI error")
            if UI and UI.frame then
                UI.frame:Hide()
            end
            Print("UI failed to initialize: " .. Addon.uiInitError)
            return
        end
        Addon.uiInitError = nil
        Addon.initialized = true
        Addon:SetStatus("Ready. Build a route, press Start, then open the Callboard.")
        Print("Ready. Type /zencb to build your quest route.")
    elseif not Addon.initialized then
        return
    elseif event == "GOSSIP_CLOSED" then
        if PE.ClearBoardAccess then PE.ClearBoardAccess() end
        Addon.pendingReroll = nil
        Addon.nextActionAt = nil
        Addon.lastBoardVisible = false
        if Addon.profile and Addon.profile.hideCallboardWhileRunning and Addon.running then
            Addon:SetStatus("Callboard interaction ended. Rerolling stopped until the board is opened/summoned again.", true)
            Addon:Debug("safety", "GOSSIP_CLOSED revoked hidden-board reroll permission")
        end
    elseif event == "GOSSIP_SHOW" then
        Addon:Debug("event", "GOSSIP_SHOW visible=" .. tostring(PE.IsBoardVisible and PE.IsBoardVisible() or false) .. " access=" .. tostring(PE.HasBoardAccess and PE.HasBoardAccess() or false))
        if Addon.paused then
            Addon:Debug("pause", "GOSSIP_SHOW ignored while paused")
            return
        end
        if PE.IsBoardVisible() then
            handleObservedBoardOpen("GOSSIP_SHOW")

            if Addon.routeSessionArmed then
                if Addon.running then
                    Addon.nextActionAt = now() + 0.10
                end
            elseif Addon.discoveryActive then
                Addon:Debug("discover", "Callboard opened/refreshed during catalogue discovery")
            else
                -- Instance-priority quests are intentionally independent of the
                -- normal Route Runner session. Opening a Callboard inside a known
                -- dungeon/raid automatically searches only for that instance quest.
                local contextZoneID, contextZone = currentInstanceContext()
                if contextZoneID then
                    Addon.instanceAutoActive = true
                    Addon.running = true
                    Addon.rerollCount = 0
                    Addon.sessionCost = 0
                    Addon.goldBeforeReroll = nil
                    setRunnerState("INSTANCE_SEARCH")
                    Addon.pendingReroll = nil
                    Addon.nextActionAt = now() + 0.10
                    Addon:Debug("context", "auto instance search started while route session disarmed zone="
                        .. tostring(contextZone) .. " zoneID=" .. tostring(contextZoneID))
                    Addon:SetStatus("Instance priority: looking for the " .. tostring(contextZone or "current instance") .. " Callboard quest.", true)
                else
                    Addon.instanceAutoActive = false
                    Addon.running = false
                end
            end
        end
    elseif event == "QUEST_DETAIL" then
        if not Addon.paused then
            handleQuestDetail()
        end
    elseif event == "QUEST_ACCEPTED" then
        if not Addon.paused then
            handleQuestAccepted(arg1, arg2)
        end
    elseif event == "QUEST_TURNED_IN" then
        if not Addon.paused then
            handleQuestTurnedIn(tonumber(arg1))
        end
    elseif event == "QUEST_COMPLETE" then
        if not Addon.paused then
            handleQuestComplete()
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_FINISHED" then
        if not Addon.paused then
            updateWaitingState()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Summon Callboard is an explicit hardware action. Let it reach the handler
        -- even while paused so the hotkey can implement Start-if-needed / Resume.
        handleSummonSpellSucceeded(arg1, arg2, arg3, arg4, arg5)
    elseif event == "PLAYER_DEAD" then
        -- On Ebonhold, death/prestige resets the server-side Callboard refresh
        -- block. Mirror that reset locally so Zen never blocks an eligible
        -- dungeon/raid quest using stale pre-death completion history.
        resetRefreshHistory("PLAYER_DEAD / Ebonhold Callboard reset")
        Addon.deathProtectionUntil = now() + 20
        Addon.waitingMissingAt = nil
        Addon.waitingMissingKey = nil
        Addon:Debug("waiting", "death protection armed; refresh lock history cleared")
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        Addon.deathProtectionUntil = now() + 4
        Addon.waitingMissingAt = nil
        Addon.waitingMissingKey = nil
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        raidReminderNextCheckAt = 0
        cachedInstanceScanAt = -1
        cachedInstanceZoneID = nil
        cachedInstanceZoneName = nil
        lastInstanceDebugKey = nil
        local zoneID, zoneName = currentInstanceContext()
        if zoneID and not Addon.running and not Addon.paused then
            local lockedKey, remaining = instanceRepeatLockState(zoneID)
            if lockedKey and remaining and remaining > 0 then
                Addon:SetStatus("Instance priority ready, but " .. questLabel(lockedKey) .. " is refresh-locked ("
                    .. tostring(remaining) .. " completion" .. (remaining == 1 and "" or "s") .. " remaining).", true)
            else
                Addon:SetStatus("Instance priority ready for " .. tostring(zoneName or "this instance") .. ". Open the Callboard to search.", true)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        raidReminderNextCheckAt = 0
        raidReminderLastZoneID = nil
        raidReminderDismissedZoneID = nil
        cachedInstanceScanAt = -1
        cachedInstanceZoneID = nil
        cachedInstanceZoneName = nil
        lastInstanceDebugKey = nil
        Addon.lastBoardVisible = false
        Addon.running = false
        Addon.paused = false
        Addon.routeSessionArmed = false
        Addon.instanceAutoActive = false
        Addon.discoveryActive = false
        Addon.waitingMissingAt = nil
        Addon.waitingMissingKey = nil
        Addon.lastRecordedCompletionKey = nil
        Addon.lastRecordedCompletionAt = 0
        Addon.deathProtectionUntil = 0
        Addon.discoveryConfirmUntil = nil
        Addon.passiveLearnUntil = nil
        Addon.pendingBoardOpen = nil
        Addon.pendingReroll = nil
        Addon.goldBeforeReroll = nil
        Addon.lastLearnedObjectiveSignature = nil
        setRunnerState("IDLE")
    end
end)

local elapsedSinceTick = 0
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceTick = elapsedSinceTick + (elapsed or 0)
    local interval = (Addon.running and not Addon.paused) and 0.10 or 0.35
    if elapsedSinceTick < interval then
        return
    end
    elapsedSinceTick = 0
    tick()
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("GOSSIP_SHOW")
pcall(eventFrame.RegisterEvent, eventFrame, "GOSSIP_CLOSED")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(eventFrame.RegisterEvent, eventFrame, "ZONE_CHANGED_NEW_AREA")
pcall(eventFrame.RegisterEvent, eventFrame, "ZONE_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "ZONE_CHANGED_INDOORS")
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_TURNED_IN")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_DEAD")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_ALIVE")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_UNGHOST")
