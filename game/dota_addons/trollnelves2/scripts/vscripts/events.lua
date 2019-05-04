function trollnelves2:OnGameRulesStateChange()
	DebugPrint("GameRulesStateChange ******************")
	local newState = GameRules:State_Get()
	DebugPrint(newState)
	if newState == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
		trollnelves2:GameSetup()
	elseif newState == DOTA_GAMERULES_STATE_PRE_GAME then
		self:PreStart()
	end
end

-- An NPC has spawned somewhere in game.  This includes heroes
function trollnelves2:OnNPCSpawned(keys)
  DebugPrint("OnNPCSpawned:")
    DebugPrintTable(keys)
  local npc = EntIndexToHScript(keys.entindex)

  if npc.GetPhysicalArmorValue then
    npc:AddNewModifier(npc, nil, "modifier_custom_armor", {})
  end

  if npc:IsRealHero() and npc.bFirstSpawned == nil then
    npc.bFirstSpawned = true
    trollnelves2:OnHeroInGame(npc)
  end
end

function trollnelves2:OnPlayerReconnect(event)
	local playerID = event.PlayerID
	local notSelectedHero = GameRules.disconnectedHeroSelects[playerID]
	if notSelectedHero then
		PlayerResource:SetSelectedHero(playerID, notSelectedHero)
	end
	local hero = PlayerResource:GetSelectedHeroEntity(playerID)
	if hero then
        -- Send info to client
        PlayerResource:ModifyGold(hero,0)
        PlayerResource:ModifyLumber(hero,0)
        PlayerResource:ModifyFood(hero,0)
        ModifyLumberPrice(0)
		if hero:HasModifier("modifier_disconnected") then
			hero:RemoveModifierByName("modifier_disconnected")
		end
		if hero:IsElf() and hero.alive == false then
			if hero.dced == true then
				hero.alive = true
				hero.dced = false
			else
				local player = PlayerResource:GetPlayer(playerID)
				if player then
					CustomGameEventManager:Send_ServerToPlayer(player, "show_helper_options", { })
				end
			end
		end
	end
end

function trollnelves2:OnDisconnect(event)
	local playerID = event.PlayerID
	local hero = PlayerResource:GetSelectedHeroEntity(playerID)
	local team = hero:GetTeamNumber()
	if team == DOTA_TEAM_GOODGUYS then
		hero:AddNewModifier(nil, nil, "modifier_disconnected", {})
		if hero.alive == true then
			hero.alive = false
			hero.dced = true
			local lastAlive = true
			for i=1,PlayerResource:GetPlayerCountForTeam(DOTA_TEAM_GOODGUYS) do
				local pID = PlayerResource:GetNthPlayerIDOnTeam(2, i)
				local hero2 = PlayerResource:GetSelectedHeroEntity(pID) or false
				if hero2 and hero2.alive then
						lastAlive = false
						break
				end
			end
			if lastAlive then
					hero:RemoveModifierByName("modifier_disconnected")
			end
		end
	elseif team == DOTA_TEAM_BADGUYS then
		hero:MoveToPosition(Vector(0,0,0))
	end
end

function trollnelves2:OnConnectFull(keys)
  	DebugPrint("OnConnectFull ******************")
	local entIndex = keys.index+1
	-- The Player entity of the joining user
	local player = EntIndexToHScript(entIndex)
	local userID = keys.userid
	GameRules.userIds = GameRules.userIds or {}
	-- The Player ID of the joining player
	local playerID = player:GetPlayerID()
	GameRules.userIds[userID] = playerID
	trollnelves2:_Capturetrollnelves2()
end

--[[
	This function is called once and only once after all players have loaded into the game, right as the hero selection time begins.
	It can be used to initialize non-hero player state or adjust the hero selection (i.e. force random etc)
]]
function trollnelves2:OnAllPlayersLoaded()
	DebugPrint("[TROLLNELVES2] All Players have loaded into the game")

end


