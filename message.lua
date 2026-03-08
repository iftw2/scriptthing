--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!
]]
--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║              DARKWIRED - MINERS WORLD PREDICTOR              ║
    ║         Particle ESP + Pattern Analysis + Prediction         ║
    ║                  + Seed Hunter + Mesh Detection              ║
    ║                       + Full UI + Persistence                ║
    ║                      + Tracer System (Debug)                 ║
    ╚══════════════════════════════════════════════════════════════╝
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")

-------------------------------------------------
-- CONFIGURATION
-------------------------------------------------
local GRID_SIZE = 4
local PREDICTION_RADIUS = 50
local UPDATE_INTERVAL = 0.5
local MIN_SAMPLES_FOR_PREDICTION = 5
local ENABLE_SEED_HUNT = true
local ENABLE_MESH_DETECTION = true
local ENABLE_PREDICTION = true
local ENABLE_FOCUS_MODE = true
local ENABLE_PATTERN = true
local ENABLE_ADVANCED = true
local ENABLE_TRACERS = true               -- master tracer toggle

-- Check if Drawing is supported
local DRAWING_SUPPORTED = pcall(Drawing.new, "Line")
if not DRAWING_SUPPORTED then
    warn("[Darkwired] Drawing library not supported – tracers will not appear.")
end

-------------------------------------------------
-- RARITY DATA
-------------------------------------------------
local rarities = {
    {name="Zenith",    color=Color3.fromRGB(120,0,120)},
    {name="Divine",    color=Color3.fromRGB(255,255,255)},
    {name="Celestial", color=Color3.fromRGB(0,255,255)},
    {name="Ethereal",  color=Color3.fromRGB(255,20,147)},
    {name="Mythic",    color=Color3.fromRGB(255,0,0)},
    {name="Legendary", color=Color3.fromRGB(255,200,0)},
    {name="Epic",      color=Color3.fromRGB(170,0,255)},
    {name="Rare",      color=Color3.fromRGB(0,120,255)},
    {name="Uncommon",  color=Color3.fromRGB(0,255,0)}
}
local rarityByName = {}
for _, r in ipairs(rarities) do rarityByName[r.name] = r end

-- Enabled rarities (ESP)
local espEnabled = {}
for _, r in ipairs(rarities) do espEnabled[r.name] = true end

-- Tracer enabled per rarity
local tracerEnabled = {}
for _, r in ipairs(rarities) do tracerEnabled[r.name] = false end

-- MeshId mapping
local targets = {
    ["rbxassetid://103949883753847"] = "TNT UN",
    ["rbxassetid://14365388307"]     = "Dynamite",
    ["rbxassetid://88911303348714"]  = "TNT CO",
    ["rbxassetid://12796568017"]     = "Emerald",
    ["rbxassetid://132422790581482"] = "Drill TNT",
    ["rbxassetid://130746239003755"] = "TNT RA",
    ["rbxassetid://136756472360049"] = "???",
    ["rbxassetid://97885003736109"]  = "TNT EP"
}
local targetNames = {}
for id, name in pairs(targets) do targetNames[id] = name end

-------------------------------------------------
-- DATA STORAGE
-------------------------------------------------
local scannedBlocks = {}               -- grid position -> block data
local scannedParts = {}                 -- set to avoid reprocessing
local rarityCounts = {}
for _, r in ipairs(rarities) do rarityCounts[r.name] = 0 end

local depthHist = {}                    -- per rarity: Y index -> count
for _, r in ipairs(rarities) do depthHist[r.name] = {} end

local positionsByRarity = {}            -- per rarity: list of grid positions
for _, r in ipairs(rarities) do positionsByRarity[r.name] = {} end

local spatialHash = {}                  -- key string -> block data
local predictionMarkers = {}             -- key -> part

-- For easy removal when disabling rarities
local espByRarity = {}                   -- rarity name -> list of {highlight, billboard}
for _, r in ipairs(rarities) do espByRarity[r.name] = {} end

-- For tracers
local tracerLines = {}                   -- key -> Drawing line object
local tracerUpdateConn = nil

-------------------------------------------------
-- UTILITY FUNCTIONS
-------------------------------------------------
local function roundToGrid(pos)
    local x = math.floor((pos.X + GRID_SIZE/2) / GRID_SIZE) * GRID_SIZE
    local y = math.floor((pos.Y + GRID_SIZE/2) / GRID_SIZE) * GRID_SIZE
    local z = math.floor((pos.Z + GRID_SIZE/2) / GRID_SIZE) * GRID_SIZE
    return Vector3.new(x, y, z)
end

local function posKey(pos)
    return string.format("%.0f,%.0f,%.0f", pos.X, pos.Y, pos.Z)
end

local function colorDistance(c1, c2)
    return (c1.R-c2.R)^2 + (c1.G-c2.G)^2 + (c1.B-c2.B)^2
end

local function avgColorFromEmitter(emitter)
    local seq = emitter.Color
    local r, g, b, count = 0, 0, 0, 0
    for _, kp in ipairs(seq.Keypoints) do
        r = r + kp.Value.R
        g = g + kp.Value.G
        b = b + kp.Value.B
        count = count + 1
    end
    if count == 0 then return nil end
    return Color3.new(r/count, g/count, b/count)
