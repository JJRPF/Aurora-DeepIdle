// Pre-script for a flat kernelcache import. Args: <syms file> <kext list file>
// Splits memory by top-level segment with permissions, labels every symbol (demangled
// later by the analyzer), and creates functions for symbols inside the listed kexts' text.
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.address.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;
import java.nio.file.*;
import java.util.*;

public class SetupKC extends GhidraScript {
    long[][] segs = {
        {0xfffffe0007004000L, 0xfffffe000700c000L, 1}, // __TEXT r
        {0xfffffe000700c000L, 0xfffffe0007990000L, 1}, // __PRELINK_TEXT r
        {0xfffffe0007990000L, 0xfffffe0008408000L, 1}, // __DATA_CONST r
        {0xfffffe0008408000L, 0xfffffe000b3d0000L, 2}, // __TEXT_EXEC rx
        {0xfffffe000b3d0000L, 0xfffffe000b6f4000L, 1}, // __PRELINK_INFO
        {0xfffffe000b6f4000L, 0xfffffe000b9c0000L, 3}, // __DATA rw
    };
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        Memory mem = currentProgram.getMemory();
        AddressSpace sp = currentProgram.getAddressFactory().getDefaultAddressSpace();
        for (long[] s : segs) {
            MemoryBlock b = mem.getBlock(sp.getAddress(s[0]));
            if (b != null && !b.getStart().equals(sp.getAddress(s[0]))) { mem.split(b, sp.getAddress(s[0])); }
        }
        for (long[] s : segs) {
            MemoryBlock b = mem.getBlock(sp.getAddress(s[0]));
            b.setRead(true); b.setWrite(s[2] == 3); b.setExecute(s[2] == 2);
        }
        Set<String> kexts = new HashSet<>(Files.readAllLines(Paths.get(a[1])));
        SymbolTable st = currentProgram.getSymbolTable();
        int n = 0, f = 0;
        for (String l : Files.readAllLines(Paths.get(a[0]))) {
            String[] p = l.split(" ", 3);
            if (p.length < 3) continue;
            long v = Long.parseUnsignedLong(p[0].substring(2), 16);
            Address ad = sp.getAddress(v);
            if (!mem.contains(ad)) continue;
            String nm = p[2];
            if (nm.endsWith("_vfpthunk_") || nm.contains(".cold.")) nm = nm.replace(".", "_");
            try { st.createLabel(ad, nm, SourceType.IMPORTED); n++; } catch (Exception e) {}
            boolean kern = p[1].equals("com.apple.kernel") && System.getenv("KC_KERNEL_FNS") != null;
            if ((kexts.contains(p[1]) || kern) && v >= 0xfffffe0008408000L && v < 0xfffffe000b3d0000L) {
                new DisassembleCommand(ad, null, true).applyTo(currentProgram, monitor);
                if (getFunctionAt(ad) == null) { new CreateFunctionCmd(ad).applyTo(currentProgram, monitor); f++; }
            }
        }
        String[] noret = {"_panic", "_panic_with_options", "___stack_chk_fail", "_Assert", "_panic_with_thread_context", "_kernel_debug_string_early"};
        for (String nr : noret) {
            for (Symbol sy : st.getSymbols(nr)) {
                ghidra.program.model.listing.Function fn = getFunctionAt(sy.getAddress());
                if (fn == null) { new CreateFunctionCmd(sy.getAddress()).applyTo(currentProgram, monitor); fn = getFunctionAt(sy.getAddress()); }
                if (fn != null && !nr.equals("_kernel_debug_string_early")) fn.setNoReturn(true);
            }
        }
        println("labels " + n + " functions " + f);
    }
}
