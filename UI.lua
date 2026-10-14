local addonName, Addon = ...
local Core = Addon.Core
local Style = Addon.ZenStyle and Addon.ZenStyle.UI

local UI = {
    routeRows = {},
    catalogRows = {},
    savedRouteRows = {},
    routeOffset = 0,
    catalogOffset = 0,
    savedRouteOffset = 0,
    selectedRouteIndex = nil,
    searchText = "",
}
Addon.UI = UI

local COLORS = {
    background = { 0.035, 0.043, 0.055, 0.98 },
    panel = { 0.065, 0.075, 0.095, 0.98 },
    panelLight = { 0.090, 0.102, 0.125, 1 },
    border = { 0.22, 0.25, 0.30, 1 },
    gold = { 0.86, 0.64, 0.25, 1 },
    text = { 0.92, 0.92, 0.92, 1 },
    muted = { 0.58, 0.62, 0.68, 1 },
    green = { 0.35, 0.78, 0.48, 1 },
    red = { 0.88, 0.32, 0.30, 1 },
    current = { 0.090, 0.102, 0.125, 1 },
    selected = { 0.090, 0.102, 0.125, 1 },
    normal = { 0.065, 0.075, 0.095, 0.98 },
}

local function setTextureColor(texture, color)
    texture:SetTexture(color[1], color[2], color[3], color[4] or 1)
end

local function setBackdrop(frame, color, border)
    if not frame or not frame.SetBackdrop then
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    if Style and Style.StyleSurface then
        local kind = "panel"
        if frame.GetObjectType and frame:GetObjectType() == "Button" then kind = "button" end
        Style:StyleSurface(frame, kind)
        -- Keep the original backdrop API available for dynamic selection states,
        -- but let ZenStylingPack paint the default surface.
        frame:SetBackdropColor(0,0,0,0)
        frame:SetBackdropBorderColor(0,0,0,0)
    else
        frame:SetBackdropColor(unpack(color or COLORS.panel))
        frame:SetBackdropBorderColor(unpack(border or COLORS.border))
    end
end

local function makeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width)
    button:SetHeight(height)
    setBackdrop(button, COLORS.panelLight, COLORS.border)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetAllPoints()
    button.label:SetText(text or "")
    button.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() == 1 then
            self:SetBackdropColor(0.14, 0.16, 0.20, 1)
            self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.8)
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(COLORS.panelLight[1], COLORS.panelLight[2], COLORS.panelLight[3], COLORS.panelLight[4])
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], COLORS.border[4])
    end)
    button:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() == 1 then
            self.label:ClearAllPoints()
            self.label:SetPoint("CENTER", 1, -1)
        end
    end)
    button:SetScript("OnMouseUp", function(self)
        self.label:ClearAllPoints()
        self.label:SetAllPoints()
    end)
    function button:SetButtonEnabled(enabled)
        if enabled then
            self:Enable()
            self.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
        else
            self:Disable()
            self.label:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
        end
    end
    return button
end

local function styleSecureButton(button, text)
    button:SetWidth(button:GetWidth())
    setBackdrop(button, COLORS.panelLight, COLORS.border)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetAllPoints()
    button.label:SetText(text or "")
    button.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.16, 0.20, 1)
        self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.8)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(COLORS.panelLight[1], COLORS.panelLight[2], COLORS.panelLight[3], COLORS.panelLight[4])
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], COLORS.border[4])
    end)
    button:SetScript("OnMouseDown", function(self)
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER", 1, -1)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.label:ClearAllPoints()
        self.label:SetAllPoints()
    end)
    return button
end

local function setButtonText(button, text)
    if button and button.label then
        button.label:SetText(text or "")
    end
end

local function makeInput(parent, width, height, maxLetters)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(width)
    holder:SetHeight(height)
    setBackdrop(holder, { 0.025, 0.030, 0.040, 1 }, COLORS.border)
    local input = CreateFrame("EditBox", nil, holder)
    input:SetPoint("TOPLEFT", 9, -2)
    input:SetPoint("BOTTOMRIGHT", -9, 2)
    input:SetFont("Fonts\\FRIZQT__.TTF", 12)
    input:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    input:SetAutoFocus(false)
    input:SetJustifyH("LEFT")
    input:SetMaxLetters(maxLetters or 80)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    holder.input = input
    return holder, input
end

local function makeCheckbox(parent, label)
    local checkbox = CreateFrame("Button", nil, parent)
    checkbox:SetWidth(18)
    checkbox:SetHeight(18)
    setBackdrop(checkbox, COLORS.panelLight, COLORS.border)
    checkbox.mark = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkbox.mark:SetAllPoints()
    checkbox.mark:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.label:SetText(label)
    checkbox.checked = false
    function checkbox:SetChecked(value)
        self.checked = value and true or false
        self.mark:SetText(self.checked and "X" or "")
        self:SetBackdropBorderColor(
            self.checked and COLORS.gold[1] or COLORS.border[1],
            self.checked and COLORS.gold[2] or COLORS.border[2],
            self.checked and COLORS.gold[3] or COLORS.border[3],
            1
        )
    end
    function checkbox:GetChecked()
        return self.checked
    end
    checkbox:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
    end)
    return checkbox
end

local function makePanel(parent, title, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(width)
    panel:SetHeight(height)
    setBackdrop(panel, COLORS.panel)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.title:SetText(title)
    panel.title:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    return panel
end

local function addHeaderBand(frame, height)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    texture:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    texture:SetHeight(height or 44)
    setTextureColor(texture, { 0.055, 0.062, 0.078, 1 })
    return texture
end

local function clampOffset(offset, count, visible)
    return math.max(0, math.min(offset or 0, math.max(0, count - visible)))
end

local function getStatusColor(message)
    local lower = string.lower(tostring(message or ""))
    if string.find(lower, "stopped", 1, true)
        or string.find(lower, "could not", 1, true)
        or string.find(lower, "not enough", 1, true)
        or string.find(lower, "repeat-locked", 1, true)
    then
        return COLORS.red
    elseif string.find(lower, "completed", 1, true)
        or string.find(lower, "route complete", 1, true)
        or string.find(lower, "saved", 1, true)
        or string.find(lower, "accepted", 1, true)
    then
        return COLORS.green
    elseif string.find(lower, "running", 1, true)
        or string.find(lower, "waiting", 1, true)
        or string.find(lower, "reroll", 1, true)
        or string.find(lower, "active", 1, true)
    then
        return COLORS.gold
    end
    return COLORS.muted
end

local function createRouteRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(27)
    row:SetPoint("LEFT", parent, "LEFT", 8, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    setBackdrop(row, COLORS.normal, COLORS.border)

    row.number = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.number:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.number:SetWidth(32)
    row.number:SetJustifyH("RIGHT")

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.number, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.label:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        UI.selectedRouteIndex = self.routeIndex
        UI:Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.16, 0.20, 1)
        self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.8)
    end)
    row:SetScript("OnLeave", function(self)
        UI:Refresh()
    end)
    return row
end

local function createCatalogRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(27)
    row:SetPoint("LEFT", parent, "LEFT", 8, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    row:EnableMouse(true)
    setBackdrop(row, COLORS.normal, COLORS.border)

    row.add = makeButton(row, "+", 28, 21)
    row.add:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.add:SetScript("OnClick", function(self)
        if self.questKey then
            Addon:AddRouteQuest(self.questKey)
        end
    end)

    row.info = makeButton(row, "?", 26, 21)
    row.info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.info:SetScript("OnClick", function(self)
        if self.questKey then
            UI:ToggleQuestDetails(self.questKey, row)
        end
    end)
    row.info:HookScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Show quest objective", 1, 0.82, 0)
            GameTooltip:Show()
        end
    end)
    row.info:HookScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.add, "RIGHT", 7, 0)
    row.label:SetPoint("RIGHT", row.info, "LEFT", -5, 0)
    row.label:SetJustifyH("LEFT")
    row:SetScript("OnMouseUp", function(self)
        if self.groupId then
            UI:ToggleCatalogGroup(self.groupId)
        end
    end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.16, 0.20, 1)
        self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.8)
    end)
    row:SetScript("OnLeave", function(self)
        UI:Refresh()
    end)
    return row
end

function UI:HideQuestDetails()
    if self.detailPopup then
        self.detailPopup.questKey = nil
        self.detailPopup:Hide()
    end
end

function UI:ToggleQuestDetails(key, owner)
    if not self.detailPopup or not key then
        return
    end
    if self.detailPopup:IsShown() and self.detailPopup.questKey == key then
        self:HideQuestDetails()
        return
    end

    local quest = Addon.db and Addon.db.knownQuests[key]
    if not quest then
        return
    end

    local classification = Core.ClassifyCatalogZone(quest)
    local objective = tostring(quest.objectiveText or "")
    if objective == "" then
        objective = "No objective text has been learned yet. Open the Callboard when this quest is offered to refresh its details."
    end

    self.detailPopup.questKey = key
    self.detailPopup.title:SetText(Core.QuestTitle(quest))
    local typeName = Core.QuestTypeName and Core.QuestTypeName(quest.questType) or "Other"
    local verification = (tonumber(quest.seen) or 0) > 0
        and ("|cff55cc77Verified " .. tostring(quest.seen) .. "x|r")
        or "|cff888888Unverified|r"
    local remaining = Addon.profile.ignoreOrder == true and 0 or Core.RepeatLockRemaining(Addon.profile and Addon.profile.recentCompletedQuests, key)
    local availability = remaining > 0
        and (" • |cffff6666Cooldown: " .. tostring(remaining) .. " quest" .. (remaining == 1 and "" or "s") .. " remaining|r")
        or " • |cff55cc77Available|r"
    self.detailPopup.meta:SetText(typeName .. " • " .. classification.label .. " • " .. verification .. availability
        .. (quest.questId and "  |cff888888Quest #" .. tostring(quest.questId) .. "|r" or ""))
    self.detailPopup.objective:SetText(objective)
    self.detailPopup.add.questKey = key
    if Core.RouteContains(Addon.profile and Addon.profile.route, key) then
        setButtonText(self.detailPopup.add, "Already Added")
        self.detailPopup.add:SetButtonEnabled(false)
    else
        setButtonText(self.detailPopup.add, "Add to Route")
        self.detailPopup.add:SetButtonEnabled(true)
    end

    local textHeight = math.max(34, self.detailPopup.objective:GetStringHeight() or 34)
    self.detailPopup:SetHeight(math.min(170, 82 + textHeight))
    self.detailPopup:ClearAllPoints()
    self.detailPopup:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    self.detailPopup:Show()
    self.detailPopup:Raise()
end

function UI:ToggleCatalogGroup(groupId)
    if not Addon.profile or type(groupId) ~= "string" then
        return
    end
    self:HideQuestDetails()
    Addon.profile.catalogCollapsed = Addon.profile.catalogCollapsed or {}
    if Addon.profile.catalogCollapsed[groupId] then
        Addon.profile.catalogCollapsed[groupId] = nil
    else
        Addon.profile.catalogCollapsed[groupId] = true
    end
    self:Refresh()
end

function UI:SetAllCatalogGroupsCollapsed(collapsed)
    if not Addon.profile then
        return
    end
    self:HideQuestDetails()
    Addon.profile.catalogCollapsed = {}
    if collapsed then
        local ids = Core.CatalogGroupIDs(Addon.db, self.searchText)
        for i = 1, table.getn(ids) do
            Addon.profile.catalogCollapsed[ids[i]] = true
        end
    end
    self.catalogOffset = 0
    self:Refresh()
end

function UI:SavePosition()
    if not self.frame or not Addon.profile then
        return
    end
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    Addon.profile.window.point = point or "CENTER"
    Addon.profile.window.relativePoint = relativePoint or point or "CENTER"
    Addon.profile.window.x = x or 0
    Addon.profile.window.y = y or 0
end

