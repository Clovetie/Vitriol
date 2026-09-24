#!/usr/bin/env node
"use strict";

/**
 * qte-build-ui.js — generates the QTE overlay's UI artifacts from the module that
 * describes it.
 *
 * The QTE package's interface is not hand-drawn twice. `qte/UI/QTEOverlay.luau`
 * holds one spec table; this tool EXECUTES that module inside fengari with a small
 * Roblox stub, reads back the tree it built, and emits:
 *
 *   qte/UI/QTEOverlay.rbxmx          a Studio-importable model (drag into StarterGui)
 *   qte/UI/QTEOverlay.preview.svg    a layout preview at the reference resolution
 *
 * Because both come from the same run, the model you import cannot drift from what
 * `QTEOverlay.ensure` builds at runtime. The run also asserts - and fails on - the
 * things a human would otherwise have to check by eye:
 *
 *   * every part the shell looks up by name exists in the built tree,
 *   * `ensure` is idempotent (second call returns the same ScreenGui),
 *   * `ensure` COMPLETES a hand-authored tree instead of replacing it,
 *   * `setVisible` really shows and hides the takeover.
 *
 * Usage:
 *   node tools/qte-build-ui.js            # (re)write the two artifacts
 *   node tools/qte-build-ui.js --check    # fail if the artifacts are out of date
 *   node tools/qte-build-ui.js --stats    # print the part/instance summary only
 */

const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const { transformLuau, luaLongString, read } = require("./lib/luau-transform");

const ROOT = path.resolve(__dirname, "..");
const MODULE_PATH = "qte/UI/QTEOverlay.luau";
const MODEL_PATH = "qte/UI/QTEOverlay.rbxmx";
const PREVIEW_PATH = "qte/UI/QTEOverlay.preview.svg";

// Reference resolution for the preview. The layout itself is anchored and scaled,
// so this is a rendering choice, not a layout constant.
const VIEWPORT = { w: 1280, h: 720 };
const CAPTION_H = 96;
const SCENE = { r: 26, g: 32, b: 34 }; // a stand-in for the world behind the overlay

// Sample strings for the preview only: at runtime the shell writes the real prompt,
// hint and verdict onto these same labels every run.
const SAMPLE_TEXT = {
	Title: "PRESS  E",
	Hint: "three times, before it closes",
	Verdict: "GOOD",
};

const INT_PROPERTIES = new Set([
	"ZIndex",
	"DisplayOrder",
	"BorderSizePixel",
	"MinTextSize",
	"MaxTextSize",
]);