end

local function closestRarity(avgColor)
    if not avgColor then return nil end
    local bestRarity, bestDist = nil, math.huge
    for _, r in ipairs(rarities) do
        local d = colorDistance(avgColor, r.color)
        if d < bestDist then
            bestDist = d
            bestRarity = r
        end
    end
    return bestDist < 3 and bestRarity or nil
end

local function findPart(obj)
    while obj do
        if obj:IsA("BasePart") then return obj end
        obj = obj.Parent
    end
    return nil
end

local function identifyRarity(part)
    -- Particles first
    local emitter = part:FindFirstChildOfClass("ParticleEmitter")
    if emitter and emitter.Color then
        local avg = avgColorFromEmitter(emitter)
        local rarity = closestRarity(avg)
        if rarity then return rarity end
    end

    -- MeshId fallback
    if ENABLE_MESH_DETECTION and part:IsA("MeshPart") and part.MeshId ~= "" then
        local name = targetNames[part.MeshId]
        if name then
            -- Could map to rarity if known
        end
    end
    return nil
end

-------------------------------------------------
-- BLOCK PROCESSING (with ESP storage)
-------------------------------------------------
local function processBlock(part)
    if scannedParts[part] then return end
    scannedParts[part] = true

    local rarity = identifyRarity(part)
    if not rarity then return end
    print("[DEBUG] Block processed:", part.Name, rarity.name) -- Debug

    local gridPos = roundToGrid(part.Position)
    local key = posKey(gridPos)
    if spatialHash[key] then return end

    local blockData = {
        part = part,
        rarity = rarity.name,
        pos = gridPos,
        color = rarity.color,
        mesh = part:IsA("MeshPart") and part.MeshId or nil
    }
    scannedBlocks[gridPos] = blockData
    spatialHash[key] = blockData
    rarityCounts[rarity.name] = rarityCounts[rarity.name] + 1

    local yIndex = math.floor(gridPos.Y / GRID_SIZE)
    depthHist[rarity.name][yIndex] = (depthHist[rarity.name][yIndex] or 0) + 1
    table.insert(positionsByRarity[rarity.name], gridPos)

    -- Create ESP only if rarity is enabled
    if espEnabled[rarity.name] then
        local highlight = Instance.new("Highlight")
        highlight.Parent = part
        highlight.FillColor = rarity.color
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        local billboard = Instance.new("BillboardGui")
        billboard.Parent = part
        billboard.Size = UDim2.new(0, 120, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        local label = Instance.new("TextLabel", billboard)
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Text = rarity.name:upper()
        label.Font = Enum.Font.GothamBlack
        label.TextScaled = true
        label.TextColor3 = rarity.color
        label.TextStrokeTransparency = 0

        blockData.highlight = highlight
        blockData.billboard = billboard
        table.insert(espByRarity[rarity.name], {highlight = highlight, billboard = billboard})
    end
end

-------------------------------------------------
-- EVENT HANDLERS
-------------------------------------------------
workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA("ParticleEmitter") then
        local part = findPart(inst)
        if part then processBlock(part) end
    elseif ENABLE_MESH_DETECTION and inst:IsA("MeshPart") and inst.MeshId ~= "" then
        processBlock(inst)
    end
end)

for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("ParticleEmitter") then
        local part = findPart(inst)
        if part then processBlock(part) end
    elseif ENABLE_MESH_DETECTION and inst:IsA("MeshPart") and inst.MeshId ~= "" then
        processBlock(inst)
    end
end

