-- arguments to the file
local _addonName, namespace = ...

-- factory to create nice scrolling frames, share this with other files
local frameFactory = {}
namespace.frameFactory = frameFactory

function frameFactory:createFrame(frameWidth, frameHeight, name, visibilityKey)
	local frameScrollTop = -25
	local frameScrollBottom = 9
	local itemWidth = frameWidth - 36
	local itemHeight = 12
	local itemsInView = math.floor((frameHeight + frameScrollTop - frameScrollBottom) / itemHeight)

	-- frame is a child of the supplied parent, the game's main window, so it will disappear with ctrl-z
	local result = CreateFrame("Frame", name, UIParent, "BackdropTemplate")

	-- the frame is shown by default, prevent this
	result:Hide()

	-- set width and heigth (not doing this will make it 0x0, so invisible)
	result:SetWidth(frameWidth)
	result:SetHeight(frameHeight)

	-- set the center of the frame to the center of the screen (offsets in the x and y direction are both 0, the arguments UIParent, "CENTER", 0, 0 are currently not needed)
	result:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	-- set the z-layer where the frame lives (so on top or on bottom or somewhere in between) to the lowest possible, so we can build things on top if needed
	result:SetFrameStrata("BACKGROUND")

	-- set the background of the frame to that of a standard ui dialog box (not doing this will make it invisible)
	result:SetBackdrop({
		bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	})

	-- intercept mouse events (so no clickthrough)
	result:EnableMouse(true)

	-- move the frame to the top z level when clicked
	result:SetToplevel(true)

	-- add a close button whose top right coincides with the frame's top right which will hide the frame when clicked (use the Blizzard template UIPanelCloseButton)
	result.closeButton = CreateFrame("Button", nil, result, "UIPanelCloseButton")
	result.closeButton:SetPoint("TOPRIGHT", result, "TOPRIGHT")
	result.closeButton:SetScript("OnClick", function()
		result:Hide()

		if visibilityKey ~= nil then
			AchievementizerData[visibilityKey] = false
		end
	end)

	-- create a scroll frame (basically a slider with a scroll wheel area next to it) so we can scroll through the items if the list is too big for the frame (use Blizzard's FauxScrollFrameTemplate)
	result.scrollFrame = CreateFrame("ScrollFrame", nil, result, "FauxScrollFrameTemplate")

	-- define the area where you can use your scroll wheel
	result.scrollFrame:SetPoint("TOPLEFT", result, "TOPLEFT", 0, frameScrollTop)
	result.scrollFrame:SetPoint("BOTTOMRIGHT", result, "BOTTOMRIGHT", -31, frameScrollBottom)

	-- update the scrollframe and the items "inside" it when the scroll wheel is used
	result.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, itemHeight, function() result:updateScrollFrame() end)
	end)

	-- update the scroll frame and the items "inside" it
	function result:updateScrollFrame()
		-- how far has the user scrolled down
		local offset = FauxScrollFrame_GetOffset(self.scrollFrame)
		--print(offset)

		-- move the slider to the correct position
		FauxScrollFrame_Update(self.scrollFrame, #self.texts, itemsInView, itemHeight)

		-- simulate the scrolling of the items by showing/hiding them and moving them around
		for textNumber, text in ipairs(self.texts) do
			-- adjust the text number for scrolling, so we show only the adjusted numbers from 1 up to and including the number of items in view
			local adjustedTextNumber = textNumber - offset

			if adjustedTextNumber > 0 and adjustedTextNumber <= itemsInView then
				-- move each item to the right and down a bit to not overlap resp. the left border and the close button
				-- also use the adjusted text number to move it further down (as if these texts are the only texts)
				text:SetPoint("TOPLEFT", 12, -12 - (itemHeight * adjustedTextNumber))
				text:Show()
			else
				-- this text is not inside the scroll frame's current field of view, hide it
				text:Hide()
			end
		end
	end

	-- manage a list of texts in the frame
	-- and also a pool (stack) of fontStrings since they cannot be deleted
	result.texts = {}
	result.fontStringPool = {}
	function result:addText(text)
		-- determine the next text number
		local textNumber = #self.texts + 1
		--print(textNumber)

		-- try to recycle an old fontString
		local oldFontString = table.remove(result.fontStringPool)
		if oldFontString == nil then
			-- out of old fontStrings, create a fontString using Blizzard's normal game font as a template and put it at the overlay layer (so on top)
			self.texts[textNumber] = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		else
			self.texts[textNumber] = oldFontString
		end

		-- calculate where the topleft of the fontString is in relation to the topleft of the frame (move to right and down a little to keep from overlapping with borders) (handled by updateScrollFrame)
		--self.texts[textNumber]:SetPoint("TOPLEFT", 12, -12 - (itemHeight * textNumber))

		-- set it to the supplied text
		self.texts[textNumber]:SetText(text)

		-- set the height to the height of the font and the width so that it cannot overlap the border
		self.texts[textNumber]:SetWidth(itemWidth)
		self.texts[textNumber]:SetHeight(itemHeight)

		-- call update to allow the scroll frame to adjust itself
		self:updateScrollFrame()
	end

	function result:clearTexts()
		-- cannot delete fontStrings, so hide them and put them in the pool for recycling
		for _, fontString in ipairs(self.texts) do
			fontString:Hide()
			table.insert(result.fontStringPool, fontString)
		end

		self.texts = {}
	end

	return result
end
