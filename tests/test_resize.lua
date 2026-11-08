local resize = require('ui.resize');
local rect = { x = 200, y = 150, width = 300, height = 200 };
local limits = { min_width = 120, min_height = 80, max_width = 900, max_height = 700, screen_width = 1200, screen_height = 900 };
for edge, point in pairs({ left = { 202, 220 }, right = { 498, 220 }, top = { 350, 152 }, bottom = { 350, 348 },
    top_left = { 202, 152 }, top_right = { 498, 152 }, bottom_left = { 202, 348 }, bottom_right = { 498, 348 } }) do
    assert(resize.grip(rect, point[1], point[2], 9) == edge);
    local horizontal, vertical = resize.axes(edge);
    local result = resize.rect(rect, edge, 30, 20, limits);
    if horizontal then
        local left = edge:find('left', 1, true);
        assert(result.width == (left and 270 or 330));
        assert(result.x == (left and 230 or 200));
    else assert(result.x == 200 and result.width == 300); end
    if vertical then
        local top = edge:find('top', 1, true);
        assert(result.height == (top and 180 or 220));
        assert(result.y == (top and 170 or 150));
    else assert(result.y == 150 and result.height == 200); end
    for _, delta in ipairs({ -10000, 10000 }) do
        result = resize.rect(rect, edge, delta, delta, limits);
        assert(result.x >= 0 and result.y >= 0 and result.x + result.width <= 1200 and result.y + result.height <= 900);
        assert(result.width >= 120 and result.height >= 80 and result.width <= 900 and result.height <= 700);
        if edge:find('left', 1, true) then assert(result.x + result.width == 500); end
        if edge:find('top', 1, true) then assert(result.y + result.height == 350); end
    end
end
assert(not resize.grip(rect, 350, 220) and not resize.grip(rect, 190, 150));
local small = resize.rect({ x = 0, y = 0, width = 60, height = 40 }, 'bottom_right', 40, 40,
    { min_width = 120, min_height = 80, screen_width = 60, screen_height = 40 });
assert(small.width == 60 and small.height == 40, 'A small display remains the final size limit.');
assert(rect.x == 200 and rect.width == 300, 'Gesture baselines stay unchanged.');
