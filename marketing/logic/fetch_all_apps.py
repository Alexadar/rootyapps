#!/usr/bin/env python3
"""
Fetch all apps from App Store Connect API
Requires: PyJWT, cryptography (install via: pip install PyJWT cryptography)
"""

import json
import time
from urllib.request import Request, urlopen
import jwt

# App Store Connect API credentials
KEY_ID = "55B6L3J65N"
ISSUER_ID = "057ddafb-cb0e-4410-9e0a-00e24f6e1688"
P8_PATH = "/Users/oleksandr/Projects/rootyapps/keys/AuthKey_55B6L3J65N.p8.txt"

# Read private key
with open(P8_PATH, 'r') as f:
    private_key = f.read()

# Create JWT token
headers_jwt = {
    "alg": "ES256",
    "kid": KEY_ID,
    "typ": "JWT"
}

payload = {
    "iss": ISSUER_ID,
    "exp": int(time.time()) + 1200,  # 20 minutes
    "aud": "appstoreconnect-v1"
}

token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers_jwt)

# Fetch apps from API
url = "https://api.appstoreconnect.apple.com/v1/apps?limit=200"
req = Request(url)
req.add_header("Authorization", f"Bearer {token}")

with urlopen(req) as response:
    data = json.loads(response.read())

    # Save full response
    with open('all_apps_full.json', 'w') as f:
        json.dump(data, f, indent=2)

    # Print and save summary
    print(f"Total apps: {len(data['data'])}")
    print()

    with open('all_apps_list.txt', 'w') as f:
        for app in data['data']:
            attrs = app['attributes']
            line = f"{attrs['name']}|{app['id']}|{attrs['bundleId']}|{attrs.get('sku', 'N/A')}"
            print(line)
            f.write(line + '\n')

print("\nFiles saved:")
print("- all_apps_full.json (complete API response)")
print("- all_apps_list.txt (summary list)")
