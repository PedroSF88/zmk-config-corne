"""Generate overlay/corne-layout.json from config/corne.keymap.

The overlay uses this file for everything it draws:
- per layer, per key position: a short label and the Windows virtual-key
  codes the key sends (so a keystroke seen on the PC can light up its key)
- combos: which positions they use and what they send
- signals: which F13-F16 key means "now on layer N" (see the to_layerN
  macros in the keymap)

Run after every keymap edit:  python tools/generate_overlay_layout.py
"""

import json
import pathlib
import re
import sys


LAYER_BLOCK_RE = re.compile(
    r"^\s*([A-Za-z0-9_]+)\s*\{\s*(.*?)^\s*\};",
    re.MULTILINE | re.DOTALL,
)
DISPLAY_NAME_RE = re.compile(r'display-name\s*=\s*"([^"]+)"')
BINDINGS_RE = re.compile(r"bindings\s*=\s*<(.*?)>;", re.DOTALL)
TOKEN_RE = re.compile(r"&[^\n&<>]+")
POSITIONS_RE = re.compile(r"key-positions\s*=\s*<([^>]*)>;")
COMBO_LAYERS_RE = re.compile(r"layers\s*=\s*<([^>]*)>;")
SIGNAL_MACRO_RE = re.compile(
    r"(to_layer\d+)\s*:[^{]*\{[^}]*bindings\s*=\s*<[^>]*&to\s+(\d+)\s+&kp\s+(F\d+)\s*>;",
    re.DOTALL,
)

KEY_COUNT = 42
SHIFT_VKS = (0xA0, 0xA1)

# ZMK key name -> (label, Windows VK code, needs shift)
KEYS = {
    "LEFT_SHIFT": ("SHFT", 0xA0, False),
    "LSHIFT": ("SHFT", 0xA0, False),
    "RIGHT_SHIFT": ("SHFT", 0xA1, False),
    "RSHIFT": ("SHFT", 0xA1, False),
    "LEFT_ALT": ("ALT", 0xA4, False),
    "LALT": ("ALT", 0xA4, False),
    "RIGHT_ALT": ("ALTGR", 0xA5, False),
    "RALT": ("ALTGR", 0xA5, False),
    "LEFT_CONTROL": ("CTRL", 0xA2, False),
    "LCTRL": ("CTRL", 0xA2, False),
    "RIGHT_CONTROL": ("CTRL", 0xA3, False),
    "RCTRL": ("CTRL", 0xA3, False),
    "LEFT_GUI": ("WIN", 0x5B, False),
    "LGUI": ("WIN", 0x5B, False),
    "RIGHT_GUI": ("WIN", 0x5C, False),
    "RGUI": ("WIN", 0x5C, False),
    "SPACE": ("SPC", 0x20, False),
    "ENTER": ("ENT", 0x0D, False),
    "TAB": ("TAB", 0x09, False),
    "ESCAPE": ("ESC", 0x1B, False),
    "ESC": ("ESC", 0x1B, False),
    "DELETE": ("DEL", 0x2E, False),
    "BACKSPACE": ("BSPC", 0x08, False),
    "HOME": ("HOME", 0x24, False),
    "END": ("END", 0x23, False),
    "PG_UP": ("PGUP", 0x21, False),
    "PAGE_UP": ("PGUP", 0x21, False),
    "PG_DN": ("PGDN", 0x22, False),
    "PAGE_DOWN": ("PGDN", 0x22, False),
    "LEFT": ("LEFT", 0x25, False),
    "LEFT_ARROW": ("LEFT", 0x25, False),
    "UP": ("UP", 0x26, False),
    "UP_ARROW": ("UP", 0x26, False),
    "RIGHT": ("RIGHT", 0x27, False),
    "RIGHT_ARROW": ("RIGHT", 0x27, False),
    "DOWN": ("DOWN", 0x28, False),
    "DOWN_ARROW": ("DOWN", 0x28, False),
    "C_VOLUME_DOWN": ("VOL-", 0xAE, False),
    "C_VOL_DN": ("VOL-", 0xAE, False),
    "C_VOLUME_UP": ("VOL+", 0xAF, False),
    "C_VOL_UP": ("VOL+", 0xAF, False),
    "SEMI": (";", 0xBA, False),
    "SEMICOLON": (";", 0xBA, False),
    "COMMA": (",", 0xBC, False),
    "DOT": (".", 0xBE, False),
    "PERIOD": (".", 0xBE, False),
    "SLASH": ("/", 0xBF, False),
    "QUESTION": ("?", 0xBF, True),
    "MINUS": ("-", 0xBD, False),
    "EQUAL": ("=", 0xBB, False),
    "PLUS": ("+", 0xBB, True),
    "APOSTROPHE": ("'", 0xDE, False),
    "SQT": ("'", 0xDE, False),
    "LEFT_BRACKET": ("[", 0xDB, False),
    "LBKT": ("[", 0xDB, False),
    "RIGHT_BRACKET": ("]", 0xDD, False),
    "RBKT": ("]", 0xDD, False),
    "PIPE": ("|", 0xDC, True),
    "BACKSLASH": ("\\", 0xDC, False),
    "AT": ("@", 0x32, True),
    "HASH": ("#", 0x33, True),
    "DOLLAR": ("$", 0x34, True),
    "PERCENT": ("%", 0x35, True),
    "AMPERSAND": ("&", 0x37, True),
    "ASTERISK": ("*", 0x38, True),
    "ASTRK": ("*", 0x38, True),
    "STAR": ("*", 0x38, True),
    "LEFT_PARENTHESIS": ("(", 0x39, True),
    "LPAR": ("(", 0x39, True),
    "RIGHT_PARENTHESIS": (")", 0x30, True),
    "RPAR": (")", 0x30, True),
}
for _i in range(26):
    _c = chr(ord("A") + _i)
    KEYS[_c] = (_c, ord(_c), False)
