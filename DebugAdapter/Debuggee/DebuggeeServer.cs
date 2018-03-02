using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace VSCodeDebug
{
    class DebuggeeServer {
        public static void StartListener(IDebuggeeListener listener, dynamic args) {
            TcpListener serverSocket = new TcpListener((bool)args.listenPublicly ? IPAddress.Any : IPAddress.Parse("127.0.0.1"), (int)args.listenPort);
            serverSocket.Start();

            new System.Threading.Thread(() => {
                while (true) {
                    var clientSocket = serverSocket.AcceptSocket();
                    if (clientSocket != null) {
                        Console.Error.WriteLine(">> accepted connection from client");

                        new System.Threading.Thread(() => {
                            using (var networkStream = new NetworkStream(clientSocket)) {
                                try {
                                    DebuggeeSession d = new DebuggeeSession(listener, networkStream);
                                    d.RunSession();
                                } catch (Exception e) {
                                    Console.Error.WriteLine("Exception: " + e);
                                }
                            }
                            clientSocket.Close();
                            Console.Error.WriteLine(">> client connection closed");
                        }).Start();
                    }
                }
            }).Start();
        }
    }
}
