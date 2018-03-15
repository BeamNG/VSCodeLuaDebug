namespace VSCodeDebug
{
    // interface to send messages to the debuggee
    public interface IDebuggee {
        void SendToDebuggee(string reqText);
    }
}
