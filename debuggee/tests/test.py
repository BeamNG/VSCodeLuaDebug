#!/usr/bin/python3

import urllib.request
import zipfile
import subprocess
import os
import sys
import shutil
from dummyVSCodeServer import *

versions_totest = ['LuaJIT-2.1.0-beta3', 'LuaJIT-2.0.0']

vcvarsall = r'C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvarsall.bat'
archs = ['x86', 'x64']
msvc_arch_fix = { 'x86': 'win32' }

# recursive delete, ignoring errors
def rmDir(folder):
  try:
    if os.path.exists(folder):
      shutil.rmtree(folder)
  except:
    pass

def downloadURL(url, fn):
  try:
    with urllib.request.urlopen(url) as response, open(fn, 'wb') as out_file:
      out_file.write(response.read())
    return True
  except:
    return False

def downloadLuaJIT(fn):
  return downloadURL('http://luajit.org/download/' + fn, fn)

def unzip(file):
  try:
    zip_ref = zipfile.ZipFile(file, 'r')
    zip_ref.extractall('.')
    zip_ref.close()
    return True
  except:
    return False

def compile(folder, script, arch, logFilename):
  with open(logFilename, 'w') as logfile:
    p = subprocess.Popen('call "' + vcvarsall + '" ' + arch + ' && ' + script, shell=True, cwd=folder, stdout=logfile, stderr=logfile)
    p.wait()
    return p.returncode == 0
  return False

def compileLuaSocket(folder, arch, logFilename):
  rmDir('luasocket-master/build')
  cmd = 'call "' + vcvarsall + '" ' + arch + ' && premake5.exe vs2017 --luapath=' + os.path.abspath(folder) + ' && cd build/ && msbuild luasocket.sln /p:Platform=' + msvc_arch_fix.get(arch, arch) + ' /nologo /p:Configuration=Release /verbosity:minimal /consoleloggerparameters:ShowTimestamp;ForceConsoleColor /maxcpucount'
  with open(logFilename, 'w') as logfile:
    p = subprocess.Popen(cmd , shell=True, cwd='luasocket-master', stdout=logfile, stderr=logfile)
    p.wait()
    return p.returncode == 0
  return False

# console logging helper
def clog(msg):
  sys.stdout.write(msg)
  sys.stdout.flush()

def test(folder, logFilename):
  cmd = r'''luajit.exe -e "package.path = '..\\..\\..\\?.lua;?.lua' ; require('vscode-debuggee').start() ; dofile('..\\..\\bench\\scimark.lua')"'''
  with open(logFilename, 'w') as logfile:
    p = subprocess.Popen(cmd, shell=True, cwd=folder, stdout=logfile, stderr=logfile)
    p.wait()
    return p.returncode == 0
  return False

def main():
  startVSCodeDummyServer()

  for arch in archs:
    successful = False
    for v in versions_totest:
      clog(' - ' + v + ' [' + arch + ']: ')
      rmDir(v)
      clog("downloading")
      if not downloadLuaJIT(v + '.zip'):
        print('** unable to download file')
        break
      clog(", unzipping")
      if not unzip(v + '.zip'):
        print('** unable to unzip file')
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