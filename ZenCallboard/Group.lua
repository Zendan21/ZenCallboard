local addonName, Addon = ...
local Core = Addon.Core

local Group = {
    PREFIX = "RAVIOLICB",
    peers = {},
    observedQuests = {},
    pendingShare = nil,
    trackedKey = nil,
    trackedQuestID = nil,
    trackedTitle = nil,
    localTrackedComplete = false,
    nextQueryAt = 0,
    nextUIRefreshAt = 0,
    nextRouteSyncAt = 0,
    autoResyncAt = 0,
    autoResyncPending = false,
    nextHelloAt = 0,
    outgoingRouteChunks = {},
    incomingRoutes = {},
    pendingRouteAcks = {},
    pendingIncomingRoute = nil,
    nextRouteChunkAt = 0,
}
Addon.Group = Group


-- Optional EbonAPI 2.1.x bridge. Keep group-only gameplay messages on the
-- existing PARTY/RAID transport; EbonAPI's shared channel is realm-wide.
-- Direct whispers can use EbonAPI's queued transport safely.
Group.ebonHandle = nil
Group.ebonAttempted = false

function Group:InitEbonAPI()
    if self.ebonHandle then return true end
    local api = _G.EbonAPI
    if type(api) ~= "table" or type(api.NewAddon) ~= "function" then
        return false
    end
    local ok, handle = pcall(api.NewAddon, api, "ZenCallboard", 2, 1)
    if not ok or not handle then return false end
    self.ebonHandle = handle
    -- EbonAPI delivers direct whispers through its own listener. Do not
    -- register the same prefix in two transports, which duplicates messages.
    if type(handle.OnWhisper) == "function" then
        local subscribed = pcall(handle.OnWhisper, handle, self.PREFIX,
            function(sender, message)
                if type(sender) == "string" and type(message) == "string" then
                    Group:HandleAddonMessage(Group.PREFIX, message, "WHISPER", sender)
                end
            end)
        if not subscribed then self.ebonHandle = nil end
    end
    return self.ebonHandle ~= nil
end

local function now()
    return GetTime and GetTime() or 0
end

local function normalizeTitle(value)
    return Core.NormalizeTitle(tostring(value or ""))
end

local function cleanText(value, maxLength)
    value = tostring(value or ""):gsub("[\t\r\n]", " ")
    return string.sub(value, 1, maxLength or 90)
end

local function encodeField(value)
    value = tostring(value or "")
    value = string.gsub(value, "%%", "%%25")
    value = string.gsub(value, "\t", "%%09")
    value = string.gsub(value, "\r", "%%0D")
    value = string.gsub(value, "\n", "%%0A")
    return value
end

local function decodeField(value)
    value = tostring(value or "")
    value = string.gsub(value, "%%0A", "\n")
    value = string.gsub(value, "%%0D", "\r")
    value = string.gsub(value, "%%09", "\t")
    value = string.gsub(value, "%%25", "%%")
    return value
end

local function splitTabs(value)
    local fields = {}
    local startAt = 1
    while true do
        local separator = string.find(value, "\t", startAt, true)
        if not separator then
            table.insert(fields, string.sub(value, startAt))
            break
        end
        table.insert(fields, string.sub(value, startAt, separator - 1))
        startAt = separator + 1
    end
    return fields
end

local function shortName(value)
    value = tostring(value or "")
    return string.match(value, "^([^%-]+)") or value
end

local function nameKey(value)
    return string.lower(shortName(value))
end

local function questIdentityKey(questID, title)
    questID = tonumber(questID) or 0
    if questID > 0 then
        return "id:" .. tostring(questID)
    end
    return "title:" .. normalizeTitle(title)
end

local function identitiesMatch(leftID, leftTitle, rightID, rightTitle)
    leftID = tonumber(leftID) or 0
    rightID = tonumber(rightID) or 0
    if leftID > 0 and rightID > 0 then
        return leftID == rightID
    end
    local left = normalizeTitle(leftTitle)
    local right = normalizeTitle(rightTitle)
    return left ~= "" and left == right
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

local function findQuestInLog(questID, title, preferredIndex)
    questID = tonumber(questID) or 0
    local wantedTitle = normalizeTitle(title)

    local function matches(entry)
        if not entry or entry.isHeader then
            return false
        end
        local entryID = tonumber(entry.questID) or 0
        if questID > 0 and entryID > 0 then
            return questID == entryID
        end
        return wantedTitle ~= "" and normalizeTitle(entry.title) == wantedTitle
    end

    preferredIndex = tonumber(preferredIndex)
    if preferredIndex and preferredIndex > 0 then
        local preferred = getQuestLogEntry(preferredIndex)
        if matches(preferred) then
            return preferredIndex, preferred
        end
    end

    if not GetNumQuestLogEntries then
        return nil
    end
    for index = 1, GetNumQuestLogEntries() do
        local entry = getQuestLogEntry(index)
        if matches(entry) then
            return index, entry
        end
    end
    return nil
end

local function isFlaggedComplete(questID)
    questID = tonumber(questID) or 0
    if questID <= 0 or not IsQuestFlaggedCompleted then
        return false
    end
    local ok, completed = pcall(IsQuestFlaggedCompleted, questID)
    return ok and (completed == true or tonumber(completed) == 1)
end

local function questProgress(index, entry)
    local complete = entry and (entry.isComplete == true or tonumber(entry.isComplete) == 1) or false
    local current = 0
    local total = 0
    local objectiveCount = GetNumQuestLeaderBoards and tonumber(GetNumQuestLeaderBoards(index)) or 0

    for objectiveIndex = 1, objectiveCount do
        local description, _, objectiveComplete = GetQuestLogLeaderBoard(objectiveIndex, index)
        local count, required
        if type(description) == "string" then
            count, required = string.match(description, "(%d+)%s*/%s*(%d+)")
        end
        count = tonumber(count)
        required = tonumber(required)
        if count and required and required > 0 then
            current = current + math.min(count, required)
            total = total + required
        else
            local percent = type(description) == "string" and tonumber(string.match(description, "(%d+)%%")) or nil
            if percent then
                current = current + math.min(percent, 100)
                total = total + 100
            else
                total = total + 1
                if objectiveComplete == true or tonumber(objectiveComplete) == 1 then
                    current = current + 1
                end
            end
        end
    end

    if total == 0 then
        total = 1
        current = complete and 1 or 0
    end
    if current >= total then
        complete = true
    end
    return complete and "C" or "A", current, total
