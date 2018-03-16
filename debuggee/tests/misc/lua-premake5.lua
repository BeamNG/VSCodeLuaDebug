solution "lua"
  configurations { "Debug", "Release", "Relwithdebinfo" }
  location("premake_build/")
  platforms { 'x86', 'x64' }
  targetdir('bin')

project "lua-exec"
  kind "ConsoleApp"
  targetname('lua')
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
    'lua',
  }

project "lua"
  kind "SharedLib"
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
