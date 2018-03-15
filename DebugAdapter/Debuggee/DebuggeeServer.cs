using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace VSCodeDebug
{
    class DebuggeeServer {
        // this is a multi-threaded TCP listener.
        // it accepts all connections as fast as possible and puts the session handling into a new thread

        public static void StartListener(IDebuggeeListener listener, dynamic args) {
            TcpListener serverSocket = new TcpListener((bool)args.listenPublicly ? IPAddress.Any : IPAddress.Parse("127.0.0.1"), (int)args.listenPort);
            serverSocket.Start();
            // run main accepting loop also in a thread
            new System.Threading.Thread(() => {
                while (true) {
                    var clientSocket = serverSocket.AcceptSocket();
                    // we got a new client, create a new thread for it :)
                    if (clientSocket != null) {
                        //Utilities.LogMessageToFile(">> accepted connection from client");

                        new System.Threading.Thread(() => {
                            using (var networkStream = new NetworkStream(clientSocket)) {
                                try {
                                    DebuggeeSession d = new DebuggeeSession(listener, networkStream);
                                    d.RunSession();
                                } catch (Exception e) {
                                    Utilities.LogMessageToFile("Exception: " + e);
                                }
                            }
                            clientSocket.Close();
                            //Utilities.LogMessageToFile(">> client connection closed");
                        }).Start();
                    }
                }
            }).Start();
        }
    }
}
