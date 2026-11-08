local identity = { name='vantage', title='Vantage' };
local selected;
local relative = 'config/addons/vantage/';
local commands = { ['/vantage']=true, ['/vg']=true };

function identity.root()
    if not selected then
        selected=AshitaCore:GetInstallPath():gsub('[\\/]+$','')..'/'..relative;
    end;
    return selected;
end

function identity.path(suffix)
    return identity.root()..(suffix or '');
end

function identity.relative(suffix)
    return relative..(suffix or '');
end

function identity.command(value)
    return type(value)=='string' and commands[value:lower()]==true;
end

return identity;
