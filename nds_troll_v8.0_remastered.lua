--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║              NDS TROLL HUB v8.0 - REMASTERED 2026                      ║
    ║                Natural Disaster Survival                                ║
    ║          Compatível com Delta Executor & Mobile                         ║
    ║                                                                         ║
    ║   CHANGELOG v8.0:                                                       ║
    ║   - SimRadius: loop agressivo com múltiplos métodos de set              ║
    ║   - Network Ownership: reclama parts via touching + proximity           ║
    ║   - R15 Full Support (UpperTorso, HumanoidRootPart)                    ║
    ║   - Accessory-based fling (usa seus próprios hats como projéteis)      ║
    ║   - Anti-idle: mantém personagem ativo para não perder ownership       ║
    ║   - Fling por colisão física (não depende de CFrame replication)       ║
    ║   - Performance otimizada com cache e throttle                          ║
    ║   - GUI redesenhada, draggable, mobile-friendly                        ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ═══════════════════════════════════════
-- CONFIGURAÇÃO
-- ═══════════════════════════════════════
local Config = {
    OrbitRadius = 20,
    OrbitSpeed = 2.5,
    OrbitHeight = 5,
    SpinRadius = 12,
    SpinSpeed = 4,
    FlySpeed = 60,
    SpeedMultiplier = 3,
    FlingVelocity = 9e4,
    
    -- INTERVALS
    SimRadiusInterval = 0.1,      -- Agressivo: a cada 0.1s
    PartScanInterval = 2,          -- Re-escaneia parts a cada 2s
    RecaptureInterval = 0.5,       -- Re-captura parts perdidas a cada 0.5s
    OwnershipTouchInterval = 0.3,  -- Toca parts para ganhar ownership
}

-- ═══════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════
local State = {
    SelectedPlayer = nil,
    Magnet = false,
    Orbit = false,
    Blackhole = false,
    Spin = false,
    Cage = false,
    PartRain = false,
    HatFling = false,
    AccessoryFling = false,
    SkyLift = false,
    ServerMagnet = false,
    Launch = false,
    GodMode = false,
    Fly = false,
    View = false,
    Noclip = false,
    Speed = false,
    ESP = false,
    AntiIdle = false,
}

local Connections = {}
local CreatedObjects = {}
local AnchorPart = nil
local MainAttachment = nil

-- ═══════════════════════════════════════
-- UTILIDADES BASE
-- ═══════════════════════════════════════
local function GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function GetHRP()
    local char = GetCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local char = GetCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- R15 SAFE: Pegar torso correto
local function GetTorso()
    local char = GetCharacter()
    if not char then return nil end
    return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end

local function Notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3
        })
    end)
end

local function ClearConnections(prefix)
    for name, conn in pairs(Connections) do
        if prefix then
            if string.find(name, prefix) then
                pcall(function() conn:Disconnect() end)
                Connections[name] = nil
            end
        else
            pcall(function() conn:Disconnect() end)
        end
    end
    if not prefix then Connections = {} end
end

local function ClearCreatedObjects()
    for _, obj in pairs(CreatedObjects) do
        pcall(function() obj:Destroy() end)
    end
    CreatedObjects = {}
end

local function DisableAllFunctions()
    for key, _ in pairs(State) do
        if key ~= "SelectedPlayer" then
            State[key] = false
        end
    end
    ClearConnections()
    ClearCreatedObjects()
    
    -- Limpar constraints que criamos
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function()
                for _, child in pairs(obj:GetChildren()) do
                    if child.Name:find("_NDS") then
                        child:Destroy()
                    end
                end
            end)
        end
    end
    
    local hrp = GetHRP()
    if hrp then
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

-- ═══════════════════════════════════════
-- SISTEMA DE REDE (SimulationRadius) - v8.0 AGRESSIVO
-- ═══════════════════════════════════════
local simRadiusThread = nil

local function SetupNetworkControl()
    -- Destruir anchor antigo
    if AnchorPart then pcall(function() AnchorPart:Destroy() end) end
    
    -- Anchor invisível para attachments
    AnchorPart = Instance.new("Part")
    AnchorPart.Name = "_NDSAnchor"
    AnchorPart.Size = Vector3.new(1, 1, 1)
    AnchorPart.Transparency = 1
    AnchorPart.CanCollide = false
    AnchorPart.CanQuery = false
    AnchorPart.CanTouch = false
    AnchorPart.Anchored = true
    AnchorPart.CFrame = CFrame.new(0, 10000, 0)
    AnchorPart.Parent = Workspace
    table.insert(CreatedObjects, AnchorPart)
    
    MainAttachment = Instance.new("Attachment")
    MainAttachment.Name = "_NDSMainAttach"
    MainAttachment.Parent = AnchorPart
    
    -- SIMRADIUS AGRESSIVO - Múltiplos métodos, loop rápido
    if simRadiusThread then
        pcall(function() task.cancel(simRadiusThread) end)
    end
    
    simRadiusThread = task.spawn(function()
        while true do
            pcall(function()
                -- Método 1: sethiddenproperty (Delta suporta)
                if sethiddenproperty then
                    sethiddenproperty(LocalPlayer, "SimulationRadius", 1e6)
                    sethiddenproperty(LocalPlayer, "MaxSimulationRadius", 1e6)
                end
            end)
            pcall(function()
                -- Método 2: setsimulationradius (alguns executors)
                if setsimulationradius then
                    setsimulationradius(1e6, 1e6)
                end
            end)
            pcall(function()
                -- Método 3: Direto (pode funcionar em alguns executors)
                LocalPlayer.SimulationRadius = 1e6
            end)
            pcall(function()
                -- Método 4: MaxSimulationRadius separado
                if sethiddenproperty then
                    sethiddenproperty(LocalPlayer, "MaxSimulationRadius", math.huge)
                end
            end)
            task.wait(Config.SimRadiusInterval)
        end
    end)
end

-- ═══════════════════════════════════════
-- SISTEMA DE PARTES - v8.0
-- ═══════════════════════════════════════

-- Cache de partes para performance
local partsCache = {}
local lastPartsScan = 0

local function IsPlayerPart(part)
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            return true
        end
    end
    return false
end

local function GetUnanchoredParts(forceRescan)
    local now = tick()
    if not forceRescan and (now - lastPartsScan) < Config.PartScanInterval and #partsCache > 0 then
        -- Validar cache (remover parts destruídas)
        local valid = {}
        for _, part in ipairs(partsCache) do
            if part and part.Parent and not part.Anchored then
                table.insert(valid, part)
            end
        end
        partsCache = valid
        return partsCache
    end
    
    lastPartsScan = now
    partsCache = {}
    
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj.Anchored then
            if not obj.Name:find("_NDS") 
               and obj.Name ~= "Terrain" 
               and not IsPlayerPart(obj) then
                table.insert(partsCache, obj)
            end
        end
    end
    
    return partsCache
end

local function GetMyAccessories()
    local handles = {}
    local char = GetCharacter()
    if char then
        for _, acc in pairs(char:GetChildren()) do
            if acc:IsA("Accessory") then
                local handle = acc:FindFirstChild("Handle")
                if handle then
                    table.insert(handles, handle)
                end
            end
        end
    end
    return handles
end

