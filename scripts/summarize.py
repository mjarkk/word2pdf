#!/usr/bin/env python3
"""Summarize a compare.py report: compare.py OUT_DIR/report.json [--all]"""
import json, statistics as st, sys
r = json.load(open(sys.argv[1]))
t = [x["text_ratio"] for x in r if "text_ratio" in x]
p = [x["pixel_diff"] for x in r if x.get("pixel_diff") is not None]
print("converted %d/%d, same pages %d, identical text %d, pixel-identical %d/%d" % (
    sum(1 for x in r if x["status"] == 0), len(r),
    sum(1 for x in r if x.get("pages") is not None and x.get("pages") == x.get("ref_pages")),
    sum(v == 1.0 for v in t), sum(v == 0 for v in p), len(p)))
secs = [x["seconds"] for x in r]
rss = [x["rss_mb"] for x in r if x.get("rss_mb")]
print("seconds median %.2f max %.2f; peak RSS MB median %d max %d" % (st.median(secs), max(secs), st.median(rss), max(rss)))
for x in r:
    if x["status"] != 0 or x.get("text_ratio", 1) < 1 or (x.get("pixel_diff") or 0) > 0 or "--all" in sys.argv:
        print("  %-50s exit=%s pages=%s/%s text=%s pixel=%s %s" % (x["name"][:50], x["status"], x.get("pages"), x.get("ref_pages"),
              x.get("text_ratio"), x.get("pixel_diff"), (x["stderr"].strip().splitlines() or [""])[-1][:120]))
# a document that does not convert is a failure; differences from the reference are reported
sys.exit(1 if any(x["status"] != 0 for x in r) else 0)