function trollnelves2:OnEntityKilled(keys)
    local killed = EntIndexToHScript(keys.entindex_killed)
    local attacker = EntIndexToHScript(keys.entindex_attacker)
    local bounty = -1
    local killedID = killed:GetPlayerOwnerID()
    local attackerID = attacker:GetPlayerOwnerID()

    if killed:IsRealHero() then
        if killed:IsElf() and killed.alive then
            bounty = ElfKilled(killed)
            if CheckTrollVictory() then
                SetResourceValues()
                Stats.SubmitMatchData(DOTA_TEAM_BADGUYS, callback)
                GameRules:SetGameWinner(DOTA_TEAM_BADGUYS)
                return
            end
        elseif killed:IsTroll() then
            SetResourceValues()
            Stats.SubmitMatchData(DOTA_TEAM_GOODGUYS, callback)
            GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
        elseif killed:IsWolf() then
            bounty = math.max(killed:GetNetworth() * 0.10,GameRules:GetGameTime())
            killed:SetRespawnPosition(Vector(0, -640, 256))
            killed:SetTimeUntilRespawn(WOLF_RESPAWN_TIME)
        elseif killed:IsAngel() then
            bounty = math.max(PlayerResource:GetGold(killedID),GameRules:GetGameTime())
            PlayerResource:SetGold(killed, 0)
            killed:SetRespawnPosition(RandomAngelLocation())
            killed:SetTimeUntilRespawn(ANGEL_RESPAWN_TIME)
            Timers:CreateTimer(ANGEL_RESPAWN_TIME, function ()
                hero:AddNewModifier(killed, nil, "modifier_invulnerable", {duration = 5})
            end)
        end
    end
    if bounty>=0 and attacker~=killed then
        local killedName = PlayerResource:GetSelectedHeroEntity(killedID)
                and PlayerResource:GetSelectedHeroEntity(killedID):GetUnitName() or killed:GetUnitName()
        local attackerName = PlayerResource:GetSelectedHeroEntity(attackerID)
                and PlayerResource:GetSelectedHeroEntity(attackerID):GetUnitName() or attacker:GetUnitName()
        bounty = math.floor(bounty)
        PlayerResource:ModifyGold(attacker,bounty)
        local message = "%s1 (" .. GetModifiedName(attackerName)  .. ") killed " .. PlayerResource:GetPlayerName(killedID) .. " (" .. GetModifiedName(killedName) .. ") for <font color='#F0BA36'>"..bounty.."</font> gold!"
        GameRules:SendCustomMessage(message, attackerID, 0)
    end
    if not killed:IsNull() and killed:GetKeyValue("FoodCost") then
        local food_cost = killed:GetKeyValue("FoodCost")
        local hero = PlayerResource:GetSelectedHeroEntity(killedID)
        PlayerResource:ModifyFood(hero,-food_cost)
    end

end

function ElfKilled(killed)
    local killedID = killed:GetPlayerOwnerID()
    killed.alive = false
    killed.legitChooser = true

    local bounty = PlayerResource:GetGold(killedID)
    PlayerResource:SetGold(killed,0)
	PlayerResource:SetLumber(killed,0)

    for i=1,#killed.units do
		if killed.units[i] and not killed.units[i]:IsNull() then
			local unit = killed.units[i]
            if unit.minimapEntity then
                UTIL_Remove(unit.minimapEntity)
			end
			unit:ForceKill(false)
        end
    end

    PlayerResource:SetCameraTarget(killedID, GameRules.trollHero)
    Timers:CreateTimer(3, function()
        PlayerResource:SetCameraTarget(killedID, nil)
    end)

    DebugPrint("Seconds elapsed: " .. GameRules:GetGameTime() - GameRules.startTime)
    if GameRules:GetGameTime() - GameRules.startTime >= WOLF_START_SPAWN_TIME then
        local orgPlayer = killed:GetPlayerOwner()
        if orgPlayer then
            CustomGameEventManager:Send_ServerToPlayer(orgPlayer, "show_helper_options", { })
            Timers:CreateTimer(30,function()
                if killed and killed.legitChooser then
                    local args = {}
                    args.team = RandomInt(0, 1) == 1 and DOTA_TEAM_GOODGUYS or DOTA_TEAM_BADGUYS
                    args.playerID = killedID
                    ChooseHelpSide(killedID, args)
                end
            end)
        else
            GameRules.dcedChoosers[killedID] = true
        end
    else
        local args = {}
        args.team = DOTA_TEAM_GOODGUYS
        args.playerID = killedID
		ChooseHelpSide(killedID, args)
    end

    return bounty
end

function CheckTrollVictory()
    for i=1,PlayerResource:GetPlayerCountForTeam(DOTA_TEAM_GOODGUYS) do
        local playerID = PlayerResource:GetNthPlayerIDOnTeam(DOTA_TEAM_GOODGUYS, i)
        local hero = PlayerResource:GetSelectedHeroEntity(playerID)
        if hero and hero.alive then
            return false
        end
    end
    return true
end


