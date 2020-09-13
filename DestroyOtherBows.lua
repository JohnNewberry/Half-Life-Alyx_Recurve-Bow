
-- Seeing a bunch of bows in the game is a bit strange, limit to the closest one in the map
-- If the player brings a bow into a level, it would be this one
-- If they loose a bow, the closest one in the next level will be available for them

local templateBow = nil
local closestBow = nil
local closestRespawnMaker = nil
local respawnPos
local respawnAng
local requiredCleanup = false
local enableBackpack = nil

local EQUIP_PLAYER_KEYVALS = {
	classname = "info_hlvr_equip_player";
	targetname = "dob_equip_player"
}

function Activate()

	print("------------------")
	print("DESTROY OTHER BOWS")
	print("------------------")

	thisEntity:SetThink(FindTemplateBow, "findtemplatebow", 0.25)

	thisEntity:SetThink(Search, "search", 0.5)
	
	requiredCleanup = false
	
	for i, otherArrow in pairs(Entities:FindAllByClassname("logic_collision_pair")) do
		if string.match(otherArrow:GetName(), "bow_arrow_collision") or string.match(otherArrow:GetName(), "drop_prevention_arrow_collision") then
			otherArrow:Kill()
			RequiredCleanup = true
		end
    end

	-- re-enable the backpack in case it was disabled
	
	if not IsValidEntity(enableBackpack) then
		local keyvals = vlua.clone(EQUIP_PLAYER_KEYVALS)
		keyvals.equip_on_mapstart = "0"
		keyvals.backpack_enabled = "1"
		keyvals.itemholder = "1"
		enableBackpack = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
	end
	
	DoEntFire(enableBackpack:GetName(), "EquipNow", "",  0.0, nil, nil)
end

function FindTemplateBow()

	-- to respawn the bow later, look for the template in the prefab and save it

	local templateBow = nil
	local closestBowDistance = 200	

	for key, value in pairs(Entities:FindAllByModel("models/bow2.vmdl")) do
		local entity = value
		
		local scope = entity:GetPrivateScriptScope()
		if scope and scope.BowThink then
		
			local bowDistance = VectorDistance(thisEntity:GetAbsOrigin(), entity:GetAbsOrigin())
			
			if bowDistance < closestBowDistance then
				closestBowDistance = bowDistance
				templateBow = entity
			end
		end		
	end
	
	if IsValidEntity(templateBow) then
		DoEntFire(templateBow:GetName(), "CallScriptFunction", "Destroy",  0.0, nil, nil)
	end
	
end

function Search()

	-- a bunch of spawned entities get left over and unreferenced when loading a save, find and remove them

	closestRespawnMaker = Entities:FindByClassnameNearest("env_entity_maker", thisEntity:GetAbsOrigin(), 1000)
	
	closestBow = nil
	local closestBowDistance = 1000000	

	-- loop through bows to find the closest, check for the ObjectBow script too
	-- destroy all but the closest bow to the player

	for key, value in pairs(Entities:FindAllByModel("models/bow2.vmdl")) do
		local entity = value
		
		local scope = entity:GetPrivateScriptScope()
		if scope and scope.BowThink then
			
			local bowDistance = VectorDistance(Entities:GetLocalPlayer():EyePosition(), entity:GetAbsOrigin())
			
			if bowDistance < closestBowDistance then
			
				if IsValidEntity(closestBow) then
					DoEntFire(closestBow:GetName(), "CallScriptFunction", "Destroy",  0.0, nil, nil)
				end
			
				closestBowDistance = bowDistance
				closestBow = entity
			else
				DoEntFire(entity:GetName(), "CallScriptFunction", "Destroy",  0.0, nil, nil)
			end
		end		
	end
	
	-- if the player is already holding a bow then do some funky stuff to reactivate it
	-- the model will lag behind a little but it should be all good if picked up again

	if IsValidEntity(closestBow) then
	
		local bowHasQuiver = false
	
		for key, value in pairs(Entities:FindAllByModel("models/bowsections/bow_quiver.vmdl")) do
			local entity = value
			
			local quiverDistance = VectorDistance(closestBow:GetAbsOrigin(), entity:GetAbsOrigin())
			
			if quiverDistance < 10 then
				bowHasQuiver = true
			end
		end
		
		if RequiredCleanup or not bowHasQuiver then
			
			respawnPos = closestBow:GetAbsOrigin() + Vector(0, 0, 5)
			respawnAng = closestBow:GetAngles()
			
			DoEntFire(closestBow:GetName(), "CallScriptFunction", "Destroy",  0.0, nil, nil)
			
			closestRespawnMaker:SetAbsAngles(respawnAng.x, respawnAng.y, respawnAng.z)
			closestRespawnMaker:SetAbsOrigin(respawnPos)
			
			if IsValidEntity(closestRespawnMaker) then
				DoEntFire(closestRespawnMaker:GetName(), "ForceSpawn", "",  0.0, nil, nil)
			end
		end
	end
	
	--
	
	-- destroy any nearby arrows, in case the player is holding one or some are attached close by
	
	for key, value in pairs(Entities:FindAllByModel("models/arrows/arrow1.vmdl")) do
		local entity = value
		
		local scope = entity:GetPrivateScriptScope()
		if scope and scope.ArrowThink then

			local leftHand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(0)	
			local rightHand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1)	
			
			local leftHandDistance = VectorDistance(leftHand:GetAbsOrigin(), entity:GetAbsOrigin())
			local rightHandDistance = VectorDistance(rightHand:GetAbsOrigin(), entity:GetAbsOrigin())
			
			if leftHandDistance < 50 or rightHandDistance < 50 then
				if scope.Destroy then
					entity:GetOrCreatePrivateScriptScope():Destroy()
				end
			end
		end		
	end
end