// ---------------------------------------------------------------------------
// The Roblox stub: just enough of the API for the overlay module to run here.
// ---------------------------------------------------------------------------
const STUB = `
local function marker(fields)
	return fields
end

Color3 = {
	fromRGB = function(r, g, b) return marker({ __type = "Color3", r = r / 255, g = g / 255, b = b / 255 }) end,
}
UDim = {
	new = function(s, o) return marker({ __type = "UDim", s = s, o = o }) end,
}
UDim2 = {
	new = function(xs, xo, ys, yo) return marker({ __type = "UDim2", xs = xs, xo = xo, ys = ys, yo = yo }) end,
	fromScale = function(x, y) return marker({ __type = "UDim2", xs = x, xo = 0, ys = y, yo = 0 }) end,
	fromOffset = function(x, y) return marker({ __type = "UDim2", xs = 0, xo = x, ys = 0, yo = y }) end,
}
Vector2 = {
	new = function(x, y) return marker({ __type = "Vector2", x = x, y = y }) end,
}
Vector3 = {
	new = function(x, y, z) return marker({ __type = "Vector3", x = x, y = y, z = z }) end,
}

-- Enum tokens, checked against the Roblox API reference. A name this stub does not
-- know is an error rather than a silent nil, so a typo cannot reach the model file.
local ENUM_TOKENS = {
	Font = {
		Legacy = 0, Arial = 1, ArialBold = 2, SourceSans = 3, SourceSansBold = 4,
		Bodoni = 7, Garamond = 8, Cartoon = 9, Code = 10,
		SourceSansSemibold = 16, Gotham = 17, GothamMedium = 18, GothamBold = 19, GothamBlack = 20,
	},
	ZIndexBehavior = { Global = 0, Sibling = 1 },
	TextXAlignment = { Left = 0, Center = 1, Right = 2 },
	TextYAlignment = { Top = 0, Center = 1, Bottom = 2 },
	AutomaticSize = { None = 0, X = 1, Y = 2, XY = 3 },
}
Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = ENUM_TOKENS[enumName]
		if items == nil then
			error("the UI stub does not know Enum." .. tostring(enumName) .. " - add it to ENUM_TOKENS")
		end
		return setmetatable({}, {
			__index = function(_, itemName)
				local value = items[itemName]
				if value == nil then
					error("the UI stub does not know Enum." .. enumName .. "." .. tostring(itemName))
				end
				return marker({ __type = "EnumItem", enum = enumName, name = itemName, value = value })
			end,
		})
	end,
})

local NodeMethods = {}
local Node = {}
Node.__index = function(self, key)
	local method = NodeMethods[key]
	if method ~= nil then return method end
	local children = rawget(self, "_children")
	for i = 1, #children do
		if children[i]._name == key then return children[i] end
	end
	return rawget(self, "_props")[key]
end
Node.__newindex = function(self, key, value)
	if key == "Name" then
		rawset(self, "_name", value)
		return
	end
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old ~= nil then
			local siblings = rawget(old, "_children")
			for i = #siblings, 1, -1 do
				if siblings[i] == self then table.remove(siblings, i) end
			end
		end
		rawset(self, "_parent", value)
		if value ~= nil then
			local siblings = rawget(value, "_children")
			siblings[#siblings + 1] = self
		end
		return
	end
	rawget(self, "_props")[key] = value
end

NodeMethods.FindFirstChild = function(self, name)
	local children = rawget(self, "_children")
	for i = 1, #children do
		if children[i]._name == name then return children[i] end
	end
	return nil
end
NodeMethods.FindFirstChildOfClass = function(self, class)
	local children = rawget(self, "_children")
	for i = 1, #children do
		if children[i]._class == class then return children[i] end
	end
	return nil
end
NodeMethods.GetChildren = function(self)
	local out = {}
	local children = rawget(self, "_children")
	for i = 1, #children do out[i] = children[i] end
	return out
end
NodeMethods.IsA = function(self, class)
	local own = rawget(self, "_class")
	if own == class then return true end
	if class == "GuiObject" then return own == "Frame" or own == "TextLabel" or own == "TextButton" end
	if class == "Instance" then return true end
	return false
end
NodeMethods.Destroy = function(self)
	self.Parent = nil
end

Instance = {
	new = function(class)
		local self = setmetatable({
			_class = class,
			_name = class,
			_props = {},
			_children = {},
			_parent = nil,
		}, Node)
		return self
	end,
}

local function serialise(node)
	local props = {}
	for key, value in pairs(rawget(node, "_props")) do
		local valueType = type(value)
		if valueType == "number" or valueType == "string" or valueType == "boolean"
			or (valueType == "table" and value.__type ~= nil) then
			props[#props + 1] = { name = key, value = value }
		end
	end
	-- Sorted so the generated XML is byte-stable: --check compares files.
	table.sort(props, function(a, b) return a.name < b.name end)
	local children = {}
	local kids = rawget(node, "_children")
	for i = 1, #kids do
		children[i] = serialise(kids[i])
	end
	return {
		class = rawget(node, "_class"),
		name = rawget(node, "_name"),
		props = props,
		children = children,
	}
end
`;

const DRIVER = `
-- ── Build and exercise the overlay ───────────────────────────────────────────
local host = Instance.new("Folder")
host.Name = "PlayerGui"

local gui = QTEOverlay.build(host, {})
local parts = QTEOverlay.parts(gui)
local missing = {}
for key, path in pairs(QTEOverlay.Parts) do
	if parts[key] == nil then
		missing[#missing + 1] = key .. " (" .. path .. ")"
	end
end
table.sort(missing)

-- ensure() must be idempotent...
local again = QTEOverlay.ensure(host, {})
local idempotent = (again == gui)

-- ...and must COMPLETE a hand-authored tree rather than replace it. Build a bare
-- ScreenGui with one restyled child and check the rest of the spec appears.
local host2 = Instance.new("Folder")
local authored = Instance.new("ScreenGui")
authored.Name = "QTEOverlay"
authored.Parent = host2
local authoredTitle = Instance.new("TextLabel")
authoredTitle.Name = "Title"
authoredTitle.Text = "hand made"
authoredTitle.Parent = authored
local completed = QTEOverlay.ensure(host2, {})
local completedParts = QTEOverlay.parts(completed)
local completedMissing = 0
for _key, node in pairs(completedParts) do
	if node == nil then completedMissing = completedMissing + 1 end
end
local keptAuthoredText = (authoredTitle.Text == "hand made")
local keptAuthoredName = (completed == authored)

-- setVisible drives the takeover and its scrim together.
QTEOverlay.setVisible(gui, true)
local shown = gui.Scrim.Visible == true and gui.QTE.Visible == true
QTEOverlay.setVisible(gui, false)
local hidden = gui.Scrim.Visible == false and gui.QTE.Visible == false

local function count(node)
	local total = 1
	for i = 1, #node.children do
		total = total + count(node.children[i])
	end
	return total
end

UI_RESULT = {
	model = serialise(gui),
	missing = missing,
	idempotent = idempotent,
	keptAuthoredName = keptAuthoredName,
	keptAuthoredText = keptAuthoredText,
	completedMissing = completedMissing,
	shown = shown,
	hidden = hidden,
	theme = QTEOverlay.Theme,
}
`;

