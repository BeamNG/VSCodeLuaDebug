#!/usr/bin/python3

import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
import time
import threading
import json


hostName = "localhost"
hostPort = 56789

def socketReadline(sock):
  tmp = ''
  while True:
    data = sock.recv(1).decode()
    tmp = tmp + data
    if '\n' in data: break
  return tmp

def send(conn, data):
  body = json.dumps(data)
  print('S|>|' + body)
  packet = '#' + str(len(body)) + "\n" + body
  conn.send(packet.encode())

def receive(conn):
  header = socketReadline(conn)
  if not header or header[0] != '#':
    print("== protocol error: got header: '"+ header+"'")
    return None
  bodySize = int(header[1:])
  body = conn.recv(bodySize).decode()
  if not body:
    return None
  print('S|<|' + body)
  return json.loads(body)

def connectionHandler(conn, addr):
  print('Connection address:', addr)
  send(conn, {'command': 'welcome', 'sourceBasePath': '.'})

  while 1:
      data = receive(conn)
      # TODO: actually do sth with the data? ;)
      #print("data: " + str(data))
      if not data:
        break
  print('client gone: ' + str(conn))

def dummyVSCodeServerMain():
  s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  s.bind((hostName, hostPort))
  s.listen(1)

  while 1:
    conn, addr = s.accept()
    thread = threading.Thread(target = connectionHandler, args = (conn, addr))
    thread.daemon = True
    thread.start()


def startVSCodeDummyServer():
  thread = threading.Thread(target = dummyVSCodeServerMain)
  thread.daemon = True
  thread.start()
  return thread #thread.join()
