newoption {
  trigger     = "luapath",
  description = "Path to the lua sources to build for",
  default     = 'lua/',
}

solution "luasocket"
  configurations { "Debug", "Release", "Relwithdebinfo" }
  location("premake_build/")
  platforms { 'x86', 'x64' }
  targetname('core')
  targetdir(_OPTIONS['luapath'] .. '/bin/socket/')

project "luasocket"
  kind "SharedLib"
  defines {
    'LUASOCKET_INET_PTON=1',
    'LUASOCKET_INET_ATON=1',
    'LUA_BUILD_AS_DLL',
    '_WINSOCK_DEPRECATED_NO_WARNINGS',
  	'LUASOCKET_API=__declspec(dllexport)',
	  'MIME_API=__declspec(dllexport)',
  }
  buildoptions {
    '-D_WIN32_WINNT=0x501',
  }
  includedirs  {
    'src',
    _OPTIONS['luapath'] .. '/src/',
    _OPTIONS['luapath'] .. '/include/' -- for old lua versions
  }
  files {
    "src/**.h",
    "src/**.c",
  }
  removefiles {
    -- remove unix things
    'src/unix*',
    'src/usocket*',
    'src/serial*',
  }
  links { "ws2_32.lib", _OPTIONS['luapath'] .. '/bin/lualib.lib' }
  local luasocket_path  = path.translate(path.getabsolute('.'), '\\')
  postbuildcommands {
    -- copy the lua files
    'copy /Y ' .. luasocket_path .. '\\src\\socket.lua ' .. path.translate(path.getabsolute(_OPTIONS['luapath'])) .. '\\bin\\'
  }