function UI:UpdateSummonCooldown()
    if (not self.summon and not self.miniSummon) or not Addon.PE or not Addon.PE.GetSummonCooldownRemaining then
        return
    end
    local boardVisible = Addon.PE.IsBoardVisible and Addon.PE.IsBoardVisible() or false
    -- Nearby-board detection may call TargetByName on Ebonhold. Never poll it
    -- just because a Zen window is visible; only probe during an active
    -- board-open flow. The click/open path performs its own explicit scan.
    local probeNearby = Addon.pendingBoardOpen ~= nil
    local nearbyBoard = probeNearby and Addon.PE.IsCallboardNearby and Addon.PE.IsCallboardNearby() or false
    local canSummon = Addon.PE.IsSummonSpellKnown and Addon.PE.IsSummonSpellKnown() or true
    local remaining = Addon.PE.GetSummonCooldownRemaining()
    local seconds = remaining > 0 and math.max(1, math.ceil(remaining)) or 0
    local stateKey = tostring(seconds) .. ":" .. tostring(boardVisible) .. ":" .. tostring(nearbyBoard) .. ":" .. tostring(canSummon)
    if self.lastSummonCooldownState == stateKey then
        return
    end
    self.lastSummonCooldownState = stateKey
    local label
    if boardVisible then
        label = "Board Open"
    elseif nearbyBoard then
        label = "Open Board"
    elseif not canSummon then
        label = "Open City Board"
    else
        label = seconds > 0 and ("Callboard " .. tostring(seconds) .. "s") or "Summon Board"
    end
    if self.summon then
        setButtonText(self.summon, label)
    end
    if self.miniSummon then
        setButtonText(self.miniSummon, label)
    end
end

function UI:UpdateStartAction(forceNearbyScan)
    if not self.start or not Addon.PE or not Addon.PE.IsBoardVisible then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local boardVisible = Addon.PE.IsBoardVisible()
    -- Avoid continuous TargetByName scans from the HUD. Nearby probing is
    -- allowed only when explicitly forced (hover/click) or while opening a board.
    local probeNearby = forceNearbyScan == true or Addon.pendingBoardOpen ~= nil
    local nearbyBoard = probeNearby and Addon.PE.IsCallboardNearby
        and Addon.PE.IsCallboardNearby(forceNearbyScan == true) or false
    local canSummon = Addon.PE.IsSummonSpellKnown and Addon.PE.IsSummonSpellKnown() or true
    local summonCooldown = Addon.PE.GetSummonCooldownRemaining and Addon.PE.GetSummonCooldownRemaining() or 0
    local macroText = (not boardVisible and not nearbyBoard and canSummon
        and summonCooldown <= 0 and Addon.pendingBoardOpen == nil) and "/cast Summon Callboard" or ""
    if self.boardActionMacro == macroText then
        return
    end
    self.boardActionMacro = macroText
    -- Start Route is intentionally non-secure in the 1.0.9 diagnostic build.
    -- Summon/open controls retain their secure macro attributes.
    if self.summon then
        self.summon:SetAttribute("macrotext", macroText)
    end
    if self.miniSummon then
        self.miniSummon:SetAttribute("macrotext", macroText)
    end
end

local function scaleFrameAroundTopRight(frame, newScale)
    if not frame or not newScale then
        return
    end

    local oldScale = frame:GetScale() or 1
    if oldScale <= 0 then
        oldScale = 1
    end

    -- Preserve the top-right screen position while changing scale.
    local right = frame:GetRight()
    local top = frame:GetTop()
    if not right or not top then
        frame:SetScale(newScale)
        return
    end

    local parentScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local frameScale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or oldScale
    local screenRight = right * frameScale / parentScale
    local screenTop = top * frameScale / parentScale

    frame:SetScale(newScale)
    frame:ClearAllPoints()

    local newEffective = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or newScale
    local x = screenRight * parentScale / newEffective
    local y = screenTop * parentScale / newEffective
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
end

function UI:SaveLauncherLayout()
    if not self.launcher or not Addon.profile then return end
    Addon.profile.launcher = Addon.profile.launcher or {}
    local point, _, relativePoint, x, y = self.launcher:GetPoint(1)
    Addon.profile.launcher.point = point or "CENTER"
    Addon.profile.launcher.relativePoint = relativePoint or point or "CENTER"
    Addon.profile.launcher.x = x or 0
    Addon.profile.launcher.y = y or 0
end

function UI:RefreshLauncher()
    if not self.launcher or not Addon.profile then return end
    local settings = Addon.profile.launcher or {}
    if settings.shown == false then
        self.launcher:Hide()
        return
    end
    self.launcher:Show()
    self.launcher:SetAlpha(math.max(0.10, math.min(1.00, tonumber(settings.opacity) or 0.65)))
end

function UI:SaveMiniLayout()
    if not self.miniFrame or not Addon.profile then
        return
    end
    local point, _, relativePoint, x, y = self.miniFrame:GetPoint(1)
    Addon.profile.miniWindow.point = point or "CENTER"
    Addon.profile.miniWindow.relativePoint = relativePoint or point or "CENTER"
    Addon.profile.miniWindow.x = x or 0
    Addon.profile.miniWindow.y = y or 0
    Addon.profile.miniWindow.width = self.miniFrame:GetWidth()
    Addon.profile.miniWindow.height = self.miniFrame:GetHeight()
    Addon.profile.miniWindow.scale = self.miniFrame:GetScale()
end

function UI:SaveGroupLayout()
    if not self.groupProgressFrame or not Addon.profile then
        return
    end
    Addon.profile.groupWindow = Addon.profile.groupWindow or {}
    local point, _, relativePoint, x, y = self.groupProgressFrame:GetPoint(1)
    Addon.profile.groupWindow.point = point or "CENTER"
    Addon.profile.groupWindow.relativePoint = relativePoint or point or "CENTER"
    Addon.profile.groupWindow.x = x or 0
    Addon.profile.groupWindow.y = y or 0
    Addon.profile.groupWindow.width = self.groupProgressFrame:GetWidth()
    Addon.profile.groupWindow.height = self.groupProgressFrame:GetHeight()
    Addon.profile.groupWindow.scale = self.groupProgressFrame:GetScale()
end

function UI:RefreshMini()
    if not self.miniFrame or not Addon.profile or not Addon.db then
        return
    end
    local route = Addon.profile.route or {}
    local currentIndex = Addon.profile.currentStep or 1
    local routeCount = table.getn(route)
    local wantedCount = math.max(1, math.min(20, Addon.profile.miniQuestCount or 5))
    local shownCount = math.min(wantedCount, routeCount)
    local lines = {}

    if currentIndex > routeCount or routeCount == 0 then
        table.insert(lines, "|cffaaaaaaRoute complete|r")
        shownCount = 1
    else
        for offset = 0, shownCount - 1 do
            local routeIndex = currentIndex + offset
            if routeIndex > routeCount then
                if Addon.profile.autoLoop then
                    routeIndex = routeIndex - routeCount
                else
                    break
                end
            end

            local key = route[routeIndex]
            local quest = key and Addon.db.knownQuests[key]
            local title = quest and Core.QuestTitle(quest) or tostring(key or "Unknown quest")
            local cooldownRemaining = (Addon.profile.ignoreOrder ~= true and key) and Core.RepeatLockRemaining(Addon.profile.recentCompletedQuests, key) or 0
            local cooldownSuffix = cooldownRemaining > 0
                and (" |cffff6666[CD " .. tostring(cooldownRemaining) .. "]|r")
                or ""
            if offset == 0 then
                table.insert(lines, "|cffffcc00> " .. tostring(routeIndex) .. ". " .. title .. "|r" .. cooldownSuffix)
            else
                table.insert(lines, "  " .. tostring(routeIndex) .. ". |cffffffff" .. title .. "|r" .. cooldownSuffix)
            end
        end
        shownCount = table.getn(lines)
    end

    self.miniFrame.title:SetText(Addon.profile.activeRouteName
        and ("ZenCallboard — " .. Addon.profile.activeRouteName)
        or "ZenCallboard Route")
    self.miniCurrent:SetText(table.concat(lines, "\n"))
    self.miniStatus:SetText(Addon.statusMessage or "")
    if self.miniStats then
        local function moneyText(v)
            v = math.max(0, math.floor(tonumber(v) or 0))
            if GetCoinTextureString and v > 0 then return GetCoinTextureString(v) end
            return v > 0 and (tostring(v) .. "c") or "0c"
        end
        self.miniStats:SetText("Current spend: " .. moneyText(Addon.sessionCost or 0))
    end
    local miniStatusColor = getStatusColor(Addon.statusMessage)
    self.miniStatus:SetTextColor(miniStatusColor[1], miniStatusColor[2], miniStatusColor[3])

    if self.miniStart then
        if Addon.running then
            setButtonText(self.miniStart, "Running")
            self.miniStart:SetButtonEnabled(false)
        else
            setButtonText(self.miniStart, "Start")
            self.miniStart:SetButtonEnabled(true)
        end
    end

    local minimumHeight = 142 + (shownCount * 15)
    if self.miniFrame.SetMinResize then
        self.miniFrame:SetMinResize(360, math.max(172, minimumHeight))
    end
    if self.miniFrame:GetWidth() < 360 then
        self.miniFrame:SetWidth(360)
    end
    if self.miniFrame:GetHeight() < minimumHeight then
        self.miniFrame:SetHeight(minimumHeight)
        self:SaveMiniLayout()
    end
    self:UpdateSummonCooldown()
    self:RefreshGroupProgress()
end

function UI:RefreshGroupProgress()
    if not self.miniGroup or not self.groupProgressFrame or not Addon.profile then
        return
    end
    if Addon.profile.showGroupProgress ~= true then
        setButtonText(self.miniGroup, "Group Off")
        self.groupProgressFrame.subtitle:SetText("Callboard group sync is disabled in Settings.")
        self.groupProgressText:SetText("|cffaaaaaaNo route sync or progress messages will be exchanged.|r")
        if self.groupRefresh then
            self.groupRefresh:SetButtonEnabled(false)
        end
        if self.groupLink then
            self.groupLink:SetButtonEnabled(false)
        end
        if self.groupTargetLink then
            self.groupTargetLink:SetButtonEnabled(false)
        end
        return
    end

    local group = Addon.Group
    if self.groupRefresh then
        self.groupRefresh:SetButtonEnabled(true)
    end
    if self.groupLink then
        self.groupLink:SetButtonEnabled(true)
        local linked, available = group and group.GetCurrentLinkCounts and group:GetCurrentLinkCounts() or 0, 0
        if group and group.GetCurrentLinkCounts then
            linked, available = group:GetCurrentLinkCounts()
        end
        setButtonText(self.groupLink, (available > 0 and linked >= available) and "Unlink Group" or "Link Group")
    end
    if self.groupTargetLink then
        self.groupTargetLink:SetButtonEnabled(true)
        local targetName = UnitName and UnitName("target") or nil
        if targetName and group and group.IsNameInCurrentGroup then
            local inGroup, rosterName = group:IsNameInCurrentGroup(targetName)
            if inGroup then
                setButtonText(self.groupTargetLink, group:IsLinkedName(rosterName) and "Unlink Target" or "Link Target")
            else
                setButtonText(self.groupTargetLink, "Link Target")
            end
        else
            setButtonText(self.groupTargetLink, "Link Target")
        end
    end
    local display = group and group.GetDisplay and group:GetDisplay() or nil
    if not display then
        setButtonText(self.miniGroup, "Group")
        return
    end

    if display.grouped then
        setButtonText(self.miniGroup, "Group " .. tostring(display.completeCount) .. "/" .. tostring(display.memberCount))
    else
        setButtonText(self.miniGroup, "Group")
    end
    local syncText = display.title
    if display.grouped then
        if display.routeMismatch then
            syncText = display.title .. "  |cffff5555[DIFFERENT ROUTES]|r"
        elseif display.stepMismatch then
            syncText = display.title .. "  |cffffcc00[STEP SYNC NEEDED]|r"
        elseif display.unknownRouteState then
            syncText = display.title .. "  |cffaaaaaa[WAITING FOR GROUP DATA]|r"
        elseif display.routeReady then
            syncText = display.title .. "  |cff55ff55[GROUP SYNCED]|r"
        end
    end
    self.groupProgressFrame.subtitle:SetText(syncText)

    local lines = {}
    if display.grouped then
        table.insert(lines, "|cff888888Only linked members participate in Callboard route sync.|r")
        table.insert(lines, "")
    end
    if not display.grouped then
        table.insert(lines, "|cffaaaaaaYou are not currently in a group.|r")
    else
        for index = 1, table.getn(display.rows or {}) do
            local row = display.rows[index]
            local color = "|cffffffff"
            if row.color == "complete" then
                color = "|cff55ff55"
            elseif row.color == "missing" then
                color = "|cffffaa55"
            elseif row.color == "unknown" then
                color = "|cff888888"
            elseif row.color == "warning" then
                color = "|cffffcc00"
            end
            table.insert(lines, color .. tostring(row.name) .. "|r  —  " .. tostring(row.status))
        end
        if display.routeMismatch then
            table.insert(lines, "")
            table.insert(lines, "|cffff5555Group route mismatch: all ZenCallboard users must load the same ordered route before Start Route is allowed.|r")
        elseif display.stepMismatch then
            table.insert(lines, "")
            table.insert(lines, "|cffffcc00Group step mismatch: Refresh / Sync will align matching routes to the furthest current step.|r")
        elseif display.unknownRouteState then
            table.insert(lines, "")
            table.insert(lines, "|cffaaaaaaWaiting for fresh route state from one or more members. Press Refresh / Sync.|r")
        end

        if (display.outOfRangeCount or 0) > 0 then
            table.insert(lines, "")
            table.insert(lines, "|cffffcc00Warning: " .. tostring(display.outOfRangeCount) .. " group member(s) are out of range; their quest state may be stale. Move nearby and press Refresh / Sync.|r")
        elseif display.addonCount < display.memberCount then
            table.insert(lines, "")
            table.insert(lines, "|cff888888Missing/stale data can be refreshed with Refresh / Sync.|r")
        end
    end

    self.groupProgressText:SetText(table.concat(lines, "\n"))
    local contentHeight = math.max(160, (table.getn(lines) * 16) + 8)
    self.groupProgressChild:SetHeight(contentHeight)