-------------------------------------------------
-- ENHANCED PATTERN ANALYSIS & PREDICTION
-------------------------------------------------
local function updatePredictions()
    if not ENABLE_PREDICTION then return end

    local playerChar = player.Character
    local hrp = playerChar and playerChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerGrid = roundToGrid(hrp.Position)

    local probMap = {}  -- key -> table rarityName -> score

    local function addProbability(gridPos, rarityName, score)
        local key = posKey(gridPos)
        probMap[key] = probMap[key] or {}
        probMap[key][rarityName] = (probMap[key][rarityName] or 0) + score
    end

    -- 1. Inverse distance weighting from observed blocks
    for rarityName, positions in pairs(positionsByRarity) do
        if espEnabled[rarityName] and #positions >= MIN_SAMPLES_FOR_PREDICTION then
            for _, obsPos in ipairs(positions) do
                local dx = obsPos.X - playerGrid.X
                local dy = obsPos.Y - playerGrid.Y
                local dz = obsPos.Z - playerGrid.Z
                if math.abs(dx) <= PREDICTION_RADIUS * GRID_SIZE and
                   math.abs(dy) <= PREDICTION_RADIUS * GRID_SIZE and
                   math.abs(dz) <= PREDICTION_RADIUS * GRID_SIZE then
                    local range = 2
                    for x = -range, range do
                        for y = -range, range do
                            for z = -range, range do
                                local candidate = obsPos + Vector3.new(x*GRID_SIZE, y*GRID_SIZE, z*GRID_SIZE)
                                local cKey = posKey(candidate)
                                if not spatialHash[cKey] then
                                    local distSq = x*x + y*y + z*z
                                    if distSq > 0 then
                                        local weight = 1 / (distSq + 0.5)
                                        addProbability(candidate, rarityName, weight)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Depth likelihood boost
    for rarityName, hist in pairs(depthHist) do
        if espEnabled[rarityName] then
            local total = 0
            for _, cnt in pairs(hist) do total = total + cnt end
            if total > MIN_SAMPLES_FOR_PREDICTION then
                for key, scores in pairs(probMap) do
                    local pos = Vector3.new(
                        tonumber(key:match("([^,]+),([^,]+),([^,]+)"))
                    )
                    local yIndex = math.floor(pos.Y / GRID_SIZE)
                    local depthProb = (hist[yIndex] or 0) / total
                    if depthProb > 0 then
                        for rname, sc in pairs(scores) do
                            scores[rname] = sc * (1 + depthProb)
                        end
                    end
                end
            end
        end
    end

    -- 3. Advanced pattern detection (if enabled)
    if ENABLE_ADVANCED then
        -- Helper to get positions of a rarity within a bounding box
        local function getPositionsInBox(rarityName, center, halfSize)
            local minX = center.X - halfSize*GRID_SIZE
            local maxX = center.X + halfSize*GRID_SIZE
            local minY = center.Y - halfSize*GRID_SIZE
            local maxY = center.Y + halfSize*GRID_SIZE
            local minZ = center.Z - halfSize*GRID_SIZE
            local maxZ = center.Z + halfSize*GRID_SIZE
            local result = {}
            for _, pos in ipairs(positionsByRarity[rarityName]) do
                if pos.X >= minX and pos.X <= maxX and
                   pos.Y >= minY and pos.Y <= maxY and
                   pos.Z >= minZ and pos.Z <= maxZ then
                    table.insert(result, pos)
                end
            end
            return result
        end

        -- 3a. Linear pattern detection
        -- For each rarity, look for at least 3 collinear points with spacing exactly GRID_SIZE
        for rarityName, positions in pairs(positionsByRarity) do
            if espEnabled[rarityName] and #positions >= 3 then
                -- Group by axis-aligned lines
                local function checkAxis(axis, positions)
                    local groups = {}
                    for _, pos in ipairs(positions) do
                        local key
                        if axis == "X" then
                            key = string.format("%.0f,%.0f", pos.Y, pos.Z)
                        elseif axis == "Y" then
                            key = string.format("%.0f,%.0f", pos.X, pos.Z)
                        else -- Z
                            key = string.format("%.0f,%.0f", pos.X, pos.Y)
                        end
                        groups[key] = groups[key] or {}
                        table.insert(groups[key], pos)
                    end
                    for _, linePositions in pairs(groups) do
                        if #linePositions >= 3 then
                            table.sort(linePositions, function(a,b)
                                if axis == "X" then return a.X < b.X
                                elseif axis == "Y" then return a.Y < b.Y
                                else return a.Z < b.Z end
                            end)
                            for i = 1, #linePositions-1 do
                                local a = linePositions[i]
                                local b = linePositions[i+1]
                                local diff
                                if axis == "X" then diff = (b.X - a.X) / GRID_SIZE
                                elseif axis == "Y" then diff = (b.Y - a.Y) / GRID_SIZE
                                else diff = (b.Z - a.Z) / GRID_SIZE end
                                if diff == 2 then
                                    local mid
                                    if axis == "X" then
                                        mid = Vector3.new(a.X + GRID_SIZE, a.Y, a.Z)
                                    elseif axis == "Y" then
                                        mid = Vector3.new(a.X, a.Y + GRID_SIZE, a.Z)
                                    else
                                        mid = Vector3.new(a.X, a.Y, a.Z + GRID_SIZE)
                                    end
                                    if not spatialHash[posKey(mid)] then
                                        addProbability(mid, rarityName, 5.0)
                                    end
                                end
                            end
                            if #linePositions >= 2 then
                                local first = linePositions[1]
                                local second = linePositions[2]
                                local dir
                                if axis == "X" then
                                    if second.X - first.X == GRID_SIZE then
                                        dir = Vector3.new(GRID_SIZE, 0, 0)
                                    end
                                elseif axis == "Y" then
                                    if second.Y - first.Y == GRID_SIZE then
                                        dir = Vector3.new(0, GRID_SIZE, 0)
                                    end
                                else
                                    if second.Z - first.Z == GRID_SIZE then
                                        dir = Vector3.new(0, 0, GRID_SIZE)
                                    end
                                end
                                if dir then
                                    local before = first - dir
                                    local after = linePositions[#linePositions] + dir
                                    if not spatialHash[posKey(before)] then
                                        addProbability(before, rarityName, 4.0)
                                    end
                                    if not spatialHash[posKey(after)] then
                                        addProbability(after, rarityName, 4.0)
                                    end
                                end
                            end
                        end
                    end
                end
                checkAxis("X", positions)
                checkAxis("Y", positions)
                checkAxis("Z", positions)
            end
        end

        -- 3b. Cluster filling (3x3x3 neighborhood)
        for key, scores in pairs(probMap) do
            local pos = Vector3.new(
                tonumber(key:match("([^,]+),([^,]+),([^,]+)"))
            )
            for rarityName, _ in pairs(scores) do
                local count = 0
                for x = -1, 1 do
                    for y = -1, 1 do
                        for z = -1, 1 do
                            if not (x==0 and y==0 and z==0) then
                                local neighborPos = pos + Vector3.new(x*GRID_SIZE, y*GRID_SIZE, z*GRID_SIZE)
                                local neighborKey = posKey(neighborPos)
                                if spatialHash[neighborKey] and spatialHash[neighborKey].rarity == rarityName then
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
                if count >= 3 then
                    scores[rarityName] = scores[rarityName] * (1 + count*0.3)
                end
            end
        end
    end

    -- Create/update markers
    local MARKER_THRESHOLD = 0.1
    for key, scores in pairs(probMap) do
        local bestRarity, bestScore = nil, 0
        for rname, score in pairs(scores) do
            if score > bestScore then
                bestScore = score
                bestRarity = rname
            end
        end
        if bestRarity and bestScore >= MARKER_THRESHOLD then
            if not predictionMarkers[key] then
                local pos = Vector3.new(
                    tonumber(key:match("([^,]+),([^,]+),([^,]+)"))
                )
                local marker = Instance.new("Part")
                marker.Size = Vector3.new(GRID_SIZE-0.2, GRID_SIZE-0.2, GRID_SIZE-0.2)
                marker.Position = pos
                marker.Anchored = true
                marker.CanCollide = false
                marker.Transparency = 0.5
                marker.BrickColor = BrickColor.new(rarityByName[bestRarity].color)
                marker.Material = Enum.Material.Neon
                marker.Parent = workspace
                predictionMarkers[key] = marker
            else
                predictionMarkers[key].BrickColor = BrickColor.new(rarityByName[bestRarity].color)
            end
        else
            if predictionMarkers[key] then
                predictionMarkers[key]:Destroy()
                predictionMarkers[key] = nil
            end
        end
    end

    -- Clean up markers for cells no longer in probMap
    for key, marker in pairs(predictionMarkers) do
        if not probMap[key] then
            marker:Destroy()
            predictionMarkers[key] = nil
        end
    end
end

-------------------------------------------------
-- FOCUS MODE
-------------------------------------------------
local function updateFocusMode()
    if not ENABLE_FOCUS_MODE then return end
    local playerChar = player.Character
    local hrp = playerChar and playerChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    for key, marker in pairs(predictionMarkers) do
        if (marker.Position - hrp.Position).Magnitude > PREDICTION_RADIUS * GRID_SIZE * 1.5 then
            marker:Destroy()
            predictionMarkers[key] = nil
        end
    end
end

-------------------------------------------------
-- SEED HUNTER
-------------------------------------------------
local function huntSeed()
    print("[SEED HUNTER] Starting scan...")
    local gc = getgc(true)
    for _, obj in ipairs(gc) do
        if type(obj) == "table" then
            for k, v in pairs(obj) do
                if type(k) == "string" and (k:lower():find("seed") or k:lower():find("noise") or k:lower():find("generat")) then
                    warn("[SEED] Possible seed in table:", k, v)
                end
            end
        elseif type(obj) == "function" then
            local info = debug.getinfo(obj)
            if info then
                local i = 1
                while true do
                    local name, value = debug.getupvalue(obj, i)
                    if not name then break end
                    if type(name) == "string" and (name:lower():find("seed") or name:lower():find("noise")) then
                        warn("[SEED] Upvalue in function", info.name or "?", name, "=", value)
                    end
                    i = i + 1
                end
            end
        end
    end

    local oldNew = Instance.new
    Instance.new = function(className, parent)
        local inst = oldNew(className, parent)
        if className == "Part" or className == "MeshPart" then
            task.defer(function()
                wait()
                if inst and inst.Parent then
                    processBlock(inst)
                end
            end)
        end
        return inst
    end
    print("[SEED HUNTER] Scan complete. Check output for seeds.")
end

if ENABLE_SEED_HUNT then
    task.defer(huntSeed)
end

-------------------------------------------------
-- PERSISTENCE
-------------------------------------------------
local SAVE_FILE = "miners_world_data.json"
local SAVE_INTERVAL = 100
local blocksSinceSave = 0

local function saveData()
    local data = {
        positionsByRarity = positionsByRarity,
        depthHist = depthHist,
        rarityCounts = rarityCounts,
        timestamp = os.time()
    }
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if success then
        pcall(writefile, SAVE_FILE, encoded)
        print("[Persistence] Data saved.")
    end
end

local function loadData()
    local success, content = pcall(readfile, SAVE_FILE)
    if not success or not content then return end
    local decoded = pcall(HttpService.JSONDecode, HttpService, content)
    if not decoded then return end
    local data = decoded
    if data.positionsByRarity then positionsByRarity = data.positionsByRarity end
    if data.depthHist then depthHist = data.depthHist end
    if data.rarityCounts then rarityCounts = data.rarityCounts end
    print("[Persistence] Data loaded.")
end

-- Hook processBlock to auto-save
local originalProcessBlock = processBlock
processBlock = function(part)
    originalProcessBlock(part)
    blocksSinceSave = blocksSinceSave + 1
    if blocksSinceSave >= SAVE_INTERVAL then
        blocksSinceSave = 0
        saveData()
    end
end

task.spawn(loadData)

getgenv().SaveData = saveData
getgenv().LoadData = loadData

-------------------------------------------------
-- MANUAL BLOCK LABELING
-------------------------------------------------
local labelingMode = false
local labelTarget = nil

getgenv().LabelBlock = function()
    labelingMode = true
    print("[Label] Click a block to label...")
    local conn
    conn = player:GetMouse().Button1Down:Connect(function()
        if not labelingMode then conn:Disconnect() return end
        labelTarget = player:GetMouse().Target
        if labelTarget and labelTarget:IsA("BasePart") then
            print("[Label] Selected:", labelTarget.Name)
            print("[Label] Use LabelAs('RarityName') to assign")
        else
            print("[Label] Not a valid part")
        end
        labelingMode = false
        conn:Disconnect()
    end)
end

getgenv().LabelAs = function(rarityName)
    if not labelTarget then
        warn("[Label] No block selected. Run LabelBlock() first.")
        return
    end
    local rarity = rarityByName[rarityName]
    if not rarity then
        warn("[Label] Unknown rarity:", rarityName)
        return
    end
    local gridPos = roundToGrid(labelTarget.Position)
    local key = posKey(gridPos)
    if spatialHash[key] then
        print("[Label] Block already recorded, updating...")
    end
    -- Force add
    local blockData = {
        part = labelTarget,
        rarity = rarity.name,
        pos = gridPos,
        color = rarity.color,
        mesh = labelTarget:IsA("MeshPart") and labelTarget.MeshId or nil,
        manuallyLabeled = true
    }
    scannedBlocks[gridPos] = blockData
    spatialHash[key] = blockData
    rarityCounts[rarity.name] = (rarityCounts[rarity.name] or 0) + 1
    local yIndex = math.floor(gridPos.Y / GRID_SIZE)
    depthHist[rarity.name][yIndex] = (depthHist[rarity.name][yIndex] or 0) + 1
    table.insert(positionsByRarity[rarity.name], gridPos)

    -- Create ESP
    if espEnabled[rarity.name] then
        local highlight = Instance.new("Highlight")
        highlight.Parent = labelTarget
        highlight.FillColor = rarity.color
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        local billboard = Instance.new("BillboardGui")
        billboard.Parent = labelTarget
        billboard.Size = UDim2.new(0, 120, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        local label = Instance.new("TextLabel", billboard)
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Text = rarity.name:upper() .. " (MANUAL)"
        label.Font = Enum.Font.GothamBlack
        label.TextScaled = true
        label.TextColor3 = rarity.color
        label.TextStrokeTransparency = 0

        blockData.highlight = highlight
        blockData.billboard = billboard
        table.insert(espByRarity[rarity.name], {highlight = highlight, billboard = billboard})
    end

    print("[Label] Block labeled as", rarityName)
    labelTarget = nil
end

-------------------------------------------------
-- TRACER SYSTEM (with debug)
-------------------------------------------------
local function updateTracers()
    if not ENABLE_TRACERS or not DRAWING_SUPPORTED then
        -- Clear all tracers
        for _, line in pairs(tracerLines) do
            line:Remove()
        end
        tracerLines = {}
        return
    end

    local screenCenter = Camera.ViewportSize / 2
    if screenCenter.X == 0 or screenCenter.Y == 0 then
        -- Camera not ready
        return
    end

    local newLines = {}
    local tracerCount = 0

    -- Iterate over all scanned blocks
    for key, data in pairs(scannedBlocks) do
        local rarity = data.rarity
        if tracerEnabled[rarity] and data.part and data.part.Parent then
            tracerCount = tracerCount + 1
            local blockPos = data.part.Position
            -- Create line if not exists
            if not tracerLines[key] then
                local line = Drawing.new("Line")
                line.Thickness = 3
                -- Convert Color3 (0-1) to RGB (0-255)
                line.Color = Color3.new(data.color.R, data.color.G, data.color.B) * 255
                line.Transparency = 1  -- fully opaque
                line.ZIndex = 10       -- high zindex
                line.Visible = false
                tracerLines[key] = line
                print("[Tracer] Created for", key)  -- Debug
            end
            -- Update line positions (screen center to block screen pos)
            local toVec, onScreen = Camera:WorldToViewportPoint(blockPos)
            if onScreen then
                tracerLines[key].From = Vector2.new(screenCenter.X, screenCenter.Y)
                tracerLines[key].To = Vector2.new(toVec.X, toVec.Y)
                tracerLines[key].Visible = true
            else
                tracerLines[key].Visible = false
            end
            newLines[key] = tracerLines[key]
        end
    end

    if tracerCount > 0 then
        print("[Tracer] Drawing", tracerCount, "lines")  -- Debug
    end

    -- Remove lines for blocks no longer valid
    for key, line in pairs(tracerLines) do
        if not newLines[key] then
            line:Remove()
            tracerLines[key] = nil
        end
    end
end

-- Connect tracer update to RenderStepped
tracerUpdateConn = RunService.RenderStepped:Connect(updateTracers)

-------------------------------------------------
-- TEST TRACER FUNCTION (creates a temporary block)
-------------------------------------------------
local function createTestTracer()
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local testPart = Instance.new("Part")
    testPart.Size = Vector3.new(4,4,4)
    testPart.Position = hrp.Position + Vector3.new(0, 10, 20)
    testPart.Anchored = true
    testPart.CanCollide = false
    testPart.BrickColor = BrickColor.new("Bright red")
    testPart.Material = Enum.Material.Neon
    testPart.Parent = workspace

    -- Manually add to scanned blocks with a dummy rarity (e.g., Zenith)
    local dummyRarity = rarities[1] -- Zenith
    local gridPos = roundToGrid(testPart.Position)
    local key = posKey(gridPos)
    if not spatialHash[key] then
        local blockData = {
            part = testPart,
            rarity = dummyRarity.name,
            pos = gridPos,
            color = dummyRarity.color,
            mesh = nil,
            isTest = true
        }
        scannedBlocks[gridPos] = blockData
        spatialHash[key] = blockData
        -- Enable tracer for this rarity
        tracerEnabled[dummyRarity.name] = true
        print("[Test] Added test block at", gridPos)
    end

    -- Remove after 10 seconds
    task.delay(10, function()
        if testPart and testPart.Parent then
            testPart:Destroy()
            -- Remove from scanned data
            local key = posKey(gridPos)
            scannedBlocks[gridPos] = nil
            spatialHash[key] = nil
            print("[Test] Test block removed")
        end
    end)
end

-------------------------------------------------
-- MAIN LOOP
-------------------------------------------------
task.spawn(function()
    while true do
        task.wait(UPDATE_INTERVAL)
        updatePredictions()
        if ENABLE_FOCUS_MODE then
            updateFocusMode()
        end
    end
end)

-------------------------------------------------
-- UI CREATION (Darkwired) with Tracers
-------------------------------------------------
local function InitScannerUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "DarkwiredPredictor"
    gui.Parent = guiParent
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- Main frame (draggable)
    local mainFrame = Instance.new("Frame", gui)
    mainFrame.Size = UDim2.new(0, 550, 0, 680)
    mainFrame.Position = UDim2.new(0.03, 0, 0.2, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
    mainFrame.Active = true
    mainFrame.Draggable = true
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 16)

    -- Close button (X)
    local closeBtn = Instance.new("TextButton", mainFrame)
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    -- Title
    local title = Instance.new("TextLabel", mainFrame)
    title.Size = UDim2.new(1, -40, 0, 40)
    title.Position = UDim2.new(0, 10, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "DARKWIRED PREDICTOR"
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 22
    title.TextColor3 = Color3.new(1,1,1)
    title.TextXAlignment = Enum.TextXAlignment.Left

    -- Stats box
    local stats = Instance.new("TextLabel", mainFrame)
    stats.Name = "Stats"
    stats.Size = UDim2.new(0.9, 0, 0, 120)
    stats.Position = UDim2.new(0.05, 0, 0, 55)
    stats.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    stats.TextColor3 = Color3.new(1,1,1)
    stats.Font = Enum.Font.Gotham
    stats.TextSize = 12
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.TextYAlignment = Enum.TextYAlignment.Top
    stats.Text = "Initializing..."
    Instance.new("UICorner", stats).CornerRadius = UDim.new(0, 10)

    -- Feature toggle buttons
    local featureFrame = Instance.new("Frame", mainFrame)
    featureFrame.Size = UDim2.new(0.9, 0, 0, 220)
    featureFrame.Position = UDim2.new(0.05, 0, 0, 185)
    featureFrame.BackgroundTransparency = 1

    local featureGrid = Instance.new("UIGridLayout", featureFrame)
    featureGrid.CellSize = UDim2.new(0.48, 0, 0.15, 0)
    featureGrid.CellPadding = UDim2.new(0.04, 0, 0.05, 0)

    -- Tooltip label
    local tooltip = Instance.new("TextLabel", mainFrame)
    tooltip.Name = "Tooltip"
    tooltip.Size = UDim2.new(0.9, 0, 0, 30)
    tooltip.Position = UDim2.new(0.05, 0, 0, 415)
    tooltip.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    tooltip.TextColor3 = Color3.fromRGB(200,200,200)
    tooltip.Font = Enum.Font.Gotham
    tooltip.TextSize = 14
    tooltip.Text = "Hover over buttons for info"
    Instance.new("UICorner", tooltip).CornerRadius = UDim.new(0, 8)

    -- Feature definitions with tooltips
    local features = {
        {name = "Prediction", var = "ENABLE_PREDICTION", color = Color3.fromRGB(0,255,100),
         desc = "Show predicted rare blocks (neon markers)"},
        {name = "Mesh Detect", var = "ENABLE_MESH_DETECTION", color = Color3.fromRGB(0,150,255),
         desc = "Identify blocks by their MeshId (for blocks without particles)"},
        {name = "Focus Mode", var = "ENABLE_FOCUS_MODE", color = Color3.fromRGB(255,200,0),
         desc = "Only show predictions near you (reduces lag)"},
        {name = "Seed Hunt", var = "ENABLE_SEED_HUNT", color = Color3.fromRGB(255,100,100),
         desc = "Scan memory for world generation seeds (run once)"},
        {name = "Pattern", var = "ENABLE_PATTERN", color = Color3.fromRGB(200,0,255),
         desc = "Use depth and clustering analysis (always on if prediction on)"},
        {name = "Advanced", var = "ENABLE_ADVANCED", color = Color3.fromRGB(255,128,0),
         desc = "Use linear vein detection and cluster filling (improves accuracy)"},
        {name = "Tracers", var = "ENABLE_TRACERS", color = Color3.fromRGB(255,105,180),
         desc = "Master toggle for tracer lines"},
        {name = "Test Tracer", action = "test", color = Color3.fromRGB(255,255,0),
         desc = "Create a test block to check tracers"},
        {name = "Clear Pred", action = "clear", color = Color3.fromRGB(255,50,50),
         desc = "Remove all prediction markers"}
    }

    for _, f in ipairs(features) do
        local btn = Instance.new("TextButton", featureFrame)
        btn.Text = f.name .. ": ON"
        btn.Font = Enum.Font.GothamBold
        btn.TextScaled = true
        btn.BackgroundColor3 = f.color
        btn.TextColor3 = Color3.new(0,0,0)
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        -- Tooltip on hover
        btn.MouseEnter:Connect(function()
            tooltip.Text = f.desc
        end)
        btn.MouseLeave:Connect(function()
            tooltip.Text = "Hover over buttons for info"
        end)

        if f.action == "clear" then
            btn.MouseButton1Click:Connect(function()
                for _, m in pairs(predictionMarkers) do m:Destroy() end
                predictionMarkers = {}
                btn.Text = "Cleared!"
                task.wait(0.5)
                btn.Text = "Clear Pred"
            end)
        elseif f.action == "test" then
            btn.MouseButton1Click:Connect(function()
                createTestTracer()
                btn.Text = "Created!"
                task.wait(1)
                btn.Text = "Test Tracer"
            end)
        else
            -- Set initial state
            local current = getfenv()[f.var]
            if current == nil then current = true end
            if not current then
                btn.BackgroundColor3 = f.color:lerp(Color3.new(0,0,0), 0.6)
                btn.Text = f.name .. ": OFF"
            end

            btn.MouseButton1Click:Connect(function()
                local cur = getfenv()[f.var]
                if cur == nil then cur = true end
                local new = not cur
                getfenv()[f.var] = new
                _G[f.var] = new
                if new then
                    btn.BackgroundColor3 = f.color
                    btn.Text = f.name .. ": ON"
                else
                    btn.BackgroundColor3 = f.color:lerp(Color3.new(0,0,0), 0.6)
                    btn.Text = f.name .. ": OFF"
                end
                -- Special handling
                if f.var == "ENABLE_PREDICTION" and not new then
                    for _, m in pairs(predictionMarkers) do m:Destroy() end
                    predictionMarkers = {}
                end
            end)
        end
    end

    -- Rarity buttons + tracer toggles
    local rarityFrame = Instance.new("Frame", mainFrame)
    rarityFrame.Size = UDim2.new(0.9, 0, 0, 200)
    rarityFrame.Position = UDim2.new(0.05, 0, 0, 455)
    rarityFrame.BackgroundTransparency = 1

    local rarityGrid = Instance.new("UIGridLayout", rarityFrame)
    rarityGrid.CellSize = UDim2.new(0.45, 0, 0.3, 0)
    rarityGrid.CellPadding = UDim2.new(0.05, 0, 0.05, 0)

    for _, r in ipairs(rarities) do
        -- Container for rarity button + tracer circle
        local container = Instance.new("Frame", rarityFrame)
        container.BackgroundTransparency = 1
        container.Size = UDim2.new(1, 0, 1, 0) -- will be set by grid

        -- Rarity toggle button
        local btn = Instance.new("TextButton", container)
        btn.Size = UDim2.new(0.7, 0, 1, 0)
        btn.Position = UDim2.new(0, 0, 0, 0)
        btn.Text = r.name
        btn.Font = Enum.Font.GothamBold
        btn.TextScaled = true
        btn.BackgroundColor3 = r.color
        btn.TextColor3 = Color3.new(0,0,0)
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        -- Tracer toggle circle
        local tracerBtn = Instance.new("TextButton", container)
        tracerBtn.Size = UDim2.new(0.25, 0, 0.8, 0)
        tracerBtn.Position = UDim2.new(0.75, 0, 0.1, 0)
        tracerBtn.Text = tracerEnabled[r.name] and "●" or "○"
        tracerBtn.Font = Enum.Font.GothamBold
        tracerBtn.TextScaled = true
        tracerBtn.BackgroundColor3 = r.color
        tracerBtn.TextColor3 = Color3.new(1,1,1)
        Instance.new("UICorner", tracerBtn).CornerRadius = UDim.new(1, 0) -- circle

        -- Tooltip
        btn.MouseEnter:Connect(function()
            tooltip.Text = "Toggle " .. r.name .. " ESP"
        end)
        tracerBtn.MouseEnter:Connect(function()
            tooltip.Text = "Toggle tracer for " .. r.name
        end)
        btn.MouseLeave:Connect(function()
            tooltip.Text = "Hover over buttons for info"
        end)
        tracerBtn.MouseLeave:Connect(function()
            tooltip.Text = "Hover over buttons for info"
        end)

        -- If initially disabled, darken
        if not espEnabled[r.name] then
            btn.BackgroundColor3 = r.color:lerp(Color3.new(0,0,0), 0.7)
        end

        -- ESP toggle
        btn.MouseButton1Click:Connect(function()
            espEnabled[r.name] = not espEnabled[r.name]
            if espEnabled[r.name] then
                btn.BackgroundColor3 = r.color
                -- Re-create ESP for existing blocks
                for gridPos, data in pairs(scannedBlocks) do
                    if data.rarity == r.name and data.part and data.part.Parent then
                        if not data.highlight then
                            local highlight = Instance.new("Highlight")
                            highlight.Parent = data.part
                            highlight.FillColor = r.color
                            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            local billboard = Instance.new("BillboardGui")
                            billboard.Parent = data.part
                            billboard.Size = UDim2.new(0, 120, 0, 40)
                            billboard.StudsOffset = Vector3.new(0, 3, 0)
                            billboard.AlwaysOnTop = true
                            local label = Instance.new("TextLabel", billboard)
                            label.Size = UDim2.fromScale(1, 1)
                            label.BackgroundTransparency = 1
                            label.Text = r.name:upper()
                            label.Font = Enum.Font.GothamBlack
                            label.TextScaled = true
                            label.TextColor3 = r.color
                            label.TextStrokeTransparency = 0
                            data.highlight = highlight
                            data.billboard = billboard
                            table.insert(espByRarity[r.name], {highlight = highlight, billboard = billboard})
                        end
                    end
                end
            else
                btn.BackgroundColor3 = r.color:lerp(Color3.new(0,0,0), 0.7)
                -- Remove ESP for this rarity
                for _, esp in ipairs(espByRarity[r.name]) do
                    if esp.highlight then esp.highlight:Destroy() end
                    if esp.billboard then esp.billboard:Destroy() end
                end
                espByRarity[r.name] = {}
                for gridPos, data in pairs(scannedBlocks) do
                    if data.rarity == r.name then
                        data.highlight = nil
                        data.billboard = nil
                    end
                end
            end
        end)

        -- Tracer toggle
        tracerBtn.MouseButton1Click:Connect(function()
            tracerEnabled[r.name] = not tracerEnabled[r.name]
            tracerBtn.Text = tracerEnabled[r.name] and "●" or "○"
        end)
    end

    -- Stats updater
    task.spawn(function()
        while gui and gui.Parent do
            local txt = ""
            for i, r in ipairs(rarities) do
                txt = txt .. r.name .. ": " .. (rarityCounts[r.name] or 0) .. "  "
                if i % 3 == 0 then txt = txt .. "\n" end
            end
            txt = txt .. "\nBlocks: " .. #scannedBlocks
            txt = txt .. "\nPredictions: " .. #predictionMarkers
            stats.Text = txt
            task.wait(1)
        end
    end)
end

task.wait(1)
InitScannerUI()

-------------------------------------------------
-- KEYBINDS
-------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F9 then
        ENABLE_PREDICTION = not ENABLE_PREDICTION
        if not ENABLE_PREDICTION then
            for _, m in pairs(predictionMarkers) do m:Destroy() end
            predictionMarkers = {}
        end
        print("Prediction:", ENABLE_PREDICTION and "ON" or "OFF")
    elseif input.KeyCode == Enum.KeyCode.F8 then
        ENABLE_FOCUS_MODE = not ENABLE_FOCUS_MODE
        print("Focus Mode:", ENABLE_FOCUS_MODE and "ON" or "OFF")
    elseif input.KeyCode == Enum.KeyCode.F7 then
        updatePredictions()
        print("Prediction update forced")
    elseif input.KeyCode == Enum.KeyCode.F6 then
        for _, m in pairs(predictionMarkers) do m:Destroy() end
        predictionMarkers = {}
        scannedBlocks = {}
        scannedParts = {}
        spatialHash = {}
        for _, r in ipairs(rarities) do
            rarityCounts[r.name] = 0
            positionsByRarity[r.name] = {}
            depthHist[r.name] = {}
        end
        print("All data cleared")
    end
end)

print("[Darkwired Predictor] Loaded. UI visible. F9=Prediction, F8=Focus, F7=Update, F6=Clear")
if not DRAWING_SUPPORTED then
    print("[Darkwired] Note: Drawing library not supported – tracers will not appear.")
else
    print("[Darkwired] Drawing library supported – tracers should work.")
end
