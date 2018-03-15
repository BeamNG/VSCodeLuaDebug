namespace VSCodeDebug
{
    // interface to receive messages and events from the debuggee
    public interface IDebuggeeListener {
        void VSDebuggeeConnected(IDebuggee debugee);
        void VSDebuggeeDisconnected(IDebuggee debugee);
        void VSDebuggeeMessage(IDebuggee debugee, byte[] json);
    }
}
