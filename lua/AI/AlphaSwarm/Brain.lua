local BC = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/BaseController.lua')
local IM = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/IntelManager.lua')
local AM = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/ArmyMonitor.lua')
local UC = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/UnitController.lua')
local PM = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/ProductionManager.lua')

Brain = Class({
    OnCreate = function(self,aiBrain)
        self.aiBrain = aiBrain
        self.Trash = TrashBag()
        self:ForkThread(self.Initialise)
    end,

    Initialise = function(self)
        -- Allow sim setup and initialisation
        WaitSeconds(5)
        -- ...
        self.base = BC.CreateBaseController(self)
        self.intel = IM.CreateIntelManager(self)
        self.monitor = AM.CreateArmyMonitor(self)
        self.army = UC.CreateUnitController(self)
        self.production = PM.CreateProductionManager(self)
        LOG("AlphaSwarm Brain ready...")
        bo = self.intel:PickBuildOrder()
        -- Make sure to copy items so that different AIs don't end up sharing variables (learned that the hard way)
        for _, v in bo.mobile do
            self.base:AddMobileJob(table.copy(v))
        end
        for _, v in bo.factory do
            self.base:AddFactoryJob(table.copy(v))
        end
        self.base:Run()
        self.intel:Run()
        self.monitor:Run()
        WaitSeconds(2)
        self.production:Run()
        self.army:Run()
    end,

    IsAlive = function(self)
        return self.aiBrain.Result ~= "defeat"
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

function CreateBrain(aiBrain)
    local b = Brain()
    b:OnCreate(aiBrain)
    return b
end