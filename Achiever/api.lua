local _G, _ = _G or getfenv()
local function debug(msg)
	-- DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff'.. (msg or 'nil'))
end
local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end
function AchievementFrameSummary_LocalizeButton (button)

end

function AchievementButton_LocalizeMiniAchievement (frame)

end

function AchievementButton_LocalizeProgressBar (frame)

end

function AchievementButton_LocalizeMetaAchievement (frame)

end

function AchievementFrame_LocalizeCriteria (frame)

end

function AchievementCategoryButton_Localize(button)

end

-- Achievement Flags
ACHIEVEMENT_FLAGS_STATISTIC             = 1;
ACHIEVEMENT_FLAGS_HIDDEN                = 2;

-- Criteria Flags
ACHIEVEMENT_CRITERIA_PROGRESS_BAR       = 1;
ACHIEVEMENT_CRITERIA_HIDDEN             = 2;
ACHIEVEMENT_CRITERIA_FLAG_MONEY_COUNTER = 32;


local function IsAchievementCompleted(id)
    local achievementCompletion = achieverDBpc and achieverDBpc.achievements and
        achieverDBpc.achievements[tonumber(id)]
    local completed = false
    if (achievementCompletion) then
        completed = true;
    else
        completed = false;
    end
    return completed;
end

local function GetPreviousID(id)
    if (not achieverDB or not achieverDB.achievements or not achieverDB.achievements.previousById) then return nil end
    return achieverDB.achievements.previousById[tonumber(id)]
end

local function GetNextID(id)
    if (not achieverDB or not achieverDB.achievements or not achieverDB.achievements.nextById) then return nil end
    return achieverDB.achievements.nextById[tonumber(id)]
end

local function IsAchievementVisible(id, includeAll)
    if (not id) then return false end
    if (includeAll) then return true end
    if (IsAchievementCompleted(id)) then
        local nextId = GetNextID(id)
        if (not nextId) then return true end
        return not IsAchievementCompleted(nextId)
    end
    local achievement = achieverDB and achieverDB.achievements and
        achieverDB.achievements.data and achieverDB.achievements.data[tonumber(id)]
    if (not achievement) then return false end
    if ((achievement.points or 0) == 0) then return false end
    local previousId = GetPreviousID(id)
    if (not previousId) then return true end
    return IsAchievementCompleted(previousId)
end

local function defaultAchievementOrderComparator(a, b)
    local aOrder = a.order or 0
    local bOrder = b.order or 0
    if (aOrder ~= bOrder) then return aOrder < bOrder end
    return a.id < b.id
end

local function GetCategory(categotyId)
    if (not achieverDB or not achieverDB.categories or not achieverDB.categories.data) then return nil end
    return achieverDB.categories.data[tonumber(categotyId)];
end

local function GetAchievement(achievementId)
    if (not achieverDB or not achieverDB.achievements or not achieverDB.achievements.data) then return nil end
    return achieverDB.achievements.data[tonumber(achievementId)];
end

local function GetAchievementCompletionTime(achievementId)
    if (not achieverDBpc or not achieverDBpc.achievements or not achieverDBpc.achievements[achievementId]) then return nil end
    return achieverDBpc.achievements[achievementId].date;
end

