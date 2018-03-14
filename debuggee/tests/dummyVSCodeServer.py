#!/usr/bin/python3

# this file implements a dummy vscode debugger host
# the purpose is to be able to profile the debugger client(debugee)
# without having vscode running

import socket
import threading
import json

# readline for sockets
def socketReadline(sock):
  tmp = ''
  while True:
    c = sock.recv(1).decode()
    tmp = tmp + c
    if c == '\n': break
  return tmp

# protocol is '#<bodysize>\n<body>
def sendPacket(conn, data):
  body = json.dumps(data)
  #print('S|>|' + body)
  packet = '#' + str(len(body)) + "\n" + body
  conn.send(packet.encode())

def receivePacket(conn):
  header = socketReadline(conn)
  if not header or header[0] != '#':
    print("== protocol error: got header: '"+ header+"'")
    return None
  bodySize = int(header[1:])
  body = conn.recv(bodySize).decode()
  if not body:
    return None
  #print('S|<|' + body)
  return json.loads(body)

def connectionHandler(conn, addr):
  #print('S|new client connected:', addr)
  sendPacket(conn, {'command': 'welcome', 'sourceBasePath': '.'})
  while True:
      data = receivePacket(conn)
      # TODO: actually do sth with the data? ;)
      #print("data: " + str(data))
      if not data:
        break
  #print('S|client gone:', addr)

# accept any clients and spawn a new thread for them to handle their protocol
def dummyVSCodeServerMain(listenAddress, listenPort):
  s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  s.bind((listenAddress, listenPort))
  s.listen()

  while True:
    conn, addr = s.accept()
    thread = threading.Thread(target = connectionHandler, args = (conn, addr))
    thread.daemon = True
    thread.start()

# server main
def startVSCodeDummyServer(listenAddress = "localhost", listenPort = 56789):
  thread = threading.Thread(target = dummyVSCodeServerMain, args = (listenAddress, listenPort))
  thread.daemon = True
  thread.start()
  return thread

if __name__ == "__main__":
  startVSCodeDummyServer()