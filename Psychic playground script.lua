local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Load Mano Gustavo UI Library
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Mano-Gustavo/Mano-Gustavo-Library/refs/heads/main/library.lua"
))()

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Store original game values to restore them when features are disabled
local OriginalValues = {
    PsychicRange = nil,
    Stored = false
}

-- Settings configuration for all features
local Settings = {
    Hitbox = {Enabled = false, Size = 15},
    Fly = {Enabled = false, Speed = 50},
    Noclip = {Enabled = false},
    EnergyOrb = {AutoCollect = false},
    ESP = {Enabled = false, ShowName = true, ShowHealth = true},
    InfRange = {Enabled = false}
}

local Components = {} -- References to UI components for programmatic control
local Connections = {} -- Store all event connections for proper cleanup
local CachedOrbs = {} -- Cache for energy orb objects to improve performance
local LastOrbScan = 0 -- Timestamp of last orb scan to prevent frequent scanning
local flyBody = nil -- BodyVelocity object for flying
local flyGyro = nil -- BodyGyro object for flying rotation
local TeleportTool = nil -- Reference to teleport tool
local infRangeDebounce = false -- Prevent multiple infinite range activations at once
local lastKeyPress = {} -- Track last key presses for debouncing

-- Apply custom theme to the UI
Library:SetTheme({
    MainColor = Color3.fromRGB(30, 30, 40),
    SecondaryColor = Color3.fromRGB(40, 40, 50),
    AccentColor = Color3.fromRGB(0, 170, 255),
    TextColor = Color3.fromRGB(240, 240, 240),
    SectionColor = Color3.fromRGB(35, 35, 45)
})

-- Create main window for the UI
local Window = Library:CreateWindow({
    Title = "ManoGustavo Hub - Psychic Playground",
    Keybind = Enum.KeyCode.RightControl
})

-- Create tabs for organization
local TabMain = Window:CreateTab("Main")
local TabESP = Window:CreateTab("Visuals")
local TabHitbox = Window:CreateTab("Hitbox")
local TabSettings = Window:CreateTab("Settings")

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

-- Returns the player's character
local function GetCharacter()
    return LocalPlayer.Character
end

-- Returns the player's HumanoidRootPart
local function GetHRP()
    local char = GetCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Returns the player's Humanoid
local function GetHumanoid()
    local char = GetCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- Checks if the player is alive
local function IsAlive()
    local hum = GetHumanoid()
    return hum and hum.Health > 0
end

-- Saves original PsychicRange value for restoration
local function SaveOriginalValues()
    if OriginalValues.Stored then return end
    
    task.spawn(function()
        local success, data = pcall(function()
            return LocalPlayer:WaitForChild("Data", 10)
        end)
        
        if success and data then
            local attributes = data:FindFirstChild("Attributes")
            if attributes then
                local rangeValue = attributes:FindFirstChild("PsychicRange")
                
                if rangeValue then
                    OriginalValues.PsychicRange = rangeValue.Value
                end
            end
            
            OriginalValues.Stored = true
        end
    end)
end

SaveOriginalValues()

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    SaveOriginalValues()
end)

-- ============================================
-- FLY MODULE
-- ============================================
-- Enables flying movement using BodyVelocity and BodyGyro
-- WASD + Space/Shift controls with camera-relative movement
local FlyModule = {}

-- Starts flying by creating physics objects and setting up movement controls
function FlyModule:Start()
    local character = GetCharacter()
    if not character then return end
    
    local hrp = GetHRP()
    local humanoid = GetHumanoid()
    if not hrp or not humanoid then return end
    
    self:Stop()
    
    flyBody = Instance.new("BodyVelocity")
    flyBody.Name = "FlyVelocity"
    flyBody.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    flyBody.Velocity = Vector3.new(0, 0, 0)
    flyBody.Parent = hrp
    
    flyGyro = Instance.new("BodyGyro")
    flyGyro.Name = "FlyGyro"
    flyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    flyGyro.P = 9e4
    flyGyro.CFrame = hrp.CFrame
    flyGyro.Parent = hrp
    
    humanoid.PlatformStand = true
    
    -- Main flying movement loop
    Connections.Fly = RunService.RenderStepped:Connect(function()
        if not Settings.Fly.Enabled or not flyBody or not flyBody.Parent then 
            self:Stop()
            return 
        end
        
        local currentHrp = GetHRP()
        if not currentHrp then return end
        
        local direction = Vector3.new(0, 0, 0)
        local speed = Settings.Fly.Speed
        
        -- Camera-relative movement controls
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction = direction + Camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction = direction - Camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction = direction - Camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction = direction + Camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            direction = direction + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            direction = direction - Vector3.new(0, 1, 0)
        end
        
        if direction.Magnitude > 0 then
            flyBody.Velocity = direction.Unit * speed
        else
            flyBody.Velocity = Vector3.new(0, 0, 0)
        end
        
        flyGyro.CFrame = CFrame.new(currentHrp.Position, currentHrp.Position + Camera.CFrame.LookVector)
    end)