-- id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy = GetAchievementInfo(achievementID or categoryID, index)
-- 1	id	Number	Achievement ID.
-- 2	name	String	The Name of the Achievement.
-- 3	points	Number	Points awarded for completing this achievement.
-- 4	completed	Boolean	Returns true/false depending if you've completed this achievement on any character.
-- 5	month	Number	Month this was completed. Returns nil if Completed is false.
-- 6	day	Number	Day this was completed. Returns nil if Completed is false.
-- 7	year	Number	Year this was completed. Returns nil if Completed is false. Returns number of years since 2000.
-- 8	description	String	The Description of the Achievement.
-- 9	flags	Number	A bitfield that indicates achievement properties:
--        0x01 - Achievement is a statistic
--        0x02 - Achievement should be hidden
--        0x80 - Progress Bar
-- 10	icon	Number	The fileID of the icon used for this achievement
-- 11	rewardText	String	Text describing the reward you get for completing this achievement.
-- 12	isGuild	Boolean	Returns true/false depending if this is a guild achievement.
-- 13	wasEarnedByMe	Boolean	Returns true/false depending if you've completed this achievement on this character.
-- function mock_GetAchievementInfo(id, index)
--     local name = 'Level 1337'
-- 	local points = 50
-- 	local icon = [[Interface\icons\Spell_Holy_Redemption]]
--     return 6, name, points, true, 3, 3, 2021, 'done kool stuff', 1, icon, 'reward text', false, true
-- end
function GetAchievementInfo(id, index, includeAll)
    local ach = nil
    local playerAch = nil
    local all = includeAll or false
    if (index) then
        local category = GetCategory(id)
        if (category) then
            local achs = {}
            local categoryAchievements = achieverDB.achievements.byCategory[tonumber(id)] or {}
            for _, aid in pairs(categoryAchievements) do
                if IsAchievementVisible(aid, all) then
                    table.insert(achs, GetAchievement(aid))
                end
            end
            if index <= getn(achs) then
                table.sort(achs, function(a, b)
                    local completedA, completedB = IsAchievementCompleted(a.id), IsAchievementCompleted(b.id)
                    if (completedA and completedB) then return defaultAchievementOrderComparator(a, b) end
                    if (completedA) then return true end
                    if (completedB) then return false end
                    local previousA, previousB = GetPreviousID(a.id), GetPreviousID(b.id)
                    completedA = (previousA and IsAchievementCompleted(previousA)) or false
                    completedB = (previousB and IsAchievementCompleted(previousB)) or false
                    if (completedA and completedB) then return previousA < previousB end
                    if (completedA) then return true end
                    if (completedB) then return false end
                    return defaultAchievementOrderComparator(a, b)
                end)
                ach = achs[index]
            end
        end
    else
        ach = GetAchievement(id)
    end
    if (ach) then
        local icon = ach.icon
        local completed, earnedBy = false, nil
        local month, day, year
        local reward = ''
        if (ach.titleReward ~= '0') then reward = ach.titleReward; end
        if (IsAchievementCompleted(ach.id)) then
            debug('GetAchievementInfo '.. ach.id)
            local completionTime = GetAchievementCompletionTime(ach.id)
            if (completionTime) then
                month, day, year = tonumber(date('%m', completionTime)), tonumber(date('%d', completionTime)), tonumber(date('%y', completionTime))
            end
            -- local month, day, year = playerAch.month, playerAch.day, playerAch.year
            completed, earnedBy = true, UnitName('player')

        end
        return ach.id, ach.name, ach.points, completed, month, day, year, ach.description, ach.flags or 0, icon, reward, false, completed, earnedBy, false
    end
    return 1, 'INVALID ACHIEVEMENT', 0, false, nil, nil, nil, '', 0, 0, '', false, false, '', false
end

function GetCategoryList()
    local result = {}

    local categories = achieverDB and achieverDB.categories and achieverDB.categories.data or {}
    for id, v in pairs(categories) do
        if (id ~= 1 and v.parentId ~= 1) then
            table.insert(result, id)
        end
    end

    table.sort(result)
    return result
end

-- category (number) - AchievementID of a statistic or statistic category.
function GetStatistic(id)
    local value = 0
    local criteriaIdList = achieverDB and achieverDB.criteria and achieverDB.criteria.byAchievement and
        achieverDB.criteria.byAchievement[id]
    if (criteriaIdList) then
        for k, v in pairs(criteriaIdList) do
            local cCriteria = achieverDBpc and achieverDBpc.criteria and achieverDBpc.criteria[v]
            if (cCriteria) then
                value = value + (cCriteria.counter or 0)
            end
        end
    end

    return value
end

function GetStatisticsCategoryList()
    local result = {}
    local rootStatCategoryIdList = achieverDB and achieverDB.categories and
        achieverDB.categories.byParent and achieverDB.categories.byParent['1'] or {};
    for i, v in pairs(rootStatCategoryIdList) do
        table.insert(result, v)
        local subStatCategoryIdList = achieverDB.categories.byParent[tostring(v)];
        if (subStatCategoryIdList) then
            for ii, vv in pairs(subStatCategoryIdList) do
                table.insert(result, vv)
            end
        end
    end
    table.sort(result)
    return result
end

-- title, parentCategoryID, flags = GetCategoryInfo(categoryID)
function GetCategoryInfo(categoryID)
    local category = GetCategory(categoryID)
    if (category) then return category.name, category.parentId, category.order end
    return '', -1, 0
