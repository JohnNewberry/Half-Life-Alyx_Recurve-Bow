
-- properties

local holdingThisBow = false
local holdingArrow = false
local leftHandFull = false
local rightHandFull = false
local inAPocket = false
local ignoreFirstPickup = true

local heldArrow = nil

local bowHand = nil
local arrowHand = nil

local backpackDisabled = false

local drawFrac = 0
local drawTime = 0

local arrowNocked = false
local nockedArrow = nil
local nockedArrowOrigin
local nockedArrowAngles
local lastArrowPos

local arrowShouldered = false
local shoulderArrow = nil

local hintArrow = nil

local needsToFire = false

local upperInitialStringLength = 0
local lowerInitialStringLength = 0

local needsToShowHint = false

local bowUpperBody = nil
local bowLowerBody = nil
local bowMidBody = nil
local bowUpperString = nil
local bowLowerString = nil
local bowUpperStringBase = nil
local bowLowerStringBase = nil
local bowReticule = nil
local bowQuiver = nil
local bowDropPrevention = nil
local arrowBowCollision = nil
local arrowDropPreventionCollision = nil
local bowEnableBackpack = nil
local bowDisableBackpack = nil
local bowDrawHint = nil
local bowNockHint = nil

-- config

local DRAW_FIRE_DELAY = 0.1
local FIRE_THINK_DELAY = 0.2
local THINK_INTERVAL = 0.01

local ARROW_LENGTH = 30
local ARROW_HAND_OFFSET = 3

local DRAW_MIN = 10
local DRAW_MAX = 25

local SNAP_XPOSTHRESHOLD_MIN = 8
local SNAP_YZPOSTHRESHOLD_MIN = 1
local SNAP_ANGTHRESHOLD_MIN = 0.93

local SNAP_XPOSTHRESHOLD_MAX = 20
local SNAP_YZPOSTHRESHOLD_MAX = 1.5
local SNAP_ANGTHRESHOLD_MAX = 0.5

local SHOULDER_POSTHRESHOLD_MIN = 0.5
local SHOULDER_ANGTHRESHOLD_MIN = 0.05

local SHOULDER_POSTHRESHOLD_MAX = 5
local SHOULDER_ANGTHRESHOLD_MAX = -0.9

local SHOULDER_HEIGHTTHRESHOLD = -25

local HAPTIC_BUMPS = {0.0, 0.1, 0.2, 0.3, 0.4,
					0.47, 0.54, 0.62, 0.67, 0.73,
					0.78, 0.83, 0.86, 0.885, 0.915,
					0.935, 0.95, 0.965, 0.975, 0.98 }

local NOCKED_ARROW_KEYVALS = {
	classname = "prop_physics"; 
	targetname = "arrow";
	model = "models/arrows/arrow1_nocollision.vmdl";
}

local SHOULDER_ARROW_KEYVALS = {
	classname = "prop_physics";
	targetname = "arrow";
	model = "models/arrows/arrow1.vmdl";
	vscripts = "ObjectArrow";
	carrytype_override = "CARRY_TYPE_1H_RIGID"
}

local HINT_ARROW_KEYVALS = {
	classname = "prop_dynamic";
	targetname = "hint_arrow";
	model = "models/arrows/arrow1_hologram.vmdl"
}

local COLLISION_PAIR_KEYVALS = {
	classname = "logic_collision_pair";
	targetname = "bow_arrow_collision"
}

local EQUIP_PLAYER_KEYVALS = {
	classname = "info_hlvr_equip_player";
	targetname = "bow_equip_player"
}

local BOW_DRAW_HINT_KEYVALS = {
	classname = "env_instructor_vr_hint";
	targetname = "bow_draw_hint";
	hint_caption = "Grab arrow from backpack";
	hint_start_sound = "Instructor.StartLesson";
	hint_vr_panel_type = "1"
}

local BOW_NOCK_HINT_KEYVALS = {
	classname = "env_instructor_vr_hint";
	targetname = "bow_nock_hint";
	hint_caption = "Align arrow with bow";
	hint_start_sound = "Instructor.StartLesson";
	hint_vr_panel_type = "2"
}


function Precache(context)
	PrecacheModel(NOCKED_ARROW_KEYVALS.model, context)
	PrecacheModel(SHOULDER_ARROW_KEYVALS.model, context)
	PrecacheModel("models/arrows/constraint_anchor.vmdl", context)
	
	PrecacheResource("soundfile", "soundevents/archery.vsndevts", context)
	PrecacheResource( "particle_folder", "particles", context )
end

function Activate()
	ListenToGameEvent("item_pickup", OnPickup, itemTable)
	ListenToGameEvent("item_released", OnRelease, itemTable)
	ListenToGameEvent("player_stored_item_in_itemholder", OnStore, itemTable)
	
	thisEntity:SetThink(BowThink, "bow_think", 0)
	thisEntity:SetThink(Init, "init", 0.5)
	
	thisEntity:DisableMotion()
end

function Init()
	-- this is delayed so that everything has activated
	if heldBow ~= thisEntity and IsValidEntity(thisEntity) then
		SetupAttachments()
		if IsValidEntity(bowReticule) then
			bowReticule:SetLocalAngles(0, 0, 90)
		end
		thisEntity:EnableMotion()
	end
end

