local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Bean Hub",
    SubTitle = "By Big Bean",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- Tabs
local Tabs = {
    Halloween = Window:AddTab({ Title = "Halloween", Icon = "ghost"}),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    PlayerSettings = Window:AddTab({ Title = "Player Settings", Icon = "user" }),
    Keybinds  = Window:AddTab({ Title = "Keybinds", Icon = "keyboard" }),
    AutoTrain = Window:AddTab({ Title = "Auto Train", Icon = "axe" }),
    AutoFight = Window:AddTab({ Title = "Auto Fight", Icon = "angry" }),
    Eggs = Window:AddTab({ Title = "Eggs", Icon = "egg" }),
    Machines = Window:AddTab({ Title = "Machines", Icon = "star" }),
    Misc = Window:AddTab({ Title = "Misc", Icon = "shuffle" })
}
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

-- Ignore keys that are used by ThemeManager.
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title = "Fluent",
    Content = "The script has been loaded.",
    Duration = 8

    
})



local Misc = Tabs.Misc
-- Variable to control the auto roll aura loop
local autoRollAura = false

-- Function to start Auto Roll Aura
local function startAutoRollAura()
    spawn(function()
        while autoRollAura do
            -- Invoke the server function
            game:GetService("ReplicatedStorage").Packages.Knit.Services.AuraService.RF.Roll:InvokeServer()
            -- Wait for 0.0001 seconds before the next iteration
            task.wait(0.0001)
        end
    end)
end

-- Function to stop Auto Roll Aura
local function stopAutoRollAura()
    autoRollAura = false
end

-- Add the Auto Roll Aura toggle to the Misc tab
Misc:AddToggle("Auto Roll Aura", {
    Title = "Auto Roll Aura",
    Default = false,
    Callback = function(enabled)
        autoRollAura = enabled
        if enabled then
            startAutoRollAura()
        else
            stopAutoRollAura()
        end
    end
})


local Halloween = Tabs.Halloween
-- Define teleporting variable
local teleporting = false

-- Function to break the current breakable
local function breakCurrentBreakable(breakable)
    local args = {
        [1] = breakable.Name
    }

    local replicatedStorage = game:GetService("ReplicatedStorage")
    local breakableService = replicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("BreakableService")
    breakableService.RF.HitBreakable:InvokeServer(unpack(args))
end

-- Function to run additional ToolService action
local function runToolService()
    local toolService = game:GetService("ReplicatedStorage").Packages.Knit.Services.ToolService
    toolService.RE.onClick:FireServer()
end