// ---------------------------------------------------------------------------
// Run the module
// ---------------------------------------------------------------------------
function luaToJs(L, index) {
	// The C API only guarantees a small push window; a nested tree walk (which is
	// exactly what this is) exhausts it around ten levels in. Raise it once, so the
	// recursion below is bounded by the data rather than by LUA_MINSTACK.
	if (!lua.lua_checkstack(L, 128)) {
		throw new Error("could not grow the Lua stack for the tree walk");
	}
	const type = lua.lua_type(L, index);
	if (type === lua.LUA_TNIL) return null;
	if (type === lua.LUA_TBOOLEAN) return lua.lua_toboolean(L, index);
	if (type === lua.LUA_TNUMBER) return lua.lua_tonumber(L, index);
	if (type === lua.LUA_TSTRING) return to_jsstring(lua.lua_tostring(L, index));
	if (type === lua.LUA_TTABLE) {
		const at = lua.lua_absindex(L, index);
		const keys = [];
		const out = {};
		lua.lua_pushnil(L);
		while (lua.lua_next(L, at) !== 0) {
			const key = luaToJs(L, -2);
			const value = luaToJs(L, -1);
			keys.push(key);
			out[String(key)] = value;
			lua.lua_pop(L, 1);
		}
		const numeric = keys.length > 0 && keys.every((k) => Number.isInteger(k) && k >= 1);
		if (numeric) {
			const array = [];
			for (let i = 1; i <= keys.length; i += 1) array.push(out[String(i)]);
			return array;
		}
		return out;
	}
	return null;
}

// An empty Lua table is neither an array nor a map until a reader decides: the
// tree's `children` and `props` are always arrays, so say so once here instead of
// guarding at every use.
function asArray(value) {
	if (Array.isArray(value)) return value;
	if (value && typeof value === "object") {
		return Object.keys(value)
			.map((key) => Number(key))
			.sort((a, b) => a - b)
			.map((index) => value[String(index)]);
	}
	return [];
}

function normaliseNode(node) {
	if (node == null) return node;
	node.props = asArray(node.props);
	node.children = asArray(node.children).map(normaliseNode);
	return node;
}

function build() {
	const source = transformLuau(read(MODULE_PATH), "QTEOverlay");
	const bundle = [
		STUB,
		`QTEOverlay = (function()\n${source}\nend)()`,
		DRIVER,
	].join("\n");

	const L = lauxlib.luaL_newstate();
	lualib.luaL_openlibs(L);
	const status = lauxlib.luaL_dostring(L, to_luastring(bundle));
	if (status !== lua.LUA_OK) {
		const err = to_jsstring(lua.lua_tostring(L, -1) || to_luastring("<no error object>"));
		throw new Error(`the overlay module failed to run:\n${err}`);
	}
	lua.lua_getglobal(L, to_luastring("UI_RESULT"));
	if (lua.lua_type(L, -1) !== lua.LUA_TTABLE) {
		throw new Error("the overlay module did not produce UI_RESULT");
	}
	const result = luaToJs(L, -1);
	lua.lua_pop(L, 1);
	result.model = normaliseNode(result.model);
	result.missing = asArray(result.missing);
	return result;
}

// ---------------------------------------------------------------------------
// Model (.rbxmx)
// ---------------------------------------------------------------------------
function esc(text) {
	return String(text)
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;");
}

function num(value) {
	if (Number.isInteger(value)) return String(value);
	return String(Number(value.toFixed(6)));
}

