-- assist — basketball positioning tool

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────────────────────

local CFG = {
	AFK_TIMEOUT     = 2.5,
	BALL_RADIUS     = 25,
	INPUT_THRESHOLD = 0.15,
	MOVE_HZ         = 1/20,
	JITTER_SMOOTH   = 0.18,
	PRESSURE_DIST   = 5,
	PRESSURE_SPEED  = 0.5,
	SENSITIVITY     = 1.0,
	REACTION_DELAY  = 0,
	HUMANIZE        = true,
	PRESSURE_ON     = true,
	BALL_NAMES      = { Ball = true, Basketball = true },
}

-- ─── State ────────────────────────────────────────────────────────────────────

local owning         = false
local lastInputTime  = tick()
local lastMoveTime   = 0
local smoothBallPos  = nil
local lastRawBallPos = nil
local ballVel        = Vector3.new()
local cachedBall     = nil
local ballConnection = nil
local reactionTimer  = 0
local humanizeOffset = Vector3.new()
local humanizeTimer  = 0
local heartbeatConn  = nil
local inputConns     = {}

-- ─── Ball Logic ───────────────────────────────────────────────────────────────

local function clearBallCache()
	cachedBall = nil
	if ballConnection then ballConnection:Disconnect(); ballConnection = nil end
end

local function watchBall(part)
	cachedBall     = part
	smoothBallPos  = part.Position
	lastRawBallPos = part.Position
	ballVel        = Vector3.new()
	if ballConnection then ballConnection:Disconnect() end
	ballConnection = part.AncestryChanged:Connect(function()
		if not part or not part.Parent then clearBallCache() end
	end)
end

local function findBall()
	local char = LocalPlayer.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local hrpPos = hrp.Position
	local best, bestD
	for _, v in next, workspace:GetDescendants() do
		local part
		if v:IsA("BasePart") and CFG.BALL_NAMES[v.Name] then
			local anc, ours = v.Parent, false
			while anc do
				if anc == char then ours = true; break end
				anc = anc.Parent
			end
			if not ours then part = v end
		end
		if part then
			local d = (part.Position - hrpPos).Magnitude
			if d <= CFG.BALL_RADIUS and (not bestD or d < bestD) then
				best, bestD = part, d
			end
		end
	end
	if best then watchBall(best) end
end

local function hasBall()
	local char = LocalPlayer.Character
	if not char then return false end
	for _, v in next, char:GetDescendants() do
		if CFG.BALL_NAMES[v.Name] then return true end
	end
	return false
end

local function isAFK()
	return tick() - lastInputTime > CFG.AFK_TIMEOUT
end

local function randomOffset()
	return Vector3.new((math.random()-0.5)*0.6, 0, (math.random()-0.5)*0.6)
end

-- ─── Unload ───────────────────────────────────────────────────────────────────

local function unload()
	owning = false
	clearBallCache()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	for _, c in next, inputConns do c:Disconnect() end
	inputConns = {}
	local gui = game:GetService("CoreGui"):FindFirstChild("__assist")
	if gui then gui:Destroy() end
end

-- ─── Input tracking ───────────────────────────────────────────────────────────

table.insert(inputConns, UserInputService.InputBegan:Connect(function()   lastInputTime = tick() end))
table.insert(inputConns, UserInputService.InputChanged:Connect(function() lastInputTime = tick() end))

-- ─── UI ───────────────────────────────────────────────────────────────────────

local cg = game:GetService("CoreGui")
local existing = cg:FindFirstChild("__assist")
if existing then existing:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name           = "__assist"
sg.ResetOnSpawn   = false
sg.DisplayOrder   = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = cg

