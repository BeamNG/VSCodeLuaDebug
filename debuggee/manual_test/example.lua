package.path = '..\\?.lua;' .. package.path

require('vscode-debuggee').start()

print("Hello world!")

-- you can also halt via code:
__halt__()

print('Bye world!')
io.read(1)