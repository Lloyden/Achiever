local _G, _ = _G or getfenv()

ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.2.4'
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
local ACHIEVER_SYNC_RETRY_DELAY = 3

local function debug(msg)
    if achieverDBpc.debug == "enabled" then
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

Achiever.isReady = function(self)
    return ACHIEVER_READY
end

Achiever.updateReadyState = function(self)
    if (ACHIEVER_READY or not ACHIEVER_SYNC_COMPLETE.categories or
        not ACHIEVER_SYNC_COMPLETE.achievements or not ACHIEVER_SYNC_COMPLETE.criteria) then
        return
    end

    ACHIEVER_READY = true
    ACHIEVER_SYNC_RETRY_COUNT = 0
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
    ACHIEVER_SYNC_COMPLETE = {
        categories = false,
        achievements = false,
        criteria = false
    }

    if (ACHIEVER_SYNC_RETRY_COUNT >= ACHIEVER_MAX_SYNC_RETRIES) then
        ACHIEVER_SYNC_RETRY_AT = nil
        DEFAULT_CHAT_FRAME:AddMessage(
            '|cffff2020Achiever: malformed ' .. dataType ..
            ' data. Loading aborted after ' ..
            ACHIEVER_MAX_SYNC_RETRIES ..
            ' retries. Use /reload to try again.|r'
        )
        return
    end

    ACHIEVER_SYNC_RETRY_AT = GetTime() + ACHIEVER_SYNC_RETRY_DELAY

    DEFAULT_CHAT_FRAME:AddMessage(
        '|cffffa500Achiever: malformed ' .. dataType ..
        ' data. Loading aborted; automatic retry ' ..
        (ACHIEVER_SYNC_RETRY_COUNT + 1) .. '/' ..
        ACHIEVER_MAX_SYNC_RETRIES ..
        ' will start when the current transfer has stopped.|r'
    )
end

Achiever.retrySync = function(self)
    ACHIEVER_SYNC_RETRY_COUNT = ACHIEVER_SYNC_RETRY_COUNT + 1
    ACHIEVER_SYNC_RETRY_AT = nil
    ACHIEVER_SYNC_ABORTED = false
    ACHIEVER_READY = false

    ACHIEVER_SYNC_COMPLETE = {
        categories = false,
        achievements = false,
        criteria = false
    }

    -- Delete all partially downloaded server metadata.
    -- Per-character progress in achieverDBpc is preserved.
    self:ensureDataTables(true)

    local factionGroup = UnitFactionGroup('player')
    achieverDB.Alliance = factionGroup == 'Alliance'
    achieverDB.Horde = factionGroup == 'Horde'

    DEFAULT_CHAT_FRAME:AddMessage(
        '|cffffff00Achiever: retrying full data load (' ..
        ACHIEVER_SYNC_RETRY_COUNT .. '/' ..
        ACHIEVER_MAX_SYNC_RETRIES .. ').|r'
    )

    self:apiEnableDataSend(0)
end

