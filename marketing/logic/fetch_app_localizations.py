#!/usr/bin/env python3
"""
Fetch app store version localizations (description, keywords, etc.) from App Store Connect API
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

def fetch_localizations(version_id, app_id=None):
    """Fetch localizations for a specific app store version"""
    token = get_jwt_token()
    url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"

    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")

    try:
        with urlopen(req) as response:
            data = json.loads(response.read())

            # Save full response
            filename = f'localizations_{version_id[:8]}.json'
            if app_id:
                filename = f'localizations_{app_id}_{version_id[:8]}.json'

            with open(filename, 'w') as f:
                json.dump(data, f, indent=2)

            print(f"Found {len(data.get('data', []))} localizations\n")

            # Display localization details
            for loc in data['data']:
                attrs = loc['attributes']
                locale = attrs.get('locale')
                description = attrs.get('description', '')
                keywords = attrs.get('keywords', 'N/A')

                print(f"=== {locale} ===")
                print(f"Description ({len(description)} chars):")
                if len(description) > 200:
                    print(description[:200] + "...")
                else:
                    print(description)
                print(f"\nKeywords: {keywords}")
                print(f"Marketing URL: {attrs.get('marketingUrl', 'N/A')}")
                print(f"Support URL: {attrs.get('supportUrl', 'N/A')}")
                print(f"Promotional Text: {attrs.get('promotionalText', 'N/A')}")
                print(f"What's New: {attrs.get('whatsNew', 'N/A')}")
                print()

            print(f"✓ Data saved to {filename}")
            return data

    except Exception as e:
        print(f"Error fetching localizations: {e}")
        return None

def get_latest_version_id(app_id):
    """Get the latest app store version ID for an app"""
    token = get_jwt_token()
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions"

    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")

    try:
        with urlopen(req) as response:
            data = json.loads(response.read())

            if data.get('data'):
                # Return first (latest) version ID
                return data['data'][0]['id']
            return None

    except Exception as e:
        print(f"Error fetching versions: {e}")
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 fetch_app_localizations.py <app_id>")
        print("  python3 fetch_app_localizations.py <app_id> <version_id>")
        print("\nExamples:")
        print("  python3 fetch_app_localizations.py 1570841203")
        print("  python3 fetch_app_localizations.py 1570841203 ef816b99-f4cc-49bc-a654-3ba745383a46")
        print("\nIf version_id is not provided, will use the latest version.")
        sys.exit(1)

    app_id = sys.argv[1]

    if len(sys.argv) >= 3:
        version_id = sys.argv[2]
    else:
        print(f"Fetching latest version for app {app_id}...")
        version_id = get_latest_version_id(app_id)

        if not version_id:
            print("Error: Could not find any versions for this app.")
            sys.exit(1)

        print(f"Using version ID: {version_id}\n")

    fetch_localizations(version_id, app_id)
