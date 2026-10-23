# Harmless: prints the uid it runs as. Used by install.sh to test the sudo rule.
import os
print(f"selftest uid={os.getuid()}")
