namespace VSCodeDebug
{
    public interface IDebuggeeListener {
        void VSDebuggeeConnected(IDebuggee debugee);
        void VSDebuggeeDisconnected(IDebuggee debugee);
        void VSDebuggeeMessage(IDebuggee debugee, byte[] json);
    }
}
