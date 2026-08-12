--[[
speed rules
magnitude speed generally around 120
game doesnt care about how fast you go vertically down so you can just cframe to teleport down

]]

local state = "start"

local teleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local ws = WebSocket.connect("ws://localhost:8766")
local jobid = game.JobId

local spawnTP = {
    Vector3.new(1725, 23 -4006),
    Vector3.new(-1262, 18, -1542),
    Vector3.new(1815, 25, -884),
    Vector3.new(714, 44, 1062),
    Vector3.new(1409, 23, -3914),
    Vector3.new(1805,28, -802)
}

local function getTotalBounty()
    local board = workspace:WaitForChild("BountyBoard")
    local wanted = board.Board.MostWanted.Board
    local bounty = 0

    for i, playerFrame in pairs(wanted:getChildren()) do
        local bountyTextObject = playerFrame:FindFirstChild("BountyText")
        if bountyTextObject then
            local splitTable = string.split(bountyTextObject.Text, "$")
            local rawAmount = splitTable[2]
            
            if rawAmount then
                local cleanText = string.gsub(rawAmount, ",", "")
                bounty += tonumber(cleanText) or 0
            end
        end
    end
    return bounty
end

local Players = game:GetService("Players")

local function getSortedBounties()
    local board = workspace:WaitForChild("BountyBoard")
    local wanted = board.Board.MostWanted.Board
    local bountyTable = {}

    for _, playerFrame in pairs(wanted:GetChildren()) do
        local bountyTextObject = playerFrame:FindFirstChild("BountyText")
        -- Change "DisplayName" to whatever the actual text label for the name is called in the frame
        local displayNameObject = playerFrame:FindFirstChild("NameText") 
        
        if bountyTextObject and displayNameObject then
            -- 1. Calculate the Bounty
            local splitTable = string.split(bountyTextObject.Text, "$")
            local rawAmount = splitTable[2]
            local bountyAmount = 0
            
            if rawAmount then
                local cleanText = string.gsub(rawAmount, ",", "")
                bountyAmount = tonumber(cleanText) or 0
            end
            
            -- 2. Convert Display Name to Username
            local uiDisplayName = displayNameObject.Text
            local actualUsername = uiDisplayName -- Fallback just in case they left the game
            
            for _, player in pairs(Players:GetPlayers()) do
                if player.DisplayName == uiDisplayName then
                    actualUsername = player.Name
                    break
                end
            end
            
            -- 3. Insert into our table
            table.insert(bountyTable, {
                Username = actualUsername,
                Bounty = bountyAmount
            })
        end
    end

    -- 4. Sort the table from Highest to Lowest
    table.sort(bountyTable, function(a, b)
        return a.Bounty > b.Bounty 
    end)

    return bountyTable
end

local function joinServer(jobid)
    local player = Players.LocalPlayer
    local placeId = game.PlaceId

    if not jobId or jobId == "" then
        warn("Invalid jobId provided.")
        return
    end
    if JobId == game.JobId then
        warn("Cannot teleport to the same server.")
        return
    end
    local success, errorMessage = pcall(function()
        teleportService:TeleportToPlaceInstance(placeId, jobid, player)
    end)

    if not success then
        warn("Teleportation failed: " .. errorMessage)
    end
    return success
end


-- Walk up the ancestry to see if this part belongs to a model with "door" in its name
local function isPartOfDoor(part: BasePart): boolean
	local current = part.Parent
	while current do
		if current:IsA("Model") and string.find(string.lower(current.Name), "door") then
			return true
		end
		current = current.Parent
	end
	return false
end

-- Run this once (e.g. at server startup) to mark all door parts as pathfinding-passable
local function markDoorsAsPassable()
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and isPartOfDoor(part) then
			if not part:FindFirstChildOfClass("PathfindingModifier") then
				local modifier = Instance.new("PathfindingModifier")
				modifier.PassThrough = true
				modifier.Parent = part
			end
		end
	end
end

markDoorsAsPassable()

local Debris = game:GetService("Debris")