function SetupAttachments()

	if not IsValidEntity(thisEntity) then
		return nil
	end

	-- Search children for relevent entities

	local children = thisEntity:GetChildren()
	for idx, child in pairs(children) do
		if child:GetModelName() == "models/bowsections/bow_upperbody.vmdl" then
			bowUpperBody = child
			local upperBodyChildren = bowUpperBody:GetChildren()
			for idx2, upperBodyChild in pairs(upperBodyChildren) do
				if upperBodyChild:GetModelName() == "models/bowsections/bow_left_sight.vmdl" then
					bowReticule = upperBodyChild
				end
			end
		elseif child:GetModelName() == "models/bowsections/bow_midbody.vmdl" then
			bowMidBody = child
		elseif child:GetModelName() == "models/bowsections/bow_lowerbody.vmdl" then
			bowLowerBody = child
		elseif child:GetModelName() == "models/bowsections/bow_lower_string.vmdl" then
			bowLowerString = child
		elseif child:GetModelName() == "models/bowsections/bow_upper_string.vmdl" then
			bowUpperString = child
		elseif child:GetModelName() == "models/bowsections/bow_lower_string_base.vmdl" then
			bowLowerStringBase = child
		elseif child:GetModelName() == "models/bowsections/bow_upper_string_base.vmdl" then
			bowUpperStringBase = child
		elseif child:GetModelName() == "models/bowsections/bow_quiver.vmdl" then
			bowQuiver = child
		elseif child:GetModelName() == "models/damageblocker2.vmdl" then
			bowDropPrevention = child
		end
	end	
	
	-- Strings scale based on thier initial size, set this up now
	
	local notchId = thisEntity:ScriptLookupAttachment("Notch") 
	local notchPos = thisEntity:GetAttachmentOrigin(notchId)

	local upperNotchId = bowUpperBody:ScriptLookupAttachment("UpperNotch") 
	local upperNotchPos = bowUpperBody:GetAttachmentOrigin(upperNotchId)

	upperInitialStringLength = (upperNotchPos - notchPos):Length()
	
	local lowerNotchId = bowLowerBody:ScriptLookupAttachment("LowerNotch") 
	local lowerNotchPos = bowLowerBody:GetAttachmentOrigin(lowerNotchId)
		
	lowerInitialStringLength = (lowerNotchPos - notchPos):Length()
	
	-- setup collision prevention between arrow and bow sectiions
	
	if not arrowBowCollision and not IsValidEntity(arrowBowCollision) then
		local keyvals = vlua.clone(COLLISION_PAIR_KEYVALS)
		keyvals.attach1 = thisEntity:GetName()
		arrowBowCollision = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
		arrowBowCollision:SetParent(thisEntity, "")
	end
	
	if not arrowDropPreventionCollision and not IsValidEntity(arrowDropPreventionCollision) and IsValidEntity(bowDropPrevention) then
		local keyvals = vlua.clone(COLLISION_PAIR_KEYVALS)
		keyvals.targetname = "drop_prevention_arrow_collision"
		keyvals.attach1 = bowDropPrevention:GetName()
		arrowDropPreventionCollision = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
		arrowDropPreventionCollision:SetParent(thisEntity, "")
	end
	
	if not IsValidEntity(bowEnableBackpack) then
		local keyvals = vlua.clone(EQUIP_PLAYER_KEYVALS)
		keyvals.equip_on_mapstart = "0"
		keyvals.backpack_enabled = "1"
		keyvals.itemholder = "1"
		bowEnableBackpack = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
		bowEnableBackpack:SetParent(thisEntity, "")
	end
	
	if not IsValidEntity(bowDisableBackpack) then
		local keyvals = vlua.clone(EQUIP_PLAYER_KEYVALS)
		keyvals.targetname = "bow_disable_backpack"
		keyvals.equip_on_mapstart = "0"
		keyvals.backpack_enabled = "0"
		keyvals.itemholder = "1"
		bowDisableBackpack = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
		bowDisableBackpack:SetParent(thisEntity, "")
	end
	
	UpdateBowString(notchPos)
end

function OnPickup(itemTable)

	-- When any item is pickup up, check for this bow and any arrow

	if not IsValidEntity(thisEntity) then
		return nil
	end
	
	if ignoreFirstPickup then
		ignoreFirstPickup = false
		if itemTable["item_name"] == nil then
			return nil
		end
	end

	local handIndex = 0
	if itemTable["vr_tip_attachment"] == 1 then
		handIndex = 1
	end
	
	local hand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(handIndex)	
	
	
	if handIndex == 0 then
		leftHandFull = true
	else
		rightHandFull = true
	end
	
	
	if itemTable["item_name"] == thisEntity:GetName() then
	
		holdingThisBow = true
		bowHand = hand		
		
		-- Retrieved from a pocket, scale the parts back up again
		
		if inAPocket then
			OnRetrieve()
		end
		
		SetupAttachments()
		
		-- scale up the drop prevention box
		-- this object blocks shots so that the player does not drop the bow when hit in the hand
		
		if IsValidEntity(bowDropPrevention) then
			bowDropPrevention:SetAbsScale(1)
		end
		
		-- to enable over the shoulder drawing, the backpack is disabled when only the bow is held
		
		if handIndex == 0 then
			if not rightHandFull then
				DisableBackpack()
			end
		else
			if not leftHandFull then
				DisableBackpack()
			end
		end
		
		-- Tutorial messages
		
		if needsToShowHint then
			if holdingArrow then
				ShowNockHint()
			else
				ShowDrawHint()
			end
		end
		
		-- the quiver is hidden when the bow is picked up
		-- I added this so the user knows they have a supply of arrows
		
		if IsValidEntity(bowQuiver) then
			thisEntity:SetThink(RemoveQuiver, "remove_quiver", 0.2)
			needsToShowHint = true
		end
		
	elseif itemTable["item_name"] and string.match(itemTable["item_name"], "Arrow") then	
		
		-- not sure how to get the entity here, closest arrow to the hand seems to work fine
		
		local closestArrow = Entities:FindByClassnameNearest("prop_physics", hand:GetAbsOrigin(), 30)
		
		if arrowShouldered then
			closestArrow = shoulderArrow
		end
		
		if closestArrow and IsValidEntity(closestArrow) then
			holdingArrow = true
			heldArrow = closestArrow
			arrowHand = hand
			lastArrowPos = heldArrow:GetAbsOrigin()
			
			if arrowShouldered then
				arrowShouldered = false
				shoulderArrow:SetParent(nil, "")
				shoulderArrow:SetAbsScale(1)
				arrowHand:FireHapticPulse(1)
			end
		
			-- if the arrow has been attached to something, break the attachment
			
			DoEntFire(itemTable["item_name"], "CallScriptFunction", "PickedUp",  0.0, nil, nil)
			
			if IsValidEntity(arrowDropPreventionCollision) then
				DoEntFire(arrowDropPreventionCollision:GetName(), "DisableCollisionsWith", heldArrow:GetName(),  0.0, nil, nil)
			end
			
			if needsToShowHint and holdingThisBow then
				ShowNockHint()
			end
		end
		
	else

		-- Keep track of other objects in the hands, the backpack should be re-enabled if something else is carried

		if leftHandFull and rightHandFull and holdingThisBow and backpackDisabled then
			EnableBackpack()
		end
	end
