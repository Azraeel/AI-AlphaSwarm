local PROFILER = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/Profiler.lua').GetProfiler()

LOW = 100
NORMAL = 200
HIGH = 300
CRITICAL = 400

JOB_INF = 1000000000

ProductionManager = Class({
    --[[
        Responsible for:
            Resource allocation between specialist production classes
                Manage main and subsidiary production classes
                TODO: Add support for subsidiary production classes, e.g. a separate land production manager for different islands
            Strategy coordination
            Production coordination (e.g. more energy requested for upgrades/overcharge)
    ]]

    Initialise = function(self,brain)
        self.brain = brain
        self.allocations = {
            { manager = BaseProduction(), mass = 0 },
            { manager = LandProduction(), mass = 0 },
            { manager = AirProduction(), mass = 0 },
            { manager = NavyProduction(), mass = 0 },
            { manager = TacticalProduction(), mass = 0 },
        }
        for _, v in self.allocations do
            v.manager:Initialise(self.brain,self)
        end
    end,

    Run = function(self)
        WaitSeconds(1)
        self:ForkThread(self.ManageProductionThread)
        --self:ForkThread(self.ReportSpendsThread)
    end,

    ManageProductionThread = function(self)
        while self.brain:IsAlive() do
            --LOG("Production Management Thread")
            self:AllocateResources()
            for _, v in self.allocations do
                local start = PROFILER:Now()
                v.manager:ManageJobs(v.mass)
                PROFILER:Add("Production"..v.manager.name,PROFILER:Now()-start)
            end
            WaitSeconds(1)
        end
    end,

    ReportSpendsThread = function(self)
        while self.brain:IsAlive() do
            LOG("================================================")
            for _, v in self.allocations do
                local totalSpend = 0
                for _, j in v.manager do
                    if j.actualSpend then
                        totalSpend = totalSpend + j.actualSpend
                    end
                end
                if totalSpend > 0 then
                    LOG(v.manager.name.." allocated: "..v.mass..", spending: "..tostring(totalSpend))
                end
            end
            WaitSeconds(15)
        end
    end,

    AllocateResources = function(self)
        -- TODO: subsidiary production and proper management.  Allocations need to be strategy dependent.
        -- Tune up allocations based on mass storage (0.85 when empty, 1.8 when full)
        local storageModifier = 0.85 + 1*self.brain.aiBrain:GetEconomyStoredRatio('MASS')
        local availableMass = self.brain.monitor.mass.income*storageModifier
        local section0 = math.min(5,availableMass)
        local section1 = math.min(14,availableMass-section0)
        local section2 = math.min(40,availableMass-section0-section1)
        local section3 = math.min(100,availableMass-section0-section1-section2)
        local section4 = availableMass-section0-section1-section2-section3
        -- Base allocation
        self.allocations[1].mass = section0 + 0.2*section1 + 0.3*section2 + 0.38*section3 + 0.4*section4
        -- Land allocation
        self.allocations[2].mass = section1*0.8 + section2*0.6 + section3*0.6 + section4*0.6
        -- Air allocation
        self.allocations[3].mass = section2*0.1 + section3*0.02
    end,

    ForkThread = function(self, fn, ...)
        if fn then
            local thread = ForkThread(fn, self, unpack(arg))
            self.brain.Trash:Add(thread)
            return thread
        else
            return nil
        end
    end,
})

function CreateProductionManager(brain)
    local pm = ProductionManager()
    pm:Initialise(brain)
    return pm
end

