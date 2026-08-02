#!/usr/bin/env python3
"""
Comprehensive data fetcher for all apps in App Store Connect
Clears tmp/marketing and fetches all relevant data for analysis

Usage:
    cd /Users/oleksandr/Projects/rootyapps/tmp
    python3 ../marketing/logic/fetch_data.py
"""

import json
import time
import os
import shutil
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import jwt

# App Store Connect API credentials
KEY_ID = "55B6L3J65N"
ISSUER_ID = "057ddafb-cb0e-4410-9e0a-00e24f6e1688"
P8_PATH = "/Users/oleksandr/Projects/rootyapps/keys/AuthKey_55B6L3J65N.p8.txt"

# Output directory
OUTPUT_DIR = "marketing"

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

def api_request(url, description="API request"):
    """Make authenticated API request"""
    token = get_jwt_token()
    req = Request(url)
    req.add_header("Authorization", f"Bearer {token}")

    try:
        with urlopen(req) as response:
            return json.loads(response.read())
    except HTTPError as e:
        print(f"⚠️  {description} failed: {e}")
        return None

def setup_output_dir():
    """Clear and create output directory"""
    if os.path.exists(OUTPUT_DIR):
        print(f"🗑️  Clearing {OUTPUT_DIR}/...")
        shutil.rmtree(OUTPUT_DIR)

    os.makedirs(OUTPUT_DIR)
    print(f"✓ Created {OUTPUT_DIR}/\n")

def fetch_all_apps():
    """Fetch all apps from App Store Connect"""
    print("📱 Fetching all apps...")
    url = "https://api.appstoreconnect.apple.com/v1/apps?limit=200"
    data = api_request(url, "Fetch all apps")

    if data:
        filename = f"{OUTPUT_DIR}/apps.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"✓ Found {len(data.get('data', []))} apps\n")
        return data.get('data', [])

    return []

def fetch_app_info(app_id, app_name):
    """Fetch detailed app information"""
    print(f"  📋 Fetching app info for {app_name}...")
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}"
    data = api_request(url, f"App info for {app_name}")

    if data:
        filename = f"{OUTPUT_DIR}/app_info_{app_id}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"  ✓ Saved app info")
        return data

    return None

def fetch_app_versions(app_id, app_name):
    """Fetch all app store versions"""
    print(f"  📦 Fetching versions for {app_name}...")
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions"
    data = api_request(url, f"Versions for {app_name}")

    if data:
        filename = f"{OUTPUT_DIR}/versions_{app_id}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)

        versions = data.get('data', [])
        print(f"  ✓ Found {len(versions)} version(s)")
        return versions

    return []

def fetch_localizations(version_id, app_id, app_name, version_string):
    """Fetch localizations for a specific version"""
    print(f"  🌐 Fetching localizations for v{version_string}...")
    url = f"https://api.appstoreconnect.apple.com/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    data = api_request(url, f"Localizations for {app_name}")

    if data:
        filename = f"{OUTPUT_DIR}/localizations_{app_id}_{version_id[:8]}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)

        locs = data.get('data', [])
        print(f"  ✓ Found {len(locs)} localization(s)")
        return data

    return None

def fetch_app_prices(app_id, app_name):
    """Fetch app price schedule and price points"""
    print(f"  💰 Fetching prices for {app_name}...")

    # First get the price schedule
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appPriceSchedule?include=baseTerritory,manualPrices"
    data = api_request(url, f"Prices for {app_name}")

    if data:
        # Try to get price tier from manual prices
        manual_prices = data.get('data', {}).get('relationships', {}).get('manualPrices', {}).get('data', [])
        if manual_prices:
            price_id = manual_prices[0]['id']
            # Fetch detailed price info including priceTier
            price_url = f"https://api.appstoreconnect.apple.com/v1/appPrices/{price_id}?include=priceTier"
            price_detail = api_request(price_url, f"Price details for {app_name}")

            if price_detail:
                # Merge the detailed price info
                data['price_detail'] = price_detail

                # If we have a price tier, get the price points
                included = price_detail.get('included', [])
                for item in included:
                    if item.get('type') == 'appPriceTiers':
                        tier_id = item['id']
                        # Fetch price points for this tier
                        points_url = f"https://api.appstoreconnect.apple.com/v1/appPriceTiers/{tier_id}/pricePoints?filter[territory]=USA&limit=1"
                        points = api_request(points_url, f"Price points for {app_name}")
                        if points and points.get('data'):
                            data['price_points'] = points
                        break

        filename = f"{OUTPUT_DIR}/prices_{app_id}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"  ✓ Saved price data")
        return data

    return None

def fetch_analytics_requests(app_id, app_name):
    """Fetch analytics report requests"""
    print(f"  📊 Fetching analytics for {app_name}...")
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/analyticsReportRequests"
    data = api_request(url, f"Analytics for {app_name}")

    if data:
        filename = f"{OUTPUT_DIR}/analytics_{app_id}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)

        requests = data.get('data', [])
        print(f"  ✓ Found {len(requests)} analytics request(s)")
        return requests

    return []

def fetch_analytics_reports(request_id, app_id, app_name):
    """Fetch available reports for an analytics request"""
    print(f"  📈 Fetching analytics reports...")
    url = f"https://api.appstoreconnect.apple.com/v1/analyticsReportRequests/{request_id}/reports"
    data = api_request(url, f"Analytics reports for {app_name}")

    if data:
        filename = f"{OUTPUT_DIR}/analytics_reports_{app_id}_{request_id[:8]}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)

        reports = data.get('data', [])
        print(f"  ✓ Found {len(reports)} report(s)")
        return data

    return None

def process_app(app):
    """Process a single app - fetch all its data"""
    app_id = app['id']
    app_name = app['attributes']['name']

    print(f"\n{'='*60}")
    print(f"Processing: {app_name} (ID: {app_id})")
    print(f"{'='*60}")

    # Fetch app info
    fetch_app_info(app_id, app_name)

    # Fetch prices
    fetch_app_prices(app_id, app_name)

    # Fetch versions
    versions = fetch_app_versions(app_id, app_name)

    # Fetch localizations for the first (latest) version
    if versions:
        latest_version = versions[0]
        version_id = latest_version['id']
        version_string = latest_version['attributes'].get('versionString', 'unknown')
        fetch_localizations(version_id, app_id, app_name, version_string)

    # Fetch analytics
    analytics_requests = fetch_analytics_requests(app_id, app_name)

    # Fetch reports for first analytics request if available
    if analytics_requests:
        first_request = analytics_requests[0]
        request_id = first_request['id']
        fetch_analytics_reports(request_id, app_id, app_name)

    print()

def main():
    """Main execution"""
    print("=" * 60)
    print("App Store Connect Data Fetcher")
    print("=" * 60)
    print()

    # Setup output directory
    setup_output_dir()

    # Fetch all apps
    apps = fetch_all_apps()

    if not apps:
        print("❌ No apps found!")
        sys.exit(1)

    # Process each app
    for i, app in enumerate(apps, 1):
        print(f"\n[{i}/{len(apps)}]")
        process_app(app)

        # Small delay to avoid rate limiting
        if i < len(apps):
            time.sleep(1)

    print("\n" + "=" * 60)
    print("✅ ALL DATA FETCHED SUCCESSFULLY")
    print("=" * 60)
    print(f"\nData saved to: {OUTPUT_DIR}/")
    print(f"Total files: {len(list(Path(OUTPUT_DIR).glob('*.json')))}")
    print("\nNext step: Run parse_data.py to analyze the data")

if __name__ == "__main__":
    main()
