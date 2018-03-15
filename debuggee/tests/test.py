#!/usr/bin/python3

import urllib.request
import subprocess
import os
import sys
import shutil
import stat
from dummyVSCodeServer import *

versions_totest = [
  'lua-5.3.4',
  'lua-5.3.3',
  'lua-5.3.2',
  'lua-5.3.1',
  'lua-5.3.0',
  'lua-5.2.4',
  'lua-5.2.3',
  'lua-5.2.2',
  'lua-5.2.1',
  'lua-5.2.0',
  'lua-5.1.5',
  'lua-5.1.4',
  'lua-5.1.3',
  'lua-5.1.2',
  'lua-5.1.1',
  'lua-5.1',
  'lua-5.0.3',
  'lua-5.0.2',
  'lua-5.0.1',
  'lua-5.0',
  'lua-4.0.1',
  'lua-4.0',
  'LuaJIT-2.1.0-beta3',
  'LuaJIT-2.1.0-beta2',
  'LuaJIT-2.1.0-beta1',
  'LuaJIT-2.0.5',
  'LuaJIT-2.0.4',
  'LuaJIT-2.0.3',
  'LuaJIT-2.0.2',
  'LuaJIT-2.0.1',
  'LuaJIT-2.0.0',
  # the following, old versions do not build with VS2017:
  #'LuaJIT-1.1.8',
  #'LuaJIT-1.1.7',
  #'LuaJIT-1.1.6',
  #'LuaJIT-1.1.5',
  #'LuaJIT-1.1.4',
  #'LuaJIT-1.1.3',
]

vcvarsall = r'C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvarsall.bat'
archs = ['x64'] # ,'x86']
msvc_arch_fix = { 'x86': 'win32' }

# recursive delete, ignoring errors
def rmDir(folder):
  try:
    if os.path.exists(folder):
      # hack to be able to delete read only files
      def del_rw(action, name, exc):
        os.chmod(name, stat.S_IWRITE)
        os.remove(name)
      shutil.rmtree(folder, onerror=del_rw)
  except Exception as e:
    #print("Exception while delecting folder: ", e)
    pass

def downloadURL(url, fn):
  try:
    with urllib.request.urlopen(url) as response, open(fn, 'wb') as out_file:
      out_file.write(response.read())
    return True
  except:
    print("URL: ", url)
    return False

def downloadLua(fn):
  if fn.startswith('LuaJIT-'):
    return downloadURL('http://luajit.org/download/' + fn, fn)
  elif fn.startswith('lua-'):
    return downloadURL('https://www.lua.org/ftp/' + fn, fn)

def unpack(filename):
  try:
    if filename.endswith(".tar.gz"):
      import tarfile
      tar = tarfile.open(filename, "r:gz")
      tar.extractall()
      tar.close()
    elif filename.endswith(".zip"):
      import zipfile
      zip_ref = zipfile.ZipFile(filename, 'r')
      zip_ref.extractall('.')
      zip_ref.close()
    else:
      print("unsupported format. Unable to unpack: ", filename)
      return False
    return True
  except Exception as e:
    print(e)
    return False

def runcmd(cmd, folder, logFilename):
  #print('runcmd', cmd)
  with open(logFilename, 'w') as logfile:
    p = subprocess.Popen(cmd, shell=True, cwd=folder, stdout=logfile, stderr=logfile)
    p.wait()
    return p.returncode == 0
  return False


def compile(folder, script, arch, logFilename):
  if folder.startswith('lua-'):
    # we got to have a buildsystem first ...
    shutil.copyfile('misc/lua-premake5.lua', folder + '/../premake5.lua')
    shutil.copyfile('misc/premake5.exe', folder + '/../premake5.exe')
    return runcmd('call "' + vcvarsall + '" ' + arch + ' && premake5.exe vs2017 && cd build && msbuild lua.sln /p:Platform=' + msvc_arch_fix.get(arch, arch) + ' /nologo /p:Configuration=Release /verbosity:minimal /consoleloggerparameters:ShowTimestamp;ForceConsoleColor /maxcpucount', folder + "\\..\\", logFilename)
  elif folder.startswith('LuaJIT-'):
    return runcmd('call "' + vcvarsall + '" ' + arch + ' && ' + script, folder, logFilename)
  return False

def compileLuaSocket(folder, arch, logFilename):
  rmDir('luasocket-master/build')
  return runcmd('call "' + vcvarsall + '" ' + arch + ' && premake5.exe vs2017 --luapath=' + os.path.abspath(folder) + ' && cd build/ && msbuild luasocket.sln /p:Platform=' + msvc_arch_fix.get(arch, arch) + ' /nologo /p:Configuration=Release /verbosity:minimal /consoleloggerparameters:ShowTimestamp;ForceConsoleColor /maxcpucount', 'luasocket-master', logFilename)

# console logging helper
def clog(msg):
  sys.stdout.write(msg)
  sys.stdout.flush()

def test(folder, logFilename):
  exeName = 'luajit.exe'
  args = ''
  if folder.startswith('lua-'):
    exeName = 'lua.exe'
    args = "arg={'-noffi'};"
  runcmd( exeName + r''' -e "package.path = '..\\..\\..\\?.lua;?.lua' ; require('vscode-debuggee').start() ; ''' + args + r'''dofile('..\\..\\bench\\scimark.lua')"''', folder, logFilename)

def main():
  startVSCodeDummyServer()

  for v in versions_totest:
    successful = False
    for arch in archs:
      clog(' - ' + '%20s'%v + ' [' + arch + ']: ')
      rmDir(v)
      fext = '.tar.gz'
      #if v.startswith('LuaJIT'): fext = '.zip'
      clog("downloading")
      if not downloadLua(v + fext):
        print('** unable to download file')
        break
      clog(", unpackping")
      if not unpack(v + fext):
        print('** unable to unpack file')
        break
      logFile = v + '/src/compile.log.txt'
      clog(", compiling")
      if not compile(v + '\\src', 'msvcbuild.bat', arch, logFile):
        print('** unable to compile file')
        print('Log file: ', logFile)
        break
      logFile = v + '/src/luasocket-compile.log.txt'
      clog(", luasocket")
      if not compileLuaSocket(v + '/src', arch, logFile):
        print('** unable to compile luasocket for Lua.')
        print('Log file: ', logFile)
        break
      logFile = v + '/src/test.log.txt'
      clog(", testing: ")
      if not test(v + '/src', logFile):
        print('** test failed')
        print('Log file: ', logFile)
        break
      os.remove(v + '.zip')
      rmDir(v)
      print("OK")
      successful = True
    if not successful:
      break

if __name__ == "__main__":
  main()