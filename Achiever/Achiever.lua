local _G, _ = _G or getfenv()

ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.6.0'
local ACHIEVER_ADDON_CHANNEL = 'ACHIEVER_CHANNEL'
local ACHIEVER_REQUESTED_DATA = false
local ACHIEVER_STARTED = false
local ACHIEVER_READY = false
local ACHIEVER_SYNC_COMPLETE = { categories = false, achievements = false, criteria = false }
local ACHIEVER_PENDING_ACHIEVEMENTS = {}
local ACHIEVER_PENDING_CRITERIA = {}
local ACHIEVER_SYNC_ABORTED = false
local ACHIEVER_SYNC_RETRY_AT = nil
local ACHIEVER_SYNC_RETRY_COUNT = 0
local ACHIEVER_MAX_SYNC_RETRIES = 3
local ACHIEVER_START_AT = nil
local ACHIEVER_LAST_METADATA_AT = nil
local ACHIEVER_RETRY_STAGE = nil
local ACHIEVER_NEXT_REQUEST = nil
local ACHIEVER_USING_CACHE = false
local ACHIEVER_EXPECTED_COUNTS = { categories = nil, achievements = nil, criteria = nil }
local ACHIEVER_FINALIZE_TIMEOUT = 10
local ACHIEVER_FALLBACK_USED = false

local function debug(msg)
    if achieverDBpc and achieverDBpc.debug == "enabled" then
	    DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff'.. (msg or 'nil'))
    end
end

local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end

local function toggleDebug()
    if achieverDBpc.debug == "enabled" then
        achieverDBpc.debug = "disabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode disabled')
    else
        achieverDBpc.debug = "enabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode enabled')
    end
end

SLASH_ACHIEVERDEBUG1 = "/acdebug"
SlashCmdList.ACHIEVERDEBUG = function()
    toggleDebug()
end

SLASH_ACHIEVERSYNC1 = "/achieversync"
SlashCmdList.ACHIEVERSYNC = function()
    DEFAULT_CHAT_FRAME:AddMessage(
        '|cffffff00Achiever: network metadata sync is disabled because the server sends it ' ..
        'synchronously and can freeze the client. Regenerate the faction data addon instead.|r')
end

Achiever = CreateFrame("Frame")

-- SavedVariables are not guaranteed to contain all fields (and old/corrupt
-- versions of the addon may have saved partial tables).  Never replace the
-- complete per-character database here; that used to erase progress/settings
-- during addon loading on some 1.12 clients.
achieverDBpc = achieverDBpc or {}
achieverDBpc.criteria = achieverDBpc.criteria or {}
achieverDBpc.achievements = achieverDBpc.achievements or {}
SLASH_RELOADUI1 = "/rl"
SlashCmdList.RELOADUI = ReloadUI

local function split(str, sep)
    if sep == nil then
        sep = '%s'
    end

    local res = {}
    local func = function(w)
        table.insert(res, w)
    end

    string.gsub(str, '[^'..sep..']+', func)
    return res
end

local function joinFields(fields, first, last, separator)
    local result = ''
    if (not first or not last or first > last) then return result end
    for i = first, last do
        if (i > first) then result = result .. separator end
        result = result .. (fields[i] or '')
    end
    return result
end

local function isMetadataMessage(messageType)
    return messageType == 'AC' or messageType == 'ACV' or
        messageType == 'CA' or messageType == 'CAV' or
        messageType == 'CR' or messageType == 'CRV'
end

Achiever:RegisterEvent("ADDON_LOADED")
Achiever:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Achiever:RegisterEvent("PLAYER_ENTERING_WORLD")
Achiever:RegisterEvent("VARIABLES_LOADED")


Achiever.version = ACHIEVER_ADDON_VERSION
Achiever.channel = ACHIEVER_ADDON_CHANNEL
Achiever.channelIndex = nil

Achiever.ensureDataTables = function(self, resetServerData)
    achieverDBpc = achieverDBpc or {}
    achieverDBpc.criteria = achieverDBpc.criteria or {}
    achieverDBpc.achievements = achieverDBpc.achievements or {}

    if (resetServerData or type(achieverDB) ~= "table") then achieverDB = {} end
    achieverDB.categories = achieverDB.categories or {}
    achieverDB.categories.data = achieverDB.categories.data or {}
    achieverDB.categories.byParent = achieverDB.categories.byParent or {}
    achieverDB.achievements = achieverDB.achievements or {}
    achieverDB.achievements.data = achieverDB.achievements.data or {}
    achieverDB.achievements.byCategory = achieverDB.achievements.byCategory or {}
    achieverDB.achievements.nextById = achieverDB.achievements.nextById or {}
    achieverDB.achievements.previousById = achieverDB.achievements.previousById or {}
    achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints or 0
    achieverDB.criteria = achieverDB.criteria or {}
    achieverDB.criteria.data = achieverDB.criteria.data or {}
    achieverDB.criteria.byAchievement = achieverDB.criteria.byAchievement or {}
