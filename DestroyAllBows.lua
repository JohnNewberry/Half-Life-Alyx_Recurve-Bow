
-- Since map extensions seem to break the Jeff chapter I destroy the bow with this script at the end of the previous one

local enableBackpack = nil

local EQUIP_PLAYER_KEYVALS = {
	classname = "info_hlvr_equip_player";
	targetname = "dab_equip_player"
}

function Run()

	print("------------------")
	print("DESTROY ALL BOWS")
	print("------------------")

	for key, value in pairs(Entities:FindAllByModel("models/bow2.vmdl")) do
		local entity = value
		local scope = entity:GetPrivateScriptScope()
		if scope and scope.ForceDestroyEntities then
			entity:GetOrCreatePrivateScriptScope():ForceDestroyEntities()
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