-- Function to find the closest breakable
local function findClosestBreakable()
    local player = game.Players.LocalPlayer
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local hrp = character.HumanoidRootPart
    local closestBreakable = nil
    local closestDistance = math.huge

    local breakables = workspace.GameObjects.Breakables:GetChildren()
    for _, breakable in ipairs(breakables) do
        if breakable:IsA("BasePart") then
            local distance = (breakable.Position - hrp.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestBreakable = breakable
            end
        end
    end

    -- Return the closest breakable only if it's within 500 studs
    if closestDistance <= 500 then
        return closestBreakable
    else
        return nil -- Return nil if no breakable is within the distance
    end
end

-- Function to teleport to breakables
local function teleportToBreakables()
    while teleporting do
        local closestBreakable = findClosestBreakable()
        
        if closestBreakable then
            -- Teleport to the closest breakable
            local humanoidRootPart = game.Players.LocalPlayer.Character.HumanoidRootPart
            humanoidRootPart.CFrame = closestBreakable.CFrame

            -- Start breaking the current breakable and fire ToolService
            local breakableActive = true
            local startTime = os.clock() -- Start timer
            local timerDuration = 9 -- Set to 9 seconds

            spawn(function()
                while breakableActive and teleporting do
                    print("Attempting to break:", closestBreakable.Name) -- Debug output
                    breakCurrentBreakable(closestBreakable)
                    runToolService()
                    wait() -- No wait time for faster hitting
                end
            end)

            -- Wait until the breakable is removed from the hierarchy or 9 seconds pass
            repeat
                wait(0.001)
                closestBreakable = workspace.GameObjects.Breakables:FindFirstChild(closestBreakable.Name)
                
                -- Check if the time limit has been reached
                if os.clock() - startTime >= timerDuration then
                    print("9 seconds reached, moving to next breakable...") -- Debug output
                    breakableActive = false -- Stop breaking the current breakable
                    break -- Exit the repeat loop to find the next closest breakable
                end
            until not closestBreakable

            -- If the breakable is still there after 9 seconds, move to the next one
            if teleporting then
                if not closestBreakable then
                    print("Current breakable destroyed, finding the next one...") -- Debug output
                else
                    print("Current breakable not destroyed, will find next one...") -- Debug output
                end
            end
        else
            print("No breakable found within 100 studs, waiting for 0.01 seconds...") -- Debug output
        end

        wait(0.01) -- Check for new breakables every 0.01 seconds
    end
end

-- Function to start teleporting
local function startTeleporting()
    teleporting = true
    teleportToBreakables()
end

-- Function to stop teleporting
local function stopTeleporting()
    teleporting = false
end

-- Add the teleport toggle to the Halloween tab
Halloween:AddToggle("Auto Break", {
    Title = "Auto Break Breakables",
    Default = false,
    Callback = function(enabled)
        if enabled then
            startTeleporting()
        else
            stopTeleporting()
        end
    end
})

-- Variable to track if the auto Trick or Treat is active
local autoTrickOrTreatActive = false
local trickOrTreatCoroutine -- Variable to hold the coroutine reference

-- Table to track which houses have been trick or treated
local processedHouses = {}
local currentHouseNumber -- Variable to track the current house

-- Teleport to a specific Trick or Treat house and return the house number
local function teleportToHouse(house)
    -- Construct the path to the specific part in the house
    local cubePart = house:FindFirstChild("Table"):FindFirstChild("Table")["Meshes/Table_Cube.007"]

    -- Check if the cube part exists and is a valid BasePart
    if cubePart and cubePart:IsA("BasePart") then
        -- Teleport to the cube part's position
        local humanoidRootPart = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart then
            humanoidRootPart.CFrame = cubePart.CFrame -- Teleport to the specified part
            currentHouseNumber = house.Name -- Update the current house number
            print("Teleported to house: " .. house.Name)
            return house.Name -- Return the house number
        end
    else
        warn("Cube part is missing or is not a BasePart in house: " .. house.Name)
    end
end

-- Run the Trick or Treat service for the current house
local function runTrickOrTreat(houseNumber)
    -- Only run Trick or Treat if the house hasn't been processed
    if processedHouses[houseNumber] then return end

    -- Prepare the arguments for the Trick or Treat service call
    local args = {
        [1] = tostring(houseNumber) -- Convert the house number to a string
    }

    -- Use pcall to handle any potential errors gracefully
    local success, response = pcall(function()
        return game:GetService("ReplicatedStorage").Packages.Knit.Services.TrickOrTreatService.RF.TrickOrTreat:InvokeServer(unpack(args))
    end)

    -- Check the response to ensure it was successful
    if not success then
        warn("Failed to invoke Trick or Treat service for house: " .. houseNumber .. " Error: " .. response)
    else
        print("Successfully invoked Trick or Treat for house: " .. houseNumber)
        processedHouses[houseNumber] = true -- Mark the house as processed
    end
end

-- Find all valid houses in the TrickOrTreat path
local function getHouses()
    local houses = {}
    for _, house in ipairs(workspace.GameObjects.TrickOrTreat:GetChildren()) do
        if house:IsA("Model") then
            table.insert(houses, house) -- Add valid house models to the list
        end
    end
    return houses
end

-- Handle teleporting and running Trick or Treat
local function teleportAndTrickOrTreat()
    local houses = getHouses() -- Get all the houses
    local currentIndex = 1 -- Initialize the current index to track which house to visit

    -- Coroutine for teleporting every 3 seconds
    coroutine.wrap(function()
        while autoTrickOrTreatActive do
            local house = houses[currentIndex] -- Get the current house
            teleportToHouse(house) -- Teleport to the house
            currentIndex = currentIndex + 1 -- Move to the next house

            -- Reset the index to loop through houses again
            if currentIndex > #houses then
                currentIndex = 1 -- Restart from the first house
                processedHouses = {} -- Reset processed houses to start fresh
            end

            wait(3) -- Wait 3 seconds before teleporting to the next house
        end
    end)()

    -- Coroutine for running Trick or Treat every 0.3 seconds
    coroutine.wrap(function()
        while autoTrickOrTreatActive do
            if currentHouseNumber then
                runTrickOrTreat(currentHouseNumber) -- Invoke Trick or Treat for the current house
            end
            wait(0.3) -- Wait 0.3 seconds between invocations
        end
    end)()

    -- Coroutine for invoking WrestleService OnClick every 0.001 seconds
    coroutine.wrap(function()
        while autoTrickOrTreatActive do
            game:GetService("ReplicatedStorage").Packages.Knit.Services.WrestleService.RF.OnClick:InvokeServer()
            wait(0.001) -- Wait 0.001 seconds before invoking again
        end
    end)()
end

-- Add the Auto Trick or Treat toggle to the Halloween tab
Halloween:AddToggle("Auto Trick or Treat", {
    Title = "Trick or Treat",
    Default = false,
    Callback = function(enabled)
        autoTrickOrTreatActive = enabled -- Set the active state
        if enabled then
            -- Start the coroutine only if it is not already running
            if not trickOrTreatCoroutine then
                processedHouses = {} -- Reset processed houses when starting
                trickOrTreatCoroutine = coroutine.create(teleportAndTrickOrTreat) -- Create a coroutine for the function
                coroutine.resume(trickOrTreatCoroutine) -- Start the coroutine
            end
        else
            -- Stop the coroutine by setting the active state to false
            autoTrickOrTreatActive = false -- Ensure the active state is false
            trickOrTreatCoroutine = nil -- Reset the coroutine reference when disabled
        end
    end
})

local ghostHuntingEnabled = false

-- Function to invoke ghost hunting every minute
local function startGhostHuntingLoop()
    while true do
        -- Check if ghost hunting is enabled
        if not ghostHuntingEnabled then
            break -- Exit the loop if hunting is not enabled
        end
        
        -- Invoke the ghost hunting service
        game:GetService("ReplicatedStorage").Packages.Knit.Services.GhostHuntingService.RF.Start:InvokeServer()
        
        print("Entered Ghost Hunting event!")
        wait(60) -- Wait for 1 minute before invoking again
    end
end

-- Function to start ghost hunting when the toggle is enabled
local function startGhostHunting()
    ghostHuntingEnabled = true
    startGhostHuntingLoop() -- Start the loop
end

-- Function to stop ghost hunting when the toggle is disabled
local function stopGhostHunting()
    ghostHuntingEnabled = false
end

-- Add the Ghost Hunting toggle and paragraph to the Halloween tab
Halloween:AddToggle("Ghost Hunting", {
    Title = "Ghost Hunting",
    Default = false,
    Callback = function(enabled)
        if enabled then
            startGhostHunting()
        else
            stopGhostHunting()
        end
    end
})


Tabs.Halloween:AddParagraph({
    Title = "Note",
    Content = "If you want Ghost Hunting to break the ghosts, make sure to turn on the Auto break Breakables toggle!"
})




local PlayerSettings = Tabs.PlayerSettings


Tabs.PlayerSettings:AddButton({
    Title = "Respawn",   -- Button title
    Description = "",  -- Short description
    Callback = function()  -- The function that is executed when the button is clicked
        for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
            if player.Character and player.Character:FindFirstChild("Humanoid") then
                player.Character.Humanoid.Health = 0 -- Set the health of the humanoid to 0, killing the player
            end
        end
        print("Respanw")
    end
})

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Variable to store the input value
local healthInputValue = 100 -- Default health value

-- Function to continuously set the player's health
local function setHealthContinuously()
    while true do
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            player.Character.Humanoid.Health = healthInputValue
        end
        wait(0.001) -- Wait for 0.001 seconds
    end
end

-- Function to update the health input value
local function updateHealthValue(inputValue)
    local numberValue = tonumber(inputValue)
    if numberValue then
        healthInputValue = numberValue
    else
        print("Invalid number input. Please enter a valid number.")
    end
end

-- Adding the input to the UI
Tabs.PlayerSettings:AddInput("Set Health", {
    Title = "Set Health",
    Default = tostring(healthInputValue),
    Callback = function(value)
        updateHealthValue(value)
    end
})

-- Start the continuous health setting
spawn(setHealthContinuously)

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Get current WalkSpeed and JumpPower from the player's Humanoid
local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
local walkspeedValue = humanoid and humanoid.WalkSpeed or 16 -- Default walk speed
local jumpPowerValue = humanoid and humanoid.JumpPower or 50 -- Default jump power

-- Function to continuously update the WalkSpeed
local function updateWalkSpeed()
    while true do
        wait(0.0001) -- Update every 0.0001 seconds
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = walkspeedValue
        end
    end
end

-- Function to continuously update the JumpPower
local function updateJumpPower()
    while true do
        wait(0.0001) -- Update every 0.0001 seconds
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.JumpPower = jumpPowerValue
        end
    end
end

-- Function to start the update processes
local function startUpdatingStats()
    spawn(updateWalkSpeed)
    spawn(updateJumpPower)
end

-- Start updating stats when the player spawns
if player.Character then
    startUpdatingStats()
end

-- Walk Speed Slider
PlayerSettings:AddSlider("Walkspeed", {
    Title = "Walk Speed",
    Min = 16,
    Max = 150, -- Increased maximum value for faster speed
    Default = walkspeedValue, -- Set default to current WalkSpeed
    Rounding = 1,
    DisplayValue = function(value)
        return math.floor((value - 16) / 10) + 1
    end,
    Callback = function(value)
        walkspeedValue = value -- Update the value to be used in the loop
    end
})

-- Jump Power Slider
PlayerSettings:AddSlider("JumpPower", {
    Title = "Jump Power",
    Min = 50,
    Max = 150, -- Increased maximum value for higher jump power
    Default = jumpPowerValue, -- Set default to current JumpPower
    Rounding = 1,
    DisplayValue = function(value)
        return value
    end,
    Callback = function(value)
        jumpPowerValue = value -- Update the value to be used in the loop
    end
})


-- Make sure the stats are always updated on player respawn
player.CharacterAdded:Connect(function(character)
    -- Start updating the WalkSpeed and JumpPower when the character spawns
    character:WaitForChild("Humanoid") -- Wait for the Humanoid to load
    startUpdatingStats()
end)

-- Start updating stats immediately for the current character
if player.Character then
    startUpdatingStats()
end

-- FOV Slider
PlayerSettings:AddSlider("Adjust FOV", {
    Title = "Field of View (70 is normal)",
    Min = 1, -- Minimum FOV
    Max = 120, -- Maximum FOV
    Default = 70, -- Default FOV
    Rounding = 1,
    Callback = function(value)
        game.Workspace.CurrentCamera.FieldOfView = value
    end
})



local Players = game:GetService("Players")
local player = Players.LocalPlayer

local infiniteJumpEnabled = false

-- Function to allow or disallow jumping
local function setInfiniteJump(enabled)
    infiniteJumpEnabled = enabled
end

-- Toggle for infinite jump
Tabs.PlayerSettings:AddToggle("Infinite Jump", {
    Title = "Infinite Jump",
    Default = false,
    Callback = function(enabled)
        setInfiniteJump(enabled)
    end
})

-- Infinite jump logic
local function applyInfiniteJumpLogic()
    while true do
        if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            game:GetService("UserInputService").JumpRequest:Connect(function()
                if infiniteJumpEnabled and humanoid then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        end
        wait(1) -- Check every 1 second to reapply logic if the player respawns
    end
end

-- Start the loop to continuously apply infinite jump logic
spawn(applyInfiniteJumpLogic)


local isFlying = false
local isHoldingSpace = false

PlayerSettings:AddToggle("Fly", {
    Title = "Fly",
    Default = false,
    Callback = function(enabled)
        local player = game.Players.LocalPlayer
        local character = player and player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")

        if not humanoid or not hrp then return end

        if enabled then
            -- Enable flying
            isFlying = true
            humanoid.PlatformStand = true

            local BodyVelocity = Instance.new("BodyVelocity")
            local BodyGyro = Instance.new("BodyGyro")
            BodyVelocity.Parent = hrp
            BodyGyro.Parent = hrp
            BodyGyro.MaxTorque = Vector3.new(4000, 4000, 4000)
            BodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)

            -- Animation and sound settings
            local Hover = Instance.new("Animation")
            Hover.AnimationId = "rbxassetid://18591651576"
            local Fly = Instance.new("Animation")
            Fly.AnimationId = "rbxassetid://18591656031"
            local Sound1 = Instance.new("Sound", hrp)
            Sound1.SoundId = "rbxassetid://3308152153"
            Sound1.Name = "Sound1"
            Sound1.Volume = 0

            local v10 = humanoid.Animator:LoadAnimation(Hover)
            local v11 = humanoid.Animator:LoadAnimation(Fly)
            local Camera = game.Workspace.CurrentCamera
            local TweenService = game:GetService("TweenService")
            local UIS = game:GetService("UserInputService")
            local Flymoving = Instance.new("BoolValue", script)
            Flymoving.Name = "Flymoving"

            -- Movement control
            local function getMovementDirection()
                if humanoid.MoveDirection == Vector3.new(0, 0, 0) then
                    return humanoid.MoveDirection
                end
                local direction = (Camera.CFrame * CFrame.new((CFrame.new(Camera.CFrame.p, Camera.CFrame.p + Vector3.new(Camera.CFrame.lookVector.x, 0, Camera.CFrame.lookVector.z)):VectorToObjectSpace(humanoid.MoveDirection)))).p - Camera.CFrame.p
                return direction.unit
            end

            -- Update flying state
            game:GetService("RunService").RenderStepped:Connect(function()
                if isFlying then
                    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
                    BodyGyro.CFrame = Camera.CFrame
                    Flymoving.Value = getMovementDirection() ~= Vector3.new(0, 0, 0)
                    TweenService:Create(BodyVelocity, TweenInfo.new(0.3), {Velocity = getMovementDirection() * 1000}):Play()

                    -- Apply upward force if spacebar is held
                    if isHoldingSpace then
                        BodyVelocity.Velocity = Vector3.new(0, 50, 0) -- Adjust the upward speed as needed
                    else
                        BodyVelocity.Velocity = Vector3.new(0, 0, 0)
                    end
                end
            end)

            Flymoving.Changed:Connect(function(p1)
                if p1 then
                    TweenService:Create(Camera, TweenInfo.new(0.5), {FieldOfView = 100}):Play()
                    v10:Stop()
                    Sound1:Play()
                    v11:Play()
                else
                    TweenService:Create(Camera, TweenInfo.new(0.5), {FieldOfView = 70}):Play()
                    v11:Stop()
                    Sound1:Stop()
                    v10:Play()
                end
            end)

            UIS.InputBegan:Connect(function(key, gameProcessed)
                if gameProcessed then return end
                if key.KeyCode == Enum.KeyCode.E then
                    if isFlying then
                        isFlying = false
                        Flymoving.Value = false
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
                        hrp.Running.Volume = 0.65
                        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                        -- Clean up BodyGyro and BodyVelocity
                        for _, obj in ipairs(hrp:GetChildren()) do
                            if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then
                                obj:Destroy()
                            end
                        end
                        v10:Stop()
                        v11:Stop()

                        -- Reset player to standing position
                        local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                        if humanoidRootPart then
                            humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position, humanoidRootPart.Position + Vector3.new(0, 0, 1))
                        end
                    else
                        isFlying = true
                        v10:Play(0.1, 1, 1)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
                        hrp.Running.Volume = 0
                        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
                        BodyVelocity.Parent = hrp
                        BodyGyro.Parent = hrp
                    end
                elseif key.KeyCode == Enum.KeyCode.Space then
                    isHoldingSpace = true
                end
            end)

            UIS.InputEnded:Connect(function(key)
                if key.KeyCode == Enum.KeyCode.Space then
                    isHoldingSpace = false
                end
            end)

        else
            -- Disable flying
            isFlying = false
            humanoid.PlatformStand = false
            -- Clean up BodyGyro and BodyVelocity
            for _, obj in ipairs(hrp:GetChildren()) do
                if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then
                    obj:Destroy()
                end
            end
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

            -- Reset player to standing position
            local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position, humanoidRootPart.Position + Vector3.new(0, 0, 1))
            end
        end
    end
})

