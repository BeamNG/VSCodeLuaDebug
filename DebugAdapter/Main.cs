/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Copyright (c) NEXON Korea Corporation. All rights reserved.
 *  Copyright (c) BeamNG GmbH. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

using System;
using System.Windows.Forms;

namespace VSCodeDebug
{
    internal class Program
	{
        public static WaitingUI WaitingUI;

        private static void Main(string[] argv)
		{
            WaitingUI = new WaitingUI();
            Application.Run(WaitingUI);
        }

        private static ICDPSender toVSCode;

        public static void Stop()
        {
            if (toVSCode != null) {
                toVSCode.SendMessage(new TerminatedEvent());
            }
        }

        public static void DebugSessionLoop()
        {
            try
            {
                // First, assemble communication with VS Code.
                // Communication with debugger is assembled after execution of launch command.
                VSDebugSession vsDebugSession = new VSDebugSession();

                var cdp = new VSCodeDebugProtocol(vsDebugSession);
                vsDebugSession.toVSCode = cdp;
                toVSCode = cdp;

                cdp.Loop(Console.OpenStandardInput(), Console.OpenStandardOutput());
            }
            catch (Exception e)
            {
                MessageBox.OK(e.ToString());
            }
        }
    }
}
