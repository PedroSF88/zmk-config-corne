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

KEY_ALIASES = {
    "LEFT_SHIFT": "LSFT",
    "RIGHT_SHIFT": "RSFT",
    "LEFT_ALT": "LALT",
    "RIGHT_ALT": "RALT",
    "LEFT_GUI": "LGUI",
    "RIGHT_GUI": "RGUI",
    "LEFT_CONTROL": "LCTL",
    "RIGHT_CONTROL": "RCTL",
    "RCTRL": "RCTL",
    "SPACE": "SPC",
    "ENTER": "ENT",
    "TAB": "TAB",
    "ESCAPE": "ESC",
    "DELETE": "DEL",
    "BACKSPACE": "BSPC",
    "QUESTION": "?",
    "SEMI": ";",
    "COMMA": ",",
    "DOT": ".",
    "SLASH": "/",
    "MINUS": "-",
    "PLUS": "+",
    "EQUAL": "=",
    "ASTERISK": "*",
    "ASTRK": "*",
    "PIPE": "|",
    "APOSTROPHE": "'",
    "AT": "@",
    "HASH": "#",
    "DOLLAR": "$",
    "PERCENT": "%",
    "AMPERSAND": "&",
    "LEFT_BRACKET": "[",
    "RIGHT_BRACKET": "]",
    "LEFT_PARENTHESIS": "(",
    "RIGHT_PARENTHESIS": ")",
    "UP_ARROW": "UP",
    "DOWN_ARROW": "DOWN",
    "LEFT": "LEFT",
    "RIGHT": "RIGHT",
    "HOME": "HOME",
    "END": "END",
    "PG_UP": "PGUP",
    "PAGE_DOWN": "PGDN",
    "C_VOLUME_DOWN": "VOL-",
    "C_VOL_DN": "VOL-",
}


def read_keymap_text(keymap_path: pathlib.Path) -> str:
    text = keymap_path.read_text(encoding="utf-8")
    match = re.search(r"keymap\s*\{(.*)\n\s*\};\s*\n\};\s*$", text, re.DOTALL)
    if not match:
        raise RuntimeError("Could not find keymap block in keymap file.")
    return match.group(1)


def normalize_key(token: str) -> str:
    token = token.strip()
    if token in KEY_ALIASES:
        return KEY_ALIASES[token]
    if re.fullmatch(r"F\d{1,2}", token):
        return token
    if re.fullmatch(r"N\d", token):
        return token[1:]
    return token.replace("_", " ")


def normalize_binding(binding: str) -> str:
    binding = " ".join(binding.strip().split())
    if not binding.startswith("&"):
        return binding

    parts = binding[1:].split()
    if not parts:
        return ""

    behavior = parts[0]
    args = parts[1:]

    if behavior == "none":
        return ""
    if behavior == "trans":
        return "TRNS"
    if behavior == "kp" and args:
        return normalize_key(args[0])
    if behavior == "mt" and args:
        return normalize_key(args[-1])
    if behavior == "to" and args:
        return f"L{args[0]}"
    if behavior == "bt" and args:
        if args[0] == "BT_SEL" and len(args) > 1:
            return f"BT{args[1]}"
        if args[0] == "BT_CLR_ALL":
            return "CLR ALL"
        if args[0] == "BT_CLR":
            return "CLR"
        return "BT"
    if behavior == "bootloader":
        return "BOOT"
    if behavior == "studio_unlock":
        return "STUDIO"
    if behavior == "comma_period":
        return ", / ."
    if behavior == "sk" and args:
        return normalize_key(args[0])

    compact = " ".join(parts)
    compact = compact.replace("_", " ")
    return compact[:10].upper()


def parse_layers(keymap_text: str) -> list[dict]:
    layers = []
    for index, match in enumerate(LAYER_BLOCK_RE.finditer(keymap_text)):
        node_name = match.group(1)
        body = match.group(2)

        display_name_match = DISPLAY_NAME_RE.search(body)
        display_name = display_name_match.group(1) if display_name_match else node_name

        bindings_match = BINDINGS_RE.search(body)
        if not bindings_match:
            continue

        binding_block = bindings_match.group(1)
        tokens = [normalize_binding(token) for token in TOKEN_RE.findall(binding_block)]
        if len(tokens) != 42:
            raise RuntimeError(
                f"Expected 42 bindings for layer {node_name}, found {len(tokens)}."
            )

        layers.append(
            {
                "index": index,
                "node": node_name,
                "name": display_name,
                "rows": [
                    tokens[0:12],
                    tokens[12:24],
                    tokens[24:36],
                    tokens[36:42],
                ],
            }
        )

    if not layers:
        raise RuntimeError("No layers were parsed from the keymap.")

    return layers


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    keymap_path = repo_root / "config" / "corne.keymap"
    output_path = repo_root / "overlay" / "corne-layout.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    layout = {
        "generated_from": str(keymap_path.relative_to(repo_root)).replace("\\", "/"),
        "layers": parse_layers(read_keymap_text(keymap_path)),
    }

    output_path.write_text(json.dumps(layout, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
