-- arguments to the file
local addonName, namespace = ...

-- color coding for percentages
local commonUncommonBoundary = 50
local uncommonRareBoundary = 20
local rareEpicBoundary = 5
local epicLegendaryBoundary = 1

-- database "class": wrapper to get data from the WoW API to the SavedVariable AchievementizerData (also holds todos)
local database = {}

-- make database available to other files in the addon
namespace.database = database

-- there is no rounding function so add .5 and use the floor function to get the same result (for a positive number)
local function round(input)
	return math.floor(input+0.5)
end

-- make round available to other files in the addon
namespace.round = round

database.factions = {
	Alliance = 1,
	Horde = 2,
	Neutral = 3
}

function database:convertTitleToFaction(factionTitle)
	local faction = database.factions.Alliance

	if factionTitle == "Horde" then
		faction = database.factions.Horde
	elseif factionTitle == "Neutral" then
		faction = database.factions.Neutral
	end

	return faction
end

-- return the current player's guid if the achievement is not account wide, nil otherwise
function database:playerGuidIfAchievementNotAccountWide(achievementId)
	local info = {GetAchievementInfo(achievementId)}
	local flags = info[9]

	if bit.band(flags, ACHIEVEMENT_FLAGS_ACCOUNT) ~= ACHIEVEMENT_FLAGS_ACCOUNT then
		return UnitGUID("player")
	end
end

-- maintain a list of ids of achievements in the Legacy and Feats of Strength categories (we need to remove them later as Blizzard erroneously links them sometimes via GetNextAchievement)
local forbiddenIds = {}

-- and also a list of removed achievements (they are still in our db, but Blizzard removed them)
local removedIds = {}

local categories = {}
local isBuildingAchievementList = false

-- populate the database with all achievements from the API, updating if already known in the db
function database:buildAchievementList()
	if isBuildingAchievementList then
		return
	end

	isBuildingAchievementList = true

	categories = GetCategoryList()
	local categoryCount = #categories
	local factionTitle = UnitFactionGroup("player")
	local faction = self:convertTitleToFaction(factionTitle)

	print(addonName, "Building database for", categoryCount, "categories and faction", factionTitle)

	-- put all current achievement ids in a list of ids of achievements that need to be removed later (so achievements removed by Blizzard will be removed here as well)
	for id, achievement in pairs(AchievementizerData.achievements) do
		if achievement.faction == database.factions.Neutral or achievement.faction == faction then
			removedIds[id] = true
		end
	end

	-- distribute the load of building the entire achievement list over time and call it one extra time to run the finishing code
	C_Timer.NewTicker(0.2, function() database:buildAchievementListForNextCategory() end, categoryCount + 1)
end

local function finishBuildAchievementList()
	-- now that all categories are done we can remove forbidden achievement ids from the db
	for forbiddenId in pairs(forbiddenIds) do
		--if AchievementizerData.achievements[forbiddenId] ~= nil then
		--	print(AchievementizerData.achievements[forbiddenId].parentCategoryTitle, AchievementizerData.achievements[forbiddenId].categoryTitle, AchievementizerData.achievements[forbiddenId].name)
		--end

		-- first remove any related todos
		database:removeTodoForAllPlayers(forbiddenId, "achievement")

		AchievementizerData.achievements[forbiddenId] = nil
	end

	-- and the removed achievements as well
	for removedId in pairs(removedIds) do
		--if AchievementizerData.achievements[removedId] ~= nil then
		--	print(AchievementizerData.achievements[removedId].parentCategoryTitle, AchievementizerData.achievements[removedId].categoryTitle, AchievementizerData.achievements[removedId].name)
		--end

		-- first remove any related todos
		database:removeTodoForAllPlayers(removedId, "achievement")

		AchievementizerData.achievements[removedId] = nil
	end

	if database:convertTitleToFaction(UnitFactionGroup("player")) == database.factions.Alliance then
		AchievementizerData.lastBuildTimeA = GetServerTime()
	else
		AchievementizerData.lastBuildTimeH = GetServerTime()
	end

	isBuildingAchievementList = false

	print(addonName, "Database built")
end

