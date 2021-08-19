-- arguments to the file
local _addonName, namespace = ...

local frameFactory = namespace.frameFactory

-- get what we need from the namespace
local database = namespace.database
local round = namespace.round
local tellPlayer = namespace.tellPlayer

-- UI settings
local todoFrameWidth = 250
local todoFrameHeight = 150

local hiddenTimedCriteria = {}

local criteriaQuantities = {}
local achievementQuantities = {}

-- create the todo frame of this addon (the name is needed as then the position is restored at player login)
local todoFrame = frameFactory:createFrame(todoFrameWidth, todoFrameHeight, "ai_todoFrame", "showTodos")

-- make the todo frame available to other files in this addon
namespace.todoFrame = todoFrame

-- make the frame movable (use standard Blizzard function for moving, and keep inside screen)
todoFrame:SetMovable(true)
todoFrame:RegisterForDrag("LeftButton")
todoFrame:SetScript("OnDragStart", todoFrame.StartMoving)
todoFrame:SetScript("OnDragStop", todoFrame.StopMovingOrSizing)
todoFrame:SetScript("OnHide", todoFrame.StopMovingOrSizing)
todoFrame:SetClampedToScreen(true)

function todoFrame:stickyShow()
	local playerGuid = UnitGUID("player")

	-- put tracked todos on top and no other sorting as there should be very few todos
	local todos = database:queryTodos{ sort = function(high, low) return high.tracked and not low.tracked end }

	self:clearTexts()

	for _, todo in pairs(todos) do
		-- show only account wide or own todos
		if todo.playerGuid == nil or todo.playerGuid == playerGuid then
			if todo.todoType == "achievement" then
				local achievement = AchievementizerData.achievements[todo.id]

				if achievement == nil then
					tellPlayer("achievement not found", todo.id)
				else
					local color = database:getAchievementColor(achievement.completedByPercentage)
					local achievementLink = GetAchievementLink(achievement.id) -- this can be nil apparently

					if achievementLink ~= nil then
						local textToAdd = achievementLink:gsub("ffffff00", color, 1)

						if todo.tracked then
							textToAdd = textToAdd .. "*"
						end

						self:addText(textToAdd)
					end

					local numCriteria = GetAchievementNumCriteria(todo.id)
					local completedCriteria = 0
					local showCriteriaPercentage = true
					local textsToAdd = {}

					for criteriaIndex = 1, numCriteria do
						local criteriaString, _criteriaType, criteriaCompleted, quantity, reqQuantity, _charName, flags, _assetID, quantityString, criteriaId, eligible, duration, elapsed = GetAchievementCriteriaInfo(todo.id, criteriaIndex)

						if criteriaCompleted then
							completedCriteria = completedCriteria + 1
						else
							if bit.band(flags, EVALUATION_TREE_FLAG_PROGRESS_BAR) == EVALUATION_TREE_FLAG_PROGRESS_BAR then
								criteriaQuantities[criteriaId] = quantity
								criteriaString = quantityString .. " (" .. round(100 * quantity / reqQuantity) .. "%)"
								showCriteriaPercentage = false
							else
								criteriaString = "- " .. criteriaString
							end

							-- show achievement criteria if tracked (and if achievement can be shown)
							if todo.tracked and achievementLink ~= nil then
								color = "ffff0000"

								if eligible then
									color = "ffffffff"
								end

								table.insert(textsToAdd, "|c" .. color .. criteriaString .. "|r")

								if duration and elapsed and elapsed <= duration and duration > 0 then
									table.insert(textsToAdd, "|c" .. color .. "time: " .. elapsed .. "s / " .. duration .. "s (" .. round(100 * elapsed / duration) .. "%)|r")
								end
							end
						end
					end

					-- record quantities for list achievements (if not known yet or not decreased, apparently can sometimes be 0 all of a sudden, e.g. at start of bg)
					if showCriteriaPercentage and (not achievementQuantities[todo.id] or completedCriteria >= achievementQuantities[todo.id]) then
						achievementQuantities[todo.id] = completedCriteria
					end

					-- show percentage if needed (and if achievement can be shown)
					if todo.tracked and achievementLink ~= nil and showCriteriaPercentage and numCriteria > 0 then
						self:addText("|c" .. color .. completedCriteria .. " / " .. numCriteria .. " (" .. round(100 * completedCriteria / numCriteria) .. "%)" .. "|r")
					end

					for _, textToAdd  in pairs(textsToAdd) do
						self:addText(textToAdd)
					end

					-- show hidden timed criterium if tracked and the time hasn't run out yet (and if achievement can be shown)
					local hiddenTimedCriterium = hiddenTimedCriteria[todo.id]
					if todo.tracked and achievementLink ~= nil and numCriteria == 0 and hiddenTimedCriterium then
						local elapsed = GetTime() - hiddenTimedCriterium.startTime

						if elapsed <= hiddenTimedCriterium.duration and hiddenTimedCriterium.duration > 0 then
							self:addText("|cfffffffftime: " .. round(elapsed) .. "s / " .. hiddenTimedCriterium.duration .. "s (" .. round(100 * elapsed / hiddenTimedCriterium.duration) .. "%)|r")
						end
					end
				end
			else
				tellPlayer("Unkown todo type", todo.todoType)
			end
		end
	end

	-- not only show the frame, but also auto show in later sessions
	AchievementizerData.showTodos = true
	self:Show()
