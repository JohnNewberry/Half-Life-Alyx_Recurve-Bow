
-- these are a list of all skeleton attachments arrows can attach to
-- attaching to alive enemies lagged behind and broke when they died so I disabled this

-- also, if one of these exists on a hit model then its entity is treated as an enemy - there is probably a better way to do this
-- this means ragdolls are treaded as enemies too

local validAttachments = {
"eyes",
"center",
"chest",
"root_attachment",
"eye",
"abdomen",
"TongueRoot"
}

-- The distance to these attachments determines extra damage

local validHeadshotAttachments = {
"eyes",
"eye"
}

-- properties

local holdingBow = false
local holdingArrow = false

local inFlight = false

local canDecay = false
local restartDecay = false
local decaying = false

local lastUsedBow = nil
local lastNockedArrow = nil

local arrowConstraint = nil
local arrowConstraintAnchor = nil

local hasAttachment = false
local attachedEntity = nil

local startLoc

local hitParent = nil
local hitLoc
local hitFwd

local attachedArrow = nil
local trailEffect = nil
local glowEffect = nil

local needsConstraint = false

-- config

local THINK_INTERVAL = 0.01
local ARROW_LENGTH = 30
local ARROW_HULL_SIZE = 0.8
local DECAY_TIME = 15
local HEADSHOT_DISTANCE = 18
local HEADSHOT_MULTIPLIER = 2.5
local ATTACHMENT_LIMIT = 1

local ATTACH_ARROW_KEYVALS = {
	classname = "prop_physics";
	targetname = "arrow";
	model = "models/arrows/arrow1.vmdl";
	vscripts = "ObjectArrow";
	carrytype_override = "CARRY_TYPE_1H_RIGID"
}

local ARROW_CONSTRAINT_KEYVALS = {
	classname = "phys_constraint";
	targetname = "rigid_constraint";
	attach1 = "";
	attach2 = "";
	enablelinearconstraint = 1;
	enableangularconstraint = 1;
	spawnflags = "1"
}

local ARROW_CONSTRAINT_ANCHOR_KEYVALS = {
	classname = "prop_dynamic";
	targetname = "rigid_constraint_anchor";
	model = "models/arrows/constraint_anchor.vmdl"
}

function Precache(context)
	PrecacheModel(ATTACH_ARROW_KEYVALS.model, context)
	PrecacheModel(ARROW_CONSTRAINT_ANCHOR_KEYVALS.model, context)
end

function Activate()
	ShowGlow()
end

function ShowGlow()
	if not glowEffect then
		glowEffect = ParticleManager:CreateParticle("particles/arrowglow.vpcf", PATTACH_POINT_FOLLOW, thisEntity)
		ParticleManager:SetParticleControlEnt(glowEffect, 0, thisEntity, PATTACH_POINT_FOLLOW, "Tip", thisEntity:GetAbsOrigin(), false) 
	end
end

function HideGlow()
	if glowEffect then
		ParticleManager:DestroyParticle(glowEffect, false)
		glowEffect = nil
	end
end

function StartFlight(usedBow, nockedArrow)
	lastUsedBow = usedBow
	lastNockedArrow = nockedArrow
	inFlight = true
	startLoc = thisEntity:GetAbsOrigin()
	thisEntity:SetThink(ArrowThink, "arrow_think", 0)
end

function SetupAttachment(constraint, anchor)
	
	if IsValidEntity(constraint) then
		arrowConstraint = constraint
	end
	
	if IsValidEntity(anchor) then
		arrowConstraintAnchor = anchor
	end
	
	StartDecay()
	
	hasAttachment = true
end

function HasSameAttachment(attachment)
	if attachment then
		return attachment == attachedEntity
	end
	return false
end

function EnforceAttachmentLimit(newAttachEntity)
	
	-- ragdolls were really messing up when I attached a bunch or arrows to them at the same time
	-- here is where I limit the number or arrows attached to the same one
	
	attachedEntity = newAttachEntity
	
	local attachmentAmount = 1

	for i, otherArrow in pairs(Entities:FindAllByModel("models/arrows/arrow1.vmdl")) do
		if otherArrow ~= thisEntity and VectorDistance(thisEntity:GetAbsOrigin(), otherArrow:GetAbsOrigin()) < 1500 then
			local scope = otherArrow:GetPrivateScriptScope()
			if scope and scope.HasSameAttachment and otherArrow:GetOrCreatePrivateScriptScope():HasSameAttachment(attachedEntity) then
				attachmentAmount = attachmentAmount + 1
				if attachmentAmount > ATTACHMENT_LIMIT then
					scope.TryBreakAttachment()
				end
			end
		end
    end
