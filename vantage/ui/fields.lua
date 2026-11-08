local fields = {}
local text_wrap = require('ui.text_wrap')
local order = { 'name', 'target', 'source', 'elapsed', 'total', 'time' }
local priorities = { name = 90, target = 60, source = 40, elapsed = 30, total = 30, time = 100 }
local labels = { source = 'by', elapsed = 'Elapsed', total = 'Total' }
fields.labels = labels

-- soon: the countdown takes time_color whatever else colors it.
function fields.build(row, panel, style, now, time, clock, name, time_color, soon)
    if panel.show_text == false then return {} end
    local ranged = row.duration_min and row.total and row.duration_min < row.total
    local values = { name = name, target = row.entity_name, source = row.source_name,
        elapsed = time(row.start and now - row.start or nil), total = ranged and time(row.duration_min) .. ' - ' .. time(row.total) or time(row.total),
        time = clock }
    local known = { name = true, target = row.entity_name ~= nil, source = row.source_name ~= nil, elapsed = row.start ~= nil,
        total = row.total ~= nil,
        time = row.status ~= 'unknown' and row.deadline ~= nil or row.count_up == true and row.start ~= nil }
    local colors = panel.colors or {}
    local entries = {}
    -- A field with no value is left out like a missing countdown: a target or caster with no name, and a start or full
    -- duration that was never seen.
    for _, id in ipairs(panel.field_order or order) do
        if panel['show_' .. id] and known[id]
            and not (id == 'time' and (clock == '' or tonumber(row.effect)==269 and row.domain~='recast')) then
            local value = values[id] or ''
            local label = (panel.field_labels or {})[id]
            if label == nil then label = id == 'total' and ranged and 'Range' or labels[id] or '' end
            if label ~= '' and panel.label_position ~= 'hidden' then
                local separator = panel.label_separator or ' '
                value = panel.label_position == 'after' and value .. separator .. label or label .. separator .. value
            end
            local color = id == 'time' and (colors.value or (style.status_time_color and time_color) or style.value_color or style.text_color)
                or id == 'name' and (colors.label or style.label_color or style.text_color)
                or (colors.detail or style.detail_color or style.text_color)
            local entry = { id = id, text = value, color = id == 'time' and soon and time_color or (panel.field_colors or {})[id] or color,
                size = style.font_size, priority = (panel.field_priority or {})[id] or priorities[id] or 50,
                alignment = (panel.field_alignments or {})[id] or (id == 'time' and 'right' or panel.alignment or 'left'),
                newline = (panel.field_newlines or {})[id], divider = (panel.field_dividers or {})[id], known = known[id] }
            if id == 'time' then
                entry.countdown, entry.clock = true, clock
                entry.countdown_bold, entry.countdown_shadow = panel.countdown_bold, panel.countdown_shadow
                entry.countdown_outline, entry.countdown_outline_color = panel.countdown_outline, panel.countdown_outline_color
            end
            entries[#entries + 1] = entry
        end
    end
    return entries
end

function fields.width(entry, measure)
    if not entry.runs then return measure(entry.text, entry.size, entry) end
    local result = 0
    for _, run in ipairs(entry.runs) do result = result + measure(run.text, run.size, run) end
    return result
end

function fields.text(entries, separator)
    local result = {}
    for i, entry in ipairs(entries) do
        if i > 1 then result[#result + 1] = entry.newline and '\n' or entry.divider or separator or '  ' end
        result[#result + 1] = entry.text
    end
    return table.concat(result)
end

local function width(entries, separator, measure)
    local total = 0
    for i, entry in ipairs(entries) do
        total = total + fields.width(entry, measure)
        if i > 1 then total = total + measure(entry.divider or separator, entry.size) end
    end
    return total
end

function fields.fit(entries, available, separator, measure, priority)
    local result = {}
    for _, entry in ipairs(entries) do result[#result + 1] = entry end
    if priority then
        while #result > 1 and width(result, separator, measure) > available do
            local remove = 1
            for i = 2, #result do if result[i].priority <= result[remove].priority then remove = i end end
            table.remove(result, remove)
        end
    end
    return result
end

-- Field breaks stay explicit. Wrapping creates additional lines without changing saved order.
function fields.lines(entries, available, panel, measure)
    local lines, current, used = {}, {}, 0
    local function finish()
        if #current > 0 then lines[#lines + 1], current, used = current, {}, 0 end
    end
    for _, entry in ipairs(entries) do
        if entry.newline then finish() end
        local gap = #current > 0 and measure(entry.divider or panel.separator or '  ', entry.size) or 0
        local length = fields.width(entry, measure)
        if panel.wrap and #current > 0 and used + gap + length > available then finish(); gap = 0 end
        if panel.wrap and length > available then
            local runs, text, length = {}, {}, 0
            local function part()
                local copy = {}; for key, value in pairs(entry) do copy[key] = value end
                if runs[#runs] then runs[#runs].text = runs[#runs].text:gsub('%s+$', '') end
                copy.text, copy.runs = table.concat(text):gsub('%s+$', ''), runs
                return copy
            end
            for _, run in ipairs(entry.runs or { entry }) do
                local tokens = {}
                for token in run.text:gmatch('%s*%S+%s*') do tokens[#tokens + 1] = token end
                if #tokens == 0 and run.text ~= '' then tokens[1] = run.text end
                for _, token in ipairs(tokens) do
                    if length > 0 and length + measure(token, run.size, run) > available then
                        current[#current + 1] = part(); finish(); runs, text, length = {}, {}, 0
                    end
                    if length == 0 then token = token:gsub('^%s+', '') end
                    local pieces = { token }
                    if measure(token, run.size, run) > available then
                        pieces = text_wrap.lines(token, available, function(value) return measure(value, run.size, run) end)
                        pieces[#pieces] = pieces[#pieces] .. (token:match('%s+$') or '')
                    end
                    for index, piece in ipairs(pieces) do
                        if index > 1 then
                            current[#current + 1] = part(); finish(); runs, text, length = {}, {}, 0
                        end
                        local copy = {}; for key, value in pairs(run) do if key ~= 'runs' then copy[key] = value end end
                        copy.text = piece
                        text[#text + 1], runs[#runs + 1] = piece, copy
                        length = length + measure(piece, run.size, run)
                    end
                end
            end
            local final = part()
            current[#current + 1], used = final, fields.width(final, measure)
        else current[#current + 1], used = entry, used + gap + length end
    end
    finish()
    if not panel.wrap then
        for i, line in ipairs(lines) do lines[i] = fields.fit(line, available, panel.separator or '  ', measure, panel.priority_overflow) end
    end
    return lines
end

function fields.positions(line, available, separator, measure)
    local lanes = { left = {}, center = {}, right = {} }
    for _, entry in ipairs(line) do local lane = lanes[entry.alignment] or lanes.left; lane[#lane + 1] = entry end
    local result, left_end = {}, 0
    local right_width = width(lanes.right, separator, measure)
    local right_start = math.max(0, available - right_width)
    for _, alignment in ipairs({ 'left', 'center', 'right' }) do
        local entries = lanes[alignment]
        local total = width(entries, separator, measure)
        local at = alignment == 'left' and 0 or alignment == 'right' and right_start or math.max(left_end, (available - total) / 2)
        local limit = alignment == 'right' and available or #lanes.right > 0 and right_start or available
        for i, entry in ipairs(entries) do
            local divider = i > 1 and (entry.divider or separator) or ''
            local gap = measure(divider, entry.size)
            if gap > 0 then result[#result + 1] = { entry = { text = divider, color = entry.color, size = entry.size }, x = at, width = math.max(0, limit - at) }; at = at + gap end
            local span = fields.width(entry, measure)
            result[#result + 1] = { entry = entry, x = at, width = math.max(0, math.min(span, limit - at)) }
            at = at + span
        end
        if alignment == 'left' then left_end = at end
    end
    return result
end

return fields