end

Achiever.hasCompleteCache = function(self)
    local factionGroup = UnitFactionGroup('player')
    local factionMatches =
        (factionGroup == 'Alliance' and achieverDB and achieverDB.Alliance == true) or
        (factionGroup == 'Horde' and achieverDB and achieverDB.Horde == true)
    return type(achieverDB) == 'table' and
        factionMatches and
        type(achieverDB.sync) == 'table' and achieverDB.sync.complete == true and
        achieverDB.sync.embedded == true and tonumber(achieverDB.sync.version) == 1 and
        type(achieverDB.categories) == 'table' and type(achieverDB.categories.data) == 'table' and
        type(achieverDB.achievements) == 'table' and type(achieverDB.achievements.data) == 'table' and
        type(achieverDB.criteria) == 'table' and type(achieverDB.criteria.data) == 'table'
end

Achiever.loadFactionMetadata = function(self)
    local factionGroup = UnitFactionGroup('player')
    local dataAddon
    if (factionGroup == 'Alliance') then
        dataAddon = 'Achiever_Data_Alliance'
    elseif (factionGroup == 'Horde') then
        dataAddon = 'Achiever_Data_Horde'
    else
        return false, 'the player faction is not available yet'
    end

    -- Each faction database is a separate LoadOnDemand addon. This is the only
    -- way for the Vanilla client to avoid parsing both large Lua files during
    -- startup; files listed in Achiever.toc are always loaded unconditionally.
    ACHIEVER_EMBEDDED_DB = nil
    local loaded, reason = LoadAddOn(dataAddon)
    if (not loaded and not IsAddOnLoaded(dataAddon)) then
        return false, dataAddon .. ' could not be loaded' ..
            (reason and ' (' .. tostring(reason) .. ')' or '')
    end

    local embedded = ACHIEVER_EMBEDDED_DB
    ACHIEVER_EMBEDDED_DB = nil
    if (type(embedded) ~= 'table') then
        return false, dataAddon .. ' does not contain generated metadata'
    end

    achieverDB = embedded
    if (not self:hasCompleteCache()) then
        achieverDB = nil
        return false, dataAddon .. ' contains incomplete or wrong-faction metadata'
    end
    return true
end

Achiever.prepareFreshDatabase = function(self)
    self:ensureDataTables(true)
    achieverDB.sync = { complete = false }
    local factionGroup = UnitFactionGroup('player')
    achieverDB.Alliance = factionGroup == 'Alliance'
    achieverDB.Horde = factionGroup == 'Horde'
    ACHIEVER_EXPECTED_COUNTS = { categories = nil, achievements = nil, criteria = nil }
    ACHIEVER_FALLBACK_USED = false
end