local function GetAvailableParts()
    local parts = GetUnanchoredParts(false)
    if #parts < 3 then
        -- Fallback: usar acessórios próprios
        local handles = GetMyAccessories()
        for _, h in pairs(handles) do
            table.insert(parts, h)
        end
    end
    return parts
end

-- ═══════════════════════════════════════
-- CONTROLE DE PARTES v8.0
-- Agora com anti-competição e ownership touch
-- ═══════════════════════════════════════

local function CleanForeignConstraints(part)
    pcall(function()
        for _, child in pairs(part:GetChildren()) do
            if (child:IsA("AlignPosition") or child:IsA("AlignOrientation") or
                child:IsA("BodyPosition") or child:IsA("BodyVelocity") or
                child:IsA("BodyForce") or child:IsA("BodyGyro") or
                child:IsA("VectorForce") or child:IsA("LineForce") or
                child:IsA("BodyAngularVelocity") or child:IsA("BodyThrust") or
                child:IsA("RocketPropulsion") or child:IsA("Torque"))
                and not child.Name:find("_NDS") then
                child:Destroy()
            end
        end
    end)
end

local function SetupPartControl(part, targetAttachment, responsiveness)
    if not part or not part:IsA("BasePart") then return nil, nil end
    if part.Anchored then return nil, nil end
    if part.Name:find("_NDS") then return nil, nil end
    
    -- Não controlar partes de outros jogadores (exceto nosso char)
    if IsPlayerPart(part) then return nil, nil end
    
    pcall(function()
        -- Limpar constraints antigos (nossos e de outros)
        local oldAlign = part:FindFirstChild("_NDSAlign")
        local oldAttach = part:FindFirstChild("_NDSAttach")
        if oldAlign then oldAlign:Destroy() end
        if oldAttach then oldAttach:Destroy() end
        
        -- Limpar constraints de outros scripts
        CleanForeignConstraints(part)
    end)
    
    -- Preparar parte
    pcall(function()
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
    end)
    
    -- Criar attachment + align
    local attach = Instance.new("Attachment")
    attach.Name = "_NDSAttach"
    attach.Parent = part
    
    local align = Instance.new("AlignPosition")
    align.Name = "_NDSAlign"
    align.MaxForce = math.huge
    align.MaxVelocity = math.huge
    align.Responsiveness = responsiveness or 200
    align.Attachment0 = attach
    align.Attachment1 = targetAttachment or MainAttachment
    align.Parent = part
    
    return attach, align
end

local function CleanPartControl(part)
    if not part then return end
    pcall(function()
        for _, child in pairs(part:GetChildren()) do
            if child.Name:find("_NDS") then
                child:Destroy()
            end
        end
        part.CanCollide = true
    end)
end

-- Tenta "tocar" part se movendo perto dela para ganhar ownership
local function TouchPartForOwnership(part)
    local hrp = GetHRP()
    if not hrp or not part or not part.Parent then return end
    pcall(function()
        -- Mover temporariamente o CFrame do nosso HRP perto da part
        -- e voltar — isso pode re-triggerar ownership
        local originalCF = hrp.CFrame
        hrp.CFrame = part.CFrame * CFrame.new(0, 2, 0)
        task.wait()
        hrp.CFrame = originalCF
    end)
end

-- ═══════════════════════════════════════
-- ANTI-IDLE (mantém personagem ativo)
-- ═══════════════════════════════════════
local function ToggleAntiIdle()
    State.AntiIdle = not State.AntiIdle
    
    if State.AntiIdle then
        -- Previne AFK kick
        Connections.AntiIdle = task.spawn(function()
            local VirtualUser = game:GetService("VirtualUser")
            while State.AntiIdle do
                pcall(function()
                    VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
                    task.wait(0.1)
                    VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
                end)
                -- Pequeno movimento para manter ownership
                pcall(function()
                    local hrp = GetHRP()
                    if hrp then
                        hrp.AssemblyLinearVelocity = Vector3.new(
                            math.random(-1, 1) * 0.01,
                            0,
                            math.random(-1, 1) * 0.01
                        )
                    end
                end)
                task.wait(30)
            end
        end)
        return true, "Anti-Idle ativado!"
    else
        return false, "Anti-Idle desativado"
    end
end

-- ═══════════════════════════════════════
-- FUNÇÕES DE TROLAGEM v8.0
-- ═══════════════════════════════════════

-- ═══ MAGNET (Ímã de Objetos) ═══
local function ToggleMagnet()
    State.Magnet = not State.Magnet
    
    if State.Magnet then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Magnet = false
            return false, "Selecione um player!"
        end
        
        local controlledParts = {}
        
        -- Função para capturar uma part
        local function CapturePart(part)
            if controlledParts[part] then return end
            if not part or not part:IsA("BasePart") or part.Anchored then return end
            if part.Name:find("_NDS") or IsPlayerPart(part) then return end
            
            SetupPartControl(part, MainAttachment, 200)
            controlledParts[part] = true
        end
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            CapturePart(part)
        end
        
        -- Captura de novas partes (desastres criam novas)
        Connections.MagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Magnet and obj:IsA("BasePart") and not obj.Anchored then
                task.defer(function()
                    task.wait(0.1) -- Pequeno delay para part estabilizar
                    CapturePart(obj)
                end)
            end
        end)
        
        -- Detectar parts que ficam unanchored (desastres desanchoram prédios)
        Connections.MagnetUnanchor = Workspace.DescendantAdded:Connect(function(obj)
            if State.Magnet and obj:IsA("BasePart") then
                obj:GetPropertyChangedSignal("Anchored"):Connect(function()
                    if not obj.Anchored and State.Magnet then
                        task.defer(function() CapturePart(obj) end)
                    end
                end)
            end
        end)
        
        -- Update: mover anchor para posição do alvo
        Connections.MagnetUpdate = RunService.Heartbeat:Connect(function()
            if State.Magnet and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    AnchorPart.CFrame = hrp.CFrame
                end
            end
        end)
        
        -- Re-captura periódica (parts que perderam controle)
        task.spawn(function()
            while State.Magnet do
                task.wait(Config.RecaptureInterval)
                if not State.Magnet then break end
                
                -- Re-capturar parts que perderam align
                for part, _ in pairs(controlledParts) do
                    if part and part.Parent then
                        local align = part:FindFirstChild("_NDSAlign")
                        if not align then
                            CleanForeignConstraints(part)
                            SetupPartControl(part, MainAttachment, 200)
                        end
                    else
                        controlledParts[part] = nil
                    end
                end
                
                -- Escanear novas parts a cada ciclo
                for _, part in pairs(GetUnanchoredParts(true)) do
                    CapturePart(part)
                end
            end
        end)
        
        return true, "Ímã ativado!"
    else
        ClearConnections("Magnet")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then
                CleanPartControl(part)
            end
        end
        partsCache = {}
        return false, "Ímã desativado"
    end
end

