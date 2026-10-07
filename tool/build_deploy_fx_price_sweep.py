"""Builds DEPLOY_fx_price_sweep.ts: a single-file copy of
supabase/functions/fx-price-sweep/{fastforex.ts,index.ts} for pasting into the
Supabase dashboard editor.

Run from the project root:  python tool/build_deploy_fx_price_sweep.py
"""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "supabase" / "functions" / "fx-price-sweep"

helper = (src / "fastforex.ts").read_text(encoding="utf-8")
helper = re.sub(r"^export ", "", helper, flags=re.M)

index = (src / "index.ts").read_text(encoding="utf-8")
index = re.sub(r'^import \{[^}]*\} from "\./fastforex\.ts";\n', "", index, flags=re.M)

# index.ts imports first (Deno needs them at the top), then the helper, then the rest.
imports, _, body = index.partition("\n\n")
out = (
    "// GENERATED single-file copy of supabase/functions/fx-price-sweep/{fastforex.ts,index.ts}\n"
    "// for pasting into the Supabase dashboard editor. DO NOT EDIT: edit the two\n"
    "// source files and run tool/build_deploy_fx_price_sweep.py.\n\n"
)
header, sep, rest = index.partition('import { serve }')
out += header + sep + rest.split("\n", 2)[0] + "\n"  # the serve import line
remaining = rest.split("\n", 2)[1:]
out += "\n".join(remaining[:1]) + "\n\n"  # the supabase-js import line
out += helper + "\n" + "\n".join(remaining[1:])
(root / "DEPLOY_fx_price_sweep.ts").write_text(out, encoding="utf-8")
print("wrote DEPLOY_fx_price_sweep.ts")