end

-- total, completed, incompleted
function GetCategoryNumAchievements(categoryID, includeAll, completion)
    local id = categoryID
    if (id == -2) then
        id = 1;
    end



    includeAll = includeAll or false

    local total, completed, incompleted = 0, 0, 0

    local category = GetCategory(tonumber(id));
    if (category) then
        local achievements = achieverDB.achievements.byCategory[category.id]
        if (achievements) then
            -- debug('GetCategoryNumAchievements ' .. table.getn(achievements))
            for _, aid in pairs(achievements) do
                if (IsAchievementVisible(aid, includeAll)) then
                    total = total + 1
                    if (IsAchievementCompleted(aid)) then
                        completed = completed + 1
                    else
                        incompleted = incompleted + 1
                    end
                end
            end
        end
    end

    return total, completed, incompleted
end

function GetPreviousAchievement(achievementID)
    return GetPreviousID(achievementID)
end

-- return The ID of the Achievement and whether it's completed
function GetNextAchievement(achievementID)
    local nextID = GetNextID(achievementID)
    if (nextID) then return nextID, IsAchievementCompleted(nextID) end
    return nil, false
end

-- total, completed
function GetNumCompletedAchievements(inGuildView)
    local completed = 0
    local playerAchievements = achieverDBpc and achieverDBpc.achievements or {}
    for _ in pairs(playerAchievements) do completed = completed + 1 end

    local total = 0;
    local achievementData = achieverDB and achieverDB.achievements and achieverDB.achievements.data or {}
    for id, v in pairs(achievementData) do
        local achievement = achievementData[id];
        if (achievement and achievement.categoryId ~= 1 and (achievement.points or 0) > 0 and not (bit.band(achievement.flags or 0, ACHIEVEMENT_FLAGS_HIDDEN) == ACHIEVEMENT_FLAGS_HIDDEN) and not (bit.band(achievement.flags or 0, ACHIEVEMENT_FLAGS_STATISTIC) == ACHIEVEMENT_FLAGS_STATISTIC)) then
            total = total + 1
        end
    end
    return total, completed
end

-- Returns a list of (up to 10) currently tracked achievements.
function GetTrackedAchievements()
    return {}
end

function GetTotalAchievementPoints(inGuildView)
    local points = 0
    local playerAchievements = achieverDBpc and achieverDBpc.achievements or {}
    for id, _ in pairs(playerAchievements) do
        local achievement = GetAchievement(id)
        if (achievement) then points = points + (achievement.points or 0) end
    end
    return points
end

function GetAchievementCategory(achievementID)
    local achievement = GetAchievement(achievementID)
    if (not achievement) then return -1 end
    return achievement.categoryId
end

-- Return the ID's of the last 5 completed Achievements.
function GetLatestCompletedAchievements(inGuildView)

    local completedAchievemenIdHash = {}
    local count = 0
    local playerAchievements = achieverDBpc and achieverDBpc.achievements or {}
    for k, v in pairs(playerAchievements) do
        count = count + 1
        completedAchievemenIdHash[count] = k
    end
    if (count == 0) then return end
    if (count == 1) then return completedAchievemenIdHash[1] end
    table.sort(completedAchievemenIdHash, function(a, b)
        local delta = (playerAchievements[a].date or 0) - (playerAchievements[b].date or 0)
        if (delta ~= 0) then return delta > 0 end
        return a > b
    end)
    local res = {}
    local resCount = 0
    for _, achievementId in pairs(completedAchievemenIdHash) do
        resCount = resCount + 1
        res[resCount] = achievementId
        if (resCount == 5) then break end
    end
    if (resCount == 2) then return res[1], res[2] end
    if (resCount == 3) then return res[1], res[2], res[3] end
    if (resCount == 4) then return res[1], res[2], res[3], res[4] end
    return res[1], res[2], res[3], res[4], res[5]
end

function GetAchievementGuildRep()
    return false, false, 0
end

function IsTrackedAchievement()
    return false
end

function SetFocusedAchievement(achievementID)

end

