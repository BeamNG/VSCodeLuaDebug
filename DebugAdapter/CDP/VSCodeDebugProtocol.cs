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
using System.Text;
using System.IO;
using System.Text.RegularExpressions;
using Newtonsoft.Json;

namespace VSCodeDebug
{
    public class VSCodeDebugProtocol : ICDPSender
	{
		protected const int BUFFER_SIZE = 4096;
		protected const string TWO_CRLF = "\r\n\r\n";
		protected static readonly Regex CONTENT_LENGTH_MATCHER = new Regex(@"Content-Length: (\d+)");

        protected static readonly Encoding Encoding = System.Text.Encoding.UTF8;

        private Stream _outputStream;

		private ByteBuffer _rawData;
		private int _bodyLength;

		private bool _stopRequested;

        private ICDPListener listener;

		public VSCodeDebugProtocol(ICDPListener listener) {
			_bodyLength = -1;
			_rawData = new ByteBuffer();
            this.listener = listener;
		}

		public void Loop(Stream inputStream, Stream outputStream) {
			_outputStream = outputStream;

			byte[] buffer = new byte[BUFFER_SIZE];

			_stopRequested = false;
			while (!_stopRequested) {
				var read = inputStream.Read(buffer, 0, buffer.Length);

				if (read == 0) {
					// end of stream
					break;
				}

				if (read > 0) {
					_rawData.Append(buffer, read);
					ProcessData();
				}
			}
		}

		public void Stop() {
			_stopRequested = true;
		}

		// ---- private ------------------------------------------------------------------------

		private void ProcessData() {
			while (true) {
				if (_bodyLength >= 0) {
					if (_rawData.Length >= _bodyLength) {
						var buf = _rawData.RemoveFirst(_bodyLength);

						_bodyLength = -1;

						Dispatch(Encoding.GetString(buf));

						continue;   // there may be more complete messages to process
					}
				} else {
					string s = _rawData.GetString(Encoding);
					var idx = s.IndexOf(TWO_CRLF);
					if (idx != -1) {
						Match m = CONTENT_LENGTH_MATCHER.Match(s);
						if (m.Success && m.Groups.Count == 2) {
							_bodyLength = Convert.ToInt32(m.Groups[1].ToString());

							_rawData.RemoveFirst(idx + TWO_CRLF.Length);

							continue;   // try to handle a complete message
						}
					}
				}
				break;
			}
		}

		private void Dispatch(string reqText) {
			var request = JsonConvert.DeserializeObject<Request>(reqText);
			if (request != null && request.type == "request") {
                listener.X_FromVSCode(request.command, request.seq, request.arguments, reqText);
            } else {
                MessageBox.WTF(reqText);
                Environment.Exit(1);
            }
		}

		public void SendMessage(MessageToVSCode message) {
			var data = ConvertToBytes(message);
			try {
				_outputStream.Write(data, 0, data.Length);
				_outputStream.Flush();
			} catch (Exception) {
				// ignore
			}
		}

        public void SendJSONEncodedMessage(byte[] json) {
            var data = PrependSizeHeader(json);
            try {
                _outputStream.Write(data, 0, data.Length);
                _outputStream.Flush();
            } catch (Exception) {
                // ignore
            }
        }

        private static byte[] ConvertToBytes(MessageToVSCode message) {
			var asJson = JsonConvert.SerializeObject(message);
			byte[] jsonBytes = Encoding.GetBytes(asJson);

            return PrependSizeHeader(jsonBytes);
		}

        private static byte[] PrependSizeHeader(byte[] jsonBytes) {
            string header = string.Format("Content-Length: {0}{1}", jsonBytes.Length, TWO_CRLF);
            byte[] headerBytes = Encoding.GetBytes(header);

            byte[] data = new byte[headerBytes.Length + jsonBytes.Length];
            System.Buffer.BlockCopy(headerBytes, 0, data, 0, headerBytes.Length);
            System.Buffer.BlockCopy(jsonBytes, 0, data, headerBytes.Length, jsonBytes.Length);

            return data;
        }

        public void SendOutput(string category, string data) {
            if (!String.IsNullOrEmpty(data)) {
                SendMessage(new OutputEvent(category, data));
            }
        }
    }

    //--------------------------------------------------------------------------------------

    class ByteBuffer
	{
		private byte[] _buffer;

		public ByteBuffer() {
			_buffer = new byte[0];
		}

		public int Length {
			get { return _buffer.Length; }
		}

		public string GetString(Encoding enc) {
			return enc.GetString(_buffer);
		}

		public void Append(byte[] b, int length) {
			byte[] newBuffer = new byte[_buffer.Length + length];
			System.Buffer.BlockCopy(_buffer, 0, newBuffer, 0, _buffer.Length);
			System.Buffer.BlockCopy(b, 0, newBuffer, _buffer.Length, length);
			_buffer = newBuffer;
		}

		public byte[] RemoveFirst(int n) {
			byte[] b = new byte[n];
			System.Buffer.BlockCopy(_buffer, 0, b, 0, n);
			byte[] newBuffer = new byte[_buffer.Length - n];
			System.Buffer.BlockCopy(_buffer, n, newBuffer, 0, _buffer.Length - n);
			_buffer = newBuffer;
			return b;
		}
	}
}