end

function Group:IsGrouped()
    local raidCount = GetNumRaidMembers and tonumber(GetNumRaidMembers()) or 0
    local partyCount = GetNumPartyMembers and tonumber(GetNumPartyMembers()) or 0
    return raidCount > 0 or partyCount > 0
end

function Group:GetChannel()
    if GetNumRaidMembers and (tonumber(GetNumRaidMembers()) or 0) > 0 then
        return "RAID"
    end
    if GetNumPartyMembers and (tonumber(GetNumPartyMembers()) or 0) > 0 then
        return "PARTY"
    end
    return nil
end

function Group:Send(message, distribution, target)
    if type(message) ~= "string" then return false end
    distribution = distribution or self:GetChannel()
    if distribution == "WHISPER" and target and self.ebonHandle
        and type(self.ebonHandle.Whisper) == "function" then
        local ok, sent = pcall(self.ebonHandle.Whisper,
            self.ebonHandle, self.PREFIX, target, message)
        if ok and sent then return true end
    end
    if not SendAddonMessage then return false end
    if not distribution then
        return false
    end
    local ok = pcall(SendAddonMessage, self.PREFIX, message, distribution, target)
    return ok
end

local function buildRoutePayload(routeName, route, autoLoop)
    local lines = {
        table.concat({ "M", encodeField(routeName), autoLoop and "1" or "0", tostring(table.getn(route or {})) }, "\t"),
    }
    for index = 1, table.getn(route or {}) do
        local key = route[index]
        local quest = Addon.db and Addon.db.knownQuests and Addon.db.knownQuests[key] or nil
        local questID = quest and Core.QuestID(quest) or tonumber(string.match(tostring(key), "^id:(%d+)$"))
        local title = quest and Core.QuestTitle(quest) or tostring(key or "Unknown quest")
        table.insert(lines, table.concat({
            "Q",
            tostring(questID or 0),
            encodeField(title),
            encodeField(quest and quest.objectiveText or ""),
            tostring(quest and quest.questType or ""),
            tostring(quest and quest.zoneOrSort or ""),
        }, "\t"))
    end
    return encodeField(table.concat(lines, "\n"))
end

local function parseRoutePayload(payload)
    payload = decodeField(payload)
    local result = {
        name = "Shared Route",
        autoLoop = false,
        quests = {},
    }
    local expectedCount
    for line in string.gmatch(payload .. "\n", "(.-)\n") do
        local fields = splitTabs(line)
        if fields[1] == "M" then
            result.name = decodeField(fields[2])
            result.autoLoop = fields[3] == "1"
            expectedCount = tonumber(fields[4])
        elseif fields[1] == "Q" then
            local quest = Core.NormalizeQuest({
                questId = tonumber(fields[2]),
                title = decodeField(fields[3]),
                objectiveText = decodeField(fields[4]),
                questType = tonumber(fields[5]),
                zoneOrSort = tonumber(fields[6]),
            })
            if quest then
                table.insert(result.quests, quest)
            end
        end
    end
    if not expectedCount or expectedCount < 1 or expectedCount > 200
        or table.getn(result.quests) ~= expectedCount then
        return nil
    end
    result.name = cleanText(result.name ~= "" and result.name or "Shared Route", 80)
    return result
end