-- ═══ ORBIT ATTACK ═══
local function ToggleOrbit()
    State.Orbit = not State.Orbit
    
    if State.Orbit then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Orbit = false
            return false, "Selecione um player!"
        end
        
        local angle = 0
        local parts = GetAvailableParts()
        local partData = {}
        
        for i, part in pairs(parts) do
            pcall(function()
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
            end)
            
            local att = Instance.new("Attachment")
            att.Name = "_NDSOrbitAtt" .. i
            att.Parent = AnchorPart
            table.insert(CreatedObjects, att)
            
            SetupPartControl(part, att, 400)
            partData[i] = {
                part = part, 
                attachment = att, 
                baseAngle = (i / #parts) * math.pi * 2
            }
        end
        
        Connections.OrbitUpdate = RunService.Heartbeat:Connect(function(dt)
            angle = angle + dt * Config.OrbitSpeed
            
            if State.Orbit and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local hrpPos = hrp.Position
                    for _, data in pairs(partData) do
                        if data.part and data.part.Parent and data.attachment then
                            local currentAngle = data.baseAngle + angle
                            local offset = Vector3.new(
                                math.cos(currentAngle) * Config.OrbitRadius,
                                Config.OrbitHeight + math.sin(currentAngle * 2) * 3,
                                math.sin(currentAngle) * Config.OrbitRadius
                            )
                            data.attachment.WorldPosition = hrpPos + offset
                        end
                    end
                end
            end
        end)
        
        -- Re-captura competitiva
        task.spawn(function()
            while State.Orbit do
                task.wait(Config.RecaptureInterval)
                if not State.Orbit then break end
                for _, data in pairs(partData) do
                    if data.part and data.part.Parent then
                        local align = data.part:FindFirstChild("_NDSAlign")
                        if not align then
                            CleanForeignConstraints(data.part)
                            SetupPartControl(data.part, data.attachment, 400)
                        end
                    end
                end
            end
        end)
        
        return true, "Orbit ativado!"
    else
        ClearConnections("Orbit")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then
                CleanPartControl(part)
            end
        end
        return false, "Orbit desativado"
    end
end

-- ═══ BLACKHOLE ═══
local function ToggleBlackhole()
    State.Blackhole = not State.Blackhole
    
    if State.Blackhole then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Blackhole = false
            return false, "Selecione um player!"
        end
        
        local angle = 0
        local parts = GetAvailableParts()
        
        for _, part in pairs(parts) do
            pcall(function()
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
            end)
            SetupPartControl(part, MainAttachment, 300)
            
            -- Torque para efeito visual
            local torque = Instance.new("Torque")
            torque.Name = "_NDSTorque"
            torque.Torque = Vector3.new(50000, 50000, 50000)
            local att = part:FindFirstChild("_NDSAttach")
            if att then torque.Attachment0 = att end
            torque.Parent = part
        end
        
        Connections.BlackholeUpdate = RunService.Heartbeat:Connect(function(dt)
            angle = angle + dt * 5
            if State.Blackhole and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    local spiral = Vector3.new(
                        math.cos(angle) * 2, 
                        math.sin(angle * 2), 
                        math.sin(angle) * 2
                    )
                    AnchorPart.CFrame = CFrame.new(hrp.Position + spiral)
                end
            end
        end)
        
        -- Re-captura
        task.spawn(function()
            while State.Blackhole do
                task.wait(1)
                if not State.Blackhole then break end
                for _, part in pairs(GetUnanchoredParts(true)) do
                    if not part:FindFirstChild("_NDSAlign") then
                        SetupPartControl(part, MainAttachment, 300)
                    end
                end
            end
        end)
        
        return true, "Blackhole ativado!"
    else
        ClearConnections("Blackhole")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then
                CleanPartControl(part)
            end
        end
        return false, "Blackhole desativado"
    end
end

-- ═══ SPIN ═══
local function ToggleSpin()
    State.Spin = not State.Spin
    
    if State.Spin then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Spin = false
            return false, "Selecione um player!"
        end
        
        local angle = 0
        local parts = GetAvailableParts()
        local partData = {}
        
        for i, part in pairs(parts) do
            pcall(function()
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
            end)
            
            local att = Instance.new("Attachment")
            att.Name = "_NDSSpinAtt" .. i
            att.Parent = AnchorPart
            table.insert(CreatedObjects, att)
            
            SetupPartControl(part, att, 300)
            partData[i] = {
                part = part, 
                attachment = att, 
                baseAngle = (i / #parts) * math.pi * 2
            }
        end
        
        Connections.SpinUpdate = RunService.Heartbeat:Connect(function(dt)
            angle = angle + dt * Config.SpinSpeed
            if State.Spin and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local hrpPos = hrp.Position
                    for _, data in pairs(partData) do
                        if data.part and data.part.Parent and data.attachment then
                            local currentAngle = data.baseAngle + angle
                            local offset = Vector3.new(
                                math.cos(currentAngle) * Config.SpinRadius,
                                1,
                                math.sin(currentAngle) * Config.SpinRadius
                            )
                            data.attachment.WorldPosition = hrpPos + offset
                        end
                    end
                end
            end
        end)
        
        return true, "Spin ativado!"
    else
        ClearConnections("Spin")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then CleanPartControl(part) end
        end
        return false, "Spin desativado"
    end
end

-- ═══ CAGE ═══
local function ToggleCage()
    State.Cage = not State.Cage
    
    if State.Cage then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Cage = false
            return false, "Selecione um player!"
        end
        
        local parts = GetAvailableParts()
        local partData = {}
        local cageRadius = 4
        
        for i, part in pairs(parts) do
            if i > 24 then break end
            
            local att = Instance.new("Attachment")
            att.Name = "_NDSCageAtt" .. i
            att.Parent = AnchorPart
            table.insert(CreatedObjects, att)
            
            SetupPartControl(part, att, 300)
            
            local layer = math.floor((i - 1) / 8)
            local indexInLayer = (i - 1) % 8
            local angle = (indexInLayer / 8) * math.pi * 2
            
            partData[i] = {
                part = part,
                attachment = att,
                angle = angle,
                height = (layer - 1) * 3
            }
        end
        
        Connections.CageUpdate = RunService.Heartbeat:Connect(function()
            if State.Cage and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for _, data in pairs(partData) do
                        if data.attachment then
                            local offset = Vector3.new(
                                math.cos(data.angle) * cageRadius,
                                data.height,
                                math.sin(data.angle) * cageRadius
                            )
                            data.attachment.WorldPosition = hrp.Position + offset
                        end
                    end
                end
            end
        end)
        
        return true, "Cage ativado!"
    else
        ClearConnections("Cage")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then CleanPartControl(part) end
        end
        return false, "Cage desativado"
    end
end

-- ═══ PART RAIN ═══
local function TogglePartRain()
    State.PartRain = not State.PartRain
    
    if State.PartRain then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.PartRain = false
            return false, "Selecione um player!"
        end
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment, 200)
        end
        
        Connections.PartRainUpdate = RunService.Heartbeat:Connect(function()
            if State.PartRain and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    local offset = Vector3.new(
                        math.random(-15, 15), 
                        50, 
                        math.random(-15, 15)
                    )
                    AnchorPart.CFrame = CFrame.new(hrp.Position + offset)
                end
            end
        end)
        
        -- Re-captura
        task.spawn(function()
            while State.PartRain do
                task.wait(1)
                if not State.PartRain then break end
                for _, part in pairs(GetUnanchoredParts(true)) do
                    if not part:FindFirstChild("_NDSAlign") then
                        SetupPartControl(part, MainAttachment, 200)
                    end
                end
            end
        end)
        
        return true, "Part Rain ativado!"
    else
        ClearConnections("PartRain")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then CleanPartControl(part) end
        end
        return false, "Part Rain desativado"
    end
end

-- ═══ ACCESSORY FLING (v8.0 - usa SEUS acessórios como projéteis) ═══
-- Funciona porque você TEM network ownership dos seus próprios acessórios
local function ToggleAccessoryFling()
    State.AccessoryFling = not State.AccessoryFling
    
    if State.AccessoryFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.AccessoryFling = false
            return false, "Selecione um player!"
        end
        
        local angle = 0
        
        Connections.AccFlingUpdate = RunService.Heartbeat:Connect(function(dt)
            if State.AccessoryFling and State.SelectedPlayer and State.SelectedPlayer.Character then
                local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myChar = GetCharacter()
                local myHRP = GetHRP()
                if tHRP and myHRP and myChar then
                    angle = angle + dt * 25
                    
                    -- Mover nosso personagem perto do alvo com velocidade alta
                    local offset = Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3)
                    myHRP.CFrame = CFrame.new(tHRP.Position + offset)
                    
                    -- Velocidade alta nos nossos acessórios para fling
                    for _, acc in pairs(myChar:GetChildren()) do
                        if acc:IsA("Accessory") then
                            local handle = acc:FindFirstChild("Handle")
                            if handle then
                                pcall(function()
                                    handle.AssemblyLinearVelocity = Vector3.new(
                                        Config.FlingVelocity, 
                                        Config.FlingVelocity, 
                                        Config.FlingVelocity
                                    )
                                    handle.AssemblyAngularVelocity = Vector3.new(
                                        Config.FlingVelocity, 
                                        Config.FlingVelocity, 
                                        Config.FlingVelocity
                                    )
                                end)
                            end
                        end
                    end
                    
                    -- Velocidade no nosso HRP também
                    pcall(function()
                        myHRP.AssemblyLinearVelocity = Vector3.new(
                            Config.FlingVelocity * 0.1, 
                            Config.FlingVelocity * 0.1, 
                            Config.FlingVelocity * 0.1
                        )
                        myHRP.AssemblyAngularVelocity = Vector3.new(
                            Config.FlingVelocity, 
                            Config.FlingVelocity, 
                            Config.FlingVelocity
                        )
                    end)
                end
            end
        end)
        
        return true, "Accessory Fling ativado!"
    else
        ClearConnections("AccFling")
        local hrp = GetHRP()
        if hrp then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
        return false, "Accessory Fling desativado"
    end