local function generateWaypoints(origin: Vector3, endPosition: Vector3, returnstate: string): {PathWaypoint}
	local path = PathfindingService:CreatePath({
		AgentRadius = 4,
		AgentHeight = 6,
		AgentCanJump = true,
	})

	local success, errorMessage = pcall(function()
		path:ComputeAsync(origin, endPosition)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()

		for _, waypoint in ipairs(waypoints) do
			local block = Instance.new("Part")
			block.Size = Vector3.new(1, 1, 1)
			block.Position = waypoint.Position
			block.Anchored = true
			block.CanCollide = false
			block.Shape = Enum.PartType.Block
			block.Material = Enum.Material.Neon
			block.Color = if waypoint.Action == Enum.PathWaypointAction.Jump
				then Color3.fromRGB(255, 170, 0)
				else Color3.fromRGB(0, 170, 255)
			block.Parent = workspace

			Debris:AddItem(block, 60)
		end

		return waypoints
	else
		warn("Pathfinding failed: " .. tostring(errorMessage))
        state = returnstate
		return {}
	end
end

ws.OnMessage:Connect(function(message)
    local ok, data = pcall(httpService.JSONDecode, httpService, message)
    if not ok then
        warn("Failed to decode JSON message: " .. data)
        return
    end
    jobid = data.job_id
end)

local function silentAim(state, part)
    silentAimEnabled = state
    local raycastModule = require(replicatedStorage.Module.RayCast)

    if silentAimEnabled then
        currentTarget = part

        getgenv().old = getgenv() or raycastModule.RayIgnoreNonCollideWithIgnoreList

        raycastModule.RayIgnoreNonCollideWithIgnoreList = function(...)
            local arg = {getgenv().old(...)}
            local scriptname = tostring(getfenv(2).script)
            if (scriptName == "BulletEmitter" or scriptName == "Taser") and currentTarget then
                arg[1] = part
                arg[2] = part.Position
            end
        end
        return unpack(arg)
    end
end

local function isPlayerBelowSomething(player, maxDistance)
    maxDistance = maxDistance or 70

    local character = player.Character
    if not character then return false end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {character}

    local origin = rootPart.Position
    local direction = Vector3.new(0, maxDistance, 0)

    local result = workspace:Raycast(origin, direction, raycastParams)

    return result ~= nil
end

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character

local path = {}

local alive = true

if localPlayer.TeamValue.Value ~= "Police" then
    firesignal(Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("TeamSelectGui").TeamSelect.Frame.MiddleContainer.Container.Police.Activated)
end


character.Humanoid.Died:Connect(function()
    alive = false
end)

localPlayer.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    alive = true
    state = "start"
end)

local function spawnVehicle(VehicleName)
    local event = replicatedStorage:WaitForChild("GarageSpawnVehicle")
    event:FireServer("Chassis",VehicleName)
end

local function vehicleState(vehicle)
    for i,v in pairs(vehicle:GetChildren()) do
        if v:IsA("Folder") then
            local split = string.split(v.Name, "_") 
            if split 
                if split[2] == "VehicleState" then
                    return split[3]
                else
                    return nil
                end
            end
        end
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BountyHunterGUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = game:GetService("CoreGui")

local textlabel = Instance.new("TextLabel")
textlabel.Size = UDim2.new(0, 300, 0, 40)
textlabel.Position = UDim2.new(0.5, -150, 0, 5)
textlabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
textlabel.BackgroundTransparency = 0.5
textlabel.TextColor3 = Color3.fromRGB(255, 255, 255)
textlabel.TextSize = 18
textlabel.Font = Enum.Font.SourceSansBold
textlabel.Text = "Bounty Hunter Active"
textlabel.Parent = screenGui


local walkspeed = 50
local flyspeed = 120
local carflyspeed = 300
local cruisealt = 500

local targetPlayer = nil
local targetVehicle = nil

local vehicleEntered = false

