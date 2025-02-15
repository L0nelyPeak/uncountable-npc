-- Services
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
-- Folders
local npcFolder = workspace.NPC
local waypointFolder = workspace.Waypoints
-- Variables
local npcAmount = 10 		-- amount of npc that we want
local npcCurrentAmount = 0	-- current amount of npc
local usedIDs = {}			-- roblox user's that we used
local logic = {}			-- table of informations about each npc
local offset = 5			-- acceptable position difference
local sessionData = {}		-- players session data		
local maxNpcAmount = 1		-- maximum npc that player can have

-- Functions
-- setting npc owner, and changing its state
local function CaptureNPC(player: Player, npc)
	-- check if owner is set up
	if player then
		local character = player.Character
		if character and character.Parent then
			local humanoid = character:FindFirstChild('Humanoid')
			local hrp = character:FindFirstChild('HumanoidRootPart')
			if hrp and humanoid then
				if humanoid.Health > 0  then
					if npc.owner == nil then
						if sessionData[player.UserId] == nil then
							sessionData[player.UserId] = {}
						end
						local currentNpcAmount = sessionData[player.UserId].npc or 0
						if currentNpcAmount < maxNpcAmount then
							sessionData[player.UserId].npc = currentNpcAmount + 1
							npc.owner = character
							npc.state = "follow"
							npc.hrp.CanCollide = false

							-- delete cupture button if npc has owner
							local button = npc.hrp:FindFirstChild('ProximityPrompt')
							if button then
								button:Destroy()
							end
						end
					else
						-- delete cupture button if npc has owner
						local button = npc.hrp:FindFirstChildOfClass('ProximityPrompt')
						if button then
							button:Destroy()
						end
					end
				end
			end
		end
	end
end

-- 1.create npc using random roblox user's avatar. 2.set up npc. 3.spawn npc 4. connect to capture event
local function SpawnNPC(owner)
	-- choose random rblx user
	local randomID = math.random(0, 999999999)
	
	-- check if we tried this user before
	if table.find(usedIDs, randomID) then
		return
	end
	table.insert(usedIDs, randomID)
	-- trying to get avatar
	local success, npcModel = pcall(function()
		return Players:CreateHumanoidModelFromUserId(randomID)
	end)
	
	if success and npcModel then
		-- trying to get user's name
		local success, name = pcall(function()
			return Players:GetNameFromUserIdAsync(randomID)
		end)
		
		if success and name then
			npcModel.Name = name
		else	-- hide name, if we didnt get it
			local Humanoid = npcModel:FindFirstChild('Humanoid')
			if Humanoid then
				Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
		
		-- set up npc
		
		local i = npcCurrentAmount + 1
		
		logic[i] = {}
		logic[i].state = 'patrol'
		logic[i].npc = npcModel
		logic[i].humanoid = npcModel:FindFirstChild('Humanoid')
		logic[i].Animator = logic[i].humanoid:FindFirstChild('Animator')
		logic[i].hrp = npcModel:FindFirstChild('HumanoidRootPart')
		logic[i].currentPosition = logic[i].hrp.Position
		logic[i].id = randomID
		logic[i].rig = nil
		logic[i].currentPoint = nil
		logic[i].nextPoint = nil
		logic[i].previousPoint = nil
		logic[i].owner = owner
		logic[i].lastTrack = nil
		
		if logic[i].humanoid.RigType == Enum.RigType.R15 then
			logic[i].rig = "R15"
		else
			logic[i].rig = "R6"
		end
		-- set up collisions
		for _, bodypart in ipairs(logic[i].npc:GetDescendants()) do
			if bodypart:IsA('BasePart') then
				bodypart.CollisionGroup = 'NPC'
				if bodypart.Name ~= "HumanoidRootPart" then
					bodypart.CanCollide = false
				end
			end
		end
		
		-- connecting to capture event
		local captureButton = Instance.new("ProximityPrompt")
		captureButton.ActionText = "capture"
		captureButton.RequiresLineOfSight = false
		captureButton.Parent = logic[i].hrp
		captureButton.Triggered:Connect(function(player)
			CaptureNPC(player, logic[i])
		end)
		
		-- spawn npc
		
		-- chosing random WP as spawn
		for number, wp in ipairs(waypointFolder:GetChildren()) do
			if number == i then
				logic[i].npc:PivotTo( wp.CFrame )
				logic[i].currentPoint = wp
			elseif i > #waypointFolder:GetChildren() then
				logic[i].npc:PivotTo( wp.CFrame )
				logic[i].currentPoint = wp
			end
		end
		
		logic[i].npc.Parent = npcFolder
		logic[i].hrp:SetNetworkOwner(nil)
		
		-- set up npc's animations
		local animationScript = npcModel:FindFirstChild('Animate')
		if animationScript then
			local walk = Instance.new("Animation")
			walk.AnimationId = animationScript.walk.WalkAnim.AnimationId
			logic[i].walk = logic[i].Animator:LoadAnimation(walk)
			local idle = Instance.new("Animation")
			idle.AnimationId = animationScript.idle.Animation1.AnimationId
			logic[i].idle = logic[i].Animator:LoadAnimation(idle)

			animationScript:Destroy()
		end
		
		npcCurrentAmount = npcCurrentAmount + 1
	end
