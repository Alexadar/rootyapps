#!/usr/bin/env python3
"""
Fetch app store versions for a specific app from App Store Connect API
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

def fetch_app_versions(app_id):
    """Fetch all app store versions for an app"""
    token = get_jwt_token()
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions"

    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")

    try:
        with urlopen(req) as response:
            data = json.loads(response.read())

            # Save full response
            filename = f'app_versions_{app_id}.json'
            with open(filename, 'w') as f:
                json.dump(data, f, indent=2)

            print(f"Found {len(data.get('data', []))} app store versions\n")

            # Display version details
            for version in data.get('data', []):
                attrs = version['attributes']
                print(f"Version: {attrs.get('versionString')}")
                print(f"  Platform: {attrs.get('platform')}")
                print(f"  State: {attrs.get('appStoreState')}")
                print(f"  Release Type: {attrs.get('releaseType')}")
                print(f"  Version ID: {version['id']}")
                print()

            print(f"✓ Data saved to {filename}")
            return data

    except Exception as e:
        print(f"Error fetching versions: {e}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 fetch_app_versions.py <app_id>")
        print("\nExample:")
        print("  python3 fetch_app_versions.py 1570841203")
        print("\nThis will fetch all app store versions for the specified app.")
        sys.exit(1)

    app_id = sys.argv[1]
    fetch_app_versions(app_id)
