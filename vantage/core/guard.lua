-- Guarded reads of the game through Ashita: a lookup or call that can't be made gives nil, never an error. It requires
-- nothing, so any module can use it.
local guard = {};

-- pcall(index_of, object, key) guards a lookup without making a closure for it.
local function index_of(object, key) return object[key]; end
guard.index_of = index_of;

-- object[key], or nil when object is nil or the lookup fails.
local function field(object, key)
    if object == nil then return nil; end
    local ok, value = pcall(index_of, object, key);
    if ok then return value; end
end
guard.field = field;

-- object:name(...), or nil when it has no such function or the function fails. The lookup is made here, not through
-- field, so a read costs no more calls than it did when each module had its own copy.
function guard.call(object, name, ...)
    if object == nil then return nil; end
    local ok, fn = pcall(index_of, object, name);
    if not ok or type(fn) ~= 'function' then return nil; end
    local done, value = pcall(fn, object, ...);
    if done then return value; end
end

-- A resource's name without control characters or the spaces around it, at most most characters long, or 200 when
-- most isn't given. Nil when it has none, or only a dot.
function guard.resource_name(resource, most)
    local value = field(field(resource, 'Name'), 1);
    if type(value) ~= 'string' then return nil; end
    value = value:gsub('%c', ''):match('^%s*(.-)%s*$');
    if value ~= '' and value ~= '.' then return value:sub(1, most or 200); end
end

return guard;