end

function UI:ToggleGroupProgress()
    if not self.groupProgressFrame then
        return
    end
    if self.groupProgressFrame:IsShown() then
        self.groupProgressFrame:Hide()
    else
        self:RefreshGroupProgress()
        self.groupProgressFrame:Show()
        self.groupProgressFrame:Raise()
    end
end

function UI:ShowMini()
    if not self.miniFrame then
        return
    end
    self.frame:Hide()
    self.miniFrame:Show()
    self:RefreshMini()
end

function UI:ShowMain()
    if self.miniFrame then
        self.miniFrame:Hide()
    end
    if self.groupProgressFrame then
        self.groupProgressFrame:Hide()
    end
    self.frame:Show()
    self.frame:Raise()
    self:Refresh()
end

function UI:RefreshSettings()
    if not self.settingsFrame or not Addon.profile then
        return
    end
    self.settingsAutoLoop:SetChecked(Addon.profile.autoLoop == true)
    self.settingsIgnoreOrder:SetChecked(Addon.profile.ignoreOrder == true)
    self.settingsAutoAccept:SetChecked(Addon.profile.autoAccept == true)
    self.settingsAutoShare:SetChecked(Addon.profile.autoShare == true)
    self.settingsGroupProgress:SetChecked(Addon.profile.showGroupProgress == true)
    local launcher = Addon.profile.launcher or {}
    self.settingsLauncherShown:SetChecked(launcher.shown ~= false)
    self.settingsLauncherLocked:SetChecked(launcher.locked == true)
    self.settingsLauncherOpacity:SetText(tostring(math.floor(((launcher.opacity or 0.65) * 100) + 0.5)))
    self.settingsMaxRerolls:SetText(tostring(Addon.profile.maxRerolls or 25))
    self.settingsRerollDelay:SetText(tostring(Addon.profile.rerollDelay or 1.6))
    self.settingsMiniQuestCount:SetText(tostring(Addon.profile.miniQuestCount or 5))
    if self.settingsAutoOpenSummoned then
        self.settingsAutoOpenSummoned:SetChecked(Addon.profile.autoOpenSummonedBoard == true)
    end
    if self.settingsHideCallboard then
        self.settingsHideCallboard:SetChecked(Addon.profile.hideCallboardWhileRunning == true)
    end
    if self.settingsSummonHotkey and self.settingsSummonHotkey.label and GetBindingKey then
        local key = GetBindingKey("SPELL Summon Callboard")
        self.settingsSummonHotkey.label:SetText(key or "Not bound")
    end
    if self.settingsFrame.goldStats then
        local stats = Addon.profile.goldStats or {}
        local total = math.max(0, math.floor(tonumber(stats.totalSpent) or 0))
        local last = math.max(0, math.floor(tonumber(stats.lastSearchSpent) or 0))
        local totalText = GetCoinTextureString and total > 0 and GetCoinTextureString(total) or (total > 0 and (tostring(total) .. "c") or "0c")
        local lastText = GetCoinTextureString and last > 0 and GetCoinTextureString(last) or (last > 0 and (tostring(last) .. "c") or "0c")
        self.settingsFrame.goldStats:SetText("Reroll stats: " .. tostring(stats.rerolls or 0) .. " total rolls • " .. totalText
            .. " total spent • last search " .. tostring(stats.lastSearchRerolls or 0) .. " rolls / " .. lastText)
    end
end

function UI:ToggleSettings()
    if not self.settingsFrame then
        return
    end
    self:HideQuestDetails()
    if self.routeManager and self.routeManager:IsShown() then
        self.routeManager:Hide()
    end
    if self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    else
        self:RefreshSettings()
        self.settingsFrame:Show()
        self.settingsFrame:Raise()
    end
end

local function sortedSavedRouteNames()
    local names = {}
    local savedRoutes = Addon.profile and Addon.profile.savedRoutes or {}
    for name in pairs(savedRoutes) do
        table.insert(names, name)
    end
    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)
    return names
end

function UI:UpdateRouteSaveButton()
    if not self.routeManagerSave or not self.routeManagerName then
        return
    end
    local name = self.routeManagerName:GetText() or ""
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    local exists = Addon.profile and Addon.profile.savedRoutes and Addon.profile.savedRoutes[name]
    setButtonText(self.routeManagerSave, exists and "Overwrite" or "Save Current")
end

function UI:RefreshRouteManager()
    if not self.routeManager or not Addon.profile then
        return
    end
    local names = sortedSavedRouteNames()
    self.savedRouteOffset = clampOffset(self.savedRouteOffset, table.getn(names), 8)

    for visibleIndex = 1, 8 do
        local row = self.savedRouteRows[visibleIndex]
        local name = names[self.savedRouteOffset + visibleIndex]
        if name then
            local saved = Addon.profile.savedRoutes[name]
            local activePrefix = Addon.profile.activeRouteName == name and "|cff66ff66*|r " or ""
            local loopSuffix = saved.autoLoop and "  |cffffcc00[Loop]|r" or ""
            row.load.routeName = name
            row.share.routeName = name
            row.delete.routeName = name
            setButtonText(row.load, activePrefix .. name .. loopSuffix)
            setButtonText(row.delete, self.pendingDeleteName == name and "Confirm" or "Delete")
            row:Show()
        else
            row.load.routeName = nil
            row.share.routeName = nil
            row.delete.routeName = nil
            row:Hide()
        end
    end
    self.routeManagerPage:SetText(tostring(table.getn(names)) .. " saved route(s)")
    self:UpdateRouteSaveButton()
end

function UI:ToggleRouteManager()
    if not self.routeManager then
        return
    end
    self:HideQuestDetails()
    if self.settingsFrame and self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    end
    if self.routeManager:IsShown() then
        self.routeManager:Hide()
    else
        self.pendingDeleteName = nil
        self.routeManagerName:SetText(Addon.profile.activeRouteName or "")
        self:RefreshRouteManager()
        self.routeManager:Show()
        self.routeManager:Raise()
    end
end

function UI:CaptureShiftClickedPlayer(link)
    if not self.routeManagerShareTarget or not IsShiftKeyDown or not IsShiftKeyDown() then
        return
    end
    local linkType, playerName = string.match(tostring(link or ""), "^([^:]+):([^:]+)")
    if linkType ~= "player" or not playerName or playerName == "" then
        return
    end
    self.routeManagerShareTarget:SetText(playerName)
    self.routeManagerShareTarget:HighlightText(0, 0)
end

function UI:InstallChatNameHook()
    if self.chatNameHooked or not hooksecurefunc or type(SetItemRef) ~= "function" then
        return
    end
    self.chatNameHooked = true
    hooksecurefunc("SetItemRef", function(link)
        UI:CaptureShiftClickedPlayer(link)
    end)
end