for _i in range(10):
    KEYS[f"N{_i}"] = (str(_i), 0x30 + _i, False)
    KEYS[f"NUMBER_{_i}"] = (str(_i), 0x30 + _i, False)
for _i in range(1, 25):
    KEYS[f"F{_i}"] = (f"F{_i}", 0x6F + _i, False)


def key_info(name):
    """Return (label, [vk entries]) for a ZMK key, handling LA()/LC() wrappers."""
    name = name.strip()
    mods = []
    while True:
        m = re.fullmatch(r"(L|R)(A|C|S|G)\((.*)\)", name)
        if not m:
            break
        mods.append({"A": "ALT+", "C": "CTRL+", "S": "SHFT+", "G": "WIN+"}[m.group(2)])
        name = m.group(3)
    if name in KEYS:
        label, vk, shift = KEYS[name]
        prefix = "".join(dict.fromkeys(mods))
        if prefix == "CTRL+ALT+" or prefix == "ALT+CTRL+":
            prefix = "C+A+"
        return prefix + label, [{"vk": vk, "shift": shift}]
    return name.replace("_", " ")[:6], []


def read_text(path):
    return path.read_text(encoding="utf-8")


def keymap_block(text):
    match = re.search(r"\bkeymap\s*\{(.*)\n\s*\};\s*\n\};\s*$", text, re.DOTALL)
    if not match:
        raise RuntimeError("Could not find keymap block in keymap file.")
    return match.group(1)