BaseProduction = Class({
    --[[
        Responsible for:
            Mex construction
            Mex upgrades
            Pgen construction
            ACU defensive production, e.g. t2/3 upgrades, RAS, etc.
            Base defenses (pd, aa, torpedo launchers)
            Engineer production
            Reclaim

        Main instance will control all mex upgrades and pgen construction.
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Base"
        self.brain = brain
        self.coord = coord
        -- Mex expansion, controlled via duplicates (considered to cost nothing mass wise)
        self.mexJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = JOB_INF, targetSpend = JOB_INF, work = "MexT1", keep = true, priority = LOW, assist = false })
        self.brain.base:AddMobileJob(self.mexJob)
        -- Pgens - controlled via target spend
        self.t1PgenJob = self.brain.base:CreateGenericJob({ duplicates = 10, count = JOB_INF, targetSpend = 0, work = "PgenT1", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.t1PgenJob)
        self.t2PgenJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = JOB_INF, targetSpend = 0, work = "PgenT2", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.t2PgenJob)
        self.t3PgenJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "PgenT3", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.t3PgenJob)
        -- Engies - controlled via job count (considered to cost nothing mass wise)
        self.t1EngieJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = 0, targetSpend = JOB_INF, work = "EngineerT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1EngieJob)
        self.t2EngieJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = 0, targetSpend = JOB_INF, work = "EngineerT2", keep = true, priority = HIGH })
        self.brain.base:AddFactoryJob(self.t2EngieJob)
        self.t3EngieJob = self.brain.base:CreateGenericJob({ duplicates = 2, count = 0, targetSpend = JOB_INF, work = "EngineerT3", keep = true, priority = HIGH })
        self.brain.base:AddFactoryJob(self.t3EngieJob)
        -- Mass upgrades - controlled via target spend
        self.mexT2Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "MexT2", keep = true, priority = NORMAL })
        self.brain.base:AddUpgradeJob(self.mexT2Job)
        self.mexT3Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "MexT3", keep = true, priority = NORMAL })
        self.brain.base:AddUpgradeJob(self.mexT3Job)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        local massRemaining = mass - self.t1EngieJob.actualSpend
        local availableMex = self.brain.intel:GetNumAvailableMassPoints()
        self.mexJob.duplicates = math.min(availableMex/1.5,math.max(self.brain.monitor.units.engies.t1-4,self.brain.monitor.units.engies.t1/1.5))
        local engiesRequired = math.max(4+math.min(10,availableMex/2),massRemaining/2)-self.brain.monitor.units.engies.t1
        -- Drop out early if we're still doing our build order
        if not self.brain.base.isBOComplete then
            self.t1EngieJob.count = engiesRequired
            return nil
        end
        local energyModifier = 2 - 0.9*self.brain.aiBrain:GetEconomyStoredRatio('ENERGY')
        -- Do I need more pgens?
        local pgenSpend = math.max(math.min(massRemaining,(self.brain.monitor.energy.spend*energyModifier - self.brain.monitor.energy.income)/4),-1)
        if self.brain.monitor.units.engies.t3 > 0 then
            self.t1PgenJob.targetSpend = 0
            self.t2PgenJob.targetSpend = 0
            self.t3PgenJob.targetSpend = pgenSpend
        elseif self.brain.monitor.units.engies.t2 > 0 then
            self.t1PgenJob.targetSpend = 0
            self.t2PgenJob.targetSpend = pgenSpend
            self.t3PgenJob.targetSpend = 0
        else
            self.t1PgenJob.targetSpend = pgenSpend
            self.t2PgenJob.targetSpend = 0
            self.t3PgenJob.targetSpend = 0
        end
        massRemaining = massRemaining - pgenSpend
        -- Do I need some mex upgrades?
        --LOG("Base spend manager - spent:"..tostring(pgenSpend)..", remaining: "..tostring(massRemaining)..", allocated: "..tostring(mass))
        if massRemaining > 8 or availableMex <= 2 then
            -- TODO: use a buffer to smooth spends on mexes (don't want blips to trigger mass upgrades)
            -- TODO: Distribute mass remaining between mex upgrade jobs
            self.mexT2Job.targetSpend = massRemaining - 5
            if self.brain.monitor.units.mex.t2 > self.brain.monitor.units.mex.t1*2 then
                self.mexT2Job.targetSpend = self.mexT2Job.targetSpend * 0.6
                self.mexT3Job.targetSpend = massRemaining - self.mexT2Job.actualSpend - 10
            else
                self.mexT3Job.targetSpend = 0
            end
        else
            self.mexT2Job.targetSpend = 0
        end
        -- How many engies do I need?
        self.t1EngieJob.count = engiesRequired
        self.t2EngieJob.count = 2-self.brain.monitor.units.engies.t2-self.brain.monitor.units.engies.t3
        self.t3EngieJob.count = 2-self.brain.monitor.units.engies.t3
    end,
})