end

function OnRelease(itemTable)

	if not IsValidEntity(thisEntity) then
		return nil
	end

	local handIndex = 0
	if itemTable["vr_tip_attachment"] == 1 then
		handIndex = 1
	end
	
	local hand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(handIndex)	

	if handIndex == 0 then
		leftHandFull = false
	else
		rightHandFull = false
	end

	if itemTable["item_name"] == thisEntity:GetName() then
	
		holdingThisBow = false
		
		if arrowNocked then
			HideGlow()
			if IsValidEntity(nockedArrow) then
				nockedArrow:Kill()
			end
			heldArrow:SetAbsScale(1)
			arrowNocked = false
		end
		
		if arrowShouldered then
			if IsValidEntity(shoulderArrow) then
				shoulderArrow:Kill()
			end
			arrowShouldered = false
		end
		
		-- scale the damage blocker back down again
		
		if IsValidEntity(bowDropPrevention) then
			bowDropPrevention:SetAbsScale(0.01)
		end
		
		-- angles reset so the bow isn't in an awkward state
		
		if IsValidEntity(bowUpperBody) then
			bowUpperBody:SetLocalAngles(0,0,0)
		end
		
		if IsValidEntity(bowMidBody) then
			bowMidBody:SetLocalAngles(0,0,0)
		end

		if IsValidEntity(bowLowerBody) then
			bowLowerBody:SetLocalAngles(0,0,0)
		end
	
		local notchId = thisEntity:ScriptLookupAttachment("Notch") 
		local notchPos = thisEntity:GetAttachmentOrigin(notchId)
	
		UpdateBowString(notchPos)
		
		if backpackDisabled then
			EnableBackpack()
		end
		
		HideHints()
		
	elseif string.match(itemTable["item_name"], "Arrow") then
	
		if IsValidEntity(arrowHand) then
			local closestArrow = Entities:FindByClassnameNearest("prop_physics", arrowHand:GetAbsOrigin(), 30)
			
			if closestArrow and IsValidEntity(closestArrow) then		
				
				if holdingArrow then
					holdingArrow = false
					if arrowNocked then
						HideGlow()
						nockedArrow:Kill()
					end
					
					if needsToShowHint and holdingThisBow then
						if not arrowNocked or drawFrac < 0.1 then
							ShowDrawHint()
						end
					end
				end
				
				DoEntFire(itemTable["item_name"], "CallScriptFunction", "Dropped",  0.0, nil, nil)
				
			end
		end
	
	else

		if not leftHandFull or not rightHandFull then
			if holdingThisBow and not backpackDisabled then
				DisableBackpack()
			end
		end
	end
end

function OnStore(itemTable)

	-- bow can be pocketed, attached entities are scaled down to hide

	if not IsValidEntity(thisEntity) then
		return nil
	end

	if itemTable["item_name"] == thisEntity:GetName() then
	
		bowUpperBody:SetAbsScale(0.001)
		bowLowerBody:SetAbsScale(0.001)
		bowMidBody:SetAbsScale(0.001)
		bowReticule:SetAbsScale(0.001)
		bowLowerString:SetAbsScale(0.001)
		bowUpperString:SetAbsScale(0.001)
		bowLowerStringBase:SetAbsScale(0.001)
		bowUpperStringBase:SetAbsScale(0.001)
		inAPocket = true
		HideHints()
		
	else
	
		-- stored something else, check if the bow is still in a pocket
	
		local hand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(0)

		local children = hand:GetChildren()
		for idx, child in pairs(children) do
			if child == thisEntity then
				return nil
			end
		end
		
		hand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1)

		children = hand:GetChildren()
		for idx, child in pairs(children) do
			if child == thisEntity then
				return nil
			end
		end
		
		-- pocketed bow has been replaced, scale it back up
		
		thisEntity:SetThink(OnRetrieve, "retrieve", 0.25)		
	end
end

function OnRetrieve()

	if not IsValidEntity(thisEntity) then
		return nil
	end
	
	-- bow is removed from pocket, scale entities back up

	bowUpperBody:SetAbsScale(1)
	bowLowerBody:SetAbsScale(1)
	bowMidBody:SetAbsScale(1)
	bowReticule:SetAbsScale(1)
	bowLowerString:SetAbsScale(1)
	bowUpperString:SetAbsScale(1)
	bowLowerStringBase:SetAbsScale(1)
	bowUpperStringBase:SetAbsScale(1)
	inAPocket = false
	
	return nil
end

function Destroy()
	if not holdingThisBow then
		ForceDestroyEntities()
	end
end

function ForceDestroyEntities()

	-- when this bow dies, any created entites are (hopefully) cleaned up too

	if IsValidEntity(arrowBowCollision) then
		arrowBowCollision:Kill();
	end
	
	if IsValidEntity(arrowDropPreventionCollision) then
		arrowDropPreventionCollision:Kill();
	end
	
	if IsValidEntity(bowEnableBackpack) then
		bowEnableBackpack:Kill();
	end
	
	if IsValidEntity(bowDisableBackpack) then
		bowDisableBackpack:Kill();
	end
	
	if IsValidEntity(bowDrawHint) then
		bowDrawHint:Kill();
	end
	
	if IsValidEntity(bowNockHint) then
		bowNockHint:Kill();
	end
	
	thisEntity:Kill()
end

function EnableBackpack()
	if IsValidEntity(bowEnableBackpack) then
		backpackDisabled = false
		DoEntFire(bowEnableBackpack:GetName(), "EquipNow", "",  0.0, nil, nil)
	end
end

function DisableBackpack()
	if IsValidEntity(bowDisableBackpack) then
		backpackDisabled = true
		DoEntFire(bowDisableBackpack:GetName(), "EquipNow", "",  0.0, nil, nil)
	end
end

