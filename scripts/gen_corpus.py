#!/usr/bin/env python3
# Generate differential corpus for MiniUnikey parity tests using the reference
# UniKey engine binary (/tmp/ref_engine built from fcitx5-unikey sources).
import json, random, subprocess, sys

CURATED = [
    # tone digits at word end
    "tuan2","ngan6 2","hoai2","hoai31","tinh1","moi1","ngang1","ngap1","thue6 2","hue1",
    "khoan2","khoan3","tuan62","ngua5","ngua62","ngu7","ngươi-like-sequence-ngu7oi5",
    # invalid / literal digits
    "login","hom nay an gi","5 1 2","danh6","danh7","hy6","ngii9","a9","h9","nghy",
    # roof 6
    "ngo6ng","ngo6ng1","toa6n","tuu6ng","daa6","aa6","sa6u","ca1","ca11","caa1",
    # hook 7
    "ngu7","ngua7","ngua72","nguu7","nguon5","ngu7ong5","ngu7oc2","ngu7oi5","ngu7oi3","tuya7t",
    # bowl 8
    "kha8n2","caa8n","la8nh1","man8","na8ng",
    # dd 9
    "daa9","da9","nghesda13","di9","dinh1","d9au9",
    # tone removal 0 & retypes
    "hoa1 0","ngoi3 0","nguc","bo9 0",
    # repeated digit undo
    "noi31","ca11","daa9 9",
    # mixed
    "nguy tham","xin chao ban","ngay mai troi dep","viet o day","ky thuat thong tin",
    "chao mung den voi mini unikey","hop lap 2 tren mac","ban co chac khong",
    "truong phong ban tri an", # lowercase only
    # combos with ng/nh
    "nghie6u2","vie6t","nam2","nha2","nhinee2","nghe6inh",
    # tone conflict guard (c/p/t + huyền/hỏi/ngã)
    "ngac2","ngac3","ngat2","ngap3","ngap4","ngac1","ngat5","ngachop",
    # modern cases
    "hoa2","hoan3","ngoa1","ngua5","tuan2","ngoai2","oai1",
]

def run(stdin_text, flags):
    args = ["/tmp/ref_engine"]
    if flags.get("free"): args.append("--free")
    if flags.get("modern"): args.append("--modern")
    if not flags.get("spell", True): args.append("--nospell")
    p = subprocess.run(args, input=stdin_text, capture_output=True, text=True)
    return p.stdout.split("\n")

alphabet = "abcdefghijklmnopqrstuvwxyz"
digits = "0123456789"
specials = " \b"

def gen_random(rng, count, maxlen=13):
    cases = []
    for _ in range(count):
        n = rng.randint(1, maxlen)
        s = []
        for _ in range(n):
            r = rng.random()
            if r < 0.72:
                s.append(rng.choice(alphabet))
            elif r < 0.85:
                s.append(rng.choice(digits))
            elif r < 0.93:
                s.append(" ")
            else:
                s.append("\b")
        cases.append("".join(s))
    return cases

def main(out_path):
    flags_sets = [
        {"free": True, "spell": True, "modern": False},
        {"free": True, "spell": True, "modern": True},
        {"free": True, "spell": False, "modern": False},
        {"free": False, "spell": True, "modern": False},
    ]
    rng = random.Random(20251103)
    rows = []
    for flags in flags_sets:
        inputs = list(CURATED)
        # remove the intentionally broken cursor sequence
        inputs = [x for x in inputs if "ngươi-like" not in x and "???" not in x and "nghinee" not in x and "quickest" not in x]
        inputs += gen_random(rng, 2600)
        outs = run("\n".join(inputs), flags)
        # stdout line per input line

    for flags in flags_sets:
        inputs = [x for x in CURATED if "ngươi-like" not in x and "???" not in x and "nghinee" not in x and "quickest" not in x]
        inputs += gen_random(rng, 2600)
        outs = run("\n".join(inputs), flags)
        for inp, out in zip(inputs, outs):
            rows.append({"in": inp, "out": out, "free": flags["free"], "spell": flags["spell"], "modern": flags["modern"]})
    with open(out_path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print("rows:", len(rows))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "corpus.jsonl")