function database:buildAchievementListForNextCategory()
	-- pop an id of the table
	local categoryId = table.remove(categories)

	if categoryId == nil then
		-- table was empty, finish the job
		finishBuildAchievementList()

		return
	end

	local factionTitle = UnitFactionGroup("player")
	local faction = self:convertTitleToFaction(factionTitle)

	-- the below doesn't work apparently (might also be slower than just trying)
	--local categoryNumAchievements = (GetCategoryNumAchievements(categoryId))
	--print(categoryNumAchievements)

	local indexInCategory = 1
	local id, name, _, completed, _, _, _, _, flags = GetAchievementInfo(categoryId, indexInCategory)
	while id ~= nil do
		--print(indexInCategory, id, name)

		database:achievementDiscovered(id, name, completed, faction, flags)

		-- get any previous achievements in the chain
		local linkedAchievementId = GetPreviousAchievement(id)
		while linkedAchievementId ~= nil do
			_, name, _, completed, _, _, _, _, flags = GetAchievementInfo(linkedAchievementId)
			--print("Prev achieve", linkedAchievementId, name)

			database:achievementDiscovered(linkedAchievementId, name, completed, faction, flags)
			linkedAchievementId = GetPreviousAchievement(linkedAchievementId)
		end

		-- get any next achievements in the chain (starting from the original achievement, from before the GetPreviousAchievement block)
		linkedAchievementId = GetNextAchievement(id)
		while linkedAchievementId ~= nil do
			_, name, _, completed, _, _, _, _, flags = GetAchievementInfo(linkedAchievementId)
			--print("Next achieve", linkedAchievementId, name)

			database:achievementDiscovered(linkedAchievementId, name, completed, faction, flags)
			linkedAchievementId = GetNextAchievement(linkedAchievementId)
		end

		indexInCategory = indexInCategory + 1
		id, name, _, completed, _, _, _, _, flags = GetAchievementInfo(categoryId, indexInCategory)
	end
end

-- an achievement has been discovered, decide what to do with it
function database:achievementDiscovered(id, name, completed, faction, flags)
	-- apparently linked achievements are not always in the same category as their parent achievement, so get the category for each achievement separately
	local categoryId = GetAchievementCategory(id)
	local categoryTitle, categoryParentId = GetCategoryInfo(categoryId)
	local parentCategoryTitle = ""
	if categoryParentId ~= -1 then
		parentCategoryTitle = (GetCategoryInfo(categoryParentId))
	end

	-- ignore the categories Legacy and Feats of Strength for the database (these usually cannot be obtained anyway)
	if categoryTitle ~= "Legacy" and parentCategoryTitle ~= "Legacy" and categoryTitle ~= "Feats of Strength" and parentCategoryTitle ~= "Feats of Strength" then
		database:saveAchievement(id, name, completed, categoryTitle, parentCategoryTitle, faction, flags)

		-- achievement is still in the game, remove from the list of removed achievements
		removedIds[id] = nil
	else
		-- save to the list of Legacy / FoS achievements
		forbiddenIds[id] = true
	end
end

-- upsert the achievement in the db
function database:saveAchievement(id, name, completed, categoryTitle, parentCategoryTitle, faction, flags)
	if AchievementizerData.achievements[id] == nil then
		local accountWide = nil

		if bit.band(flags, ACHIEVEMENT_FLAGS_ACCOUNT) == ACHIEVEMENT_FLAGS_ACCOUNT then
			accountWide = true
		end

		-- create new achievement

		AchievementizerData.achievements[id] = {
			id = id,
			name = name,
			completed = completed,
			categoryTitle = categoryTitle,
			parentCategoryTitle = parentCategoryTitle,
			scanCount = 0,
			completedByCount = 0,
			completedByPercentage = 0,
			faction = faction,
			accountWide = accountWide
		}
	else
		-- update known achievement, if completed now or if also for other faction

		if not AchievementizerData.achievements[id].completed and completed then
			AchievementizerData.achievements[id].completed = completed
		end

		if AchievementizerData.achievements[id].faction ~= faction then
			AchievementizerData.achievements[id].faction = database.factions.Neutral
		end
	end
end