-- Colour palette
local C = {
	bg        = Color3.fromRGB(9,  9,  9),
	surface   = Color3.fromRGB(15, 15, 15),
	surface2  = Color3.fromRGB(20, 20, 20),
	row       = Color3.fromRGB(13, 13, 13),
	border    = Color3.fromRGB(32, 32, 32),
	text      = Color3.fromRGB(160, 160, 160),
	muted     = Color3.fromRGB(75,  75,  75),
	dim       = Color3.fromRGB(42,  42,  42),
	green     = Color3.fromRGB(72,  200, 90),
	greenBg   = Color3.fromRGB(18,  48,  22),
	amber     = Color3.fromRGB(215, 155, 45),
	yellow    = Color3.fromRGB(200, 185, 55),
	red       = Color3.fromRGB(180, 55,  55),
	redBg     = Color3.fromRGB(40,  12,  12),
}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function corner(inst, r)
	local c = Instance.new("UICorner", inst)
	c.CornerRadius = UDim.new(0, r or 6)
	return c
end

local function stroke(inst, col, thick, trans)
	local s = Instance.new("UIStroke", inst)
	s.Color        = col or C.border
	s.Thickness    = thick or 1
	s.Transparency = trans or 0
	return s
end

local function frame(parent, props)
	local f = Instance.new("Frame", parent)
	f.BackgroundTransparency = props.trans or 0
	f.BackgroundColor3       = props.bg   or C.bg
	f.BorderSizePixel        = 0
	f.Size                   = props.size or UDim2.new(1,0,0,24)
	f.Position               = props.pos  or UDim2.new(0,0,0,0)
	if props.zindex then f.ZIndex = props.zindex end
	return f
end

local function label(parent, text, props)
	local l = Instance.new("TextLabel", parent)
	l.BackgroundTransparency = 1
	l.BorderSizePixel        = 0
	l.Text                   = text
	l.Font                   = props.font  or Enum.Font.Gotham
	l.TextSize               = props.size  or 10
	l.TextColor3             = props.color or C.text
	l.TextXAlignment         = props.xa    or Enum.TextXAlignment.Left
	l.TextYAlignment         = props.ya    or Enum.TextYAlignment.Center
	l.Size                   = props.sz    or UDim2.new(1, 0, 1, 0)
	l.Position               = props.pos   or UDim2.new(0, 0, 0, 0)
	l.ZIndex                 = props.zindex or 1
	return l
end

local function btn(parent, text, props)
	local b = Instance.new("TextButton", parent)
	b.BackgroundColor3       = props.bg    or C.surface2
	b.BackgroundTransparency = props.trans or 0
	b.BorderSizePixel        = 0
	b.Text                   = text
	b.Font                   = props.font  or Enum.Font.Gotham
	b.TextSize               = props.size  or 10
	b.TextColor3             = props.color or C.muted
	b.AutoButtonColor        = false
	b.Size                   = props.sz    or UDim2.new(0, 60, 0, 22)
	b.Position               = props.pos   or UDim2.new(0, 0, 0, 0)
	b.ZIndex                 = props.zindex or 2
	return b
end

-- ── Stealth dot ──────────────────────────────────────────────────────────────
-- Small pill in top-right corner; always on screen.
-- Click anywhere in the 30x30 hit area to show/hide panel.

local DOT_W, DOT_H = 6, 6
local DOT_RIGHT, DOT_TOP = 18, 18

local dotVis = frame(sg, {
	bg   = C.dim,
	size = UDim2.new(0, DOT_W, 0, DOT_H),
	pos  = UDim2.new(1, -(DOT_RIGHT + DOT_W), 0, DOT_TOP),
	zindex = 50,
	trans = 0,
})
corner(dotVis, 99)

local dotHit = btn(sg, "", {
	bg    = C.bg,
	trans = 1,
	sz    = UDim2.new(0, 28, 0, 28),
	pos   = UDim2.new(1, -(DOT_RIGHT + DOT_W + 11), 0, DOT_TOP - 11),
	zindex = 51,
})

-- ── Panel ────────────────────────────────────────────────────────────────────

local PW = 204   -- panel width
local PX = -(PW + 12)  -- right edge offset
local PY = 10    -- top offset