-- Update WalkSpeed every 0.01 seconds
local RunService = game:GetService("RunService")
RunService.RenderStepped:Connect(function()
    local player = game.Players.LocalPlayer
    local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = walkspeedValue
    end
end)

local Players = game:GetService("Players")
local highlight = Instance.new("Highlight")
highlight.Name = "Highlight"

local isESPEnabled = false -- Variable to track if ESP is enabled

-- Function to setup ESP for a given player
local function setupESPForPlayer(player)
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        if not player.Character.HumanoidRootPart:FindFirstChild("Highlight") then
            local highlightClone = highlight:Clone()
            highlightClone.Adornee = player.Character
            highlightClone.Parent = player.Character.HumanoidRootPart
            highlightClone.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlightClone.Name = "Highlight"
        end
    end
end

-- Function to setup ESP for all players
local function setupESP()
    for _, player in pairs(Players:GetPlayers()) do
        setupESPForPlayer(player)
    end
end

-- Function to enable or disable ESP
local function toggleESP(value)
    isESPEnabled = value
    if isESPEnabled then
        spawn(function()
            -- Start the loop for continuous checking
            while isESPEnabled do
                setupESP() -- Setup ESP every loop iteration
                wait(0.0000001) -- Wait for the specified time before checking again
            end
        end)
    else
        -- Disable ESP: Clean up highlights
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local highlightToRemove = player.Character.HumanoidRootPart:FindFirstChild("Highlight")
                if highlightToRemove then
                    highlightToRemove:Destroy()
                end
            end
        end
    end