end

function TryBreakAttachment()
	if arrowConstraint and IsValidEntity(arrowConstraint) then
		arrowConstraint:Kill()
		
		hasAttachment = false
		attachedEntity = ""
	end
	
	if arrowConstraintAnchor and IsValidEntity(arrowConstraintAnchor) then
		arrowConstraintAnchor:Kill()
		
		hasAttachment = false
		attachedEntity = ""
	end
end

function Dropped()
	StartDecay()
end

function PickedUp()
	if hasAttachment then
		StartSoundEventFromPosition("sound.arrow_extract", thisEntity:GetAbsOrigin() + (thisEntity:GetForwardVector() * ARROW_LENGTH))
	end

	TryBreakAttachment()
	StopDecay()
end

function ArrowThink()

	local vel = GetPhysVelocity(thisEntity)	
	local speed = vel:Length()
	local distanceInterval = speed * THINK_INTERVAL
	
	if inFlight == true and speed > 30 then
		
		
		if not trailEffect then
			trailEffect = ParticleManager:CreateParticle("particles/arrowtrail_basic1.vpcf", PATTACH_ABSORIGIN_FOLLOW, thisEntity)
			ParticleManager:SetParticleControlEnt(trailEffect, 0, thisEntity, PATTACH_ABSORIGIN_FOLLOW, "End", Vector(0, 0, 0), false)
		end	
	
		-- trace forward from the arrow to check for collisions
	
		local arrowTip = thisEntity:GetAbsOrigin() + (thisEntity:GetForwardVector() * (ARROW_LENGTH + 3))
	
		local traceTable =
		{
			startpos = arrowTip;
			endpos = arrowTip + vel:Normalized() * distanceInterval * 1.5;
			ignore = thisEntity;
			
			min = Vector(-ARROW_HULL_SIZE, -ARROW_HULL_SIZE, -ARROW_HULL_SIZE);
			max = Vector(ARROW_HULL_SIZE, ARROW_HULL_SIZE, ARROW_HULL_SIZE)
		}

		TraceHull(traceTable)
		
		-- if we hit something...
		
		if traceTable.hit then
		
			local impactAngle = abs(thisEntity:GetForwardVector():Dot(traceTable.normal))
		
			-- lets see what we hit...
			
			if traceTable.enthit and traceTable.enthit:GetEntityIndex() > 0 then
			
				-- we hit a dynamic object
				
				-- look for attachments that match valid enemy attachments
				
				local FindAttach = GetValidAttachment(traceTable.enthit, traceTable.pos) -- traceTable.enthit:ScriptLookupAttachment("headBack_NUL")
				
				if not FindAttach then
				
					-- we hit a prop
					
					-- deal a lot of damage
					
					if CanDamage(traceTable.enthit) then
						local dmg = CreateDamageInfo(thisEntity, user, vel * thisEntity:GetMass(), traceTable.pos, speed * 1000, DMG_BULLET)--DMG_SLASH)
						traceTable.enthit:TakeDamage(dmg)
						DestroyDamageInfo(dmg)
					end
					
					if traceTable.enthit and IsValidEntity(traceTable.enthit) and traceTable.enthit:IsAlive() then
					
						-- If the object is still alive...
						if impactAngle < 0.4 or not CanAttachTo(traceTable.enthit) then
						
							-- we hit it at a shallow angle or cannot attach, glance off and apply an opposing force
						
							thisEntity:ApplyAbsVelocityImpulse((vel:Length() * traceTable.normal * 0.25) - (vel * 0.75))
					
							traceTable.enthit:ApplyAbsVelocityImpulse(vel:Length() * -traceTable.normal * 0.1)
					
							StartSoundEventFromPosition("sound.arrow_bounce", traceTable.pos)
							
						else
						
							-- we hit it more directly, attach to it instead
							
							hitParent = traceTable.enthit
							hitLoc = traceTable.pos
							hitFwd = thisEntity:GetForwardVector()
							
							StartSoundEventFromPosition("sound.arrow_hit", hitLoc)
							
							local keyvals = vlua.clone(ATTACH_ARROW_KEYVALS)
							keyvals.targetname = DoUniqueString("Arrow")
							keyvals.origin = hitLoc - (hitFwd * (ARROW_LENGTH))
							keyvals.angles = thisEntity:GetAngles()
							
							thisEntity:SetAbsOrigin(Vector(0,0,0))
							
							SpawnImpactEffect(hitLoc, hitFwd) -- done before arrow gets in the way!
							
							-- spawn a new replacement arrow and setup the attachment for it
							-- using this arrow can mess up since it has velocity
							
							attachedArrow = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
							
							local locConstraintKeyvals = vlua.clone(ARROW_CONSTRAINT_KEYVALS)
							locConstraintKeyvals.origin = attachedArrow:GetAbsOrigin()
							locConstraintKeyvals.attachpoint = hitLoc
							locConstraintKeyvals.attach2 = attachedArrow:GetName()
							
							if hitParent:GetName() == ""
							then
								hitParent:SetEntityName(DoUniqueString("arrow_attach"))
							end
							
							locConstraintKeyvals.attach1 = hitParent:GetName()
							arrowConstraint = SpawnEntityFromTableSynchronous(locConstraintKeyvals.classname, locConstraintKeyvals)
							
							local scope = attachedArrow:GetPrivateScriptScope()
							if scope then
								if scope.SetupAttachment then
									attachedArrow:GetOrCreatePrivateScriptScope():SetupAttachment(arrowConstraint, nil)
								end		
							end
							
							thisEntity:Kill()
							
							StopFlight()
							
							return nil
							
						end
					end
				else
				
					-- we hit an enemy

					-- do some damage
					
					local wasAlive = traceTable.enthit:IsAlive()
					
					if wasAlive then
						SpawnImpactEffect(traceTable.pos, thisEntity:GetForwardVector())
					end
					
					-- get headshot damage
					
					local damageMultiplier = GetHeadshotDamageMultiplier(traceTable.enthit, traceTable.pos)
					
					local isHeadshot = damageMultiplier > 1
					
					-- get enemy specific damage
					
					damageMultiplier = damageMultiplier + GetEnemyDamageMultiplier(traceTable.enthit)
					
					local damageValue = speed * 0.017 * damageMultiplier
					
					if CanDamage(traceTable.enthit) then
						local dmg = CreateDamageInfo(thisEntity, user, vel * thisEntity:GetMass(), traceTable.pos, damageValue, DMG_BULLET)
						traceTable.enthit:TakeDamage(dmg)
						DestroyDamageInfo(dmg)
					end
					
					if wasAlive and IsValidEntity(traceTable.enthit) and not traceTable.enthit:IsAlive() then
						-- we just killed this enemy, do the trace again to get the ragdoll, this sometimes works and looks great
						TraceHull(traceTable)
					end					
					
					if isHeadshot then
						StartSoundEventFromPosition("sound.arrow_hit_enemy_headshot", traceTable.pos)
					else
						StartSoundEventFromPosition("sound.arrow_hit_enemy", traceTable.pos)
					end
					
					SpawnImpactEffect(traceTable.pos, thisEntity:GetForwardVector())
					
					
					enemyHitEffect = ParticleManager:CreateParticle("particles/arrowimpact3.vpcf", PATTACH_CUSTOMORIGIN, thisEntity)
					ParticleManager:SetParticleControl(enemyHitEffect, 0, traceTable.pos)
					ParticleManager:ReleaseParticleIndex(enemyHitEffect) 
					
					StopFlight()
					
					--
					
					if traceTable.enthit:IsAlive() then
					
						traceTable.enthit:ApplyAbsVelocityImpulse(vel / 60)
						
						thisEntity:ApplyAbsVelocityImpulse((thisEntity:GetForwardVector() * 10000) - vel)
					
					else
					
						traceTable.enthit:ApplyAbsVelocityImpulse(vel / 80)
						
						if traceTable.enthit:GetName() == "" then
							traceTable.enthit:SetEntityName(DoUniqueString("arrow_attach_parent"))
						end
					
						hitParent = traceTable.enthit
						hitLoc = traceTable.pos
						hitFwd = thisEntity:GetForwardVector()
						
						local attachPos = hitParent:GetAttachmentOrigin(hitParent:ScriptLookupAttachment(FindAttach))
						
						if VectorDistance(traceTable.pos, attachPos) < 10 then
							thisEntity:SetAbsOrigin(hitLoc - (hitFwd * ARROW_LENGTH))
							
							-- spawn a new replacement arrow and setup the attachment for it
							
							local keyvals = vlua.clone(ATTACH_ARROW_KEYVALS)
							keyvals.targetname = DoUniqueString("Arrow")
							keyvals.origin = hitLoc - (hitFwd * (ARROW_LENGTH / 2))
							keyvals.angles = thisEntity:GetAngles()
							
							attachedArrow = SpawnEntityFromTableSynchronous(keyvals.classname, keyvals)
							
							local anchorKeyvals = vlua.clone(ARROW_CONSTRAINT_ANCHOR_KEYVALS)
							anchorKeyvals.origin = hitLoc
							
							arrowConstraintAnchor = SpawnEntityFromTableSynchronous(anchorKeyvals.classname, anchorKeyvals)
							arrowConstraintAnchor:SetParent(hitParent, FindAttach)
							arrowConstraintAnchor:SetEntityName(DoUniqueString("arrow_attach_anchor"))

							local constraintKeyvals = vlua.clone(ARROW_CONSTRAINT_KEYVALS)
							constraintKeyvals.origin = attachedArrow:GetAbsOrigin()
							constraintKeyvals.attachpoint = hitLoc
							constraintKeyvals.attach1 = attachedArrow:GetName()
							constraintKeyvals.attach2 = arrowConstraintAnchor:GetName()
							
							arrowConstraint = SpawnEntityFromTableSynchronous(constraintKeyvals.classname, constraintKeyvals)
							arrowConstraint:SetEntityName(DoUniqueString("arrow_attach_constraint"))
							
							local scope = attachedArrow:GetPrivateScriptScope()
							if scope then
								if scope.SetupAttachment then
									attachedArrow:GetOrCreatePrivateScriptScope():SetupAttachment(arrowConstraint, arrowConstraintAnchor)
								end
								if scope.EnforceAttachmentLimit then
									attachedArrow:GetOrCreatePrivateScriptScope():EnforceAttachmentLimit(traceTable.enthit)
								end	
							end
							
							thisEntity:Kill()
						end
					
					end
					
					return nil
					
				end
				
			else
			
				-- we hit a static object
				
				StartSoundEventFromPosition("sound.arrow_bounce", traceTable.pos)
				
				if impactAngle < 0.1 or speed < 10 then
					
					-- we hit it at a flat angle, stop flying
					
					StopFlight()
					return nil
						
				elseif impactAngle < 0.5 then
				
					-- we hit it at a shallow angle, ricochet off the entity and keep moving
				
					local reflectionVec = vel:Normalized() - ((2 * traceTable.normal) * (thisEntity:GetForwardVector() * traceTable.normal))
					
					thisEntity:SetAbsOrigin(traceTable.pos + reflectionVec * 1)
					
					local reflectionAngles = VectorToAngles(reflectionVec)
					thisEntity:SetAngles(reflectionAngles.x, reflectionAngles.y, reflectionAngles.z)					
					
					local reboundStrength = (1 - thisEntity:GetForwardVector():Dot(traceTable.normal) * 2)
					
					thisEntity:ApplyAbsVelocityImpulse((reflectionVec * vel:Length() * reboundStrength) -vel)
					
					return THINK_INTERVAL

				else
				
					-- we hit it at a steep angle, bounce off the entity and stop flying
					
					local reflectionVec = vel:Normalized() - ((2 * traceTable.normal) * (thisEntity:GetForwardVector() * traceTable.normal))
					
					thisEntity:SetAbsOrigin(traceTable.pos + (reflectionVec * ARROW_LENGTH))
					
					thisEntity:ApplyAbsVelocityImpulse((vel:Length() * reflectionVec * 0.05) - vel)
					
					StopFlight()
					return nil
					
				end
			end
		end
		
	-- if we run out of speed, stop flight

	elseif inFlight and speed < 5 then
		
		StopFlight()
		
		return nil
	end
	
	return THINK_INTERVAL