function ShowGlow()

	-- arrows have a light at thier tip, showing and hiding this swaps the glow between the held arrow and nocked arrow

	if not glowEffect then
		glowEffect = ParticleManager:CreateParticle("particles/arrowglow.vpcf", PATTACH_POINT_FOLLOW, thisEntity)
		ParticleManager:SetParticleControlEnt(glowEffect, 0, nockedArrow, PATTACH_POINT_FOLLOW, "Tip", nockedArrow:GetAbsOrigin(), false)
	end
	
	if IsValidEntity(heldArrow) then
		local scope = heldArrow:GetPrivateScriptScope()
		if scope and scope.HideGlow then
			heldArrow:GetOrCreatePrivateScriptScope():HideGlow()
		end
	end
end

function HideGlow()
	if glowEffect then
		ParticleManager:DestroyParticle(glowEffect, false)
		glowEffect = nil
	end
	
	if IsValidEntity(heldArrow) then
		local scope = heldArrow:GetPrivateScriptScope()
		if scope and scope.HideGlow then
			heldArrow:GetOrCreatePrivateScriptScope():ShowGlow()
		end
	end
end

function ShowDrawHint()
	
	-- this hint tells the player to grab arrows
	
	if IsValidEntity(bowNockHint) then
		DoEntFire(bowNockHint:GetName(), "EndHint", "",  0.0, nil, nil)
	end
	
	if IsValidEntity(hintArrow) then
		hintArrow:Kill()
	end
	
	if hintEffect then
		ParticleManager:DestroyParticle(hintEffect, false)
		hintEffect = nil
	end
	
	if not IsValidEntity(bowDrawHint) then
		local keyvals = vlua.clone(BOW_DRAW_HINT_KEYVALS)
		bowDrawHint = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
	end

	DoEntFire(bowDrawHint:GetName(), "ShowHint", "",  0.0, nil, nil)
end

function ShowNockHint()
	
	-- this hint tells the player to nock the held arrow
	
	if IsValidEntity(bowDrawHint) then
		DoEntFire(bowDrawHint:GetName(), "EndHint", "",  0.0, nil, nil)
	end
	
	-- an arrow and some particles indicate where the held arrow should go
	
	if not IsValidEntity(hintArrow) then
		local keyvals = vlua.clone(HINT_ARROW_KEYVALS)
		hintArrow = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
		hintArrow:SetParent(bowUpperBody, "")
	end
		
	local notchId = thisEntity:ScriptLookupAttachment("Notch") 
	local notchPos = thisEntity:GetAttachmentOrigin(notchId)
	
	local localNotchPos = thisEntity:TransformPointWorldToEntity(notchPos)
	
	local hintArrowPos = Vector(localNotchPos.x - 2, -0.2, 0)
	local hintArrowAngle = 7
	
	if bowHand == Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1) then
		hintArrowPos = Vector(localNotchPos.x - 2, 0.2, 0)
		hintArrowAngle = -7
	end

	hintArrow:SetLocalAngles(0, hintArrowAngle, 0)
	hintArrow:SetLocalOrigin(hintArrowPos)
	
	if not hintEffect then
		hintEffect = ParticleManager:CreateParticle("particles/arrowholo.vpcf", PATTACH_POINT_FOLLOW, hintArrow)
		ParticleManager:SetParticleControlEnt(hintEffect, 0, hintArrow, PATTACH_POINT_FOLLOW, "Mid", Vector(0, 0, 0), false)
	end

	if not IsValidEntity(bowNockHint) then
		local keyvals = vlua.clone(BOW_NOCK_HINT_KEYVALS)
		bowNockHint = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
	end
	
	DoEntFire(bowNockHint:GetName(), "ShowHint", "",  0.0, nil, nil)
end

function HideHints()

	if IsValidEntity(bowDrawHint) then
		bowDrawHint:Kill()
	end

	if IsValidEntity(bowNockHint) then
		bowNockHint:Kill()
	end
	
	if hintEffect then
		ParticleManager:DestroyParticle(hintEffect, true)
		hintEffect = nil
	end
	
	if IsValidEntity(hintArrow) then
		hintArrow:Kill()
	end
end