end

-- Adding the toggle to the UI
Tabs.PlayerSettings:AddToggle("Toggle ESP", {
    Title = "ESP (See Players Through Walls)", 
    Default = false,
    Callback = function(value)
        toggleESP(value)
    end
})

-- Player added event
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Wait for HumanoidRootPart to be present
        repeat wait() until character:FindFirstChild("HumanoidRootPart")

        -- Only setup highlight if ESP is enabled
        if isESPEnabled then
            setupESPForPlayer(player)
        end
    end)
end)

-- Player removing event
Players.PlayerRemoving:Connect(function(playerRemoved)
    if playerRemoved.Character and playerRemoved:FindFirstChild("HumanoidRootPart") then
        local highlightToRemove = playerRemoved.HumanoidRootPart:FindFirstChild("Highlight")
        if highlightToRemove then
            highlightToRemove:Destroy()
        end
    end
end)


local noClipEnabled = false 
local RunService = game:GetService("RunService")
local LocalPlayer = game.Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- Table to keep track of original CanCollide states
local originalCanCollideStates = {}

-- Function to enable or disable NoClip
local function NoClip(enable)
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            if enable then
                -- Store the original CanCollide state before disabling it
                if originalCanCollideStates[part] == nil then
                    originalCanCollideStates[part] = part.CanCollide
                end
                part.CanCollide = false
            else
                -- Reapply the original CanCollide state if it exists
                if originalCanCollideStates[part] ~= nil then
                    part.CanCollide = originalCanCollideStates[part]
                    -- Optionally clear the entry to avoid carrying old state
                end
            end
        end
    end
