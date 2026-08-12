--[[
	NDui_AbsorbOverlay
	Keep NDui's absorb bar (current health -> right).
	When absorb does not fit into missing health (incl. full HP),
	show black dashes from the left — only on the absorb fill, never
	over the whole health bar / class color.
]]

local ADDON_NAME = ...

local oUF
local registered
local MAX_CLAMP = Enum.UnitDamageAbsorbClampMode.MaximumHealth
local DASH_TEX = "Interface\\AddOns\\NDui_AbsorbOverlay\\Media\\AbsorbDash.tga"

local function ApplyDashTexture(tex)
	if not tex or tex._nduiDashApplied then return end
	tex:SetTexture(DASH_TEX, true, true)
	tex:SetHorizTile(true)
	tex:SetVertTile(true)
	tex:SetSnapToPixelGrid(false)
	tex:SetTexelSnappingBias(0)
	tex:SetVertexColor(0, 0, 0)
	tex._nduiDashApplied = true
end

local function RestyleNduiAbsorbOverlay(absorbBar)
	if not absorbBar or absorbBar._nduiDashRestyled then return end
	local fill = absorbBar:GetStatusBarTexture()
	local regions = {absorbBar:GetRegions()}
	for i = 1, #regions do
		local region = regions[i]
		if region ~= fill and region.GetObjectType and region:GetObjectType() == "Texture" then
			ApplyDashTexture(region)
		end
	end
	absorbBar._nduiDashRestyled = true
end

local function CreateOverflowBar(parent, health, template)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetPoint("TOP", health, "TOP")
	bar:SetPoint("BOTTOM", health, "BOTTOM")
	bar:SetPoint("LEFT", health, "LEFT")
	bar:SetWidth(health:GetWidth() or 1)
	bar:SetFrameLevel(template:GetFrameLevel())

	-- Invisible fill: only used to size the dash layer. Does NOT tint class color.
	bar:SetStatusBarTexture("Interface\\ChatFrame\\ChatFrameBackground")
	bar:SetStatusBarColor(1, 1, 1)
	local fill = bar:GetStatusBarTexture()
	fill:SetAlpha(0)

	bar:SetAlpha(0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:Show()

	-- Dashes ONLY on the StatusBar fill (absorb amount), not the whole frame.
	local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 7)
	overlay:SetAllPoints(fill)
	ApplyDashTexture(overlay)

	bar._shieldOverlay = overlay
	bar._calc = CreateUnitHealPredictionCalculator()
	return bar
end

local function SyncShieldOverlay(bar)
	local fill = bar:GetStatusBarTexture()
	local overlay = bar._shieldOverlay
	if not fill or not overlay then return end
	overlay:ClearAllPoints()
	overlay:SetPoint("TOPLEFT", fill, "TOPLEFT")
	overlay:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
end

local function SetBarAlpha(bar, conditioned, onAlpha)
	if bar.SetAlphaFromBoolean then
		bar:SetAlphaFromBoolean(conditioned, onAlpha, 0)
	else
		local tex = bar._shieldOverlay
		if tex and tex.SetAlphaFromBoolean then
			bar:SetAlpha(onAlpha)
			tex:SetAlphaFromBoolean(conditioned, 1, 0)
		end
	end
end

local function PostUpdate(element, unit)
	local frame = element.__owner
	local overflow = frame._absorbOverflowBar
	local healthBar = frame.Health
	if not overflow or not healthBar or not unit then return end

	local width = healthBar:GetWidth()
	if width and width > 0 then
		overflow:SetWidth(width)
	end

	-- Right bar already drew absorb that fits into missing health.
	-- Left bar should only show the overflow remainder when possible.
	local _, clamped = element.values:GetDamageAbsorbs()

	local calc = overflow._calc
	-- Amount that fits on the right (missing health).
	calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
	UnitGetDetailedHealPrediction(unit, "player", calc)
	local fit = calc:GetDamageAbsorbs()

	-- Amount capped to max health (includes full-HP shields).
	calc:SetDamageAbsorbClampMode(MAX_CLAMP)
	UnitGetDetailedHealPrediction(unit, "player", calc)
	local capped = calc:GetDamageAbsorbs()
	local maxHealth = calc:GetMaximumHealth()

	overflow:SetMinMaxValues(0, maxHealth)

	-- Prefer excess = capped - fit (secret-safe SetValue). If arithmetic
	-- fails, fall back to capped (still clipped to fill, not whole frame).
	local ok, excess = pcall(function()
		return capped - fit
	end)
	if ok then
		overflow:SetValue(excess)
	else
		overflow:SetValue(capped)
	end

	SyncShieldOverlay(overflow)
	SetBarAlpha(overflow, clamped, 1)
end

local function StyleAbsorb(frame)
	if frame._nduiAbsorbOverlay then return end
	if frame.mystyle ~= "raid" then return end

	local hp = frame.HealthPrediction
	local absorb = hp and hp.damageAbsorb
	local predic = frame.predicFrame
	local health = frame.Health
	if not hp or not absorb or not predic or not health or not hp.values then return end

	RestyleNduiAbsorbOverlay(absorb)
	frame._absorbOverflowBar = CreateOverflowBar(predic, health, absorb)

	if hp.overDamageAbsorbIndicator then
		hp.overDamageAbsorbIndicator:SetAlpha(0)
		hp.overDamageAbsorbIndicator = nil
	end

	hp.PostUpdate = PostUpdate
	frame._nduiAbsorbOverlay = true

	if hp.ForceUpdate and frame.unit then
		hp:ForceUpdate()
	end
end

local function StyleAll()
	if not oUF then return end
	for _, frame in pairs(oUF.objects) do
		StyleAbsorb(frame)
	end
end

local function Boot()
	if not NDui or not NDui.oUF then return false end
	oUF = NDui.oUF

	if not registered then
		registered = true
		oUF:RegisterInitCallback(StyleAbsorb)

		local B = NDui[1]
		if B then
			local prev = B.InitCallback
			B.InitCallback = function(...)
				if prev then prev(...) end
				StyleAll()
			end
		end
	end

	StyleAll()
	return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON_NAME then return end
		Boot()
	elseif event == "PLAYER_LOGIN" then
		Boot()
		self:UnregisterAllEvents()
	end
end)