function BowThink()

	if not IsValidEntity(thisEntity) then
		return nil
	end

	if not holdingThisBow then
		return THINK_INTERVAL
	end
	
	local handIndex = 1
	if bowHand == Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1) then
		handIndex = 0
	end
	
	local handsFull = leftHandFull and rightHandFull
	
	-- Spin the sight to the side of the bow that is being used
	
	if IsValidEntity(bowReticule) then
		local reticuleCurrentRoll = bowReticule:GetLocalAngles().z
		if handIndex == 0 then
			if reticuleCurrentRoll + THINK_INTERVAL * 800 < 180 then
				bowReticule:SetLocalAngles(1, 0, reticuleCurrentRoll + THINK_INTERVAL * 800)
			else
				bowReticule:SetLocalAngles(1, 0, 180)
			end
		else
			if reticuleCurrentRoll - THINK_INTERVAL * 800 > 0 then
				bowReticule:SetLocalAngles(1, 0, reticuleCurrentRoll - THINK_INTERVAL * 800)
			else
				bowReticule:SetLocalAngles(1, 0, 0)
			end
		end
	end

	if not holdingArrow and not arrowNocked and not handsFull
	then
		
		-- check for the player reaching over shoulder, spawn an arrow if so
	
		local handIndex = 1
		if bowHand == Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1) then
			handIndex = 0
		end
		
		local arrowHand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(handIndex)

		local localHandGrabStart = arrowHand:TransformPointEntityToWorld(Vector(0, 0, -3))
		local localHandGrabEnd = arrowHand:TransformPointEntityToWorld(Vector(10, 0, -15))
		local localHandGrabDir = (localHandGrabEnd - localHandGrabStart):Normalized()
	
		local arrowHandAng = VectorToAngles(localHandGrabDir)
		
		local localHandToView = Entities:GetLocalPlayer():TransformPointWorldToEntity(localHandGrabStart)
		
		local playerBackwardDir = -Entities:GetLocalPlayer():GetForwardVector()
	
		-- player z is wonky, use the eye z instead
	
		localHandToView.z = localHandGrabStart.z - Entities:GetLocalPlayer():EyePosition().z
		
		-- change the required angle based on how far behind the shoulder the hand is
		
		local AngThresholdLerp = Clamp(localHandToView.x, SHOULDER_POSTHRESHOLD_MIN, SHOULDER_POSTHRESHOLD_MAX)
		
		AngThresholdLerp = (SHOULDER_POSTHRESHOLD_MAX - AngThresholdLerp) / (SHOULDER_POSTHRESHOLD_MAX - SHOULDER_POSTHRESHOLD_MIN)
		
		AngThreshold = Lerp(AngThresholdLerp, SHOULDER_ANGTHRESHOLD_MIN, SHOULDER_ANGTHRESHOLD_MAX)
		
		if localHandGrabDir:Dot(playerBackwardDir) > AngThreshold and localHandToView.x < SHOULDER_POSTHRESHOLD_MIN and localHandToView.z > SHOULDER_HEIGHTTHRESHOLD then
			
			if not arrowShouldered then
				
				-- spawn an arrow to follow the hand and priemtivley scale it down to avoid collisions
				
				SpawnShoulderArrow()
				
				shoulderArrow:SetAbsOrigin(localHandGrabStart)
				shoulderArrow:SetAngles(arrowHandAng.x + 90, arrowHandAng.y, arrowHandAng.z)
				
				shoulderArrow:SetParent(arrowHand, "")
				
				shoulderArrow:SetAbsScale(0.05)
				
				shoulderArrowBehind = true
				
				PlayShoulderArrowFeedback()
			end
			
		elseif arrowShouldered then
			shoulderArrow:Kill()
			arrowShouldered = false
			shoulderArrowBehind = false
			arrowHand:FireHapticPulse(0)
		end

	end

	if not heldArrow or not IsValidEntity(heldArrow) then
		return THINK_INTERVAL
	end

	local notchId = thisEntity:ScriptLookupAttachment("Notch") 
	local notchPos = thisEntity:GetAttachmentOrigin(notchId)
	
	local railID = bowUpperBody:ScriptLookupAttachment("LeftRail")
	if bowHand == Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1) then
		railID = bowUpperBody:ScriptLookupAttachment("RightRail")
	end
	
	local railPos = bowUpperBody:GetAttachmentOrigin(railID)	

	if arrowNocked and not holdingArrow
	then
		-- at this point the arrow is released, fire it
	
		if Time() > drawTime + DRAW_FIRE_DELAY
		then
			needsToFire = true
			
			-- doing this immediatley kinda broke stuff, a short delay works fine
			
			thisEntity:SetThink(FireThink, "fire_think", 0.01)
			
			arrowHand:FireHapticPulse(2)
			bowHand:FireHapticPulse(1)
			
			-- tutorial needs to play again in the event of an initial misfire
			
			local misfire = false
			
			if drawFrac > 0.9 then
				StartSoundEventFromPosition("sound.fire_arrow_strong", notchPos)
			elseif drawFrac > 0.7 then
				StartSoundEventFromPosition("sound.fire_arrow", notchPos)
			elseif drawFrac > 0.1 then
				StartSoundEventFromPosition("sound.fire_arrow_weak", notchPos)
			else
				StartSoundEventFromPosition("sound.drop_arrow", notchPos)
				misfire = true
			end
			
			if needsToShowHint and not misfire then
				needsToShowHint = false
			end
			
		else
			-- drop arrow if drawn too quickly
			heldArrow:SetAbsScale(1)
			heldArrow:SetParent(nil, "")
		end	
		arrowNocked = false
		
		return THINK_INTERVAL
		
	elseif not arrowNocked and holdingArrow then

		-- if we are holding the shoulder arrow, make it real small if it's still behind us
		
		if heldArrow == shoulderArrow and shoulderArrowBehind then
		
			local handIndex = 1
			if bowHand == Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1) then
				handIndex = 0
			end
			
			local arrowHand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(handIndex)

			local localHandGrabStart = arrowHand:TransformPointEntityToWorld(Vector(0, 0, -3))
			local localHandGrabEnd = arrowHand:TransformPointEntityToWorld(Vector(10, 0, -15)) --10
			local localHandGrabDir = (localHandGrabEnd - localHandGrabStart):Normalized()
			
			local localHandToView = Entities:GetLocalPlayer():TransformPointWorldToEntity(localHandGrabStart)
			
			local playerBackwardDir = -Entities:GetLocalPlayer():GetForwardVector()	
		
			if localHandGrabDir:Dot(playerBackwardDir) < -0.1 and localHandToView.x > -1 then
				heldArrow:SetAbsScale(1)
				shoulderArrowBehind = false
			else
				heldArrow:SetAbsScale(0.01)
			end
		end
		
		---
		
		
		-- figure out the arrow position relative to the notch
		
		local bowVec = (railPos - notchPos):Normalized()
		local arrowVec = heldArrow:GetForwardVector()
		
		local localnotchPos = thisEntity:TransformPointWorldToEntity(notchPos)
		local localarrowPos = thisEntity:TransformPointWorldToEntity(heldArrow:GetAbsOrigin()) - localnotchPos
		
		local arrowDrawLength = VectorDistance(railPos, heldArrow:GetAbsOrigin())
		
		local xArrowDist = abs(localarrowPos.x)
		
		local yzlocalArrowPos = Vector(0, localarrowPos.y, localarrowPos.z)
		local yzArrowDist = yzlocalArrowPos:Length()
		
		local angleVec = bowVec
		
		-- people were having trouble nocking arrows so rotating the bow to meet the arrow when it gets close helps
		
		local snapAssistDist = Clamp(localarrowPos:Length(), 0, 10) / 10
		
		local snapAssistLerp = 1 - snapAssistDist
		
		if snapAssistLerp > 0 then
			
			local snapAssistAng = angleVec:Dot(arrowVec)
			
			snapAssistLerp = snapAssistLerp * snapAssistAng
			
			---
			
			local localarrowPos = thisEntity:TransformPointWorldToEntity(heldArrow:GetAbsOrigin())
			local localrailPos = thisEntity:TransformPointWorldToEntity(railPos)
			
			local xylocalArrowPos = Vector(localarrowPos.x, localarrowPos.y, 0)
			
			local xylocalRailPos = Vector(localrailPos.x, localrailPos.y, 0)
			
			local xylocaldrawVec = (xylocalRailPos - xylocalArrowPos)
			
			local xylocaldrawAng = VectorToAngles(xylocaldrawVec)
			
			local clampedDrawAng = QAngle(0, xylocaldrawAng.y, 0)
			
			local localDrawVec = AnglesToVector(clampedDrawAng)
			
			local worldDrawVec = (localDrawVec.x * thisEntity:GetForwardVector()) - (localDrawVec.y * thisEntity:GetRightVector()) 
			
			local drawLength = VectorDistance(railPos, notchPos)
			
			local nockedArrowPos = railPos - (worldDrawVec:Normalized() * (drawLength + ARROW_HAND_OFFSET))
			
			
			-- find local position of new arrow loc in relation to the new rotation
			
			local xyrotatedxvector = nockedArrowPos - railPos
			
			local xzlocalArrowPos = Vector(xyrotatedxvector:Length(), 0, localarrowPos.z)

			local xzlocalRailPos = Vector(0, 0, localrailPos.z)

			local xzlocaldrawVec = (xzlocalRailPos - xzlocalArrowPos)
			
			local xzlocaldrawAng = VectorToAngles(xzlocaldrawVec)

			
			if xzlocaldrawAng.x < 90 and xzlocaldrawAng.x > 45 then
				xzlocaldrawAng.x = 45
			elseif xzlocaldrawAng.x > 270 and xzlocaldrawAng.x < 315 then
				xzlocaldrawAng.x = 315
			end
			
			if xylocaldrawAng.y > 180 and xylocaldrawAng.y < 270 then
				xylocaldrawAng.y = 270
			elseif xylocaldrawAng.y < 180 and xylocaldrawAng.y > 90 then
				xylocaldrawAng.y = 90
			end
			
			if xylocaldrawAng.y > 180 then
				xylocaldrawAngY = Lerp(1 - snapAssistLerp, xylocaldrawAng.y - 360, 0)
			else
				xylocaldrawAngY = Lerp(snapAssistLerp, 0, xylocaldrawAng.y)
			end
			
			if xzlocaldrawAng.x > 180 then
				xzlocaldrawAngX = Lerp(1 - snapAssistLerp, xzlocaldrawAng.x - 360, 0)
			else
				xzlocaldrawAngX = Lerp(snapAssistLerp, 0, xzlocaldrawAng.x)
			end
			
			bowUpperBody:SetLocalAngles(xzlocaldrawAngX, xylocaldrawAngY, 0)
			bowMidBody:SetLocalAngles(0, xylocaldrawAngY, 0)
			bowLowerBody:SetLocalAngles(xzlocaldrawAngX, xylocaldrawAngY, 0)		

			
			local clampedDrawAng = QAngle(xzlocaldrawAngX, xylocaldrawAngY, 0)
			
			local localDrawVec = AnglesToVector(clampedDrawAng)
			
			local worldDrawVec = (localDrawVec.x * thisEntity:GetForwardVector()) + (localDrawVec.z * thisEntity:GetUpVector()) - (localDrawVec.y * thisEntity:GetRightVector()) 
			
			local nockedStringPos = railPos - (worldDrawVec:Normalized() * (drawLength + 1))
			
			UpdateBowString(nockedStringPos)
			
			---
			
			xArrowDist = (worldDrawVec:Normalized() * (arrowDrawLength - drawLength + ARROW_HAND_OFFSET)):Length()
			yzArrowDist = (nockedStringPos - heldArrow:GetAbsOrigin()):Length() / 5 -- fudge this value with xyz, seems to work ok
			angleVec = (railPos - heldArrow:GetAbsOrigin()):Normalized()
			
			---
		else
			bowUpperBody:SetLocalAngles(0, 0, 0)
			bowMidBody:SetLocalAngles(0, 0, 0)
			bowLowerBody:SetLocalAngles(0, 0, 0)	
			
			UpdateBowString(notchPos)
		end		
		
		-- snap arrow if close enough
		
		-- measure the speed of the held arrow, increase thresholds if needed
		
		local arrowSpeed = VectorDistance(heldArrow:GetAbsOrigin(), lastArrowPos) / THINK_INTERVAL
		
		local arrowSpeedLerp = Clamp(arrowSpeed, 0, 100) / 100
		
		lastArrowPos = heldArrow:GetAbsOrigin()
		
		local speedScaled = (20^(arrowSpeedLerp - 1))
		
		local snapXPosThreshold = Lerp(speedScaled, SNAP_XPOSTHRESHOLD_MIN, SNAP_XPOSTHRESHOLD_MAX)
		local snapYZPosThreshold = Lerp(speedScaled, SNAP_YZPOSTHRESHOLD_MIN, SNAP_YZPOSTHRESHOLD_MAX)
		local snapAngleThreshold = Lerp(speedScaled, SNAP_ANGTHRESHOLD_MIN, SNAP_ANGTHRESHOLD_MAX)

		if xArrowDist < snapXPosThreshold and yzArrowDist < snapYZPosThreshold and angleVec:Dot(arrowVec) > snapAngleThreshold then
		
			-- arrow is close enough, scale it down to hide it and create a new nocked arrow in its place
		
			heldArrow:SetAbsScale(0.01)
			SpawnNockedArrow()
			arrowNocked = true
			drawTime = Time()
			drawFrac = 0
			
			HideHints()
			
			if IsValidEntity(arrowBowCollision) then
				DoEntFire(arrowBowCollision:GetName(), "DisableCollisionsWith", heldArrow:GetName(),  0.0, nil, nil)
			end
			
			bowHand:FireHapticPulse(0)
			arrowHand:FireHapticPulse(1)
			
			StartSoundEvent("sound.notch_arrow", thisEntity)	
		end
	
	elseif not arrowNocked and not holdingArrow then
		bowUpperBody:SetLocalAngles(0,0,0)
		bowMidBody:SetLocalAngles(0,0,0)
		bowLowerBody:SetLocalAngles(0,0,0)
	
		UpdateBowString(notchPos)
	end
	
	if arrowNocked and holdingArrow
	then	
			
		-- arrow is nocked and the player is aiming the bow
			
		local drawVec = (railPos - heldArrow:GetAbsOrigin())
		local drawLength = drawVec:Length() - ARROW_HAND_OFFSET	
		
		if drawLength < DRAW_MIN
		then
			drawLength = DRAW_MIN
		end
		
		if drawLength > DRAW_MAX
		then
			drawLength = DRAW_MAX
		end
	
		local newDrawFrac = abs((drawLength - DRAW_MIN) / (DRAW_MAX - DRAW_MIN))
		
		-- fire haptics and play sounds at exponential intervals
		
		for i=1,20 do
			if drawFrac < HAPTIC_BUMPS[i] and newDrawFrac >= HAPTIC_BUMPS[i] or drawFrac >= HAPTIC_BUMPS[i] and newDrawFrac < HAPTIC_BUMPS[i] then
				arrowHand:FireHapticPulse(1)
				bowHand:FireHapticPulse(0)
				
				local upperNotchId = bowUpperBody:ScriptLookupAttachment("UpperNotch") 
				local upperNotchPos = bowUpperBody:GetAttachmentOrigin(upperNotchId)
				
				local lowerNotchId = bowLowerBody:ScriptLookupAttachment("LowerNotch") 
				local lowerNotchPos = bowLowerBody:GetAttachmentOrigin(lowerNotchId)

				PlayStringSound(drawFrac, upperNotchPos)
				PlayStringSound(drawFrac, lowerNotchPos)
			end
		end
		
		-- play heavy feedback on first reaching max draw, repeated smaller ones when held after
		
		if newDrawFrac >= 1 then
			if drawFrac < 1 then
				bowHand:FireHapticPulse(1)
				arrowHand:FireHapticPulse(2)
			else
				arrowHand:FireHapticPulse(0)
			end
		end
		
		drawFrac = newDrawFrac


		-- now for some fun rotations

		local localarrowPos = thisEntity:TransformPointWorldToEntity(heldArrow:GetAbsOrigin())
		local localrailPos = thisEntity:TransformPointWorldToEntity(railPos)
		
		local xylocalArrowPos = Vector(localarrowPos.x, localarrowPos.y, 0)
		
		local xylocalRailPos = Vector(localrailPos.x, localrailPos.y, 0)
		
		local xylocaldrawVec = (xylocalRailPos - xylocalArrowPos)
		
		
		if xylocaldrawVec:Length() < 3 then
			
			-- un-nock the arrow if the hand is too close to the bow
			
			arrowNocked = false
			HideGlow()
			nockedArrow:Kill()
			heldArrow:SetAbsScale(1)
			
			if IsValidEntity(arrowBowCollision) then
				DoEntFire(arrowBowCollision:GetName(), "EnableCollisions", "",  0.0, nil, nil)
			end

			StartSoundEvent("sound.notch_arrow", thisEntity)

			return THINK_INTERVAL
		end
		
		local xylocaldrawAng = VectorToAngles(xylocaldrawVec)
		
		local clampedDrawAng = QAngle(0, xylocaldrawAng.y, 0)
		
		local localDrawVec = AnglesToVector(clampedDrawAng)
		
		local worldDrawVec = (localDrawVec.x * thisEntity:GetForwardVector()) - (localDrawVec.y * thisEntity:GetRightVector()) 
		
		local nockedArrowPos = railPos - (worldDrawVec:Normalized() * (drawLength + ARROW_HAND_OFFSET))
		
		-- find local position of new arrow loc in relation to the new rotation
		
		local xyrotatedxvector = nockedArrowPos - railPos
		
		local xzlocalArrowPos = Vector(xyrotatedxvector:Length(), 0, localarrowPos.z)

		local xzlocalRailPos = Vector(0, 0, localrailPos.z)

		local xzlocaldrawVec = (xzlocalRailPos - xzlocalArrowPos)
		
		local xzlocaldrawAng = VectorToAngles(xzlocaldrawVec)

		
		if xzlocaldrawAng.x < 90 and xzlocaldrawAng.x > 45 then
			xzlocaldrawAng.x = 45
		elseif xzlocaldrawAng.x > 270 and xzlocaldrawAng.x < 315 then
			xzlocaldrawAng.x = 315
		end
		

		nockedArrow:SetLocalAngles(xzlocaldrawAng.x, xylocaldrawAng.y, 0)
		nockedArrowAngles = nockedArrow:GetAngles()
		
		
		bowUpperBody:SetLocalAngles(xzlocaldrawAng.x, xylocaldrawAng.y, 0)
		bowMidBody:SetLocalAngles(0, xylocaldrawAng.y, 0)
		bowLowerBody:SetLocalAngles(xzlocaldrawAng.x, xylocaldrawAng.y, 0)		
		
		
		
		local clampedDrawAng = QAngle(xzlocaldrawAng.x, xylocaldrawAng.y, 0)
		
		local localDrawVec = AnglesToVector(clampedDrawAng)
		
		
		local worldDrawVec = (localDrawVec.x * thisEntity:GetForwardVector()) + (localDrawVec.z * thisEntity:GetUpVector()) - (localDrawVec.y * thisEntity:GetRightVector()) 

		
		local newnockedArrowPos = railPos - (worldDrawVec:Normalized() * (drawLength + ARROW_HAND_OFFSET))

		nockedArrowPos = newnockedArrowPos
		
		
		nockedArrow:SetAbsOrigin(nockedArrowPos)
		nockedArrowOrigin = nockedArrowPos
		
		
		local nockedStringPos = railPos - (worldDrawVec:Normalized() * (drawLength + 1))
		
		UpdateBowString(nockedStringPos)
	end
	
	return THINK_INTERVAL