end

-- Create NoClip toggle using the specified format
PlayerSettings:AddToggle("NoClip", {
    Title = "NoClip",
    Default = false,
    Callback = function(enabled)
        noClipEnabled = enabled
        if noClipEnabled then
            print("NoClip enabled")
            NoClip(true) -- Enable NoClip
        else
            print("NoClip disabled")
            NoClip(false) -- Disable NoClip
            -- Clear the original states after disabling
            -- Uncomment if you want to clear original states after disabling. 
            -- originalCanCollideStates = {}
        end
    end
})

-- NoClip toggle handler
RunService.Stepped:Connect(function()
    if noClipEnabled and Character and HumanoidRootPart then
        NoClip(true) -- Continuously enable NoClip if enabled
    end
end)

-- Listen for character respawn to reset NoClip
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

    -- Reapply NoClip state on respawn
    NoClip(noClipEnabled)

    -- Clear previous stored CanCollide states since it's a new character
    originalCanCollideStates = {}
end)


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local aimbotEnabled = false
local aimingConnection
local originalTransparency = {} -- Store original transparency values

-- Function to look at players' heads
local function AimAtPlayers()
    aimingConnection = RunService.RenderStepped:Connect(function()
        if not aimbotEnabled then
            aimingConnection:Disconnect() -- Disconnect the loop if aimbot is disabled
            return
        end

        -- Find the closest player
        local closestPlayer = nil
        local closestDistance = math.huge

        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
                local headPosition = player.Character.Head.Position
                local playerDistance = (headPosition - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
                
                if playerDistance < closestDistance then
                    closestDistance = playerDistance
                    closestPlayer = player
                end
            end
        end

        if closestPlayer then
            local camera = workspace.CurrentCamera
            camera.CFrame = CFrame.new(camera.CFrame.Position, closestPlayer.Character.Head.Position)
        end
    end)
end

-- Function to set player invisibility
local function SetInvisibility(enabled)
    if enabled then
        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                originalTransparency[part] = part.Transparency -- Save the original transparency
                part.Transparency = 0.9 -- Make almost invisible
            end
        end
    else
        for part, original in pairs(originalTransparency) do
            if part and part:IsA("BasePart") then
                part.Transparency = original -- Restore original transparency
            end
        end
        originalTransparency = {} -- Clear stored transparency
    end
end

-- Assuming PlayerSettings is a valid UI component for toggles
PlayerSettings:AddToggle("Aimbot", {
    Title = "Aimbot",
    Default = false,
    Callback = function(enabled)
        aimbotEnabled = enabled
        
        if aimbotEnabled then
            print("Aimbot enabled")
            AimAtPlayers() -- Start aiming if enabled
            SetInvisibility(true) -- Set player to be almost invisible
        else
            print("Aimbot disabled")
            if aimingConnection then
                aimingConnection:Disconnect() -- Disconnect if currently connected
                aimingConnection = nil
            end
            SetInvisibility(false) -- Restore player visibility
        end
    end
})

-- Handle when the character respawns to reset the aimbot status
LocalPlayer.CharacterAdded:Connect(function()
    if aimbotEnabled and aimingConnection then
        AimAtPlayers()
    end
end)


-- Function to teleport to a target player
local function teleportToPlayer(targetPlayer)
    if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local targetPosition = targetPlayer.Character.HumanoidRootPart.Position
        
        -- Ensure the player's character exists
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            -- Teleport the player by setting the CFrame directly
            player.Character.HumanoidRootPart.CFrame = CFrame.new(targetPosition)
        end
    end
end

-- Creating buttons for each player in the PlayerSettings tab
local function createTeleportButtons()
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then -- Exclude self
            Tabs.PlayerSettings:AddButton({
                Title = targetPlayer.Name,  -- Button title (Player's username)
                Description = "Teleport to " .. targetPlayer.Name,  -- Short description 
                Callback = function()  -- Function executed when the button is clicked
                    teleportToPlayer(targetPlayer)  -- Teleport to the selected player
                end
            })
        end
    end
end

-- Call the function to create buttons when the game starts or when needed
createTeleportButtons()

-- Optional: Update buttons if players join/leave
Players.PlayerAdded:Connect(function(newPlayer)
    createTeleportButtons() -- Recreate buttons when a new player joins
end)

Players.PlayerRemoving:Connect(function(removedPlayer)
    createTeleportButtons() -- Recreate buttons when a player leaves
end)




-- Keybind Tab
local Keybinds = Tabs.Keybinds

Tabs.Keybinds:AddParagraph({
    Title = "Keybinds",
    Content = "Keybinds are optional and the toggles work the same way, but make sure you dont have the toggle on when you use the keybinds, or it might break."
})
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local infiniteJumpEnabled = false

-- Keybind for toggling Infinite Jump
local Keybind = Tabs.Keybinds:AddKeybind("Infinite Jump Keybind", {
    Title = "Infinite Jump Keybind",
    Mode = "Toggle", -- Mode can be Always, Toggle, or Hold
    Default = "", -- No default keybind set initially
    Callback = function(Value)
        -- Value is true/false when the keybind is clicked
        infiniteJumpEnabled = Value
    end,

    ChangedCallback = function(New)
        print("Keybind changed to:", New)
    end
})

-- Logic to respond to keybind click
Keybind:OnClick(function()
    print("Keybind clicked:", Keybind:GetState())
end)

-- Logic to respond to keybind change
Keybind:OnChanged(function()
    print("Keybind changed:", Keybind.Value)
end)

-- Infinite jump logic
local function applyInfiniteJumpLogic()
    game:GetService("UserInputService").JumpRequest:Connect(function()
        if infiniteJumpEnabled and player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

-- Continuously check if the keybind is being held down
task.spawn(function()
    while true do
        wait(1)
        local state = Keybind:GetState()
        if state then
            print("Keybind is being held down")
        end

        if Fluent.Unloaded then break end
    end
end)

-- Start the infinite jump logic
applyInfiniteJumpLogic()
local isFlying = false
local isHoldingSpace = false

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Keybind for toggling Fly
local FlyKeybind = Tabs.Keybinds:AddKeybind("Fly Keybind", {
    Title = "Fly Keybind",
    Mode = "Toggle", -- Mode can be Always, Toggle, or Hold
    Default = "", -- No default keybind set initially
    Callback = function(Value)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")

        if not humanoid or not hrp then return end

        if Value then
            -- Enable flying
            isFlying = true
            humanoid.PlatformStand = true

            local BodyVelocity = Instance.new("BodyVelocity")
            local BodyGyro = Instance.new("BodyGyro")
            BodyVelocity.Parent = hrp
            BodyGyro.Parent = hrp
            BodyGyro.MaxTorque = Vector3.new(4000, 4000, 4000)
            BodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)

            -- Movement control
            local function getMovementDirection()
                local Camera = game.Workspace.CurrentCamera
                local direction = humanoid.MoveDirection
                if direction == Vector3.new(0, 0, 0) then
                    return direction
                end
                direction = (Camera.CFrame * CFrame.new((CFrame.new(Camera.CFrame.p, Camera.CFrame.p + Vector3.new(Camera.CFrame.lookVector.x, 0, Camera.CFrame.lookVector.z)):VectorToObjectSpace(direction)))).p - Camera.CFrame.p
                return direction.unit
            end

            -- Update flying state
            local connection
            connection = game:GetService("RunService").RenderStepped:Connect(function()
                if not isFlying then
                    connection:Disconnect()
                    return
                end
                humanoid:ChangeState(Enum.HumanoidStateType.Physics)
                BodyGyro.CFrame = game.Workspace.CurrentCamera.CFrame

                if isHoldingSpace then
                    BodyVelocity.Velocity = Vector3.new(0, 50, 0)
                else
                    BodyVelocity.Velocity = getMovementDirection() * 100
                end
            end)

        else
            -- Disable flying
            isFlying = false
            humanoid.PlatformStand = false

            -- Clean up BodyGyro and BodyVelocity
            for _, obj in ipairs(hrp:GetChildren()) do
                if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then
                    obj:Destroy()
                end
            end
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end,

    ChangedCallback = function(New)
        print("Fly Keybind changed to:", New)
    end
})

-- Handling spacebar for upward movement
local UIS = game:GetService("UserInputService")

UIS.InputBegan:Connect(function(key)
    if key.KeyCode == Enum.KeyCode.Space then
        isHoldingSpace = true
    end
end)

UIS.InputEnded:Connect(function(key)
    if key.KeyCode == Enum.KeyCode.Space then
        isHoldingSpace = false
    end
end)


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local noClipEnabled = false 
-- Table to keep track of original CanCollide states
local originalCanCollideStates = {}

-- Function to enable or disable NoClip
local function NoClip(enable)
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            if enable then
                -- Store the original CanCollide state before disabling it
                if originalCanCollideStates[part] == nil then
                    originalCanCollideStates[part] = part.CanCollide
                end
                part.CanCollide = false
            else
                -- Reapply the original CanCollide state if it exists
                if originalCanCollideStates[part] ~= nil then
                    part.CanCollide = originalCanCollideStates[part]
                end
            end
        end
    end
end


-- Adding a keybind for NoClip
local NoClipKeybind = Tabs.Keybinds:AddKeybind("NoClip Keybind", {
    Title = "NoClip Keybind",
    Mode = "Toggle", -- Can be Always, Toggle, or Hold
    Default = "", -- No default keybind set initially
    Callback = function(value)
        noClipEnabled = value -- Set noClipEnabled to the value from the keybind
        if noClipEnabled then
            print("NoClip enabled via keybind")
            NoClip(true) -- Enable NoClip
        else
            print("NoClip disabled via keybind")
            NoClip(false) -- Disable NoClip
        end
    end,
})

-- NoClip toggle handler
RunService.Stepped:Connect(function()
    if noClipEnabled and Character and HumanoidRootPart then
        NoClip(true) -- Continuously enable NoClip if enabled
    end
end)

-- Listen for character respawn to reset NoClip
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

    -- Reapply NoClip state on respawn
    NoClip(noClipEnabled)

    -- Clear previous stored CanCollide states since it's a new character
    originalCanCollideStates = {}
end)


local Players = game:GetService("Players")
local highlight = Instance.new("Highlight")
highlight.Name = "Highlight"

local isESPEnabled = false -- Variable to track if ESP is enabled

-- Function to setup ESP for a given player
local function setupESPForPlayer(player)
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        if not player.Character.HumanoidRootPart:FindFirstChild("Highlight") then
            local highlightClone = highlight:Clone()
            highlightClone.Adornee = player.Character
            highlightClone.Parent = player.Character.HumanoidRootPart
            highlightClone.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlightClone.Name = "Highlight"
        end
    end
end

-- Function to setup ESP for all players
local function setupESP()
    for _, player in pairs(Players:GetPlayers()) do
        setupESPForPlayer(player)
    end
end

-- Function to enable or disable ESP
local function toggleESP(value)
    isESPEnabled = value
    if isESPEnabled then
        spawn(function()
            -- Start the loop for continuous checking
            while isESPEnabled do
                setupESP() -- Setup ESP every loop iteration
                wait(0.0000001) -- Wait for the specified time before checking again
            end
        end)
    else
        -- Disable ESP: Clean up highlights
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local highlightToRemove = player.Character.HumanoidRootPart:FindFirstChild("Highlight")
                if highlightToRemove then
                    highlightToRemove:Destroy()
                end
            end
        end
    end
end

-- Adding a keybind to the UI
local ESPKeybind = Tabs.Keybinds:AddKeybind("ESP Keybind", {
    Title = "ESP Keybind",
    Mode = "Toggle", -- Mode can be Always, Toggle, or Hold
    Default = "", -- No default keybind set initially
    Callback = function(Value)
        -- Toggle ESP on or off when keybind is pressed
        toggleESP(Value)
    end,

    ChangedCallback = function(New)
        print("ESP Keybind changed to:", New)
    end
})

-- Player added event
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Wait for HumanoidRootPart to be present
        repeat wait() until character:FindFirstChild("HumanoidRootPart")

        -- Only setup highlight if ESP is enabled
        if isESPEnabled then
            setupESPForPlayer(player)
        end
    end)
