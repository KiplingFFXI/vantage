local rows={};
package.loaded['core.recasts']={new=function() return {
    reset=function()end,update=function()end,drain_events=function()return{};end,
    view=function()return{valid=true,rows=rows,version=1};end,
};end};
local app=dofile(ADDON_DIR..'/vantage.lua');
app.refresh(1);
local defaults=require('ui.defaults');
local recast_rule=defaults.rule('Recast fallback');
recast_rule.domain,recast_rule.effect,recast_rule.name='recast',10033,'Recast fallback';
app.state.settings.alerts.rules={recast_rule};
app.refresh(2);
assert(app.alerts.compiled.entries[1].rule.effect_name=='Recast fallback');
local compiled=app.alerts.compiled;
rows={{key='recast:10033',domain='recast',effect=10033,name='Spell name',entity_id=1001,instance=1,scope='self',kind='spell',status='server',remaining=50,present=true}};
app.refresh(2.1);
assert(app.alerts.compiled~=compiled and app.alerts.compiled.entries[1].rule.effect_name=='Spell name','A newly readable recast name refreshes enrichment without editing the rule');
local state=app.alerts.states[recast_rule.id];
rows[1].name='Updated spell name';app.refresh(2.2);
assert(app.alerts.compiled.entries[1].rule.effect_name=='Updated spell name' and app.alerts.states[recast_rule.id]==state,'Name changes do not reset threshold history');
compiled=app.alerts.compiled;rows[1].remaining=49;app.refresh(2.3);
assert(app.alerts.compiled==compiled,'Changing only the countdown does not rebuild enrichment');
rows={};app.refresh(2.4);
assert(app.alerts.compiled.entries[1].rule.effect_name=='Recast fallback','Disappearing recasts restore the configured fallback');

local resource_name;
AshitaCore.GetResourceManager=function()return{GetString=function()return resource_name;end};end;
local status_rule=defaults.rule('Status fallback');status_rule.effect=999;
app.state.settings.alerts.rules={status_rule};
app.refresh(3);
assert(app.alerts.compiled.entries[1].rule.effect_name=='An effect with no name');
resource_name='Recovered status';app.refresh(3.1);
assert(app.alerts.compiled.entries[1].rule.effect_name=='Recovered status','Late client status resources refresh compiled alert names');