def block_body(text, name):
    match = re.search(r"\b" + name + r"\s*\{", text)
    if not match:
        return ""
    depth = 0
    for i in range(match.end() - 1, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[match.end():i]
    raise RuntimeError(f"Unbalanced braces in {name} block.")


def binding_entry(binding, signals, layer_names):
    """Turn one binding token into {label, vks, kind}."""
    parts = " ".join(binding.strip().split())[1:].split()
    behavior, args = parts[0], parts[1:]

    if behavior == "none":
        return {"label": "", "vks": [], "kind": "none"}
    if behavior == "trans":
        return {"label": "", "vks": [], "kind": "trans"}
    if behavior in ("kp", "sk") and args:
        label, vks = key_info(args[0])
        return {"label": label, "vks": vks, "kind": "key"}
    if behavior == "mt" and len(args) >= 2:
        hold_label, hold_vks = key_info(args[0])
        tap_label, tap_vks = key_info(args[1])
        return {"label": tap_label, "sub": hold_label, "vks": tap_vks + hold_vks, "kind": "key"}
    if behavior in ("to", "mo", "tog") and args:
        target = int(args[0])
        return {"label": layer_names.get(target, f"L{target}"), "sub": "layer", "vks": [], "kind": "layer"}
    if behavior in signals:
        target = signals[behavior]["layer"]
        return {"label": layer_names.get(target, f"L{target}"), "sub": "layer", "vks": [], "kind": "layer"}
    if behavior == "bt" and args:
        if args[0] == "BT_SEL" and len(args) > 1:
            return {"label": f"BT{args[1]}", "vks": [], "kind": "system"}
        if args[0] == "BT_CLR_ALL":
            return {"label": "CLR ALL", "vks": [], "kind": "system"}
        if args[0] == "BT_CLR":
            return {"label": "BT CLR", "vks": [], "kind": "system"}
        return {"label": "BT", "vks": [], "kind": "system"}
    if behavior == "bootloader":
        return {"label": "BOOT", "vks": [], "kind": "system"}
    if behavior == "studio_unlock":
        return {"label": "UNLOCK", "vks": [], "kind": "system"}
    if behavior == "comma_period":
        return {
            "label": ", .",
            "vks": [{"vk": 0xBC, "shift": False}, {"vk": 0xBE, "shift": False}],
            "kind": "key",
        }
    return {"label": behavior.replace("_", " ")[:6].upper(), "vks": [], "kind": "other"}


def parse(text):
    signals = {}
    for name, layer, fkey in SIGNAL_MACRO_RE.findall(block_body(text, "macros")):
        signals[name] = {"layer": int(layer), "vk": KEYS[fkey][1], "key": fkey}

    km = keymap_block(text)
    raw_layers = []
    for match in LAYER_BLOCK_RE.finditer(km):
        body = match.group(2)
        bindings_match = BINDINGS_RE.search(body)
        if not bindings_match:
            continue
        name_match = DISPLAY_NAME_RE.search(body)
        tokens = TOKEN_RE.findall(bindings_match.group(1))
        if len(tokens) != KEY_COUNT:
            raise RuntimeError(
                f"Expected {KEY_COUNT} bindings for layer {match.group(1)}, found {len(tokens)}."
            )
        raw_layers.append((match.group(1), name_match.group(1) if name_match else match.group(1), tokens))
    if not raw_layers:
        raise RuntimeError("No layers were parsed from the keymap.")

    layer_names = {i: name for i, (_, name, _) in enumerate(raw_layers)}
    layers = []
    for index, (node, name, tokens) in enumerate(raw_layers):
        keys = [binding_entry(t, signals, layer_names) for t in tokens]
        layers.append({"index": index, "node": node, "name": name, "keys": keys})

    # A transparent key falls through to the base layer: show and match that.
    for layer in layers[1:]:
        for pos, key in enumerate(layer["keys"]):
            if key["kind"] == "trans":
                base = layers[0]["keys"][pos]
                key.update({k: v for k, v in base.items() if k != "kind"})
                key["kind"] = "trans"

    combos = []
    for match in LAYER_BLOCK_RE.finditer(block_body(text, "combos")):
        body = match.group(2)
        bind = BINDINGS_RE.search(body)
        pos = POSITIONS_RE.search(body)
        if not bind or not pos:
            continue
        entry = binding_entry(TOKEN_RE.findall(bind.group(1))[0], signals, layer_names)
        lay = COMBO_LAYERS_RE.search(body)
        combos.append({
            "name": match.group(1),
            "positions": [int(p) for p in pos.group(1).split()],
            "layers": [int(x) for x in lay.group(1).split()] if lay else None,
            "label": entry["label"],
            "vks": entry["vks"],
        })

    return {
        "generated_from": "config/corne.keymap",
        "key_count": KEY_COUNT,
        "signals": sorted(signals.values(), key=lambda s: s["layer"]),
        "layers": layers,
        "combos": combos,
    }


def main():
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    keymap_path = repo_root / "config" / "corne.keymap"
    output_path = repo_root / "overlay" / "corne-layout.json"
    layout = parse(read_text(keymap_path))
    output_path.write_text(json.dumps(layout, indent=1) + "\n", encoding="utf-8")
    print(f"Wrote {output_path}: {len(layout['layers'])} layers, "
          f"{len(layout['combos'])} combos, {len(layout['signals'])} layer signals")
    return 0


if __name__ == "__main__":
    sys.exit(main())