function database:completedAchievement(id)
	if AchievementizerData.achievements[id] == nil then
		-- new achievement, get data, then call save

		local faction = self:convertTitleToFaction(UnitFactionGroup("player"))
		local _, name, _, _, _, _, _, _, flags = GetAchievementInfo(id)
		local categoryId = GetAchievementCategory(id)
		local categoryTitle, categoryParentId = GetCategoryInfo(categoryId)
		local parentCategoryTitle = ""
		if categoryParentId ~= -1 then
			parentCategoryTitle = (GetCategoryInfo(categoryParentId))
		end

		database:saveAchievement(id, name, true, categoryTitle, parentCategoryTitle, faction, flags)
	else
		-- known achievement, only need id and completed=true
		database:saveAchievement(id, nil, true)
	end
end

-- reset the database
function database:reset()
	AchievementizerData = {
		achievements = {},
		scanned = {},
		scanCount = 0,
		todos = {},
		lastBuildTimeA = 0,
		lastBuildTimeH = 0
	}
end

-- remove player data for the supplied guids, as there are no links to the players' achieves their removal is done probabilistically:
-- reduces the completedByCount by at most #playerGuids for all achievements for the faction (or neutral), the higher an achievement's percentage the higher the chance, 0% guarantees no reduction, 100% guarantees reduction
-- also reduces the scanCounts and recalculates the completedByPercentages
local function probabilisticallyRemovePlayerAchievements(playerGuids, faction)
	local count = #playerGuids

	-- this simulates the serial removal of count players of a faction
	for _, playerGuid in pairs(playerGuids) do
		for _id, achievement in pairs(AchievementizerData.achievements) do
			if achievement.faction == database.factions.Neutral or achievement.faction == faction then
				-- roll random number and compare with completed percentage, a higher percentage means a higher chance for a reduction of 1
				local rand = random(1, 100)
				if rand <= achievement.completedByPercentage then
					achievement.completedByCount = max(0, achievement.completedByCount - 1)
				end

				--print("probabilisticallyRemovePlayerAchievements", achievement.completedByPercentage)

				achievement.scanCount = max(0, achievement.scanCount - 1)

				if achievement.scanCount > 0 then
					achievement.completedByPercentage = round(100 * achievement.completedByCount / achievement.scanCount)
				else
					achievement.completedByPercentage = 0
				end
			end
		end

		AchievementizerData.scanned[playerGuid] = nil
	end

	AchievementizerData.scanCount = max(0, AchievementizerData.scanCount - count)

	--print("probabilisticallyRemovePlayerAchievements", count, AchievementizerData.scanCount)
end

-- settings for removing stale data
local maxTimeInDb = 60*60*24*7
local maxPlayersInDb = 1000
local maxAmountToRemove = 20