function UI:Create()
    if self.frame then return self.frame end
    if Style and Style.AttachSettings and Addon.profile then
        Addon.profile.appearance = Addon.profile.appearance or Style.DefaultAppearance()
        Style:AttachSettings(Addon.profile.appearance)
        local function updatePalette()
            local theme = Style:Theme()
            local r,g,b = Style:Accent()
            local function copy(dst,src,alpha)
                dst[1],dst[2],dst[3],dst[4] = src[1],src[2],src[3],alpha or 1
            end
            copy(COLORS.background,theme.background,Style:PanelAlpha())
            copy(COLORS.panel,theme.surface,Style:PanelAlpha())
            copy(COLORS.panelLight,theme.surface,1)
            copy(COLORS.normal,theme.surface,Style:PanelAlpha())
            copy(COLORS.current,theme.surface,1)
            copy(COLORS.selected,theme.surface,1)
            copy(COLORS.border,theme.border,1)
            copy(COLORS.gold,{r,g,b},1)
            copy(COLORS.text,theme.text,1)
            copy(COLORS.muted,theme.muted,1)
        end
        Style:OnAppearanceChanged(function()
            updatePalette()
            if UI.frame then UI:Refresh() end
        end)
        updatePalette()
    end

    local frame = CreateFrame("Frame", "ZenCallboardFrame", UIParent)
    frame:SetWidth(940)
    frame:SetHeight(620)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    setBackdrop(frame, COLORS.background)
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()
    end)
    frame:SetScript("OnShow", function(self)
        self:Raise()
        UI:Refresh()
    end)
    frame:SetScript("OnHide", function()
        UI:HideQuestDetails()
        if UI.settingsFrame then
            UI.settingsFrame:Hide()
        end
        if UI.routeManager then
            UI.routeManager:Hide()
        end
    end)
    frame:Hide()
    self.frame = frame
    if Style and Style.CreateAppearancePanel then
        local appearanceButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        appearanceButton:SetWidth(106)
        appearanceButton:SetHeight(22)
        appearanceButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -7)
        appearanceButton:SetText("Appearance")
        appearanceButton:SetScript("OnClick", function()
            if not UI.zenAppearanceWindow then
                UI.zenAppearanceWindow = Style:CreateAppearancePanel(UIParent)
                UI.zenAppearanceWindow:Hide()
            end
            if UI.zenAppearanceWindow:IsShown() then
                UI.zenAppearanceWindow:Hide()
            else
                UI.zenAppearanceWindow:Show()
                UI.zenAppearanceWindow:Raise()
            end
        end)
        Style:StyleSurface(appearanceButton, "button")
    end

    local window = Addon.profile and Addon.profile.window or {}
    frame:SetPoint(window.point or "CENTER", UIParent, window.relativePoint or "CENTER", window.x or 0, window.y or 0)

    local launcherSettings = Addon.profile.launcher or {}
    self.launcher = CreateFrame("Button", "ZenCallboardFloatingLauncher", UIParent)
    self.launcher:SetWidth(38)
    self.launcher:SetHeight(38)
    self.launcher:SetFrameStrata("MEDIUM")
    self.launcher:SetClampedToScreen(true)
    self.launcher:SetMovable(true)
    self.launcher:EnableMouse(true)
    self.launcher:RegisterForClicks("LeftButtonUp")
    self.launcher:RegisterForDrag("LeftButton")
    self.launcher:SetPoint(launcherSettings.point or "CENTER", UIParent,
        launcherSettings.relativePoint or "CENTER", launcherSettings.x or -360, launcherSettings.y or 0)
    setBackdrop(self.launcher, COLORS.background, COLORS.gold)

    self.launcher.icon = self.launcher:CreateTexture(nil, "ARTWORK")
    self.launcher.icon:SetPoint("TOPLEFT", self.launcher, "TOPLEFT", 3, -3)
    self.launcher.icon:SetPoint("BOTTOMRIGHT", self.launcher, "BOTTOMRIGHT", -3, 3)
    self.launcher.icon:SetTexture("Interface\\AddOns\\ZenCallboard\\Textures\\CallboardIcon")

    self.launcher:SetScript("OnClick", function()
        UI:Toggle()
    end)
    self.launcher:SetScript("OnDragStart", function(self)
        local settings = Addon.profile and Addon.profile.launcher or {}
        if settings.locked ~= true then self:StartMoving() end
    end)
    self.launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveLauncherLayout()
    end)
    self.launcher:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("ZenCallboard")
            GameTooltip:AddLine("Left-click: Open /zencb", 1, 1, 1)
            local settings = Addon.profile and Addon.profile.launcher or {}
            GameTooltip:AddLine(settings.locked and "Position: Locked" or "Drag to move", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    self.launcher:SetScript("OnLeave", function(self)
        local settings = Addon.profile and Addon.profile.launcher or {}
        self:SetAlpha(math.max(0.10, math.min(1.00, tonumber(settings.opacity) or 0.65)))
        if GameTooltip then GameTooltip:Hide() end
    end)
    self:RefreshLauncher()

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    frame.header:SetHeight(60)
    frame.header.texture = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.header.texture:SetAllPoints()
    setTextureColor(frame.header.texture, { 0.055, 0.062, 0.078, 1 })

    frame.title = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame.header, "TOPLEFT", 18, -13)
    frame.title:SetText("ZenCallboard v1.0.116")
    frame.title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    frame.subtitle = frame.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.header, "TOPLEFT", 18, -38)
    frame.subtitle:SetText("Ordered Callboard route builder")
    frame.subtitle:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    frame.close = makeButton(frame.header, "X", 28, 28)
    frame.close:SetPoint("TOPRIGHT", frame.header, "TOPRIGHT", -12, -12)
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.settingsButton = makeButton(frame.header, "Settings", 76, 28)
    frame.settingsButton:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
    frame.settingsButton:SetScript("OnClick", function()
        UI:ToggleSettings()
    end)

    frame.routesButton = makeButton(frame.header, "Routes", 76, 28)
    frame.routesButton:SetPoint("RIGHT", frame.settingsButton, "LEFT", -8, 0)
    frame.routesButton:SetScript("OnClick", function()
        UI:ToggleRouteManager()
    end)

    self.navPanel = CreateFrame("Frame", nil, frame)
    self.navPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -61)
    self.navPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    self.navPanel:SetWidth(152)
    setBackdrop(self.navPanel, { 0.045, 0.052, 0.066, 1 }, { 0.10, 0.11, 0.14, 1 })

    self.routePanel = makePanel(frame, "Quest route", 356, 514)
    self.routePanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -61)
    self.routePanel:EnableMouseWheel(true)
    self.routePanel:SetScript("OnMouseWheel", function(_, delta)
        local count = Addon.profile and table.getn(Addon.profile.route) or 0
        UI.routeOffset = clampOffset(UI.routeOffset - delta, count, 13)
        UI:Refresh()
    end)

    self.catalogPanel = makePanel(frame, "Learned Callboard quests", 430, 514)
    self.catalogPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 153, -61)
    self.catalogPanel:EnableMouseWheel(true)
    self.catalogPanel:SetScript("OnMouseWheel", function(_, delta)
        local count = table.getn(UI.catalog or {})
        UI.catalogOffset = clampOffset(UI.catalogOffset - delta, count, 12)
        UI:Refresh()
    end)

    self.searchHolder, self.search = makeInput(self.catalogPanel, 398, 30, 80)
    self.searchHolder:SetPoint("TOPLEFT", self.catalogPanel, "TOPLEFT", 16, -31)
    self.search:SetScript("OnTextChanged", function(self)
        UI:HideQuestDetails()
        UI.searchText = self:GetText() or ""
        UI.catalogOffset = 0
        UI:Refresh()
    end)

    for i = 1, 13 do
        local row = createRouteRow(self.routePanel, i)
        row:SetPoint("TOP", self.routePanel, "TOP", 0, -32 - ((i - 1) * 29))
        self.routeRows[i] = row
    end

    for i = 1, 12 do
        local row = createCatalogRow(self.catalogPanel, i)
        row:SetPoint("TOP", self.catalogPanel, "TOP", 0, -63 - ((i - 1) * 29))
        self.catalogRows[i] = row
    end

    self.routeEmpty = self.routePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.routeEmpty:SetPoint("CENTER", self.routePanel, "CENTER", 0, 8)
    self.routeEmpty:SetWidth(300)
    self.routeEmpty:SetText("No route steps yet.\n\nAdd quests from the catalogue to begin.")
    self.routeEmpty:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    self.routeEmpty:SetJustifyH("CENTER")

    self.catalogEmpty = self.catalogPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.catalogEmpty:SetPoint("CENTER", self.catalogPanel, "CENTER", 0, 8)
    self.catalogEmpty:SetWidth(340)
    self.catalogEmpty:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    self.catalogEmpty:SetJustifyH("CENTER")

    self.detailPopup = CreateFrame("Frame", "ZenCallboardQuestDetailPopup", frame)
    self.detailPopup:SetWidth(390)
    self.detailPopup:SetHeight(125)
    self.detailPopup:SetFrameStrata("TOOLTIP")
    self.detailPopup:SetClampedToScreen(true)
    setBackdrop(self.detailPopup, COLORS.background, COLORS.gold)
    self.detailPopup.headerTexture = addHeaderBand(self.detailPopup, 30)
    self.detailPopup:EnableMouse(true)

    self.detailPopup.title = self.detailPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.detailPopup.title:SetPoint("TOPLEFT", self.detailPopup, "TOPLEFT", 12, -10)
    self.detailPopup.title:SetPoint("RIGHT", self.detailPopup, "RIGHT", -38, 0)
    self.detailPopup.title:SetJustifyH("LEFT")
    self.detailPopup.title:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])

    self.detailPopup.meta = self.detailPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailPopup.meta:SetPoint("TOPLEFT", self.detailPopup.title, "BOTTOMLEFT", 0, -5)
    self.detailPopup.meta:SetPoint("RIGHT", self.detailPopup, "RIGHT", -12, 0)
    self.detailPopup.meta:SetJustifyH("LEFT")
    self.detailPopup.meta:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.detailPopup.objective = self.detailPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailPopup.objective:SetPoint("TOPLEFT", self.detailPopup.meta, "BOTTOMLEFT", 0, -8)
    self.detailPopup.objective:SetPoint("RIGHT", self.detailPopup, "RIGHT", -12, 0)
    self.detailPopup.objective:SetJustifyH("LEFT")
    self.detailPopup.objective:SetJustifyV("TOP")

    self.detailPopup.close = makeButton(self.detailPopup, "X", 24, 21)
    self.detailPopup.close:SetPoint("TOPRIGHT", self.detailPopup, "TOPRIGHT", -6, -6)
    self.detailPopup.close:SetScript("OnClick", function()
        UI:HideQuestDetails()
    end)

    self.detailPopup.add = makeButton(self.detailPopup, "Add to Route", 94, 23)
    self.detailPopup.add.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    self.detailPopup.add:SetPoint("BOTTOMRIGHT", self.detailPopup, "BOTTOMRIGHT", -9, 8)
    self.detailPopup.add:SetScript("OnClick", function(self)
        if self.questKey then
            Addon:AddRouteQuest(self.questKey)
            UI:HideQuestDetails()
        end
    end)
    self.detailPopup:Hide()

    self.settingsFrame = CreateFrame("Frame", "ZenCallboardSettingsFrame", frame)
    self.settingsFrame:SetWidth(520)
    self.settingsFrame:SetHeight(690)
    self.settingsFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
    self.settingsFrame:SetFrameStrata("TOOLTIP")
    self.settingsFrame:SetClampedToScreen(true)
    setBackdrop(self.settingsFrame, COLORS.background, COLORS.gold)
    self.settingsFrame.headerTexture = addHeaderBand(self.settingsFrame, 46)
    self.settingsFrame:EnableMouse(true)

    self.settingsFrame.title = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.settingsFrame.title:SetPoint("TOPLEFT", self.settingsFrame, "TOPLEFT", 16, -15)
    self.settingsFrame.title:SetText("ZenCallboard Settings")
    self.settingsFrame.title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.settingsFrame.close = makeButton(self.settingsFrame, "X", 26, 22)
    self.settingsFrame.close:SetPoint("TOPRIGHT", self.settingsFrame, "TOPRIGHT", -9, -9)
    self.settingsFrame.close:SetScript("OnClick", function()
        UI.settingsFrame:Hide()
    end)

    self.settingsAutoLoop = makeCheckbox(self.settingsFrame, "Automatically loop to step 1 when the route finishes")
    self.settingsAutoLoop:SetPoint("TOPLEFT", self.settingsFrame, "TOPLEFT", 18, -57)
    self.settingsAutoLoop.label:SetWidth(450)
    self.settingsAutoLoop.label:SetJustifyH("LEFT")

    self.settingsIgnoreOrder = makeCheckbox(self.settingsFrame, "Ignore route order — accept the first visible route quest")
    self.settingsIgnoreOrder:SetPoint("TOPLEFT", self.settingsAutoLoop, "BOTTOMLEFT", 0, -14)
    self.settingsIgnoreOrder.label:SetWidth(450)
    self.settingsIgnoreOrder.label:SetJustifyH("LEFT")

    self.settingsAutoAccept = makeCheckbox(self.settingsFrame, "Automatically select and accept the matching Callboard quest")
    self.settingsAutoAccept:SetPoint("TOPLEFT", self.settingsIgnoreOrder, "BOTTOMLEFT", 0, -10)
    self.settingsAutoAccept.label:SetWidth(450)
    self.settingsAutoAccept.label:SetJustifyH("LEFT")

    self.settingsAutoShare = makeCheckbox(self.settingsFrame, "Automatically share each accepted route quest with the group")
    self.settingsAutoShare:SetPoint("TOPLEFT", self.settingsAutoAccept, "BOTTOMLEFT", 0, -10)
    self.settingsAutoShare.label:SetWidth(450)
    self.settingsAutoShare.label:SetJustifyH("LEFT")

    self.settingsGroupProgress = makeCheckbox(self.settingsFrame, "Enable route/group sync with other ZenCallboard users")
    self.settingsGroupProgress:SetPoint("TOPLEFT", self.settingsAutoShare, "BOTTOMLEFT", 0, -10)
    self.settingsGroupProgress.label:SetWidth(450)
    self.settingsGroupProgress.label:SetJustifyH("LEFT")

    self.settingsLauncherShown = makeCheckbox(self.settingsFrame, "Show floating ZenCallboard launcher")
    self.settingsLauncherShown:SetPoint("TOPLEFT", self.settingsGroupProgress, "BOTTOMLEFT", 0, -12)
    self.settingsLauncherShown.label:SetWidth(450)
    self.settingsLauncherShown.label:SetJustifyH("LEFT")

    self.settingsLauncherLocked = makeCheckbox(self.settingsFrame, "Lock floating launcher position")
    self.settingsLauncherLocked:SetPoint("TOPLEFT", self.settingsLauncherShown, "BOTTOMLEFT", 0, -10)
    self.settingsLauncherLocked.label:SetWidth(450)
    self.settingsLauncherLocked.label:SetJustifyH("LEFT")

    self.settingsLauncherOpacityLabel = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.settingsLauncherOpacityLabel:SetPoint("TOPLEFT", self.settingsLauncherLocked, "BOTTOMLEFT", 2, -18)
    self.settingsLauncherOpacityLabel:SetWidth(340)
    self.settingsLauncherOpacityLabel:SetJustifyH("LEFT")
    self.settingsLauncherOpacityLabel:SetText("Floating launcher opacity (10-100%)")
    self.settingsLauncherOpacityLabel:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.settingsLauncherOpacityHolder, self.settingsLauncherOpacity = makeInput(self.settingsFrame, 70, 24, 3)
    self.settingsLauncherOpacity:SetNumeric(true)
    self.settingsLauncherOpacityHolder:SetPoint("LEFT", self.settingsLauncherOpacityLabel, "RIGHT", 14, 0)

    self.settingsMaxLabel = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.settingsMaxLabel:SetPoint("TOPLEFT", self.settingsLauncherOpacityLabel, "BOTTOMLEFT", 0, -26)
    self.settingsMaxLabel:SetWidth(340)
    self.settingsMaxLabel:SetJustifyH("LEFT")
    self.settingsMaxLabel:SetText("Hard reroll safety cap per search")
    self.settingsMaxLabel:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.settingsMaxHolder, self.settingsMaxRerolls = makeInput(self.settingsFrame, 70, 24, 3)
    self.settingsMaxRerolls:SetNumeric(true)
    self.settingsMaxHolder:SetPoint("LEFT", self.settingsMaxLabel, "RIGHT", 14, 0)

    self.settingsDelayLabel = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.settingsDelayLabel:SetPoint("TOPLEFT", self.settingsMaxLabel, "BOTTOMLEFT", 0, -26)
    self.settingsDelayLabel:SetWidth(340)
    self.settingsDelayLabel:SetJustifyH("LEFT")
    self.settingsDelayLabel:SetText("Reroll response delay (seconds)")
    self.settingsDelayLabel:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.settingsDelayHolder, self.settingsRerollDelay = makeInput(self.settingsFrame, 70, 24, 5)
    self.settingsDelayHolder:SetPoint("LEFT", self.settingsDelayLabel, "RIGHT", 14, 0)

    self.settingsMiniCountLabel = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.settingsMiniCountLabel:SetPoint("TOPLEFT", self.settingsDelayLabel, "BOTTOMLEFT", 0, -26)
    self.settingsMiniCountLabel:SetWidth(340)
    self.settingsMiniCountLabel:SetJustifyH("LEFT")
    self.settingsMiniCountLabel:SetText("Quests shown in mini window (1-20)")
    self.settingsMiniCountLabel:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.settingsMiniHolder, self.settingsMiniQuestCount = makeInput(self.settingsFrame, 70, 24, 2)
    self.settingsMiniQuestCount:SetNumeric(true)
    self.settingsMiniHolder:SetPoint("LEFT", self.settingsMiniCountLabel, "RIGHT", 14, 0)

    self.settingsAutoOpenSummoned = makeCheckbox(self.settingsFrame, "Automatically open the Callboard after summoning")
    self.settingsAutoOpenSummoned:SetPoint("TOPLEFT", self.settingsMiniCountLabel, "BOTTOMLEFT", -4, -18)

    self.settingsHideCallboard = makeCheckbox(self.settingsFrame, "Keep Callboard window hidden while searching")
    self.settingsHideCallboard:SetPoint("TOPLEFT", self.settingsAutoOpenSummoned, "BOTTOMLEFT", 0, -8)

    self.settingsSummonHotkeyLabel = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.settingsSummonHotkeyLabel:SetPoint("TOPLEFT", self.settingsHideCallboard, "BOTTOMLEFT", 4, -18)
    self.settingsSummonHotkeyLabel:SetText("Summon Callboard hotkey")
    self.settingsSummonHotkeyLabel:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.settingsSummonHotkey = makeButton(self.settingsFrame, "Not bound", 135, 25)
    self.settingsSummonHotkey:SetPoint("LEFT", self.settingsSummonHotkeyLabel, "LEFT", 250, 0)
    self.settingsSummonHotkey.capturing = false

    self.settingsClearHotkey = makeButton(self.settingsFrame, "Clear", 60, 25)
    self.settingsClearHotkey:SetPoint("LEFT", self.settingsSummonHotkey, "RIGHT", 6, 0)

    local function refreshSummonBindingText()
        local key = GetBindingKey and GetBindingKey("SPELL Summon Callboard")
        UI.settingsSummonHotkey.label:SetText(key or "Not bound")
    end

    local function stopSummonKeyCapture()
        UI.settingsSummonHotkey.capturing = false
        UI.settingsSummonHotkey:EnableKeyboard(false)
        refreshSummonBindingText()
    end

    self.settingsSummonHotkey:SetScript("OnClick", function(button)
        if InCombatLockdown and InCombatLockdown() then
            Addon:SetStatus("The Summon Callboard hotkey cannot be changed during combat.", true)
            return
        end
        button.capturing = true
        button:EnableKeyboard(true)
        button:SetPropagateKeyboardInput(false)
        button.label:SetText("Press a key...")
    end)
    self.settingsSummonHotkey:SetScript("OnKeyDown", function(button, key)
        if not button.capturing then return end
        if key == "ESCAPE" then
            stopSummonKeyCapture()
            return
        end
        if key == "BACKSPACE" or key == "DELETE" then
            local old1, old2 = GetBindingKey("SPELL Summon Callboard")
            if old1 then SetBinding(old1) end
            if old2 then SetBinding(old2) end
            SaveBindings(GetCurrentBindingSet())
            stopSummonKeyCapture()
            return
        end
        local modifier = ""
        if IsControlKeyDown() then modifier = modifier .. "CTRL-" end
        if IsAltKeyDown() then modifier = modifier .. "ALT-" end
        if IsShiftKeyDown() then modifier = modifier .. "SHIFT-" end
        if key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT"
            or key == "LSHIFT" or key == "RSHIFT" or key == "UNKNOWN" then
            return
        end
        local bindKey = modifier .. key
        local old1, old2 = GetBindingKey("SPELL Summon Callboard")
        if old1 then SetBinding(old1) end
        if old2 then SetBinding(old2) end
        local ok = SetBindingSpell and SetBindingSpell(bindKey, "Summon Callboard")
        if ok then
            SaveBindings(GetCurrentBindingSet())
            Addon:SetStatus("Summon Callboard hotkey set to " .. bindKey .. ".", true)
        else
            Addon:SetStatus("Could not create the native Summon Callboard spell binding for " .. bindKey .. ".", true)
        end
        stopSummonKeyCapture()
    end)
    self.settingsClearHotkey:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            Addon:SetStatus("The Summon Callboard hotkey cannot be changed during combat.", true)
            return
        end
        local old1, old2 = GetBindingKey("SPELL Summon Callboard")
        if old1 then SetBinding(old1) end
        if old2 then SetBinding(old2) end
        SaveBindings(GetCurrentBindingSet())
        refreshSummonBindingText()
        Addon:SetStatus("Summon Callboard hotkey cleared.", true)
    end)

    self.settingsFrame.note = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.settingsFrame.note:SetPoint("TOPLEFT", self.settingsSummonHotkeyLabel, "BOTTOMLEFT", 0, -20)
    self.settingsFrame.note:SetWidth(480)
    self.settingsFrame.note:SetHeight(52)
    self.settingsFrame.note:SetJustifyH("LEFT")
    self.settingsFrame.note:SetJustifyV("TOP")
    if self.settingsFrame.note.SetWordWrap then
        self.settingsFrame.note:SetWordWrap(true)
    end
    self.settingsFrame.note:SetText("Safety: the reroll cap applies to both route and instance searches. Group sync only talks to other ZenCallboard users; quest auto-share is controlled separately. Auto-loop requires enough spacing to satisfy the Callboard refresh lock.")
    self.settingsFrame.note:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.settingsFrame.goldStats = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.settingsFrame.goldStats:SetPoint("TOPLEFT", self.settingsFrame.note, "BOTTOMLEFT", 0, -12)
    self.settingsFrame.goldStats:SetWidth(480)
    self.settingsFrame.goldStats:SetJustifyH("LEFT")
    self.settingsFrame.goldStats:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.settingsFrame.creditsTitle = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.settingsFrame.creditsTitle:SetPoint("BOTTOMLEFT", self.settingsFrame, "BOTTOMLEFT", 18, 52)
    self.settingsFrame.creditsTitle:SetText("Credits & Inspiration")
    self.settingsFrame.creditsTitle:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])

    self.settingsFrame.credits = self.settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.settingsFrame.credits:SetPoint("TOPLEFT", self.settingsFrame.creditsTitle, "BOTTOMLEFT", 0, -4)
    self.settingsFrame.credits:SetWidth(300)
    self.settingsFrame.credits:SetJustifyH("LEFT")
    self.settingsFrame.credits:SetText("Special thanks to Disarrayed for the original inspiration, ideas, and concepts that helped shape ZenCallboard.")
    self.settingsFrame.credits:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.settingsFrame.save = makeButton(self.settingsFrame, "Save Settings", 112, 27)
    self.settingsFrame.save.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    self.settingsFrame.save:SetPoint("BOTTOMRIGHT", self.settingsFrame, "BOTTOMRIGHT", -14, 12)
    self.settingsFrame.save:SetScript("OnClick", function()
        Addon:ApplySettings(
            UI.settingsAutoLoop:GetChecked(),
            UI.settingsAutoAccept:GetChecked(),
            UI.settingsMaxRerolls:GetText(),
            UI.settingsRerollDelay:GetText(),
            UI.settingsMiniQuestCount:GetText(),
            UI.settingsAutoShare:GetChecked(),
            UI.settingsGroupProgress:GetChecked(),
            UI.settingsIgnoreOrder:GetChecked(),
            UI.settingsLauncherShown:GetChecked(),
            UI.settingsLauncherLocked:GetChecked(),
            UI.settingsLauncherOpacity:GetText(),
            UI.settingsAutoOpenSummoned and UI.settingsAutoOpenSummoned:GetChecked() or false,
            UI.settingsHideCallboard and UI.settingsHideCallboard:GetChecked() or false
        )
    end)
    self.settingsFrame:Hide()

    self.routeManager = CreateFrame("Frame", "ZenCallboardRouteManager", frame)
    self.routeManager:SetWidth(460)
    self.routeManager:SetHeight(465)
    self.routeManager:SetPoint("CENTER", frame, "CENTER", 0, 0)
    self.routeManager:SetFrameStrata("TOOLTIP")
    setBackdrop(self.routeManager, COLORS.background, COLORS.gold)
    self.routeManager.headerTexture = addHeaderBand(self.routeManager, 46)
    self.routeManager:EnableMouse(true)
    self.routeManager:EnableMouseWheel(true)
    self.routeManager:SetScript("OnMouseWheel", function(_, delta)
        local count = table.getn(sortedSavedRouteNames())
        UI.savedRouteOffset = clampOffset(UI.savedRouteOffset - delta, count, 8)
        UI:RefreshRouteManager()
    end)

    self.routeManager.title = self.routeManager:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.routeManager.title:SetPoint("TOPLEFT", self.routeManager, "TOPLEFT", 16, -15)
    self.routeManager.title:SetText("Saved Routes")
    self.routeManager.title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.routeManager.close = makeButton(self.routeManager, "X", 26, 22)
    self.routeManager.close:SetPoint("TOPRIGHT", self.routeManager, "TOPRIGHT", -9, -9)
    self.routeManager.close:SetScript("OnClick", function()
        UI.routeManager:Hide()
    end)

    self.routeManager.nameLabel = self.routeManager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.routeManager.nameLabel:SetPoint("TOPLEFT", self.routeManager, "TOPLEFT", 16, -50)
    self.routeManager.nameLabel:SetText("Route name")
    self.routeManager.nameLabel:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.routeManagerNameHolder, self.routeManagerName = makeInput(self.routeManager, 312, 24, 60)
    self.routeManagerNameHolder:SetPoint("TOPLEFT", self.routeManager, "TOPLEFT", 16, -66)
    self.routeManagerName:SetScript("OnTextChanged", function()
        UI:UpdateRouteSaveButton()
    end)
    self.routeManagerName:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    self.routeManagerName:SetScript("OnEnterPressed", function(self)
        Addon:SaveCurrentRoute(self:GetText())
        self:ClearFocus()
    end)

    self.routeManagerSave = makeButton(self.routeManager, "Save Current", 106, 25)
    self.routeManagerSave.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    self.routeManagerSave:SetPoint("TOPRIGHT", self.routeManager, "TOPRIGHT", -14, -65)
    self.routeManagerSave:SetScript("OnClick", function()
        Addon:SaveCurrentRoute(UI.routeManagerName:GetText())
    end)

    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, self.routeManager)
        row:SetHeight(29)
        row:SetPoint("TOPLEFT", self.routeManager, "TOPLEFT", 14, -105 - ((i - 1) * 31))
        row:SetPoint("RIGHT", self.routeManager, "RIGHT", -14, 0)
        setBackdrop(row, COLORS.normal, COLORS.border)

        row.load = makeButton(row, "", 258, 23)
        row.load:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.load:SetScript("OnClick", function(self)
            if self.routeName then
                UI.pendingDeleteName = nil
                Addon:LoadSavedRoute(self.routeName)
                UI.routeManagerName:SetText(self.routeName)
                UI:RefreshRouteManager()
            end
        end)

        row.share = makeButton(row, "Share", 82, 23)
        row.share:SetPoint("RIGHT", row, "RIGHT", -82, 0)
        row.share:SetScript("OnClick", function(self)
            if self.routeName then
                Addon:ShareSavedRoute(self.routeName, UI.routeManagerShareTarget:GetText())
                UI.routeManagerShareTarget:ClearFocus()
            end
        end)

        row.delete = makeButton(row, "Delete", 72, 23)
        row.delete.label:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
        row.delete:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.delete:SetScript("OnClick", function(self)
            if not self.routeName then
                return
            end
            if UI.pendingDeleteName == self.routeName then
                local name = self.routeName
                UI.pendingDeleteName = nil
                Addon:DeleteSavedRoute(name)
            else
                UI.pendingDeleteName = self.routeName
                UI:RefreshRouteManager()
            end
        end)

        self.savedRouteRows[i] = row
    end

    self.routeManager.shareLabel = self.routeManager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.routeManager.shareLabel:SetPoint("BOTTOMLEFT", self.routeManager, "BOTTOMLEFT", 16, 51)
    self.routeManager.shareLabel:SetText("Recipient for Share buttons (addon required)")
    self.routeManager.shareLabel:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.routeManagerShareHolder, self.routeManagerShareTarget = makeInput(self.routeManager, 312, 24, 48)
    self.routeManagerShareHolder:SetPoint("BOTTOMLEFT", self.routeManager, "BOTTOMLEFT", 16, 17)
    if self.routeManagerShareTarget.SetMaxLetters then
        self.routeManagerShareTarget:SetMaxLetters(48)
    end
    self.routeManagerShareTarget:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    self.routeManagerShareTarget:SetScript("OnEnterPressed", function(self)
        Addon:ShareCurrentRoute(self:GetText(), UI.routeManagerName:GetText())
        self:ClearFocus()
    end)

    self.routeManagerShare = makeButton(self.routeManager, "Share Current", 108, 25)
    self.routeManagerShare.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    self.routeManagerShare:SetPoint("BOTTOMRIGHT", self.routeManager, "BOTTOMRIGHT", -14, 17)
    self.routeManagerShare:SetScript("OnClick", function()
        Addon:ShareCurrentRoute(UI.routeManagerShareTarget:GetText(), UI.routeManagerName:GetText())
        UI.routeManagerShareTarget:ClearFocus()
    end)

    self.routeManagerPage = self.routeManager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.routeManagerPage:SetPoint("BOTTOMLEFT", self.routeManager, "BOTTOMLEFT", 16, 85)
    self.routeManagerPage:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    self.routeManager:Hide()
    self:InstallChatNameHook()

    self.routePage = self.routePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.routePage:SetPoint("BOTTOMLEFT", self.routePanel, "BOTTOMLEFT", 12, 10)
    self.routePage:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.catalogPage = self.catalogPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.catalogPage:SetPoint("BOTTOMLEFT", self.catalogPanel, "BOTTOMLEFT", 12, 10)
    self.catalogPage:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.up = makeButton(frame, "Up", 62, 25)
    self.up:SetPoint("TOPLEFT", self.routePanel, "BOTTOMLEFT", 0, -8)
    self.up:SetScript("OnClick", function()
        if UI.selectedRouteIndex then
            Addon:MoveRouteStep(UI.selectedRouteIndex, UI.selectedRouteIndex - 1)
            UI.selectedRouteIndex = math.max(1, UI.selectedRouteIndex - 1)
        end
    end)

    self.down = makeButton(frame, "Down", 62, 25)
    self.down:SetPoint("LEFT", self.up, "RIGHT", 5, 0)
    self.down:SetScript("OnClick", function()
        if UI.selectedRouteIndex then
            Addon:MoveRouteStep(UI.selectedRouteIndex, UI.selectedRouteIndex + 1)
            UI.selectedRouteIndex = math.min(table.getn(Addon.profile.route), UI.selectedRouteIndex + 1)
        end
    end)

    self.remove = makeButton(frame, "Remove", 72, 25)
    self.remove.label:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
    self.remove:SetPoint("LEFT", self.down, "RIGHT", 5, 0)
    self.remove:SetScript("OnClick", function()
        if UI.selectedRouteIndex then
            Addon:RemoveRouteStep(UI.selectedRouteIndex)
            UI.selectedRouteIndex = nil
        end
    end)

    self.setCurrent = makeButton(frame, "Set Current", 94, 25)
    self.setCurrent:SetPoint("LEFT", self.remove, "RIGHT", 5, 0)
    self.setCurrent:SetScript("OnClick", function()
        if UI.selectedRouteIndex then
            Addon:SetCurrentStep(UI.selectedRouteIndex)
        end
    end)

    self.collapseZones = makeButton(frame, "Collapse", 76, 25)
    self.collapseZones:SetPoint("TOPLEFT", self.catalogPanel, "BOTTOMLEFT", 0, -8)
    self.collapseZones:SetScript("OnClick", function()
        UI:SetAllCatalogGroupsCollapsed(true)
    end)

    self.expandZones = makeButton(frame, "Expand", 76, 25)
    self.expandZones:SetPoint("LEFT", self.collapseZones, "RIGHT", 5, 0)
    self.expandZones:SetScript("OnClick", function()
        UI:SetAllCatalogGroupsCollapsed(false)
    end)

    self.discover = makeButton(frame, "Refresh List", 112, 25)
    self.discover.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    self.discover:SetPoint("TOPRIGHT", self.catalogPanel, "BOTTOMRIGHT", 0, -8)
    self.discover:SetScript("OnClick", function() Addon:BeginCatalogDiscovery() end)

    self.catalogExport = makeButton(frame, "Export", 58, 25)
    self.catalogExport:SetPoint("RIGHT", self.discover, "LEFT", -5, 0)
    self.catalogExport:SetScript("OnClick", function() Addon:ShowCatalogTransfer("export") end)

    self.catalogImport = makeButton(frame, "Import", 58, 25)
    self.catalogImport:SetPoint("RIGHT", self.catalogExport, "LEFT", -5, 0)
    self.catalogImport:SetScript("OnClick", function() Addon:ShowCatalogTransfer("import") end)

    self.navRunLabel = self.navPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.navRunLabel:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -18)
    self.navRunLabel:SetText("RUN ROUTE")
    self.navRunLabel:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.navStatusDivider = self.navPanel:CreateTexture(nil, "ARTWORK")
    self.navStatusDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.navStatusDivider:SetVertexColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7)
    self.navStatusDivider:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -254)
    self.navStatusDivider:SetWidth(124)
    self.navStatusDivider:SetHeight(1)

    self.navStatusLabel = self.navPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.navStatusLabel:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -270)
    self.navStatusLabel:SetText("STATUS")
    self.navStatusLabel:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.status:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -292)
    self.status:SetWidth(124)
    self.status:SetHeight(82)
    self.status:SetJustifyH("LEFT")
    self.status:SetJustifyV("TOP")
    self.status:SetText("Ready.")
    self.status:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.navUsageDivider = self.navPanel:CreateTexture(nil, "ARTWORK")
    self.navUsageDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.navUsageDivider:SetVertexColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7)
    self.navUsageDivider:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -382)
    self.navUsageDivider:SetWidth(124)
    self.navUsageDivider:SetHeight(1)

    self.navUsageLabel = self.navPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.navUsageLabel:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -398)
    self.navUsageLabel:SetText("REROLL USAGE")
    self.navUsageLabel:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.mainGoldStats = self.navPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.mainGoldStats:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -420)
    self.mainGoldStats:SetWidth(124)
    self.mainGoldStats:SetHeight(92)
    self.mainGoldStats:SetJustifyH("LEFT")
    self.mainGoldStats:SetJustifyV("TOP")
    self.mainGoldStats:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    -- Route Runner is deliberately non-secure, but uses the same Zen
    -- visual treatment as the rest of the navigation rail.
    self.start = makeButton(self.navPanel, "Route Runner", 124, 30)
    self.start:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -40)
    self.start.label:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    self.start:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.45)
    self.start:SetScript("OnClick", function()
        if Addon.Debug then
            Addon:Debug("button", "Route Runner opened from main window")
        end
        Addon:SetStatus("Runner ready. Open the Callboard, then press Start Route.", true)
        UI:ShowMini()
    end)
    self.start:HookScript("OnEnter", function()
        UI:UpdateSummonCooldown()
    end)
    self.communityOpen = makeButton(self.navPanel, "Community Routes", 124, 26)
    self.communityOpen:SetPoint("TOPLEFT", self.navPanel, "TOPLEFT", 14, -235)
    self.communityOpen:SetScript("OnClick", function() UI:ShowCommunityRoutes() end)
    self.boardActionMacro = nil

    self.summon = CreateFrame("Button", "ZenCallboardSummonButton", self.navPanel, "SecureActionButtonTemplate")
    self.summon:SetWidth(124)
    self.summon:SetHeight(30)
    styleSecureButton(self.summon, "Summon Board")
    self.summon:SetPoint("TOPLEFT", self.start, "BOTTOMLEFT", 0, -8)
    self.summon:SetAttribute("type", "macro")
    self.summon:SetAttribute("macrotext", "/cast Summon Callboard")
    self.summon:SetScript("PostClick", function()
        Addon:BeginBoardOpenFlow(false)
    end)
    if self.summon.HookScript then
        self.summon:HookScript("OnEnter", function()
            UI:UpdateStartAction(true)
            UI:UpdateSummonCooldown()
        end)
    end
    self:UpdateSummonCooldown()

    self.advance = makeButton(self.navPanel, "Complete Step", 124, 30)
    self.advance:SetPoint("TOPLEFT", self.summon, "BOTTOMLEFT", 0, -8)
    self.advance.label:SetTextColor(COLORS.green[1], COLORS.green[2], COLORS.green[3])
    self.advance:SetScript("OnClick", function()
        Addon:AdvanceRoute("Marked complete by user")
    end)

    self.reset = makeButton(self.navPanel, "Reset to Step 1", 124, 30)
    self.reset:SetPoint("TOPLEFT", self.advance, "BOTTOMLEFT", 0, -8)
    self.reset:SetScript("OnClick", function()
        Addon:ResetRoute()
    end)

    self.clear = makeButton(self.navPanel, "Clear Route", 124, 30)
    self.clear:SetPoint("TOPLEFT", self.reset, "BOTTOMLEFT", 0, -8)
    self.clear.label:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
    self.clear:SetScript("OnClick", function()
        Addon:ClearRoute()
        UI.selectedRouteIndex = nil
    end)

    local miniLayout = Addon.profile.miniWindow
    self.miniFrame = CreateFrame("Frame", "ZenCallboardMiniFrame", UIParent)
    self.miniFrame:SetWidth(math.max(360, miniLayout.width or 380))
    self.miniFrame:SetHeight(miniLayout.height or 172)
    self.miniFrame:SetPoint(
        miniLayout.point or "CENTER",
        UIParent,
        miniLayout.relativePoint or "CENTER",
        miniLayout.x or 0,
        miniLayout.y or 180
    )
    self.miniFrame:SetScale(miniLayout.scale or 1)
    self.miniFrame:SetFrameStrata("DIALOG")
    self.miniFrame:SetClampedToScreen(true)
    self.miniFrame:SetMovable(true)
    self.miniFrame:SetResizable(true)
    if self.miniFrame.SetMinResize then
        self.miniFrame:SetMinResize(360, 172)
    end
    if self.miniFrame.SetMaxResize then
        self.miniFrame:SetMaxResize(620, 420)
    end
    self.miniFrame:EnableMouse(true)
    self.miniFrame:RegisterForDrag("LeftButton")
    setBackdrop(self.miniFrame, COLORS.background)
    self.miniFrame.headerTexture = addHeaderBand(self.miniFrame, 32)
    self.miniFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    self.miniFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveMiniLayout()
    end)

    self.miniFrame.title = self.miniFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.miniFrame.title:SetPoint("TOPLEFT", self.miniFrame, "TOPLEFT", 14, -12)
    self.miniFrame.title:SetPoint("RIGHT", self.miniFrame, "RIGHT", -14, 0)
    self.miniFrame.title:SetJustifyH("LEFT")
    self.miniFrame.title:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])

    self.miniCurrent = self.miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.miniCurrent:SetPoint("TOPLEFT", self.miniFrame, "TOPLEFT", 12, -36)
    self.miniCurrent:SetPoint("BOTTOMRIGHT", self.miniFrame, "BOTTOMRIGHT", -12, 104)
    self.miniCurrent:SetJustifyH("LEFT")
    self.miniCurrent:SetJustifyV("TOP")

    self.miniNext = self.miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.miniNext:Hide()

    self.miniStatus = self.miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.miniStatus:SetPoint("BOTTOMLEFT", self.miniFrame, "BOTTOMLEFT", 12, 82)
    self.miniStatus:SetPoint("BOTTOMRIGHT", self.miniFrame, "BOTTOMRIGHT", -12, 82)
    self.miniStatus:SetJustifyH("LEFT")
    self.miniStatus:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.miniStats = self.miniFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.miniStats:SetPoint("BOTTOMLEFT", self.miniFrame, "BOTTOMLEFT", 12, 64)
    self.miniStats:SetPoint("BOTTOMRIGHT", self.miniFrame, "BOTTOMRIGHT", -12, 64)
    self.miniStats:SetJustifyH("LEFT")
    self.miniStats:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.miniStart = makeButton(self.miniFrame, "Start", 68, 24)
    self.miniStart:SetPoint("BOTTOMLEFT", self.miniFrame, "BOTTOMLEFT", 10, 9)
    self.miniStart:SetScript("OnClick", function()
        if Addon.Debug then
            local visible = Addon.PE and Addon.PE.IsBoardVisible and Addon.PE.IsBoardVisible() or false
            local access = Addon.PE and Addon.PE.HasBoardAccess and Addon.PE.HasBoardAccess() or false
            Addon:Debug("button", "Mini Start Route clicked visible=" .. tostring(visible) .. " access=" .. tostring(access))
        end
        -- Start explicitly arms the normal route session.
        Addon:BeginStartFlow()
    end)

    self.miniSummon = CreateFrame("Button", "ZenCallboardMiniSummonButton", self.miniFrame, "SecureActionButtonTemplate")
    self.miniSummon:SetWidth(86)
    self.miniSummon:SetHeight(24)
    self.miniSummon:SetPoint("LEFT", self.miniStart, "RIGHT", 4, 0)
    styleSecureButton(self.miniSummon, "Summon")
    self.miniSummon:SetAttribute("type", "macro")
    self.miniSummon:SetAttribute("macrotext", "/cast Summon Callboard")
    self.miniSummon:SetScript("PostClick", function()
        Addon:BeginBoardOpenFlow(false)
    end)
    if self.miniSummon.HookScript then
        self.miniSummon:HookScript("OnEnter", function()
            UI:UpdateStartAction(true)
            UI:UpdateSummonCooldown()
        end)
    end

    self.miniPause = makeButton(self.miniFrame, "Pause", 50, 24)
    self.miniPause:SetPoint("LEFT", self.miniSummon, "RIGHT", 4, 0)
    self.miniPause:SetScript("OnClick", function()
        Addon:PauseRoute("Route paused. Press Start when you want to resume.")
        UI:RefreshMini()
    end)

    self.miniStop = makeButton(self.miniFrame, "Stop", 50, 24)
    self.miniStop:SetPoint("LEFT", self.miniPause, "RIGHT", 4, 0)
    self.miniStop:SetScript("OnClick", function()
        Addon:StopRouteAndReturn()
    end)
    self.miniStop.label:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])

    self.miniShare = makeButton(self.miniFrame, "Share Quest", 78, 20)
    self.miniShare:SetPoint("BOTTOMLEFT", self.miniStart, "TOPLEFT", 0, 4)
    self.miniShare:SetScript("OnClick", function()
        if not Addon.Group or not Addon.Group.ShareCurrentRouteQuest then
            Addon:SetStatus("Quest sharing is unavailable.", true)
            return
        end
        local ok, message = Addon.Group:ShareCurrentRouteQuest()
        Addon:SetStatus(message or (ok and "Quest shared." or "Quest could not be shared."), true)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffb58cffZenCallboard:|r " .. tostring(message or "Quest share attempted."))
        end
    end)

    self.miniGroup = makeButton(self.miniFrame, "Group", 58, 20)
    self.miniGroup:SetPoint("LEFT", self.miniShare, "RIGHT", 4, 0)
    self.miniGroup:SetScript("OnClick", function()
        UI:ToggleGroupProgress()
    end)

    self.miniUtilityLabel = self.miniFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.miniUtilityLabel:SetPoint("LEFT", self.miniGroup, "RIGHT", 8, 0)
    self.miniUtilityLabel:SetText("Utilities")
    self.miniUtilityLabel:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    local groupLayout = Addon.profile.groupWindow or {}
    self.groupProgressFrame = CreateFrame("Frame", "ZenCallboardGroupProgressFrame", UIParent)
    self.groupProgressFrame:SetWidth(groupLayout.width or 360)
    self.groupProgressFrame:SetHeight(groupLayout.height or 260)
    self.groupProgressFrame:SetMinResize(340, 180)
    self.groupProgressFrame:SetMaxResize(700, 600)
    self.groupProgressFrame:SetResizable(true)
    self.groupProgressFrame:SetPoint(
        groupLayout.point or "CENTER",
        UIParent,
        groupLayout.relativePoint or "CENTER",
        groupLayout.x or 390,
        groupLayout.y or 100
    )
    self.groupProgressFrame:SetScale(groupLayout.scale or 1)
    self.groupProgressFrame:SetFrameStrata("TOOLTIP")
    self.groupProgressFrame:SetClampedToScreen(true)
    self.groupProgressFrame:SetMovable(true)
    self.groupProgressFrame:EnableMouse(true)
    self.groupProgressFrame:RegisterForDrag("LeftButton")
    self.groupProgressFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    self.groupProgressFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveGroupLayout()
    end)
    setBackdrop(self.groupProgressFrame, COLORS.background, COLORS.gold)
    self.groupProgressFrame.headerTexture = addHeaderBand(self.groupProgressFrame, 38)

    self.groupProgressFrame.title = self.groupProgressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.groupProgressFrame.title:SetPoint("TOPLEFT", self.groupProgressFrame, "TOPLEFT", 10, -10)
    self.groupProgressFrame.title:SetText("Group Progress")
    self.groupProgressFrame.title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])

    self.groupProgressFrame.close = makeButton(self.groupProgressFrame, "X", 26, 22)
    self.groupProgressFrame.close:SetPoint("TOPRIGHT", self.groupProgressFrame, "TOPRIGHT", -6, -6)
    self.groupProgressFrame.close:SetScript("OnClick", function()
        UI.groupProgressFrame:Hide()
    end)

    self.groupProgressFrame.subtitle = self.groupProgressFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.groupProgressFrame.subtitle:SetPoint("TOPLEFT", self.groupProgressFrame, "TOPLEFT", 10, -34)
    self.groupProgressFrame.subtitle:SetPoint("RIGHT", self.groupProgressFrame, "RIGHT", -10, 0)
    self.groupProgressFrame.subtitle:SetJustifyH("LEFT")
    self.groupProgressFrame.subtitle:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    self.groupRefresh = makeButton(self.groupProgressFrame, "Refresh / Sync", 104, 22)
    self.groupRefresh:SetPoint("BOTTOMLEFT", self.groupProgressFrame, "BOTTOMLEFT", 8, 7)
    self.groupRefresh:SetScript("OnClick", function()
        if Addon.Group and Addon.Group.RefreshAndSync then
            Addon.Group:RefreshAndSync()
            Addon:SetStatus("Group refresh/sync requested.", true)
        end
    end)

    self.groupLink = makeButton(self.groupProgressFrame, "Link Group", 82, 22)
    self.groupLink:SetPoint("LEFT", self.groupRefresh, "RIGHT", 6, 0)
    self.groupLink:SetScript("OnClick", function()
        if not Addon.Group then
            return
        end
        local linked, available = Addon.Group:GetCurrentLinkCounts()
        if available > 0 and linked >= available then
            local count = Addon.Group:UnlinkCurrentGroup()
            Addon:SetStatus("Unlinked Callboard sync from " .. tostring(count) .. " group member(s).", true)
        else
            local count = Addon.Group:LinkCurrentGroup()
            Addon:SetStatus("Linked Callboard sync with " .. tostring(count) .. " group member(s).", true)
        end
        UI:RefreshGroupProgress()
    end)

    self.groupTargetLink = makeButton(self.groupProgressFrame, "Link Target", 82, 22)
    self.groupTargetLink:SetPoint("LEFT", self.groupLink, "RIGHT", 6, 0)
    self.groupTargetLink:SetScript("OnClick", function()
        if not Addon.Group or not Addon.Group.ToggleTargetLink then
            return
        end
        local ok, message = Addon.Group:ToggleTargetLink()
        Addon:SetStatus(message or (ok and "Target link updated." or "Could not update target link."), true)
        UI:RefreshGroupProgress()
    end)

    self.groupLink:Hide()
    self.groupTargetLink:Hide()

    self.groupProgressScroll = CreateFrame("ScrollFrame", "ZenCallboardGroupProgressScroll", self.groupProgressFrame, "UIPanelScrollFrameTemplate")
    self.groupProgressScroll:SetPoint("TOPLEFT", self.groupProgressFrame, "TOPLEFT", 8, -52)
    self.groupProgressScroll:SetPoint("BOTTOMRIGHT", self.groupProgressFrame, "BOTTOMRIGHT", -28, 36)

    self.groupProgressChild = CreateFrame("Frame", nil, self.groupProgressScroll)
    self.groupProgressChild:SetWidth(245)
    self.groupProgressChild:SetHeight(160)
    self.groupProgressScroll:SetScrollChild(self.groupProgressChild)

    self.groupProgressText = self.groupProgressChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.groupProgressText:SetPoint("TOPLEFT", self.groupProgressChild, "TOPLEFT", 3, -3)
    self.groupProgressText:SetPoint("RIGHT", self.groupProgressChild, "RIGHT", -3, 0)
    self.groupProgressText:SetJustifyH("LEFT")
    self.groupProgressText:SetJustifyV("TOP")

    self.groupScaleDown = makeButton(self.groupProgressFrame, "-", 22, 20)
    self.groupScaleDown:SetPoint("TOPRIGHT", self.groupProgressFrame, "TOPRIGHT", -82, -5)
    self.groupScaleDown:SetScript("OnClick", function()
        local scale = math.max(0.55, (UI.groupProgressFrame:GetScale() or 1) - 0.05)
        scaleFrameAroundTopRight(UI.groupProgressFrame, scale)
        UI:SaveGroupLayout()
        UI:SetStatus(string.format("Group UI scale: %d%%", math.floor(scale * 100 + 0.5)))
    end)

    self.groupScaleUp = makeButton(self.groupProgressFrame, "+", 22, 20)
    self.groupScaleUp:SetPoint("LEFT", self.groupScaleDown, "RIGHT", 3, 0)
    self.groupScaleUp:SetScript("OnClick", function()
        local scale = math.min(1.50, (UI.groupProgressFrame:GetScale() or 1) + 0.05)
        scaleFrameAroundTopRight(UI.groupProgressFrame, scale)
        UI:SaveGroupLayout()
        UI:SetStatus(string.format("Group UI scale: %d%%", math.floor(scale * 100 + 0.5)))
    end)

    self.groupResize = CreateFrame("Button", nil, self.groupProgressFrame)
    self.groupResize:SetWidth(18)
    self.groupResize:SetHeight(18)
    self.groupResize:SetPoint("BOTTOMRIGHT", self.groupProgressFrame, "BOTTOMRIGHT", -2, 2)
    self.groupResize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    self.groupResize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    self.groupResize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    self.groupResize:SetScript("OnMouseDown", function()
        UI.groupProgressFrame:StartSizing("BOTTOMRIGHT")
    end)
    self.groupResize:SetScript("OnMouseUp", function()
        UI.groupProgressFrame:StopMovingOrSizing()
        UI:SaveGroupLayout()
    end)
    self.groupProgressFrame:SetScript("OnSizeChanged", function(self)
        local width = math.max(190, self:GetWidth() - 48)
        UI.groupProgressChild:SetWidth(width)
    end)
    self.groupProgressFrame:Hide()

    self.miniScaleDown = makeButton(self.miniFrame, "-", 22, 20)
    self.miniScaleDown:SetPoint("TOPRIGHT", self.miniFrame, "TOPRIGHT", -51, -5)
    self.miniScaleDown:SetScript("OnClick", function()
        local scale = math.max(0.55, (UI.miniFrame:GetScale() or 1) - 0.05)
        scaleFrameAroundTopRight(UI.miniFrame, scale)
        UI:SaveMiniLayout()
        UI:SetStatus(string.format("Mini UI scale: %d%%", math.floor(scale * 100 + 0.5)))
    end)

    self.miniScaleUp = makeButton(self.miniFrame, "+", 22, 20)
    self.miniScaleUp:SetPoint("LEFT", self.miniScaleDown, "RIGHT", 3, 0)
    self.miniScaleUp:SetScript("OnClick", function()
        local scale = math.min(1.50, (UI.miniFrame:GetScale() or 1) + 0.05)
        scaleFrameAroundTopRight(UI.miniFrame, scale)
        UI:SaveMiniLayout()
        UI:SetStatus(string.format("Mini UI scale: %d%%", math.floor(scale * 100 + 0.5)))
    end)

    self.miniResize = CreateFrame("Button", nil, self.miniFrame)
    self.miniResize:SetWidth(18)
    self.miniResize:SetHeight(18)
    self.miniResize:SetPoint("BOTTOMRIGHT", self.miniFrame, "BOTTOMRIGHT", -2, 2)
    self.miniResize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    self.miniResize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    self.miniResize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    self.miniResize:SetScript("OnMouseDown", function()
        UI.miniFrame:StartSizing("BOTTOMRIGHT")
    end)
    self.miniResize:SetScript("OnMouseUp", function()
        UI.miniFrame:StopMovingOrSizing()
        UI:SaveMiniLayout()
    end)
    self.miniFrame:Hide()
    self.boardActionMacro = nil
    self.lastSummonCooldownState = nil
    self:UpdateStartAction()
    self:UpdateSummonCooldown()

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ZenCallboardFrame")
    end
    return frame