end

-- spawn npc and wait until we spawn specified amount of them
repeat
	SpawnNPC()
	task.wait()
until npcCurrentAmount == npcAmount


-- Main
-- control each npc
while task.wait() do
	for i = 1, #logic do
		local npc = logic[i]
		
		-- idle state: npc just stays w idle anim
		if npc.state == 'idle' then
			
			if npc.idle then
				if not npc.idle.IsPlaying then
					npc.walk:Stop()
					npc.idle:Play()
				end
			end
			
		-- patrol state: npc choose random available WP and move to it
		elseif npc.state == 'patrol' then
			
			if npc.nextPoint == nil then
				-- choosing random available WP
				local accessiblePoints = npc.currentPoint:GetChildren()
				if #accessiblePoints - 1 > 0 then
					local wayNumber
					repeat
						wayNumber = math.random(1, #accessiblePoints)
					until accessiblePoints[wayNumber].Value ~= npc.previousPoint
					
					for number, wp in ipairs(npc.currentPoint:GetChildren()) do
						if wp:IsA("ObjectValue") then
							if number == wayNumber then
								npc.nextPoint = wp.Value
							end
						end
					end
				else
					npc.nextPoint = npc.currentPoint:FindFirstChildOfClass('ObjectValue').Value
				end
			else
				-- move if we dont already moving
				if npc.humanoid.MoveDirection == Vector3.zero then
					npc.humanoid:MoveTo(npc.nextPoint.Position)
				end
				
				-- checking if WP achieved. if achieved then chose next WP
				local dist = (npc.hrp.Position - npc.nextPoint.Position).Magnitude
				if dist <= offset then
					npc.previousPoint = npc.currentPoint
					npc.currentPoint = npc.nextPoint
					npc.nextPoint = nil
				end
				
				if npc.walk then
					if not npc.walk.IsPlaying then
						npc.idle:Stop()
						npc.walk:Play()
					end
				end
			end
			
		-- if owner, then follows his owner	
		elseif npc.state == "follow" then
			
			-- check if npc still has owner
			if not (npc.owner and npc.owner.Parent) then 
				npc.owner = nil
				npc.state = "idle"
				continue
			end
			local ownerHumanoid = npc.owner:FindFirstChild("Humanoid")
			if not npc.owner:FindFirstChild('HumanoidRootPart') or not ownerHumanoid then
				npc.owner = nil
				npc.state = "idle"
				continue
			end
			
			
			local targetPos = (npc.owner.HumanoidRootPart.CFrame * CFrame.new(0,0,3)).Position
			if npc.humanoid.MoveDirection == Vector3.zero then
				npc.humanoid:MoveTo(targetPos)
			end
			
			-- manage npc animations
			if ownerHumanoid.MoveDirection == Vector3.zero then
				npc.humanoid:MoveTo(npc.hrp.Position)
				if npc.idle then
					if not npc.idle.IsPlaying then
						npc.walk:Stop()
						npc.idle:Play()
					end
				end
			else
				if npc.walk then
					if not npc.walk.IsPlaying then
						npc.idle:Stop()
						npc.walk:Play()
					end
				end
			end
		end
	end
end