-- removes redundant players (if they have stale data or if there are just too many), if any
function database:removeRedundantPlayers()
	local now = GetServerTime()

	-- remove 1 extra as 1 is going to be added, but never more than maxAmountToRemove
	local minAmountToRemove = min(max(0, AchievementizerData.scanCount - maxPlayersInDb + 1), maxAmountToRemove)
	local playerGuidsA = {}
	local playerGuidsH = {}
	local tempPlayers = {}
	local playerCount = 0
	--print("minAmountToRemove", minAmountToRemove, AchievementizerData.scanCount)

	for playerGuid, playerData in pairs(AchievementizerData.scanned) do
		--print("playerData.time", playerData.time, playerGuid)
		if playerCount >= maxAmountToRemove then
			-- no more room, no need to continue, let's keep the framerate high
			break
		elseif now - playerData.time > maxTimeInDb then
			-- player is too long in db, always remove if there is room
			if playerData.faction == database.factions.Alliance then
				table.insert(playerGuidsA, playerGuid)
			else
				table.insert(playerGuidsH, playerGuid)
			end

			minAmountToRemove = minAmountToRemove - 1
			playerCount = playerCount + 1
		elseif minAmountToRemove > 0 then
			-- still players left to remove, keep adding to temp list, will be shortened later
			table.insert(tempPlayers, { playerGuid = playerGuid, time = playerData.time, faction = playerData.faction })
		else
			-- no players left to remove, only remove players that are too long in the db
			tempPlayers = {}
			--print("cleared")
		end
	end

	-- dont make temp list too long (remove most recent data)
	table.sort(tempPlayers, function(high, low) return high.time < low.time end)

	for _ = 1, #tempPlayers - minAmountToRemove do
		--local removedGuid =
		table.remove(tempPlayers)
		--if removedGuid ~= nil then
			--print("removedGuid", removedGuid.playerGuid)
		--end
	end

	--print("#tempPlayers", #tempPlayers) -- , tempPlayers[1].time, tempPlayers[2].time
	--print("#playerGuids", #playerGuidsA, #playerGuidsH)

	-- copy remaining temp guids to final list of guids
	for _, tempPlayer in pairs(tempPlayers) do
		if tempPlayer.faction == database.factions.Alliance then
			table.insert(playerGuidsA, tempPlayer.playerGuid)
		else
			table.insert(playerGuidsH, tempPlayer.playerGuid)
		end
	end

	--print("#playerGuids", #playerGuidsA, #playerGuidsH, playerGuidsA[1], playerGuidsH[1])

	if #playerGuidsA > 0 then
		probabilisticallyRemovePlayerAchievements(playerGuidsA, database.factions.Alliance)
	end

	if #playerGuidsH > 0 then
		probabilisticallyRemovePlayerAchievements(playerGuidsH, database.factions.Horde)
	end
end

function database:savePlayerAchievements(playerGuid, targetPoints, factionTitle)
	local faction = self:convertTitleToFaction(factionTitle)

	-- check if stale players need to be probabilistically removed and do this
	database:removeRedundantPlayers()

	if AchievementizerData.scanned[playerGuid] ~= nil then
		-- player was scanned before, only update points (, time and newly completed achievements)

		AchievementizerData.scanned[playerGuid].points = targetPoints
		--AchievementizerData.scanned[playerGuid].time = GetServerTime()

		--[[for id, achievement in pairs(AchievementizerData.achievements) do
			if not achievement.completedBy[playerGuid] then
				local completed = (GetAchievementComparisonInfo(id))

				if completed then
					achievement.completedBy[playerGuid] = true
					achievement.completedByCount = achievement.completedByCount + 1
					achievement.completedByPercentage = round(100 * achievement.completedByCount / AchievementizerData.scanCount)
				end
			end
		end]]
	else
		-- player was not scanned before, register player, increase scanCount, and update all achievements

		AchievementizerData.scanned[playerGuid] = { points = targetPoints, time = GetServerTime(), faction = faction }
		AchievementizerData.scanCount = AchievementizerData.scanCount + 1

		for id, achievement in pairs(AchievementizerData.achievements) do
			local completed = (GetAchievementComparisonInfo(id))

			if completed then
				--achievement.completedBy[playerGuid] = true
				achievement.completedByCount = achievement.completedByCount + 1
			end

			if achievement.faction == database.factions.Neutral or achievement.faction == faction then
				achievement.scanCount = achievement.scanCount + 1
			end

			if achievement.scanCount > 0 then
				achievement.completedByPercentage = round(100 * achievement.completedByCount / achievement.scanCount)
			end
		end
	end
end

-- query the achievements: use a filter function to only select the achievements you need, the sort function to give them a particular order, and the limit integer to limit your results to the first few, all parameters can be nil
function database:queryAchievements(params)
	return database:queryTable(params, AchievementizerData.achievements)
end

-- query todos just like achievements, see database:queryAchievements
function database:queryTodos(params)
	return database:queryTable(params, AchievementizerData.todos)
end

-- query a table not necessarily in this database
function database:queryTable(params, tableToQuery)
	local result = {}

	-- store these checks for slightly more speed (also easier to read)
	local filterIsInactive = params.filter == nil
	local sortIsInactive = params.sort == nil
	local limitIsActive = params.limit ~= nil

	-- in one pass perform the filter and copy to an array table (and maybe the limit as well)
	local rowNumber = 1
	for _, row in pairs(tableToQuery) do
		if filterIsInactive or params.filter(row) then
			if sortIsInactive and limitIsActive and rowNumber > params.limit then
				-- if the sort is not used anyway, but the limit is then we can limit the amount of work right away
				break
			end

			-- copy row
			result[rowNumber] = row

			rowNumber = rowNumber + 1
		end
	end

	-- sort the array table and limit
	if not sortIsInactive then
		table.sort(result, params.sort)

		if limitIsActive then
			-- remove unwanted data
			for index = params.limit + 1, #result do
				result[index] = nil
			end
		end
	end

	return result
end

function database:getAchievementColor(completedByPercentage)
	local result

	if completedByPercentage > commonUncommonBoundary then
		result = "ffffffff" -- white for common
	elseif completedByPercentage > uncommonRareBoundary then
		result = "ff1eff00" -- green for uncommon
	elseif completedByPercentage > rareEpicBoundary then
		result = "ff0070dd" -- blue for rare
	elseif completedByPercentage > epicLegendaryBoundary then
		result = "ffa335ee" -- purple for epic
	else
		result = "ffff8000" -- orange for legendary
	end

	return result
end

function database:getAchievementColors(completedByPercentage)
	local result = {}

	if completedByPercentage > commonUncommonBoundary then
		-- white for common
		result.r = 1
		result.g = 1
		result.b = 1
	elseif completedByPercentage > uncommonRareBoundary then
		-- green for uncommon
		result.r = 30/255
		result.g = 1
		result.b = 0
	elseif completedByPercentage > rareEpicBoundary then
		-- blue for rare
		result.r = 0
		result.g = 112/255
		result.b = 221/255
	elseif completedByPercentage > epicLegendaryBoundary then
		-- purple for epic
		result.r = 163/255
		result.g = 53/255
		result.b = 238/255
	else
		-- orange for legendary
		result.r = 1
		result.g = 128/255
		result.b = 0
	end

	return result
end

function database:getSampleSummary(ownPoints, isPlayer)
	local result = { rank = 1, pointsToRankUp = 9999999999, maxPoints = 0, minPoints = 9999999999, oldestTime = 9999999999, playerCountA = 0, playerCountH = 0 }

	-- get all data in one pass
	for _, playerData in pairs(AchievementizerData.scanned) do
		if playerData.points > ownPoints then
			result.rank = result.rank + 1
			result.pointsToRankUp = math.min(result.pointsToRankUp, playerData.points - ownPoints)
		end

		if playerData.points > result.maxPoints then
			result.maxPoints = playerData.points
		end

		if playerData.points < result.minPoints then
			result.minPoints = playerData.points
		end

		if playerData.time < result.oldestTime then
			result.oldestTime = playerData.time
		end

		if playerData.faction == database.factions.Alliance then
			result.playerCountA = result.playerCountA + 1
		else
			result.playerCountH = result.playerCountH + 1
		end
	end

	if isPlayer then
		-- add 1 to count self as well
		result.rankPercentage = round(100 * result.rank / (1 + AchievementizerData.scanCount))
	else
		result.rankPercentage = round(100 * result.rank / AchievementizerData.scanCount)
	end

	return result
end

local function determineKey(id, todoType, playerGuid)
	local key = todoType .. "_" .. id

	if playerGuid ~= nil then
		key = key .. "_" .. playerGuid
	end

	return key
end

function database:addTodo(id, todoType, playerGuid)
	local key = determineKey(id, todoType, playerGuid)

	if AchievementizerData.todos[key] == nil then
		AchievementizerData.todos[key] = {
			id = id,
			todoType = todoType,
			playerGuid = playerGuid
		}
	else
		local message = "You have already added this"

		if playerGuid == nil then
			print(addonName, message, todoType .. ":", id)
		else
			print(addonName, message, todoType .. " for this character:", id)
		end
	end
end

function database:removeTodo(id, todoType, playerGuid)
	local key = determineKey(id, todoType, playerGuid)

	AchievementizerData.todos[key] = nil
end

function database:removeTodoForAllPlayers(id, todoType)
	local keyToSearch = todoType .. "_" .. id
	local keyPrefix = keyToSearch .. "_"
	local keyPrefixLen = keyPrefix:len()

	--print("Removing", keyToSearch, "for all players")

	for key, _ in pairs(AchievementizerData.todos) do
		if key == keyToSearch or key:sub(1, keyPrefixLen) == keyPrefix then
			AchievementizerData.todos[key] = nil

			--print("Removed", keyPrefix, key, "for all players")
		end
	end
end

function database:getTodo(id, todoType, playerGuid)
	local key = determineKey(id, todoType, playerGuid)

	return AchievementizerData.todos[key]
end

function database:toggleTrackTodo(id, todoType, playerGuid)
	local todo = self:getTodo(id, todoType, playerGuid)

	if todo.tracked then
		todo.tracked = nil
	else
		todo.tracked = true
	end
end