end

function GetValidAttachment(searchEntity, searchLocation)

	local foundAttach = false
	local closestAttach = nil
	local closestAttachDistance = 100000

	for i, attach in pairs(validAttachments) do
	  
		local attachId = searchEntity:ScriptLookupAttachment(attach)
		
		if attachId ~= 0 then
			local attachDistance = VectorDistance(searchEntity:GetAttachmentOrigin(attachId), searchLocation)
			if attachDistance < closestAttachDistance then
				foundAttach = true
				closestAttach = attach
				closestAttachDistance = attachDistance
			end
		end	  
    end

	if foundAttach then
		return closestAttach
	end

	return nil
end

function GetHeadshotDamageMultiplier(searchEntity, searchLocation)

	for i, attach in pairs(validHeadshotAttachments) do
	  
		print(attach)
		  
		local attachId = searchEntity:ScriptLookupAttachment(attach)
		  
		print(attachId)
	  
		if attachId ~= 0 then
			local attachDistance = VectorDistance(searchEntity:GetAttachmentOrigin(attachId), searchLocation)
			if attachDistance < HEADSHOT_DISTANCE then
				print("HEADSHOT!")
				return HEADSHOT_MULTIPLIER
			end
		end	  
    end

	print("No headshot :(")

	return 1
end

