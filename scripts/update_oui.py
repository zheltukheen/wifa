#!/usr/bin/env python3
import sys, os, re
from urllib.request import urlopen

DEFAULT_URLS = [
    os.environ.get("OUI_URL") or "https://standards-oui.ieee.org/oui/oui.txt",
    "https://standards-oui.ieee.org/oui.txt",  # legacy path
]

HEX_RE = re.compile(r"^\s*([0-9A-Fa-f]{2})[-: ]?([0-9A-Fa-f]{2})[-: ]?([0-9A-Fa-f]{2})\s*\((?:hex|base 16)\)\s*(.+?)\s*$")
HEX6_RE = re.compile(r"^\s*([0-9A-Fa-f]{6})\s*\((?:hex|base 16)\)\s*(.+?)\s*$")


def load_source(arg: str) -> str:
    if re.match(r"^https?://", arg):
        with urlopen(arg) as resp:
            return resp.read().decode("utf-8", errors="ignore")
    with open(arg, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def normalize_oui(s: str) -> str:
    s = s.strip().upper().replace(":", "").replace("-", "")
    return s[:6]


def parse_oui(text: str) -> dict:
    out = {}
    prefer = lambda v: (v and v.upper() != "IEEE REGISTRATION AUTHORITY")
    for line in text.splitlines():
        if not line or line.startswith("#"):  # comments
            continue
        m = HEX_RE.match(line) or HEX6_RE.match(line)
        if not m:
            continue
        if len(m.groups()) == 4:
            key = normalize_oui("".join(m.groups()[:3]))
            vendor = m.group(4).strip()
        else:
            key = normalize_oui(m.group(1))
            vendor = m.group(2).strip()
        if len(key) != 6 or not vendor:
            continue
        vendor = re.sub(r"\s+", " ", vendor).strip().upper()
        if key not in out or (prefer(vendor) and not prefer(out[key])):
            out[key] = vendor
    return out


def main():
    # Locate repo root and output path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, ".."))
    resources_dir = os.path.join(repo_root, "Resources")
    os.makedirs(resources_dir, exist_ok=True)
    output_path = os.path.join(resources_dir, "oui")

    # Determine input (URL or local file)
    source_text = None
    if len(sys.argv) > 1:
        source_text = load_source(sys.argv[1])
    else:
        for url in DEFAULT_URLS:
            try:
                source_text = load_source(url)
                break
            except Exception:
                continue
        if source_text is None:
            print("Failed to download OUI list. Provide a local path:", file=sys.stderr)
            print("  python3 scripts/update_oui.py path/to/oui.txt", file=sys.stderr)
            sys.exit(1)

    table = parse_oui(source_text)
    if not table:
        print("Parsed table is empty.", file=sys.stderr)
        sys.exit(2)

    with open(output_path, "w", encoding="utf-8") as f:
        for k in sorted(table.keys()):
            f.write(f"{k}\t{table[k]}\n")

    print(f"Wrote {len(table)} entries to {output_path}")


if __name__ == "__main__":
    main()