end

function RemoveQuiver()

	-- I added a quiver to give some context to the infinite arrows in the backpack

	if IsValidEntity(bowQuiver) then
		bowQuiver:Kill()
		local quiverLocation = Entities:GetLocalPlayer():EyePosition() - (Entities:GetLocalPlayer():GetForwardVector() * 10) - Vector(0,0,10)
		StartSoundEventFromPosition("sound.equip_arrows", quiverLocation)
		
		if not holdingArrow and needsToShowHint then
			ShowDrawHint()
		end
	end
end

function PlayStringSound(drawFrac, notchPos)
	
	-- This is terrible but I don't know how to change audio pitch outside of .vsndevts
	
	if drawFrac < 0.1 then StartSoundEventFromPosition("sound.draw_arrow_Pitch1", notchPos)
	elseif drawFrac < 0.2 then StartSoundEventFromPosition("sound.draw_arrow_Pitch2", notchPos)
	elseif drawFrac < 0.3 then StartSoundEventFromPosition("sound.draw_arrow_Pitch3", notchPos)
	elseif drawFrac < 0.4 then StartSoundEventFromPosition("sound.draw_arrow_Pitch4", notchPos)
	elseif drawFrac < 0.5 then StartSoundEventFromPosition("sound.draw_arrow_Pitch5", notchPos)
	elseif drawFrac < 0.6 then StartSoundEventFromPosition("sound.draw_arrow_Pitch6", notchPos)
	elseif drawFrac < 0.7 then StartSoundEventFromPosition("sound.draw_arrow_Pitch7", notchPos)
	elseif drawFrac < 0.8 then StartSoundEventFromPosition("sound.draw_arrow_Pitch8", notchPos)
	elseif drawFrac < 0.9 then StartSoundEventFromPosition("sound.draw_arrow_Pitch9", notchPos)
	else StartSoundEventFromPosition("sound.draw_arrow_Pitch10", notchPos)
	end
