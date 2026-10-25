// fdttool: tiny flattened-device-tree tool.
//   fdttool dump <dtb>                              - print the tree
//   fdttool keep <in.dtb> <out.dtb> <path> [...]    - keep only the given node paths (and their ancestors
//                                                     and subtrees); every other node is dropped
//   fdttool set <in.dtb> <out.dtb> <path> <prop> <str|u32:..|del>  - set/delete a property
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

class Node
{
    public string Name = "";
    public List<(string Name, byte[] Value)> Props = new();
    public List<Node> Children = new();
}

static class Fdt
{
    static uint BE(byte[] b, int o) => (uint)(b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3]);

    public static Node Parse(byte[] b)
    {
        int offStruct = (int)BE(b, 8), offStrings = (int)BE(b, 12);
        int p = offStruct;
        var stack = new Stack<Node>();
        Node root = null;
        while (true)
        {
            uint tok = BE(b, p); p += 4;
            if (tok == 1)
            {
                int e = p; while (b[e] != 0) e++;
                var n = new Node { Name = Encoding.ASCII.GetString(b, p, e - p) };
                p = (e + 1 + 3) & ~3;
                if (stack.Count > 0) stack.Peek().Children.Add(n); else root = n;
                stack.Push(n);
            }
            else if (tok == 2) stack.Pop();
            else if (tok == 3)
            {
                int len = (int)BE(b, p), nameOff = (int)BE(b, p + 4); p += 8;
                int e = offStrings + nameOff; while (b[e] != 0) e++;
                stack.Peek().Props.Add((Encoding.ASCII.GetString(b, offStrings + nameOff, e - offStrings - nameOff), b.Skip(p).Take(len).ToArray()));
                p = (p + len + 3) & ~3;
            }
            else if (tok == 4) continue;
            else if (tok == 9) break;
            else throw new Exception("bad token " + tok);
        }
        return root;
    }

    public static byte[] Build(Node root)
    {
        var st = new MemoryStream(); var strings = new MemoryStream(); var strOff = new Dictionary<string, int>();
        void W(uint v) { st.WriteByte((byte)(v >> 24)); st.WriteByte((byte)(v >> 16)); st.WriteByte((byte)(v >> 8)); st.WriteByte((byte)v); }
        void Pad() { while (st.Length % 4 != 0) st.WriteByte(0); }
        void Emit(Node n)
        {
            W(1); var nb = Encoding.ASCII.GetBytes(n.Name); st.Write(nb); st.WriteByte(0); Pad();
            foreach (var (name, val) in n.Props)
            {
                if (!strOff.TryGetValue(name, out int so)) { so = (int)strings.Length; strOff[name] = so; strings.Write(Encoding.ASCII.GetBytes(name)); strings.WriteByte(0); }
                W(3); W((uint)val.Length); W((uint)so); st.Write(val); Pad();
            }
            foreach (var c in n.Children) Emit(c);
            W(2);
        }
        Emit(root); W(9);
        byte[] s = st.ToArray(), str = strings.ToArray();
        int hdr = 40, rsv = 16, offRsv = hdr, offStruct = offRsv + rsv, offStr = offStruct + s.Length, total = offStr + str.Length;
        var o = new byte[total];
        void P(int at, uint v) { o[at] = (byte)(v >> 24); o[at + 1] = (byte)(v >> 16); o[at + 2] = (byte)(v >> 8); o[at + 3] = (byte)v; }
        P(0, 0xd00dfeed); P(4, (uint)total); P(8, (uint)offStruct); P(12, (uint)offStr); P(16, (uint)offRsv);
        P(20, 17); P(24, 16); P(28, 0); P(32, (uint)str.Length); P(36, (uint)s.Length);
        Array.Copy(s, 0, o, offStruct, s.Length); Array.Copy(str, 0, o, offStr, str.Length);
        return o;
    }

    public static string Fmt(byte[] v)
    {
        if (v.Length == 0) return "";
        bool printable = v[^1] == 0 && v.Take(v.Length - 1).All(c => c == 0 || (c >= 32 && c < 127)) && v[0] != 0;
        if (printable) return "\"" + Encoding.ASCII.GetString(v, 0, v.Length - 1).Replace("\0", "\", \"") + "\"";
        if (v.Length % 4 == 0) return "<" + string.Join(" ", Enumerable.Range(0, v.Length / 4).Select(i => "0x" + BE(v, i * 4).ToString("x"))) + ">";
        return "[" + BitConverter.ToString(v).Replace("-", " ") + "]";
    }

    public static void Dump(Node n, string indent = "")
    {
        Console.WriteLine(indent + (n.Name == "" ? "/" : n.Name) + " {");
        foreach (var (name, val) in n.Props) Console.WriteLine(indent + "  " + name + " = " + Fmt(val) + ";");
        foreach (var c in n.Children) Dump(c, indent + "  ");
        Console.WriteLine(indent + "};");
    }

    public static Node Find(Node root, string path)
    {
        Node cur = root;
        foreach (var part in path.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            cur = cur.Children.FirstOrDefault(c => c.Name == part || c.Name.Split('@')[0] == part && !part.Contains('@'));
            if (cur == null) throw new Exception("node not found: " + path);
        }
        return cur;
    }
}