-- Row heights (all explicit, no UIListLayout fighting absolute positioning)
local ROW_H      = 30
local HDR_H      = 36
local SEC_H      = 22
local DIVIDER_H  = 1
local BTN_H      = 34
local FOOT_H     = 28
local PAD        = 8   -- left/right inner padding

-- We'll accumulate total height as we place rows
local rows = {}   -- { height }
local function addRow(h) rows[#rows+1] = h end

-- Calculate layout slots
-- header
addRow(HDR_H)
-- detection section
addRow(DIVIDER_H) addRow(SEC_H)
addRow(ROW_H) addRow(ROW_H) addRow(ROW_H)
-- smoothing
addRow(DIVIDER_H) addRow(SEC_H)
addRow(ROW_H)
-- pressure
addRow(DIVIDER_H) addRow(SEC_H)
addRow(ROW_H) addRow(ROW_H)
-- options
addRow(DIVIDER_H) addRow(SEC_H)
addRow(ROW_H) addRow(ROW_H)
-- activate
addRow(DIVIDER_H) addRow(BTN_H)
-- unload
addRow(FOOT_H)

local totalH = 0
local rowY   = {}
for i, h in ipairs(rows) do
	rowY[i]  = totalH
	totalH   = totalH + h
end

local panel = frame(sg, {
	bg   = C.bg,
	size = UDim2.new(0, PW, 0, totalH),
	pos  = UDim2.new(1, PX, 0, PY),
})
corner(panel, 10)
stroke(panel, C.border, 1, 0)
panel.Active   = true
panel.Draggable = true

-- ── Header ───────────────────────────────────────────────────────────────────

local rowIdx = 1
local hdr = frame(panel, {
	bg   = C.surface,
	size = UDim2.new(1, 0, 0, HDR_H),
	pos  = UDim2.new(0, 0, 0, rowY[rowIdx]),
})
-- only round top corners
corner(hdr, 10)
local hdrFix = frame(hdr, {
	bg   = C.surface,
	size = UDim2.new(1, 0, 0, 10),
	pos  = UDim2.new(0, 0, 1, -10),
})

label(hdr, "assist", {
	font  = Enum.Font.GothamBold,
	size  = 11,
	color = C.muted,
	sz    = UDim2.new(0, 60, 1, 0),
	pos   = UDim2.new(0, PAD+4, 0, 0),
})

-- status badge in header
local badgeW = 58
local badge = frame(hdr, {
	bg   = C.surface2,
	size = UDim2.new(0, badgeW, 0, 18),
	pos  = UDim2.new(1, -(badgeW + PAD), 0.5, -9),
})
corner(badge, 5)
local badgeStroke = stroke(badge, C.border, 1, 0)

local badgeLbl = label(badge, "off", {
	font  = Enum.Font.GothamBold,
	size  = 9,
	color = C.dim,
	xa    = Enum.TextXAlignment.Center,
	sz    = UDim2.new(1, 0, 1, 0),
	zindex = 2,
})
rowIdx = rowIdx + 1

-- ── Row builder helpers ───────────────────────────────────────────────────────

local function makeDividerAt(yPos)
	local d = frame(panel, {
		bg   = C.border,
		size = UDim2.new(1, -(PAD*2), 0, 1),
		pos  = UDim2.new(0, PAD, 0, yPos),
	})
end

local function makeSectionAt(yPos, text)
	local s = frame(panel, {
		bg   = C.bg,
		size = UDim2.new(1, 0, 0, SEC_H),
		pos  = UDim2.new(0, 0, 0, yPos),
		trans = 1,
	})
	label(s, string.upper(text), {
		font  = Enum.Font.GothamBold,
		size  = 8,
		color = C.dim,
		sz    = UDim2.new(1, -(PAD*2), 1, 0),
		pos   = UDim2.new(0, PAD+4, 0, 0),
	})
end

-- value row: label | value | − | +
local function makeValueRowAt(yPos, lText, vText, onMinus, onPlus)
	local r = frame(panel, {
		bg   = C.bg,
		size = UDim2.new(1, 0, 0, ROW_H),
		pos  = UDim2.new(0, 0, 0, yPos),
		trans = 1,
	})

	label(r, lText, {
		size  = 10,
		color = C.text,
		sz    = UDim2.new(0, 90, 1, 0),
		pos   = UDim2.new(0, PAD+4, 0, 0),
	})

	local valLbl = label(r, vText, {
		font  = Enum.Font.GothamBold,
		size  = 10,
		color = C.muted,
		xa    = Enum.TextXAlignment.Center,
		sz    = UDim2.new(0, 38, 1, 0),
		pos   = UDim2.new(0, 100, 0, 0),
	})

	local BW, BH = 20, 20
	local function makeAdjBtn(xOff, sym)
		local b = btn(r, sym, {
			bg    = C.surface2,
			font  = Enum.Font.GothamBold,
			size  = 12,
			color = C.muted,
			sz    = UDim2.new(0, BW, 0, BH),
			pos   = UDim2.new(1, xOff, 0.5, -BH/2),
			zindex = 3,
		})
		corner(b, 5)
		stroke(b, C.border, 1, 0)
		return b
	end

	local minusB = makeAdjBtn(-(BW*2 + PAD + 4), "−")
	local plusB  = makeAdjBtn(-(BW   + PAD),     "+")

	minusB.MouseButton1Click:Connect(onMinus)
	plusB.MouseButton1Click:Connect(onPlus)

	return valLbl
end

-- toggle row: label | pill toggle
local function makeToggleRowAt(yPos, lText, initState, onChange)
	local r = frame(panel, {
		bg   = C.bg,
		size = UDim2.new(1, 0, 0, ROW_H),
		pos  = UDim2.new(0, 0, 0, yPos),
		trans = 1,
	})

	label(r, lText, {
		size  = 10,
		color = C.text,
		sz    = UDim2.new(0, 130, 1, 0),
		pos   = UDim2.new(0, PAD+4, 0, 0),
	})

	local TW, TH = 34, 16
	local track = frame(r, {
		bg   = initState and C.greenBg or C.surface2,
		size = UDim2.new(0, TW, 0, TH),
		pos  = UDim2.new(1, -(TW + PAD + 2), 0.5, -TH/2),
	})
	corner(track, 99)
	local ts = stroke(track, initState and C.green or C.border, 1, initState and 0.7 or 0)

	local KS = 10
	local knob = frame(track, {
		bg   = initState and C.green or C.muted,
		size = UDim2.new(0, KS, 0, KS),
		pos  = initState and UDim2.new(1, -(KS+3), 0.5, -KS/2) or UDim2.new(0, 3, 0.5, -KS/2),
	})
	corner(knob, 99)

	local state = initState

	local hitbox = btn(r, "", {
		trans  = 1,
		sz     = UDim2.new(0, TW+16, 0, TH+12),
		pos    = UDim2.new(1, -(TW+PAD+10), 0.5, -(TH+12)/2),
		zindex = 5,
	})
	hitbox.MouseButton1Click:Connect(function()
		state = not state
		track.BackgroundColor3 = state and C.greenBg or C.surface2
		ts.Color               = state and C.green or C.border
		ts.Transparency        = state and 0.7 or 0
		knob.Position          = state and UDim2.new(1,-(KS+3),0.5,-KS/2) or UDim2.new(0,3,0.5,-KS/2)
		knob.BackgroundColor3  = state and C.green or C.muted
		onChange(state)
	end)
end

local function wireValueRow(yPos, lText, key, minV, maxV, step, fmt)
	local function fmtV() return fmt(CFG[key]) end
	local vl = makeValueRowAt(yPos, lText, fmtV(),
		function()
			CFG[key] = math.max(minV, math.floor((CFG[key]-step)*1000+0.5)/1000)
			if key == "BALL_RADIUS" then clearBallCache() end
			vl.Text = fmtV()
		end,
		function()
			CFG[key] = math.min(maxV, math.floor((CFG[key]+step)*1000+0.5)/1000)
			vl.Text = fmtV()
		end
	)
end

-- ── Place all rows ───────────────────────────────────────────────────────────

rowIdx = 2  -- 1 = header (already done)

makeDividerAt(rowY[rowIdx]); rowIdx = rowIdx + 1
makeSectionAt(rowY[rowIdx], "detection"); rowIdx = rowIdx + 1
wireValueRow(rowY[rowIdx], "radius",      "BALL_RADIUS",    5,    60,  5,    function(v) return v.."st" end);         rowIdx = rowIdx + 1
wireValueRow(rowY[rowIdx], "sensitivity", "SENSITIVITY",    0.1,  2.0, 0.1,  function(v) return math.floor(v*100).."%"end); rowIdx = rowIdx + 1
wireValueRow(rowY[rowIdx], "delay",       "REACTION_DELAY", 0,    1.0, 0.05, function(v) return v.."s" end);          rowIdx = rowIdx + 1

makeDividerAt(rowY[rowIdx]); rowIdx = rowIdx + 1
makeSectionAt(rowY[rowIdx], "smoothing"); rowIdx = rowIdx + 1
wireValueRow(rowY[rowIdx], "jitter",      "JITTER_SMOOTH",  0.02, 0.5, 0.02, function(v) return v end);              rowIdx = rowIdx + 1

makeDividerAt(rowY[rowIdx]); rowIdx = rowIdx + 1
makeSectionAt(rowY[rowIdx], "pressure"); rowIdx = rowIdx + 1
wireValueRow(rowY[rowIdx], "speed",       "PRESSURE_SPEED", 0,    2.0, 0.1,  function(v) return v end);              rowIdx = rowIdx + 1
wireValueRow(rowY[rowIdx], "afk after",   "AFK_TIMEOUT",    2,    30,  1,    function(v) return v.."s" end);         rowIdx = rowIdx + 1

makeDividerAt(rowY[rowIdx]); rowIdx = rowIdx + 1
makeSectionAt(rowY[rowIdx], "options"); rowIdx = rowIdx + 1
makeToggleRowAt(rowY[rowIdx], "humanize", CFG.HUMANIZE,    function(v) CFG.HUMANIZE    = v end); rowIdx = rowIdx + 1
makeToggleRowAt(rowY[rowIdx], "pressure", CFG.PRESSURE_ON, function(v) CFG.PRESSURE_ON = v end); rowIdx = rowIdx + 1

makeDividerAt(rowY[rowIdx]); rowIdx = rowIdx + 1

-- ── Activate button ──

local actY = rowY[rowIdx]; rowIdx = rowIdx + 1
local actPad = 5
local toggleBtn = btn(panel, "activate", {
	bg    = C.surface2,
	font  = Enum.Font.GothamBold,
	size  = 10,
	color = C.muted,
	sz    = UDim2.new(1, -(PAD*2), 0, BTN_H - actPad*2),
	pos   = UDim2.new(0, PAD, 0, actY + actPad),
	zindex = 3,
})
corner(toggleBtn, 7)
local tStroke = stroke(toggleBtn, C.border, 1, 0)

-- ── Unload button ──

local footY = rowY[rowIdx]
local unloadBtn = btn(panel, "unload", {
	bg    = C.bg,
	trans = 0,
	font  = Enum.Font.Gotham,
	size  = 9,
	color = Color3.fromRGB(80, 42, 42),
	sz    = UDim2.new(1, -(PAD*2), 0, FOOT_H - 10),
	pos   = UDim2.new(0, PAD, 0, footY + 5),
	zindex = 3,
})
corner(unloadBtn, 6)
stroke(unloadBtn, Color3.fromRGB(55, 28, 28), 1, 0)

-- ─── Status & state ──────────────────────────────────────────────────────────

local function setStatus(text, color)
	badgeLbl.Text             = text
	badgeLbl.TextColor3       = color
	badgeStroke.Color         = color
	badgeStroke.Transparency  = 0.55
	dotVis.BackgroundColor3   = color
end

local function setState(state)
	owning         = state
	smoothBallPos  = nil
	lastRawBallPos = nil
	ballVel        = Vector3.new()
	reactionTimer  = 0
	if not state then clearBallCache() end
	if state then
		setStatus("active", C.green)
		toggleBtn.Text             = "deactivate"
		toggleBtn.TextColor3       = C.green
		toggleBtn.BackgroundColor3 = C.greenBg
		tStroke.Color              = C.green
		tStroke.Transparency       = 0.55
	else
		setStatus("off", C.dim)
		toggleBtn.Text             = "activate"
		toggleBtn.TextColor3       = C.muted
		toggleBtn.BackgroundColor3 = C.surface2
		tStroke.Color              = C.border
		tStroke.Transparency       = 0
	end
end

-- ─── Button wiring ───────────────────────────────────────────────────────────

dotHit.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

toggleBtn.MouseButton1Click:Connect(function() setState(not owning) end)
unloadBtn.MouseButton1Click:Connect(function() unload() end)

-- ─── Main loop ───────────────────────────────────────────────────────────────

heartbeatConn = RunService.Heartbeat:Connect(function()
	if not owning then return end
	local now = tick()
	if now - lastMoveTime < CFG.MOVE_HZ then return end
	lastMoveTime = now

	if isAFK() then setStatus("afk", C.amber); return end
	if hasBall() then setStatus("holding", C.yellow); return end

	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local myHRP    = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not myHRP then return end

	if not cachedBall or not cachedBall.Parent then findBall() end

	local ball = cachedBall
	if not ball or not ball.Parent then
		setStatus("scanning", C.muted)
		return
	end

	local rawPos = ball.Position
	if not smoothBallPos then
		smoothBallPos  = rawPos
		lastRawBallPos = rawPos
	else
		local rawDelta = rawPos - lastRawBallPos
		ballVel        = ballVel:Lerp(rawDelta, 0.25)
		lastRawBallPos = rawPos
		smoothBallPos  = smoothBallPos:Lerp(rawPos + ballVel*3, CFG.JITTER_SMOOTH)
	end

	if CFG.REACTION_DELAY > 0 then
		reactionTimer = reactionTimer + CFG.MOVE_HZ
		if reactionTimer < CFG.REACTION_DELAY then
			setStatus("active", C.green)
			return
		end
		reactionTimer = 0
	end

	setStatus("active", C.green)

	local moveDir = humanoid.MoveDirection
	if moveDir and moveDir.Magnitude > CFG.INPUT_THRESHOLD then return end

	local myPos  = myHRP.Position
	local right  = myHRP.CFrame.RightVector
	local fwd    = myHRP.CFrame.LookVector
	local delta  = smoothBallPos - myPos
	local latOff = delta:Dot(right) * CFG.SENSITIVITY
	local fwdOff = delta:Dot(fwd)
	local speed  = ballVel.Magnitude

	if CFG.HUMANIZE then
		humanizeTimer = humanizeTimer + CFG.MOVE_HZ
		if humanizeTimer > 0.8 then
			humanizeOffset = randomOffset()
			humanizeTimer  = 0
		end
	else
		humanizeOffset = Vector3.new()
	end

	local target
	if speed < 0.04 and CFG.PRESSURE_ON then
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > CFG.PRESSURE_DIST then
			target = myPos + flat.Unit * CFG.PRESSURE_SPEED + humanizeOffset
		else
			target = myPos + right * latOff + humanizeOffset
		end
	else
		target = myPos + right * latOff + fwd * (fwdOff * 0.12) + humanizeOffset
	end

	humanoid:MoveTo(target)
end)

setState(false)
