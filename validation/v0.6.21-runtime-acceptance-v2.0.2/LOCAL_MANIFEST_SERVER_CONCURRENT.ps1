[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$Port,[Parameter(Mandatory=$true)][string]$ManifestPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){throw 'Manifest file missing.'}

# Each accepted client is handled on its own short-lived background thread. This is
# intentional: endpoint scanners/AV can create several half-open loopback connections
# at once, and a serial TcpListener would make the real Bootstrap request wait behind
# every per-client read timeout.
$serverSource=@'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public sealed class SpotifyControlLoopbackManifestServer
{
    private const int ClientReadTimeoutMs = 1500;
    private const int ClientWriteTimeoutMs = 1500;
    private const int MaxHeaderLines = 100;
    private const int MaxLineChars = 8192;
    private readonly int port;
    private readonly string manifestPath;

    public SpotifyControlLoopbackManifestServer(int port, string manifestPath)
    {
        this.port = port;
        this.manifestPath = manifestPath;
    }

    public void Run()
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start(128);
        try
        {
            while (true)
            {
                TcpClient client = listener.AcceptTcpClient();
                Thread thread = new Thread(delegate() { HandleClient(client); });
                thread.IsBackground = true;
                thread.Name = "SpotifyControlManifestClient";
                thread.Start();
            }
        }
        finally
        {
            listener.Stop();
        }
    }

    private void HandleClient(TcpClient client)
    {
        using (client)
        {
            try
            {
                client.ReceiveTimeout = ClientReadTimeoutMs;
                client.SendTimeout = ClientWriteTimeoutMs;
                NetworkStream stream = client.GetStream();
                stream.ReadTimeout = ClientReadTimeoutMs;
                stream.WriteTimeout = ClientWriteTimeoutMs;
                using (StreamReader reader = new StreamReader(stream, Encoding.ASCII, false, 4096, true))
                {
                    string first = reader.ReadLine();
                    if (String.IsNullOrEmpty(first) || first.Length > MaxLineChars) return;
                    bool complete = false;
                    for (int i = 0; i < MaxHeaderLines; i++)
                    {
                        string line = reader.ReadLine();
                        if (line == null || line.Length > MaxLineChars) break;
                        if (line.Length == 0) { complete = true; break; }
                    }
                    if (!complete) return;

                    string path = String.Empty;
                    string[] parts = first.Split(' ');
                    if (parts.Length >= 2) path = parts[1];
                    byte[] body;
                    string status;
                    string type;
                    if (String.Equals(path, "/manifest.json", StringComparison.Ordinal))
                    {
                        body = File.ReadAllBytes(manifestPath);
                        status = "200 OK";
                        type = "application/json; charset=utf-8";
                    }
                    else
                    {
                        body = Encoding.UTF8.GetBytes("not found");
                        status = "404 Not Found";
                        type = "text/plain; charset=utf-8";
                    }
                    string header = "HTTP/1.1 " + status + "\r\nContent-Type: " + type +
                        "\r\nContent-Length: " + body.Length.ToString() +
                        "\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n";
                    byte[] hb = Encoding.ASCII.GetBytes(header);
                    stream.Write(hb, 0, hb.Length);
                    stream.Write(body, 0, body.Length);
                    stream.Flush();
                }
            }
            catch (IOException) { }
            catch (SocketException) { }
            catch (ObjectDisposedException) { }
        }
    }
}
'@
Add-Type -TypeDefinition $serverSource -Language CSharp -ErrorAction Stop
$server=New-Object SpotifyControlLoopbackManifestServer($Port,(Resolve-Path -LiteralPath $ManifestPath).Path)
$server.Run()
# exact-head validation trigger; no runtime behavior change
