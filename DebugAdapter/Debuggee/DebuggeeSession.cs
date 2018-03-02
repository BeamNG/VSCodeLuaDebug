using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using System.Net.Sockets;

namespace VSCodeDebug
{
    class DebuggeeSession : IDebuggee {
        //Encoding encoding;
        protected static readonly Encoding encoding = System.Text.Encoding.UTF8;
        NetworkStream networkStream;
        IDebuggeeListener debuggeeListener;

        const bool debuglogProtocol = true;

        public DebuggeeSession(IDebuggeeListener debuggeeListener, NetworkStream networkStream) {
            this.debuggeeListener = debuggeeListener;
            this.networkStream = networkStream;
        }

        private void Disconnect() {
            // let VS know we are gone
            debuggeeListener.VSDebuggeeDisconnected(this);
        }

        public void RunSession() {
            try {
                ByteBuffer recvBuffer = new ByteBuffer();
                debuggeeListener.VSDebuggeeConnected(this);
                var tempBuffer = new byte[9046];
                while (true) {
                    var read = networkStream.Read(tempBuffer, 0, tempBuffer.Length);

                    if (read == 0) { break; } // end of stream
                    if (read > 0) {
                        recvBuffer.Append(tempBuffer, read);
                        while (ProcessData(ref recvBuffer)) { }
                    }
                }
            } catch (Exception /*e*/) {
                //Program.MessageBox(IntPtr.Zero, e.ToString(), "LuaDebug", 0);
            }
            Disconnect();
        }

        bool ProcessData(ref ByteBuffer recvBuffer) {
            string s = recvBuffer.GetString(encoding);
            int headerEnd = s.IndexOf('\n');
            if (headerEnd < 0) { return false; }

            string header = s.Substring(0, headerEnd);
            if (header[0] != '#') { throw new Exception("Broken header:" + header); }
            var bodySize = int.Parse(header.Substring(1));

            // Because the headers are all 0 - 127 ASCII characters only
            // The results are the same when calculated as string length and as number of bytes.
            if (recvBuffer.Length < headerEnd + 1 + bodySize) { return false; }

            recvBuffer.RemoveFirst(headerEnd + 1);
            byte[] bodyBytes = recvBuffer.RemoveFirst(bodySize);

            string body = encoding.GetString(bodyBytes);
            //MessageBox.OK(body);

            if(debuglogProtocol) Utilities.LogMessageToFile(" < " + body);
            debuggeeListener.VSDebuggeeMessage(this, bodyBytes);
            return true;
        }

        public void SendToDebuggee(string reqText)  {
            if (debuglogProtocol) Utilities.LogMessageToFile(" > " + reqText);
            byte[] bodyBytes = encoding.GetBytes(reqText);
            string header = '#' + bodyBytes.Length.ToString() + "\n";
            byte[] headerBytes = encoding.GetBytes(header);
            try {
                networkStream.Write(headerBytes, 0, headerBytes.Length);
                networkStream.Write(bodyBytes, 0, bodyBytes.Length);
            } catch (IOException) {
                Disconnect();
            }
        }
    }
}
