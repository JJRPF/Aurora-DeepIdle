// Decompile listed functions. Args: <addr-list-file> <out-file>
// Each line of the list: <hex addr> [name]. Creates the function if needed.
import ghidra.app.script.GhidraScript;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.SourceType;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class DecompFns extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        List<String> lines = Files.readAllLines(Paths.get(a[0]));
        AddressSpace sp = currentProgram.getAddressFactory().getDefaultAddressSpace();
        List<Address> fns = new ArrayList<>();
        for (String l : lines) {
            l = l.trim();
            if (l.isEmpty() || l.startsWith("#")) continue;
            String[] p = l.split("\\s+");
            Address ad = sp.getAddress(Long.parseUnsignedLong(p[0].replace("0x", ""), 16));
            new DisassembleCommand(ad, null, true).applyTo(currentProgram, monitor);
            Function f = getFunctionAt(ad);
            if (f == null) {
                new CreateFunctionCmd(ad).applyTo(currentProgram, monitor);
                f = getFunctionAt(ad);
            }
            if (f != null && p.length > 1) {
                try { f.setName(p[1].replace("::", "__").replaceAll("[^A-Za-z0-9_]", "_"), SourceType.USER_DEFINED); } catch (Exception e) {}
            }
            fns.add(ad);
        }
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        try (PrintWriter w = new PrintWriter(new FileWriter(a[1]))) {
            for (Address ad : fns) {
                Function f = getFunctionAt(ad);
                if (f == null) { w.println("// no function at " + ad); continue; }
                DecompileResults r = d.decompileFunction(f, 120, monitor);
                w.println("// ===== " + ad + " " + f.getName());
                w.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// failed: " + r.getErrorMessage());
            }
        }
    }
}
