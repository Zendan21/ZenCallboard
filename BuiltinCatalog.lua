local addonName, Addon = ...

-- Built-in baseline catalogue. These entries let a fresh install build routes without
-- paying for catalogue-discovery rerolls. Live Ebonhold data always remains authoritative
-- and can add/update entries as they are naturally encountered.
Addon.BuiltinCatalog = {
    { questId = 50095, title = "Peak Predators" },
    { questId = 50205, title = "Storm Peaks Trophy", zoneOrSort = 90 },
    { questId = 50206, title = "Icecrown Trophy", zoneOrSort = 210 },
    { questId = 600600, title = "The Fall of Sartharion", zoneOrSort = 4493, questType = 3 },
    { questId = 600601, title = "Malygos Must Die!", zoneOrSort = 4500, questType = 3 },
    { questId = 600602, title = "End of the Line: Kelthuzad", zoneOrSort = 3456, questType = 3 },
    { questId = 600603, title = "Topple the Tyrant: Yogg-Saron", zoneOrSort = 4273, questType = 3 },
    { questId = 600637, title = "Wanted: Loken", zoneOrSort = 4272, questType = 2 },
    { questId = 600638, title = "Bring Down Ingvar the Plunderer", zoneOrSort = 206, questType = 2 },
    { questId = 600639, title = "Clear the Path: King Ymiron", zoneOrSort = 1196, questType = 2 },
    { questId = 600640, title = "Into the Depths: Anub'arak", zoneOrSort = 4277, questType = 2 },
    { questId = 600641, title = "The Menace of Ahn'kahet: Old Kingdom", zoneOrSort = 4494, questType = 2 },
    { questId = 600642, title = "A Blade for Keristrasza", zoneOrSort = 4265, questType = 2 },
    { questId = 600643, title = "End the Threat: The Prophet Tharon'ja", zoneOrSort = 4196, questType = 2 },
    { questId = 600644, title = "Storm the Gates: Gal'darah", zoneOrSort = 4416, questType = 2 },
    { questId = 600645, title = "Dungeon Crawl: Loken", zoneOrSort = 4272, questType = 2 },
    { questId = 600646, title = "By Sword and Shield: Ingvar the Plunderer", zoneOrSort = 206, questType = 2 },
    { questId = 600658, title = "Thinning the Herd in Winterspring", questType = 1 },
    { questId = 600660, title = "Culling of the Water Revenant", questType = 1 },
    { questId = 600661, title = "Population Management: Earthbound Revenant", questType = 1 },
    { questId = 600662, title = "Raging Flame Infestation", questType = 1 },
    { questId = 600663, title = "Clear the Roads of Winterspring", questType = 1 },
    { questId = 600664, title = "Pacify Winterspring: Whispering Wind", questType = 1 },
    { questId = 600665, title = "Drive Them Back: Skeletal Archmage", zoneOrSort = 210, questType = 1 },
    { questId = 600666, title = "A Growing Menace: Ravaged Ghoul", zoneOrSort = 210, questType = 1 },
    { questId = 600667, title = "Crystalsong Forest Under Siege", zoneOrSort = 2817, questType = 1 },
    { questId = 600668, title = "Sweep and Clear: Azure Manashaper", zoneOrSort = 2817, questType = 1 },
    { questId = 600669, title = "No Mercy: Azure Scalebane", zoneOrSort = 2817, questType = 1 },
    { questId = 600772, title = "Order Restored: The Oculus", zoneOrSort = 4228, questType = 2 },
    { questId = 600836, title = "Collect Saronite Bar", questType = 4 },
    { questId = 600840, title = "Titansteel Bar Supply", questType = 4 },
    { questId = 600841, title = "Crafting Materials: Hardened Saronite Bar", questType = 4 },
    { questId = 600842, title = "Resource Acquisition: Titanium Bar", questType = 4 },
    { questId = 600873, title = "Trade Goods: Eternal Water", questType = 4 },
    { questId = 600874, title = "Eternal Air Wanted", questType = 4 },
    { questId = 600875, title = "Bulk Order: Eternal Earth", questType = 4 },
    { questId = 600876, title = "Stockpile: Eternal Life", questType = 4 },
    { questId = 600877, title = "Material Requisition: Eternal Shadow", questType = 4 },
    { questId = 600878, title = "Supply Run: Eternal Fire", questType = 4 },
    { questId = 600930, title = "Constrictor Grass Supply", questType = 4 },
    { questId = 600931, title = "Crafting Materials: Adder's Tongue", questType = 4 },
    { questId = 600933, title = "Trade Goods: Lichbloom", questType = 4 },
    { questId = 600934, title = "Icethorn Wanted", questType = 4 },
    { questId = 600936, title = "Stockpile: Frost Lotus", questType = 4 },
    { questId = 600970, title = "Gather Heavy Borean Leather", questType = 4 },
}

function Addon:SeedBuiltinCatalog()
    if not self.db or not self.Core then return 0 end
    local added = 0
    for i = 1, table.getn(self.BuiltinCatalog or {}) do
        local quest = self.BuiltinCatalog[i]
        quest.source = quest.source or "seed"
        local key = self.Core.QuestKey(quest)
        if key and not self.db.knownQuests[key] and self.Core.LearnQuest(self.db, quest) then added = added + 1 end
    end
    return added
end