function Group:QueueRouteShare(target, routeName, route, autoLoop)
    target = tostring(target or ""):gsub("^%s+", ""):gsub("%s+$", "")
    routeName = tostring(routeName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if target == "" or string.find(target, "%s") then
        return false, "Enter a valid character name to share the route with."
    end
    if type(route) ~= "table" or table.getn(route) == 0 then
        return false, "Add quests before sharing the route."
    end
    if table.getn(route) > 200 then
        return false, "Routes with more than 200 steps cannot be shared."
    end

    routeName = routeName ~= "" and routeName or "Shared Route"
    local payload = buildRoutePayload(routeName, route, autoLoop)
    local transferID = tostring(math.floor(now() * 1000) % 1000000) .. tostring(math.random(100, 999))
    local chunkSize = 180
    local total = math.ceil(string.len(payload) / chunkSize)
    if total > 300 then
        return false, "This route contains too much quest text to share."
    end

    for index = 1, total do
        local chunk = string.sub(payload, ((index - 1) * chunkSize) + 1, index * chunkSize)
        table.insert(self.outgoingRouteChunks, {
            target = target,
            message = "RT\t" .. transferID .. "\t" .. tostring(index) .. "\t" .. tostring(total) .. "\t" .. chunk,
            transferID = transferID,
            final = index == total,
        })
    end
    self.pendingRouteAcks[transferID] = {
        target = target,
        routeName = routeName,
        expiresAt = now() + 90,
    }
    return true, transferID
end

function Group:ProcessOutgoingRouteChunks()
    if now() < (self.nextRouteChunkAt or 0) or table.getn(self.outgoingRouteChunks) == 0 then
        return
    end
    self.nextRouteChunkAt = now() + 0.12
    local item = table.remove(self.outgoingRouteChunks, 1)
    local playerName = UnitName and UnitName("player") or ""
    if nameKey(item.target) == nameKey(playerName) then
        self:HandleAddonMessage(self.PREFIX, item.message, "WHISPER", playerName)
    else
        self:Send(item.message, "WHISPER", item.target)
    end
    if item.final and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r Route sent to " .. tostring(item.target) .. "; waiting for them to accept it.")
    end
end

function Group:SendRouteAcknowledgement(target, transferID, state, detail)
    local message = "RA\t" .. tostring(transferID) .. "\t" .. tostring(state) .. "\t" .. cleanText(detail, 100)
    local playerName = UnitName and UnitName("player") or ""
    if nameKey(target) == nameKey(playerName) then
        self:HandleAddonMessage(self.PREFIX, message, "WHISPER", playerName)
    else
        self:Send(message, "WHISPER", target)
    end
end

local function uniqueSharedRouteName(profile, originalName, sender)
    local base = cleanText(originalName, 60) .. " (from " .. shortName(sender) .. ")"
    local candidate = base
    local suffix = 2
    while profile.savedRoutes[candidate] do
        candidate = base .. " " .. tostring(suffix)
        suffix = suffix + 1
    end
    return candidate
end

-- EbonAPI community route exchange is opt-in: no routes are published
-- automatically, and incoming shared data is never applied automatically.
function Group:PublishCommunityRoute(name, route, autoLoop)
    if not self:InitEbonAPI() or not self.ebonHandle.Share then
        return false, "EbonAPI 2.1+ must be installed and enabled."
    end
    if type(route) ~= "table" or table.getn(route) < 1 or table.getn(route) > 200 then
        return false, "Select a route with 1-200 steps."
    end
    local payload = buildRoutePayload(name or "Shared Route", route, autoLoop)
    local state = math.max(1, tonumber(time and time() or 0) or 0)
    if self.communityShareState and state <= self.communityShareState then
        state = self.communityShareState + 1
    end
    local ok, result = pcall(self.ebonHandle.Share, self.ebonHandle, "route", state, payload)
    if not ok then return false, tostring(result) end
    self.communityShareState = state
    return true
end

function Group:ImportCommunityRoute()
    if not self:InitEbonAPI() or not self.ebonHandle.GetShared then
        return false, "EbonAPI 2.1+ must be installed and enabled."
    end
    local ok, payload = pcall(self.ebonHandle.GetShared, self.ebonHandle, "route")
    if not ok or type(payload) ~= "string" or payload == "" then
        return false, "No community route has been received yet."
    end
    local route = parseRoutePayload(payload)
    if not route then return false, "Received community route data is invalid." end
    if not Addon.profile or not Addon.db then return false, "ZenCallboard is not ready." end
    local keys = {}
    for index = 1, table.getn(route.quests) do
        local quest = route.quests[index]
        Core.LearnQuest(Addon.db, quest)
        local key = Core.QuestKey(quest)
        if key then table.insert(keys, key) end
    end
    if table.getn(keys) ~= table.getn(route.quests) then
        return false, "Community route contains unrecognized quests."
    end
    Addon.profile.savedRoutes = Addon.profile.savedRoutes or {}
    local name = uniqueSharedRouteName(Addon.profile, route.name, "EbonAPI")
    Addon.profile.savedRoutes[name] = { route = keys, autoLoop = route.autoLoop == true }
    if Addon.UI and Addon.UI.RefreshRouteManager then Addon.UI:RefreshRouteManager() end
    if Addon.UI and Addon.UI.Refresh then Addon.UI:Refresh() end
    return true, name
end


-- Browser API: each player publishes a separately named EbonAPI share.
-- EbonAPI synchronizes a collection of keys, not a centralized leaderboard.
function Group:CommunityRoutes()
    local rows = {}
    if not self:InitEbonAPI() then return rows end
    local h = self.ebonHandle
    if not h.SharedNames or not h.GetShared then return rows end
    local ok, names = pcall(h.SharedNames, h)
    if not ok or type(names) ~= "table" then return rows end
    for _, key in pairs(names) do
        if type(key) == "string" and string.sub(key, 1, 6) == "route_" then
            local good, payload = pcall(h.GetShared, h, key)
            if good and type(payload) == "string" then
                local parsed = parseRoutePayload(payload)
                if parsed then
                    table.insert(rows, {
                        key = key, name = parsed.name,
                        author = string.sub(key, 7),
                        steps = table.getn(parsed.quests),
                        route = parsed,
                    })
                end
            end
        end
    end
    table.sort(rows, function(a,b)
        if a.name == b.name then return a.author < b.author end
        return a.name < b.name
    end)
    return rows
end

function Group:PublishBrowsableRoute()
    if not self:InitEbonAPI() then return false, "EbonAPI is not available." end
    if not Addon.profile or not Addon.profile.route then return false, "No active route." end
    local route = Addon.profile.route
    if table.getn(route) == 0 then return false, "Your current route is empty." end
    local author = UnitName and UnitName("player") or "Player"
    author = tostring(author or "Player"):gsub("[^%w_]", "")
    local key = "route_" .. string.sub(author, 1, 25)
    local payload = buildRoutePayload(Addon.profile.activeRouteName or "Community Route", route, Addon.profile.autoLoop)
    local state = math.max(1, tonumber(time and time() or 0) or 0)
    if self.communityShareState and state <= self.communityShareState then state = self.communityShareState + 1 end
    local ok, result = pcall(self.ebonHandle.Share, self.ebonHandle, key, state, payload)
    if not ok then return false, tostring(result) end
    self.communityShareState = state
    if self.ebonHandle.SyncShares then pcall(self.ebonHandle.SyncShares, self.ebonHandle) end
    return true, key
end

function Group:ImportBrowsableRoute(row)
    if type(row) ~= "table" or type(row.route) ~= "table" then return false, "Select a route." end
    if not Addon.profile or not Addon.db then return false, "ZenCallboard is not ready." end
    local parsed = row.route
    local keys = {}
    -- Validate all steps before writing to the local quest catalogue.
    for i=1,table.getn(parsed.quests) do
        local key = Core.QuestKey(parsed.quests[i])
        if not key then return false, "Route contains an invalid quest." end
        table.insert(keys,key)
    end
    for i=1,table.getn(parsed.quests) do Core.LearnQuest(Addon.db, parsed.quests[i]) end
    Addon.profile.savedRoutes = Addon.profile.savedRoutes or {}
    local name = uniqueSharedRouteName(Addon.profile, parsed.name, row.author)
    Addon.profile.savedRoutes[name] = { route=keys, autoLoop=parsed.autoLoop == true }
    if Addon.UI and Addon.UI.RefreshRouteManager then Addon.UI:RefreshRouteManager() end
    if Addon.UI and Addon.UI.Refresh then Addon.UI:Refresh() end
    return true,name
end

function Group:AcceptIncomingRoute(transfer)
    if not transfer or transfer.responded or not transfer.route or not Addon.profile or not Addon.db then
        return
    end
    transfer.responded = "A"
    if self.pendingIncomingRoute and self.pendingIncomingRoute.transferID == transfer.transferID then
        self.pendingIncomingRoute = nil
    end
    Addon.profile.savedRoutes = Addon.profile.savedRoutes or {}
    local route = {}
    for index = 1, table.getn(transfer.route.quests or {}) do
        local quest = transfer.route.quests[index]
        Core.LearnQuest(Addon.db, quest)
        local key = Core.QuestKey(quest)
        if key then
            table.insert(route, key)
        end
    end
    if table.getn(route) == 0 then
        self:SendRouteAcknowledgement(transfer.sender, transfer.transferID, "E", "Route contained no usable quests")
        return
    end

    local savedName = uniqueSharedRouteName(Addon.profile, transfer.route.name, transfer.sender)
    Addon.profile.savedRoutes[savedName] = {
        route = route,
        autoLoop = transfer.route.autoLoop == true,
    }
    if Addon.UI and Addon.UI.RefreshRouteManager then
        Addon.UI:RefreshRouteManager()
    end
    if Addon.UI and Addon.UI.Refresh then
        Addon.UI:Refresh()
    end
    if Addon.SetStatus then
        Addon:SetStatus("Saved shared route: " .. savedName .. ".", true)
    end
    self:SendRouteAcknowledgement(transfer.sender, transfer.transferID, "A", savedName)
end

function Group:DeclineIncomingRoute(transfer)
    if transfer and not transfer.responded then
        transfer.responded = "D"
        if self.pendingIncomingRoute and self.pendingIncomingRoute.transferID == transfer.transferID then
            self.pendingIncomingRoute = nil
        end
        self:SendRouteAcknowledgement(transfer.sender, transfer.transferID, "D", transfer.route and transfer.route.name or "route")
    end
end

function Group:ShowIncomingRoute(transfer)
    self.pendingIncomingRoute = transfer
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r Route received from " .. tostring(transfer.sender) .. ": " .. tostring(transfer.route.name) .. ". Use the popup, /zencb accept, or /zencb decline.")
    end
    if StaticPopup_Show then
        StaticPopup_Show("ZENCALLBOARD_ROUTE_SHARE", transfer.sender, transfer.route.name, transfer)
    end
end

function Group:AcceptLatestIncomingRoute()
    local transfer = self.pendingIncomingRoute
    if not transfer then
        return false
    end
    self:AcceptIncomingRoute(transfer)
    if StaticPopup_Hide then
        StaticPopup_Hide("ZENCALLBOARD_ROUTE_SHARE")
    end
    return true
end

function Group:DeclineLatestIncomingRoute()
    local transfer = self.pendingIncomingRoute
    if not transfer then
        return false
    end
    self:DeclineIncomingRoute(transfer)
    if StaticPopup_Hide then
        StaticPopup_Hide("ZENCALLBOARD_ROUTE_SHARE")
    end
    return true
end

function Group:HandleRouteChunk(sender, transferID, index, total, chunk)
    index = tonumber(index)
    total = tonumber(total)
    if not sender or not transferID or not index or not total or total < 1 or total > 300
        or index < 1 or index > total then
        return
    end
    local key = nameKey(sender) .. ":" .. tostring(transferID)
    local transfer = self.incomingRoutes[key]
    if not transfer or transfer.total ~= total then
        transfer = {
            sender = sender,
            transferID = transferID,
            total = total,
            received = 0,
            chunks = {},
            expiresAt = now() + 45,
        }
        self.incomingRoutes[key] = transfer
    end
    if not transfer.chunks[index] then
        transfer.chunks[index] = chunk or ""
        transfer.received = transfer.received + 1
    end
    if transfer.received < transfer.total then
        return
    end

    local payload = {}
    for chunkIndex = 1, transfer.total do
        if not transfer.chunks[chunkIndex] then
            return
        end
        table.insert(payload, transfer.chunks[chunkIndex])
    end
    self.incomingRoutes[key] = nil
    transfer.route = parseRoutePayload(table.concat(payload, ""))
    if not transfer.route then
        self:SendRouteAcknowledgement(sender, transferID, "E", "Route data was incomplete")
        return
    end
    self:ShowIncomingRoute(transfer)
end

function Group:HandleRouteAcknowledgement(transferID, state, detail)
    local pending = self.pendingRouteAcks[transferID]
    if not pending then
        return
    end
    self.pendingRouteAcks[transferID] = nil
    local message
    if state == "A" then
        message = pending.target .. " accepted and saved the route as " .. tostring(detail) .. "."
    elseif state == "D" then
        message = pending.target .. " declined the shared route."
    else
        message = pending.target .. " could not import the route: " .. tostring(detail) .. "."
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r " .. message)
    end
end

function Group:QuestIdentityForKey(key)
    local quest = key and Addon.db and Addon.db.knownQuests and Addon.db.knownQuests[key]
    if not quest then
        return nil, tostring(key or "")
    end
    return Core.QuestID(quest), Core.QuestTitle(quest)
end

function Group:SetTrackedQuest(key)
    local questID, title = self:QuestIdentityForKey(key)
    self.trackedKey = key
    self.trackedQuestID = tonumber(questID) or 0
    self.trackedTitle = title
    self.localTrackedComplete = false
    self.nextQueryAt = 0
end

function Group:MarkTrackedComplete(key)
    local questID, title = self:QuestIdentityForKey(key)
    if identitiesMatch(self.trackedQuestID, self.trackedTitle, questID, title) then
        self.localTrackedComplete = true
    end
end

function Group:GetProgress(questID, title)
    local identityKey = questIdentityKey(questID, title)
    local observed = self.observedQuests[identityKey]
    local index, entry = findQuestInLog(questID, title)
    if index and entry then
        observed = observed or {}
        observed.seen = true
        local state, current, total = questProgress(index, entry)
        if state == "C" then
            observed.complete = true
        end
        self.observedQuests[identityKey] = observed
        return state, current, total
    end

    if isFlaggedComplete(questID) or (observed and observed.seen) then
        if observed then
            observed.complete = true
        end
        return "C", 1, 1
    end
    return "N", 0, 0
end

local function restoreQuestLogSelection(previousIndex)
    if previousIndex and previousIndex > 0 and SelectQuestLogEntry then
        SelectQuestLogEntry(previousIndex)
    end
end

function Group:ShareQuestLogIndex(index, title)
    if not index or not SelectQuestLogEntry or not QuestLogPushQuest then
        return false, "Quest sharing is unavailable on this client."
    end

    local previousIndex = GetQuestLogSelection and tonumber(GetQuestLogSelection()) or nil
    SelectQuestLogEntry(index)
    if GetQuestLogPushable and not GetQuestLogPushable() then
        restoreQuestLogSelection(previousIndex)
        return false, "Quest is not shareable: " .. tostring(title or "quest")
    end

    QuestLogPushQuest()
    restoreQuestLogSelection(previousIndex)
    return true
end

function Group:ShareCurrentRouteQuest()
    if not self:IsGrouped() then
        return false, "You are not currently in a group."
    end

    local key = self.trackedKey
    if not key and Addon.profile and Addon.profile.route then
        key = Addon.waitingKey or Addon.profile.route[Addon.profile.currentStep]
    end
    if not key then
        return false, "No current route quest is available to share."
    end

    local questID, title = self:QuestIdentityForKey(key)
    local index, entry = findQuestInLog(questID, title)
    if not index then
        return false, "The current route quest is not in your quest log yet."
    end

    local shared, reason = self:ShareQuestLogIndex(index, entry and entry.title or title)
    if shared then
        return true, "Shared route quest with the group: " .. tostring(entry and entry.title or title)
    end
    return false, reason or "The current route quest could not be shared."
end

function Group:QueueAutoShare(key, questID, title, preferredIndex)
    self:SetTrackedQuest(key)
    if not Addon.profile or Addon.profile.autoShare ~= true then
        return
    end
    self.pendingShare = {
        questID = tonumber(questID) or 0,
        title = title or "",
        preferredIndex = preferredIndex,
        expiresAt = now() + 12,
        nextAttemptAt = 0,
    }
end

function Group:ProcessPendingShare()
    local pending = self.pendingShare
    if not pending then
        return
    end
    if not Addon.profile or Addon.profile.autoShare ~= true or now() > pending.expiresAt then
        self.pendingShare = nil
        return
    end
    if not self:IsGrouped() or now() < (pending.nextAttemptAt or 0) then
        return
    end

    pending.nextAttemptAt = now() + 0.35
    local index, entry = findQuestInLog(pending.questID, pending.title, pending.preferredIndex)
    if not index then
        return
    end

    local shared, reason = self:ShareQuestLogIndex(index, entry and entry.title or pending.title)
    self.pendingShare = nil
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        if shared then
            DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r Shared route quest with the group: " .. tostring(entry and entry.title or pending.title))
        elseif reason then
            DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r " .. tostring(reason))
        end
    end
end



function Group:IsEnabled()
    return Addon.profile ~= nil and Addon.profile.showGroupProgress == true
end

function Group:IsLinkedName(name)
    if not self:IsEnabled() or not Addon.profile then
        return false
    end
    local linked = Addon.profile.linkedGroupMembers or {}
    return linked[nameKey(name)] == true
end

function Group:HasLinkedMembers()
    if not self:IsEnabled() or not self:IsGrouped() then
        return false
    end
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected and self:IsLinkedName(member.name) then
            return true
        end
    end
    return false
end

function Group:IsSyncActive()
    return self:IsEnabled() and self:IsGrouped() and self:HasLinkedMembers()
end


function Group:IsNameInCurrentGroup(name)
    local wanted = nameKey(name)
    if wanted == "" then
        return false
    end
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected and member.key == wanted then
            return true, member.name
        end
    end
    return false
end

function Group:ToggleTargetLink()
    if not UnitExists or not UnitExists("target") or not UnitName then
        return false, "Target a group member first."
    end
    if UnitIsUnit and UnitIsUnit("target", "player") then
        return false, "You cannot link yourself."
    end

    local targetName = UnitName("target")
    if not targetName or targetName == "" then
        return false, "Target a group member first."
    end

    local inGroup, rosterName = self:IsNameInCurrentGroup(targetName)
    if not inGroup then
        return false, tostring(shortName(targetName)) .. " is not in your current group."
    end

    local linked = self:IsLinkedName(rosterName)
    self:SetLinkedMember(rosterName, not linked)
    if linked then
        return true, "Unlinked Callboard sync with " .. tostring(rosterName) .. "."
    end
    return true, "Linked Callboard sync with " .. tostring(rosterName) .. "."
end

function Group:SetLinkedMember(name, linked)
    if not Addon.profile then
        return false
    end
    name = shortName(name)
    if name == "" or nameKey(name) == nameKey(UnitName and UnitName("player") or "") then
        return false
    end
    Addon.profile.linkedGroupMembers = Addon.profile.linkedGroupMembers or {}
    local key = nameKey(name)
    if linked then
        Addon.profile.linkedGroupMembers[key] = true
    else
        Addon.profile.linkedGroupMembers[key] = nil
        self.peers[key] = nil
    end
    self.nextQueryAt = 0
    self.nextRouteSyncAt = 0
    if linked and self:IsEnabled() then
        self:ScheduleAutoResync(0.2)
    end
    if Addon.UI and Addon.UI.RefreshGroupProgress then
        Addon.UI:RefreshGroupProgress()
    end
    return true
end

function Group:LinkCurrentGroup()
    if not Addon.profile then
        return 0
    end
    local count = 0
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected then
            Addon.profile.linkedGroupMembers = Addon.profile.linkedGroupMembers or {}
            Addon.profile.linkedGroupMembers[member.key] = true
            count = count + 1
        end
    end
    self.nextQueryAt = 0
    self.nextRouteSyncAt = 0
    if count > 0 and self:IsEnabled() then
        self:ScheduleAutoResync(0.2)
    end
    if Addon.UI and Addon.UI.RefreshGroupProgress then
        Addon.UI:RefreshGroupProgress()
    end
    return count
end

function Group:UnlinkCurrentGroup()
    if not Addon.profile then
        return 0
    end
    local count = 0
    Addon.profile.linkedGroupMembers = Addon.profile.linkedGroupMembers or {}
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and Addon.profile.linkedGroupMembers[member.key] then
            Addon.profile.linkedGroupMembers[member.key] = nil
            self.peers[member.key] = nil
            count = count + 1
        end
    end
    self.autoResyncPending = false
    if Addon.UI and Addon.UI.RefreshGroupProgress then
        Addon.UI:RefreshGroupProgress()
    end
    return count
end

function Group:GetCurrentLinkCounts()
    local linked, available = 0, 0
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected then
            available = available + 1
            if self:IsLinkedName(member.name) then
                linked = linked + 1
            end
        end
    end
    return linked, available
end

function Group:SendLinked(message)
    if not self:IsSyncActive() then
        return false
    end
    local sent = false
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected and self:IsLinkedName(member.name) then
            if self:Send(message, "WHISPER", member.name) then
                sent = true
            end
        end
    end
    return sent
end

function Group:DisableSync()
    self.autoResyncPending = false
    self.nextQueryAt = 0
    self.nextRouteSyncAt = 0
    self.peers = {}
end

-- Automatic group discovery (1.0.58).
-- Normal party/raid members never become a dependency. Only characters that
-- answer ZenCallboard's HELLO packet participate in route/progress syncing.
function Group:IsLinkedName(name)
    if not self:IsEnabled() then
        return false
    end
    local peer = self.peers[nameKey(name)]
    if not peer then
        return false
    end
    local seen = peer.addonSeen or peer.lastSeen or peer.routeSeen or 0
    return now() - seen <= 10
end

function Group:HasLinkedMembers()
    if not self:IsEnabled() or not self:IsGrouped() then
        return false
    end
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected and self:IsLinkedName(member.name) then
            return true
        end
    end
    return false
end

function Group:IsSyncActive()
    return self:IsEnabled() and self:IsGrouped() and self:HasLinkedMembers()
end

function Group:SendLinked(message)
    if not self:IsEnabled() or not self:IsGrouped() then
        return false
    end
    local sent = false
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        if not member.isPlayer and member.connected and self:IsLinkedName(member.name) then
            if self:Send(message, "WHISPER", member.name) then
                sent = true
            end
        end
    end
    return sent
end

function Group:BroadcastHello()
    if not self:IsEnabled() or not self:IsGrouped() then
        return false
    end
    return self:Send("H\t1")
end

function Group:DisableSync()
    self.autoResyncPending = false
    self.nextQueryAt = 0
    self.nextRouteSyncAt = 0
    self.nextHelloAt = 0
    self.peers = {}
end

local function routeFingerprint()
    local route = Addon.profile and Addon.profile.route or {}
    local hash = 5381
    for index = 1, table.getn(route) do
        local value = tostring(route[index] or "")
        for charIndex = 1, string.len(value) do
            hash = ((hash * 33) + string.byte(value, charIndex)) % 2147483647
        end
        hash = ((hash * 33) + index) % 2147483647
    end
    return tostring(table.getn(route)) .. ":" .. tostring(hash)
end

function Group:BroadcastRouteState()
    if not self:IsSyncActive() or not Addon.profile then
        return false
    end
    local step = tonumber(Addon.profile.currentStep) or 1
    return self:SendLinked("S\t" .. routeFingerprint() .. "\t" .. tostring(step))
end

function Group:ScheduleAutoResync(delay)
    if not self:IsEnabled() then
        self.autoResyncPending = false
        return
    end
    self.autoResyncPending = true
    self.autoResyncAt = now() + (tonumber(delay) or 1.0)
end

function Group:RefreshAndSync()
    if not self:IsSyncActive() then
        if Addon.UI and Addon.UI.RefreshGroupProgress then
            Addon.UI:RefreshGroupProgress()
        end
        return false
    end
    self.nextQueryAt = 0
    self.nextRouteSyncAt = 0
    if not self.trackedKey and Addon.profile and Addon.profile.route then
        local key = Addon.profile.route[Addon.profile.currentStep or 1]
        if key then
            self:SetTrackedQuest(key)
        end
    end
    self:BroadcastRouteState()
    if self.trackedKey then
        local message = "Q\t" .. tostring(tonumber(self.trackedQuestID) or 0) .. "\t" .. cleanText(self.trackedTitle, 90)
        self:SendLinked(message)
    end
    if Addon.UI and Addon.UI.RefreshGroupProgress then
        Addon.UI:RefreshGroupProgress()
    end
end

function Group:BroadcastProgress(questID, title, distribution, target)
    local state, current, total = self:GetProgress(questID, title)
    if self.localTrackedComplete and identitiesMatch(self.trackedQuestID, self.trackedTitle, questID, title) then
        state, current, total = "C", 1, 1
    end
    local message = "P\t" .. tostring(tonumber(questID) or 0)
        .. "\t" .. state
        .. "\t" .. tostring(current or 0)
        .. "\t" .. tostring(total or 0)
        .. "\t" .. cleanText(title, 90)
    self:Send(message, distribution, target)
end

function Group:HandleAddonMessage(prefix, message, distribution, sender)
    if prefix ~= self.PREFIX or type(message) ~= "string" then
        return
    end
    local transferID, chunkIndex, chunkTotal, chunk = string.match(message, "^RT\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
    if transferID then
        self:HandleRouteChunk(sender, transferID, chunkIndex, chunkTotal, chunk)
        return
    end

    local acknowledgementID, acknowledgementState, acknowledgementDetail = string.match(message, "^RA\t([^\t]+)\t([ADE])\t(.*)$")
    if acknowledgementID then
        self:HandleRouteAcknowledgement(acknowledgementID, acknowledgementState, acknowledgementDetail)
        return
    end

    -- Progress requests should not echo back to the same character, but route
    -- transfers and acknowledgements above intentionally support self-testing.
    if nameKey(sender) == nameKey(UnitName and UnitName("player") or "") then
        return
    end

    if not self:IsEnabled() or not sender then
        return
    end

    local helloVersion = string.match(message, "^H\t([^\t]+)$")
    if helloVersion then
        local helloPeer = self.peers[nameKey(sender)] or { name = shortName(sender) }
        helloPeer.name = shortName(sender)
        helloPeer.addonSeen = now()
        helloPeer.addonVersion = helloVersion
        self.peers[nameKey(sender)] = helloPeer
        if distribution ~= "WHISPER" then
            self:Send("H\t1", "WHISPER", sender)
        end
        self.nextRouteSyncAt = 0
        self.nextQueryAt = 0
        if Addon.UI and Addon.UI.RefreshGroupProgress then
            Addon.UI:RefreshGroupProgress()
        end
        return
    end

    if not self:IsLinkedName(sender) then
        return
    end

    local syncSignature, syncStep = string.match(message, "^S\t([^\t]+)\t([^\t]+)$")
    if syncSignature and sender then
        local peer = self.peers[nameKey(sender)] or { name = shortName(sender) }
        peer.routeSignature = syncSignature
        peer.routeStep = math.max(1, tonumber(syncStep) or 1)
        peer.routeSeen = now()
        peer.addonSeen = now()
        self.peers[nameKey(sender)] = peer

        if Addon.profile and syncSignature == routeFingerprint() then
            local localStep = math.max(1, tonumber(Addon.profile.currentStep) or 1)
            -- Group linking follows the furthest member on the same ordered route.
            -- This lets a late joiner catch up without pulling an advanced member back.
            if peer.routeStep > localStep and Addon.SyncGroupStep then
                Addon:SyncGroupStep(peer.routeStep, shortName(sender))
            elseif localStep > peer.routeStep then
                -- Advertise our later step immediately so the other member can catch up.
                self.nextRouteSyncAt = 0
            end
        end
        if Addon.UI and Addon.UI.RefreshGroupProgress then
            Addon.UI:RefreshGroupProgress()
        end
        return
    end

    local queryID, queryTitle = string.match(message, "^Q\t([^\t]*)\t(.*)$")
    if queryID then
        self:BroadcastProgress(tonumber(queryID), queryTitle, "WHISPER", sender)
        return
    end

    local progressID, state, current, total, title = string.match(message, "^P\t([^\t]*)\t([ACN])\t([^\t]*)\t([^\t]*)\t(.*)$")
    if not progressID or not sender then
        return
    end
    local existingPeer = self.peers[nameKey(sender)] or {}
    self.peers[nameKey(sender)] = {
        name = shortName(sender),
        questID = tonumber(progressID) or 0,
        title = cleanText(title, 90),
        state = state,
        current = math.max(0, tonumber(current) or 0),
        total = math.max(0, tonumber(total) or 0),
        lastSeen = now(),
        routeSignature = existingPeer.routeSignature,
        routeStep = existingPeer.routeStep,
        routeSeen = existingPeer.routeSeen,
        addonSeen = now(),
        addonVersion = existingPeer.addonVersion,
    }
    if Addon.UI and Addon.UI.RefreshGroupProgress then
        Addon.UI:RefreshGroupProgress()
    end
end

local function addRosterMember(result, seen, unit)
    if not UnitName then
        return
    end
    local name = UnitName(unit)
    if not name or name == "" then
        return
    end
    local key = nameKey(name)
    if seen[key] then
        return
    end
    seen[key] = true
    local isPlayer = UnitIsUnit and UnitIsUnit(unit, "player") or key == nameKey(UnitName("player"))
    local inRange = true
    if not isPlayer then
        if UnitInRange then
            local range = UnitInRange(unit)
            if range ~= nil then
                inRange = range == true or tonumber(range) == 1
            elseif CheckInteractDistance then
                inRange = CheckInteractDistance(unit, 4) == true or tonumber(CheckInteractDistance(unit, 4)) == 1
            end
        elseif CheckInteractDistance then
            local range = CheckInteractDistance(unit, 4)
            inRange = range == true or tonumber(range) == 1
        end
    end
    table.insert(result, {
        name = shortName(name),
        key = key,
        unit = unit,
        isPlayer = isPlayer,
        connected = not UnitIsConnected or UnitIsConnected(unit),
        inRange = inRange,
    })
end

function Group:GetRoster()
    local result = {}
    local seen = {}
    local raidCount = GetNumRaidMembers and tonumber(GetNumRaidMembers()) or 0
    if raidCount > 0 then
        for index = 1, raidCount do
            addRosterMember(result, seen, "raid" .. tostring(index))
        end
    else
        addRosterMember(result, seen, "player")
        local partyCount = GetNumPartyMembers and tonumber(GetNumPartyMembers()) or 0
        for index = 1, partyCount do
            addRosterMember(result, seen, "party" .. tostring(index))
        end
    end
    return result
end

local function statusText(state, current, total)
    if state == "C" then
        return "Complete", "complete"
    end
    if state == "N" then
        return "Quest not found", "missing"
    end
    if tonumber(total) and tonumber(total) > 0 then
        return tostring(current or 0) .. "/" .. tostring(total), "active"
    end
    return "In progress", "active"
end


function Group:GetRouteConsistency()
    local result = {
        grouped = self:IsGrouped(),
        ready = true,
        routeMismatch = false,
        stepMismatch = false,
        unknown = false,
        furthestStep = Addon.profile and (tonumber(Addon.profile.currentStep) or 1) or 1,
        memberCount = 0,
        addonCount = 0,
    }
    if not result.grouped or not Addon.profile or not self:IsEnabled() then
        return result
    end

    local localSignature = routeFingerprint()
    local localStep = tonumber(Addon.profile.currentStep) or 1
    local roster = self:GetRoster()
    result.memberCount = table.getn(roster)

    for index = 1, table.getn(roster) do
        local member = roster[index]
        if member.isPlayer then
            result.addonCount = result.addonCount + 1
        elseif member.connected and self:IsLinkedName(member.name) then
            local peer = self.peers[member.key]
            if not peer or not peer.routeSignature or now() - (peer.routeSeen or 0) > 10 then
                result.unknown = true
                result.ready = false
            else
                result.addonCount = result.addonCount + 1
                if peer.routeSignature ~= localSignature then
                    result.routeMismatch = true
                    result.ready = false
                else
                    local peerStep = math.max(1, tonumber(peer.routeStep) or 1)
                    if peerStep ~= localStep then
                        result.stepMismatch = true
                        result.ready = false
                    end
                    if peerStep > result.furthestStep then
                        result.furthestStep = peerStep
                    end
                end
            end
        end
    end
    return result
end

function Group:IsRouteReady()
    local state = self:GetRouteConsistency()
    if not state.grouped then
        return true, state
    end
    return state.ready == true, state
end

function Group:GetDisplay()
    local questID = tonumber(self.trackedQuestID) or 0
    local title = self.trackedTitle or ""
    if not self.trackedKey and Addon.profile then
        local key = Addon.waitingKey or Addon.profile.route[Addon.profile.currentStep]
        questID, title = self:QuestIdentityForKey(key)
        questID = tonumber(questID) or 0
    end

    local rows = {}
    local completeCount = 0
    local addonCount = 0
    local consistency = self:GetRouteConsistency()
    local roster = self:GetRoster()
    for index = 1, table.getn(roster) do
        local member = roster[index]
        local state, current, total
        if not member.connected then
            state = "O"
        elseif member.isPlayer then
            state, current, total = self:GetProgress(questID, title)
            if self.localTrackedComplete then
                state, current, total = "C", 1, 1
            end
            addonCount = addonCount + 1
        else
            local peer = self.peers[member.key]
            if not self:IsLinkedName(member.name) then
                state = "X"
            elseif not member.inRange then
                state = "R"
            elseif peer and peer.routeSignature and peer.routeSignature ~= routeFingerprint() then
                state = "D"
            elseif peer and now() - (peer.lastSeen or 0) <= 8
                and identitiesMatch(peer.questID, peer.title, questID, title) then
                state, current, total = peer.state, peer.current, peer.total
                addonCount = addonCount + 1
            else
                state = "U"
            end
        end

        local label, color
        if state == "O" then
            label, color = "Offline", "missing"
        elseif state == "X" then
            label, color = "Not linked", "unknown"
        elseif state == "R" then
            label, color = "Out of range — refresh when nearby", "warning"
        elseif state == "D" then
            label, color = "Different route — cannot sync", "missing"
        elseif state == "U" then
            label, color = "No/stale addon data — press Refresh / Sync", "unknown"
        else
            label, color = statusText(state, current, total)
        end
        if state == "C" then
            completeCount = completeCount + 1
        end
        table.insert(rows, {
            name = member.name,
            status = label,
            color = color,
        })
    end

    local outOfRangeCount = 0
    for index = 1, table.getn(rows) do
        if rows[index].status and string.find(rows[index].status, "Out of range", 1, true) then
            outOfRangeCount = outOfRangeCount + 1
        end
    end

    return {
        title = title ~= "" and title or "Current route quest",
        rows = rows,
        outOfRangeCount = outOfRangeCount,
        completeCount = completeCount,
        memberCount = table.getn(rows),
        addonCount = addonCount,
        grouped = self:IsGrouped(),
        routeReady = consistency.ready,
        routeMismatch = consistency.routeMismatch,
        stepMismatch = consistency.stepMismatch,
        unknownRouteState = consistency.unknown,
        furthestStep = consistency.furthestStep,
    }
end

function Group:Tick()
    self:ProcessOutgoingRouteChunks()

    local tickNow = now()
    if tickNow < (self.nextHousekeepingAt or 0) then
        return
    end
    self.nextHousekeepingAt = tickNow + 0.5

    for key, transfer in pairs(self.incomingRoutes) do
        if tickNow > (transfer.expiresAt or 0) then
            self.incomingRoutes[key] = nil
        end
    end
    for transferID, pending in pairs(self.pendingRouteAcks) do
        if tickNow > (pending.expiresAt or 0) then
            self.pendingRouteAcks[transferID] = nil
            if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r No route-share response from " .. tostring(pending.target) .. ". They may not have ZenCallboard installed.")
            end
        end
    end

    self:ProcessPendingShare()

    if self:IsEnabled() and self:IsGrouped() and tickNow >= (self.nextHelloAt or 0) then
        self.nextHelloAt = tickNow + 8
        self:BroadcastHello()
    end

    if self.autoResyncPending and tickNow >= (self.autoResyncAt or 0) then
        self.autoResyncPending = false
        if self:IsSyncActive() then
            self:RefreshAndSync()
            if Addon.Debug then
                Addon:Debug("group", "automatic group resync requested")
            end
        end
    end

    if not self:IsSyncActive() then
        return
    end

    local progressWindowOpen = Addon.UI and Addon.UI.groupProgressFrame
        and Addon.UI.groupProgressFrame:IsShown()
    if not Addon.running and not progressWindowOpen then
        return
    end

    if tickNow >= (self.nextRouteSyncAt or 0) then
        self.nextRouteSyncAt = tickNow + 2.5
        self:BroadcastRouteState()
    end

    if tickNow >= (self.nextQueryAt or 0) and self.trackedKey then
        self.nextQueryAt = tickNow + 2.5
        local message = "Q\t" .. tostring(tonumber(self.trackedQuestID) or 0) .. "\t" .. cleanText(self.trackedTitle, 90)
        self:SendLinked(message)
    end

    if tickNow >= (self.nextUIRefreshAt or 0) then
        self.nextUIRefreshAt = tickNow + 0.5
        if Addon.UI and Addon.UI.RefreshGroupProgress then
            Addon.UI:RefreshGroupProgress()
        end
    end
end

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs.ZENCALLBOARD_ROUTE_SHARE = {
        text = "%s wants to share the route |cffffcc00%s|r with you.\nAccept and save a copy?",
        button1 = ACCEPT or "Accept",
        button2 = DECLINE or "Decline",
        OnAccept = function(self, data)
            Group:AcceptIncomingRoute(data or self.data)
        end,
        OnCancel = function(self, data)
            Group:DeclineIncomingRoute(data or self.data)
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "PLAYER_LOGIN" then
        Group:InitEbonAPI()
        if RegisterAddonMessagePrefix then
            pcall(RegisterAddonMessagePrefix, Group.PREFIX)
        end
        if Group:IsEnabled() then
            Group:ScheduleAutoResync(2.0)
        end
    elseif event == "CHAT_MSG_ADDON" then
        if not (Group.ebonHandle and arg1 == Group.PREFIX and arg3 == "WHISPER") then
            Group:HandleAddonMessage(arg1, arg2, arg3, arg4)
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        Group.nextQueryAt = 0
        Group.nextRouteSyncAt = 0
        Group.nextHelloAt = 0
        if Group:IsEnabled() then
            Group:ScheduleAutoResync(1.0)
        end
        if Addon.UI and Addon.UI.RefreshGroupProgress then
            Addon.UI:RefreshGroupProgress()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if Group:IsSyncActive() then
            Group.nextQueryAt = 0
            Group:ScheduleAutoResync(0.5)
        end
        if Addon.UI and Addon.UI.RefreshGroupProgress then
            Addon.UI:RefreshGroupProgress()
        end
    end
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
