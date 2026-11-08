-- What Vantage makes after it loads, run as named steps a few milliseconds at a time at the top of each Present, so
-- loading is one short stall instead of one long one (docs/PERFORMANCE.md). Each owner hands out its steps
-- (warmup_steps(): { name, run }, run doing nothing once its work is done). They run in the order they are listed. A
-- deferred group waits until something wants it (want, need). The first Present after the load event runs none: it
-- still belongs to the load's stall. From the second on, each Present starts steps until 8 ms have gone, at least one.
-- The displays draw once every wanted step has run, but for a group listed apart from them (the name point's, whose
-- overhead blocks need it alone), and once a refresh has read the settings and asked for what they draw with (asked).
-- They first draw in the Present after the one their last step ran in, and that Present runs no step, so the first
-- draw's own work (icons made on first use, ImGui's glyphs) never comes on top of a full budget of steps. A command or
-- /vg report runs what is left at once (drain). A failure is said in chat in plain words, once for each part that could
-- not load, and /vg report keeps each step's name and why. Without a timing clock nothing can be budgeted: every step
-- runs in the load event, and one wanted later at the top of the next Present.
local warmup = {};

local BUDGET = 8;
-- Presents after a load whose gaps and handlers /vg report lists.
local FRAMES = 32;
-- Steps /vg report lists, in the order they ran.
local LOGGED = 128;

local performance;
local function timer()
    local ok, value = pcall(require, 'core.performance');
    if ok and type(value) == 'table' and type(value.now) == 'function' and type(value.record) == 'function' then return value; end
end