end)

-- Player removing event
Players.PlayerRemoving:Connect(function(playerRemoved)
    if playerRemoved.Character and playerRemoved:FindFirstChild("HumanoidRootPart") then
        local highlightToRemove = playerRemoved.HumanoidRootPart:FindFirstChild("Highlight")
        if highlightToRemove then
            highlightToRemove:Destroy()
        end
    end
end)


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local aimbotEnabled = false
local aimingConnection
local originalTransparency = {} -- Store original transparency values

-- Function to look at players' heads
local function AimAtPlayers()
    aimingConnection = RunService.RenderStepped:Connect(function()
        if not aimbotEnabled then
            aimingConnection:Disconnect() -- Disconnect the loop if aimbot is disabled
            return
        end

        -- Find the closest player
        local closestPlayer = nil
        local closestDistance = math.huge

        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
                local headPosition = player.Character.Head.Position
                local playerDistance = (headPosition - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
                
                if playerDistance < closestDistance then
                    closestDistance = playerDistance
                    closestPlayer = player
                end
            end
        end

        if closestPlayer then
            local camera = workspace.CurrentCamera
            camera.CFrame = CFrame.new(camera.CFrame.Position, closestPlayer.Character.Head.Position)
        end
    end)
end

-- Function to set player invisibility
local function SetInvisibility(enabled)
    if enabled then
        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                originalTransparency[part] = part.Transparency -- Save the original transparency
                part.Transparency = 0.9 -- Make almost invisible
            end
        end
    else
        for part, original in pairs(originalTransparency) do
            if part and part:IsA("BasePart") then
                part.Transparency = original -- Restore original transparency
            end
        end
        originalTransparency = {} -- Clear stored transparency
    end
end

-- Function to toggle the aimbot on and off
local function toggleAimbot(enabled)
    aimbotEnabled = enabled
    
    if aimbotEnabled then
        print("Aimbot enabled")
        AimAtPlayers() -- Start aiming if enabled
        SetInvisibility(true) -- Set player to be almost invisible
    else
        print("Aimbot disabled")
        if aimingConnection then
            aimingConnection:Disconnect() -- Disconnect if currently connected
            aimingConnection = nil
        end
        SetInvisibility(false) -- Restore player visibility
    end
end

-- Adding a keybind for the aimbot
local AimbotKeybind = Tabs.Keybinds:AddKeybind("Aimbot Keybind", {
    Title = "Aimbot Keybind",
    Mode = "Toggle", -- Can be Always, Toggle, or Hold
    Default = "", -- No default keybind set initially
    Callback = function(Value)
        toggleAimbot(Value) -- Toggles the aimbot when keybind is pressed
    end,
})

-- Handle when the character respawns to reset the aimbot status
LocalPlayer.CharacterAdded:Connect(function()
    if aimbotEnabled and aimingConnection then
        AimAtPlayers()
    end
end)






-- Default values
local availableEggs = {}
local selectedEgg = ""
local autoHatchEnabled = false
local eventEggAutoHatchEnabled = false
local hatchMultiplier = "1x"
local autoDeleteEnabled = false
local autoDeleteChance = 0
local petData = require(game:GetService("ReplicatedStorage").Data.EggData)

-- Fetch egg names from EggData
local function fetchAvailableEggs()
    availableEggs = {}
    local eggData = require(game:GetService("ReplicatedStorage").Data.EggData)

    for eggName, _ in pairs(eggData) do
        if not (eggName:match("Limited") or eggName:match("Event") or eggName:match("MusicalDragon") or eggName:match("100x") or eggName:match("Sour") or eggName:match("Gem") or eggName:match("Cyberpunk")) then
            if eggName:sub(-3) == "Egg" then
                eggName = eggName:sub(1, -4)
            end
            table.insert(availableEggs, eggName)
        end
    end

    -- Sort alphabetically
    table.sort(availableEggs)
end

-- Fetch available eggs initially
fetchAvailableEggs()

-- Function to send remote args
local function SendRemote(args)
    local eggService = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
        and game:GetService("ReplicatedStorage").Packages:FindFirstChild("Knit")
        and game:GetService("ReplicatedStorage").Packages.Knit.Services
        and game:GetService("ReplicatedStorage").Packages.Knit.Services.EggService
        and game:GetService("ReplicatedStorage").Packages.Knit.Services.EggService.RF
        and game:GetService("ReplicatedStorage").Packages.Knit.Services.EggService.RF.purchaseEgg

    if eggService then
        eggService:InvokeServer(unpack(args))
    end
end

-- Function to start auto-hatching for normal eggs
local function startAutoHatch()
    while autoHatchEnabled do
        local petSettings = {}

        -- Dynamically set all pets to true/false based on autoDeleteEnabled
        for eggName, data in pairs(petData) do
            if data.Chances then
                for petName, chance in pairs(data.Chances) do
                    petSettings[petName] = autoDeleteEnabled and chance >= autoDeleteChance or false
                end
            end
        end

        local args = {}
        if hatchMultiplier == "1x" then
            args = {selectedEgg, petSettings, false, true, false}
        elseif hatchMultiplier == "3x" then
            args = {selectedEgg, petSettings, true, false}
        elseif hatchMultiplier == "8x" then
            args = {selectedEgg, petSettings, false, true, true}
        elseif hatchMultiplier == "30x" then
            args = {selectedEgg, petSettings, false, false, nil, true}
        end

        SendRemote(args)
        wait(0.001)
    end
end

-- Toggle auto-hatching on/off
local function toggleAutoHatch(value)
    autoHatchEnabled = value
    if autoHatchEnabled then
        spawn(startAutoHatch)
    end
end

-- Function to start auto-hatching Event Eggs (always 8x)
local function startAutoHatchEventEgg()
    while eventEggAutoHatchEnabled do
        local args = {8} -- Always hatch 8x for event eggs

        local eventService = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
            and game:GetService("ReplicatedStorage").Packages:FindFirstChild("Knit")
            and game:GetService("ReplicatedStorage").Packages.Knit.Services
            and game:GetService("ReplicatedStorage").Packages.Knit.Services.EventService
            and game:GetService("ReplicatedStorage").Packages.Knit.Services.EventService.RF
            and game:GetService("ReplicatedStorage").Packages.Knit.Services.EventService.RF.ClaimEgg

        if eventService then
            eventService:InvokeServer(unpack(args))
        end

        wait(0.01) -- Adjust this delay as needed
    end
end

-- Toggle auto-hatching Event Eggs on/off
local function toggleEventEggAutoHatch(value)
    eventEggAutoHatchEnabled = value
    if eventEggAutoHatchEnabled then
        spawn(startAutoHatchEventEgg)
    end
end

-- Function to handle auto-deleting pets based on chance, restricted to selected egg
local function autoDeletePets()
    -- Only execute once when enabled
    local petsToDelete = {}

    -- Check only the selected egg's data
    if selectedEgg and petData[selectedEgg] and petData[selectedEgg].Chances then
        for petName, chance in pairs(petData[selectedEgg].Chances) do
            if chance >= autoDeleteChance then
                table.insert(petsToDelete, petName)
            end
        end
    end

    -- Delete pets
    for _, petName in ipairs(petsToDelete) do
        local args = {
            [1] = petName
        }
        game:GetService("ReplicatedStorage").Packages.Knit.Services.PetService.RF.SetAutoDelete:InvokeServer(unpack(args))
    end
end

-- Toggle auto-delete on/off
local function toggleAutoDelete(value)
    autoDeleteEnabled = value
    autoDeletePets() -- Call the deletion function when toggled on or off
end

-- Add dropdown to select eggs with search feature
Tabs.Eggs:AddDropdown("SelectEggDropdown", {
    Title = "Select Egg",
    Values = availableEggs,
    Default = selectedEgg,
    Search = true,
    Callback = function(selected)
        selectedEgg = selected
    end
})

-- Add dropdown to select hatch multiplier (1x, 3x, 8x)
Tabs.Eggs:AddDropdown("SelectHatchMultiplier", {
    Title = "Hatch Multiplier",
    Values = { "1x", "3x", "8x", "30x" },
    Default = hatchMultiplier,
    Callback = function(selected)
        hatchMultiplier = selected
    end
})

-- Add toggle to start/stop auto-hatching
Tabs.Eggs:AddToggle("AutoHatchToggle", {
    Title = "Auto Hatch",
    Default = false,
    Callback = function(value)
        toggleAutoHatch(value)
    end
})

-- Add heading for Event Eggs section
Tabs.Eggs:AddParagraph({
    Title = "Event Eggs",
    Content = "Enjoy this free 8x hatch for event eggs. You don't need to own the gamepass for this to work."
})

-- Add toggle for Event Eggs (always 8x)
Tabs.Eggs:AddToggle("EventEggAutoHatchToggle", {
    Title = "Auto Hatch Event Eggs (8x)",
    Default = false,
    Callback = function(value)
        toggleEventEggAutoHatch(value)
    end
})

-- Add heading for Auto Delete section
Tabs.Eggs:AddParagraph({
    Title = "Auto Delete",
    Content = "Automatically delete pets based on their chances. Pets with chances equal to or higher than the value set will be deleted. There is a bug with auto delete where it sometimes won't work, to fix this turn the toggle on and off. It won't show the pets being deleted but you won't gain them in your inventory."
})

-- Add toggle for auto-delete pets
Tabs.Eggs:AddToggle("AutoDeleteToggle", {
    Title = "Auto Delete Pets",
    Default = false,
    Callback = function(value)
        toggleAutoDelete(value)
    end
})

-- Add input for auto-delete chance
Tabs.Eggs:AddInput("AutoDeleteChanceInput", {
    Title = "Delete Chances Higher than:",
    Default = "0",
    Numeric = true,
    Callback = function(value)
        autoDeleteChance = tonumber(value) or 0
    end
})

-- Add a button to fetch and update available eggs
Tabs.Eggs:AddButton("Refresh Egg List", function()
    fetchAvailableEggs()
    Tabs.Eggs:UpdateDropdown("SelectEggDropdown", availableEggs)
end)


-- Load previously saved configurations
SaveManager:LoadAutoloadConfig()