end

function UI:SetStatus(message)
    if self.status then
        self.status:SetText(message or "")
        local color = getStatusColor(message)
        self.status:SetTextColor(color[1], color[2], color[3])
    end
end

function UI:Refresh()
    if not self.frame or not Addon.profile or not Addon.db then
        return
    end

    local route = Addon.profile.route
    local routeCount = table.getn(route)
    local activeRouteName = Addon.profile.activeRouteName
    local loopSuffix = Addon.profile.autoLoop and "  |cffffcc00[Loop]|r" or ""
    self.routePanel.title:SetText(activeRouteName and ("Quest route — " .. activeRouteName .. loopSuffix) or ("Quest route" .. loopSuffix))
    self.routeOffset = clampOffset(self.routeOffset, routeCount, 13)

    for visibleIndex = 1, 13 do
        local row = self.routeRows[visibleIndex]
        local routeIndex = self.routeOffset + visibleIndex
        local key = route[routeIndex]
        if key then
            local quest = Addon.db.knownQuests[key]
            local title = quest and Core.QuestTitle(quest) or key
            row.routeIndex = routeIndex
            row.number:SetText(tostring(routeIndex) .. ".")
            row.label:SetText(title)
            if routeIndex == Addon.profile.currentStep then
                row:SetBackdropColor(unpack(COLORS.current))
                row:SetBackdropBorderColor(COLORS.green[1], COLORS.green[2], COLORS.green[3], 1)
            elseif routeIndex == self.selectedRouteIndex then
                row:SetBackdropColor(unpack(COLORS.selected))
                row:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
            else
                row:SetBackdropColor(unpack(COLORS.normal))
                row:SetBackdropBorderColor(unpack(COLORS.border))
            end
            row:Show()
        else
            row.routeIndex = nil
            row:Hide()
        end
    end
    self.routePage:SetText(tostring(routeCount) .. " route step(s)")
    if routeCount == 0 then
        self.routeEmpty:Show()
    else
        self.routeEmpty:Hide()
    end

    local zoneCount
    local learnedCount
    self.catalog, zoneCount, learnedCount = Core.BuildGroupedCatalog(
        Addon.db,
        self.searchText,
        Addon.profile.catalogCollapsed
    )
    local catalogCount = table.getn(self.catalog)
    if catalogCount == 0 then
        self.catalogEmpty:SetText((self.searchText or "") ~= ""
            and "No learned quests match this search."
            or "No quests learned yet.\n\nOpen the Callboard to learn visible quests, or use Refresh List while it is open.")
        self.catalogEmpty:Show()
    else
        self.catalogEmpty:Hide()
    end
    self.catalogOffset = clampOffset(self.catalogOffset, catalogCount, 12)
    for visibleIndex = 1, 12 do
        local row = self.catalogRows[visibleIndex]
        local catalogIndex = self.catalogOffset + visibleIndex
        local entry = self.catalog[catalogIndex]
        if entry then
            if entry.kind == "header" then
                row.groupId = entry.groupId
                row.add.questKey = nil
                row.info.questKey = nil
                row.add:Hide()
                row.info:Hide()
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row, "LEFT", 10, 0)
                row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.label:SetText((entry.collapsed and "|cffffcc00[+]|r " or "|cffffcc00[-]|r ")
                    .. entry.label .. "  |cff888888(" .. tostring(entry.count) .. ")|r")
                row:SetBackdropColor(unpack(COLORS.panelLight))
                row:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 0.65)
            else
                local quest = entry.quest
                local inRoute = Core.RouteContains(route, quest.key)
                row.groupId = nil
                row.add.questKey = quest.key
                row.info.questKey = quest.key
                setButtonText(row.add, inRoute and "=" or "+")
                row.add:Show()
                row.info:Show()
                if inRoute then
                    row.add:SetButtonEnabled(false)
                else
                    row.add:SetButtonEnabled(true)
                end
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row.add, "RIGHT", 7, 0)
                row.label:SetPoint("RIGHT", row.info, "LEFT", -5, 0)
                local idSuffix = quest.questId and "  |cff777777#" .. tostring(quest.questId) .. "|r" or ""
                local seen = tonumber(quest.seen) or 0
                local verifySuffix = seen > 0 and ("  |cff55cc77✓" .. tostring(seen) .. "|r") or "  |cff777777Unverified|r"
                local remaining = Addon.profile.ignoreOrder == true and 0 or Core.RepeatLockRemaining(Addon.profile and Addon.profile.recentCompletedQuests, quest.key)
                local cooldownSuffix = remaining > 0
                    and ("  |cffff6666[CD " .. tostring(remaining) .. "]|r")
                    or ""
                row.label:SetText(Core.QuestTitle(quest) .. idSuffix .. verifySuffix .. cooldownSuffix)
                row:SetBackdropColor(unpack(COLORS.normal))
                row:SetBackdropBorderColor(unpack(COLORS.border))
            end
            row:Show()
        else
            row.groupId = nil
            row.add.questKey = nil
            row.info.questKey = nil
            row:Hide()
        end
    end
    local verifiedCount = 0
    if Addon.db and Addon.db.knownQuests then
        for _, quest in pairs(Addon.db.knownQuests) do
            if (tonumber(quest.seen) or 0) > 0 then verifiedCount = verifiedCount + 1 end
        end
    end
    self.catalogPage:SetText(tostring(learnedCount or 0) .. " known • " .. tostring(verifiedCount) .. " verified • " .. tostring(zoneCount or 0) .. " groups")

    if self.mainGoldStats then
        local stats = Addon.profile.goldStats or {}
        local function compactMoney(v)
            v = math.max(0, math.floor(tonumber(v) or 0))
            local gold = math.floor(v / 10000)
            local silver = math.floor((v % 10000) / 100)
            local copper = v % 100
            if gold > 0 then
                return tostring(gold) .. "g " .. tostring(silver) .. "s"
            elseif silver > 0 then
                return tostring(silver) .. "s " .. tostring(copper) .. "c"
            end
            return tostring(copper) .. "c"
        end
        self.mainGoldStats:SetText(
            "Total rolls: |cffffffff" .. tostring(stats.rerolls or 0) .. "|r\n"
            .. "Total spent: |cffffffff" .. compactMoney(stats.totalSpent or stats.spent or 0) .. "|r\n"
            .. "Session: |cffffffff" .. tostring(stats.sessionRerolls or 0) .. " rolls • " .. compactMoney(stats.sessionSpent or 0) .. "|r\n\n"
            .. "Last search: |cffffffff" .. tostring(stats.lastSearchRerolls or 0) .. " rolls|r\n"
            .. "Cost: |cffffffff" .. compactMoney(stats.lastSearchSpent or 0) .. "|r"
        )
    end

    setButtonText(self.start, "Route Runner")
    self:SetStatus(Addon.statusMessage or "Ready.")
    self:RefreshMini()
