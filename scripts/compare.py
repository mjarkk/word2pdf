#!/usr/bin/env python3
"""Convert a corpus with word2pdf and compare against reference PDFs.

    compare.py WORD2PDF CORPUS_DIR REFERENCE_DIR OUT_DIR [--jobs N] [--timeout S] [-- WORD2PDF_ARGS...]

For every document: exit status, wall time and peak RSS of the converter, then page count,
extracted text and a coarse per-page pixel difference against the reference PDF
(needs poppler-utils and Pillow). Prints a table and writes OUT_DIR/report.json.
"""

import argparse
import concurrent.futures
import difflib
import json
import os
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageChops


def peak_rss_mb(stats):
    """Peak RSS from /usr/bin/time's output file (GNU: KiB, BSD/macOS -l: bytes)."""
    if sys.platform == "darwin":
        for line in stats.splitlines():
            if line.strip().endswith("maximum resident set size"):
                return int(line.split()[0]) // (1024 * 1024)
        return None
    lines = stats.split()
    return int(lines[-1]) // 1024 if lines and lines[-1].isdigit() else None


def run_converter(word2pdf, extra, src, dst, timeout):
    timer = ["-l"] if sys.platform == "darwin" else ["-f", "%M"]
    with tempfile.NamedTemporaryFile("r") as stats:
        start = time.monotonic()
        proc = subprocess.Popen(["/usr/bin/time", *timer, "-o", stats.name,
                                 word2pdf, *extra, "--timeout", str(timeout), src, dst],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            _, err = proc.communicate(timeout=timeout + 30)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, err = proc.communicate()
            return {"status": "killed", "seconds": timeout + 30, "rss_mb": None,
                    "stderr": err.decode(errors="replace")}
        seconds = round(time.monotonic() - start, 2)
        rss = peak_rss_mb(stats.read())
    return {"status": proc.returncode, "seconds": seconds, "rss_mb": rss,
            "stderr": err.decode(errors="replace")[-2000:]}


def pdf_pages(path):
    out = subprocess.run(["pdfinfo", path], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("Pages:"):
            return int(line.split()[1])
    return None


def pdf_text(path):
    return subprocess.run(["pdftotext", "-q", path, "-"], capture_output=True, text=True,
                          errors="replace").stdout


def render(path, outdir, prefix):
    subprocess.run(["pdftoppm", "-q", "-r", "30", "-gray", "-png", path, os.path.join(outdir, prefix)],
                   check=False)
    return sorted(f for f in os.listdir(outdir) if f.startswith(prefix + "-"))


def pixel_diff(a_pdf, b_pdf):
    """Mean over pages of the fraction of differing pixels (0 = identical)."""
    with tempfile.TemporaryDirectory() as tmp:
        a = render(a_pdf, tmp, "a")
        b = render(b_pdf, tmp, "b")
        if not a or len(a) != len(b):
            return None
        total = 0.0
        for fa, fb in zip(a, b):
            ia = Image.open(os.path.join(tmp, fa))
            ib = Image.open(os.path.join(tmp, fb))
            if ia.size != ib.size:
                total += 1.0
                continue
            diff = ImageChops.difference(ia, ib).point(lambda v: 255 if v > 48 else 0)
            hist = diff.histogram()
            total += hist[255] / (ia.size[0] * ia.size[1])
        return round(total / len(a), 4)


def compare_one(args, name):
    src = os.path.join(args.corpus, name)
    base = os.path.splitext(name)[0]
    dst = os.path.join(args.out, base + ".pdf")
    ref = os.path.join(args.reference, base + ".pdf")
    if os.path.exists(dst):
        os.remove(dst)
    result = {"name": name}
    result.update(run_converter(args.word2pdf, args.extra, src, dst, args.timeout))
    result["ref_exists"] = os.path.exists(ref)
    result["out_exists"] = os.path.exists(dst)
    if result["out_exists"] and result["ref_exists"]:
        result["pages"] = pdf_pages(dst)
        result["ref_pages"] = pdf_pages(ref)
        ta, tb = pdf_text(dst), pdf_text(ref)
        result["text_ratio"] = round(difflib.SequenceMatcher(None, ta, tb, autojunk=False).ratio(), 4) \
            if len(ta) + len(tb) < 400000 else (1.0 if ta == tb else 0.0)
        result["pixel_diff"] = pixel_diff(dst, ref) if result["pages"] == result["ref_pages"] else None
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("word2pdf")
    parser.add_argument("corpus")
    parser.add_argument("reference")
    parser.add_argument("out")
    parser.add_argument("--jobs", type=int, default=os.cpu_count())
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("extra", nargs="*")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    names = sorted(os.listdir(args.corpus))
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda n: compare_one(args, n), names))

    with open(os.path.join(args.out, "report.json"), "w") as f:
        json.dump(results, f, indent=1)

    ok = sum(1 for r in results if r["status"] == 0 and r["out_exists"])
    same_pages = sum(1 for r in results if r.get("pages") is not None and r.get("pages") == r.get("ref_pages"))
    print("%-60s %6s %6s %6s %9s %6s %6s" % ("document", "exit", "secs", "MB", "pages", "text", "pixel"))
    for r in results:
        pages = "%s/%s" % (r.get("pages"), r.get("ref_pages")) if "pages" in r else "-"
        print("%-60s %6s %6s %6s %9s %6s %6s" % (r["name"][:60], r["status"], r["seconds"], r.get("rss_mb"),
                                                pages, r.get("text_ratio", "-"), r.get("pixel_diff", "-")))
    print("\nconverted %d/%d, same page count %d, references %d" %
          (ok, len(results), same_pages, sum(1 for r in results if r["ref_exists"])))
    failed = [r for r in results if r["status"] != 0]
    for r in failed[:20]:
        print("FAILED %s (%s): %s" % (r["name"], r["status"], r["stderr"].strip().splitlines()[-1:] if r["stderr"].strip() else ""))


if __name__ == "__main__":
    sys.exit(main())
