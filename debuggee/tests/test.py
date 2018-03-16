#!/usr/bin/python3

import urllib.request
import subprocess
import os
import sys
import shutil
import stat
from distutils.dir_util import copy_tree
from dummyVSCodeServer import *

outdir = 'out'

continueOnError = True # if False, it stops upon the first error

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
  # these will not compile correctly with vs17:
  #'lua-5.0.3',
  #'lua-5.0.2',
  #'lua-5.0.1',
  #'lua-5.0',
  #'lua-4.0.1',
  #'lua-4.0', # weird folder structure
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
archs = ['x86','x64']
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

def downloadLua(outfile, fn):
  if fn.startswith('LuaJIT-'):
    return downloadURL('http://luajit.org/download/' + fn, outfile)
  elif fn.startswith('lua-'):
    return downloadURL('https://www.lua.org/ftp/' + fn, outfile)

def unpack(filename, targetDir):
  try:
    if filename.endswith(".tar.gz"):
      import tarfile
      tar = tarfile.open(filename, "r:gz")
      tar.extractall(targetDir)
      tar.close()
    elif filename.endswith(".zip"):
      import zipfile
      zip_ref = zipfile.ZipFile(filename, 'r')
      zip_ref.extractall(targetDir)
      zip_ref.close()
    else:
      print("unsupported format. Unable to unpack: ", filename)
      return False
    return True
  except Exception as e:
    print(e)
    return False

def runcmds(context, cmds, folder, logFilename):
  #print('runcmds', cmd)
  cmdfilename = context + '.bat'
  with open(os.path.join(folder, cmdfilename), 'w') as cmdfile:
    cmdfile.write("@echo on\n\n::This file is generated, be careful\n\ncd \"" + os.path.abspath(folder) + "\"\n\n")
    for cmd in cmds:
      cmdfile.write(cmd + " || goto :error\n")
    cmdfile.write('''
goto :EOF
:error
echo Failed with error #%errorlevel%.
exit /b %errorlevel%''')
  cmdfile.close()

  with open(logFilename, 'w') as logfile:
    p = subprocess.Popen(cmdfilename, shell=True, cwd=folder, stdout=logfile, stderr=logfile)
    p.wait()
    return p.returncode == 0
  return False


def compile(folder, arch, logFilename, flavor):
  if flavor == 'luajit':
    res = runcmds('compile', ['call "' + vcvarsall + '" ' + arch, 'cd src', 'msvcbuild.bat'], folder, logFilename)
    if res:
      try:
        bindir = os.path.join(folder, 'bin')
        if not os.path.isdir(bindir):
          os.makedirs(bindir, True)
        shutil.copyfile(os.path.join(folder, 'src', 'luajit.exe'), os.path.join(bindir, 'luajit.exe'))
        shutil.copyfile(os.path.join(folder, 'src', 'lua51.lib'), os.path.join(bindir, 'lua51.lib'))
        shutil.copyfile(os.path.join(folder, 'src', 'lua51.dll'), os.path.join(bindir, 'lua51.dll'))
      except:
        return False
    return res
  elif flavor == 'lua':
    # we got to have a buildsystem first ...
    shutil.copyfile(os.path.join('misc', 'lua-premake5.lua'), os.path.join(folder, 'premake5.lua'))
    shutil.copyfile(os.path.join('misc', 'premake5.exe'), os.path.join(folder, 'premake5.exe'))
    return runcmds('compile', [
'call "' + vcvarsall + '" ' + arch,
'premake5.exe vs2017',
'cd premake_build',
'msbuild lua.sln /p:Platform=' + msvc_arch_fix.get(arch, arch) + ' /nologo /p:Configuration=Release /verbosity:minimal /consoleloggerparameters:ShowTimestamp /maxcpucount',
    ], folder, logFilename)

def compileLuaSocket(folder, arch, logFilename):
  copy_tree('luasocket-master', folder + "\\luasocket-master")
  #rmDir('luasocket-master/build')
  return runcmds('compile-luasocket', [
'call "' + vcvarsall + '" ' + arch,
'premake5.exe vs2017 --luapath=' + os.path.abspath(folder),
'cd premake_build',
'msbuild luasocket.sln /p:Platform=' + msvc_arch_fix.get(arch, arch) + ' /nologo /p:Configuration=Release /verbosity:minimal /consoleloggerparameters:ShowTimestamp /maxcpucount',
  ], folder + "\\luasocket-master", logFilename)

# console logging helper
def clog(msg):
  sys.stdout.write(msg)
  sys.stdout.flush()

def test(exeName, folder, luaArgs, logFilename):
  #shutil.copyfile('bench/test-main.lua', folder + '/bin/test-main.lua')
  #shutil.copyfile('bench/mandelbrot2.lua', folder + '/bin/mandelbrot2.lua')

  shutil.copyfile('json/json.lua', folder + '/bin/json.lua')
  shutil.copyfile('json/test-main.lua', folder + '/bin/test-main.lua')
  shutil.copyfile('json/testfile.json', folder + '/bin/testfile.json')

  shutil.copyfile('../vscode-debuggee.lua', folder + '/bin/vscode-debuggee.lua')
  shutil.copyfile('../dkjson.lua', folder + '/bin/dkjson.lua')
  return runcmds('test', [exeName + ' test-main.lua ' + (' '.join(luaArgs))], folder + '\\bin', logFilename)

def main():
  startVSCodeDummyServer()
  if not os.path.isdir(outdir):
    os.makedirs(outdir, True)

  for v in versions_totest:
    successful = False
    for arch in archs:
      clog(' - ' + '%20s'%v + ' [' + arch + ']: ')
      exeName = 'luajit.exe'
      flavor = 'luajit'
      if v.startswith('lua-'):
        exeName = 'lua.exe'
        flavor = 'lua'
      archdir = os.path.join(outdir, arch)
      oname = os.path.join(archdir, v) # out name
      if not os.path.isdir(oname):
        os.makedirs(oname, True)
      #rmDir(oname)
      fext = '.tar.gz'
      if not os.path.exists(oname + fext):
        clog("downloading, ")
        if not downloadLua(oname + fext, v + fext):
          print('** unable to download file')
          break
      if not os.path.isdir(oname) or len(os.listdir(oname)) == 0:
        clog("unpackping, ")
        if not unpack(oname + fext, archdir):
          print('** unable to unpack file')
          break
      if not os.path.exists(oname + '/bin/' + exeName):
        logFile = os.path.join(oname, 'compile.log.txt')
        clog("compiling, ")
        if not compile(oname, arch, logFile, flavor):
          print('** unable to compile file')
          print('Log file: ', logFile)
          break
      if not os.path.exists(oname + '/bin/socket/core.dll'):
        logFile = os.path.join(oname, 'luasocket-compile.log.txt')
        clog("luasocket, ")
        if not compileLuaSocket(oname, arch, logFile):
          print('** unable to compile luasocket for Lua. Not using luasocket for testing ...')
          print('Log file: ', logFile)
          # luasocket is optional for this test
          #break

      logFile = os.path.join(oname, 'test.log.txt')
      clog("testing: ")
      if not test(exeName, oname, [v, arch], logFile):
        print('** test failed')
        print('Log file: ', logFile)
        break
      #os.remove(oname + fext)
      #rmDir(oname)
      print("OK")
      successful = True
    if not continueOnError and not successful:
      break

if __name__ == "__main__":
  main()