function propertyXml(name, value) {
	// Indentation: one tab for the property, two for its components. The caller
	// shifts the whole block to the item's depth.
	if (typeof value === "boolean") {
		return `\t<bool name="${name}">${value ? "true" : "false"}</bool>`;
	}
	if (typeof value === "number") {
		if (INT_PROPERTIES.has(name)) return `\t<int name="${name}">${Math.round(value)}</int>`;
		return `\t<float name="${name}">${num(value)}</float>`;
	}
	if (typeof value === "string") {
		return `\t<string name="${name}">${esc(value)}</string>`;
	}
	if (value && value.__type === "Color3") {
		return [
			`\t<Color3 name="${name}">`,
			`\t\t<R>${num(value.r)}</R>`,
			`\t\t<G>${num(value.g)}</G>`,
			`\t\t<B>${num(value.b)}</B>`,
			"\t</Color3>",
		].join("\n");
	}
	if (value && value.__type === "UDim2") {
		return [
			`\t<UDim2 name="${name}">`,
			`\t\t<XS>${num(value.xs)}</XS>`,
			`\t\t<XO>${num(value.xo)}</XO>`,
			`\t\t<YS>${num(value.ys)}</YS>`,
			`\t\t<YO>${num(value.yo)}</YO>`,
			"\t</UDim2>",
		].join("\n");
	}
	if (value && value.__type === "UDim") {
		return `\t<UDim name="${name}">\n\t\t<S>${num(value.s)}</S>\n\t\t<O>${num(value.o)}</O>\n\t</UDim>`;
	}
	if (value && value.__type === "Vector2") {
		return `\t<Vector2 name="${name}">\n\t\t<X>${num(value.x)}</X>\n\t\t<Y>${num(value.y)}</Y>\n\t</Vector2>`;
	}
	if (value && value.__type === "Vector3") {
		return `\t<Vector3 name="${name}">\n\t\t<X>${num(value.x)}</X>\n\t\t<Y>${num(value.y)}</Y>\n\t\t<Z>${num(value.z)}</Z>\n\t</Vector3>`;
	}
	if (value && value.__type === "EnumItem") {
		return `\t<token name="${name}">${value.value}</token>`;
	}
	throw new Error(`cannot serialise property ${name} (${JSON.stringify(value)})`);
}

let referentCounter = 0;
function itemXml(node, depth) {
	const pad = "\t".repeat(depth + 1);
	const referent = `RBX${referentCounter}`;
	referentCounter += 1;
	const lines = [];
	lines.push(`${pad}<Item class="${node.class}" referent="${referent}">`);
	lines.push(`${pad}\t<Properties>`);
	lines.push(`${pad}\t\t<string name="Name">${esc(node.name)}</string>`);
	for (const prop of node.props) {
		if (prop.name === "Name") continue;
		const xml = propertyXml(prop.name, prop.value);
		lines.push(xml.split("\n").map((line) => `${pad}\t${line}`).join("\n"));
	}
	lines.push(`${pad}\t</Properties>`);
	for (const child of node.children) {
		lines.push(itemXml(child, depth + 1));
	}
	lines.push(`${pad}</Item>`);
	return lines.join("\n");
}

function modelXml(result) {
	referentCounter = 0;
	return [
		'<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
		"\t<!-- Generated by tools/qte-build-ui.js from qte/UI/QTEOverlay.luau.",
		"\t     Drag into StarterGui > QTEOverlay. Editing it in Studio is supported:",
		"\t     QTEOverlay.ensure completes a tree like this one, it never replaces it. -->",
		itemXml(result.model, 0),
		"</roblox>",
		"",
	].join("\n");
}

// ---------------------------------------------------------------------------
// Preview (.svg): the same geometry, resolved against the reference resolution.
// ---------------------------------------------------------------------------
function propsOf(node) {
	const out = {};
	for (const prop of node.props) out[prop.name] = prop.value;
	return out;
}

const DEFAULTS = {
	Position: { __type: "UDim2", xs: 0, xo: 0, ys: 0, yo: 0 },
	Size: { __type: "UDim2", xs: 0, xo: 0, ys: 0, yo: 0 },
	AnchorPoint: { __type: "Vector2", x: 0, y: 0 },
};

