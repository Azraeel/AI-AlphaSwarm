AlphaSwarmYeOldeAIBrainClass = AIBrain

local CreateAlphaSwarmBrain = import('/mods/AlphaSwarm/lua/AI/AlphaSwarm/Brain.lua').CreateBrain

AIBrain = Class(AlphaSwarmYeOldeAIBrainClass) {
    OnCreateAI = function(self, planName)
        local per = ScenarioInfo.ArmySetup[self.Name].AIPersonality
        if string.find(per, 'AlphaSwarmAIKey') then
            -- I don't call the standard OnCreateAI here, so do any necessary initialisation.
            self:CreateBrainShared(planName)
            LOG('Initialising AlphaSwarm AI - Name: ('..self.Name..') - personality: ('..per..') ')
            self.AlphaSwarm = true
            self.AlphaSwarmBrain = CreateAlphaSwarmBrain(self)
            -- Set up cheating stuff?
            local cheatPos = string.find(per, 'AlphaSwarmAIKeyCheat')
            if cheatPos then
                AIUtils.SetupCheat(self, true)
                ScenarioInfo.ArmySetup[self.Name].AIPersonality = string.sub(per, 1, cheatPos - 1)
            end
        else
            AlphaSwarmYeOldeAIBrainClass.OnCreateAI(self,planName)
        end
    end,

    InitializeSkirmishSystems = function(self)
        if not self.AlphaSwarm then
            return AlphaSwarmYeOldeAIBrainClass.InitializeSkirmishSystems(self)
        end
        -- Here lies the grave of the PlatoonFormManager; look on it's works ye mighty, and despair.
        --            _____                    _____                    _____
        --           /\    \                  /\    \                  /\    \
        --          /::\    \                /::\    \                /::\    \
        --         /::::\    \               \:::\    \              /::::\    \
        --        /::::::\    \               \:::\    \            /::::::\    \
        --       /:::/\:::\    \               \:::\    \          /:::/\:::\    \
        --      /:::/__\:::\    \               \:::\    \        /:::/__\:::\    \
        --     /::::\   \:::\    \              /::::\    \      /::::\   \:::\    \
        --    /::::::\   \:::\    \    ____    /::::::\    \    /::::::\   \:::\    \
        --   /:::/\:::\   \:::\____\  /\   \  /:::/\:::\    \  /:::/\:::\   \:::\____\
        --  /:::/  \:::\   \:::|    |/::\   \/:::/  \:::\____\/:::/  \:::\   \:::|    |
        --  \::/   |::::\  /:::|____|\:::\  /:::/    \::/    /\::/    \:::\  /:::|____|
        --   \/____|:::::\/:::/    /  \:::\/:::/    / \/____/  \/_____/\:::\/:::/    /
        --         |:::::::::/    /    \::::::/    /                    \::::::/    /
        --         |::|\::::/    /      \::::/____/                      \::::/    /
        --         |::| \::/____/        \:::\    \                       \::/____/
        --         |::|  ~|               \:::\    \                       ~~
        --         |::|   |                \:::\    \
        --         \::|   |                 \:::\____\
        --          \:|   |                  \::/    /
        --           \|___|                   \/____/
    end,

    OnIntelChange = function(self, blip, reconType, val)
        if not self.AlphaSwarm then
            return AlphaSwarmYeOldeAIBrainClass.OnIntelChange(self, blip, reconType, val)
        end
        -- I may or may not pass this through at some point
    end,
}