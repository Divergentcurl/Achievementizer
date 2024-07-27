std = "lua51"
max_line_length = 250

ignore = {
    "21./_.*", -- Unused local or loop variable or argument prefixed with _
    "212/self", -- Unused argument 'self'
    "432/self", -- Shadowing upvalue argument 'self'
}

globals = {
    -- own database
	"AchievementizerData",

    -- other own global vars
    "AchievementFrameCategory_StatusBarTooltip_AI",
    "AchievementFrame_OnShow_AI",

    -- slash commands
    "SLASH_AI1",
    "SlashCmdList",

    -- wow globals that need to be slightly mutated
    "AchievementFrameCategory_StatusBarTooltip",
    "AchievementFrame_OnShow",
}

read_globals = {
    -- general functions / objects
	"bit",
    "C_Timer",
    "CreateFrame",
    "GetMouseFoci",
    "GetServerTime",
    "GetTime",
    "IsAltKeyDown",
    "IsShiftKeyDown",
    "max",
    "min",
    "random",
    "strsplit",

    -- wow global vars
    "ACHIEVEMENT_FLAGS_ACCOUNT",
    "ACHIEVEMENT_TITLE",
    "EVALUATION_TREE_FLAG_PROGRESS_BAR",

    -- wow functions / objects
    "AchievementFrame",
    "AchievementFrameBaseTab_OnClick",
    "AchievementFrameComparisonTab_OnClick",
    "AchievementFrame_LoadUI",
    "C_ContentTracking",
    "ClearAchievementComparisonUnit",
    "Enum",
    "FauxScrollFrame_GetOffset",
    "FauxScrollFrame_OnVerticalScroll",
    "FauxScrollFrame_Update",
    "GameTooltip",
    "GetAchievementCategory",
    "GetAchievementComparisonInfo",
    "GetAchievementCriteriaInfo",
    "GetAchievementInfo",
    "GetAchievementLink",
    "GetAchievementNumCriteria",
    "GetCategoryInfo",
    "GetCategoryList",
    "GetCategoryNumAchievements",
    "GetComparisonAchievementPoints",
    "GetNextAchievement",
    "GetNumGroupMembers",
    "GetPreviousAchievement",
    "GetTotalAchievementPoints",
    "IsInRaid",
    "OpenAchievementFrameToAchievement",
    "SetAchievementComparisonUnit",
    "UIParent",
    "UnitFactionGroup",
    "UnitGUID",
    "UnitIsPlayer",
    "UnitIsUnit",
}