end

function UpdateBowString(targetLocation)

	-- the string works by scaling the top and bottom pieces to meet the tips of the bow arms

	if IsValidEntity(bowUpperString) and IsValidEntity(bowLowerString) and IsValidEntity(bowUpperStringBase) and IsValidEntity(bowLowerStringBase)  then
		local notchId = thisEntity:ScriptLookupAttachment("Notch") 
		local notchPos = thisEntity:GetAttachmentOrigin(notchId)

		local upperNotchId = bowUpperBody:ScriptLookupAttachment("UpperNotch") 
		local upperNotchPos = bowUpperBody:GetAttachmentOrigin(upperNotchId)

		local upperNotchInitVector = upperNotchPos - notchPos
		local upperNotchVector = upperNotchPos - targetLocation
		local upperNotchAngle = VectorToAngles(upperNotchVector)

		bowUpperString:SetAbsOrigin(targetLocation)
		bowUpperString:SetAbsAngles(upperNotchAngle.x + 90, upperNotchAngle.y, upperNotchAngle.z)
		bowUpperString:SetAbsScale(upperNotchVector:Length() / upperInitialStringLength)
		
		bowUpperStringBase:SetAbsOrigin(targetLocation)
		bowUpperStringBase:SetAbsAngles(upperNotchAngle.x + 90, upperNotchAngle.y, upperNotchAngle.z)

		local lowerNotchId = bowLowerBody:ScriptLookupAttachment("LowerNotch")
		local lowerNotchPos = bowLowerBody:GetAttachmentOrigin(lowerNotchId)
			
		local lowerNotchInitVector = lowerNotchPos - notchPos
		local lowerNotchVector = lowerNotchPos - targetLocation
		local lowerNotchAngle = VectorToAngles(lowerNotchVector)

		bowLowerString:SetAbsOrigin(targetLocation)
		bowLowerString:SetAbsAngles(lowerNotchAngle.x - 90, lowerNotchAngle.y, lowerNotchAngle.z)
		bowLowerString:SetAbsScale(lowerNotchVector:Length() / lowerInitialStringLength)
		
		bowLowerStringBase:SetAbsOrigin(targetLocation)
		bowLowerStringBase:SetAbsAngles(lowerNotchAngle.x - 90, lowerNotchAngle.y, lowerNotchAngle.z)
	end
