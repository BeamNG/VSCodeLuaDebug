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

using System;
using System.Text.RegularExpressions;
using System.Reflection;

namespace VSCodeDebug
{
    public class Utilities {
		private static readonly Regex VARIABLE = new Regex(@"\{(\w+)\}");
		
		public static string ExpandVariables(string format, dynamic variables, bool underscoredOnly = true) {
			if (variables == null) {
				variables = new { };
			}
			Type type = variables.GetType();
			return VARIABLE.Replace(format, match => {
				string name = match.Groups[1].Value;
				if (!underscoredOnly || name.StartsWith("_")) {
					
					PropertyInfo property = type.GetProperty(name);
					if (property != null) {
						object value = property.GetValue(variables, null);
						return value.ToString();
					}
					return '{' + name + ": not found}";
				}
				return match.Groups[0].Value;
			});
		}

        // quick, slow and dirty logging
        private static Object logLock = new Object();
        public static void LogMessageToFile(string msg) {
            lock (logLock) {
                try { 
                    System.IO.StreamWriter sw = System.IO.File.AppendText(System.IO.Path.GetDirectoryName(Assembly.GetEntryAssembly().Location) + "\\LuaJITDebugAdapter.log");
                    try {
                        string logLine = System.String.Format("{0:G}: {1}.", System.DateTime.Now, msg);
                        sw.WriteLine(logLine);
                    } finally {
                        sw.Close();
                    }
                } catch (Exception /*e*/) {
                    //Program.MessageBox(IntPtr.Zero, e.ToString(), "LuaDebug", 0);
                }
            }
        }
    }
}
