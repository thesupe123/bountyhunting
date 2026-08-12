--[[
speed rules
magnitude speed generally around 120
game doesnt care about how fast you go vertically down so you can just cframe to teleport down

]]

local teleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local httpService = game:GetService("HttpService")
local runService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

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

local function generateWaypoints(origin: Vector3, endPosition: Vector3): {PathWaypoint}
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
	})

	-- Track modified parts so we can restore their collision states
	local modifiedParts = {}

	-- Temporarily disable collision for parts inside any model containing "Door"
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.CanCollide then
			local model = descendant:FindFirstAncestorOfClass("Model")
			if model and string.find(model.Name:lower(), "door") then
				table.insert(modifiedParts, {
					part = descendant, 
					originalCanCollide = descendant.CanCollide
				})
				descendant.CanCollide = false
			end
		end
	end

	-- Compute the path safely using pcall
	local success, errorMessage = pcall(function()
		path:ComputeAsync(origin, endPosition)
	end)

	-- Restore the original collision states immediately
	for _, item in ipairs(modifiedParts) do
		item.part.CanCollide = item.originalCanCollide
	end

	-- Return waypoints if successful, or an empty table if it failed
	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	else
		warn("Pathfinding failed: " .. tostring(errorMessage))
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

firesignal(Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("TeamSelectGui").TeamSelect.Frame.MiddleContainer.Container.Police)

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character
local state = "start"
local path = {}
character.Humanoid.Died:Connect(function()
    alive = false
    state = "start"
end)

localPlayer.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    alive = true
    state = "start"
end)

local alive = true

local walkspeed = 30
local flyspeed = 120

runservice.RenderStepped:Connect(function(dt)
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
          end
        end
        if state == "leaving" then
            if #path > 0 then
                local nextWaypoint = path[1]
                local direction = (nextWaypoint.Position - character.HumanoidRootPart.Position).Unit
                character.HumanoidRootPart.CFrame = CFrame.new(character.HumanoidRootPart.Position + direction * flyspeed * dt)
                if (character.HumanoidRootPart.Position - nextWaypoint.Position).Magnitude < 5 then
                    table.remove(path, 1)
                end
            end
        end
    end
    print(state)
end)