end

function todoFrame:addTodo(id, todoType)
	database:addTodo(id, todoType, database:playerGuidIfAchievementNotAccountWide(id))

	-- show the todo frame, so we know the todo was added
	self:stickyShow()
end

function todoFrame:removeTodo(id, todoType)
	database:removeTodo(id, todoType, database:playerGuidIfAchievementNotAccountWide(id))

	-- show the todo frame, so we know the todo was removed
	self:stickyShow()
end

function todoFrame:toggleTrackTodo(id, todoType)
	database:toggleTrackTodo(id, todoType, database:playerGuidIfAchievementNotAccountWide(id))

	-- show the todo frame, so we know the todo's tracked bit was toggled
	self:stickyShow()
end

-- enable achievement hyperlinks and use default Blizzard handler for left click and remove for right click
todoFrame:SetHyperlinksEnabled(true)
todoFrame:SetScript("OnHyperlinkClick", function(self, link, _text, button)
	local _, achievementId = strsplit(":", link)
	achievementId = tonumber(achievementId)

	if button == "LeftButton" then
		if IsShiftKeyDown() then
			self:toggleTrackTodo(achievementId, "achievement")
		else
			OpenAchievementFrameToAchievement(achievementId)
		end
	elseif button == "RightButton" then
		-- remove from list
		self:removeTodo(achievementId, "achievement")
	end
end)

todoFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "TRACKED_ACHIEVEMENT_LIST_CHANGED" then
		local achievementId, added = ...

		if added then
			-- remove from Blizzard frame
			RemoveTrackedAchievement(achievementId)

			-- and add to own frame
			self:addTodo(achievementId, "achievement")
		end
	elseif event == "TRACKED_ACHIEVEMENT_UPDATE" then
		local achievementId, _criteriaId, elapsed, duration = ...

		if (GetAchievementInfo(achievementId)) == nil then
			-- somehow an event is triggered for an achievement that no longer exists, just ignore it
			return
		end

		local todo = database:getTodo(achievementId, "achievement", database:playerGuidIfAchievementNotAccountWide(achievementId))

		if todo ~= nil then
			local numCriteria = GetAchievementNumCriteria(achievementId)

			if numCriteria == 0 then
				-- this achievement has/is a hidden timed criterium and is a todo
				-- if it has not timed out yet, store it for later use in stickyShow, i.e. do an upsert now
				if elapsed <= duration then
					local hiddenTimedCriterium = hiddenTimedCriteria[achievementId] or {}

					-- store the start time since the elapsed time is constantly changing
					hiddenTimedCriterium.startTime = GetTime() - elapsed
					hiddenTimedCriterium.duration = duration
					hiddenTimedCriteria[achievementId] = hiddenTimedCriterium

					-- also keep refreshing the todoFrame every second for as long as needed
					C_Timer.NewTicker(1, function() todoFrame:stickyShow() end, round(duration - elapsed))
				else
					-- remove if there is no time left
					hiddenTimedCriteria[achievementId] = nil
				end
			end

			-- achievement found and something needs to be updated, track it if it wasn't already (and has time left) and show the todo frame
			if todo.tracked or elapsed > duration then
				-- todo is already tracked or has elapsed, only show the todo frame so we can see how the achievement has changed
				self:stickyShow()
			else
				-- tracking the todo will automatically show and thus refresh the todo frame
				self:toggleTrackTodo(achievementId, "achievement")
			end
		end
	elseif event == "CRITERIA_UPDATE" then
		-- auto track todos if they aren't tracked already, are incomplete, and there is some progress
		local progressMade = false
		local playerGuid = UnitGUID("player")

		for _, todo in pairs(AchievementizerData.todos) do
			if todo.playerGuid == nil or todo.playerGuid == playerGuid and todo.todoType == "achievement" and not todo.tracked then
				local numCriteria = GetAchievementNumCriteria(todo.id)
				local completedCriteria = 0

				for criteriaIndex = 1, numCriteria do
					local _criteriaString, _criteriaType, criteriaCompleted, quantity, _reqQuantity, _charName, flags, _assetID, _quantityString, criteriaId, _eligible, _duration, _elapsed = GetAchievementCriteriaInfo(todo.id, criteriaIndex)
					local oldQuantity = criteriaQuantities[criteriaId]

					if criteriaCompleted then
						completedCriteria = completedCriteria + 1
					elseif bit.band(flags, EVALUATION_TREE_FLAG_PROGRESS_BAR) == EVALUATION_TREE_FLAG_PROGRESS_BAR and oldQuantity and quantity > oldQuantity then
						todo.tracked = true
						progressMade = true
						break
					end
				end

				local oldCompletedCriteria = achievementQuantities[todo.id]

				if oldCompletedCriteria and completedCriteria > oldCompletedCriteria then
					todo.tracked = true
					progressMade = true
				end
			end
		end

		-- update the todo frame if shown or show it if some progress was made, so we can see how the achievement criteria have changed
		if AchievementizerData.showTodos or progressMade then
			self:stickyShow()
		end
	else
		tellPlayer("Unknown event", event)
	end
end)