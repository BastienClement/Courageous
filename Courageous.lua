if not LibStub then return end

local LDB = LibStub("LibDataBroker-1.1")
if not LDB then
	print("Courageous requires a LDB-enabled addon to be display.");
	return
end

-- Find out the correct spell id for Clearcasting

local buffIDs = {
	[2]  = 137288, -- Paladin
	[5]  = 137323, -- Priest
	[7]  = 137326, -- Shaman (assumed)
	[10] = 137331, -- Monk (assumed)
	[11] = 137247  -- Druid
}

local clearcastingID = buffIDs[select(3, UnitClass("player"))]
if not clearcastingID or true then
	-- Class cannot proc Clearcasting
	local function noop() end
	LDB:NewDataObject("Courageous", { type = "data source", text = "N/A", OnClick = noop, OnTooltipShow = noop }) -- Stub LDB object
	return
end

-- Courageous Core & UI

local Courageous = {
	type = "data source",
	text = "N/A",
	
	saved = 0,
	count = 0,
	uptime = 0,
	details = {},
	
	incombat = InCombatLockdown(),
	start_time = GetTime(),
	end_time = GetTime(),
	
	cc = false,
	cc_start = 0,
	cc_time = 0,
	cc_buffer = {}
}

-- Updates the total mana saved counter
function Courageous:UpdateTotal()
	if self.cc then return end
	
	self.saved = 0
	for spell, details in pairs(self.details) do
		local _, _, _, cost = GetSpellInfo(spell)
		details.cost = cost
		self.saved = self.saved + (details.count * cost)
	end
	
	self:UpdateText()
end

-- Updates the LDB text value
function Courageous:UpdateText()
	if self.saved > 1000 then
		self.text = string.format("%.1fk", self.saved / 1000)
	else
		self.text = tostring(self.saved)
	end
end

-- Called when the player enters combat state
function Courageous:EnterCombat()
	self:Reset()
	self.incombat = true
	self.start_time = GetTime()
	self:UpdateText()
end

-- Called when the player exists combat state
function Courageous:ExitCombat()
	self.incombat = false
	self.end_time = GetTime()
	self:UpdateText()
end

-- Called when the clearcasting buff is applied on ourselve
function Courageous:EnterClearcasting(evTime)
	if not self.incombat then return end
	
	self.cc = true
	self.cc_start = GetTime()
	self.cc_time = evTime
	wipe(self.cc_buffer)
end

-- Called when the clearcasting buff wears off
function Courageous:ExitClearcasting()
	if not self.cc then return end
	
	self.cc = false
	self.count = self.count + 1
	self.uptime = self.uptime + (GetTime() - self.cc_start)
	self:UpdateTotal()
end

-- Handle every casted spell
function Courageous:SpellCast(evTime, spellid)
	-- Ignore casts when not in clearcasting or combat
	if not self.cc or not self.incombat then return end
	if evTime <= self.cc_time then return end
	
	-- Checks that the spell costs mana
	local _, _, _, _, _, powerType = GetSpellInfo(spellid)
	if powerType ~= 0 then return end
	
	if not self.details[spellid] then
		self.details[spellid] = { count = 0, cost = 0 }
	end
	
	local spellDetails = self.details[spellid]
	spellDetails.count = spellDetails.count + 1
end

-- Reset all state variables
function Courageous:Reset()
	self.saved = 0
	self.count = 0
	self.uptime = 0
	self.incombat = false
	self.cc = false
	wipe(self.details)
end

-- No click handler
function Courageous:OnClick()
	return false
end

-- Display the tooltip with detailed informations
function Courageous:OnTooltipShow()
	local length
	if Courageous.incombat then
		length = GetTime() - Courageous.start_time
	else
		length = Courageous.end_time - Courageous.start_time
	end
	
	if length == 0 then
		return false
	end
	
	self:AddLine("Courageous")
	self:AddLine(" ")
	
	local mp5 = (Courageous.saved / length) * 5
	local uptime = (Courageous.uptime / length) * 100
	
	local length_text
	if length >= 60 then
		local minutes = math.floor(length / 60)
		local seconds = length - (minutes * 60)
		length_text = string.format("%d min %d sec", minutes, seconds)
	else
		length_text = string.format("%d sec", length)
	end
	
	self:AddLine("Last fight data:")
	self:AddDoubleLine("Fight length:", length_text, 1, 1, 1, 0, 1, 0)
	self:AddDoubleLine("Total mana saved:", tostring(Courageous.saved), 1, 1, 1, 0, 1, 0)
	self:AddDoubleLine("Equivalent MP5:", string.format("%.1f mp5", mp5), 1, 1, 1, 0, 1, 0)
	self:AddDoubleLine("Proc count:", tostring(Courageous.count), 1, 1, 1, 0, 1, 0)
	self:AddDoubleLine("Uptime:", string.format("%.1f%%", uptime), 1, 1, 1, 0, 1, 0)
	
	local spells = {}
	for spellid, details in pairs(Courageous.details) do
		local count = details.count
		local cost = details.cost
		local saved = count * cost
		
		if saved > 0 then
			table.insert(spells, { id = spellid, count = count, cost = cost, saved = saved })
		end
	end
	
	if #spells < 1 then return end
	
	table.sort(spells, function(a, b) return a.saved > b.saved end)
	
	self:AddLine(" ")
	self:AddLine("Spell details:")
	
	for _, spell in pairs(spells) do
		local name, _, icon = GetSpellInfo(spell.id)
		self:AddDoubleLine(name, string.format("%d (%dx)", spell.saved, spell.count), 1, 1, 1, 0, 1, 0)
		self:AddTexture(icon)
	end
end

-- Listener

local f = CreateFrame("frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function(_, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local evTime, ev = ...
		local spellid = select(12, ...)
		
		if ev == "SPELL_AURA_APPLIED" or ev == "SPELL_AURA_REMOVED" then
			-- I'm only interested in Clearcasting
			if spellid ~= clearcastingID then return end
			
			-- And only when it's on myself
			local guid = select(8, ...)
			if UnitGUID("player") ~= guid then return end
			
			if ev == "SPELL_AURA_APPLIED" then
				Courageous:EnterClearcasting(evTime)
			else
				Courageous:ExitClearcasting()
			end
		elseif ev == "SPELL_CAST_SUCCESS" then
			-- Any cast done by myself
			local guid = select(4, ...)
			if UnitGUID("player") ~= guid then return end
			
			Courageous:SpellCast(evTime, spellid)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		Courageous:EnterCombat()
	elseif event == "PLAYER_REGEN_ENABLED" then
		Courageous:ExitCombat()
	end
end)

-- Register with LDB

LDB:NewDataObject("Courageous", Courageous)
