"""Run Vantage fixtures in separate LuaJIT runtimes, without the game."""
from pathlib import Path
import os
import sys
import tempfile

from lupa import luajit21

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent / 'vantage'
if not os.environ.get('ASHITA_LIBS'):
    raise SystemExit('Set ASHITA_LIBS to the Ashita addons/libs folder (addons/libs in an Ashita install).')
ASHITA_LIBS = Path(os.environ['ASHITA_LIBS'])
# The strict json.lua Vantage ships as core.json, the decoder players run, instead of the game folder's copy.
JSON = ADDON / 'core/json.lua'
# What client_image_fixture.lua stops with. The images are game code, so a fresh copy of the repository has none.
NO_IMAGE = 'no client image'


def runtime(install):
    install = Path(install).resolve()
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = ... .. package.path', ';'.join((
        ADDON.as_posix() + '/?.lua', HERE.as_posix() + '/?.lua', ASHITA_LIBS.as_posix() + '/?.lua', '')))
    lua.execute('local path = ...; package.preload.json = function() return dofile(path) end', JSON.as_posix())
    lua.globals().MOCK_INSTALL_PATH = install.as_posix()
    lua.globals().ADDON_DIR = ADDON.as_posix()
    lua.globals().ASHITA_LIBS = ASHITA_LIBS.as_posix()
    lua.globals().VANTAGE_TEST_MODE = True

    def mkdir(path):
        target = Path(path).resolve()
        if not target.is_relative_to(install):
            raise RuntimeError('Tests may create folders only inside their temporary install.')
        target.mkdir(parents=True, exist_ok=True)
        return True

    lua.globals().MOCK_MKDIR = mkdir
    config = install / 'config/addons/vantage'
    mkdir(config)
    lua.execute((HERE / 'mock_ashita.lua').read_text(encoding='utf-8'))
    lua.globals().MOCK.fs[config.as_posix() + '/'] = True
    lua.execute('''
        TEST_ASSERTIONS = 0;
        local original = assert;
        assert = function(...)
            TEST_ASSERTIONS = TEST_ASSERTIONS + 1;
            return original(...);
        end;
    ''')
    return lua


def main(names):
    tests = [HERE / name for name in names] if names else sorted(HERE.glob('test_*.lua'))
    failures, assertions, skipped = 0, 0, 0
    with tempfile.TemporaryDirectory(prefix='vantage_syntax_') as folder:
        lua = runtime(folder)
        compile_lua = lua.eval('function(path) local fn, err = loadfile(path); return fn ~= nil, err end')
        sources = sorted(ADDON.rglob('*.lua'))
        for source in sources:
            valid, error = compile_lua(source.as_posix())
            if not valid:
                print('FAIL syntax %s: %s' % (source.relative_to(ADDON), error))
                failures += 1
        print('Compiled %d runtime Lua files.' % len(sources))
    for test in tests:
        with tempfile.TemporaryDirectory(prefix='vantage_test_') as folder:
            lua = runtime(folder)
            try:
                lua.execute(test.read_text(encoding='utf-8'))
                count = int(lua.globals().TEST_ASSERTIONS)
                if count < 1:
                    raise AssertionError('Fixture made no assertions.')
                assertions += count
                print('PASS %s: %d assertions' % (test.name, count))
            except Exception as error:
                if NO_IMAGE in str(error):
                    skipped += 1
                    print('SKIP %s: %s' % (test.name, NO_IMAGE))
                    continue
                failures += 1
                print('FAIL %s: %s' % (test.name, error))
    if not tests:
        print('FAIL no test fixtures found.')
        failures += 1
    print('%d fixtures, %d assertions, %d failures, %d skipped.' % (len(tests), assertions, failures, skipped))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
