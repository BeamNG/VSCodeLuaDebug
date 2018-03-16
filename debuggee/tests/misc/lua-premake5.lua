solution "lua"
  configurations { "Debug", "Release", "Relwithdebinfo" }
  location("premake_build/")
  platforms { 'x86', 'x64' }
  targetdir('bin')
  symbols "On"
  symbolspath 'bin/$(TargetName).pdb'

project "lua-exec"
  kind "ConsoleApp"
  targetname('lua')
  largeaddressaware "on"
  characterset "ASCII" -- prevents compiling in UNICODE
  defines {
    'LUA_COMPAT_ALL',
    'LUA_BUILD_AS_DLL',
  }
  includedirs  {
    'src',
    'include', -- used in old lua distributions
  }
  files {
    "src/lua.h",
    "src/lua.c",
  }
  links {
    'lualib',
  }

project "lualib"
  kind "SharedLib"
  largeaddressaware "on"
  characterset "ASCII"  -- prevents compiling in UNICODE
  defines {
    'LUA_COMPAT_ALL',
    'LUA_BUILD_AS_DLL',
  }
  includedirs  {
    'src',
    'include', -- used in old lua distributions
  }
  files {
    "src/**.h",
    "src/**.c",
  }
  removefiles {
  	'src/luac**',
  	'src/lua.*',
  }
