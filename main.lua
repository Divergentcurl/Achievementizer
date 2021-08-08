-- arguments to the file
local addonName, namespace = ...

-- get the frames and database and round function from the namespace
local todoFrame = namespace.todoFrame
local mainFrame = namespace.mainFrame
local database = namespace.database
local round = namespace.round

-- workaround to get factions in event
local tempFactionPool = {}

-- scan pool with (stack) CRUD
local scanPool = {}
local function addToScanPool(unitId)
	table.insert(scanPool, unitId)
end

-- remove a unitId from the scan pool if there is one and return it, otherwise nil
local function removeFromScanPool()
	if #scanPool > 0 then
		return table.remove(scanPool)
	end

	return nil
end

local lastScanned = nil
local function scanPlayerMaybe(unitId)
	local scanNow = false

	while unitId ~= nil do
		if UnitIsPlayer(unitId) and not UnitIsUnit(unitId, "player") then
			-- only scan if unit is player, but not self

			local playerGuid = UnitGUID(unitId)

			if playerGuid ~= nil and AchievementizerData.scanned[playerGuid] == nil then
				-- not scanned before, scan now or later
				if lastScanned == nil or GetServerTime() - lastScanned > 0 then
					-- 1 second or more has elapsed since the last scan, scan now
					scanNow = true
					--print("scan now", unitId)

					-- put faction in temporary pool so we can move it out later in the scanned event
					tempFactionPool[playerGuid] = UnitFactionGroup(unitId)
				else
					-- too soon, Executus! Store in pool to scan later
					addToScanPool(unitId)
					--print("scan later", lastScanned, GetServerTime(), unitId, #scanPool)
				end

				break
			else
				-- player scanned before or no guid found, see if we have a unitId in the pool left
				--print("scanned before or not found", unitId)
				unitId = removeFromScanPool()
				--print("Removed from pool1", unitId, #scanPool)
			end
		else
			-- is self or not a player, see if we have a unitId in the pool left
			--print("self or not player", unitId)
			unitId = removeFromScanPool()
			--print("Removed from pool2", unitId, #scanPool)
		end
	end

	if scanNow then
		-- fix Blizzard errors when scanning players by ensuring that selectedCategory has a numeric value (the same as during a comparison, see Blizzard_AchievementUI.lua)
		if ACHIEVEMENT_FUNCTIONS.selectedCategory == "summary" then
			ACHIEVEMENT_FUNCTIONS.selectedCategory = -1
		end

		ClearAchievementComparisonUnit()

		local success = SetAchievementComparisonUnit(unitId)
		--print("SetAchievementComparisonUnit", success)

		lastScanned = GetServerTime()

		if not success then
			-- restore of: fix Blizzard errors when scanning players
			if ACHIEVEMENT_FUNCTIONS.selectedCategory == -1 then
				ACHIEVEMENT_FUNCTIONS.selectedCategory = "summary"
			end

			addToScanPool(unitId)
		end
	else
		-- cannot scan now, maybe there is something we can scan later
		unitId = removeFromScanPool()

		if unitId ~= nil then
			C_Timer.After(1, function() scanPlayerMaybe(unitId) end)
		end
	end
end

local function adjustPlayerToolTipMaybe(playerGuidMaybe)
	local numLines = GameTooltip:NumLines()
	local gameTooltipText

	if numLines > 0 then
		gameTooltipText = _G["GameTooltipTextLeft"..numLines]:GetText()

		if gameTooltipText == "PvP" then
			gameTooltipText = _G["GameTooltipTextLeft"..(numLines-1)]:GetText()
		end
	end

	if gameTooltipText == "Alliance" or gameTooltipText == "Horde" then
		-- player tooltip, no points added yet, add points if possible

		local points = nil
		local isPlayer = UnitIsUnit("mouseover", "player")
		local hideLater = false

		if isPlayer then
			points = GetTotalAchievementPoints()
		else
			local playerGuid = UnitGUID("mouseover")

			if playerGuid == nil then
				-- no longer mouseover of a player, maybe a guid was provided by an event
				playerGuid = playerGuidMaybe
				hideLater = true
			end

			if AchievementizerData.scanned[playerGuid] ~= nil then
				points = AchievementizerData.scanned[playerGuid].points
			end
		end

		if points ~= nil then
			local sampleSummary = database:getSampleSummary(points, isPlayer)
			local colors = database:getAchievementColors(sampleSummary.rankPercentage)

			GameTooltip:AddLine("Points: ".. points .. " (top " .. sampleSummary.rankPercentage .. "%)", colors.r, colors.g, colors.b)
			GameTooltip:Show() -- call show to grow the tooltip so the new line fits

			-- changing the tooltip after hovering over someone has the side effect of cancelling the fade out (which means it stays up indefinitely)
			-- instead we leave it up for a bit and then abruptly hide it (we can't trigger the fade out manually)
			if hideLater then
				--print("hiding")
				C_Timer.After(1, function() GameTooltip:Hide() end)
			end
		end
	end
end

-- adjusts the tooltip for an achievement category to also show the information we have in this addon
local function adjustAchievementCategoryTooltip(self, adjustTitleText)
	-- add a percentage to the title
	if adjustTitleText then
		_G["GameTooltipTextLeft1"]:SetText(_G["GameTooltipTextLeft1"]:GetText() .. " (" .. round(100 * self.numCompleted / self.numAchievements) .. "%)")
	end

	-- prepare the database query
	local faction = database:convertTitleToFaction(UnitFactionGroup("player"))
	local isChildCategory = type(self.parentID) == "number"
	local filter

	local baseFilter = function(achievement) return not achievement.completed and (achievement.faction == database.factions.Neutral or achievement.faction == faction) end
	if IsAltKeyDown() then
		-- modify the filter for alts if alt is used
		baseFilter = function(achievement) return not achievement.completed and (achievement.faction == database.factions.Neutral or achievement.faction == faction) and achievement.accountWide end
	end

	-- get 10 popular not done achievements for this category
	if isChildCategory then
		local parentCategoryTitle = (GetCategoryInfo(self.parentID))
		filter = function(achievement) return baseFilter(achievement) and achievement.categoryTitle == self.name and achievement.parentCategoryTitle == parentCategoryTitle end
	elseif IsShiftKeyDown() then
		-- show only parent category
		filter = function(achievement) return baseFilter(achievement) and achievement.categoryTitle == self.name end
	else
		-- show parent category and below
		filter = function(achievement) return baseFilter(achievement) and (achievement.categoryTitle == self.name or achievement.parentCategoryTitle == self.name) end
	end

	local popularNotCompletedAchievements = database:queryAchievements{
		filter = filter,
		sort = function(high, low) return high.completedByPercentage > low.completedByPercentage end,
		limit = 10
	}

	-- add them to the tooltip or adjust the existing ones
	for number, achievement in pairs(popularNotCompletedAchievements) do
		local fontString = _G["GameTooltipTextLeft"..(number+2)]
		local colors = database:getAchievementColors(achievement.completedByPercentage)
		local text = achievement.name .. " (" .. achievement.completedByPercentage .. "%)"

		if fontString and fontString:GetText() then
			fontString:SetText(text)
			fontString:SetTextColor(colors.r, colors.g, colors.b)
			fontString:Show()
		else
			GameTooltip:AddLine(text, colors.r, colors.g, colors.b)
		end
	end

	-- hide any remaining lines
	for number = (#popularNotCompletedAchievements+3), 12 do
		local fontString = _G["GameTooltipTextLeft"..number]

		if fontString then
			fontString:Hide()
		end
	end

	-- call show to grow the tooltip so the new lines fit
	GameTooltip:Show()
end

-- shows the tooltip for an achievement category and then adjusts it to also show the information we have in this addon
local function showAndAdjustAchievementCategoryTooltip(self)
	--print('Intercepted!', self, self.name)

	-- show Blizzard tooltip
	AchievementFrameCategory_StatusBarTooltip_AI(self)

	-- only adjust tooltip when it is about individual achievements
	if AchievementFrameHeaderTitle:GetText() == ACHIEVEMENT_TITLE then
		adjustAchievementCategoryTooltip(self, true)
	end
end

-- hidden frame to listen for events
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

-- handle events
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then
			-- run this only when the addon loaded event fires for this addon

			if AchievementizerData == nil then
				-- db is not initialized, reset to do so
				database:reset()
			end

			-- only register events when addon is fully loaded and db initialized (otherwise might cause errors)
			self:RegisterEvent("PLAYER_LOGIN")
			self:RegisterEvent("PLAYER_TARGET_CHANGED")
			self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
			self:RegisterEvent("GROUP_ROSTER_UPDATE")
			self:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
			self:RegisterEvent("ACHIEVEMENT_EARNED")
			todoFrame:RegisterEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED")
		end
	elseif event == "PLAYER_LOGIN" then
		-- only register these events when all information about achievements is available, it is ok to miss a few fires of these events
		todoFrame:RegisterEvent("TRACKED_ACHIEVEMENT_UPDATE")
		todoFrame:RegisterEvent("CRITERIA_UPDATE")

		-- show the todo frame if it was shown last time
		if AchievementizerData.showTodos then
			todoFrame:stickyShow()
		end

		-- intercept the achievement tooltip function so we can modify that tooltip (requires load ui to exist)
		AchievementFrame_LoadUI()
		AchievementFrameCategory_StatusBarTooltip_AI = AchievementFrameCategory_StatusBarTooltip
		AchievementFrameCategory_StatusBarTooltip = showAndAdjustAchievementCategoryTooltip

		-- now that we have modified the tooltip we can also react to modifier keys to update it
		self:RegisterEvent("MODIFIER_STATE_CHANGED")

		-- intercept the achievement frame LoadTextures function so we can reset the achievement functions in time (when OnShow is called, which cannot be intercepted)
		-- this restores the fix for Blizzard errors when scanning players (see Blizzard_AchievementUI.lua)
		AchievementFrame_LoadTextures_AI = AchievementFrame_LoadTextures
		AchievementFrame_LoadTextures = function() if ACHIEVEMENT_FUNCTIONS.selectedCategory == -1 then ACHIEVEMENT_FUNCTIONS.selectedCategory = "summary" end AchievementFrame_LoadTextures_AI() end

		--print(addonName, "loaded")

		-- auto build the database if it hasn't been done in the past 16 hours for this faction (allows roughly one rebuild per day with a reasonable amount of time between them while accomodating various playstyles)
		local faction = database:convertTitleToFaction(UnitFactionGroup("player"))
		local secondsBetweenRebuilds = 16*60*60

		if (faction == database.factions.Alliance and GetServerTime() - AchievementizerData.lastBuildTimeA > secondsBetweenRebuilds)
			or (faction == database.factions.Horde and GetServerTime() - AchievementizerData.lastBuildTimeH > secondsBetweenRebuilds) then
			database:buildAchievementList()
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		scanPlayerMaybe("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		scanPlayerMaybe("mouseover")
		adjustPlayerToolTipMaybe()
	elseif event == "GROUP_ROSTER_UPDATE" then
		--print("Members:", GetNumGroupMembers(), IsInRaid())
		if IsInRaid() then
			for i = 1, GetNumGroupMembers() do
				scanPlayerMaybe("raid" .. i)
			end
		elseif GetNumGroupMembers() > 1 then
			for i = 1, GetNumGroupMembers() do
				scanPlayerMaybe("party" .. i)
			end
		end
	elseif event == "INSPECT_ACHIEVEMENT_READY" then
		local targetPoints = GetComparisonAchievementPoints()

		-- get player guid (and name if debugging)
		local playerGuid = ...
		--local playerInfo = {GetPlayerInfoByGUID(playerGuid)}
		--local playerName = playerInfo[6]
		-- or use: local playerName = (select(6, GetPlayerInfoByGUID(playerGuid)))
		--print(playerGuid, playerName)

		if targetPoints > 0 then
			-- move the faction out of the temporary pool, this is its only purpose
			local factionTitle = tempFactionPool[playerGuid]
			tempFactionPool[playerGuid] = nil

			database:savePlayerAchievements(playerGuid, targetPoints, factionTitle)

			if AchievementizerData.showTodos then
				-- might change todo frame
				todoFrame:stickyShow()
			end

			-- adjust tooltip if showing
			if GameTooltip:IsShown() then
				adjustPlayerToolTipMaybe(playerGuid)
			end
		end
	elseif event == "ACHIEVEMENT_EARNED" then
		local achievementId = (...)
		database:completedAchievement(achievementId)
		--print("Registered achievement", achievementId)

		if AchievementizerData.showTodos then
			-- might need to remove from todo frame
			todoFrame:removeTodo(achievementId, "achievement")
		else
			-- remove in background (removal will be visible next time todo frame is shown)
			database:removeTodo(achievementId, "achievement", database:playerGuidIfAchievementNotAccountWide(achievementId))
		end
	elseif event == "MODIFIER_STATE_CHANGED" then
		--local key, down = ...
		local statusBarActive = false

		if GameTooltip.statusBarPool then
			statusBarActive = GameTooltip.statusBarPool:GetNumActive() > 0
		end

		-- adjust if a tooltip is being shown with status bar and we are looking at individual achievements
		-- (atm the achievement category tooltips are the only ones that use this)
		if GameTooltip:IsShown() and statusBarActive and AchievementFrameHeaderTitle and AchievementFrameHeaderTitle:GetText() == ACHIEVEMENT_TITLE then
			adjustAchievementCategoryTooltip(GetMouseFocus(), false)
		end
	else
		print(addonName, "Unknown event", event)
	end
end)

-- define slash command
SLASH_AI1 = "/ai"
SlashCmdList["AI"] = function(rawCommand)
	local command = string.lower(rawCommand)

	--if command == "build" then
		--database:buildAchievementList()
	--elseif command == "clear" then
		--database:reset()
		--print(addonName, "Database cleared")
		--todoFrame:stickyShow()
	if command == "" then
		if AchievementizerData.scanCount > 0 then
			local ownPoints = GetTotalAchievementPoints()
			local sampleSummary = database:getSampleSummary(ownPoints, true)

			-- determine staleness text
			local stalenessText
			local staleness = GetServerTime() - sampleSummary.oldestTime
			local secondsPerHour = 60*60
			local secondsPerDay = 60*60*24
			local stalenessDays = math.floor(staleness / secondsPerDay)

			if stalenessDays == 1 then
				stalenessText = "1 day"
			elseif stalenessDays > 1 then
				stalenessText = stalenessDays .. " days"
			else
				local stalenessHours = math.floor(staleness / secondsPerHour)

				if stalenessHours == 1 then
					stalenessText = "1 hour"
				elseif stalenessHours > 1 then
					stalenessText = stalenessHours .. " hours"
				else
					local stalenessMinutes = math.floor(staleness / 60)

					if stalenessMinutes == 0 then
						stalenessText = "<1 minute"
					elseif stalenessMinutes == 1 then
						stalenessText = "1 minute"
					else
						stalenessText = stalenessMinutes .. " minutes"
					end
				end
			end

			print(addonName, "You have", ownPoints, "points. This ranks you at number", sampleSummary.rank, "(top", sampleSummary.rankPercentage ..
				"%) compared to the sample of", AchievementizerData.scanCount, "players (max", sampleSummary.maxPoints ..
				", min", sampleSummary.minPoints, "points, oldest data is", stalenessText, "old, Alliance:", sampleSummary.playerCountA ..
				", Horde:", sampleSummary.playerCountH .. ").")

			if sampleSummary.rank > 1 then
				print(addonName, "You need", sampleSummary.pointsToRankUp, "points to gain a rank.")
			end
		end

		local faction = database:convertTitleToFaction(UnitFactionGroup("player"))
		local popularNotCompletedAchievements = database:queryAchievements{
			filter = function(achievement) return not achievement.completed and (achievement.faction == database.factions.Neutral or achievement.faction == faction) end,
			sort = function(high, low) return high.completedByPercentage > low.completedByPercentage end,
			limit = 100
		}

		mainFrame:showAchievements(popularNotCompletedAchievements)
	elseif command == "done" then
		local faction = database:convertTitleToFaction(UnitFactionGroup("player"))
		local impopularCompletedAchievements = database:queryAchievements{
			filter = function(achievement) return achievement.completed and (achievement.faction == database.factions.Neutral or achievement.faction == faction) end,
			sort = function(high, low) return high.completedByPercentage < low.completedByPercentage end,
			limit = 100
		}

		mainFrame:showAchievements(impopularCompletedAchievements)
	elseif command == "todo" then
		todoFrame:stickyShow()
	elseif command == "alt" then
		local faction = database:convertTitleToFaction(UnitFactionGroup("player"))
		local accountWidePopularNotCompletedAchievements = database:queryAchievements{
			filter = function(achievement) return not achievement.completed and (achievement.faction == database.factions.Neutral or achievement.faction == faction) and achievement.accountWide end,
			sort = function(high, low) return high.completedByPercentage > low.completedByPercentage end,
			limit = 100
		}

		mainFrame:showAchievements(accountWidePopularNotCompletedAchievements)
	else
		print(addonName, 'Command unknown: "' .. command .. '".')
		print("Available commands: ")
		print('-"" (shows popular incomplete achievements)')
		print('-"done" (shows impopular completed achievements)')
		print('-"todo" (shows the todo frame if it was hidden)')
		print('-"alt" (shows popular incomplete achievements that alts can contribute to)')
	end
end
