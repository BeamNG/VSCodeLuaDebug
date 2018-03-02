using System.Collections.Generic;
using System.Linq;

namespace VSCodeDebug
{
    /*
	 * subclasses of ResponseBody are serialized as the body of a response.
	 * Don't change their instance variables since that will break the debug protocol.
	 */
    public class ResponseBody
    {
        // empty
    }

    public class Response : MessageToVSCode
    {
        public bool success { get; private set; }
        public string message { get; private set; }
        public int request_seq { get; }
        public string command { get; }
        public ResponseBody body { get; private set; }

        public Response(string command, int seq) : base("response")
        {
            this.success = true;
            this.request_seq = seq;
            this.command = command;
        }

        public void SetBody(ResponseBody bdy)
        {
            success = true;
            body = bdy;
        }

        public void SetErrorBody(string msg, ResponseBody bdy = null)
        {
            success = false;
            message = msg;
            body = bdy;
        }
    }

    public class ThreadResponse : MessageToVSCode
    {
        public ThreadResponse(string command, int seq) : base("response") { }
        public ThreadsResponseBody body { get; set; }
    }

    // ---- Response -------------------------------------------------------------------------

    public class Capabilities : ResponseBody
    {

        public bool supportsConfigurationDoneRequest;
        public bool supportsFunctionBreakpoints;
        public bool supportsConditionalBreakpoints;
        public bool supportsEvaluateForHovers;
        public dynamic[] exceptionBreakpointFilters;
    }

    public class ErrorResponseBody : ResponseBody
    {

        public Message error { get; }

        public ErrorResponseBody(Message error)
        {
            this.error = error;
        }
    }

    public class StackTraceResponseBody : ResponseBody
    {
        public StackFrame[] stackFrames { get; }

        public StackTraceResponseBody(List<StackFrame> frames = null)
        {
            if (frames == null)
                stackFrames = new StackFrame[0];
            else
                stackFrames = frames.ToArray<StackFrame>();
        }
    }

    public class ScopesResponseBody : ResponseBody
    {
        public Scope[] scopes { get; }

        public ScopesResponseBody(List<Scope> scps = null)
        {
            if (scps == null)
                scopes = new Scope[0];
            else
                scopes = scps.ToArray<Scope>();
        }
    }

    public class VariablesResponseBody : ResponseBody
    {
        public Variable[] variables { get; }

        public VariablesResponseBody(List<Variable> vars = null)
        {
            if (vars == null)
                variables = new Variable[0];
            else
                variables = vars.ToArray<Variable>();
        }
    }

    public class ThreadsResponseBody : ResponseBody
    {
        public List<Thread> threads { get; }

        public ThreadsResponseBody(List<Thread> threads = null) {
            this.threads = threads;
        }
    }

    public class EvaluateResponseBody : ResponseBody
    {
        public string result { get; }
        public int variablesReference { get; }

        public EvaluateResponseBody(string value, int reff = 0)
        {
            result = value;
            variablesReference = reff;
        }
    }

    public class SetBreakpointsResponseBody : ResponseBody
    {
        public Breakpoint[] breakpoints { get; }

        public SetBreakpointsResponseBody(List<Breakpoint> bpts = null)
        {
            if (bpts == null)
                breakpoints = new Breakpoint[0];
            else
                breakpoints = bpts.ToArray<Breakpoint>();
        }
    }
}
