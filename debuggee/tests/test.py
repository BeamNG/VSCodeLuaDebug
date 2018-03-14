# python3 script

import urllib.request
import zipfile
from subprocess import Popen
import os
import shutil
from dummyVSCodeServer import *

versions_totest = ['LuaJIT-2.0.0']

vcvarsall = r'C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvarsall.bat'
archs = ['x86', 'x64']
msvc_arch_fix = { 'x86': 'win32' }

luasocket_URL = 'https://github.com/diegonehab/luasocket/archive/master.zip'

def downloadURL(url, fn):
  with urllib.request.urlopen(url) as response, open(fn, 'wb') as out_file:
    out_file.write(response.read())

def downloadLuaJIT(fn):
  return downloadURL('http://luajit.org/download/' + fn, fn)


def unzip(file):
  zip_ref = zipfile.ZipFile(file, 'r')
  zip_ref.extractall('.')
  zip_ref.close()

def compile(folder, script, arch):
  p = Popen('call "' + vcvarsall + '" ' + arch + ' && ' + script, shell=True, cwd=folder)
  stdout, stderr = p.communicate()
  return p.returncode == 0

def compileLuaSocket(folder, arch):
  #if os.path.exists('luasocket-master/build'):
    #shutil.rmtree('luasocket-master/build')
  cmd = 'call "' + vcvarsall + '" ' + arch + ' && premake5.exe vs2017 --luapath=' + os.path.abspath(folder) + ' && cd build/ && msbuild luasocket.sln /p:Platform=' + msvc_arch_fix.get(arch, arch) + ' /nologo /p:Configuration=Release /verbosity:minimal /consoleloggerparameters:ShowTimestamp;ForceConsoleColor /maxcpucount'
  #print(cmd)
  p = Popen(cmd , shell=True, cwd='luasocket-master')
  stdout, stderr = p.communicate()
  return p.returncode == 0

def test(folder):
  cmd = r'''luajit.exe -e "package.path = '..\\..\\..\\?.lua;?.lua' ; require('vscode-debuggee').start() ; dofile('..\\..\\bench\\scimark.lua')"'''
  p = Popen(cmd, shell=True, cwd=folder)
  stdout, stderr = p.communicate()
  return p.returncode == 0


def main():
  startVSCodeDummyServer()

  for v in versions_totest:
    #downloadLuaJIT(v + '.zip')
    #unzip(v + '.zip')
    #compile(v + '\\src', 'msvcbuild.bat', 'x86')
    #compileLuaSocket(v + '/src', 'x86')
    test(v + '/src')
    #os.remove(v + '.zip')
    #shutil.rmtree(v)

if __name__ == "__main__":
  main()