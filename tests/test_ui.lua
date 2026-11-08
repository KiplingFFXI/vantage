local defaults = require('ui.defaults')
local hud = require('ui.hud')
local theme = require('ui.theme')
local window = require('ui.settings_window')
local s = defaults.make()
local view = hud.sample(100)
local p = s.panels.self_buffs
assert(#hud.filter_rows(view, p, 'self_buffs', s) == 6)
assert(#hud.filter_rows(view, s.panels.self_debuffs, 'self_debuffs', s) == 2)
assert(#hud.filter_rows(view, s.panels.target, 'target', s) == 2)
assert(#hud.filter_rows(view, s.panels.party, 'party', s) == 2)
s.watch_ids = {16781313}
assert(#hud.filter_rows(view, s.panels.watch, 'watch', s) == 2)
s.watch_ids = {['16781313'] = true}
assert(#hud.filter_rows(view, s.panels.watch, 'watch', s) == 2)
p.include[214] = true
local matches = hud.filter_rows(view, p, 'self_buffs', s)
assert(#matches == 2 and matches[1].key ~= matches[2].key, 'Duplicate icons stay distinct.')
p.exclude[214] = true
assert(#hud.filter_rows(view, p, 'self_buffs', s) == 0, 'Exclude takes precedence.')
p.include, p.exclude = {}, {}
p.mine_only = true
assert(#hud.filter_rows(view, p, 'self_buffs', s) == 1)
p.mine_only = false
p.filter = 'party member'
assert(#hud.filter_rows(view, p, 'self_buffs', s) == 1)
p.filter = '41'
assert(hud.filter_rows(view, p, 'self_buffs', s)[1].effect == 41)
p.filter = ''
local kind = view.rows[1].group
view.rows[1].group = 'Support'
p.groups.Support = true
assert(#hud.filter_rows(view, p, 'self_buffs', s) == 1)
view.rows[1].group = kind
p.groups = {}
p.sort, p.order = 'fixed', {251,40}
assert(hud.filter_rows(view, p, 'self_buffs', s)[1].effect == 251)
p.pinned[33] = true
assert(hud.filter_rows(view, p, 'self_buffs', s)[1].effect == 33)
p.members[555] = true
assert(#hud.filter_rows(view, p, 'self_buffs', s) > 0, 'Samples are nobody, so a member ticked keeps them.')
view.context.sample = nil
assert(#hud.filter_rows(view, p, 'self_buffs', s) == 0)
view.context.sample = true
p.members = {}
local unknown = {effect=13,name='Slow',status='unknown',present=true,entity_name='You',scope='self'}
assert(hud.timer_text(unknown, 100) == '')
assert(hud.fraction(unknown, p, 100) == nil)
assert(hud.details(unknown, 100, p):find('effect is present', 1, true))
unknown.present = nil
assert(hud.details(unknown, 100, p):find('no countdown', 1, true) and not hud.details(unknown, 100, p):lower():find('unknown', 1, true))
local loaded = {effect=40,name='Protect',status='server',deadline=220,total=nil}
p.direction, p.horizon = 'drain', 300
assert(hud.fraction(loaded, p, 100) == 0.4)
assert(hud.details(loaded, 100, p):find('The full duration was not seen', 1, true))
p.direction = 'fill'
assert(hud.fraction(loaded, p, 100) == 0.6)
-- A deadline that isn't a finite number has no countdown, so it has no bar either.
for _, deadline in ipairs({ 0/0, math.huge, -math.huge }) do
    local broken = {effect=40,name='Protect',status='server',deadline=deadline,total=180}
    assert(hud.timer_text(broken, 100) == '' and hud.fraction(broken, p, 100) == nil, tostring(deadline))
end
-- The roll and pet boxes show nothing for a time that isn't a finite number.
local box = require('ui.element_box')
assert(box.time(0/0) == '' and box.time(math.huge) == '' and box.time(-math.huge) == '' and box.time(90) == '1m')
local range = {effect=4,name='Paralysis',status='estimated',deadline=280,start=100,total=180,duration_min=30}
assert(hud.timer_text(range, 110) == '20s - 2m')
assert(hud.timer_text(range, 135) == '0s - 2m')
assert(hud.details(range, 110, p):find('upper bound', 1, true))
-- One time format everywhere, as the game shows it: hours, then minutes, then seconds.
assert(hud.time(0.1) == '1s' and hud.time(3601) == '1h' and hud.time(-10) == '0s')
local parts = { 'show_icon', 'show_name', 'show_time', 'show_target', 'show_source', 'show_elapsed', 'show_total' }
for _, key in ipairs(parts) do p[key] = false end
assert(#hud.field_lines(view.rows[1], p, 100) == 0, 'Field toggles are honored.')
for _, key in ipairs(parts) do p[key] = true end
assert(#hud.field_lines(view.rows[1], p, 100) == 5)
-- With no target or caster name those fields are left out.
local range_lines = hud.field_lines(range, p, 110)
assert(range_lines[3] == 'Range 30s - 3m' and #range_lines == 3 and not table.concat(range_lines, ' '):find('Unknown', 1, true))
p.mode = 'icons'
local rect = hud.bounds(p, s.style, 32, 800, 600)
assert(rect.row_height==s.style.icon_size, 'Icons-only measurement ignores the stored tile field toggles.')
assert(rect.shown==32 and rect.height<=600, 'Compact icons fit without reserving rows for hidden tile labels.')
p.x,p.y = 9000,9000
rect = hud.bounds(p, s.style, 2, 800, 600)
assert(rect.x + rect.width <= 800 and rect.y + rect.height <= 600)
assert(#window.search('sound') > 0 and window.search('party')[1].tab == 'Display')
assert(#window.search('sound impossible-word') == 0)
for _, name in ipairs(theme.names) do theme.apply(s, name); assert(theme.current(s) == name) end
s.style.buff_color[1] = s.style.buff_color[1] + 0.123
assert(theme.current(s) == 'Custom')
local bad = defaults.make()
bad.panels.self_buffs.mode, bad.panels.self_buffs.stack_direction = 'bars', 'vertical'
bad.style.scale, bad.style.opacity = 0/0, 100
bad.panels.self_buffs.width, bad.panels.self_buffs.labels = -1, {['33']='##Ha\nste',[4]='Bad'}
bad.alerts.rules = {defaults.rule('r'),defaults.rule('r')}
bad.alerts.rules[1].sound, bad.alerts.rules[1].thresholds = '../no.exe', {-1,0,10,10,90000}
bad.alerts.rules[2].unit, bad.alerts.rules[2].thresholds = 'percent', {10,101,50}
bad = defaults.tidy(bad)
assert(bad.style.scale == 1 and bad.style.opacity == 1)
assert(bad.panels.self_buffs.width == 24 and bad.panels.self_buffs.labels[33] == 'Haste')
assert(hud.bounds(bad.panels.self_buffs,bad.style,1,800,600).min_width>=160,'Bar rendering still enforces its readable minimum width.')
assert(bad.alerts.rules[1].id ~= bad.alerts.rules[2].id)
assert(bad.alerts.rules[1].sound == '' and #bad.alerts.rules[1].thresholds == 1)
assert(bad.alerts.rules[2].thresholds[1] == 50 and #bad.alerts.rules[2].thresholds == 2)
local copied = defaults.copy(bad)
copied.panels.self_buffs.labels[33] = 'Different'
assert(bad.panels.self_buffs.labels[33] == 'Haste', 'Profiles and resets need independent nested tables.')
bad.alerts.rules = {defaults.rule('rule_2_1'),defaults.rule('rule_2_1'),defaults.rule('rule_2_2')}
bad.job_profiles = {['5']='Support',[500]='Wrong',['bad']='Bad type',[2]={}}
bad.panels.self_buffs.include = {['0']=true,['60000']=true,[1.5]=true}
bad.watch_ids = {['16781313']=true}
bad.panels.party.members = {1002,1003}
bad = defaults.tidy(bad)
local ids = {}
for _, rule in ipairs(bad.alerts.rules) do assert(not ids[rule.id]); ids[rule.id] = true end
assert(bad.job_profiles['5']=='Support' and bad.job_profiles['500']==nil and bad.job_profiles['2']==nil)
assert(bad.panels.self_buffs.include[0] and bad.panels.self_buffs.include[60000] and not bad.panels.self_buffs.include[1.5])
assert(bad.watch_ids[1] == 16781313 and bad.panels.party.members[1002] and bad.panels.party.members[1003])
