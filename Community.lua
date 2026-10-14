local addonName, Addon = ...
local UI = Addon.UI
local Group = Addon.Group
local Style = Addon.ZenStyle and Addon.ZenStyle.UI
local window, rows, selected, listButtons, preview

local function button(parent, text, width, x, y, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function update()
    if not window then return end
    rows = Group:CommunityRoutes()
    for i=1,10 do
        local b = listButtons[i]
        local row = rows[i]
        if row then
            b:SetText((selected == i and "> " or "") .. row.name .. "  -  " .. row.author .. "  (" .. row.steps .. " steps)")
            b:Show()
        else
            b:Hide()
        end
    end
    if not Group.ebonHandle then
        preview:SetText("EbonAPI 2.1.2 is required for community sharing.\\nZenCallboard still works normally without it.")
    elseif selected and rows[selected] then
        local row = rows[selected]
        local lines = {row.name .. "  |  by " .. row.author, tostring(row.steps) .. " quests:", ""}
        for i=1,math.min(13,row.steps) do
            table.insert(lines, tostring(i) .. ". " .. tostring(row.route.quests[i].title or "Unknown quest"))
        end
        if row.steps > 13 then table.insert(lines, "... and " .. tostring(row.steps-13) .. " more") end
        preview:SetText(table.concat(lines,"\\n"))
    else
        preview:SetText("Select a route to preview.\\n\\nRoutes shared by other EbonAPI users appear after synchronization.\\nOnly routes received by EbonAPI are listed.")
    end
end

function UI:ShowCommunityRoutes()
    if not window then
        window = CreateFrame("Frame","ZenCallboardCommunityRoutes",UIParent)
        window:SetWidth(710); window:SetHeight(460)
        window:SetPoint("CENTER",UIParent,"CENTER",0,20)
        window:SetFrameStrata("DIALOG")
        window:SetMovable(true); window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart",function(self) self:StartMoving() end)
        window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        window:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        window:SetBackdropColor(.035,.043,.055,.98)
        window:SetBackdropBorderColor(.40,.33,.20,1)
        if Style then
            Style:StyleSurface(window, "panel")
            window:SetBackdropColor(0,0,0,0)
            window:SetBackdropBorderColor(0,0,0,0)
        end
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        title:SetPoint("TOPLEFT",window,"TOPLEFT",18,-16)
        title:SetText("|cffffd078ZenCallboard|r  /  Community Routes")
        local close=CreateFrame("Button",nil,window,"UIPanelCloseButton")
        close:SetPoint("TOPRIGHT",window,"TOPRIGHT",-4,-4)
        listButtons={}
        for i=1,10 do
            local index=i
            local b=button(window,"",325,16,-54-(i-1)*30,function()
                selected=index
                update()
            end)
            listButtons[i]=b
        end
        preview=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        preview:SetPoint("TOPLEFT",window,"TOPLEFT",358,-58)
        preview:SetWidth(332);preview:SetHeight(300)
        preview:SetJustifyH("LEFT");preview:SetJustifyV("TOP")
        local notice=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        notice:SetPoint("BOTTOMLEFT",window,"BOTTOMLEFT",18,48)
        notice:SetWidth(660);notice:SetHeight(36)
        notice:SetJustifyH("LEFT")
        notice:SetText("Sharing is opt-in. Imports are saved presets only; your active route is never replaced.")
        button(window,"Share My Route",150,18,-420,function()
            local ok,info=Group:PublishBrowsableRoute()
            if Addon.SetStatus then Addon:SetStatus(ok and "Community route published." or tostring(info),true) end
            update()
        end)
        button(window,"Refresh",95,184,-420,function()
            if Group:InitEbonAPI() and Group.ebonHandle.SyncShares then
                pcall(Group.ebonHandle.SyncShares,Group.ebonHandle)
            end
            update()
        end)
        button(window,"Import Selected",145,359,-420,function()
            if not selected or not rows[selected] then return end
            local ok,info=Group:ImportBrowsableRoute(rows[selected])
            if Addon.SetStatus then Addon:SetStatus(ok and ("Saved route: "..info) or tostring(info),true) end
        end)
        window:SetScript("OnShow",update)
    end
    selected=nil
    window:Show()
    window:Raise()
    update()
end
