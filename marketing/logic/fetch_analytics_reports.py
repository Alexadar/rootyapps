#!/usr/bin/env python3
"""
Fetch analytics reports for a specific app from App Store Connect API
Requires: PyJWT, cryptography (install via: pip install PyJWT cryptography)
"""

import json
import time
import sys
from urllib.request import Request, urlopen
import jwt

# App Store Connect API credentials
KEY_ID = "55B6L3J65N"
ISSUER_ID = "057ddafb-cb0e-4410-9e0a-00e24f6e1688"
P8_PATH = "/Users/oleksandr/Projects/rootyapps/keys/AuthKey_55B6L3J65N.p8.txt"

def get_jwt_token():
    """Generate JWT token for App Store Connect API"""
    with open(P8_PATH, 'r') as f:
        private_key = f.read()

    payload = {
        "iss": ISSUER_ID,
        "exp": int(time.time()) + 1200,  # 20 minutes
        "aud": "appstoreconnect-v1"
    }

    return jwt.encode(payload, private_key, algorithm="ES256",
                     headers={"alg": "ES256", "kid": KEY_ID, "typ": "JWT"})

def fetch_analytics_requests(app_id):
    """Fetch all analytics report requests for an app"""
    token = get_jwt_token()
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/analyticsReportRequests"

    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")

    with urlopen(req) as response:
        data = json.loads(response.read())

        # Save full response
        filename = f'analytics_requests_{app_id}.json'
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)

        print(f"Found {len(data.get('data', []))} analytics report requests")

        for report in data.get('data', []):
            print(f"ID: {report['id']}, Access Type: {report['attributes'].get('accessType', 'N/A')}")

        return data

def fetch_available_reports(report_request_id):
    """Fetch available reports for a specific analytics request"""
    token = get_jwt_token()
    url = f"https://api.appstoreconnect.apple.com/v1/analyticsReportRequests/{report_request_id}/reports"

    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")

    with urlopen(req) as response:
        data = json.loads(response.read())

        # Save full response
        filename = f'analytics_reports_{report_request_id[:8]}.json'
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)

        print(f"\nFound {len(data.get('data', []))} analytics reports")

        # Group by category
        by_category = {}
        for report in data.get('data', []):
            category = report['attributes'].get('category')
            if category not in by_category:
                by_category[category] = []
            by_category[category].append(report['attributes'].get('name'))

        print("\nReports by category:")
        for category, reports in sorted(by_category.items()):
            print(f"\n{category}: {len(reports)} reports")
            for report_name in reports[:3]:  # Show first 3
                print(f"  - {report_name}")
            if len(reports) > 3:
                print(f"  ... and {len(reports) - 3} more")

        return data

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 fetch_analytics_reports.py <app_id>")
        print("  python3 fetch_analytics_reports.py <app_id> <report_request_id>")
        print("\nExample:")
        print("  python3 fetch_analytics_reports.py 1570956847")
        print("  python3 fetch_analytics_reports.py 1570956847 4c57f118-3daf-4aba-927f-38f9656e5593")
        sys.exit(1)

    app_id = sys.argv[1]

    print(f"Fetching analytics for app {app_id}...\n")
    requests_data = fetch_analytics_requests(app_id)

    # If report request ID provided, fetch those reports
    if len(sys.argv) >= 3:
        report_request_id = sys.argv[2]
    elif requests_data.get('data'):
        # Use first available request
        report_request_id = requests_data['data'][0]['id']
        print(f"\nUsing report request: {report_request_id}")
    else:
        print("\nNo analytics report requests found for this app.")
        print("Create one using: mcp__app-store-connect__create_analytics_report_request")
        sys.exit(0)

    fetch_available_reports(report_request_id)

    print("\n✓ Analytics data saved to JSON files")