Achiever.markSyncComplete = function(self, section, current, total)
    if (current and total and total > 0 and current == total) then
        ACHIEVER_SYNC_COMPLETE[section] = true
        self:updateReadyState()
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

        -- The active server transfer cannot be cancelled. Ignore its remaining
        -- metadata and retry when no more rows are arriving.
        if (ACHIEVER_SYNC_ABORTED and isMetadataMessage(params[2])) then
            if (ACHIEVER_SYNC_RETRY_COUNT < ACHIEVER_MAX_SYNC_RETRIES) then
                if (params[2] == 'CRV') then
                    -- CRV is the final marker in the metadata stream.
                    ACHIEVER_SYNC_RETRY_AT = GetTime() + 0.5
                else
                    ACHIEVER_SYNC_RETRY_AT =
                        GetTime() + ACHIEVER_SYNC_RETRY_DELAY
                end
            end

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
            local id = tonumber(a[1])
            local categoryId = tonumber(a[6])
            local order = tonumber(a[8])
            if (not id or not categoryId or not order) then
                warn('ignored malformed achievement data')
                return
            end
            local old = achieverDB.achievements.data[id]
            if (old) then
                achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints - (old.points or 0)
            end
            achieverDB.achievements.data[id] = {}
            achieverDB.achievements.data[id].id = tonumber(id)
            achieverDB.achievements.data[id].faction = tonumber(a[2])
            achieverDB.achievements.data[id].previousId = tonumber(a[3])
            local name = ''
            if (a[4] ~= '_') then name = a[4] end
            achieverDB.achievements.data[id].name = name
            local description = ''
            if (a[5] ~= '_') then description = a[5] end
            achieverDB.achievements.data[id].description = description
            achieverDB.achievements.data[id].categoryId = tonumber(a[6])
            achieverDB.achievements.data[id].points = tonumber(a[7]) or 0
            achieverDB.achievements.data[id].order = order
            achieverDB.achievements.data[id].flags = tonumber(a[9]) or 0
            achieverDB.achievements.data[id].icon = tonumber(a[10])
            local titleReward = ''
            if (a[11] ~= '_') then titleReward = a[11] end
            achieverDB.achievements.data[id].titleReward = titleReward
            achieverDB.achievements.data[id].count = tonumber(a[12])
            achieverDB.achievements.data[id].refAchievement = tonumber(a[13])
            achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints + (tonumber(a[7]) or 0)

            --local n = tonumber(a[14])
            --local c = tonumber(a[15])
            local a = split(params[3], ';')
            local fieldCount = table.getn(a)
            local id = tonumber(a[1])
            local categoryId = tonumber(a[6])
            local order = tonumber(a[8])
            local n = tonumber(a[14])
            local c = tonumber(a[15])

            if (fieldCount < 15 or not id or not categoryId or
                not order or not n or not c) then
                self:abortSync('achievement')
                return
            end

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
            ACHIEVER_SYNC_COMPLETE.achievements = true
            self:updateReadyState()
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
            ACHIEVER_SYNC_COMPLETE.categories = true
            self:updateReadyState()
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
            achieverDB.criteria.data[id] = {}
            achieverDB.criteria.data[id].id = tonumber(id)
            achieverDB.criteria.data[id].achievementId = tonumber(a[2])
            achieverDB.criteria.data[id].type = tonumber(a[3])
            achieverDB.criteria.data[id].assetId = tonumber(a[4])
            achieverDB.criteria.data[id].count = tonumber(a[5])
            achieverDB.criteria.data[id].assetId1 = tonumber(a[6])
            achieverDB.criteria.data[id].count1 = tonumber(a[7])
            achieverDB.criteria.data[id].assetId2 = tonumber(a[8])
            achieverDB.criteria.data[id].count2 = tonumber(a[9])
            local name = ''
            local encodedName = joinFields(a, 10, fieldCount - 7, ';')
            if (encodedName ~= '_') then name = encodedName end
            achieverDB.criteria.data[id].name = name
            achieverDB.criteria.data[id].flags = flags or 0
            achieverDB.criteria.data[id].timedType = timedType
            achieverDB.criteria.data[id].timerStartEvent = timerStartEvent
            achieverDB.criteria.data[id].timeLimit = timeLimit
            achieverDB.criteria.data[id].order = order

            if (achieverDB.criteria.byAchievement[achievementId] == nil) then
                achieverDB.criteria.byAchievement[achievementId] = {}
            end
            achieverDB.criteria.byAchievement[achievementId][order] = id
            -- table.insert(achieverDB.criteria.byAchievement[achievementId], id)
            self:markSyncComplete('criteria', n, c)
        elseif (params[2] == 'CRV') then
            debug('server response: criteria data version')
            achieverDB.criteria.version = tonumber(params[3])
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
    
    self:ensureDataTables(false)
    local factionGroup, localedFaction = UnitFactionGroup("player");

    if (not achieverDBpc.debug) then achieverDBpc.debug = "disabled" end
    if (not achieverDBpc.buttonsmall) then achieverDBpc.buttonsmall = "disabled"; Achiever_Minimap:Hide(); end
    if (not achieverDBpc.buttonmain) then achieverDBpc.buttonmain = "enabled" end
    if (not achieverDBpc.version) then achieverDBpc.version = 0 end

    achieverDB.Alliance = factionGroup == "Alliance"
    achieverDB.Horde = factionGroup == "Horde"
    -- The metadata database is rebuilt above, so asking with a cached version
    -- can make the server correctly send no rows and leave the client empty.
    -- Always request a complete snapshot.
    debug('request full data for UI')
    ACHIEVER_STARTED = true
    self:apiEnableDataSend(0)
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
        Achiever:startup()
	end
end)

Achiever:SetScript("OnUpdate", function()
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