function GetEnemyDamageMultiplier(searchEntity)

	-- antlion spitters seem to have a tonne of health, do some more damage to them

	if searchEntity:GetModelName() == "models/creatures/antlion/antlion_worker.vmdl" then
		return 2
	end

	return 1
end

function CanDamage(attachEntity)
	if attachEntity == Entities:GetLocalPlayer() then
		return false
	end
	return true
end

function CanAttachTo(attachEntity)
	if IsValidEntity(lastUsedBow) and attachEntity == lastUsedBow then
		return false
	elseif IsValidEntity(lastNockedArrow) and attachEntity == lastNockedArrow then
		return false
	elseif attachEntity == Entities:GetLocalPlayer() then
		return false
	elseif string.match(attachEntity:GetName(), "Arrow") then -- Don't attach to other arrows - bad stuff happens
		return false
	end
	return true
end

function StopFlight()

	inFlight = false

	if trailEffect then
		ParticleManager:DestroyParticle(trailEffect, false)
		trailEffect = nil
	end
end

function SpawnImpactEffect(targetLocation, targetDirection)

	local directionAngle = VectorToAngles(targetDirection)
	local endPosition = thisEntity:GetAbsOrigin() + (targetDirection * 50)

	--Trace used for effects
	
	local effectTrace = {
		startpos = thisEntity:GetAbsOrigin(),
		endpos = endPosition,
		mask = 0,
		ignore = thisEntity
	}

	local bulletEndTargetName = thisEntity:GetName() .. "bullet_end_target"
	local bulletEndTarget = SpawnEntityFromTableSynchronous("info_target", {
		classname = "info_target",
		targetname = bulletEndTargetName,
		origin = targetLocation,
		angles = VectorToAngles(targetDirection)
	})
	
	EntFireByHandle(bulletEndTarget, bulletEndTarget, "Kill", "", 5)
	
	--env_gunfire for impact effects, this is spawned at the end of effectTrace and the tracer effect from this is not used
	
	local bulletGunfire = SpawnEntityFromTableSynchronous("env_gunfire", {
		classname = "env_gunfire",
		targetname = thisEntity:GetName() .. "bullet_gunfire",
		origin = targetLocation - (targetDirection * (ARROW_LENGTH / 2)),
		angles = directionAngle,
		target = bulletEndTargetName,
		minburstsize = 1,
		maxburstsize = 1,
		minburstdelay = 1,
		maxburstdelay = 1,
		rateoffire = 0,
		spread = 0,
		bias = 1,
		collisions = 1,
		shootsound = "",
		tracertype = ""
	})
	
	EntFireByHandle(bulletGunfire, bulletGunfire, "Kill", "", 0.01)

end

function StartDecay()

	-- arrows get destroyed after a while if not held or flying
	-- this timer gets reset on pickup

	if not decaying then
		thisEntity:SetThink(Decay, "decay", DECAY_TIME)
		
		canDecay = true
		decaying = true
	elseif decaying and not canDecay then
		restartDecay = true
	end
end

function StopDecay()
	if decaying then
		canDecay = false
		restartDecay = false
	end
end

function Decay()
	if canDecay then
		StopFlight()
		TryBreakAttachment()
		HideGlow()		
		thisEntity:Kill()		
	elseif restartDecay then
		StartDecay()
	else
		decaying = false
	end
end

function Destroy()
	canDecay = true
	Decay()	
end