function GiveResources(eventSourceIndex, event)
    DebugPrint("Give resources, event source index: ", eventSourceIndex)
    DebugPrintTable(event)
    local targetID = event.target
    local casterID = event.casterID
    local gold = math.floor(math.abs(tonumber(event.gold)))
    local lumber = math.floor(math.abs(tonumber(event.lumber)))
    if tonumber(event.gold) ~= nil and tonumber(event.lumber) ~= nil then
        if PlayerResource:GetSelectedHeroEntity(targetID) and PlayerResource:GetSelectedHeroEntity(targetID):GetTeam() == PlayerResource:GetSelectedHeroEntity(event.casterID):GetTeam() then
            local hero = PlayerResource:GetSelectedHeroEntity(targetID)
            local casterHero = PlayerResource:GetSelectedHeroEntity(casterID)
            if gold and lumber then
                if PlayerResource:GetGold(casterID) < gold or PlayerResource:GetLumber(casterID) < lumber then
                    SendErrorMessage(casterID, "#error_not_enough_resources")
                    return
                end
                PlayerResource:ModifyGold(casterHero,-gold,true)
                PlayerResource:ModifyLumber(casterHero,-lumber,true)
                PlayerResource:ModifyGold(hero,gold,true)
                PlayerResource:ModifyLumber(hero,lumber,true)
                PlayerResource:ModifyGoldGiven(targetID,-gold)
                PlayerResource:ModifyLumberGiven(targetID,-lumber)
                PlayerResource:ModifyGoldGiven(casterID,gold)
                PlayerResource:ModifyLumberGiven(casterID,lumber)
                if gold > 0 or lumber > 0 then
                    local text = PlayerResource:GetPlayerName(casterHero:GetPlayerOwnerID()) .. "(" .. GetModifiedName(casterHero:GetUnitName()) .. ") has sent "
                    if gold > 0 then
                        text = text .. "<font color = '#F0BA36'>" .. gold .. "</font> gold"
                    end
                    if gold > 0 and lumber > 0 then
                        text = text .. " and "
                    end
                    if lumber > 0 then
                        text = text .. "<font color = '#009900'>" .. lumber .. "</font> lumber"
                    end
                    text = text ..  " to " .. PlayerResource:GetPlayerName(hero:GetPlayerOwnerID()) .. "(" .. GetModifiedName(hero:GetUnitName()) .. ")!"
                    GameRules:SendCustomMessageToTeam(text,casterHero:GetTeamNumber(),0,0)
                end
            else
                SendErrorMessage(event.casterID, "#error_enter_only_digits")
            end
        else
            SendErrorMessage(event.casterID, "#error_select_only_your_allies")
        end
    else
        SendErrorMessage(event.casterID, "#error_type_only_digits")
    end
end

function ChooseHelpSide(eventSourceIndex, event)
    DebugPrint("Choose help side: " .. eventSourceIndex);
    DebugPrintTable(event);
    local team = event.team
    local playerID = event.playerID
    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    hero.legitChooser = false

    local newHeroName
    local message
    local timer
    local pos
    if team == DOTA_TEAM_GOODGUYS then
        newHeroName = ANGEL_HERO
        message = "%s1 will keep helping elves and now is an " .. GetModifiedName(ANGEL_HERO)
        timer = ANGEL_RESPAWN_TIME
        pos = RandomAngelLocation()
    elseif team == DOTA_TEAM_BADGUYS then
        newHeroName = WOLF_HERO
        message = "%s1 has joined the dark side and now will help " .. GetModifiedName(TROLL_HERO) .. ". %s1 is now a" .. GetModifiedName(WOLF_HERO)
        timer = WOLF_RESPAWN_TIME
        pos = Vector(0, -640, 256)
    end
    Timers:CreateTimer(function()
        GameRules:SendCustomMessage(message, playerID, 0)
    end)

    PlayerResource:SetCustomTeamAssignment(playerID, team)
    hero:SetTimeUntilRespawn(timer)
    Timers:CreateTimer(timer, function()
        PlayerResource:ReplaceHeroWith(playerID, newHeroName, 0, 0)
        UTIL_Remove(hero)
        hero = PlayerResource:GetSelectedHeroEntity(playerID)
        FindClearSpaceForUnit(hero, pos, true)
    end)
end

function RandomAngelLocation()
    return (GameRules.angel_spawn_points and #GameRules.angel_spawn_points and #GameRules.angel_spawn_points > 0) and GameRules.angel_spawn_points[RandomInt(1, #GameRules.angel_spawn_points)]:GetAbsOrigin() or Vector(0,0,0)
end