runService.RenderStepped:Connect(function(dt)
    textlabel.Text = state
    if alive then
        if state == "start" then
            print("under something")
            local closestSpawn = nil
            local closestDistance = math.huge
            for _, spawn in ipairs(spawnTP) do
            local distance = (spawn - character.HumanoidRootPart.Position).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closestSpawn = spawn
                end
            end
            state = "leaving"
            markDoorsAsPassable()
            path = generateWaypoints(character.HumanoidRootPart.Position, closestSpawn, "start")
        end
        if state == "leaving" then
           if #path > 0 then
                local nextWaypoint = path[1]
                local direction = (nextWaypoint.Position - character.HumanoidRootPart.Position).Unit
                character.HumanoidRootPart.CFrame = CFrame.new(character.HumanoidRootPart.Position + direction * walkspeed * dt)
                
                if (character.HumanoidRootPart.Position - nextWaypoint.Position).Magnitude < 2 then
                    print("Reached waypoint:", nextWaypoint.Position)

                    if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
                        character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end

                    table.remove(path, 1)
                    -- Check if we just cleared the final waypoint
                    if #path == 0 then
                        state = "vehiclefind"
                        print("Path completed! Switching state to:", state)
                    end
                end
            end
        end 
        if state == "vehiclefind" then
            local vehicles = workspace:WaitForChild("Vehicles"):GetChildren()
            local closestVehicle = nil
            local closestDistance = math.huge
            local maxDistance = 200
            for _,vehicle in pairs(vehicles) do
                if vehicle.Name == "Jeep" or vehicle.Name == "Camaro" then
                    local distance = (vehicle.PrimaryPart.Position - character.HumanoidRootPart.Position).Magnitude
                    local occupied = vehicleState(vehicle)
                    if distance < closestDistance and distance <= maxDistance and occupied == nil then
                        closestDistance = distance
                        closestVehicle = vehicle
                    end
                end
            end
            if closestVehicle ~= nil then
                targetVehicle = closestVehicle
                state = "vehicleapproach"
                print("Found vehicle:", targetVehicle.Name, "at distance:", closestDistance)
            else
                state = "vehiclespawn"
                print("No vehicle found within range. Switching state to:", state)
            end
        end
        if state == "vehiclespawn" then
            spawnVehicle("Camaro")
            --find closest vehicle and set it to targetVehicle
            local vehicles = workspace:WaitForChild("Vehicles"):GetChildren()
            local closestVehicle = nil
            local closestDistance = math.huge
            local maxDistance = 20
            for i,v in pairs(workspace.Vehicles:GetChildren()) do
                if v:FindFirstChild("_VehicleState_"..localPlayer.Name) then
                    targetVehicle = v
                end
            end
            print("Spawned vehicle:", targetVehicle.Name, "at distance:", closestDistance)
            vehicleEntered = true
            state = "locatetarget"
        end
        if state == "vehicleapproach" then
            print("State: vehicleapproach, Target Vehicle:", targetVehicle.Name)
            state = "vehicleenter"
            markDoorsAsPassable()
            path = generateWaypoints(character.HumanoidRootPart.Position, targetVehicle.Seat.Position, "vehicleapproach")
        end
        if state == "vehicleenter" then
            if #path > 0 then
                local nextWaypoint = path[1]
                local direction = (nextWaypoint.Position - character.HumanoidRootPart.Position).Unit
                character.HumanoidRootPart.CFrame = CFrame.new(character.HumanoidRootPart.Position + direction * walkspeed * dt)
                
                if (character.HumanoidRootPart.Position - nextWaypoint.Position).Magnitude < 2 then
                    print("Reached waypoint:", nextWaypoint.Position)

                    if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
                        character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end


                    table.remove(path, 1)
                    
                    if #path == 0 then
                        keytap(0x45) -- E key to enter vehicle
                        state = "locatetarget"
                        vehicleEntered = true
                        print("Path completed! Switching state to:", state)
                    end
                end
            end
        end
        if state == "locatetarget" then
            if vehicleEntered then
                task.spawn(function()
                    task.wait(1)
                    vehicleEntered = false
                end)
            end
            if vehicleEntered == false then
                local bounties = getSortedBounties()
                if #bounties > 0 then
                    local topBounty = bounties[1]
                    targetPlayer = Players:FindFirstChild(topBounty.Username)
                    if targetPlayer then
                        print("Targeting player:", targetPlayer.Name, "with bounty:", topBounty.Bounty)
                        if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                            if targetVehicle.PrimaryPart.Position.Y < cruisealt then
                                targetVehicle.PrimaryPart.CFrame = CFrame.new(targetVehicle.PrimaryPart.Position+Vector3.new(0,1,0)*carflyspeed*dt)
                            end
                        else
                            state = "targetapproach"
                        end
                    else
                        print("Target player not found in the game.")
                    end
                else
                    print("No players with bounties found.")
                end
            end
        end
        if state == "targetapproach" then
            if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local targetPosition = targetPlayer.Character.HumanoidRootPart.Position
                targetPosition = Vector3.new(targetPosition.X, cruisealt, targetPosition.Z)
                local direction = (targetPosition - character.HumanoidRootPart.Position).Unit
                targetVehicle.PrimaryPart.CFrame = CFrame.new(targetVehicle.PrimaryPart.Position + direction * carflyspeed * dt)
            else
                print("Target player not found or does not have a character.")
            end
        end
    end
end)