end

-- Stops flying and cleans up physics objects
function FlyModule:Stop()
    if Connections.Fly then
        Connections.Fly:Disconnect()
        Connections.Fly = nil
    end
    
    if flyBody then
        flyBody:Destroy()
        flyBody = nil
    end
    
    if flyGyro then
        flyGyro:Destroy()
        flyGyro = nil
    end
    
    local character = GetCharacter()
    if character then
        local humanoid = GetHumanoid()
        if humanoid then
            humanoid.PlatformStand = false
        end
        
        local hrp = GetHRP()
        if hrp then
            for _, child in ipairs(hrp:GetChildren()) do
                if child.Name == "FlyVelocity" or child.Name == "FlyGyro" then
                    child:Destroy()
                end
            end
        end
    end
end

-- ============================================
-- NOCLIP MODULE
-- ============================================
-- Allows walking through walls by disabling collision on character parts
local NoclipModule = {}

-- Starts noclip by continuously disabling collision
function NoclipModule:Start()
    if Connections.Noclip then return end
    
    Connections.Noclip = RunService.Stepped:Connect(function()
        if not Settings.Noclip.Enabled then return end
        
        local character = GetCharacter()
        if not character then return end
        
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

-- Stops noclip and restores collision
function NoclipModule:Stop()
    if Connections.Noclip then
        Connections.Noclip:Disconnect()
        Connections.Noclip = nil
    end
    
    local character = GetCharacter()
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

-- ============================================
-- INFINITE RANGE MODULE
-- ============================================
-- Allows selecting objects from any distance by teleporting to them temporarily
-- IMPORTANT: Requires TWO CLICKS to work properly:
-- 1. First click: Teleports you near the object
-- 2. Second click (automatic): Selects the object using the game's remote event
-- The system automatically teleports you back after selection
local InfRangeModule = {}

-- Starts infinite range by overriding PsychicRange and setting up click detection
function InfRangeModule:Start()
    if Connections.InfRange then
        Connections.InfRange:Disconnect()
    end
    
    task.spawn(function()
        local success, rangeStat = pcall(function()
            local data = LocalPlayer:WaitForChild("Data", 10)
            local attributes = data:WaitForChild("Attributes", 10)
            return attributes:WaitForChild("PsychicRange", 10)
        end)
        
        if success and rangeStat then
            if not OriginalValues.PsychicRange then
                OriginalValues.PsychicRange = rangeStat.Value
            end
            
            rangeStat.Value = 9999
            
            -- Set up click detection for object selection
            Connections.InfRange = Mouse.Button1Down:Connect(function()
                if not Settings.InfRange.Enabled then return end
                if infRangeDebounce then return end
                
                local target = Mouse.Target
                if not target then return end
                if not (target:IsDescendantOf(Workspace.Objects) or target:IsDescendantOf(Workspace.BrokenObjects)) then return end
                
                local hrp = GetHRP()
                if not hrp then return end
                
                infRangeDebounce = true
                
                -- Two-click process: Teleport → Select → Return
                task.spawn(function()
                    local originalCFrame = hrp.CFrame
                    local originalCamType = Camera.CameraType
                    local originalSubject = Camera.CameraSubject
                    
                    pcall(function()
                        -- Step 1: Teleport near the object (First click effect)
                        Camera.CameraType = Enum.CameraType.Scriptable
                        
                        hrp.CFrame = CFrame.new(target.Position + Vector3.new(0, 5, 0))
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        
                        task.wait(0.1)
                        
                        -- Step 2: Automatically select the object (Second click simulation)
                        if _G.RemoteEvent then
                            _G.RemoteEvent:FireServer("SelectObject", target)
                        end
                        
                        task.wait(0.15)
                        
                        -- Step 3: Return to original position
                        hrp.CFrame = originalCFrame
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        
                        task.wait(0.05)
                        
                        Camera.CameraType = originalCamType
                        Camera.CameraSubject = originalSubject
                    end)
                    
                    task.wait(0.5)
                    infRangeDebounce = false
                end)
            end)
        end
    end)
end

-- Stops infinite range and restores original values
function InfRangeModule:Stop()
    if Connections.InfRange then
        Connections.InfRange:Disconnect()
        Connections.InfRange = nil
    end
    
    task.spawn(function()
        local success, rangeStat = pcall(function()
            local data = LocalPlayer:WaitForChild("Data", 5)
            local attributes = data:WaitForChild("Attributes", 5)
            return attributes:WaitForChild("PsychicRange", 5)
        end)
        
        if success and rangeStat and OriginalValues.PsychicRange then
            rangeStat.Value = OriginalValues.PsychicRange
        end
    end)
    
    pcall(function()
        Camera.CameraType = Enum.CameraType.Custom
        local humanoid = GetHumanoid()
        if humanoid then
            Camera.CameraSubject = humanoid
        end
    end)
    
    infRangeDebounce = false
end

-- ============================================
-- TELEPORT MODULE
-- ============================================
-- Provides a teleport tool for manual teleportation
local TeleportModule = {}

-- Creates a teleport tool in the player's backpack
function TeleportModule:CreateTool()
    if TeleportTool and TeleportTool.Parent then
        TeleportTool:Destroy()
    end
    
    local tool = Instance.new("Tool")
    tool.Name = "Teleport Tool"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    
    tool.Activated:Connect(function()
        local hrp = GetHRP()
        if not hrp then return end
        
        local target = Mouse.Hit
        if target then
            hrp.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
        end
    end)
    
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        tool.Parent = backpack
        TeleportTool = tool
        return true
    end
    
    return false
end

-- Removes the teleport tool
function TeleportModule:RemoveTool()
    if TeleportTool and TeleportTool.Parent then
        TeleportTool:Destroy()
        TeleportTool = nil
    end
end

-- ============================================
-- HITBOX MODULE
-- ============================================
-- Expands enemy hitboxes to make them easier to hit
local HitboxModule = {}

-- Expands a player's hitbox size
function HitboxModule:Expand(player)
    if player == LocalPlayer then return end
    if not Settings.Hitbox.Enabled then return end
    
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    local size = Settings.Hitbox.Size
    
    if hrp then
        pcall(function()
            hrp.Size = Vector3.new(size, size, size)
            hrp.Transparency = 0.7
            hrp.CanCollide = false
            hrp.Material = Enum.Material.ForceField
            hrp.BrickColor = BrickColor.new("Really red")
        end)
    end
    
    if head then
        pcall(function()
            head.Size = Vector3.new(size, size, size)
            head.Transparency = 0.7
            head.CanCollide = false
            head.Material = Enum.Material.ForceField
            head.BrickColor = BrickColor.new("Really red")
        end)
    end
end

-- Resets a player's hitbox to original size
function HitboxModule:Reset(player)
    if not player then return end
    
    local character = player.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    
    if hrp then
        pcall(function()
            hrp.Size = Vector3.new(2, 2, 1)
            hrp.Transparency = 1
            hrp.CanCollide = false
            hrp.Material = Enum.Material.Plastic
        end)
    end
    
    if head then
        pcall(function()
            head.Size = Vector3.new(2, 1, 1)
            head.Transparency = 0
            head.CanCollide = false
            head.Material = Enum.Material.Plastic
        end)
    end
end

-- Starts continuously expanding all enemy hitboxes
function HitboxModule:Start()
    if Connections.Hitbox then return end
    
    Connections.Hitbox = RunService.Heartbeat:Connect(function()
        if not Settings.Hitbox.Enabled then return end
        
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                self:Expand(player)
            end
        end
    end)
end

-- Stops hitbox expansion and resets all players
function HitboxModule:Stop()
    if Connections.Hitbox then
        Connections.Hitbox:Disconnect()
        Connections.Hitbox = nil
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:Reset(player)
        end
    end
end

-- ============================================
-- ENERGY ORB MODULE
-- ============================================
-- Automatically collects energy orbs in the game world
local EnergyOrbModule = {}

-- Scans the workspace for energy orbs with caching for performance
function EnergyOrbModule:ScanOrbs()
    local currentTime = tick()
    
    if currentTime - LastOrbScan < 1 then
        return CachedOrbs
    end
    
    LastOrbScan = currentTime
    CachedOrbs = {}
    
    for _, child in ipairs(Workspace:GetChildren()) do
        if child.Name == "EnergyOrb" then
            table.insert(CachedOrbs, child)
        elseif child:IsA("Folder") or child:IsA("Model") then
            for _, subChild in ipairs(child:GetChildren()) do
                if subChild.Name == "EnergyOrb" then
                    table.insert(CachedOrbs, subChild)
                end
            end
        end
    end
    
    return CachedOrbs
end

-- Teleports all found orbs to the player's position
function EnergyOrbModule:TeleportOrbs()
    local hrp = GetHRP()
    if not hrp then return 0 end
    
    local orbs = self:ScanOrbs()
    local count = 0
    local targetPosition = hrp.CFrame
    
    for i = 1, #orbs do
        local orb = orbs[i]
        
        if orb and orb.Parent then
            pcall(function()
                if orb:IsA("BasePart") then
                    orb.CFrame = targetPosition
                    count = count + 1
                elseif orb:IsA("Model") then
                    local primary = orb.PrimaryPart
                    if primary then
                        orb:SetPrimaryPartCFrame(targetPosition)
                        count = count + 1
                    else
                        local part = orb:FindFirstChildWhichIsA("BasePart")
                        if part then
                            part.CFrame = targetPosition
                            count = count + 1
                        end
                    end
                end
            end)
        end
    end
    
    return count
end

-- Starts automatic orb collection on a timer
function EnergyOrbModule:StartAutoCollect()
    if Connections.AutoCollect then return end
    
    Connections.AutoCollect = task.spawn(function()
        while Settings.EnergyOrb.AutoCollect do
            if IsAlive() then
                self:TeleportOrbs()
            end
            task.wait(2)
        end
    end)
end

-- Stops automatic orb collection
function EnergyOrbModule:StopAutoCollect()
    Settings.EnergyOrb.AutoCollect = false
    Connections.AutoCollect = nil
    CachedOrbs = {}
end

-- ============================================
-- ESP MODULE
-- ============================================
-- Visual ESP (Extra Sensory Perception) for players
local ESPModule = {}

-- Creates ESP visuals for a player (highlight and info labels)
function ESPModule:CreateESP(player)
    if player == LocalPlayer then return end
    
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local head = character:FindFirstChild("Head")
    if not humanoid or not head then return end
    
    self:RemoveESP(player)
    
    -- Create highlight effect
    local highlight = Instance.new("Highlight")
    highlight.Name = "ManoGustavoESP"
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = character
    
    -- Create billboard GUI for name and health info
    if Settings.ESP.ShowName or Settings.ESP.ShowHealth then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ManoGustavoESPGui"
        billboard.Size = UDim2.new(0, 100, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = head
        
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 1, 0)
        container.BackgroundTransparency = 1
        container.Parent = billboard
        
        local layout = Instance.new("UIListLayout")
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.Parent = container
        
        if Settings.ESP.ShowName then
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "NameLabel"
            nameLabel.Size = UDim2.new(1, 0, 0, 20)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = player.Name
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.TextStrokeTransparency = 0
            nameLabel.TextSize = 14
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.Parent = container
        end
        
        if Settings.ESP.ShowHealth then
            local healthLabel = Instance.new("TextLabel")
            healthLabel.Name = "HealthLabel"
            healthLabel.Size = UDim2.new(1, 0, 0, 16)
            healthLabel.BackgroundTransparency = 1
            healthLabel.Text = math.floor(humanoid.Health) .. " HP"
            healthLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            healthLabel.TextStrokeTransparency = 0
            healthLabel.TextSize = 12
            healthLabel.Font = Enum.Font.Gotham
            healthLabel.Parent = container
            
            -- Update health dynamically
            local healthConnection
            healthConnection = humanoid.HealthChanged:Connect(function(health)
                if not healthLabel or not healthLabel.Parent then
                    if healthConnection then
                        healthConnection:Disconnect()
                    end
                    return
                end
                
                healthLabel.Text = math.floor(health) .. " HP"
                
                -- Color code based on health percentage
                local percent = health / humanoid.MaxHealth
                if percent > 0.5 then
                    healthLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
                elseif percent > 0.25 then
                    healthLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
                else
                    healthLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
                end
            end)
        end
    end
end

-- Removes ESP visuals from a player
function ESPModule:RemoveESP(player)
    if player == LocalPlayer then return end
    
    local character = player.Character
    if not character then return end
    
    local highlight = character:FindFirstChild("ManoGustavoESP")
    if highlight then
        highlight:Destroy()
    end
    
    local head = character:FindFirstChild("Head")
    if head then
        local billboard = head:FindFirstChild("ManoGustavoESPGui")
        if billboard then
            billboard:Destroy()
        end
    end
end

-- Initializes ESP for all current and future players
function ESPModule:Start()
    -- Apply ESP to existing players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            self:CreateESP(player)
        end
    end
    
    Connections.ESPCharacter = {}
    
    -- Set up connections for character additions
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local conn = player.CharacterAdded:Connect(function()
                task.wait(1)
                if Settings.ESP.Enabled then
                    self:CreateESP(player)
                end
            end)
            table.insert(Connections.ESPCharacter, conn)
        end
    end
    
    -- Handle new players joining
    Connections.ESPPlayerAdded = Players.PlayerAdded:Connect(function(player)
        local conn = player.CharacterAdded:Connect(function()
            task.wait(1)
            if Settings.ESP.Enabled then
                self:CreateESP(player)
            end
        end)
        table.insert(Connections.ESPCharacter, conn)
        
        if player.Character then
            task.wait(1)
            if Settings.ESP.Enabled then
                self:CreateESP(player)
            end
        end
    end)
    
    -- Clean up when players leave
    Connections.ESPPlayerRemoving = Players.PlayerRemoving:Connect(function(player)
        self:RemoveESP(player)
    end)
end

-- Stops ESP and cleans up all connections
function ESPModule:Stop()
    if Connections.ESPPlayerAdded then
        Connections.ESPPlayerAdded:Disconnect()
        Connections.ESPPlayerAdded = nil
    end
    
    if Connections.ESPPlayerRemoving then
        Connections.ESPPlayerRemoving:Disconnect()
        Connections.ESPPlayerRemoving = nil
    end
    
    if Connections.ESPCharacter then
        for _, conn in ipairs(Connections.ESPCharacter) do
            pcall(function() conn:Disconnect() end)
        end
        Connections.ESPCharacter = nil
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        self:RemoveESP(player)
    end
end

-- Refreshes ESP for all players
function ESPModule:Refresh()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:RemoveESP(player)
            if Settings.ESP.Enabled then
                self:CreateESP(player)
            end
        end
    end
end

-- ============================================
-- UI CONSTRUCTION WITH MANO GUSTAVO UI
-- ============================================

-- Main Tab Sections
local SectionMovement = TabMain:CreateSection("Movement")
local SectionObjects = TabMain:CreateSection("Objects")
local SectionPlayer = TabMain:CreateSection("Player")
local SectionOrbs = TabMain:CreateSection("Energy Orbs")

-- Fly Toggle with detailed explanation
Components.FlyToggle = SectionMovement:CreateToggle("Fly", function(Value)
    Settings.Fly.Enabled = Value
    if Value then 
        FlyModule:Start()
        Components.FlyToggle:OnEnable(function()
            Library:Notification({
                Title = "Fly",
                Text = "Enabled - Use WASD for movement, Space to ascend, Shift/Ctrl to descend",
                Duration = 4,
                Type = "Success"
            })
        end)
    else 
        FlyModule:Stop()
        Components.FlyToggle:OnDisable(function()
            Library:Notification({
                Title = "Fly",
                Text = "Disabled",
                Duration = 2,
                Type = "Info"
            })
        end)
    end
end, false)
Components.FlyToggle:SetTooltip("Enable flying movement with camera-relative controls")

-- Fly Speed Slider
Components.FlySpeed = SectionMovement:CreateSlider(
    "Fly Speed",
    10,
    200,
    50,
    function(Value)
        Settings.Fly.Speed = Value
    end
)
Components.FlySpeed:SetTooltip("Adjust the speed of flying movement (10-200)")

-- Noclip Toggle
Components.NoclipToggle = SectionMovement:CreateToggle("Noclip", function(Value)
    Settings.Noclip.Enabled = Value
    if Value then 
        NoclipModule:Start()
        Components.NoclipToggle:OnEnable(function()
            Library:Notification({
                Title = "Noclip",
                Text = "Enabled - You can now walk through walls and objects",
                Duration = 3,
                Type = "Success"
            })
        end)
    else 
        NoclipModule:Stop()
        Components.NoclipToggle:OnDisable(function()
            Library:Notification({
                Title = "Noclip",
                Text = "Disabled",
                Duration = 2,
                Type = "Info"
            })
        end)
    end
end, false)
Components.NoclipToggle:SetTooltip("Walk through walls and objects by disabling collision")

-- Infinite Range Toggle with TWO-CLICK EXPLANATION
Components.InfRangeToggle = SectionObjects:CreateToggle("Infinite Range", function(Value)
    Settings.InfRange.Enabled = Value
    if Value then 
        InfRangeModule:Start()
        Components.InfRangeToggle:OnEnable(function()
            Library:Notification({
                Title = "Infinite Range",
                Text = "Enabled - Click ANY object to select it!\n\nHOW IT WORKS:\n1. First click: Teleports you near the object\n2. Second click (automatic): Selects the object\n3. Automatically returns you to original position",
                Duration = 6,
                Type = "Success"
            })
        end)
    else 
        InfRangeModule:Stop()
        Components.InfRangeToggle:OnDisable(function()
            Library:Notification({
                Title = "Infinite Range",
                Text = "Disabled - Object selection now requires normal range",
                Duration = 3,
                Type = "Info"
            })
        end)
    end
end, false)
Components.InfRangeToggle:SetTooltip("Select objects from ANY distance! IMPORTANT: Requires ONE click on the object - system handles the rest automatically with teleportation.")

-- Teleport Tool Button
SectionPlayer:CreateButton("Give Teleport Tool", function()
    local success = TeleportModule:CreateTool()
    Library:Notification({
        Title = "Teleport Tool",
        Text = success and "Teleport tool added to your backpack!\nEquip and click anywhere to teleport." or "Failed to add teleport tool",
        Duration = 4,
        Type = success and "Success" or "Error"
    })
end)

-- Auto Collect Orbs Toggle
Components.AutoCollect = SectionOrbs:CreateToggle("Auto Collect Orbs", function(Value)
    Settings.EnergyOrb.AutoCollect = Value
    if Value then 
        EnergyOrbModule:StartAutoCollect()
        Components.AutoCollect:OnEnable(function()
            Library:Notification({
                Title = "Auto Collect",
                Text = "Enabled - Automatically collecting energy orbs every 2 seconds",
                Duration = 3,
                Type = "Success"
            })
        end)
    else 
        EnergyOrbModule:StopAutoCollect()
        Components.AutoCollect:OnDisable(function()
            Library:Notification({
                Title = "Auto Collect",
                Text = "Disabled",
                Duration = 2,
                Type = "Info"
            })
        end)
    end
end, false)
Components.AutoCollect:SetTooltip("Automatically teleports all energy orbs to your position every 2 seconds")

-- Collect All Orbs Button
SectionOrbs:CreateButton("Collect All Orbs", function()
    local count = EnergyOrbModule:TeleportOrbs()
    Library:Notification({
        Title = "Orbs Collected",
        Text = "Successfully collected " .. count .. " energy orbs!\nThey have been teleported to your current position.",
        Duration = 4,
        Type = count > 0 and "Success" or "Info"
    })
end)

-- ESP Tab Section
local SectionESP = TabESP:CreateSection("Player ESP")

-- ESP Toggle
Components.ESPToggle = SectionESP:CreateToggle("Enable ESP", function(Value)
    Settings.ESP.Enabled = Value
    if Value then 
        ESPModule:Start()
        Components.ESPToggle:OnEnable(function()
            Library:Notification({
                Title = "ESP",
                Text = "Enabled - All players are now highlighted with information",
                Duration = 3,
                Type = "Success"
            })
        end)
    else 
        ESPModule:Stop()
        Components.ESPToggle:OnDisable(function()
            Library:Notification({
                Title = "ESP",
                Text = "Disabled",
                Duration = 2,
                Type = "Info"
            })
        end)
    end
end, false)
Components.ESPToggle:SetTooltip("Show player highlights with name and health information")

-- Show Names Toggle
SectionESP:CreateToggle("Show Names", function(Value)
    Settings.ESP.ShowName = Value
    ESPModule:Refresh()
end, true):SetTooltip("Display player names above their heads")

-- Show Health Toggle
SectionESP:CreateToggle("Show Health", function(Value)
    Settings.ESP.ShowHealth = Value
    ESPModule:Refresh()
end, true):SetTooltip("Display player health with color coding (Green >50%, Yellow >25%, Red <25%)")

-- Hitbox Tab Section
local SectionHitbox = TabHitbox:CreateSection("Hitbox Expander")

-- Hitbox Toggle
Components.HitboxToggle = SectionHitbox:CreateToggle("Enable Hitbox", function(Value)
    Settings.Hitbox.Enabled = Value
    if Value then 
        HitboxModule:Start()
        Components.HitboxToggle:OnEnable(function()
            Library:Notification({
                Title = "Hitbox",
                Text = "Enabled - Enemy hitboxes are now expanded for easier targeting",
                Duration = 3,
                Type = "Success"
            })
        end)
    else 
        HitboxModule:Stop()
        Components.HitboxToggle:OnDisable(function()
            Library:Notification({
                Title = "Hitbox",
                Text = "Disabled - Hitboxes returned to normal size",
                Duration = 2,
                Type = "Info"
            })
        end)
    end
end, false)
Components.HitboxToggle:SetTooltip("Expand enemy hitboxes to make them easier to hit")

-- Hitbox Size Slider
SectionHitbox:CreateSlider(
    "Hitbox Size",
    5,
    30,
    15,
    function(Value)
        Settings.Hitbox.Size = Value
    end
):SetTooltip("Adjust the size of expanded hitboxes (5-30)")

-- Settings Tab Sections
local SectionControls = TabSettings:CreateSection("Controls")
local SectionInfo = TabSettings:CreateSection("Information")

-- Disable All Button
SectionControls:CreateButton("Disable All Features", function()
    Settings.Hitbox.Enabled = false
    Settings.Fly.Enabled = false
    Settings.Noclip.Enabled = false
    Settings.EnergyOrb.AutoCollect = false
    Settings.ESP.Enabled = false
    Settings.InfRange.Enabled = false
    
    HitboxModule:Stop()
    FlyModule:Stop()
    NoclipModule:Stop()
    EnergyOrbModule:StopAutoCollect()
    ESPModule:Stop()
    InfRangeModule:Stop()
    TeleportModule:RemoveTool()
    
    -- Update UI toggles
    if Components.FlyToggle then Components.FlyToggle:Set(false) end
    if Components.NoclipToggle then Components.NoclipToggle:Set(false) end
    if Components.InfRangeToggle then Components.InfRangeToggle:Set(false) end
    if Components.AutoCollect then Components.AutoCollect:Set(false) end
    if Components.ESPToggle then Components.ESPToggle:Set(false) end
    if Components.HitboxToggle then Components.HitboxToggle:Set(false) end
    
    Library:Notification({
        Title = "All Features Disabled",
        Text = "All cheat features have been turned off and cleaned up",
        Duration = 3,
        Type = "Warning"
    })
end):SetTooltip("Turn off all active features and clean up modifications")

-- Destroy GUI Button
SectionControls:CreateButton("Destroy GUI", function()
    Settings.Hitbox.Enabled = false
    Settings.Fly.Enabled = false
    Settings.Noclip.Enabled = false
    Settings.EnergyOrb.AutoCollect = false
    Settings.ESP.Enabled = false
    Settings.InfRange.Enabled = false
    
    HitboxModule:Stop()
    FlyModule:Stop()
    NoclipModule:Stop()
    EnergyOrbModule:StopAutoCollect()
    ESPModule:Stop()
    InfRangeModule:Stop()
    TeleportModule:RemoveTool()
    
    -- Disconnect all connections
    for key, conn in pairs(Connections) do
        if typeof(conn) == "RBXScriptConnection" then
            pcall(function() conn:Disconnect() end)
        elseif typeof(conn) == "table" then
            for _, c in ipairs(conn) do
                pcall(function() c:Disconnect() end)
            end
        end
    end
    
    Library:Notification({
        Title = "Goodbye!",
        Text = "ManoGustavo Hub has been safely destroyed",
        Duration = 2,
        Type = "Info"
    })
    
    task.wait(2)
    Window:Destroy()
end):SetTooltip("Completely remove the GUI and clean up all modifications")

-- Information Section with detailed explanations
SectionInfo:CreateLabel("🎮 KEYBINDS (Toggle Features):")
SectionInfo:CreateLabel("F = Toggle Fly")
SectionInfo:CreateLabel("N = Toggle Noclip")
SectionInfo:CreateLabel("G = Collect All Orbs (Instant)")
SectionInfo:CreateLabel("R = Toggle Infinite Range")
SectionInfo:CreateLabel(" ")
SectionInfo:CreateLabel("⚡ INFINITE RANGE EXPLANATION:")
SectionInfo:CreateLabel("When enabled, click ANY object to select it!")
SectionInfo:CreateLabel("System automatically handles the two-click process:")
SectionInfo:CreateLabel("1. Teleports you near object")
SectionInfo:CreateLabel("2. Selects object automatically")
SectionInfo:CreateLabel("3. Returns you to original position")
SectionInfo:CreateLabel(" ")
SectionInfo:CreateLabel("🔧 CREDITS:")
SectionInfo:CreateLabel("Made with Mano Gustavo UI Library")
SectionInfo:CreateLabel("Psychic Playground Cheat Menu")
SectionInfo:CreateLabel("Version 1.0")

-- ============================================
-- EVENT HANDLERS AND CLEANUP
-- ============================================

-- Clean up when players leave the game
Players.PlayerRemoving:Connect(function(player)
    HitboxModule:Reset(player)
    ESPModule:RemoveESP(player)
end)

-- ============================================
-- KEYBIND SYSTEM
-- ============================================
-- Quick keyboard shortcuts for toggling features
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    local keyCode = input.KeyCode
    local now = tick()
    
    -- Debounce to prevent rapid toggling
    if lastKeyPress[keyCode] and now - lastKeyPress[keyCode] < 0.5 then
        return
    end
    
    lastKeyPress[keyCode] = now
    
    if keyCode == Enum.KeyCode.F then
        Settings.Fly.Enabled = not Settings.Fly.Enabled
        if Settings.Fly.Enabled then 
            FlyModule:Start()
        else 
            FlyModule:Stop()
        end
        if Components.FlyToggle then 
            Components.FlyToggle:Set(Settings.Fly.Enabled)
        end
        
    elseif keyCode == Enum.KeyCode.N then
        Settings.Noclip.Enabled = not Settings.Noclip.Enabled
        if Components.NoclipToggle then 
            Components.NoclipToggle:Set(Settings.Noclip.Enabled)
        end
        
    elseif keyCode == Enum.KeyCode.G then
        local count = EnergyOrbModule:TeleportOrbs()
        Library:Notification({
            Title = "Instant Orb Collection",
            Text = "Successfully collected " .. count .. " energy orbs!",
            Duration = 3,
            Type = count > 0 and "Success" or "Info"
        })
        
    elseif keyCode == Enum.KeyCode.R then
        Settings.InfRange.Enabled = not Settings.InfRange.Enabled
        if Components.InfRangeToggle then 
            Components.InfRangeToggle:Set(Settings.InfRange.Enabled)
        end
    end
end)

-- ============================================
-- INITIALIZATION NOTIFICATION
-- ============================================
Library:Notification({
    Title = "ManoGustavo Hub - Psychic Playground",
    Text = "Successfully loaded!\n\n🔹 Press RightControl to toggle menu\n🔹 Use F/N/G/R for quick keybinds\n🔹 Check Settings tab for detailed explanations\n\nHappy cheating! 😊",
    Duration = 6,
    Type = "Success"
})