end

-- ═══ HAT FLING (clássico) ═══
local function ToggleHatFling()
    State.HatFling = not State.HatFling
    
    if State.HatFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.HatFling = false
            return false, "Selecione um player!"
        end
        
        local angle = 0
        
        Connections.HatFlingUpdate = RunService.Heartbeat:Connect(function(dt)
            if State.HatFling and State.SelectedPlayer and State.SelectedPlayer.Character then
                local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myHRP = GetHRP()
                if tHRP and myHRP then
                    angle = angle + dt * 30
                    local offset = Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3)
                    myHRP.CFrame = CFrame.new(tHRP.Position + offset)
                    myHRP.AssemblyLinearVelocity = Vector3.new(9e5, 9e5, 9e5)
                    myHRP.AssemblyAngularVelocity = Vector3.new(9e5, 9e5, 9e5)
                end
            end
        end)
        
        return true, "Hat Fling ativado!"
    else
        ClearConnections("HatFling")
        local hrp = GetHRP()
        if hrp then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
        return false, "Hat Fling desativado"
    end
end

-- ═══ SKY LIFT ═══
local function ToggleSkyLift()
    State.SkyLift = not State.SkyLift
    
    if State.SkyLift then
        local parts = GetAvailableParts()
        local skyParts = {}
        
        for _, part in pairs(parts) do
            pcall(function()
                CleanForeignConstraints(part)
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 0, 0)
                
                local bf = Instance.new("BodyForce")
                bf.Name = "_NDSSkyForce"
                bf.Force = Vector3.new(0, part:GetMass() * 5000, 0)
                bf.Parent = part
                table.insert(CreatedObjects, bf)
                
                part.AssemblyLinearVelocity = Vector3.new(0, 500, 0)
                table.insert(skyParts, part)
            end)
        end
        
        -- Proteção
        task.spawn(function()
            while State.SkyLift do
                task.wait(0.2)
                if not State.SkyLift then break end
                for _, part in pairs(skyParts) do
                    if part and part.Parent then
                        pcall(function()
                            if not part:FindFirstChild("_NDSSkyForce") then
                                CleanForeignConstraints(part)
                                local bf = Instance.new("BodyForce")
                                bf.Name = "_NDSSkyForce"
                                bf.Force = Vector3.new(0, part:GetMass() * 5000, 0)
                                bf.Parent = part
                            end
                            if part.Position.Y < 3000 then
                                part.AssemblyLinearVelocity = Vector3.new(0, 500, 0)
                            end
                        end)
                    end
                end
            end
        end)
        
        return true, "Sky Lift ativado!"
    else
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then
                local sf = part:FindFirstChild("_NDSSkyForce")
                if sf then pcall(function() sf:Destroy() end) end
            end
        end
        return false, "Sky Lift desativado"
    end
end

-- ═══ SERVER MAGNET (ataca todos os players) ═══
local function ToggleServerMagnet()
    State.ServerMagnet = not State.ServerMagnet
    
    if State.ServerMagnet then
        local playerAttachments = {}
        local controlledParts = {}
        
        local function GetTargetPlayers()
            local targets = {}
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        table.insert(targets, player)
                    end
                end
            end
            return targets
        end
        
        local function SetupPlayerAttachments()
            for _, att in pairs(playerAttachments) do
                if att and att.Parent then
                    pcall(function() att:Destroy() end)
                end
            end
            playerAttachments = {}
            
            local targets = GetTargetPlayers()
            for i, player in pairs(targets) do
                local att = Instance.new("Attachment")
                att.Name = "_NDSServerAtt" .. i
                att.Parent = AnchorPart
                table.insert(CreatedObjects, att)
                playerAttachments[player] = att
            end
            return targets
        end
        
        local function DistributeParts()
            local targets = GetTargetPlayers()
            if #targets == 0 then return end
            SetupPlayerAttachments()
            
            local parts = GetAvailableParts()
            local playerIndex = 1
            
            for _, part in pairs(parts) do
                if not controlledParts[part] then
                    local targetPlayer = targets[playerIndex]
                    local targetAtt = playerAttachments[targetPlayer]
                    if targetAtt then
                        SetupPartControl(part, targetAtt, 300)
                        controlledParts[part] = targetPlayer
                    end
                    playerIndex = (playerIndex % #targets) + 1
                end
            end
        end
        
        DistributeParts()
        
        -- Captura de novas partes
        Connections.ServerMagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.ServerMagnet and obj:IsA("BasePart") and not obj.Anchored then
                task.defer(function()
                    if not controlledParts[obj] then
                        local targets = GetTargetPlayers()
                        if #targets > 0 then
                            local minPlayer = targets[1]
                            local targetAtt = playerAttachments[minPlayer]
                            if targetAtt then
                                SetupPartControl(obj, targetAtt, 300)
                                controlledParts[obj] = minPlayer
                            end
                        end
                    end
                end)
            end
        end)
        
        -- Atualiza posição dos attachments
        Connections.ServerMagnetUpdate = RunService.Heartbeat:Connect(function()
            if State.ServerMagnet then
                for player, att in pairs(playerAttachments) do
                    if player and player.Character and att and att.Parent then
                        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            att.WorldPosition = hrp.Position
                        end
                    end
                end
            end
        end)
        
        -- Re-distribuição periódica
        task.spawn(function()
            while State.ServerMagnet do
                task.wait(2)
                if not State.ServerMagnet then break end
                
                -- Verificar se precisa redistribuir
                local needsRedist = false
                for player, _ in pairs(playerAttachments) do
                    if not player or not player.Parent or not player.Character then
                        needsRedist = true
                        break
                    end
                end
                
                if needsRedist then
                    controlledParts = {}
                    DistributeParts()
                else
                    for part, player in pairs(controlledParts) do
                        if part and part.Parent then
                            if not part:FindFirstChild("_NDSAlign") then
                                local targetAtt = playerAttachments[player]
                                if targetAtt then
                                    SetupPartControl(part, targetAtt, 300)
                                end
                            end
                        else
                            controlledParts[part] = nil
                        end
                    end
                end
            end
        end)
        
        local targetCount = #GetTargetPlayers()
        return true, "Server Magnet! (" .. targetCount .. " alvos)"
    else
        ClearConnections("ServerMagnet")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function()
                    local a = part:FindFirstChild("_NDSAlign")
                    local b = part:FindFirstChild("_NDSAttach")
                    if a then a:Destroy() end
                    if b then b:Destroy() end
                end)
            end
        end
        return false, "Server Magnet desativado"
    end
