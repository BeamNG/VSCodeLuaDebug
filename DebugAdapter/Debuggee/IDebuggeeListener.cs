namespace VSCodeDebug
{
    public interface IDebuggeeListener
    {
        void X_DebuggeeArrived(IDebuggee debugee);
        void X_FromDebuggee(byte[] json);
        void X_DebuggeeHasGone();
    }
}