local function _GetAchievementCriteria(aid, c)
    -- if (not c or not c.name) then
    --     return '', 0, false, 0, 0, '', 0, 0, '', 0, false, 0, 0
    -- end
    -- local criteria = achieverDB.criteria.data[]
    -- local completion = cmanager:GetLocal()
    -- local quantity = completion:GetCriteriaProgression(aid, c.id)
    -- local requiredQuantity = c.quantity
    -- local quantityStr = nil
    -- if requiredQuantity then
    --     if c.quantityFormat then
    --         quantityStr = c.quantityFormat(quantity, requiredQuantity)
    --     else
    --         quantityStr = quantity .. ' / ' .. requiredQuantity
    --     end
    -- end
    -- local assetID = 0
    -- if c.data and c.data[1] then assetID = c.data[1] end
    -- return c.name, c.type, completion:IsCriteriaCompleted(aid, c.id), quantity, requiredQuantity, '', c.flags, assetID, quantityStr, c.id, true, 0, 0
end

-- calculate the gold, silver, and copper values based the amount of copper
function getGSC(money)
    if (money == nil) then money = 0 end
    local g = math.floor(money / 10000)
    local s = math.floor((money - (g*10000)) / 100)
    local c = math.ceil(money - (g*10000) - (s*100))
    return g,s,c
end

-- formats money text by color for gold, silver, copper
function getTextGSC(money, exact, dontUseColorCodes)
    local TEXT_NONE = "0"

    local GSC_GOLD="ffd100"
    local GSC_SILVER="e6e6e6"
    local GSC_COPPER="c8602c"
    local GSC_START="|cff%s%d|r"
    local GSC_PART=".|cff%s%02d|r"
    local GSC_NONE="|cffa0a0a0"..TEXT_NONE.."|r"

    if (not exact) and (money >= 10000) then
        -- Round to nearest silver
        money = math.floor(money / 100 + 0.5) * 100
    end
    local g, s, c = getGSC(money)

    local gsc = ""
    if (not dontUseColorCodes) then
        local fmt = GSC_START
        if (g > 0) then
            gsc = gsc..string.format(fmt, GSC_GOLD, g)
            fmt = GSC_PART
        end
        if (s > 0) or (c > 0) then
            gsc = gsc..string.format(fmt, GSC_SILVER, s)
            fmt = GSC_PART
        end
        if (c > 0) then
            gsc = gsc..string.format(fmt, GSC_COPPER, c)
        end
        if (gsc == "") then
            gsc = GSC_NONE
        end
    else
        if (g > 0) then
            gsc = gsc .. g .. "g ";
        end;
        if (s > 0) then
            gsc = gsc .. s .. "s ";
        end;
        if (c > 0) then
            gsc = gsc .. c .. "c ";
        end;
        if (gsc == "") then
            gsc = TEXT_NONE
        end
    end
    return gsc
end

-- criteriaString, criteriaType, completed, quantity, reqQuantity,
--  charName, flags, assetID, quantityString, criteriaID, eligible =
--    GetAchievementCriteriaInfo(achievementID, criteriaIndex [, countHidden])
function GetAchievementCriteriaInfo(achievementID, criteriaIndex)

    local pCriteria = nil
    local criteria = nil
    local criteriaIdList = achieverDB and achieverDB.criteria and achieverDB.criteria.byAchievement and
        achieverDB.criteria.byAchievement[achievementID]
    local criteriaId = nil
    if (criteriaIdList) then
        criteriaId = criteriaIdList[criteriaIndex]
        if (criteriaId) then
            criteria = achieverDB.criteria.data[criteriaId]
            pCriteria = achieverDBpc.criteria[criteriaId]
        end
        if (not criteriaId or not criteria) then
            return 'INVALID CRITERIA', 0, false, 0, 0, '', 0, 0, '', 0
        end
    end
    if (not criteria) then
        return 'INVALID CRITERIA', 0, false, 0, 0, '', 0, 0, '', 0
    end

    local name = criteria.name
    local criteriaType = criteria.type
    local quantity = 0
    local reqQuantity = criteria.count or 0
    local completed = false
    local charName = UnitName('player')
    local quantityString = ''
    local flags = criteria.flags or 0
    local assetId = criteria.assetId

    -- Fix achievement criterias not showing as completed
    if (reqQuantity == 0 and criteriaType == CRITERIA_TYPE_ACHIEVEMENT) then
        reqQuantity = 1
    end

    if (criteria) then
        if (pCriteria) then
            quantity = pCriteria.counter
        else
            quantity = 0
        end
        completed = pCriteria and quantity >= reqQuantity
        quantityString = quantity .. ' / ' .. reqQuantity
    end

    if ( bit.band(flags, ACHIEVEMENT_CRITERIA_FLAG_MONEY_COUNTER) == ACHIEVEMENT_CRITERIA_FLAG_MONEY_COUNTER ) then
        quantityString = getTextGSC(quantity, true, false)
        quantityString = quantityString .. ' / ' .. getTextGSC(reqQuantity, true, false)
    end

    return name, criteriaType, completed, quantity, reqQuantity, charName, flags, assetId, quantityString, criteriaId
    -- local achievement = GetAchievement(achievementID)
    -- if (achievement) then
    --     local criterias = achievement:GetCriteriasSorted()
    --     local criteriaCount = table.getn(criterias)
    --     if (criteriaIndex <= criteriaCount) then
    --         return _GetAchievementCriteria(achievementID, criterias[criteriaIndex])
    --     end
    -- end
    -- return _GetAchievementCriteria()
