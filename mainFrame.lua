-- arguments to the file
local _addonName, namespace = ...

local frameFactory = namespace.frameFactory

-- get the database from the namespace
local database = namespace.database

-- UI settings
local mainFrameWidth = 600
local mainFrameHeight = 600

-- create the main frame of this addon
local mainFrame = frameFactory:createFrame(mainFrameWidth, mainFrameHeight)

-- make the main frame available to other files in this addon
namespace.mainFrame = mainFrame

function mainFrame:showAchievements(achievements)
	self:clearTexts()

	for _, achievement in pairs(achievements) do
		-- get correct color and achievement link and adjust the latter's color
		local color = database:getAchievementColor(achievement.completedByPercentage)
		local achievementLink = GetAchievementLink(achievement.id):gsub("ffffff00", color, 1)
		local parentCategoryText = achievement.parentCategoryTitle

		if parentCategoryText ~= "" then
			parentCategoryText = parentCategoryText .. ">"
		end

		self:addText("|c" .. color .. parentCategoryText .. achievement.categoryTitle .. ">|r" .. achievementLink.. "|c" .. color .. "(" .. achievement.completedByPercentage .. "%)|r")
	end

	self:Show()
end

-- enable hyperlinks and use default Blizzard handler
mainFrame:SetHyperlinksEnabled(true)
mainFrame:SetScript("OnHyperlinkClick", function(_self, link, _text, button)
	local _, achievementId = strsplit(":", link)

	if button == "LeftButton" then
		OpenAchievementFrameToAchievement(tonumber(achievementId))
	elseif button == "RightButton" then
		-- add to list
		C_ContentTracking.StartTracking(Enum.ContentTrackingType.Achievement, tonumber(achievementId))
	end
end)