end

-- ═══ LAUNCH ═══
local function ToggleLaunch()
    State.Launch = not State.Launch
    
    if State.Launch then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Launch = false
            return false, "Selecione um player!"
        end
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment, 200)
        end
        
        Connections.LaunchUpdate = RunService.Heartbeat:Connect(function()
            if State.Launch and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    AnchorPart.CFrame = CFrame.new(hrp.Position + Vector3.new(0, -3, 0))
                end
            end
        end)
        
        return true, "Launch ativado!"
    else
        ClearConnections("Launch")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then CleanPartControl(part) end
        end
        return false, "Launch desativado"
    end
end

-- ═══════════════════════════════════════
-- UTILIDADES
-- ═══════════════════════════════════════

-- GOD MODE
local function ToggleGodMode()
    State.GodMode = not State.GodMode
    
    if State.GodMode then
        local char = GetCharacter()
        local humanoid = GetHumanoid()
        if not char or not humanoid then
            State.GodMode = false
            return false, "Erro!"
        end
        
        -- ForceField invisível
        local ff = Instance.new("ForceField")
        ff.Name = "_NDSForceField"
        ff.Visible = false
        ff.Parent = char
        table.insert(CreatedObjects, ff)
        
        -- Loop de proteção
        Connections.GodMode = RunService.Heartbeat:Connect(function()
            if State.GodMode then
                local h = GetHumanoid()
                if h then h.Health = h.MaxHealth end
                local c = GetCharacter()
                if c and not c:FindFirstChild("_NDSForceField") then
                    local newFF = Instance.new("ForceField")
                    newFF.Name = "_NDSForceField"
                    newFF.Visible = false
                    newFF.Parent = c
                end
            end
        end)
        
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        end)
        
        return true, "God Mode ativado!"
    else
        ClearConnections("GodMode")
        local char = GetCharacter()
        if char then
            local ff = char:FindFirstChild("_NDSForceField")
            if ff then ff:Destroy() end
        end
        pcall(function()
            GetHumanoid():SetStateEnabled(Enum.HumanoidStateType.Dead, true)
        end)
        return false, "God Mode desativado"
    end
end

-- FLY v8.0 (R15 compatible)
local flyData = { active = false, bg = nil, bv = nil, speed = 1, ctrl = {f=0,b=0,l=0,r=0} }

local function ToggleFly()
    State.Fly = not State.Fly
    flyData.active = State.Fly
    
    if State.Fly then
        local char = GetCharacter()
        local humanoid = GetHumanoid()
        local torso = GetTorso() -- R15 safe
        
        if not char or not humanoid or not torso then
            State.Fly = false
            flyData.active = false
            return false, "Erro!"
        end
        
        -- Desabilitar animações
        local animate = char:FindFirstChild("Animate")
        if animate then animate.Disabled = true end
        for _, v in pairs(humanoid:GetPlayingAnimationTracks()) do
            v:AdjustSpeed(0)
        end
        
        -- BodyGyro + BodyVelocity
        flyData.bg = Instance.new("BodyGyro", torso)
        flyData.bg.P = 9e4
        flyData.bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyData.bg.CFrame = torso.CFrame
        
        flyData.bv = Instance.new("BodyVelocity", torso)
        flyData.bv.Velocity = Vector3.new(0, 0.1, 0)
        flyData.bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        
        humanoid.PlatformStand = true
        flyData.ctrl = {f=0,b=0,l=0,r=0}
        
        -- Key handlers
        Connections.FlyKeyDown = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.W then flyData.ctrl.f = 1 end
            if input.KeyCode == Enum.KeyCode.S then flyData.ctrl.b = -1 end
            if input.KeyCode == Enum.KeyCode.A then flyData.ctrl.l = -1 end
            if input.KeyCode == Enum.KeyCode.D then flyData.ctrl.r = 1 end
        end)
        
        Connections.FlyKeyUp = UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.W then flyData.ctrl.f = 0 end
            if input.KeyCode == Enum.KeyCode.S then flyData.ctrl.b = 0 end
            if input.KeyCode == Enum.KeyCode.A then flyData.ctrl.l = 0 end
            if input.KeyCode == Enum.KeyCode.D then flyData.ctrl.r = 0 end
        end)
        
        local maxspeed = Config.FlySpeed
        local speed = 0
        local lastctrl = {f=0,b=0,l=0,r=0}
        
        Connections.FlyLoop = RunService.RenderStepped:Connect(function()
            if not flyData.active or not flyData.bv or not flyData.bg then return end
            local h = GetHumanoid()
            if not h or h.Health == 0 then return end
            
            local c = flyData.ctrl
            if c.l + c.r ~= 0 or c.f + c.b ~= 0 then
                speed = math.min(speed + 0.5 + (speed / maxspeed), maxspeed)
            elseif speed > 0 then
                speed = math.max(speed - 1, 0)
            end
            
            local cam = Camera
            if (c.l + c.r) ~= 0 or (c.f + c.b) ~= 0 then
                flyData.bv.Velocity = (
                    (cam.CFrame.LookVector * (c.f + c.b)) + 
                    ((cam.CFrame * CFrame.new(c.l + c.r, (c.f + c.b) * 0.2, 0).Position) - cam.CFrame.Position)
                ) * speed
                lastctrl = {f = c.f, b = c.b, l = c.l, r = c.r}
            elseif speed > 0 then
                flyData.bv.Velocity = (
                    (cam.CFrame.LookVector * (lastctrl.f + lastctrl.b)) + 
                    ((cam.CFrame * CFrame.new(lastctrl.l + lastctrl.r, (lastctrl.f + lastctrl.b) * 0.2, 0).Position) - cam.CFrame.Position)
                ) * speed
            else
                flyData.bv.Velocity = Vector3.zero
            end
            
            flyData.bg.CFrame = cam.CFrame * CFrame.Angles(
                -math.rad((c.f + c.b) * 50 * speed / maxspeed), 0, 0
            )
        end)
        
        return true, "Fly ativado! (WASD)"
    else
        ClearConnections("Fly")
        if flyData.bg then pcall(function() flyData.bg:Destroy() end) end
        if flyData.bv then pcall(function() flyData.bv:Destroy() end) end
        flyData.bg = nil
        flyData.bv = nil
        
        local h = GetHumanoid()
        if h then h.PlatformStand = false end
        local char = GetCharacter()
        if char then
            local animate = char:FindFirstChild("Animate")
            if animate then animate.Disabled = false end
        end
        
        return false, "Fly desativado"
    end