local function countTableEntries(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

Achiever.validateSection = function(self, section)
    if (ACHIEVER_USING_CACHE) then return true end
    local expected = ACHIEVER_EXPECTED_COUNTS[section]

    local values
    if (section == 'categories') then values = achieverDB.categories.data end
    if (section == 'achievements') then values = achieverDB.achievements.data end
    if (section == 'criteria') then values = achieverDB.criteria.data end
    local received = countTableEntries(values)
    if (received < 1) then
        self:abortSync(section .. ' (no rows received)')
        return false
    end

    -- The row counter's total is global, while the server can filter rows for
    -- the player's faction/expansion. For example, receiving 696 of a global
    -- 811 achievements is valid. CAV/ACV/CRV are the authoritative completion
    -- markers; equality with the global total must not trigger a retry.
    debug('validated ' .. section .. ': ' .. received .. '/' ..
        (expected or '?') .. ' applicable rows')
    return true
end

Achiever.isReady = function(self)
    return ACHIEVER_READY
end

Achiever.updateReadyState = function(self)
    if (ACHIEVER_READY or not ACHIEVER_SYNC_COMPLETE.categories or
        not ACHIEVER_SYNC_COMPLETE.achievements or not ACHIEVER_SYNC_COMPLETE.criteria) then
        return
    end

    ACHIEVER_READY = true
    ACHIEVER_SYNC_ABORTED = false
    ACHIEVER_SYNC_RETRY_AT = nil
    ACHIEVER_RETRY_STAGE = nil
    ACHIEVER_SYNC_RETRY_COUNT = 0
    achieverDB.sync = achieverDB.sync or {}
    achieverDB.sync.complete = true
    achieverDB.sync.version = achieverDB.criteria.version or
        achieverDB.achievements.version or achieverDB.categories.version or 0
    achieverDBpc.version = achieverDB.sync.version
    DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00Achiever: data loaded. You can now open the achievement window.|r')

    -- Events can arrive while the definitions are still downloading.  Store
    -- their progress immediately, but update the UI/alerts only once it is safe.
    for id, _ in pairs(ACHIEVER_PENDING_ACHIEVEMENTS) do
        self:showAchievementEarned(id)
    end
    ACHIEVER_PENDING_ACHIEVEMENTS = {}
    for id, achievementId in pairs(ACHIEVER_PENDING_CRITERIA) do
        self:updateCriteriaUI(id, achievementId)
    end
    ACHIEVER_PENDING_CRITERIA = {}
end

Achiever.abortSync = function(self, dataType)
    if (ACHIEVER_SYNC_ABORTED) then return end

    ACHIEVER_SYNC_ABORTED = true
    ACHIEVER_READY = false
    ACHIEVER_LAST_METADATA_AT = GetTime()
    if (achieverDB and achieverDB.sync) then achieverDB.sync.complete = false end
    ACHIEVER_SYNC_COMPLETE = {
        categories = false,
        achievements = false,
        criteria = false
    }

    ACHIEVER_SYNC_RETRY_AT = nil
    DEFAULT_CHAT_FRAME:AddMessage(
        '|cffff2020Achiever: malformed ' .. dataType ..
        ' data. Network loading is disabled to protect client memory. ' ..
        'Regenerate the faction data addon.|r'
    )
end

Achiever.retrySync = function(self)
    DEFAULT_CHAT_FRAME:AddMessage(
        '|cffffff00Achiever: network retry is disabled. Regenerate the faction data addon instead.|r'
    )
end

Achiever.markSyncComplete = function(self, section, current, total)
    -- Row counters are useful progress information but are not transaction
    -- boundaries. Only CAV/ACV/CRV may mark a section complete; otherwise the
    -- UI can become ready before the version/final row reaches the client.
    if (current and total and total > 0) then
        ACHIEVER_EXPECTED_COUNTS[section] = total
    end
    if (current and total and total > 0 and current == total) then
        debug('received final ' .. section .. ' row; waiting for version marker')
    end
end

Achiever.showAchievementEarned = function(self, id)
    local achievement = achieverDB and achieverDB.achievements and
        achieverDB.achievements.data and achieverDB.achievements.data[id]
    if (not achievement) then
        ACHIEVER_PENDING_ACHIEVEMENTS[id] = true
        return
    end
    if (AchievementFrameAchievements_OnEvent and _G['AchievementFrameAchievements']) then
        AchievementFrameAchievements_OnEvent(_G['AchievementFrameAchievements'], 'ACHIEVEMENT_EARNED', id)
    end
    for _, frame in pairs(self.achievementFrameSummaryCategorySubscribers or {}) do
        if (AchievementFrameSummaryCategory_OnEvent) then
            AchievementFrameSummaryCategory_OnEvent(frame, 'ACHIEVEMENT_EARNED', id)
        end
    end
    if (AchievementFrameSummary_Update) then AchievementFrameSummary_Update() end
    debug("ACHIEVEMENT EARNED " .. (achievement.name or tostring(id)))
    if (AlertFrame_ShowAchievementEarned) then AlertFrame_ShowAchievementEarned(id) end
end

Achiever.updateCriteriaUI = function(self, id, achievementId)
    local achievement = achieverDB and achieverDB.achievements and
        achieverDB.achievements.data and achieverDB.achievements.data[achievementId]
    local criteria = achieverDB and achieverDB.criteria and
        achieverDB.criteria.data and achieverDB.criteria.data[id]
    if (not achievement or not criteria) then
        ACHIEVER_PENDING_CRITERIA[id] = achievementId
        return
    end
    if (AchievementFrameAchievements_OnEvent and _G['AchievementFrameAchievements']) then
        AchievementFrameAchievements_OnEvent(_G['AchievementFrameAchievements'], 'CRITERIA_UPDATE', id)
    end
    if (AchievementFrameStats_OnEvent and _G['AchievementFrameStats']) then
        AchievementFrameStats_OnEvent(_G['AchievementFrameStats'], 'CRITERIA_UPDATE', id)
    end
    debug("ACHIEVEMENT CRITERIA UPDATE " .. (achievement.name or tostring(achievementId)) ..
        '[' .. (criteria.name or tostring(id)) .. ']')
end

Achiever.hookChatFrame = function(self, frame)
    if (not frame) then
        warn('Achiever failed to hook chat frame')
        return
    end

    if (frame.achieverHooked) then return end
    local original = frame.AddMessage
    if (original) then
        frame.AddMessage = function(t, message, ...)
            local s, e
            if (type(message) == 'string') then
                s, e = string.find(message, 'ACHI#', 1, true)
            end
            if (s == 1 and e == 5) then
                -- The server already sends one packet per row. Do not copy the
                -- entire burst into a second Lua queue: on the 1.12 client that
                -- doubles peak memory and can crash before CRV is received.
                self:processServerMessage(message)
                return false --hide this message
            end
            original(t, message, unpack(arg))
        end
        frame.achieverHooked = true
    else
        warn('failed to hook non-chat frame.')
    end
end

Achiever.achievementFrameSummaryCategorySubscribers = {}

Achiever.processServerMessage = function(self, message)
    if (type(message) ~= 'string') then return end
    self:ensureDataTables(false)
    local params = split(message, '#')
    if (params[1] == 'ACHI') then
        if (not params[2]) then return end

        if (isMetadataMessage(params[2])) then
            ACHIEVER_LAST_METADATA_AT = GetTime()
            -- Metadata is never accepted over chat in 0.6.0. A full response
            -- is synchronous on the world thread and was the source of the
            -- frozen sessions and memory crashes. Only generated data is used.
            return
        end

        -- The active server transfer cannot be cancelled. Ignore its remaining
        -- metadata. Never start another automatic transfer: the original
        -- synchronous burst may already have pushed the client near its limit.
        if (ACHIEVER_SYNC_ABORTED and isMetadataMessage(params[2])) then
            return
        end
        if ((params[2] == 'AC' or params[2] == 'CA' or params[2] == 'CR' or
            params[2] == 'CH_AC' or params[2] == 'CH_CR' or
            params[2] == 'AE' or params[2] == 'ACU') and not params[3]) then

            if (params[2] == 'AC' or params[2] == 'CA' or
                params[2] == 'CR') then
                self:abortSync(params[2])
                return
            end

            warn('ignored incomplete server message (' .. params[2] .. ')')
            return
        end
        if (params[2] == 'AC') then
            --debug('server response: new achievement entry ')
            local a = split(params[3], ';')
            local fieldCount = table.getn(a)
            local id = tonumber(a[1])
            local categoryId = tonumber(a[6])
            local order = tonumber(a[8])
            local n = tonumber(a[14])
            local c = tonumber(a[15])
            if (fieldCount ~= 15 or not id or not categoryId or
                not order or not n or not c) then
                self:abortSync('achievement')
                return
            end
            local old = achieverDB.achievements.data[id]
            if (old) then
                achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints - (old.points or 0)
            end
            achieverDB.achievements.data[id] = {}
            achieverDB.achievements.data[id].id = id
            local name = ''
            if (a[4] ~= '_') then name = a[4] end
            achieverDB.achievements.data[id].name = name
            local description = ''
            if (a[5] ~= '_') then description = a[5] end
            achieverDB.achievements.data[id].description = description
            achieverDB.achievements.data[id].categoryId = categoryId
            achieverDB.achievements.data[id].points = tonumber(a[7]) or 0
            achieverDB.achievements.data[id].order = order
            achieverDB.achievements.data[id].flags = tonumber(a[9]) or 0
            achieverDB.achievements.data[id].icon = tonumber(a[10])
            local titleReward = ''
            if (a[11] ~= '_') then titleReward = a[11] end
            achieverDB.achievements.data[id].titleReward = titleReward
            achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints + (tonumber(a[7]) or 0)

            if (achieverDB.achievements.byCategory[categoryId] == nil) then
                achieverDB.achievements.byCategory[categoryId] = {}
            end
            -- table.insert(achieverDB.achievements.byCategory[categoryId], id)
            achieverDB.achievements.byCategory[categoryId][order] = id

            local previousId = tonumber(a[3])
            if (previousId == 0) then previousId = nil end
            if (previousId) then
                achieverDB.achievements.previousById[id] = previousId
                achieverDB.achievements.nextById[previousId] = id
            end

            self:markSyncComplete('achievements', n, c)

        elseif (params[2] == 'ACV') then
            debug('server response: achievement data version')
            achieverDB.achievements.version = tonumber(params[3])
            if (not self:validateSection('achievements')) then return end
            ACHIEVER_SYNC_COMPLETE.achievements = true
            self:updateReadyState()
            if (ACHIEVER_RETRY_STAGE == 'achievements' and not ACHIEVER_SYNC_ABORTED) then
                ACHIEVER_RETRY_STAGE = 'criteria'
                ACHIEVER_NEXT_REQUEST = { at = GetTime() + 0.5, section = 'criteria' }
            end
        elseif (params[2] == 'CA') then
            --debug('server response: get all categories')
            local a = split(params[3], ";")
            local fieldCount = table.getn(a)
            local id = tonumber(a[1])
            local order = tonumber(a[fieldCount - 2])
            local n = tonumber(a[fieldCount - 1])
            local c = tonumber(a[fieldCount])
            if (fieldCount < 6 or not id or not order or not n or not c) then
                --warn('ignored malformed category data')
                self:abortSync('category')
                return
            end
            achieverDB.categories.data[id] = {}
            achieverDB.categories.data[id].id = tonumber(id)
            achieverDB.categories.data[id].parentId = tonumber(a[2])
            local name = ''
            local encodedName = joinFields(a, 3, fieldCount - 3, ';')
            if (encodedName ~= '_') then name = encodedName end
            achieverDB.categories.data[id].name = name
            achieverDB.categories.data[id].order = order

            local parentId = a[2]
            if (achieverDB.categories.byParent[parentId] == nil) then
                achieverDB.categories.byParent[parentId] = {}
            end
            -- table.insert(achieverDB.categories.byParent[parentId], id)
            achieverDB.categories.byParent[parentId][order] = id
            self:markSyncComplete('categories', n, c)
        elseif (params[2] == 'CAV') then
            debug('server response: category data version')
            achieverDB.categories.version = tonumber(params[3])
            if (not self:validateSection('categories')) then return end
            ACHIEVER_SYNC_COMPLETE.categories = true
            self:updateReadyState()
            if (ACHIEVER_RETRY_STAGE == 'categories' and not ACHIEVER_SYNC_ABORTED) then
                ACHIEVER_RETRY_STAGE = 'achievements'
                ACHIEVER_NEXT_REQUEST = { at = GetTime() + 0.5, section = 'achievements' }
            end
        elseif (params[2] == 'CR') then
            --debug('server response: get all criteria')
            local a = split(params[3], ";")
            local fieldCount = table.getn(a)
            local id = tonumber(a[1])
            local achievementId = tonumber(a[2])
            -- Criteria names are sent as unescaped text.  They may themselves
            -- contain semicolons, so read the seven numeric fields from the
            -- right-hand end instead of assuming that the name is one field.
            local flags = tonumber(a[fieldCount - 6])
            local timedType = tonumber(a[fieldCount - 5])
            local timerStartEvent = tonumber(a[fieldCount - 4])
            local timeLimit = tonumber(a[fieldCount - 3])
            local order = tonumber(a[fieldCount - 2])
            local n = tonumber(a[fieldCount - 1])
            local c = tonumber(a[fieldCount])
            if (fieldCount < 17 or not id or not achievementId or not order or not n or not c) then
                --warn('ignored malformed criteria data')
                self:abortSync('criteria')
                return
            end

            -- The module sends every WotLK criteria row, even on a Classic
            -- realm. Keep only criteria belonging to an achievement actually
            -- delivered for this faction/patch. This removes thousands of
            -- unreachable tables from the Vanilla client's small Lua heap.
            if (not achieverDB.achievements.data[achievementId]) then
                self:markSyncComplete('criteria', n, c)
                return
            end
            achieverDB.criteria.data[id] = {}
            achieverDB.criteria.data[id].id = id
            achieverDB.criteria.data[id].achievementId = achievementId
            achieverDB.criteria.data[id].type = tonumber(a[3])
            achieverDB.criteria.data[id].assetId = tonumber(a[4])
            achieverDB.criteria.data[id].count = tonumber(a[5])
            local name = ''
            local encodedName = joinFields(a, 10, fieldCount - 7, ';')
            if (encodedName ~= '_') then name = encodedName end
            achieverDB.criteria.data[id].name = name
            achieverDB.criteria.data[id].flags = flags or 0

            if (achieverDB.criteria.byAchievement[achievementId] == nil) then
                achieverDB.criteria.byAchievement[achievementId] = {}
            end
            achieverDB.criteria.byAchievement[achievementId][order] = id
            -- table.insert(achieverDB.criteria.byAchievement[achievementId], id)
            self:markSyncComplete('criteria', n, c)
        elseif (params[2] == 'CRV') then
            debug('server response: criteria data version')
            achieverDB.criteria.version = tonumber(params[3])
            if (not self:validateSection('criteria')) then return end
            ACHIEVER_SYNC_COMPLETE.criteria = true
            self:updateReadyState()
        elseif (params[2] == 'CH_AC') then
            --debug('server response: char achievements')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (id) then
                achieverDBpc.achievements[id] = {}
                achieverDBpc.achievements[id].date = tonumber(a[2]) or 0
            end
        elseif (params[2] == 'CH_CR') then
            --debug('server response: char criteria')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (id) then
                achieverDBpc.criteria[id] = {}
                achieverDBpc.criteria[id].counter = tonumber(a[2]) or 0
                achieverDBpc.criteria[id].date = tonumber(a[3]) or 0
            end
        elseif (params[2] == 'AE') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (not achieverDBpc.achievements) then achieverDBpc.achievements = {} end
            if (not id) then return end
            achieverDBpc.achievements[id] = {}
            achieverDBpc.achievements[id].date = tonumber(a[2]) or 0
            if (ACHIEVER_READY) then
                self:showAchievementEarned(id)
            else
                ACHIEVER_PENDING_ACHIEVEMENTS[id] = true
            end
        elseif (params[2] == 'ACU') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (not achieverDBpc.criteria) then achieverDBpc.criteria = {} end
            if (not id) then return end
            local achievementId = tonumber(a[2])
            achieverDBpc.criteria[id] = {}
            achieverDBpc.criteria[id].achievementId = tonumber(a[2])
            achieverDBpc.criteria[id].counter = tonumber(a[3]) or 0
            achieverDBpc.criteria[id].date = tonumber(a[4]) or 0
            if (ACHIEVER_READY) then
                self:updateCriteriaUI(id, achievementId)
            else
                ACHIEVER_PENDING_CRITERIA[id] = achievementId
            end
        else
            warn('server response: unhandled ' .. params[2])
        end
    end
end

Achiever.apiEnableDataSend = function(self, version)

    debug('request to enable sending achievement info, ' .. version)
    SendChatMessage('.achievements enableAchiever ' .. version)
    --SendChatMessage('!achievements getCategoties ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCategoryInfo = function(self, version)

    --debug('requested information about categories from server, ' .. version)
    SendChatMessage('.achievements getCategories ' .. version)
    --SendChatMessage('!achievements getCategoties ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestAchievementInfo = function(self, version)

    --debug('requested information about achievements from server, ' .. version)
    SendChatMessage('.achievements getAchievements ' .. version)
    --SendChatMessage('!achievements getAchievements ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCriteriaInfo = function(self, version)

    --debug('requested information about criteria from server, ' .. version)
    SendChatMessage('.achievements getCriteria ' .. version)
    --SendChatMessage('!achievements getCriteria ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCharacterCriteria = function(self)
    debug('requested character criteria progress from server')
    achieverDBpc.criteria = {}
    SendChatMessage('.achievements getCharacterCriteria')
    --SendChatMessage('!achievements getCharacterCriteria', 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCharacterAchievements = function(self)
    debug('requested character achievements from server')
    achieverDBpc.achievements = {}
    SendChatMessage('.achievements getCharacterAchievements')
    --SendChatMessage('.achievements getCharacterAchievements', 'CHANNEL', nil, Achiever.channelIndex)
end

Achiever.getChannelIndex = function(self, channelName)
    local lastVal = 0
    local chanList = { GetChannelList() }
    local result = nil
    for _, value in next, chanList do
        if value == channelName then
            result = lastVal
            break
        end
        lastVal = value
    end
    return result
end

Achiever.joinChannel = function(self)
    self.channelIndex = self:getChannelIndex(self.channel)
    if (self.channelIndex == nil) then
        JoinChannelByName(self.channel)
    else
        --self:startup()
    end
end

Achiever.startup = function(self)
    if (ACHIEVER_STARTED == true) then
        return
    end
    
    local factionGroup, localedFaction = UnitFactionGroup("player");

    if (not achieverDBpc.debug) then achieverDBpc.debug = "disabled" end
    if (not achieverDBpc.buttonsmall) then achieverDBpc.buttonsmall = "disabled"; Achiever_Minimap:Hide(); end
    if (not achieverDBpc.buttonmain) then achieverDBpc.buttonmain = "enabled" end
    if (not achieverDBpc.version) then achieverDBpc.version = 0 end

    local metadataLoaded, metadataError = self:loadFactionMetadata()
    local requestVersion = 1
    if (metadataLoaded) then
        ACHIEVER_USING_CACHE = true
        ACHIEVER_READY = true
        ACHIEVER_SYNC_COMPLETE = { categories = true, achievements = true, criteria = true }
        requestVersion = tonumber(achieverDB.sync.version) or 0
        DEFAULT_CHAT_FRAME:AddMessage('|cff00ff00Achiever: ' .. factionGroup ..
            ' metadata loaded; checking the server version.|r')
    else
        ACHIEVER_STARTED = true
        DEFAULT_CHAT_FRAME:AddMessage(
            '|cffff2020Achiever: faction metadata is missing: ' ..
            (metadataError or 'unknown error') .. '. Network sync was not started. ' ..
            'Generate and install the matching Achiever_Data faction addon.|r')
        return
    end

    achieverDB.Alliance = factionGroup == "Alliance"
    achieverDB.Horde = factionGroup == "Horde"
    -- The server will now send the complete progress snapshot (but no
    -- metadata). Clear stale per-character rows before receiving it.
    achieverDBpc.criteria = {}
    achieverDBpc.achievements = {}
    debug('enable addon data; client version ' .. requestVersion)
    ACHIEVER_STARTED = true
    self:apiEnableDataSend(requestVersion)
end



Achiever:SetScript("OnEvent", function()
    if (not event) then
        warn('OnEvent with no event')
		return
	elseif (event == "ADDON_LOADED" and arg1 == ACHIEVER_ADDON_NAME) then
		debug('ADDON_LOADED')
		Achiever:hookChatFrame(ChatFrame1)
		Achiever:ensureDataTables(false)
	elseif (event == 'CHAT_MSG_CHANNEL_LEAVE') then
        debug('OnEvent CHAT_MSG_CHANNEL_LEAVE')
	elseif (event == 'CHAT_MSG_ADDON') then
        debug('OnEvent CHAT_MSG_ADDON')
    elseif (event == 'VARIABLES_LOADED') then
        debug('VARIABLES_LOADED')
	elseif (event == 'PLAYER_ENTERING_WORLD') then
        Achiever:hookChatFrame(ChatFrame1)
        -- Let the world, SavedVariables and chat system settle before asking
        -- the server to emit a large response.
        if (not ACHIEVER_STARTED and not ACHIEVER_START_AT) then
            ACHIEVER_START_AT = GetTime() + 2
        end
	end
end)

Achiever:SetScript("OnUpdate", function()
    if (ACHIEVER_START_AT and GetTime() >= ACHIEVER_START_AT) then
        ACHIEVER_START_AT = nil
        Achiever:startup()
    end

    -- The server sends completion markers, but a single lost chat packet must
    -- not leave the addon loading forever. Once the synchronous stream has
    -- been quiet for ten seconds, a non-empty metadata set is safe to commit.
    if (ACHIEVER_STARTED and not ACHIEVER_READY and not ACHIEVER_SYNC_ABORTED and
        not ACHIEVER_USING_CACHE and not ACHIEVER_FALLBACK_USED and
        ACHIEVER_LAST_METADATA_AT and
        GetTime() - ACHIEVER_LAST_METADATA_AT >= ACHIEVER_FINALIZE_TIMEOUT) then

        local categoryCount = countTableEntries(achieverDB.categories.data)
        local achievementCount = countTableEntries(achieverDB.achievements.data)
        local criteriaCount = countTableEntries(achieverDB.criteria.data)
        if (categoryCount > 0 and achievementCount > 0 and criteriaCount > 0) then
            ACHIEVER_FALLBACK_USED = true
            achieverDB.categories.version = tonumber(achieverDB.categories.version) or 1
            achieverDB.achievements.version = tonumber(achieverDB.achievements.version) or 1
            achieverDB.criteria.version = tonumber(achieverDB.criteria.version) or 1
            if (achieverDB.categories.version < 1) then achieverDB.categories.version = 1 end
            if (achieverDB.achievements.version < 1) then achieverDB.achievements.version = 1 end
            if (achieverDB.criteria.version < 1) then achieverDB.criteria.version = 1 end
            ACHIEVER_SYNC_COMPLETE = { categories = true, achievements = true, criteria = true }
            DEFAULT_CHAT_FRAME:AddMessage('|cffffff00Achiever: completion marker was missed; using the received data.|r')
            Achiever:updateReadyState()
        end
    end

    if (ACHIEVER_NEXT_REQUEST and GetTime() >= ACHIEVER_NEXT_REQUEST.at) then
        local section = ACHIEVER_NEXT_REQUEST.section
        ACHIEVER_NEXT_REQUEST = nil
        if (section == 'achievements') then
            Achiever:apiRequestAchievementInfo(0)
        elseif (section == 'criteria') then
            Achiever:apiRequestCriteriaInfo(0)
        end
    end

    if (ACHIEVER_SYNC_ABORTED and ACHIEVER_SYNC_RETRY_AT and
        GetTime() >= ACHIEVER_SYNC_RETRY_AT) then
        Achiever:retrySync()
    end
end)

NEWBIE_TOOLTIP_ACHIEVEMENT = "View information about your achievements and statistics.";
TOGGLEACHIEVEMENTS = 'Open Achievements';
BINDING_HEADER_ACHIEVER = "Achiever";
BINDING_NAME_TOGGLEACHIEVEMENTS = "Show Achievements";

function AchievementsMicroButton_OnLoad()
    this:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    this:RegisterEvent("PLAYER_LEVEL_UP");
    this:RegisterEvent("UPDATE_BINDINGS");
    this:RegisterEvent("UNIT_LEVEL");
    this:RegisterEvent("PLAYER_ENTERING_WORLD");
    this:SetNormalTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Up");
    this:SetPushedTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Down");
    this:SetDisabledTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Disabled");
    this:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight");
    this:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    if ( GetBindingKey("TOGGLEACHIEVEMENTS") ) then
        this.tooltipText = "Achievements".." "..NORMAL_FONT_COLOR_CODE.."("..GetBindingKey("TOGGLEACHIEVEMENTS")..")"..FONT_COLOR_CODE_CLOSE;
    else
        this.tooltipText = "Achievements";
    end
    this.newbieText = NEWBIE_TOOLTIP_ACHIEVEMENT;
end

function AchievementsMicroButton_OnEvent()
    if ( event == "PLAYER_LEVEL_UP" ) then
        UpdateAchievementsButton();
    elseif ( event == "UNIT_LEVEL" or event == "PLAYER_ENTERING_WORLD" ) then
        UpdateAchievementsButton();
    elseif ( event == "UPDATE_BINDINGS" ) then
        if ( GetBindingKey("TOGGLEACHIEVEMENTS") ) then
            this.tooltipText = "Achievements".." "..NORMAL_FONT_COLOR_CODE.."("..GetBindingKey("TOGGLEACHIEVEMENTS")..")"..FONT_COLOR_CODE_CLOSE;
        else
            this.tooltipText = "Achievements";
        end
    end
end

function UpdateAchievementsButton()
    -- move nearby buttons
    if ( UnitLevel("player") < 10 ) then
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
        QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -2, 0);
    else
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
        --QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -2, 0);
    end
    -- hide help button to free up space
    HelpMicroButton:Hide();
    QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -3, 0);

    -- Update main bar button
    if ( AchievementFrame:IsShown() ) then
        AchievementsMicroButton:SetButtonState("PUSHED", 1);
        SetButtonPulse(AchievementsMicroButton, 0, 1);
    else
        AchievementsMicroButton:SetButtonState("NORMAL");
    end

    if achieverDBpc.buttonsmall == "disabled" then
        Achiever_Minimap:Hide();
    end
end

local function toggleMainButton()
    if achieverDBpc.buttonmain == "enabled" then
        achieverDBpc.buttonmain = "disabled"
        AchievementsMicroButton:Hide();
        HelpMicroButton:Show();
        if ( UnitLevel("player") < 10 ) then
            QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
        else
            QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
        end
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button disabled')
    else
        achieverDBpc.buttonmain = "enabled"
        AchievementsMicroButton:Show();
        UpdateAchievementsButton();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button enabled')
    end
end

local function toggleSmallButton()
    if achieverDBpc.buttonsmall == "enabled" then
        achieverDBpc.buttonsmall = "disabled"
        Achiever_Minimap:Hide();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button disabled')
    else
        achieverDBpc.buttonsmall = "enabled"
        Achiever_Minimap:Show();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button enabled')
    end
end

SLASH_ACHIEVERBUTTONMAIN1 = "/acbuttonmain"
SlashCmdList.ACHIEVERBUTTONMAIN = function()
    toggleMainButton()
end

SLASH_ACHIEVERBUTTONSMALL1 = "/acbuttonsmall"
SlashCmdList.ACHIEVERBUTTONSMALL = function()
    toggleSmallButton()
end
