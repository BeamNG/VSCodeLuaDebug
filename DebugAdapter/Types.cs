using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace VSCodeDebug
{
    // ---- Types -------------------------------------------------------------------------

    public class Message
    {
        public int id { get; }
        public string format { get; }
        public dynamic variables { get; }
        public dynamic showUser { get; }
        public dynamic sendTelemetry { get; }

        public Message(int id, string format, dynamic variables = null, bool user = true, bool telemetry = false)
        {
            this.id = id;
            this.format = format;
            this.variables = variables;
            this.showUser = user;
            this.sendTelemetry = telemetry;
        }
    }

    public class StackFrame
    {
        public int id { get; }
        public Source source { get; }
        public int line { get; }
        public int column { get; }
        public string name { get; }

        public StackFrame(int id, string name, Source source, int line, int column)
        {
            this.id = id;
            this.name = name;
            this.source = source;
            this.line = line;
            this.column = column;
        }
    }

    public class Scope
    {
        public string name { get; }
        public int variablesReference { get; }
        public bool expensive { get; }

        public Scope(string name, int variablesReference, bool expensive = false)
        {
            this.name = name;
            this.variablesReference = variablesReference;
            this.expensive = expensive;
        }
    }

    public class Variable
    {
        public string name { get; }
        public string value { get; }
        public int variablesReference { get; }

        public Variable(string name, string value, int variablesReference = 0)
        {
            this.name = name;
            this.value = value;
            this.variablesReference = variablesReference;
        }
    }

    public class Thread
    {
        public string id { get; }
        public string name { get; }

        public Thread(string id, string name)
        {
            this.id = id;
            if (name == null || name.Length == 0)
            {
                this.name = string.Format("Thread #{0}", id);
            }
            else
            {
                this.name = name;
            }
        }
    }

    public class Source
    {
        public string name { get; }
        public string path { get; }
        public int sourceReference { get; }

        public Source(string name, string path, int sourceReference = 0)
        {
            this.name = name;
            this.path = path;
            this.sourceReference = sourceReference;
        }

        public Source(string path, int sourceReference = 0)
        {
            this.name = Path.GetFileName(path);
            this.path = path;
            this.sourceReference = sourceReference;
        }
    }

    public class Breakpoint
    {
        public bool verified { get; }
        public int line { get; }

        public Breakpoint(bool verified, int line)
        {
            this.verified = verified;
            this.line = line;
        }
    }

}
