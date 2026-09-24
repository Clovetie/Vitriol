--!strict
-- QTEOverlay.luau
-- Location: ReplicatedStorage > QTE > UI > QTEOverlay  (ModuleScript)
-- Purpose:  The QTE overlay's interface, as DATA. One spec table describes every
--           instance; `build` walks it, `ensure` reuses (or completes) whatever is
--           already in PlayerGui, and tools/qte-build-ui.js walks the SAME spec to
--           emit the Studio-importable model (QTEOverlay.rbxmx) and the layout
--           preview (QTEOverlay.preview.svg). Nothing here is drawn by hand twice,
--           so the model you import cannot drift from what the code builds.
--
--           DESIGN (see README.md §8):
--             * a scrim, so the struggle reads as a takeover rather than a popup,
--             * a title the player can read at a glance, a faint accent rule that
--               carries the QTE's own colour, the widget stage, a thin timer RULE
--               (never a graph — no HUD bars), a hint line and one verdict word.
--             * TextScaled + UITextSizeConstraint everywhere, so it is legible at
--               480p and still scaled on a 4K display (a bare TextSize is
--               resolution-dependent and a bare TextScaled can go to 4 px).
--             * IgnoreGuiInset, so the layout is the same on every platform and
--               the mouse maths in the shell (which subtracts GuiService:GetGuiInset)
--               lands in the same space the widgets are drawn in.
--
--           NOTHING HERE IS PER-FRAME. Build once at boot; the shell writes text,
--           colours, sizes and visibility on the pooled widgets under Stage.
--
-- Requires: (none — this module is deliberately dependency-free so it can also be
--           pasted into a different project on its own)
-- Used by:  Client/QTEStruggle, tools/qte-build-ui.js
--
-- INSTALLING IT BY HAND (optional):
--   1. Drag QTEOverlay.rbxmx into StarterGui. Studio copies it into PlayerGui on
--      every spawn; `ResetOnSpawn = false` keeps it alive across respawns.
--   2. Restyle it there however you like. `ensure` only fills in MISSING nodes and
--      never overwrites a property it did not create, so hand edits survive.
--   3. Do nothing at all — the shell builds this tree at runtime if it is absent.

local QTEOverlay = {}

-- ── Palette ──────────────────────────────────────────────────────────────────
-- Muted paper and ink, one accent used sparingly (the accent rule + the timer
-- fill). The shell tints both with the running QTE's own accent colour from
-- Lib/QTECatalog, so each family reads slightly differently without any extra art.
QTEOverlay.Theme = {
	Scrim = { 10, 10, 12 },
	Paper = { 238, 233, 222 }, -- instruction text
	Muted = { 186, 179, 165 }, -- hint text
	Ink = { 16, 16, 20 }, -- track / rule backgrounds
	Accent = { 198, 74, 58 }, -- default accent, overridden per QTE
	Good = { 150, 205, 160 }, -- verdict tint on a win
	Danger = { 226, 96, 84 }, -- verdict tint on a loss
	ScrimTransparency = 0.45,
	InkTransparency = 0.45,
	StrokeTransparency = 0.35,
}

