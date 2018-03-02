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
    public class VSDebugSession : ICDPListener, IDebuggeeListener {
        protected static readonly Encoding encoding = System.Text.Encoding.UTF8;
        public ICDPSender toVSCode;

        Process process;
        string startCommand;
        string sourceBasePath;
        int startSeq;

        Dictionary<string, IDebuggee> debuggeeThreads = new Dictionary<string, IDebuggee>();
        List<IDebuggee> debuggees = new List<IDebuggee>();

        public VSDebugSession() {
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
                            FindAndSendToDebuggee(reqText);
                            break;

                        case "source":
                            SendErrorResponse(command, seq, 1020, "command not supported: " + command);
                            break;

                        default:
                            SendErrorResponse(command, seq, 1014, "unrecognized request: {_request}", new { _request = command });
                            break;
                    }
                } catch (Exception e) {
                    Utilities.LogMessageToFile("Exception in X_FromVSCode: " + e);
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

        public static string GetFullPath(string fileName) {
            if (File.Exists(fileName))
                return Path.GetFullPath(fileName);

            var values = Environment.GetEnvironmentVariable("PATH");
            foreach (var path in values.Split(Path.PathSeparator)) {
                var fullPath = Path.Combine(path, fileName);
                if (File.Exists(fullPath))
                    return fullPath;
            }
            return null;
        }

        void Launch(string command, int seq, dynamic args) {
            var arguments = (string)args.arguments;
            if (arguments == null) { arguments = ""; }

            // working directory
            string workingDirectory = (string)args.workingDirectory;
            if (workingDirectory == null) { workingDirectory = ""; }

            workingDirectory = workingDirectory.Trim();
            if (workingDirectory.Length == 0) {
                SendErrorResponse(command, seq, 3003, "Property 'workingDirectory' is empty.");
                return;
            }
            if (!Directory.Exists(workingDirectory)) {
                SendErrorResponse(command, seq, 3004, "Working directory '{path}' does not exist.", new { path = workingDirectory });
                return;
            }

            // executable
            var runtimeExecutable = (string)args.executable;
            if (runtimeExecutable == null) { runtimeExecutable = ""; }

            runtimeExecutable = runtimeExecutable.Trim();
            if (runtimeExecutable.Length == 0) {
                SendErrorResponse(command, seq, 3005, "Property 'executable' is empty.");
                return;
            }
            var runtimeExecutableFull = GetFullPath(runtimeExecutable);
            if (runtimeExecutableFull == null) {
                SendErrorResponse(command, seq, 3006, "Runtime executable '{path}' does not exist.", new { path = runtimeExecutable });
                return;
            }

            // validate argument 'env'
            Dictionary<string, string> env = null;
            var environmentVariables = args.env;
            if (environmentVariables != null) {
                env = new Dictionary<string, string>();
                foreach (var entry in environmentVariables) {
                    env.Add((string)entry.Name, entry.Value.ToString());
                }
                if (env.Count == 0) {
                    env = null;
                }
            }

            process = new Process();
            process.StartInfo.CreateNoWindow = false;
            process.StartInfo.WindowStyle = ProcessWindowStyle.Normal;
            process.StartInfo.UseShellExecute = true;
            process.StartInfo.WorkingDirectory = workingDirectory;
            process.StartInfo.FileName = runtimeExecutableFull;
            process.StartInfo.Arguments = arguments;

            process.EnableRaisingEvents = true;
            process.Exited += (object sender, EventArgs e) => {
                lock (this) {
                    toVSCode.SendMessage(new TerminatedEvent());
                }
            };

            if (env != null) {
                foreach (var entry in env) {
                    System.Environment.SetEnvironmentVariable(entry.Key, entry.Value);
                }
            }

            var cmd = string.Format("{0} {1}\n", runtimeExecutableFull, arguments);
            toVSCode.SendOutput("console", cmd);

            try {
                process.Start();
            } catch (Exception e) {
                SendErrorResponse(command, seq, 3012, "Can't launch terminal ({reason}).", new { reason = e.Message });
                return;
            }

            Attach(command, seq, args);
        }

        void Attach(string command, int seq, dynamic args) {
            Program.WaitingUI.SetLabelText("Waiting for debugee ... "); // listener.LocalEndpoint.ToString() + "...");

            sourceBasePath = (string)args.sourceBasePath;
            this.startCommand = command;
            this.startSeq = seq;

            DebuggeeServer.StartListener(this, args);
        }


        void IDebuggeeListener.VSDebuggeeConnected(IDebuggee debuggee) {
            lock (this) {
                debuggees.Add(debuggee);

                Program.WaitingUI.BeginInvoke(new Action(() => {
                    Program.WaitingUI.Hide();
                }));
                
                var welcome = new {
                    command = "welcome",
                    sourceBasePath = sourceBasePath,
                };
                debuggee.SendToDebuggee(JsonConvert.SerializeObject(welcome));

                SendResponse(startCommand, startSeq, null);
                toVSCode.SendMessage(new InitializedEvent());
                startCommand = null;
            }
        }

        void IDebuggeeListener.VSDebuggeeMessage(IDebuggee debugee, byte[] json) {
            lock (this) {
                // we intercept the messages here and reverse-engineer the local threads :)
                try {
                    string jsonString = encoding.GetString(json);
                    var j = JsonConvert.DeserializeObject<Response>(jsonString);
                    if (j.command == "threads" && j.type == "response") {
                        ThreadResponse jThread = JsonConvert.DeserializeObject<ThreadResponse>(jsonString);
                        for(int ti = 0; ti < jThread.body.threads.Count; ti++) {
                            debuggeeThreads.Add(jThread.body.threads[ti].id, debugee);
                            Utilities.LogMessageToFile("Associated thread: " + jThread.body.threads[ti].id + " -> " + debugee);
                        }
                    }
                } catch(Exception /*e*/) {
                    //Utilities.LogMessageToFile("Exception in VSDebuggeeMessage: " + e);
                }
                toVSCode.SendJSONEncodedMessage(json);
            }
        }

        void IDebuggeeListener.VSDebuggeeDisconnected(IDebuggee debugee) {
            //System.Threading.Thread.Sleep(500);
            lock (this) {
                toVSCode.SendMessage(new TerminatedEvent());
            }
        }

        private void sendToEveryone(string jsonText) {
            for (int i = 0; i < debuggees.Count; i++) {
                debuggees[i].SendToDebuggee(jsonText);
            }
        }


        private void FindAndSendToDebuggee(string jsonText) {
            // ok, figure out to what debuggee this should go
            try {
                var j = JsonConvert.DeserializeObject<Request>(jsonText);
                if (j.arguments != null) {
                    var threadIdTmp = j.arguments.Property("threadId");
                    if (threadIdTmp != null) {
                        string threadId = (string)threadIdTmp;
                        debuggeeThreads[threadId].SendToDebuggee(jsonText);
                        return;
                    }
                }
            } catch(Exception e) {
                Utilities.LogMessageToFile("Exception in FindAndSendToDebuggee: " + e);
            }
            Utilities.LogMessageToFile("[[Broadcast]]");
            sendToEveryone(jsonText);
        }
    }
}
