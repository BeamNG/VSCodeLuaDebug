namespace VSCodeDebug
{
    public interface ICDPListener {
        void X_FromVSCode(string command, int seq, dynamic args, string reqText);
    }
}