end

-- VIEW PLAYER
local function ToggleView()
    State.View = not State.View
    
    if State.View then
        if not State.SelectedPlayer then
            State.View = false
            return false, "Selecione um player!"
        end
        
        local target = State.SelectedPlayer
        
        local function UpdateCamera()
            if not State.View or not target or not target.Parent then return end
            local tChar = target.Character
            if tChar then
                local tHum = tChar:FindFirstChildOfClass("Humanoid")
                if tHum then Camera.CameraSubject = tHum end
            end
        end
        
        UpdateCamera()
        
        Connections.ViewCharAdded = target.CharacterAdded:Connect(function()
            task.wait(0.2)
            UpdateCamera()
        end)
        
        Connections.ViewRemove = Players.PlayerRemoving:Connect(function(p)
            if p == target then
                State.View = false
                Camera.CameraSubject = GetHumanoid()
                ClearConnections("View")
            end
        end)
        
        task.spawn(function()
            while State.View do
                task.wait(1)
                UpdateCamera()
            end
        end)
        
        return true, "View: " .. target.Name
    else
        ClearConnections("View")
        Camera.CameraSubject = GetHumanoid()
        return false, "View desativado"
    end
end

-- NOCLIP
local function ToggleNoclip()
    State.Noclip = not State.Noclip
    
    if State.Noclip then
        Connections.NoclipUpdate = RunService.Stepped:Connect(function()
            if State.Noclip then
                local char = GetCharacter()
                if char then
                    for _, part in pairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end)
        return true, "Noclip ativado!"
    else
        ClearConnections("Noclip")
        return false, "Noclip desativado"
    end
end

-- SPEED
local originalSpeed = 16
local function ToggleSpeed()
    State.Speed = not State.Speed
    
    if State.Speed then
        local h = GetHumanoid()
        if h then
            originalSpeed = h.WalkSpeed
            h.WalkSpeed = originalSpeed * Config.SpeedMultiplier
        end
        
        Connections.SpeedUpdate = RunService.Heartbeat:Connect(function()
            if State.Speed then
                local hum = GetHumanoid()
                if hum and hum.WalkSpeed < originalSpeed * Config.SpeedMultiplier then
                    hum.WalkSpeed = originalSpeed * Config.SpeedMultiplier
                end
            end
        end)
        
        return true, "Speed 3x ativado!"
    else
        ClearConnections("Speed")
        local h = GetHumanoid()
        if h then h.WalkSpeed = originalSpeed end
        return false, "Speed desativado"
    end
end

-- ESP
local espObjects = {}
local function ToggleESP()
    State.ESP = not State.ESP
    
    if State.ESP then
        local function createESP(player)
            if player == LocalPlayer then return end
            if not player.Character then return end
            
            -- Remover ESP antigo
            if espObjects[player] then
                pcall(function() espObjects[player]:Destroy() end)
            end
            
            local highlight = Instance.new("Highlight")
            highlight.Name = "_NDSESP"
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Adornee = player.Character
            highlight.Parent = player.Character
            espObjects[player] = highlight
        end
        
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character then createESP(player) end
            Connections["ESPChar_" .. player.Name] = player.CharacterAdded:Connect(function()
                if State.ESP then
                    task.wait(0.5)
                    createESP(player)
                end
            end)
        end
        
        Connections.ESPPlayerAdded = Players.PlayerAdded:Connect(function(player)
            player.CharacterAdded:Connect(function()
                if State.ESP then
                    task.wait(0.5)
                    createESP(player)
                end
            end)
        end)
        
        return true, "ESP ativado!"
    else
        for _, h in pairs(espObjects) do
            pcall(function() h:Destroy() end)
        end
        espObjects = {}
        ClearConnections("ESP")
        return false, "ESP desativado"
    end
end

-- TELEPORT
local function TeleportToPlayer()
    if not State.SelectedPlayer or not State.SelectedPlayer.Character then
        return false, "Selecione um player!"
    end
    
    local hrp = GetHRP()
    local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
    
    if hrp and tHRP then
        hrp.CFrame = tHRP.CFrame * CFrame.new(0, 0, 3)
        return true, "Teleportado!"
    end
    return false, "Erro!"
end

-- ═══════════════════════════════════════
-- RECONEXÃO AO RESPAWN
-- ═══════════════════════════════════════
LocalPlayer.CharacterAdded:Connect(function()
    -- Desativar tudo ao morrer
    local wasGodMode = State.GodMode
    local wasESP = State.ESP
    DisableAllFunctions()
    
    task.wait(1)
    SetupNetworkControl()
    
    -- Re-ativar ESP se estava ligado
    if wasESP then
        State.ESP = false
        ToggleESP()
    end
end)