end

function GetAchievementCriteriaInfoByID(achievementID, criteriaID)
    -- local achievement = db:GetAchiev[ement(achievementID)
    -- if achievement then
    --     return _GetAchievementCriteria(achievementID, achievement:GetCriteria(criteriaID))
    -- end
    -- return _GetAchievementCriteria()
end

function GetAchievementNumCriteria(achievementID)
    local total = 0
    local achievement = GetAchievement(achievementID)
    if (achievement) then
        local criteriaList = achieverDB.criteria.byAchievement[achievementID]
        if (criteriaList) then
            for _, criteriaId in pairs(achieverDB.criteria.byAchievement[achievementID]) do
                local criteria = achieverDB.criteria.data[criteriaId];
                if (criteria) then
                    if (criteria.name) then total = total + 1 end
                end
            end
        end
    end
    return total
end

function ClearAchievementComparisonUnit()

end

function SetAchievementComparisonUnit(unit)

end

-- return completed, month, day, year
function GetAchievementComparisonInfo(id)
    -- local completion = cmanager:GetTarget()
    -- if not completion:IsAchievementCompleted(id) then
    --     return false, nil, nil, nil
    -- else
    --     local time = completion:GetAchievementCompletionTime(id)
    --     local month, day, year = tonumber(date('%m', time)), tonumber(date('%d', time)), tonumber(date('%y', time))
    --     return true, day, month, year
    -- end
end

function GetComparisonCategoryNumAchievements(categoryID, includeAll)
    -- local _, completed = GetCategoryNumAchievements(categoryID, includeAll, cmanager:GetTarget())
    -- return completed
end

function GetComparisonAchievementPoints()
    -- local points = 0
    -- local completion = cmanager:GetTarget()
    -- local tab = db:GetTab(db.TAB_ID_PLAYER)
    -- for _, category in pairs(tab:GetCategories()) do
    --     for _, achievement in pairs(category:GetAchievements()) do
    --         if completion:IsAchievementCompleted(achievement.id) then points = points + achievement.points end
    --     end
    -- end
    -- return points
end

function GetNumTrackedAchievements()
    return 0
end

local lastSearchResult = {}

function SetAchievementSearchString(text)
    -- text = string.lower(text)
    -- lastSearchResult = {}
    -- for _, category in pairs(db:GetSelectedTab():GetCategories()) do
    --     for _, ach in pairs(category:GetAchievements()) do
    --         if string.find(string.lower(ach.name), text) and IsAchievementVisible(ach) then lastSearchResult[#lastSearchResult + 1] = ach end
    --     end
    -- end
    -- local completion = cmanager:GetLocal()
    -- table.sort(lastSearchResult, function(a, b)
    --     local completedA, completedB = completion:IsAchievementCompleted(a.id), completion:IsAchievementCompleted(b.id)
    --     if completedA and completedB then return a.id < b.id end
    --     if completedA then return true end
    --     if completedB then return false end
    --     return a.id < b.id
    -- end)
    -- return true
end

function GetNumFilteredAchievements()
    return table.getn(lastSearchResult)
end

function GetFilteredAchievementID(index)
    return lastSearchResult[index].id
end