LandProduction = Class({
    --[[
        Responsible for:
            Land Factory production
            Land unit composition/production
            Land factory upgrades
            ACU offensive production, e.g. PD creeps, gun upgrades, etc.

        Main instance has exclusive control of HQ upgrades.
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Land"
        self.brain = brain
        self.coord = coord
        self.island = not self.brain.intel:CanPathToLand(self.brain.intel.allies[1],self.brain.intel.enemies[1])
        -- Base zone
        self.baseZone = self.brain.intel:FindZone(self.brain.intel.allies[1])
        -- T1 jobs
        self.t1ScoutJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "LandScoutT1", keep = true, priority = HIGH })
        self.brain.base:AddFactoryJob(self.t1ScoutJob)
        self.t1TankJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "DirectFireT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1TankJob)
        self.t1ArtyJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "ArtyT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1ArtyJob)
        self.t1AAJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AntiAirT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t1AAJob)
        -- T2 jobs
        self.t2TankJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "DirectFireT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t2TankJob)
        self.t2HoverJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AmphibiousT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t2HoverJob)
        self.t2AAJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AntiAirT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t2AAJob)
        self.t2MMLJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "MMLT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t2MMLJob)
        -- T3 jobs
        self.t3LightJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "DirectFireT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t3LightJob)
        self.t3HeavyJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "HeavyLandT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t3HeavyJob)
        self.t3AAJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AntiAirT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t3AAJob)
        self.t3ArtyJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "ArtyT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.t3ArtyJob)
        -- Experimental jobs
        self.expJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "LandExp", keep = true, priority = HIGH })
        self.brain.base:AddMobileJob(self.expJob)
        -- Factory Jobs
        self.facJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "LandFactoryT1", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.facJob)
        self.t2HQJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 0, work = "LandHQT2", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t2HQJob)
        self.t3HQJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 0, work = "LandHQT3", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t3HQJob)
        self.t2SupportJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "LandSupportT2", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t2SupportJob)
        self.t3SupportJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "LandSupportT3", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t3SupportJob)
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        if self.island then
            return self:ManageIslandJobs(mass)
        end
        local massRemaining = mass
        -- Factory HQ upgrade decisions
        --    Based on:
        --        - investment in units
        --        - available mexes
        --        - available mass
        --        - existence of support factories
        self.t2HQJob.targetSpend = 0
        self.t2HQJob.count = 0
        self.t3HQJob.targetSpend = 0
        self.t3HQJob.count = 0
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- We have a t3 HQ
        elseif self.brain.monitor.units.facs.land.hq.t2 > 0 then
            -- We have only a t2 HQ
            if (self.brain.monitor.units.facs.land.total.t3 > 0) or (mass > 70) or (self.brain.monitor.units.land.mass.total > 7000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t3HQJob.count = 1
                self.t3HQJob.targetSpend = math.min(40,mass)
            end
        else
            -- We have no HQs
            -- Otherwise make a decision based on available mass/unit investment
            if (self.brain.monitor.units.facs.land.total.t2 + self.brain.monitor.units.facs.land.total.t3 > 0)
                    or (mass > 30) or (self.brain.monitor.units.land.mass.total > 3000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t2HQJob.count = 1
                self.t2HQJob.targetSpend = math.min(20,mass)
            end
        end
        -- Update remaining mass
        massRemaining = math.max(0,massRemaining - self.t2HQJob.actualSpend - self.t3HQJob.actualSpend)

        -- Factory support upgrade decisions (2)
        --    Based on:
        --        - HQ availability
        --        - Spend per factory (by tier)
        --        - investment in units
        local t1Spend = self.t1ScoutJob.actualSpend + self.t1TankJob.actualSpend + self.t1ArtyJob.actualSpend + self.t1AAJob.actualSpend
        local t2Spend = self.t2TankJob.actualSpend + self.t2HoverJob.actualSpend + self.t2AAJob.actualSpend + self.t2MMLJob.actualSpend
        local t2Target = self.t2TankJob.targetSpend + self.t2HoverJob.targetSpend + self.t2AAJob.targetSpend + self.t2MMLJob.targetSpend
        local t3Spend = self.t3LightJob.actualSpend + self.t3HeavyJob.actualSpend + self.t3AAJob.actualSpend + self.t3ArtyJob.actualSpend
        local t3Target = self.t3LightJob.targetSpend + self.t3HeavyJob.targetSpend + self.t3AAJob.targetSpend + self.t3ArtyJob.targetSpend
        self.facJob.targetSpend = 0
        self.t2SupportJob.targetSpend = 0
        self.t2SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t1/4,math.max(self.brain.monitor.units.facs.land.total.t2/2,self.brain.monitor.units.facs.land.total.t3))
        self.t3SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t2/4,self.brain.monitor.units.facs.land.total.t3/2)
        self.t3SupportJob.targetSpend = 0
        if (t3Spend < t3Target/1.2) and (self.brain.monitor.units.facs.land.idle.t3 == 0) then
            if self.brain.monitor.units.facs.land.total.t2 - self.brain.monitor.units.facs.land.hq.t2 > 0 then
                self.t3SupportJob.targetSpend = t3Target - t3Spend
            elseif self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = t3Target - t3Spend
            else
                self.facJob.targetSpend = t3Target - t3Spend
            end
        end
        if t2Spend < t2Target/1.2 and (self.brain.monitor.units.facs.land.idle.t2 == 0) then
            if self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = self.t2SupportJob.targetSpend + t2Target - t2Spend
            else
                self.facJob.targetSpend = self.facJob.targetSpend + t2Target - t2Spend
            end
        end
        massRemaining = math.max(0,massRemaining - self.t2SupportJob.actualSpend - self.t3SupportJob.actualSpend - self.facJob.actualSpend)

        -- T1,T2,T3,Exp spending allocations + ratios (1)
        --    Based on:
        --        - Available factories
        --        - Available mass
        --        - Enemy intel (TODO)
        --    Remember Hi Pri tank decisions (for early game)
        if massRemaining > 100 and self.brain.monitor.units.engies.t3 > 0 then
            -- Time for an experimental
            self.expJob.targetSpend = (massRemaining-50)*0.8
        else
            self.expJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - self.expJob.actualSpend)
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T3 spend
            self.t3LightJob.targetSpend = 0
            self.t3HeavyJob.targetSpend = 0
            self.t3AAJob.targetSpend = 0
            self.t3ArtyJob.targetSpend = 0
            local actualMass = massRemaining*1.2
            if self.brain.monitor.units.land.count.t3 < 16 then
                self.t3LightJob.targetSpend = actualMass*0.8
                self.t3AAJob.targetSpend = actualMass*0.2
            else
                self.t3HeavyJob.targetSpend = actualMass*0.9
                self.t3AAJob.targetSpend = actualMass*0.1
            end
        end
        massRemaining = math.max(0,massRemaining - t3Spend)
        if self.brain.monitor.units.facs.land.hq.t2+self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T2 spend
            local actualMass = massRemaining*1.2
            self.t2TankJob.targetSpend = 0
            self.t2HoverJob.targetSpend = 0
            self.t2AAJob.targetSpend = 0
            self.t2MMLJob.targetSpend = 0
            if self.brain.monitor.units.land.count.t2 < 20 then
                self.t2TankJob.targetSpend = actualMass * 0.8
                self.t2AAJob.targetSpend = actualMass * 0.2
            else
                self.t2TankJob.targetSpend = actualMass * 0.6
                self.t2AAJob.targetSpend = actualMass * 0.1
                self.t2MMLJob.targetSpend = actualMass * 0.3
            end
        end
        massRemaining = math.max(0,massRemaining - t2Spend)
        if true then
            -- T1 spend
            local actualMass = massRemaining*1.2
            self.t1ScoutJob.targetSpend = 0
            self.t1TankJob.targetSpend = 0
            self.t1ArtyJob.targetSpend = 0
            self.t1AAJob.targetSpend = 0
            if (self.brain.monitor.units.land.count.total > 0) and (self.brain.monitor.units.land.count.scout < 0.1 + math.log(self.brain.monitor.units.land.count.total)) then
                self.t1ScoutJob.targetSpend = 5
            end
            if self.brain.monitor.units.land.count.total < 20 then
                self.t1TankJob.targetSpend = actualMass
            elseif self.brain.monitor.units.land.count.t2+self.brain.monitor.units.land.count.t3 < 10 then
                self.t1TankJob.targetSpend = actualMass*0.7
                self.t1ArtyJob.targetSpend = actualMass*0.3
            elseif self.brain.monitor.units.land.mass.total < 5000 then
                self.t1TankJob.targetSpend = actualMass*0.8
                self.t1ArtyJob.targetSpend = actualMass*0.2
            else
                self.t1TankJob.targetSpend = actualMass*0.5
                self.t1ArtyJob.targetSpend = actualMass*0.5
            end
        end
        massRemaining = math.max(0,massRemaining - t1Spend)

        -- Upgrade jobs to high/critical priority if there's an urgent need for them (4)
        -- T1 tanks early game
        -- AA if being bombed
        if (self.brain.monitor.units.land.count.total < 30) and (((self.brain.monitor.units.engies.t1 - 1) * 2) > self.brain.monitor.units.land.count.total) then
            self.t1TankJob.priority = HIGH
            self.t1ArtyJob.priority = HIGH
        else
            self.t1TankJob.priority = NORMAL
            self.t1ArtyJob.priority = NORMAL
        end
        if self.baseZone.control.air.enemy < 0.5 then
            self.t3AAJob.priority = NORMAL
            self.t2AAJob.priority = NORMAL
            self.t1AAJob.priority = NORMAL
        else
            self.t3AAJob.priority = CRITICAL
            self.t3AAJob.targetSpend = math.max(10,self.t3AAJob.targetSpend)
            self.t2AAJob.priority = CRITICAL
            self.t2AAJob.targetSpend = math.max(10,self.t2AAJob.targetSpend)
            self.t1AAJob.priority = CRITICAL
            self.t1AAJob.targetSpend = math.max(10,self.t1AAJob.targetSpend)
        end

        if massRemaining > 0 and self.brain.base.isBOComplete
                             and self.brain.monitor.units.facs.land.idle.t1+self.brain.monitor.units.facs.land.idle.t2+self.brain.monitor.units.facs.land.idle.t3 == 0 then
            self.facJob.targetSpend = self.facJob.targetSpend + massRemaining
        end
    end,

    ManageIslandJobs = function(self,mass)
        local massRemaining = mass
        -- Dodgy copy paste because I have no time while writing this :)
        self.t2HQJob.targetSpend = 0
        self.t2HQJob.count = 0
        self.t3HQJob.targetSpend = 0
        self.t3HQJob.count = 0
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- We have a t3 HQ
        elseif self.brain.monitor.units.facs.land.hq.t2 > 0 then
            -- We have only a t2 HQ
            if (self.brain.monitor.units.facs.land.total.t3 > 0) or (mass > 70) or (self.brain.monitor.units.land.mass.total > 7000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t3HQJob.count = 1
                self.t3HQJob.targetSpend = math.min(40,mass)
            end
        else
            -- We have no HQs
            -- Otherwise make a decision based on available mass/unit investment
            if (self.brain.monitor.units.facs.land.total.t2 + self.brain.monitor.units.facs.land.total.t3 > 0) or (mass > 12) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t2HQJob.count = 1
                self.t2HQJob.targetSpend = math.min(20,mass)
            end
        end
        -- Update remaining mass
        massRemaining = math.max(0,massRemaining - self.t2HQJob.actualSpend - self.t3HQJob.actualSpend)

        -- Factory support upgrade decisions (2)
        --    Based on:
        --        - HQ availability
        --        - Spend per factory (by tier)
        --        - investment in units
        local t1Spend = self.t1ScoutJob.actualSpend + self.t1TankJob.actualSpend + self.t1ArtyJob.actualSpend + self.t1AAJob.actualSpend
        local t2Spend = self.t2TankJob.actualSpend + self.t2HoverJob.actualSpend + self.t2AAJob.actualSpend + self.t2MMLJob.actualSpend
        local t2Target = self.t2TankJob.targetSpend + self.t2HoverJob.targetSpend + self.t2AAJob.targetSpend + self.t2MMLJob.targetSpend
        local t3Spend = self.t3LightJob.actualSpend + self.t3HeavyJob.actualSpend + self.t3AAJob.actualSpend + self.t3ArtyJob.actualSpend
        local t3Target = self.t3LightJob.targetSpend + self.t3HeavyJob.targetSpend + self.t3AAJob.targetSpend + self.t3ArtyJob.targetSpend
        self.facJob.targetSpend = 0
        self.t2SupportJob.targetSpend = 0
        self.t2SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t1/4,math.max(self.brain.monitor.units.facs.land.total.t2/2,self.brain.monitor.units.facs.land.total.t3))
        self.t3SupportJob.duplicates = math.max(self.brain.monitor.units.facs.land.total.t2/4,self.brain.monitor.units.facs.land.total.t3/2)
        self.t3SupportJob.targetSpend = 0
        if (t3Spend < t3Target/1.2) and (self.brain.monitor.units.facs.land.idle.t3 == 0) then
            if self.brain.monitor.units.facs.land.total.t2 - self.brain.monitor.units.facs.land.hq.t2 > 0 then
                self.t3SupportJob.targetSpend = t3Target - t3Spend
            elseif self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = t3Target - t3Spend
            else
                self.facJob.targetSpend = t3Target - t3Spend
            end
        end
        if t2Spend < t2Target/1.2 and (self.brain.monitor.units.facs.land.idle.t2 == 0) then
            if self.brain.monitor.units.facs.land.total.t1 > 0 then
                self.t2SupportJob.targetSpend = self.t2SupportJob.targetSpend + t2Target - t2Spend
            else
                self.facJob.targetSpend = self.facJob.targetSpend + t2Target - t2Spend
            end
        end
        massRemaining = math.max(0,massRemaining - self.t2SupportJob.actualSpend - self.t3SupportJob.actualSpend - self.facJob.actualSpend)

        -- T1,T2,T3,Exp spending allocations + ratios (1)
        --    Based on:
        --        - Available factories
        --        - Available mass
        --        - Enemy intel (TODO)
        --    Remember Hi Pri tank decisions (for early game)
        if massRemaining > 100 and self.brain.monitor.units.engies.t3 > 0 then
            -- Time for an experimental
            self.expJob.targetSpend = (massRemaining-50)*0.8
        else
            self.expJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - self.expJob.actualSpend)
        if self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T3 spend
            self.t3LightJob.targetSpend = 0
            self.t3HeavyJob.targetSpend = 0
            self.t3AAJob.targetSpend = 0
            self.t3ArtyJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - t3Spend)
        if self.brain.monitor.units.facs.land.hq.t2+self.brain.monitor.units.facs.land.hq.t3 > 0 then
            -- T2 spend
            local actualMass = massRemaining*1.2
            self.t2TankJob.targetSpend = 0
            self.t2HoverJob.targetSpend = actualMass
            self.t2AAJob.targetSpend = 0
            self.t2MMLJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - t2Spend)
        if true then
            -- T1 spend
            local actualMass = massRemaining*1.2
            self.t1ScoutJob.targetSpend = 0
            self.t1TankJob.targetSpend = 0
            self.t1ArtyJob.targetSpend = 0
            self.t1AAJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - t1Spend)

        -- Upgrade jobs to high/critical priority if there's an urgent need for them (4)
        -- T1 tanks early game
        -- AA if being bombed
        if self.baseZone.control.air.enemy < 0.5 then
            self.t3AAJob.priority = NORMAL
            self.t2AAJob.priority = NORMAL
            self.t1AAJob.priority = NORMAL
        else
            self.t3AAJob.priority = CRITICAL
            self.t3AAJob.targetSpend = math.max(10,self.t3AAJob.targetSpend)
            self.t2AAJob.priority = CRITICAL
            self.t2AAJob.targetSpend = math.max(10,self.t2AAJob.targetSpend)
            self.t1AAJob.priority = CRITICAL
            self.t1AAJob.targetSpend = math.max(10,self.t1AAJob.targetSpend)
        end

        if massRemaining > 0 and self.brain.base.isBOComplete
                             and self.brain.monitor.units.facs.land.idle.t1+self.brain.monitor.units.facs.land.idle.t2+self.brain.monitor.units.facs.land.idle.t3 == 0 then
            self.facJob.targetSpend = self.facJob.targetSpend + massRemaining
        end
    end,
})