-- ── Small constructors, so the spec below reads like a layout and not like code ─
local function rgb(c: any): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function scale(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

local function at(x: number, y: number): UDim2
	return UDim2.fromScale(x, y)
end

local function anchor(x: number, y: number): Vector2
	return Vector2.new(x, y)
end

local function text(props: any): any
	-- Every label gets the same legibility treatment; callers only describe
	-- content-specific bits (font, colour, size, constraint range).
	local base = {
		BackgroundTransparency = 1,
		-- TextScaled auto-enables wrapping and ignores TextSize; the child
		-- UITextSizeConstraint is what keeps the result legible at 480p.
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextStrokeTransparency = QTEOverlay.Theme.StrokeTransparency,
		RichText = false,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return base
end

local function label(node: any, minSize: number, maxSize: number): any
	node.children = node.children or {}
	node.children[#node.children + 1] = {
		class = "UITextSizeConstraint",
		name = "SizeConstraint",
		props = { MinTextSize = minSize, MaxTextSize = maxSize },
	}
	return node
end

-- ── The layout ───────────────────────────────────────────────────────────────
-- Geometry is anchored and centred, so the composition holds from 480p to 4K.
-- Only the two text boxes and the two rules use px offsets; every container is
-- scale-based. `Root` is the frame the shell shows and hides.
QTEOverlay.Spec = {
	class = "ScreenGui",
	name = "QTEOverlay",
	props = {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
	},
	children = {
		{
			class = "Frame",
			name = "Scrim",
			props = {
				BackgroundColor3 = rgb(QTEOverlay.Theme.Scrim),
				BackgroundTransparency = QTEOverlay.Theme.ScrimTransparency,
				BorderSizePixel = 0,
				Size = scale(1, 1),
				Position = at(0, 0),
				ZIndex = 1,
				Visible = false,
			},
		},
		{
			class = "Frame",
			name = "QTE",
			props = {
				AnchorPoint = anchor(0.5, 0.5),
				Position = at(0.5, 0.45),
				Size = scale(0.66, 0.42),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 20,
			},
			children = {
				label({
					class = "TextLabel",
					name = "Title",
					props = text({
						AnchorPoint = anchor(0.5, 1),
						Position = UDim2.new(0.5, 0, 0, -6),
						Size = UDim2.new(1, 0, 0, 30),
						Font = Enum.Font.GothamBold,
						TextColor3 = rgb(QTEOverlay.Theme.Paper),
					}),
				}, 14, 30),
				{
					class = "Frame",
					name = "Accent",
					props = {
						AnchorPoint = anchor(0.5, 1),
						Position = UDim2.new(0.5, 0, 0, -2),
						Size = UDim2.new(0.18, 0, 0, 2),
						BackgroundColor3 = rgb(QTEOverlay.Theme.Accent),
						BackgroundTransparency = 0.15,
						BorderSizePixel = 0,
					},
				},
				{
					class = "Frame",
					name = "Stage",
					props = {
						Position = at(0, 0),
						Size = UDim2.new(1, 0, 1, -26),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClipsDescendants = false,
					},
				},
				{
					class = "Frame",
					name = "Timer",
					props = {
						AnchorPoint = anchor(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -4),
						Size = UDim2.new(0.86, 0, 0, 2),
						BackgroundColor3 = rgb(QTEOverlay.Theme.Ink),
						BackgroundTransparency = QTEOverlay.Theme.InkTransparency,
						BorderSizePixel = 0,
					},
					children = {
						{
							class = "Frame",
							name = "Fill",
							props = {
								Position = at(0, 0),
								Size = scale(1, 1),
								BackgroundColor3 = rgb(QTEOverlay.Theme.Accent),
								BorderSizePixel = 0,
							},
						},
					},
				},
				{
					class = "TextLabel",
					name = "Verdict",
					props = text({
						AnchorPoint = anchor(0.5, 0.5),
						Position = at(0.5, 0.5),
						Size = UDim2.new(1, 0, 0, 40),
						Font = Enum.Font.GothamBlack,
						TextColor3 = rgb(QTEOverlay.Theme.Paper),
						TextTransparency = 1,
						TextStrokeTransparency = 0.5,
						ZIndex = 30,
					}),
				},
				label({
					class = "TextLabel",
					name = "Hint",
					props = text({
						AnchorPoint = anchor(0.5, 0),
						Position = UDim2.new(0.5, 0, 1, 8),
						Size = UDim2.new(1, 0, 0, 20),
						Font = Enum.Font.Gotham,
						TextColor3 = rgb(QTEOverlay.Theme.Muted),
						TextStrokeTransparency = 0.6,
					}),
				}, 12, 20),
			},
		},
	},
}

-- Children the rest of the system looks up by name. `ensure` completes exactly
-- these if a hand-authored tree is missing them, and nothing else.
QTEOverlay.Required = { "QTE", "QTE/Title", "QTE/Hint", "QTE/Stage", "QTE/Timer", "QTE/Timer/Fill", "QTE/Verdict" }

QTEOverlay.Parts = {
	root = "QTE",
	title = "QTE/Title",
	accent = "QTE/Accent",
	hint = "QTE/Hint",
	surface = "QTE/Stage",
	timer = "QTE/Timer",
	fill = "QTE/Timer/Fill",
	verdict = "QTE/Verdict",
	scrim = "Scrim",
}

-- ── Building ─────────────────────────────────────────────────────────────────
local function apply(instance: any, props: any): ()
	for key, value in pairs(props) do
		instance[key] = value
	end
end

local function buildNode(node: any, parent: any, opts: any): any
	local instance = Instance.new(node.class)
	instance.Name = node.name
	if not (opts and opts.keepAuthoredLook) then
		apply(instance, node.props)
	end
	instance.Parent = parent
	local children = node.children or {}
	for i = 1, #children do
		buildNode(children[i], instance, opts)
	end
	return instance
end

-- build(parent, opts?) -> ScreenGui
-- Always constructs a fresh overlay. `parent` is normally PlayerGui.
function QTEOverlay.build(parent: any, opts: any?): any
	local o = opts or {}
	local spec = QTEOverlay.Spec
	local gui = Instance.new(spec.class)
	gui.Name = o.name or spec.name
	apply(gui, spec.props)
	gui.Parent = parent
	local children = spec.children or {}
	for i = 1, #children do
		buildNode(children[i], gui, nil)
	end
	return gui
end

-- ensure(parent, opts?) -> ScreenGui
--
-- Returns the overlay, building whatever is missing. An instance that already
-- exists under `parent` is REUSED and never restyled: import QTEOverlay.rbxmx,
-- restyle it in Studio, and this call becomes a no-op. Only nodes the spec asks
-- for and the tree does not have are created.
function QTEOverlay.ensure(parent: any, opts: any?): any
	if parent == nil then
		return nil
	end
	local o = opts or {}
	local spec = QTEOverlay.Spec
	local gui = parent[o.name or spec.name]
	if gui == nil then
		gui = QTEOverlay.build(parent, o)
		return gui
	end
	local function complete(node: any, host: any): ()
		for i = 1, #(node.children or {}) do
			local child = node.children[i]
			local existing = host[child.name]
			if existing == nil then
				existing = buildNode(child, host, { keepAuthoredLook = false })
			else
				complete(child, existing)
			end
		end
	end
	complete(spec, gui)
	return gui
end

-- parts(gui) -> { root, title, accent, hint, surface, timer, fill, verdict, scrim }
-- One traversal, at the start of a run, never per frame.
function QTEOverlay.parts(gui: any): any
	if gui == nil then
		return nil
	end
	local out = {}
	for key, path in pairs(QTEOverlay.Parts) do
		local node = gui
		for segment in string.gmatch(path, "[^/]+") do
			node = node and node[segment] or nil
		end
		out[key] = node
	end
	return out
end

-- setVisible(gui, visible) -> ()
-- Shows/hides the whole takeover, scrim included, in one call.
function QTEOverlay.setVisible(gui: any, visible: boolean): ()
	if gui == nil then
		return
	end
	local scrim = gui[QTEOverlay.Parts.scrim]
	if scrim ~= nil then
		scrim.Visible = visible
	end
	local root = gui[QTEOverlay.Parts.root]
	if root ~= nil then
		root.Visible = visible
	end
end

return QTEOverlay