end

function SpawnNockedArrow()
	local keyvals = vlua.clone(NOCKED_ARROW_KEYVALS)
	keyvals.targetname = DoUniqueString(keyvals.targetname)
	nockedArrow = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
	nockedArrow:SetParent(thisEntity, "")
	nockedArrow:SetLocalOrigin(Vector(0,0,0))
	nockedArrow:SetLocalAngles(0, 0, 0)
	ShowGlow()
end

function SpawnShoulderArrow()
	arrowShouldered = true
	local keyvals = vlua.clone(SHOULDER_ARROW_KEYVALS)
	keyvals.targetname = DoUniqueString("Arrow")
	shoulderArrow = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
end

function PlayShoulderArrowFeedback()
	if shoulderArrowBehind then
	
		local handIndex = 1
		if bowHand == Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(1) then
			handIndex = 0
		end
		
		local feedbackHand = Entities:GetLocalPlayer():GetHMDAvatar():GetVRHand(handIndex)
		
		if IsValidEntity(feedbackHand) then
			local fingerPos = feedbackHand:TransformPointEntityToWorld(Vector(0, 0, -3))
			StartSoundEventFromPosition("sound.reach_arrow", fingerPos)
			feedbackHand:FireHapticPulse(1)
		end
	end
	
	return nil
end

function FireThink()

	FireArrow()
	return nil
end

function FireArrow()

	if not needsToFire then
		return nil
	end
	
	needsToFire = false
	
	DoEntFire("CollisionPair_BowArrow", "DisableCollisionsWith", heldArrow:GetName(),  0.0, nil, nil)
	
	heldArrow:SetAbsScale(1)
	heldArrow:SetAbsAngles(nockedArrowAngles.x, nockedArrowAngles.y, nockedArrowAngles.z)
	heldArrow:SetOrigin(nockedArrowOrigin)

	local scope = heldArrow:GetPrivateScriptScope()
	if scope then
		if scope.StartFlight then
			heldArrow:GetOrCreatePrivateScriptScope():StartFlight(thisEntity, nockedArrow)
		end		
	end
	
	-- arrow speed is scaled exponentially
	
	local vecScaled = (1.3^drawFrac) - 1
	
	heldArrow:ApplyAbsVelocityImpulse((AnglesToVector(nockedArrowAngles) * 10000 * vecScaled) - GetPhysVelocity(heldArrow))
	
	-- if the player fires an arrow with hand behind the shoulder, they would miss the haptic feedback
	
	thisEntity:SetThink(PlayShoulderArrowFeedback, "late_feedback", 0.2)
end