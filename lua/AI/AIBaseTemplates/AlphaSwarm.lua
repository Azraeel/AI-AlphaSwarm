BaseBuilderTemplate {
    BaseTemplateName = 'AlphaSwarmTemplate',
    Builders = { },
    NonCheatBuilders = { },
    BaseSettings = { },
    ExpansionFunction = function(aiBrain, location, markerType)
        -- Expanding is for casuals (and people who know how this works, which I don't...)
        return 0
    end,

    FirstBaseFunction = function(aiBrain)
        local per = ScenarioInfo.ArmySetup[aiBrain.Name].AIPersonality
        if not per then 
            return 0, 'AlphaSwarmTemplate'
        end
        if per != 'AlphaSwarmAIKey' then
            return 0, 'AlphaSwarmTemplate'
        else
            return 9000, 'AlphaSwarmTemplate'
        end
    end,
}