function rectOf(node, parent) {
	const props = propsOf(node);
	const position = props.Position || DEFAULTS.Position;
	const size = props.Size || DEFAULTS.Size;
	const anchor = props.AnchorPoint || DEFAULTS.AnchorPoint;
	const w = size.xs * parent.w + size.xo;
	const h = size.ys * parent.h + size.yo;
	return {
		x: parent.x + position.xs * parent.w + position.xo - anchor.x * w,
		y: parent.y + position.ys * parent.h + position.yo - anchor.y * h,
		w,
		h,
	};
}

function cssColor(colour, transparency) {
	if (!colour) return null;
	const alpha = Math.max(0, Math.min(1, 1 - (transparency || 0)));
	const r = Math.round(colour.r * 255);
	const g = Math.round(colour.g * 255);
	const b = Math.round(colour.b * 255);
	if (alpha >= 1) return `rgb(${r},${g},${b})`;
	return `rgba(${r},${g},${b},${alpha.toFixed(3)})`;
}

function previewSvg(result) {
	const root = result.model;
	const scale = { x: 0, y: 0, w: VIEWPORT.w, h: VIEWPORT.h };
	const build = [];
	const texts = [];

	function walk(node, parentRect) {
		// A ScreenGui fills the screen: it has no Position/Size of its own, so
		// resolving it from those properties would give every child a 0x0 parent.
		const rect = node.class === "ScreenGui" ? parentRect : rectOf(node, parentRect);
		const props = propsOf(node);
		const isLabel = node.class === "TextLabel";
		const fill = isLabel ? null : cssColor(props.BackgroundColor3, props.BackgroundTransparency);
		if (fill) {
			build.push(
				`<rect x="${rect.x.toFixed(1)}" y="${rect.y.toFixed(1)}" width="${Math.max(0, rect.w).toFixed(1)}" height="${Math.max(0, rect.h).toFixed(1)}" fill="${fill}" />`
			);
		}
		const sample = SAMPLE_TEXT[node.name];
		if (isLabel && sample) {
			const colour = cssColor(props.TextColor3, props.TextTransparency) || "#ffffff";
			const size = Math.max(11, Math.min(rect.h, 30));
			texts.push(
				`<text x="${(rect.x + rect.w / 2).toFixed(1)}" y="${(rect.y + rect.h / 2).toFixed(1)}" fill="${colour}" font-family="Gotham, Montserrat, Arial, Helvetica, sans-serif" font-size="${size.toFixed(1)}" font-weight="700" letter-spacing="${(size * 0.06).toFixed(2)}" text-anchor="middle" dominant-baseline="middle">${esc(sample)}</text>`
			);
		}
		for (const child of node.children) walk(child, rect);
	}

	walk(root, { x: scale.x, y: scale.y, w: scale.w, h: scale.h });

	const captionY = VIEWPORT.h + 26;
	const lines = [
		"QTE overlay at 1280 x 720 - generated from qte/UI/QTEOverlay.luau by tools/qte-build-ui.js",
		"Dark scrim, paper-white instruction, a faint accent rule that carries the QTE family colour, a thin timer RULE (never a graph),",
		"and one verdict word. Every label is TextScaled inside a UITextSizeConstraint (12-34 px), so it stays legible at 480p.",
		'Strings shown here are samples; the shell writes the real prompt, hint and verdict. The dashed area is the widget stage.',
	];
	const caption = lines
		.map((line, index) => `<text x="24" y="${captionY + index * 18}" fill="#9aa3a6" font-family="Montserrat, Arial, Helvetica, sans-serif" font-size="13">${esc(line)}</text>`)
		.join("\n");

	// The widget stage gets an annotation instead of invented widgets: what widgets
	// appear is decided per QTE by the engine, and faking them here would lie.
	const qte = root.children.find((child) => child.name === "QTE");
	const stage = qte ? qte.children.find((child) => child.name === "Stage") : null;
	const qteRect = qte ? rectOf(qte, { x: scale.x, y: scale.y, w: scale.w, h: scale.h }) : null;
	const stageRect = stage && qteRect ? rectOf(stage, qteRect) : null;
	const stageNote = stageRect
		? [
			`<rect x="${stageRect.x.toFixed(1)}" y="${stageRect.y.toFixed(1)}" width="${stageRect.w.toFixed(1)}" height="${stageRect.h.toFixed(1)}" fill="none" stroke="#6f7a7d" stroke-dasharray="6 6" stroke-width="1" />`,
			`<text x="${(stageRect.x + stageRect.w / 2).toFixed(1)}" y="${(stageRect.y + stageRect.h / 2).toFixed(1)}" fill="#6f7a7d" font-family="Montserrat, Arial, Helvetica, sans-serif" font-size="13" text-anchor="middle" dominant-baseline="middle">widget stage - bars, targets, grids and chips are pooled here per QTE</text>`,
		].join("\n")
		: "";

	return [
		`<svg xmlns="http://www.w3.org/2000/svg" width="${VIEWPORT.w}" height="${VIEWPORT.h + CAPTION_H}" viewBox="0 0 ${VIEWPORT.w} ${VIEWPORT.h + CAPTION_H}" role="img" aria-label="QTE overlay layout preview">`,
		`<rect width="${VIEWPORT.w}" height="${VIEWPORT.h + CAPTION_H}" fill="#14181a" />`,
		`<rect x="0" y="0" width="${VIEWPORT.w}" height="${VIEWPORT.h}" fill="rgb(${SCENE.r},${SCENE.g},${SCENE.b})" />`,
		build.join("\n"),
		stageNote,
		texts.join("\n"),
		`<rect x="0" y="${VIEWPORT.h}" width="${VIEWPORT.w}" height="${CAPTION_H}" fill="#0d1012" />`,
		caption,
		"</svg>",
		"",
	].join("\n");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function main() {
	const argv = process.argv.slice(2);
	const check = argv.includes("--check");
	const statsOnly = argv.includes("--stats");

	const result = build();

	const failures = [];
	if (result.missing.length > 0) failures.push(`parts missing from the built tree: ${result.missing.join(", ")}`);
	if (!result.idempotent) failures.push("QTEOverlay.ensure built a second overlay instead of reusing the first");
	if (!result.keptAuthoredName) failures.push("QTEOverlay.ensure replaced a hand-authored ScreenGui instead of completing it");
	if (!result.keptAuthoredText) failures.push("QTEOverlay.ensure overwrote a hand-authored property");
	if (result.completedMissing > 0) failures.push(`QTEOverlay.ensure left ${result.completedMissing} part(s) unbuilt in a hand-authored tree`);
	if (!result.shown || !result.hidden) failures.push("QTEOverlay.setVisible did not show/hide the takeover and its scrim");

	const instances = (function count(node) {
		return 1 + node.children.reduce((total, child) => total + count(child), 0);
	})(result.model);

	if (failures.length) {
		for (const failure of failures) console.error(`qte-build-ui: ${failure}`);
		process.exit(1);
	}

	const model = modelXml(result);
	const preview = previewSvg(result);

	if (statsOnly) {
		console.log(`qte-build-ui: ${instances} instances, parts ok, ensure idempotent, setVisible ok`);
		return;
	}

	if (check) {
		const problems = [];
		for (const [rel, generated] of [[MODEL_PATH, model], [PREVIEW_PATH, preview]]) {
			const absolute = path.join(ROOT, rel);
			if (!fs.existsSync(absolute)) problems.push(`${rel} is missing`);
			else if (fs.readFileSync(absolute, "utf8") !== generated) problems.push(`${rel} is out of date`);
		}
		const absoluteModel = path.join(ROOT, MODEL_PATH);
		if (fs.existsSync(absoluteModel)) {
			const onDisk = fs.readFileSync(absoluteModel, "utf8");
			const opens = (onDisk.match(/<Item class=/g) || []).length;
			if (opens !== instances) problems.push(`${MODEL_PATH} has ${opens} items, the module builds ${instances}`);
			if (!onDisk.trimEnd().endsWith("</roblox>")) problems.push(`${MODEL_PATH} is not a complete model file`);
		}
		if (problems.length) {
			for (const problem of problems) console.error(`qte-build-ui: ${problem}`);
			console.error("qte-build-ui: run `node tools/qte-build-ui.js` to regenerate");
			process.exit(1);
		}
		console.log(`qte-build-ui: model and preview are up to date (${instances} instances, ${result.missing.length} missing parts)`);
		return;
	}

	fs.writeFileSync(path.join(ROOT, MODEL_PATH), model);
	fs.writeFileSync(path.join(ROOT, PREVIEW_PATH), preview);
	console.log(`qte-build-ui: wrote ${MODEL_PATH} (${model.length} bytes) and ${PREVIEW_PATH} (${preview.length} bytes)`);
	console.log(`qte-build-ui: ${instances} instances; every part the shell looks up exists; ensure() is idempotent and completing`);
}

main();
