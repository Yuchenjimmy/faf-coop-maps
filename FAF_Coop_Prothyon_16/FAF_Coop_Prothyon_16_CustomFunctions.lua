local ScenarioFramework = import('/lua/ScenarioFramework.lua')
local ScenarioPlatoonAI = import('/lua/ScenarioPlatoonAI.lua')
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua')

function CarrierAI(platoon)
    platoon:Stop()
    local aiBrain = platoon:GetBrain()
    local data = platoon.PlatoonData
    local carriers = platoon:GetPlatoonUnits()
    local movePositions = {}

    if not data then
        error('*Carrier AI ERROR: PlatoonData not defined', 2)
    elseif not (data.MoveRoute or data.MoveChain) then
        error('*Carrier AI ERROR: MoveToRoute or MoveChain not defined', 2)
    end


    if data.MoveChain then
        movePositions = ScenarioUtils.ChainToPositions(data.MoveChain)
    else
        for k, v in data.MoveRoute do
            if type(v) == 'string' then
                table.insert(movePositions, ScenarioUtils.MarkerToPosition(v))
            else
                table.insert(movePositions, v)
            end
        end
    end

    local numCarriers = table.getn(carriers)
    local numPositions = table.getn(movePositions)

    if numPositions < numCarriers then
        error('*Carrier AI ERROR: Less mvoe positions than carriers', 2)
    end

    for i = 1, numCarriers do
        ForkThread(function(i)
            local carrier = carriers[i]
            IssueMove({carrier}, movePositions[i])

            while (not carrier:IsDead() and carrier:IsUnitState('Moving')) do
                WaitSeconds(.5)
            end

            if carrier.Dead then
                return
            end

            for _, location in aiBrain.PBM.Locations do
                if location.LocationType == data.Location .. i then
                    location.PrimaryFactories.Air = carrier.ExternalFactory
                    break
                end
            end

            carrier:ForkThread(function(self)
                local factory = self.ExternalFactory

                while true do
                    if table.getn(self:GetCargo()) > 0 and factory:IsIdleState() then
                        IssueClearCommands({self})
                        IssueTransportUnload({self}, carrier:GetPosition())
    
                        repeat
                            WaitSeconds(3)
                        until not self:IsUnitState("TransportUnloading")
                    end

                    WaitSeconds(1)
                end
            end)
        end, i)
    end
end

function PatrolThread(platoon)
    local data = platoon.PlatoonData

    for _, unit in platoon:GetPlatoonUnits() do
        while (not unit:IsDead() and unit:IsUnitState('Attached')) do
            WaitSeconds(1)
        end
    end

    platoon:Stop()
    if(data) then
        if(data.PatrolRoute or data.PatrolChain) then
            if data.PatrolChain then
                ScenarioFramework.PlatoonPatrolRoute(platoon, ScenarioUtils.ChainToPositions(data.PatrolChain))
            else
                for k,v in data.PatrolRoute do
                    if type(v) == 'string' then
                        platoon:Patrol(ScenarioUtils.MarkerToPosition(v))
                    else
                        platoon:Patrol(v)
                    end
                end
            end
        else
            error('*SCENARIO PLATOON AI ERROR: PatrolRoute or PatrolChain not defined', 2)
        end
    else
        error('*SCENARIO PLATOON AI ERROR: PlatoonData not defined', 2)
    end
end

function PlatoonAttackWithTransports( platoon, landingChain, attackChain, instant )
    ForkThread( PlatoonAttackWithTransportsThread, platoon, landingChain, attackChain, instant )
end

function PlatoonAttackWithTransportsThread( platoon, landingChain, attackChain, instant, moveChain )
    local aiBrain = platoon:GetBrain()
    local allUnits = platoon:GetPlatoonUnits()
    local startPos = platoon:GetPlatoonPosition()
    local units = {}
    local transports = {}
    for k,v in allUnits do
        if EntityCategoryContains( categories.TRANSPORTATION, v ) then
            table.insert( transports, v )
        else
            table.insert( units, v )
        end
    end

    local landingLocs = ScenarioUtils.ChainToPositions( landingChain )
    local landingLocation = landingLocs[Random(1,table.getn(landingLocs))]

    if instant then
        ScenarioFramework.AttachUnitsToTransports( units, transports )
        if moveChain and not ScenarioPlatoonAI.MoveAlongRoute(platoon, ScenarioUtils.ChainToPositions(moveChain)) then
            return
        end
        IssueTransportUnload( transports, landingLocation )
        local attached = true
        while attached do
            WaitSeconds(3)
            local allDead = true
            for k,v in transports do
                if not v.Dead then
                    allDead = false
                    break
                end
            end
            if allDead then
                return
            end
            attached = false
            for num, unit in units do
                if not unit.Dead and unit:IsUnitState('Attached') then
                    attached = true
                    break
                end
            end
        end
    else
        if not import('/lua/ai/aiutilities.lua').UseTransports( units, transports, landingLocation ) then
            return
        end
    end

    local attackLocs = ScenarioUtils.ChainToPositions(attackChain)
    for k,v in attackLocs do
        IssuePatrol( units, v )
    end
    --[[
    if instant then
        IssueMove( transports, startPos )
        for k, unit in transports do
            aiBrain:AssignUnitsToPlatoon( 'TransportPool', {unit}, 'Scout', 'None')
        end
    end]]--
end