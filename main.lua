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
    Vector3.new(-1263, 18, -1534),
    Vector3.new(1815, 25, -884),
    Vector3.new(714, 44, 1062),
    Vector3.new(1409, 23, -3914)
}

local function getBounty()
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

local function generateWaypoints(origin: Vector3, endPosition: Vector3): {PathWaypoint}
	local path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = 5,
		AgentCanJump = false,
	})

	local success, errorMessage = pcall(function()
		path:ComputeAsync(origin, endPosition)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	else
		warn("Pathfinding failed: " .. tostring(errorMessage))
        state = "start"
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

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character

local path = {}

local alive = true

if localPlayer.TeamValue.Value ~= "Police" then
    firesignal(Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("TeamSelectGui").TeamSelect.Frame.MiddleContainer.Container.Police.Activated)
end

task.wait(5)

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

local walkspeed = 30
local flyspeed = 120
local cruisealt = 500

local targetPlayer = nil
local targetVehicle = nil
runService.RenderStepped:Connect(function(dt)
    if alive then
        if state == "start" then
             local raycastParams = RaycastParams.new()
            -- Ignore the player's own character so it doesn't hit itself
            raycastParams.FilterDescendantsInstances = {character}
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.IgnoreWater = true
            local raycastDistance = 50
            local direction = Vector3.new(0, 1, 0) * raycastDistance
            local result = workspace:Raycast(character.HumanoidRootPart.Position, direction, raycastParams)
            if result then
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
                path = generateWaypoints(character.HumanoidRootPart.Position, closestSpawn)
            else
                print("not under something")
                state = "vehiclefind"
          end
        end
        if state == "leaving" then
           if #path > 0 then
                local nextWaypoint = path[1]
                local direction = (nextWaypoint.Position - character.HumanoidRootPart.Position).Unit
                character.HumanoidRootPart.CFrame = CFrame.new(character.HumanoidRootPart.Position + direction * walkspeed * dt)
                
                if (character.HumanoidRootPart.Position - nextWaypoint.Position).Magnitude < 5 then
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
                    if distance < closestDistance and distance <= maxDistance then
                        closestDistance = distance
                        closestVehicle = vehicle
                    end
                end
            end
            if closestVehicle ~= nil then
                targetVehicle = closestVehicle
                state = "vehicleenter"
            else
                state = "vehiclespawn"
            end
        end
        if state == "vehiclespawn" then
            spawnVehicle("Camaro")
            state = "locatetarget"
        end
    end
end)



