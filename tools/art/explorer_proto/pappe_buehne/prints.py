# Erzeugt die prozeduralen PBR-Texturen (tools/pappe_pbr.py) nach ./prints – nicht eingecheckt.
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "prints")
if not os.path.exists(os.path.join(OUT, "prints.png")) or os.environ.get("FORCE"):
    subprocess.check_call([sys.executable, os.path.join(HERE, "..", "tools", "pappe_pbr.py"), OUT])