-- ═══════════════════════════════════════
-- INTERFACE v8.0 (COMPACTA, MOBILE-FRIENDLY)
-- ═══════════════════════════════════════
local function CreateUI()
    -- Limpar UI existente
    pcall(function() game:GetService("CoreGui"):FindFirstChild("NDSTrollHub"):Destroy() end)
    pcall(function() LocalPlayer.PlayerGui:FindFirstChild("NDSTrollHub"):Destroy() end)
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "NDSTrollHub"
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.ResetOnSpawn = false
    
    pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
    if not ScreenGui.Parent then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    -- Cores
    local BG = Color3.fromRGB(15, 15, 20)
    local BG2 = Color3.fromRGB(25, 25, 35)
    local ACCENT = Color3.fromRGB(130, 50, 220)
    local ACCENT2 = Color3.fromRGB(90, 30, 160)
    local TEXT = Color3.fromRGB(255, 255, 255)
    local DIM = Color3.fromRGB(100, 100, 110)
    local GREEN = Color3.fromRGB(50, 200, 50)
    local RED = Color3.fromRGB(200, 50, 50)
    
    -- Frame Principal
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "Main"
    MainFrame.Size = UDim2.new(0, 310, 0, 480)
    MainFrame.Position = UDim2.new(0.5, -155, 0.5, -240)
    MainFrame.BackgroundColor3 = BG
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Parent = ScreenGui
    
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", MainFrame)
    stroke.Color = ACCENT
    stroke.Thickness = 2
    
    -- Header
    local Header = Instance.new("Frame")
    Header.Size = UDim2.new(1, 0, 0, 38)
    Header.BackgroundColor3 = BG2
    Header.BorderSizePixel = 0
    Header.Parent = MainFrame
    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)
    
    -- Header fix (bottom corners)
    local hfix = Instance.new("Frame")
    hfix.Size = UDim2.new(1, 0, 0, 12)
    hfix.Position = UDim2.new(0, 0, 1, -12)
    hfix.BackgroundColor3 = BG2
    hfix.BorderSizePixel = 0
    hfix.Parent = Header
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -90, 1, 0)
    Title.Position = UDim2.new(0, 10, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "⚡ NDS Troll v8.0 REMASTERED"
    Title.TextColor3 = TEXT
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 13
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Header
    
    -- Botão Minimizar
    local MinBtn = Instance.new("TextButton")
    MinBtn.Size = UDim2.new(0, 28, 0, 28)
    MinBtn.Position = UDim2.new(1, -64, 0, 5)
    MinBtn.BackgroundColor3 = ACCENT
    MinBtn.Text = "—"
    MinBtn.TextColor3 = TEXT
    MinBtn.Font = Enum.Font.GothamBold
    MinBtn.TextSize = 16
    MinBtn.Parent = Header
    Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)
    
    -- Botão Fechar
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 28, 0, 28)
    CloseBtn.Position = UDim2.new(1, -32, 0, 5)
    CloseBtn.BackgroundColor3 = RED
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = TEXT
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 12
    CloseBtn.Parent = Header
    Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
    
    -- Content
    local Content = Instance.new("Frame")
    Content.Name = "Content"
    Content.Size = UDim2.new(1, -16, 1, -46)
    Content.Position = UDim2.new(0, 8, 0, 42)
    Content.BackgroundTransparency = 1
    Content.Parent = MainFrame
    
    -- Player Selection
    local PlayerSection = Instance.new("Frame")
    PlayerSection.Size = UDim2.new(1, 0, 0, 80)
    PlayerSection.BackgroundColor3 = BG2
    PlayerSection.BorderSizePixel = 0
    PlayerSection.Parent = Content
    Instance.new("UICorner", PlayerSection).CornerRadius = UDim.new(0, 8)
    
    local PlayerLabel = Instance.new("TextLabel")
    PlayerLabel.Size = UDim2.new(1, -10, 0, 16)
    PlayerLabel.Position = UDim2.new(0, 5, 0, 4)
    PlayerLabel.BackgroundTransparency = 1
    PlayerLabel.Text = "🎯 Selecionar Player:"
    PlayerLabel.TextColor3 = DIM
    PlayerLabel.Font = Enum.Font.Gotham
    PlayerLabel.TextSize = 10
    PlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
    PlayerLabel.Parent = PlayerSection
    
    local PlayerList = Instance.new("ScrollingFrame")
    PlayerList.Size = UDim2.new(1, -10, 0, 38)
    PlayerList.Position = UDim2.new(0, 5, 0, 20)
    PlayerList.BackgroundColor3 = BG
    PlayerList.BorderSizePixel = 0
    PlayerList.ScrollBarThickness = 3
    PlayerList.ScrollBarImageColor3 = ACCENT
    PlayerList.AutomaticCanvasSize = Enum.AutomaticSize.X
    PlayerList.CanvasSize = UDim2.new(0, 0, 0, 0)
    PlayerList.Parent = PlayerSection
    Instance.new("UICorner", PlayerList).CornerRadius = UDim.new(0, 5)
    
    local PlayerListLayout = Instance.new("UIListLayout")
    PlayerListLayout.FillDirection = Enum.FillDirection.Horizontal
    PlayerListLayout.SortOrder = Enum.SortOrder.Name
    PlayerListLayout.Padding = UDim.new(0, 4)
    PlayerListLayout.Parent = PlayerList
    
    Instance.new("UIPadding", PlayerList).PaddingLeft = UDim.new(0, 3)
    
    local SelectedLabel = Instance.new("TextLabel")
    SelectedLabel.Size = UDim2.new(1, -10, 0, 14)
    SelectedLabel.Position = UDim2.new(0, 5, 1, -18)
    SelectedLabel.BackgroundTransparency = 1
    SelectedLabel.Text = "Nenhum selecionado"
    SelectedLabel.TextColor3 = DIM
    SelectedLabel.Font = Enum.Font.Gotham
    SelectedLabel.TextSize = 9
    SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    SelectedLabel.Parent = PlayerSection
    
    local function UpdatePlayerList()
        for _, child in pairs(PlayerList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for _, player in pairs(Players:GetPlayers()) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, 80, 1, -6)
            btn.BackgroundColor3 = State.SelectedPlayer == player and ACCENT or BG2
            btn.Text = player.DisplayName
            btn.TextColor3 = TEXT
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 9
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            btn.Parent = PlayerList
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            
            btn.MouseButton1Click:Connect(function()
                State.SelectedPlayer = player
                SelectedLabel.Text = "✅ " .. player.DisplayName
                SelectedLabel.TextColor3 = GREEN
                UpdatePlayerList()
            end)
        end
    end
    
    UpdatePlayerList()
    Players.PlayerAdded:Connect(UpdatePlayerList)
    Players.PlayerRemoving:Connect(function(p)
        if State.SelectedPlayer == p then
            State.SelectedPlayer = nil
            SelectedLabel.Text = "Nenhum selecionado"
            SelectedLabel.TextColor3 = DIM
        end
        task.wait(0.1)
        UpdatePlayerList()
    end)
    
    -- Botões Scroll
    local BtnScroll = Instance.new("ScrollingFrame")
    BtnScroll.Size = UDim2.new(1, 0, 1, -88)
    BtnScroll.Position = UDim2.new(0, 0, 0, 85)
    BtnScroll.BackgroundTransparency = 1
    BtnScroll.BorderSizePixel = 0
    BtnScroll.ScrollBarThickness = 3
    BtnScroll.ScrollBarImageColor3 = ACCENT
    BtnScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    BtnScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    BtnScroll.Parent = Content
    
    local BtnLayout = Instance.new("UIListLayout")
    BtnLayout.SortOrder = Enum.SortOrder.LayoutOrder
    BtnLayout.Padding = UDim.new(0, 4)
    BtnLayout.Parent = BtnScroll
    
    -- Helpers
    local StatusIndicators = {}
    
    local function MakeCategory(name, order)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 16)
        f.BackgroundTransparency = 1
        f.LayoutOrder = order
        f.Parent = BtnScroll
        
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 1, 0)
        l.BackgroundTransparency = 1
        l.Text = "── " .. name .. " ──"
        l.TextColor3 = ACCENT
        l.Font = Enum.Font.GothamBold
        l.TextSize = 10
        l.Parent = f
    end
    
    local function MakeToggle(name, callback, order, stateKey)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = BG2
        btn.Text = ""
        btn.LayoutOrder = order
        btn.Parent = BtnScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -36, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = TEXT
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = btn
        
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 10, 0, 10)
        dot.Position = UDim2.new(1, -20, 0.5, -5)
        dot.BackgroundColor3 = DIM
        dot.Parent = btn
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        
        if stateKey then StatusIndicators[stateKey] = dot end
        
        btn.MouseButton1Click:Connect(function()
            local ok, msg = callback()
            dot.BackgroundColor3 = ok and GREEN or DIM
            if msg then Notify(name, msg, 2) end
        end)
    end
    
    local function MakeButton(name, callback, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = BG2
        btn.Text = name
        btn.TextColor3 = TEXT
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.LayoutOrder = order
        btn.Parent = BtnScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        
        btn.MouseButton1Click:Connect(function()
            local ok, msg = callback()
            if msg then Notify(name, msg, 2) end
        end)
    end
    
    -- ══ BOTÕES ══
    MakeCategory("⚔️ TROLAGEM (PARTES)", 1)
    MakeToggle("🧲 Ímã de Objetos", ToggleMagnet, 2, "Magnet")
    MakeToggle("🌀 Orbit Attack", ToggleOrbit, 3, "Orbit")
    MakeToggle("⚫ Blackhole", ToggleBlackhole, 4, "Blackhole")
    MakeToggle("🔄 Spin", ToggleSpin, 5, "Spin")
    MakeToggle("🏗️ Cage", ToggleCage, 6, "Cage")
    MakeToggle("🌧️ Part Rain", TogglePartRain, 7, "PartRain")
    MakeToggle("☁️ Sky Lift", ToggleSkyLift, 8, "SkyLift")
    MakeToggle("🌐 Server Magnet", ToggleServerMagnet, 9, "ServerMagnet")
    MakeToggle("🚀 Launch", ToggleLaunch, 10, "Launch")
    
    MakeCategory("💥 FLING", 20)
    MakeToggle("🎩 Hat Fling (clássico)", ToggleHatFling, 21, "HatFling")
    MakeToggle("💎 Accessory Fling (v8)", ToggleAccessoryFling, 22, "AccessoryFling")
    
    MakeCategory("🛠️ UTILIDADES", 30)
    MakeToggle("🛡️ God Mode", ToggleGodMode, 31, "GodMode")
    MakeToggle("✈️ Fly (WASD)", ToggleFly, 32, "Fly")
    MakeToggle("👁️ View Player", ToggleView, 33, "View")
    MakeToggle("🚫 Noclip", ToggleNoclip, 34, "Noclip")
    MakeToggle("⚡ Speed 3x", ToggleSpeed, 35, "Speed")
    MakeToggle("👀 ESP", ToggleESP, 36, "ESP")
    MakeToggle("💤 Anti-Idle", ToggleAntiIdle, 37, "AntiIdle")
    MakeButton("📍 Teleport ao Player", TeleportToPlayer, 38)
    
    MakeCategory("⚙️ CONFIG", 50)
    
    -- Slider Orbit Radius
    local sFrame = Instance.new("Frame")
    sFrame.Size = UDim2.new(1, 0, 0, 42)
    sFrame.BackgroundColor3 = BG2
    sFrame.LayoutOrder = 51
    sFrame.Parent = BtnScroll
    Instance.new("UICorner", sFrame).CornerRadius = UDim.new(0, 6)
    
    local sLabel = Instance.new("TextLabel")
    sLabel.Size = UDim2.new(1, -10, 0, 16)
    sLabel.Position = UDim2.new(0, 5, 0, 3)
    sLabel.BackgroundTransparency = 1
    sLabel.Text = "Raio Orbit: " .. Config.OrbitRadius
    sLabel.TextColor3 = TEXT
    sLabel.Font = Enum.Font.Gotham
    sLabel.TextSize = 10
    sLabel.TextXAlignment = Enum.TextXAlignment.Left
    sLabel.Parent = sFrame
    
    local sBg = Instance.new("Frame")
    sBg.Size = UDim2.new(1, -10, 0, 8)
    sBg.Position = UDim2.new(0, 5, 0, 22)
    sBg.BackgroundColor3 = BG
    sBg.Parent = sFrame
    Instance.new("UICorner", sBg).CornerRadius = UDim.new(1, 0)
    
    local sFill = Instance.new("Frame")
    sFill.Size = UDim2.new(Config.OrbitRadius / 50, 0, 1, 0)
    sFill.BackgroundColor3 = ACCENT
    sFill.Parent = sBg
    Instance.new("UICorner", sFill).CornerRadius = UDim.new(1, 0)
    
    local sBtn = Instance.new("TextButton")
    sBtn.Size = UDim2.new(1, 0, 1, 0)
    sBtn.BackgroundTransparency = 1
    sBtn.Text = ""
    sBtn.Parent = sBg
    
    local draggingSlider = false
    sBtn.MouseButton1Down:Connect(function() draggingSlider = true end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    
    RunService.RenderStepped:Connect(function()
        if draggingSlider then
            local mouse = UserInputService:GetMouseLocation()
            local relX = math.clamp(
                (mouse.X - sBg.AbsolutePosition.X) / sBg.AbsoluteSize.X, 0, 1
            )
            Config.OrbitRadius = math.floor(relX * 45) + 5
            sFill.Size = UDim2.new(relX, 0, 1, 0)
            sLabel.Text = "Raio Orbit: " .. Config.OrbitRadius
        end
    end)
    
    -- Kill All Parts (botão especial)
    MakeButton("🔥 DESATIVAR TUDO", function()
        DisableAllFunctions()
        for key, dot in pairs(StatusIndicators) do
            dot.BackgroundColor3 = DIM
        end
        return true, "Tudo desativado!"
    end, 60)
    
    -- Botão flutuante
    local FloatBtn = Instance.new("TextButton")
    FloatBtn.Size = UDim2.new(0, 46, 0, 46)
    FloatBtn.Position = UDim2.new(0, 8, 0.5, -23)
    FloatBtn.BackgroundColor3 = ACCENT
    FloatBtn.Text = "⚡"
    FloatBtn.TextColor3 = TEXT
    FloatBtn.Font = Enum.Font.GothamBold
    FloatBtn.TextSize = 18
    FloatBtn.Visible = false
    FloatBtn.Parent = ScreenGui
    Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)
    
    -- Minimizar
    local minimized = false
    MinBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(MainFrame, TweenInfo.new(0.2), {
                Size = UDim2.new(0, 310, 0, 38)
            }):Play()
            MinBtn.Text = "+"
            Content.Visible = false
        else
            TweenService:Create(MainFrame, TweenInfo.new(0.2), {
                Size = UDim2.new(0, 310, 0, 480)
            }):Play()
            MinBtn.Text = "—"
            task.wait(0.2)
            Content.Visible = true
        end
    end)
    
    -- Fechar / Reabrir
    CloseBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = false
        FloatBtn.Visible = true
    end)
    
    FloatBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = true
        FloatBtn.Visible = false
    end)
    
    -- Dragging
    local dragging, dragStart, startPos = false, nil, nil
    
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    
    Header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or 
           input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X, 
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    -- Float button dragging
    local fdrag, fdragS, fstartP = false, nil, nil
    FloatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            fdrag = true
            fdragS = input.Position
            fstartP = FloatBtn.Position
        end
    end)
    FloatBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            fdrag = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if fdrag and (input.UserInputType == Enum.UserInputType.MouseMovement or 
           input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - fdragS
            FloatBtn.Position = UDim2.new(
                fstartP.X.Scale, fstartP.X.Offset + delta.X,
                fstartP.Y.Scale, fstartP.Y.Offset + delta.Y
            )
        end
    end)
    
    return ScreenGui
end

-- ═══════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════
SetupNetworkControl()
local UI = CreateUI()

task.spawn(function()
    task.wait(1)
    Notify("⚡ NDS Troll Hub v8.0", "REMASTERED - Carregado!", 3)
end)

print("[NDS Troll Hub v8.0 REMASTERED] Carregado com sucesso!")
print("[INFO] SimRadius: loop agressivo ativado")
print("[INFO] R15 Full Support habilitado")
print("[INFO] Anti-competição de constraints ativada")
print("[INFO] Compatível com Delta Executor")