-- entries in order: { name, run, group, what, done }. groups by name: { wanted, left (not done), displays (false when
-- the displays don't wait for it), note }.
local entries, groups = {}, {};
local spread, busy, opened, idle, first = false, false, true, true, false;
-- The Present the displays' last step ran in: they wait for the next. asked: what they need has been asked for
-- (asked()); they wait for that too. early: only a command at the title screen has asked so far.
local held, asked, early = nil, true, false;
local report, reported = nil, {};
local log;

local function new_log()
    return { presents = {}, steps = {}, failed = {}, drains = 0, restarts = 0, work = 0, counting = false, count = 0 };
end
log = new_log();

local function now() return performance and performance.now() or 0; end

-- The first wanted step not run yet, of group only when it is given.
local function next_entry(only)
    if idle and not only then return nil; end
    for _, entry in ipairs(entries) do
        if not entry.done and (not only or entry.group == only) and groups[entry.group].wanted then return entry; end
    end
    if not only then idle = true; end
end

-- Whether a wanted step the displays wait for is still to run.
local function displays_left()
    for _, group in pairs(groups) do
        if group.displays and group.wanted and group.left > 0 then return true; end
    end
    return false;
end

-- Chat gets what failed in plain words (what, from the step's list), once for each line: two steps of one part that
-- fail say it once. The report keeps every step's name and why.
local function fail(name, what, why)
    why = tostring(why);
    if #log.failed < LOGGED then log.failed[#log.failed + 1] = { name = name, problem = why }; end
    local part = type(what) == 'string' and what ~= '' and ' (' .. what .. ')' or '';
    local line = ('Part of Vantage could not load%s, so it goes on without it. /vg report has the reason.'):format(part);
    if reported[line] then return; end
    reported[line] = true;
    if not report then return; end
    pcall(report, line);
end

-- Runs one step. It is marked done first, so a step that fails isn't tried again and a drain inside it skips it.
local function run(entry, present)
    entry.done = true;
    local group = groups[entry.group];
    group.left = group.left - 1;
    local started = now();
    local ok, why = pcall(entry.run);
    local ms = now() - started;
    log.work, log.worked = log.work + ms, true;
    if #log.steps < LOGGED then log.steps[#log.steps + 1] = { name = entry.name, ms = ms, present = present }; end
    if not ok then fail(entry.name, entry.what, why); end
end

-- Each time no wanted step is left after steps ran, the warmup's end moves to now: finished_ms and warmup.total say
-- when its last work ended, a group asked for later included (a login after the title screen, overhead icons turned
-- on, a new graphics device).
local function finished()
    if not log.worked or next_entry() then return; end
    log.worked, log.finished_at = false, now();
    if performance and log.loaded_at then performance.record('warmup.total', log.loaded_at); end
end

-- A new load: list is { { group, steps, deferred, displays, note, what }, ... } in the order the steps run, what
-- naming the steps in plain words for chat. say(line) says a failed step in chat, once for each part. Without a
-- timing clock every step that is wanted runs now.
function warmup.start(list, say)
    performance = timer();
    spread = performance ~= nil;
    entries, groups, report, reported, log = {}, {}, say, {}, new_log();
    busy, opened, idle, first, held, asked, early = false, false, false, spread, nil, false, false;
    for _, item in ipairs(type(list) == 'table' and list or {}) do
        local group = groups[item.group];
        if not group then
            group = { wanted = not item.deferred, left = 0, displays = item.displays ~= false, note = item.note };
            groups[item.group] = group;
        end
        for _, step in ipairs(type(item.steps) == 'table' and item.steps or {}) do
            if type(step) == 'table' and type(step.run) == 'function' then
                entries[#entries + 1] = { name = tostring(step.name or item.group), run = step.run, group = item.group,
                    what = item.what, done = false };
                group.left = group.left + 1;
            end
        end
    end
    log.loaded_at, log.counting, log.last_end = performance and now(), spread, performance and now();
    if not spread then warmup.drain(); end
end

-- A part the load event makes itself that failed: said and listed as a failed step is.
function warmup.fail(name, what, why)
    fail(tostring(name), what, why);
end

-- At the top of a Present: this Present's steps. started is when its handler began. Without a clock, every step wanted
-- since the last Present. The Present the displays first draw in runs none.
function warmup.frame(started)
    if not spread then
        if not idle then warmup.drain(); end
        return;
    end
    log.count = log.count + 1;
    if log.counting then
        local presents = log.presents;
        presents[#presents + 1] = { gap_ms = (started or now()) - (log.last_end or 0), began = started or now(), steps = 0, steps_ms = 0 };
    end
    if first then
        first = false;
        if log.loaded_at then performance.record('load.first_present', log.loaded_at); end
        return;
    end
    local closed = not opened;
    if idle or busy or closed and asked and not displays_left() then return; end
    busy = true;
    local begun, ran = now(), 0;
    repeat
        local entry = next_entry();
        if not entry then break; end
        run(entry, log.count);
        ran = ran + 1;
    until now() - begun >= BUDGET;
    busy = false;
    if closed and not displays_left() then held = log.count; end
    if ran > 0 then
        performance.record('warmup.frame', begun);
        local present = log.counting and log.presents[#log.presents];
        if present then present.steps, present.steps_ms = ran, now() - begun; end
    end
    finished();
end

-- At the end of the Present's handler, for the handler times /vg report lists.
function warmup.frame_end()
    if not log.counting then return; end
    local present = log.presents[#log.presents];
    local at = now();
    if present then present.handler_ms, present.began = at - present.began, nil; end
    log.last_end = at;
    if #log.presents >= FRAMES then log.counting = false; end
end

-- Runs every wanted step not run yet, of group only when it is given, now: for a command, /vg report, and what is
-- needed without a clock. Inside a step it does nothing.
function warmup.drain(group)
    if busy then return false; end
    busy = true;
    local begun, ran = now(), 0;
    while true do
        local entry = next_entry(group);
        if not entry then break; end
        run(entry, 0);
        ran = ran + 1;
    end
    busy = false;
    if ran > 0 then
        log.drains = log.drains + 1;
        if performance then performance.record('warmup.drain', begun); end
    end
    finished();
    return true;
end

-- Asks for a deferred group's steps. They run on the next Presents, never inside the caller's.
function warmup.want(name)
    local group = groups[name];
    if not group or group.wanted then return; end
    group.wanted, idle = true, false;
end

-- Whether a wanted group still has steps to run.
function warmup.pending(name)
    local group = groups[name];
    return group ~= nil and group.wanted and group.left > 0;
end

-- Asks for a group and says whether its steps are still to run: what needs them waits while this is true. Without a
-- clock nothing waits: they run now.
function warmup.need(name)
    warmup.want(name);
    if not spread and warmup.pending(name) then warmup.drain(name); end
    return warmup.pending(name);
end

-- Runs a group's steps again, as a new graphics device needs its art made again: the displays wait for them as at
-- load. False for a group that isn't listed.
function warmup.restart(name)
    local group = groups[name];
    if not group then return false; end
    local again = 0;
    for _, entry in ipairs(entries) do
        if entry.group == name and entry.done then entry.done, group.left, again = false, group.left + 1, again + 1; end
    end
    if again == 0 then return true; end
    if group.displays then opened = false; end
    idle = false;
    log.restarts = log.restarts + 1;
    if not spread then warmup.drain(name); end
    return true;
end

-- After a load, what the displays draw with has been asked for: a refresh has read the settings, which want XI View
-- or the game's party list. The displays wait for this too, so a command or drain before it can't let them draw
-- without those. Without a clock they don't: every step runs at once there. A command at the
-- title screen, where no settings can be read, asks early: the displays draw with the defaults in use, and the first
-- refresh that reads the settings makes them wait again for what those ask for. True when they must wait again.
function warmup.asked(before_settings)
    if before_settings then
        if not asked then asked, early = true, spread; end
        return false;
    end
    asked = true;
    if not early then return false; end
    early = false;
    if not displays_left() then return false; end
    opened = false;
    return true;
end

-- Whether the displays may draw: what they need is asked for, and every wanted step they wait for has run, the last
-- one before this Present. Once true it stays true until a restart, or until the first settings after an early ask
-- want more (asked).
function warmup.ready()
    if opened then return true; end
    if held == log.count or spread and not asked or displays_left() then return false; end
    opened = true;
    if performance and log.loaded_at and not log.ready_at then
        log.ready_at, log.ready_present = now(), log.count;
    end
    return true;
end

-- At unload: nothing more runs.
function warmup.reset()
    entries, groups, busy, opened, idle, first, held, asked, early = {}, {}, false, true, true, false, nil, true, false;
    log.counting = false;
end

local function rounded(value) return type(value) == 'number' and math.floor(value * 1000 + 0.5) / 1000 or nil; end

-- For /vg report: times in ms from the end of the load event.
function warmup.report()
    local out = { spread = spread, budget_ms = BUDGET, ready = warmup.ready(), drains = log.drains, restarts = log.restarts,
        work_ms = rounded(log.work), presents = {}, steps = {}, failed = {}, later = {} };
    if not spread then out.note = 'Every step ran at once: there is no timing clock to spread them with.';
    else out.note = 'Times in ms. The steps start at the second Present after the load, about 8 ms of them a Present.'; end
    local start = log.loaded_at;
    if start then
        out.displays_ready_ms = log.ready_at and rounded(log.ready_at - start) or nil;
        out.displays_ready_present = log.ready_present;
        out.finished_ms = log.finished_at and rounded(log.finished_at - start) or nil;
    end
    for index, present in ipairs(log.presents) do
        out.presents[index] = { gap_ms = rounded(present.gap_ms), handler_ms = rounded(present.handler_ms), steps = present.steps,
            steps_ms = rounded(present.steps_ms) };
    end
    for index, step in ipairs(log.steps) do
        out.steps[index] = { name = step.name, ms = rounded(step.ms), present = step.present };
    end
    for index, failure in ipairs(log.failed) do out.failed[index] = { name = failure.name, problem = failure.problem }; end
    local seen = {};
    for _, entry in ipairs(entries) do
        local group = groups[entry.group];
        if not entry.done and not seen[entry.group] then
            seen[entry.group] = true;
            local left = { group = entry.group, steps = group.left };
            left.note = group.wanted and 'Still to run.' or group.note or 'Not needed yet.';
            out.later[#out.later + 1] = left;
        end
    end
    out.reload = log.reload;
    return out;
end

-- Reload timings: an unload keeps when it began and ended in a process environment variable (VANTAGE_RELOAD, through
-- core/patterns.lua's kernel32 store), which the next load in the same game reads once, if it is under 5 seconds
-- old, and clears. Nothing is written to disk.
local RELOAD, STALE = 'VANTAGE_RELOAD', 5000;
local store;
local function environment()
    if store == nil then
        local ok, finder = pcall(require, 'core.patterns');
        store = ok and type(finder) == 'table' and type(finder.environment) == 'function' and finder.environment(RELOAD) or false;
    end
    return store or nil;
end

-- The time now on the counter all Lua states share, in ms; nil without one.
local function absolute(source)
    if not source or type(source.origin_ms) ~= 'number' then return nil; end
    return source.origin_ms + source.now();
end

local unload_began;
-- At the start of the unload handler.
function warmup.unloading()
    unload_began = absolute(timer());
end

-- At the end of the unload handler: both times, kept for the next load.
function warmup.unloaded()
    local source, ended = environment(), absolute(timer());
    if not source or not unload_began or not ended then return; end
    local ok, process = pcall(source.process);
    if not ok or type(process) ~= 'number' then return; end
    pcall(source.write, ('1;%x;%.3f;%.3f'):format(process, unload_began, ended));
end

-- At load: an unload kept by this game process under 5 seconds before this load started gives reload.unload (its
-- handler) and reload.gap (from its end to this load's start: the old Lua state closing and this one starting).
-- Anything else is ignored. Either way the variable is taken away.
function warmup.reloaded()
    local source = environment();
    performance = performance or timer();
    if not source then return; end
    local read, text = pcall(source.read);
    if not read or type(text) ~= 'string' then return; end
    pcall(source.write, nil);
    local ok, process = pcall(source.process);
    local pid, began, ended = text:match('^1;(%x+);(%d+%.?%d*);(%d+%.?%d*)$');
    began, ended = tonumber(began), tonumber(ended);
    if not ok or not pid or tonumber(pid, 16) ~= process or not began or not ended or ended < began then return; end
    local start = performance and type(performance.origin_ms) == 'number' and performance.origin_ms;
    if not start or start < ended or start - ended > STALE then return; end
    log.reload = { unload_ms = rounded(ended - began), gap_ms = rounded(start - ended) };
    if type(performance.add) == 'function' then
        performance.add('reload.unload', ended - began);
        performance.add('reload.gap', start - ended);
    end
end

if VANTAGE_TEST_MODE then
    -- The reload store in place of the environment: { read, write, process }, or nil for none.
    function warmup._set_store(value) store = value or false; end
    warmup._BUDGET = BUDGET;
    -- Whether a group is asked for.
    function warmup.wanted(name)
        local group = groups[name];
        return group ~= nil and group.wanted;
    end
end

return warmup;
