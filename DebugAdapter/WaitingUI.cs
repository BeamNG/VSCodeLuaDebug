using System;
using System.Windows.Forms;

namespace VSCodeDebug
{
    class WaitingUI : Form
    {
        private Label label1;

        public WaitingUI()
        {
            InitializeComponent();
            CenterToScreen();

            Shown += WaitingUI_Shown;
            FormClosing += WaitingUI_FormClosing;
        }

        private void WaitingUI_FormClosing(object sender, FormClosingEventArgs e)
        {
            Program.Stop();
            Environment.Exit(0);
        }

        private void WaitingUI_Shown(object sender, EventArgs e)
        {
            new System.Threading.Thread(Program.DebugSessionLoop).Start();
        }

        public void SetLabelText(string s)
        {
            BeginInvoke(new Action(() =>
            {
                label1.Text = s;
            }));
        }

        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(WaitingUI));
            this.label1 = new System.Windows.Forms.Label();
            this.SuspendLayout();
            // 
            // label1
            // 
            this.label1.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label1.Location = new System.Drawing.Point(12, 9);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(527, 73);
            this.label1.TabIndex = 0;
            this.label1.Text = "label1";
            this.label1.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // WaitingUI
            // 
            this.ClientSize = new System.Drawing.Size(551, 91);
            this.Controls.Add(this.label1);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "WaitingUI";
            this.Text = "Lua/LuaJIT Debugger";
            this.ResumeLayout(false);

        }
    }
}
