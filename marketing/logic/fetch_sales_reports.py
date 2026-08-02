#!/usr/bin/env python3
"""
Fetch a Sales and Trends report from App Store Connect (v1/salesReports).

This is a DIFFERENT API from App Analytics (analyticsReportRequests). It requires
the account's Vendor Number, which is NOT exposed anywhere in the App Store Connect
REST API — you have to copy it from the App Store Connect web UI:
  App Store Connect -> Payments and Financial Reports -> "Vendor Number" (8 digits,
  same for every app in the account, shown near the top of the page).

Usage:
    cd /Users/oleksandr/Projects/rootyapps
    ASC_KEY_ID=55B6L3J65N \
    ASC_ISSUER_ID=057ddafb-cb0e-4410-9e0a-00e24f6e1688 \
    ASC_KEY_PATH=keys/AuthKey_55B6L3J65N.p8.txt \
    ASC_VENDOR_NUMBER=<your 8-digit vendor number> \
    conda run -n fantastic python3 marketing/logic/fetch_sales_reports.py <YYYY-MM-DD> [out_dir]

Notes:
- frequency=DAILY reports have roughly a 1-day lag (yesterday's data is usually the
  most recent available "today").
- reportType=SALES / reportSubType=SUMMARY gives units + proceeds per SKU per day.
  Units column includes free + paid; filter productTypeIdentifier / units>0 and
  check "Units" vs the "Proceeds" column to distinguish paid downloads.
- Response is gzip-compressed TSV, not JSON — this script decompresses and saves
  both the raw .gz and a decoded .tsv.
- A 404 with code NOT_FOUND typically means no data exists for that date (too
  recent, or before the report type existed for this account) rather than an error.
"""
import gzip
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import asc_client as c


def fetch_sales_report(report_date, report_type="SALES", report_sub_type="SUMMARY",
                        frequency="DAILY", vendor_number=None):
    vendor_number = vendor_number or os.environ.get("ASC_VENDOR_NUMBER")
    if not vendor_number:
        raise SystemExit(
            "Missing ASC_VENDOR_NUMBER. Find it in App Store Connect -> "
            "Payments and Financial Reports -> Vendor Number, and pass it via "
            "the ASC_VENDOR_NUMBER env var."
        )
    path = (
        "/v1/salesReports"
        f"?filter[reportDate]={report_date}"
        f"&filter[reportType]={report_type}"
        f"&filter[reportSubType]={report_sub_type}"
        f"&filter[frequency]={frequency}"
        f"&filter[vendorNumber]={vendor_number}"
    )
    url = c.BASE + path
    import urllib.request
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {c.token()}",
        "Accept": "application/a-gzip",
    })
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise RuntimeError(f"GET {url} -> {e.code}\n{detail}") from None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: fetch_sales_reports.py <YYYY-MM-DD> [out_dir]")
        sys.exit(1)
    report_date = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "."
    os.makedirs(out_dir, exist_ok=True)

    raw = fetch_sales_report(report_date)
    gz_path = os.path.join(out_dir, f"sales_{report_date}.tsv.gz")
    with open(gz_path, "wb") as f:
        f.write(raw)

    tsv = gzip.decompress(raw).decode("utf-8", errors="replace")
    tsv_path = os.path.join(out_dir, f"sales_{report_date}.tsv")
    with open(tsv_path, "w") as f:
        f.write(tsv)

    lines = tsv.splitlines()
    print(f"Saved {gz_path}")
    print(f"Saved {tsv_path}")
    print(f"{len(lines)} lines (including header)")
    if lines:
        print("Header:", lines[0])
    for line in lines[1:6]:
        print(line)