AirProduction = Class({
    --[[
        Responsible for:
            Air Factory production
            Air unit composition/production
            Air factory upgrades

        Main instance has exclusive control of HQ upgrades.
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Air"
        self.brain = brain
        self.coord = coord
        -- T1 units
        self.intieJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "IntieT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.intieJob)
        self.bomberJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "BomberT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.bomberJob)
        self.gunshipJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "GunshipT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.gunshipJob)
        self.scoutJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "AirScoutT1", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.scoutJob)
        -- T2 units
        self.intiet2Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "IntieT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.intiet2Job)
        self.bombert2Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "BomberT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.bombert2Job)
        self.gunshipt2Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "GunshipT2", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.gunshipt2Job)
        -- T3 units
        self.intiet3Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "IntieT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.intiet3Job)
        self.bombert3Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "BomberT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.bombert3Job)
        self.gunshipt3Job = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "GunshipT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.gunshipt3Job)
        self.scoutt3Job = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "ScoutT3", keep = true, priority = NORMAL })
        self.brain.base:AddFactoryJob(self.scoutt3Job)
        -- Experimental jobs
        self.airexpJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = JOB_INF, targetSpend = 0, work = "AirExp", keep = true, priority = HIGH })
        self.brain.base:AddMobileJob(self.airexpJob)
        -- Factories
        self.facJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AirFactoryT1", keep = true, priority = NORMAL })
        self.brain.base:AddMobileJob(self.facJob)
        self.t2HQfacJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 0, work = "AirHQT2", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t2HQfacJob)
        self.t3HQfacJob = self.brain.base:CreateGenericJob({ duplicates = 1, count = 0, targetSpend = 0, work = "AirHQT3", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t3HQfacJob)
        self.t2supportfacJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AirSupportT2", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t2supportfacJob)
        self.t3supportfacJob = self.brain.base:CreateGenericJob({ duplicates = JOB_INF, count = JOB_INF, targetSpend = 0, work = "AirSupportT3", keep = true, priority = HIGH })
        self.brain.base:AddUpgradeJob(self.t3supportfacJob)
    end,

    -- Good Teaching Lessons when doing the Air Builds for the Production Manager.
    -- Interesting Flexibly and farthermore I will admit not as straight forward but thats just more per say learning curve.
    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
        local massRemaining = mass
        -- Factory HQ upgrade decisions
        --    Based on:
        --        - investment in units
        --        - available mexes
        --        - available mass
        --        - existence of support factories
        self.t2HQfacJob.targetSpend = 0
        self.t2HQfacJob.count = 0
        self.t3HQfacJob.targetSpend = 0
        self.t3HQfacJob.count = 0
        if self.brain.monitor.units.facs.air.hq.t3 > 0 then
            -- We have a t3 HQ
        elseif self.brain.monitor.units.facs.air.hq.t2 > 0 then
            -- We have only a t2 HQ
            if (self.brain.monitor.units.facs.air.total.t3 > 0) or (mass > 50) or (self.brain.monitor.units.air.mass.total > 5000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t3HQfacJob.count = 1
                self.t3HQfacJob.targetSpend = math.min(40,mass)
            end
        else
            -- We have no HQs
            -- Otherwise make a decision based on available mass/unit investment
            if (self.brain.monitor.units.facs.air.total.t2 + self.brain.monitor.units.facs.air.total.t3 > 0)
                    or (mass > 15) or (self.brain.monitor.units.air.mass.total > 2000) then
                -- If we have higher tier support factories, an upgrade is high priority
                self.t2HQfacJob.count = 1
                self.t2HQfacJob.targetSpend = math.min(20,mass)
            end
        end
        -- Update remaining mass
        massRemaining = math.max(0,massRemaining - self.t2HQfacJob.actualSpend - self.t3HQfacJob.actualSpend)

        -- Factory support upgrade decisions (2)
        --    Based on:
        --        - HQ availability
        --        - Spend per factory (by tier)
        --        - investment in units
        local t1Spend = self.intieJob.actualSpend + self.bomberJob.actualSpend + self.gunshipJob.actualSpend + self.scoutJob.actualSpend
        local t2Spend = self.intiet2Job.actualSpend + self.bombert2Job.actualSpend + self.gunshipt2Job.actualSpend
        local t2Target = self.intiet2Job.targetSpend + self.bombert2Job.targetSpend + self.gunshipt2Job.targetSpend
        local t3Spend = self.intiet3Job.actualSpend + self.bombert3Job.actualSpend + self.gunshipt3Job.actualSpend + self.scoutt3Job.actualSpend
        local t3Target = self.intiet3Job.targetSpend + self.bombert3Job.targetSpend + self.gunshipt3Job.targetSpend + self.scoutt3Job.targetSpend
        self.facJob.targetSpend = 0
        self.t2supportfacJob.targetSpend = 0
        self.t2supportfacJob.duplicates = math.max(self.brain.monitor.units.facs.air.total.t1/4,math.max(self.brain.monitor.units.facs.air.total.t2/2,self.brain.monitor.units.facs.air.total.t3))
        self.t3supportfacJob.duplicates = math.max(self.brain.monitor.units.facs.air.total.t2/4,self.brain.monitor.units.facs.air.total.t3/2)
        self.t3supportfacJob.targetSpend = 0
        if (t3Spend < t3Target/1.2) and (self.brain.monitor.units.facs.air.idle.t3 == 0) then
            if self.brain.monitor.units.facs.air.total.t2 - self.brain.monitor.units.facs.air.hq.t2 > 0 then
                self.t3supportfacJob.targetSpend = t3Target - t3Spend
            elseif self.brain.monitor.units.facs.air.total.t1 > 0 then
                self.t2supportfacJob.targetSpend = t3Target - t3Spend
            else
                self.facJob.targetSpend = t3Target - t3Spend
            end
        end
        if t2Spend < t2Target/1.2 and (self.brain.monitor.units.facs.air.idle.t2 == 0) then
            if self.brain.monitor.units.facs.air.total.t1 > 0 then
                self.t2supportfacJob.targetSpend = self.t2supportfacJob.targetSpend + t2Target - t2Spend
            else
                self.facJob.targetSpend = self.facJob.targetSpend + t2Target - t2Spend
            end
        end
        massRemaining = math.max(0,massRemaining - self.t2supportfacJob.actualSpend - self.t3supportfacJob.actualSpend - self.facJob.actualSpend)

        -- T1,T2,T3,Exp spending allocations + ratios (1)
        --    Based on:
        --        - Available factories
        --        - Available mass
        --        - Enemy intel (TODO)
        --    Remember Hi Pri tank decisions (for early game)
        if massRemaining > 100 and self.brain.monitor.units.engies.t3 > 0 then
            -- Time for an experimental
            self.airexpJob.targetSpend = (massRemaining-50)*0.8
        else
            self.airexpJob.targetSpend = 0
        end
        massRemaining = math.max(0,massRemaining - self.airexpJob.actualSpend)
        if self.brain.monitor.units.facs.air.hq.t3 > 0 then
            -- T3 spend
            self.intiet3Job.targetSpend = 0
            self.bombert3Job.targetSpend = 0
            self.gunshipt3Job.targetSpend = 0
            self.scoutt3Job.targetSpend = 0
            local actualMass = massRemaining*1.2
            if self.brain.monitor.units.air.count.t3 < 50 then
                self.intiet3Job.targetSpend = actualMass*0.8
                self.scoutt3Job.targetSpend = actualMass*0.2
            else
                self.bombert3Job.targetSpend = actualMass*0.9
                self.gunshipt3Job.targetSpend = actualMass*0.2
            end
        end
        massRemaining = math.max(0,massRemaining - t3Spend)
        if self.brain.monitor.units.facs.air.hq.t2+self.brain.monitor.units.facs.air.hq.t3 > 0 then
            -- T2 spend
            local actualMass = massRemaining*1.2
            self.intiet2Job.targetSpend = 0
            self.bombert2Job.targetSpend = 0
            self.gunshipt2Job.targetSpend = 0
            if self.brain.monitor.units.air.count.t2 < 15 then
                self.intiet2Job.targetSpend = actualMass * 0.8
                self.bombert2Job.targetSpend = actualMass * 0.7
            else
                self.bombert2Job.targetSpend = actualMass * 0.5
                self.gunshipt2Job.targetSpend = actualMass * 0.1
            end
        end
        massRemaining = math.max(0,massRemaining - t2Spend)
        if true then
            -- T1 spend
            local actualMass = massRemaining*1.2
            self.intieJob.targetSpend = 0
            self.bomberJob.targetSpend = 0
            self.gunshipJob.targetSpend = 0
            self.scoutJob.targetSpend = 0
            if (self.brain.monitor.units.air.count.total > 0) and (self.brain.monitor.units.air.count.scout < 0.1 + math.log(self.brain.monitor.units.air.count.total)) then
                self.scoutJob.targetSpend = 5
            end
            if self.brain.monitor.units.air.count.total < 20 then
                self.intieJob.targetSpend = actualMass
            elseif self.brain.monitor.units.air.count.t2+self.brain.monitor.units.air.count.t3 < 10 then
                self.bomberJob.targetSpend = actualMass*0.7
                self.gunshipJob.targetSpend = actualMass*0.3
            elseif self.brain.monitor.units.air.mass.total < 5000 then
                self.bomberJob.targetSpend = actualMass*0.8
                self.gunshipJob.targetSpend = actualMass*0.2
            else
                self.bomberJob.targetSpend = actualMass*0.5
                self.gunshipJob.targetSpend = actualMass*0.5
            end
        end
        massRemaining = math.max(0,massRemaining - t1Spend)

        -- Upgrade jobs to high/critical priority if there's an urgent need for them (4)
        -- T1 Inties/Bombers early game
        -- More Inties if being bombed
        if (self.brain.monitor.units.air.count.total < 30) and (((self.brain.monitor.units.engies.t1 - 1) * 2) > self.brain.monitor.units.air.count.total) then
            self.intieJob.priority = HIGH
            self.bomberJob.priority = HIGH
        else
            self.intieJob.priority = NORMAL
            self.bomberJob.priority = NORMAL
        end
        if self.baseZone.control.air.enemy < 0.5 then
            self.intieJob.priority = NORMAL
            self.intiet2Job.priority = NORMAL
            self.intiet3Job.priority = NORMAL
        else
            self.intiet3Job.priority = CRITICAL
            self.intiet3Job.targetSpend = math.max(10,self.intiet3Job.targetSpend)
            self.intiet2Job.priority = CRITICAL
            self.intiet2Job.targetSpend = math.max(10,self.intiet2Job.targetSpend)
            self.intieJob.priority = CRITICAL
            self.intieJob.targetSpend = math.max(10,self.intieJob.targetSpend)
        end

        if massRemaining > 0 and self.brain.base.isBOComplete
                             and self.brain.monitor.units.facs.air.idle.t1+self.brain.monitor.units.facs.air.idle.t2+self.brain.monitor.units.facs.air.idle.t3 == 0 then
            self.facJob.targetSpend = self.facJob.targetSpend + massRemaining
        end
    end,
})

NavyProduction = Class({
    --[[
        TODO
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Navy"
        self.brain = brain
        self.coord = coord
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
    end,
})

TacticalProduction = Class({
    --[[
        Responsible for:
            TML / TMD
            Nukes / AntiNuke
            Base Shielding
            T3 Artillery
            Game Enders - e.g. T3 artillery, paragon, novax, etc

        Subsidiary instances restricted to cheap stuff (tmd/tml/shields)
    ]]

    Initialise = function(self,brain,coord)
        self.name = "Tactical"
        self.brain = brain
        self.coord = coord
    end,

    -- Called every X ticks, does the job management.  Passed the mass assigned this funding round.
    ManageJobs = function(self,mass)
    end,
})