static class Program
{
    static int Main(string[] a)
    {
        var root = Fdt.Parse(File.ReadAllBytes(a[1]));
        switch (a[0])
        {
            case "dump":
                Fdt.Dump(root);
                return 0;
            case "keep":
            {
                var keep = new HashSet<Node>();
                foreach (var path in a.Skip(3))
                {
                    var n = Fdt.Find(root, path);
                    void Sub(Node x) { keep.Add(x); x.Children.ForEach(Sub); }
                    Sub(n);
                    // ancestors
                    Node cur = root;
                    keep.Add(root);
                    foreach (var part in path.Split('/', StringSplitOptions.RemoveEmptyEntries))
                    {
                        cur = cur.Children.First(c => c.Name == part || c.Name.Split('@')[0] == part && !part.Contains('@'));
                        keep.Add(cur);
                    }
                }
                void Prune(Node x) { x.Children.RemoveAll(c => !keep.Contains(c)); x.Children.ForEach(Prune); }
                Prune(root);
                File.WriteAllBytes(a[2], Fdt.Build(root));
                return 0;
            }
            case "delprops": // delprops <in> <out> <path> <suffix> : remove every property whose name ends with suffix
            {
                Fdt.Find(root, a[3]).Props.RemoveAll(p => p.Name.EndsWith(a[4]));
                File.WriteAllBytes(a[2], Fdt.Build(root));
                return 0;
            }
            case "keepchildren": // keepchildren <in> <out> <path> <name,name,...> : drop all other child nodes
            {
                var keepNames = a[4].Split(',');
                Fdt.Find(root, a[3]).Children.RemoveAll(c => !keepNames.Contains(c.Name));
                File.WriteAllBytes(a[2], Fdt.Build(root));
                return 0;
            }
            case "delnode": // delnode <in> <out> <path>
            {
                var path = a[3];
                int cut = path.LastIndexOf('/');
                var parent = cut <= 0 ? root : Fdt.Find(root, path[..cut]);
                parent.Children.Remove(Fdt.Find(root, path));
                File.WriteAllBytes(a[2], Fdt.Build(root));
                return 0;
            }
            case "addnode": // addnode <in> <out> <parentPath> <name>
            {
                Fdt.Find(root, a[3]).Children.Add(new Node { Name = a[4] });
                File.WriteAllBytes(a[2], Fdt.Build(root));
                return 0;
            }
            case "set":
            {
                var n = Fdt.Find(root, a[3]);
                string prop = a[4], val = a[5];
                n.Props.RemoveAll(p => p.Name == prop);
                if (val != "del")
                {
                    byte[] bytes;
                    if (val.StartsWith("u32:"))
                        bytes = val[4..].Split(',').SelectMany(s => { uint v = Convert.ToUInt32(s, s.StartsWith("0x") ? 16 : 10); return new[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v }; }).ToArray();
                    else if (val == "empty") bytes = Array.Empty<byte>();
                    else if (val.StartsWith("strs:")) bytes = Encoding.ASCII.GetBytes(val[5..].Replace('|', '\0') + "\0");
                    else bytes = Encoding.ASCII.GetBytes(val + "\0");
                    n.Props.Add((prop, bytes));
                }
                File.WriteAllBytes(a[2], Fdt.Build(root));
                return 0;
            }
        }
        return 2;
    }
}
