// Original work by:
/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Modified by:
/*---------------------------------------------------------------------------------------------
*  Copyright (c) NEXON Korea Corporation. All rights reserved.
*  Licensed under the MIT License. See License.txt in the project root for license information.
*--------------------------------------------------------------------------------------------*/

using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace VSCodeDebug
{
    public class DebugSession : ICDPListener, IDebuggeeListener
    {
        public ICDPSender toVSCode;
        public IDebuggee debuggee;
        Process process;
        string startCommand;
        int startSeq;

        public DebugSession() {
            Program.WaitingUI.SetLabelText("Waiting for commands from Visual Studio Code...");
        }

        void ICDPListener.X_FromVSCode(string command, int seq, dynamic args, string reqText) {
            lock (this) {
                //MessageBox.OK(reqText);
                if (args == null) { args = new { }; }

                try {
                    switch (command) {
                        case "initialize":
                            Initialize(command, seq, args);
                            break;

                        case "launch":
                            Launch(command, seq, args);
                            break;

                        case "attach":
                            Attach(command, seq, args);
                            break;

                        case "disconnect":
                            Disconnect(command, seq, args);
                            break;

                        case "next":
                        case "continue":
                        case "stepIn":
                        case "stepOut":
                        case "stackTrace":
                        case "scopes":
                        case "variables":
                        case "threads":
                        case "setBreakpoints":
                        case "configurationDone":
                        case "evaluate":
                        case "pause":
                            if (debuggee != null) {
                                debuggee.SendToDebuggee(reqText);
                            }
                            break;

                        case "source":
                            SendErrorResponse(command, seq, 1020, "command not supported: " + command);
                            break;

                        default:
                            SendErrorResponse(command, seq, 1014, "unrecognized request: {_request}", new { _request = command });
                            break;
                    }
                } catch (Exception e) {
                    MessageBox.WTF(e.ToString());
                    SendErrorResponse(command, seq, 1104, "error while processing request '{_request}' (exception: {_exception})", new { _request = command, _exception = e.Message });
                    Environment.Exit(1);
                }
            }
        }

        void SendResponse(string command, int seq, dynamic body) {
            var response = new Response(command, seq);
            if (body != null) {
                response.SetBody(body);
            }
            toVSCode.SendMessage(response);
        }

        void SendErrorResponse(string command, int seq, int id, string format, dynamic arguments = null, bool user = true, bool telemetry = false) {
            var response = new Response(command, seq);
            var msg = new Message(id, format, arguments, user, telemetry);
            var message = Utilities.ExpandVariables(msg.format, msg.variables);
            response.SetErrorBody(message, new ErrorResponseBody(msg));
            toVSCode.SendMessage(response);
        }

        void Disconnect(string command, int seq, dynamic arguments) {
            if (process != null) {
                try {
                    // TODO
                    //process.Kill();
                }
                catch(Exception) {
                    // If it exits normally, it comes in this path.
                }
                process = null;
            }
            SendResponse(command, seq, null);
            toVSCode.Stop();
        }

        void Initialize(string command, int seq, dynamic args) {
            SendResponse(command, seq, new Capabilities() {
                supportsConfigurationDoneRequest = true,
                supportsFunctionBreakpoints = false,
                supportsConditionalBreakpoints = false,
                supportsEvaluateForHovers = false,
                exceptionBreakpointFilters = new dynamic[0]
            });
        }

        void Launch(string command, int seq, dynamic args) {
            // TODO
            Attach(command, seq, args);
        }

        void Attach(string command, int seq, dynamic args) {
            Program.WaitingUI.SetLabelText("Waiting for debugee ... "); // listener.LocalEndpoint.ToString() + "...");

            this.startCommand = command;
            this.startSeq = seq;
            DebuggeeServer.StartListener(this, args);
        }


        void IDebuggeeListener.VSDebuggeeConnected(IDebuggee debuggee) {
            lock (this) {
                this.debuggee = debuggee;

                Program.WaitingUI.BeginInvoke(new Action(() => {
                    Program.WaitingUI.Hide();
                }));
                
                var welcome = new {
                    command = "welcome",
                };
                debuggee.SendToDebuggee(JsonConvert.SerializeObject(welcome));

                SendResponse(startCommand, startSeq, null);
                toVSCode.SendMessage(new InitializedEvent());
                startCommand = null;
            }
        }

        void IDebuggeeListener.VSDebuggeeMessage(IDebuggee debugee, byte[] json) {
            lock (this) {
                toVSCode.SendJSONEncodedMessage(json);
            }
        }

        void IDebuggeeListener.VSDebuggeeDisconnected(IDebuggee debugee) {
            //System.Threading.Thread.Sleep(500);
            lock (this) {
                toVSCode.SendMessage(new TerminatedEvent());
            }
        }
    }
}