end

function UI:Toggle()
    if Addon.uiInitError then
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555ZenCallboard UI error:|r " .. tostring(Addon.uiInitError))
        end
        return
    end
    self:Create()
    if self.miniFrame and self.miniFrame:IsShown() then
        self:ShowMain()
        return
    end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self.frame:Raise()
        self:Refresh()
    end
end


-- Hidden Callboard tooltip guard. The board stays genuinely shown internally so
-- Ebonhold keeps the live interaction session, but its invisible Reroll control can
-- still feed GameTooltip on hover. Hide only tooltips that identify the Callboard.
do
    local tooltipGuard = CreateFrame("Frame")
    local elapsed = 0
    tooltipGuard:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.05 then return end
        elapsed = 0
        if not (Addon.profile and Addon.profile.hideCallboardWhileRunning) then return end
        if not (GameTooltip and GameTooltip:IsShown()) then return end
        for i = 1, 12 do
            local line = _G["GameTooltipTextLeft" .. tostring(i)]
            local txt = line and line.GetText and string.lower(tostring(line:GetText() or "")) or ""
            if string.find(txt, "reroll selection", 1, true)
                or string.find(txt, "objectives board", 1, true)
                or (i <= 3 and string.find(txt, "cost:", 1, true)) then
                GameTooltip:Hide()
                return
            end
        end
    end)
end
