-- READ ONLY/Edit Vitriol: selected serializable, authored Instance properties.
-- Intended for tools/backup-studio-edit-properties.py, which substitutes the
-- service name from a fixed allowlist. NOT a full place file or restoration.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local serviceName="__ROOT_SERVICE__"
local service=game:GetService(serviceName)
assert(service and service.Name==serviceName,"service missing/mismatched")
local tags=game:GetService("CollectionService")
local function value(v)
 local t=typeof(v)
 if t=="nil" or t=="boolean" or t=="number" or t=="string" then return v end
 if t=="Vector3" then return {type=t,components={v.X,v.Y,v.Z}} end
 if t=="Vector2" then return {type=t,components={v.X,v.Y}} end
 if t=="Color3" then return {type=t,components={v.R,v.G,v.B}} end
 if t=="CFrame" then return {type=t,components={v:GetComponents()}} end
 if t=="UDim" then return {type=t,components={v.Scale,v.Offset}} end
 if t=="UDim2" then return {type=t,components={v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset}} end
 if t=="NumberRange" then return {type=t,components={v.Min,v.Max}} end
 if t=="Instance" then return {type=t,path=v:GetFullName(),className=v.ClassName} end
 return {type=t,text=tostring(v)} -- unsupported types are NOT restorable
end
local common={"Archivable"}
local base={"CFrame","Size","Anchored","CanCollide","CanTouch","CanQuery",
 "Transparency","Color","Material","Reflectance","CollisionGroup","CastShadow"}
local classes={
 Model={"PrimaryPart","WorldPivot"},
 Part={"Shape"},
 MeshPart={"MeshId","TextureID","CollisionFidelity","RenderFidelity","DoubleSided"},
 UnionOperation={"UsePartColor"},
 SpecialMesh={"MeshId","TextureId","MeshType","Scale","Offset"},
 SpawnLocation={"Enabled","Neutral","TeamColor"},
 Tool={"Grip","RequiresHandle","CanBeDropped","TextureId","ToolTip"},
 Attachment={"CFrame","Position","Visible"},
 ProximityPrompt={"ActionText","ObjectText","HoldDuration","MaxActivationDistance",
   "RequiresLineOfSight","Enabled","ClickablePrompt","Exclusivity","KeyboardKeyCode","GamepadKeyCode"},
 PointLight={"Color","Brightness","Range","Shadows","Enabled"},
 SpotLight={"Color","Brightness","Range","Shadows","Enabled","Angle","Face"},
 SurfaceLight={"Color","Brightness","Range","Shadows","Enabled","Angle","Face"},
 Sound={"SoundId","Volume","PlaybackSpeed","Looped","RollOffMinDistance",
   "RollOffMaxDistance","RollOffMode","SoundGroup"},
 Animation={"AnimationId"},
 ParticleEmitter={"Texture","Color","Transparency","Size","Rate","Lifetime","Speed","Enabled"},
 Trail={"Texture","Color","Transparency","Lifetime","Enabled","Attachment0","Attachment1"},
 SurfaceAppearance={"ColorMap","MetalnessMap","NormalMap","RoughnessMap","AlphaMode"},
 Texture={"Texture","Color3","Transparency","StudsPerTileU","StudsPerTileV","Face"},
 ScreenGui={"Enabled","IgnoreGuiInset","ResetOnSpawn","ZIndexBehavior","DisplayOrder"},
 SurfaceGui={"Enabled","Adornee","CanvasSize","Face","AlwaysOnTop","LightInfluence"},
 ImageLabel={"Image","ImageColor3","ImageTransparency","ScaleType"},
 TextLabel={"Text","TextColor3","TextSize","TextScaled","Font"},
 UIGradient={"Color","Transparency","Rotation","Enabled"},
 UICorner={"CornerRadius"},
 UIPadding={"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"},
 WeldConstraint={"Part0","Part1","Enabled"},
 Motor6D={"Part0","Part1","C0","C1","Enabled"},
 Sky={"SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp",
   "SunTextureId","MoonTextureId"},
 Atmosphere={"Density","Offset","Color","Decay","Glare","Haze"},
 BloomEffect={"Enabled","Intensity","Size","Threshold"},
 DepthOfFieldEffect={"Enabled","FarIntensity","FocusDistance","InFocusRadius","NearIntensity"},
 SunRaysEffect={"Enabled","Intensity","Spread"},
 Lighting={"Ambient","OutdoorAmbient","Brightness","ClockTime","ExposureCompensation",
   "FogStart","FogEnd","FogColor","GeographicLatitude","GlobalShadows"},
 Terrain={"WaterColor","WaterTransparency","WaterReflectance","WaterWaveSize","WaterWaveSpeed"},
 ValueBase={"Value"},
}
local gui={"Position","Size","AnchorPoint","Visible","BackgroundColor3",
 "BackgroundTransparency","Rotation","ZIndex","LayoutOrder"}
local seen={}
local entries={}
local function collect(inst)
 local row={index=#entries+1,name=inst.Name,className=inst.ClassName,
  fullName=inst:GetFullName(),parentIndex=seen[inst.Parent],
  tags=tags:GetTags(inst),attributes={},properties={}}
 for k,v in pairs(inst:GetAttributes()) do row.attributes[k]=value(v) end
 local function props(list)
  for _,key in ipairs(list) do
   local ok,v=pcall(function() return inst[key] end)
   if ok and v~=nil then row.properties[key]=value(v) end
  end
 end
 props(common)
 if inst:IsA("BasePart") then props(base) end
 if inst:IsA("GuiObject") then props(gui) end
 if inst:IsA("ValueBase") then props(classes.ValueBase) end
 props(classes[inst.ClassName] or {})
 entries[#entries+1]=row
 seen[inst]=row.index
end
collect(service)
for _,inst in ipairs(service:GetDescendants()) do collect(inst) end
return game:GetService("HttpService"):JSONEncode({ok=true,mode="Edit",placeId=game.PlaceId,
 root=serviceName,count=#entries,entries=entries,
 scope="selected readable properties; NOT a complete place/asset/voxel backup",
 sourceIncluded=false,studioWritten=false,playCaptured=false})
