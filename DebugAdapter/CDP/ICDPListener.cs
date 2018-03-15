namespace VSCodeDebug
{
    // this interface receives commands from VSCode
    public interface ICDPListener {
        void X_FromVSCode(string command, int seq, dynamic args, string reqText);
    }
}
