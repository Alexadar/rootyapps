#!/usr/bin/env python3
"""
Parse fetched App Store Connect data and output formatted analysis context
Reads JSON files from tmp/marketing and extracts key information

Usage:
    cd /Users/oleksandr/Projects/rootyapps/tmp
    python3 ../marketing/logic/parse_data.py
"""

import json
import os
import sys
import base64
from pathlib import Path

DATA_DIR = "marketing"

def load_json(filepath):
    """Load JSON file safely"""
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"⚠️  Error loading {filepath}: {e}", file=sys.stderr)
        return None

def parse_apps_list():
    """Parse main apps list"""
    data = load_json(f"{DATA_DIR}/apps.json")
    if not data:
        return []

    apps = []
    for app in data.get('data', []):
        attrs = app['attributes']
        apps.append({
            'id': app['id'],
            'name': attrs.get('name'),
            'bundle_id': attrs.get('bundleId'),
            'sku': attrs.get('sku'),
            'primary_locale': attrs.get('primaryLocale')
        })

    return apps

def parse_app_versions(app_id):
    """Parse app versions"""
    filepath = f"{DATA_DIR}/versions_{app_id}.json"
    if not os.path.exists(filepath):
        return []

    data = load_json(filepath)
    if not data:
        return []

    versions = []
    for version in data.get('data', []):
        attrs = version['attributes']
        versions.append({
            'version_id': version['id'],
            'version_string': attrs.get('versionString'),
            'platform': attrs.get('platform'),
            'state': attrs.get('appStoreState'),
            'release_type': attrs.get('releaseType'),
            'created_date': attrs.get('createdDate')
        })

    return versions

def parse_localizations(app_id):
    """Parse localizations (finds any localization file for this app)"""
    files = list(Path(DATA_DIR).glob(f"localizations_{app_id}_*.json"))

    if not files:
        return []

    # Use the first (should be latest version)
    data = load_json(str(files[0]))
    if not data:
        return []

    localizations = []
    for loc in data.get('data', []):
        attrs = loc['attributes']
        description = attrs.get('description') or ''
        keywords = attrs.get('keywords') or ''

        localizations.append({
            'locale': attrs.get('locale'),
            'description': description,
            'description_length': len(description),
            'keywords': keywords,
            'keyword_count': len([k.strip() for k in keywords.split(',') if k.strip()]) if keywords else 0,
            'promotional_text': attrs.get('promotionalText'),
            'whats_new': attrs.get('whatsNew'),
            'marketing_url': attrs.get('marketingUrl'),
            'support_url': attrs.get('supportUrl')
        })

    return localizations

def parse_app_prices(app_id):
    """Parse app pricing information"""
    filepath = f"{DATA_DIR}/prices_{app_id}.json"
    if not os.path.exists(filepath):
        return None

    data = load_json(filepath)
    if not data:
        return None

    # Standard Apple price tiers
    tier_prices = {
        '1': '0.99',
        '2': '1.99',
        '3': '2.99',
        '4': '3.99',
        '5': '4.99',
        '6': '5.99',
        '7': '6.99',
        '8': '7.99',
        '9': '8.99',
        '10': '9.99'
    }

    # Try to extract price tier from appPrices ID (base64 encoded)
    included = data.get('included', [])
    for item in included:
        if item.get('type') == 'appPrices':
            price_id = item.get('id', '')
            try:
                # Decode base64 ID to extract price tier
                decoded = base64.b64decode(price_id).decode('utf-8')
                decoded_json = json.loads(decoded)
                tier = str(decoded_json.get('p', ''))

                if tier in tier_prices:
                    return {
                        'customer_price': tier_prices[tier],
                        'proceeds': None,
                        'territory': 'USA',
                        'tier': tier,
                        'source': 'decoded_tier'
                    }
            except:
                pass

    # Try to extract from price_points (new format)
    if 'price_points' in data:
        price_points = data['price_points'].get('data', [])
        if price_points:
            point = price_points[0]
            attrs = point.get('attributes', {})
            return {
                'customer_price': attrs.get('customerPrice'),
                'proceeds': attrs.get('proceeds'),
                'territory': 'USA',
                'source': 'api'
            }

    # Try to extract from price_detail
    if 'price_detail' in data:
        detail = data['price_detail']
        included = detail.get('included', [])
        for item in included:
            if item.get('type') == 'appPriceTiers':
                tier_id = item.get('id')
                if tier_id in tier_prices:
                    return {
                        'customer_price': tier_prices[tier_id],
                        'proceeds': None,
                        'territory': 'USA',
                        'tier': tier_id,
                        'source': 'tier_mapping'
                    }

    # Fallback - just indicate pricing is configured but amount unknown
    if data.get('data'):
        return {'status': 'configured', 'customer_price': None}

    return None

def parse_analytics(app_id):
    """Parse analytics requests"""
    filepath = f"{DATA_DIR}/analytics_{app_id}.json"
    if not os.path.exists(filepath):
        return []

    data = load_json(filepath)
    if not data:
        return []

    analytics = []
    for req in data.get('data', []):
        attrs = req['attributes']
        analytics.append({
            'request_id': req['id'],
            'access_type': attrs.get('accessType')
        })

    return analytics

def format_app_summary(app, versions, localizations, prices, analytics):
    """Format a single app summary"""
    lines = []

    # Header
    lines.append(f"\n{'='*80}")
    lines.append(f"APP: {app['name']}")
    lines.append(f"{'='*80}")

    # Basic info
    lines.append(f"\n📱 BASIC INFO:")
    lines.append(f"  App ID: {app['id']}")
    lines.append(f"  Bundle ID: {app['bundle_id']}")
    lines.append(f"  SKU: {app['sku']}")
    lines.append(f"  Primary Locale: {app['primary_locale']}")

    # Pricing
    lines.append(f"\n💰 PRICING:")
    if prices:
        if isinstance(prices, dict):
            if prices.get('customer_price'):
                price = prices['customer_price']
                lines.append(f"  Price: ${price}")
                if prices.get('proceeds'):
                    lines.append(f"  Proceeds: ${prices['proceeds']}")
                if prices.get('tier'):
                    lines.append(f"  Tier: {prices['tier']}")
                if prices.get('source'):
                    lines.append(f"  Source: {prices['source']}")
            elif 'status' in prices:
                if prices['status'] == 'configured':
                    lines.append(f"  ⚠️  Pricing configured but amount unavailable from API")
                    lines.append(f"  Note: Manual price lookup required")
                else:
                    lines.append(f"  Status: {prices['status']}")
            else:
                lines.append(f"  Status: Configured (details unknown)")
        else:
            lines.append(f"  ⚠️  Price data format unknown")
    else:
        lines.append(f"  ⚠️  No pricing data - app not published or removed from sale")
        lines.append(f"  Note: Revenue projections not available for this app")

    # Versions
    lines.append(f"\n📦 VERSIONS ({len(versions)}):")
    if versions:
        for v in versions[:3]:  # Show first 3
            lines.append(f"  • v{v['version_string']} ({v['platform']})")
            lines.append(f"    State: {v['state']}")
            lines.append(f"    Release: {v['release_type']}")
    else:
        lines.append(f"  ⚠️  No versions found")

    # Localizations
    lines.append(f"\n🌐 LOCALIZATIONS ({len(localizations)}):")
    if localizations:
        for loc in localizations:
            lines.append(f"\n  Locale: {loc['locale']}")
            lines.append(f"  Description: {loc['description_length']} chars")

            # Show description snippet
            if loc['description']:
                snippet = loc['description'][:150]
                if len(loc['description']) > 150:
                    snippet += "..."
                lines.append(f"  Preview: \"{snippet}\"")
            else:
                lines.append(f"  Preview: (empty)")

            lines.append(f"  Keywords: {loc['keyword_count']} keywords")
            if loc['keywords']:
                lines.append(f"  Keywords: {loc['keywords']}")

            if loc['promotional_text']:
                lines.append(f"  Promotional Text: {loc['promotional_text'][:100]}...")

            if loc['marketing_url']:
                lines.append(f"  Marketing URL: {loc['marketing_url']}")

            if loc['support_url']:
                lines.append(f"  Support URL: {loc['support_url']}")
    else:
        lines.append(f"  ⚠️  No localizations found")

    # Analytics
    lines.append(f"\n📊 ANALYTICS:")
    if analytics:
        for a in analytics:
            lines.append(f"  • Request ID: {a['request_id'][:8]}...")
            lines.append(f"    Access Type: {a['access_type']}")
    else:
        lines.append(f"  ⚠️  No analytics data found")

    return "\n".join(lines)

def generate_portfolio_summary(apps_data):
    """Generate overall portfolio summary"""
    lines = []

    lines.append("\n" + "="*80)
    lines.append("PORTFOLIO SUMMARY")
    lines.append("="*80)

    lines.append(f"\nTotal Apps: {len(apps_data)}")

    # Count by platform
    platforms = {}
    states = {}
    for app_data in apps_data:
        for version in app_data['versions']:
            platform = version['platform']
            state = version['state']
            platforms[platform] = platforms.get(platform, 0) + 1
            states[state] = states.get(state, 0) + 1

    lines.append(f"\nPlatforms:")
    for platform, count in sorted(platforms.items()):
        lines.append(f"  • {platform}: {count}")

    lines.append(f"\nStates:")
    for state, count in sorted(states.items()):
        lines.append(f"  • {state}: {count}")

    # Pricing status
    lines.append(f"\n💰 PRICING STATUS:")
    apps_with_prices = 0
    apps_without_prices = 0
    for app_data in apps_data:
        prices = app_data['prices']
        if prices and prices.get('customer_price'):
            apps_with_prices += 1
        else:
            apps_without_prices += 1

    lines.append(f"  Apps with pricing data: {apps_with_prices}")
    lines.append(f"  Apps without pricing data: {apps_without_prices}")

    # Apps with issues
    lines.append(f"\n⚠️  POTENTIAL ISSUES:")

    issues_found = False
    for app_data in apps_data:
        app = app_data['app']
        localizations = app_data['localizations']

        app_issues = []

        # Check for short descriptions
        for loc in localizations:
            if loc['description_length'] < 500:
                app_issues.append(f"Short description ({loc['description_length']} chars)")

        # Check for few keywords
        for loc in localizations:
            if loc['keyword_count'] < 10:
                app_issues.append(f"Few keywords ({loc['keyword_count']})")

        # Check for missing analytics
        if not app_data['analytics']:
            app_issues.append("No analytics data")

        # Check for missing prices
        if not app_data['prices'] or not app_data['prices'].get('customer_price'):
            app_issues.append("No pricing data (can't project revenue)")

        if app_issues:
            issues_found = True
            lines.append(f"\n  {app['name']}:")
            for issue in app_issues:
                lines.append(f"    - {issue}")

    if not issues_found:
        lines.append("  None found!")

    return "\n".join(lines)

def generate_revenue_projections(apps_data):
    """Generate revenue projections for apps with pricing data"""
    lines = []

    lines.append("\n" + "="*80)
    lines.append("REVENUE PROJECTIONS")
    lines.append("="*80)
    lines.append("\nNote: Projections shown only for apps with pricing data")
    lines.append("Apps without pricing data will show ASO recommendations only\n")

    # Separate apps with/without prices
    apps_with_prices = []
    apps_without_prices = []

    for app_data in apps_data:
        if app_data['prices'] and app_data['prices'].get('customer_price'):
            apps_with_prices.append(app_data)
        else:
            apps_without_prices.append(app_data)

    # Apps WITH prices
    if apps_with_prices:
        lines.append("=" * 80)
        lines.append(f"APPS WITH PRICING DATA ({len(apps_with_prices)} apps)")
        lines.append("=" * 80)

        for app_data in apps_with_prices:
            app = app_data['app']
            prices = app_data['prices']
            localizations = app_data['localizations']
            versions = app_data['versions']

            lines.append(f"\n📱 {app['name']}")
            lines.append(f"   Price: ${prices['customer_price']}")

            # Check if live
            is_live = any(v['state'] == 'READY_FOR_SALE' for v in versions)
            lines.append(f"   Status: {'✅ LIVE' if is_live else '⏳ NOT LIVE YET'}")

            # ASO Issues
            aso_issues = []
            for loc in localizations:
                if loc['description_length'] < 500:
                    aso_issues.append(f"Short description ({loc['description_length']} chars)")
                if loc['keyword_count'] < 10:
                    aso_issues.append(f"Few keywords ({loc['keyword_count']})")

            if aso_issues:
                lines.append(f"   ASO Issues: {', '.join(aso_issues)}")
            else:
                lines.append(f"   ASO Status: ✅ Good")

            lines.append(f"   Revenue Projection: [Requires actual sales data for baseline]")

    # Apps WITHOUT prices
    if apps_without_prices:
        lines.append("\n" + "=" * 80)
        lines.append(f"APPS WITHOUT PRICING DATA ({len(apps_without_prices)} apps)")
        lines.append("=" * 80)
        lines.append("Note: Cannot project revenue without pricing data")
        lines.append("These apps need to be published or re-enabled for sale\n")

        for app_data in apps_without_prices:
            app = app_data['app']
            localizations = app_data['localizations']
            versions = app_data['versions']

            lines.append(f"\n📱 {app['name']}")

            # Check status
            has_versions = len(versions) > 0
            if has_versions:
                is_live = any(v['state'] == 'READY_FOR_SALE' for v in versions)
                if is_live:
                    lines.append(f"   Status: ⚠️  LIVE but no price data (API issue)")
                else:
                    lines.append(f"   Status: ⏳ In submission, not yet published")
            else:
                lines.append(f"   Status: ❌ No versions created")

            # ASO Issues
            aso_issues = []
            for loc in localizations:
                if loc['description_length'] == 0:
                    aso_issues.append("❌ NO DESCRIPTION (blocking)")
                elif loc['description_length'] < 500:
                    aso_issues.append(f"Short description ({loc['description_length']} chars)")
                if loc['keyword_count'] == 0:
                    aso_issues.append("❌ NO KEYWORDS (blocking)")
                elif loc['keyword_count'] < 10:
                    aso_issues.append(f"Few keywords ({loc['keyword_count']})")

            if aso_issues:
                lines.append(f"   Issues: {', '.join(aso_issues)}")
                lines.append(f"   Action: Fix metadata to enable publishing")
            else:
                lines.append(f"   Action: Set pricing and publish")

    return "\n".join(lines)

def main():
    """Main execution"""
    print("="*80, file=sys.stderr)
    print("App Store Connect Data Parser", file=sys.stderr)
    print("="*80, file=sys.stderr)

    # Check if data directory exists
    if not os.path.exists(DATA_DIR):
        print(f"\n❌ Error: {DATA_DIR}/ directory not found!", file=sys.stderr)
        print(f"Run fetch_data.py first to download data.\n", file=sys.stderr)
        sys.exit(1)

    # Parse apps list
    print(f"\n📱 Parsing apps list...", file=sys.stderr)
    apps = parse_apps_list()

    if not apps:
        print("❌ No apps found in data!", file=sys.stderr)
        sys.exit(1)

    print(f"✓ Found {len(apps)} apps\n", file=sys.stderr)

    # Parse each app's data
    apps_data = []
    for i, app in enumerate(apps, 1):
        print(f"[{i}/{len(apps)}] Parsing {app['name']}...", file=sys.stderr)

        versions = parse_app_versions(app['id'])
        localizations = parse_localizations(app['id'])
        prices = parse_app_prices(app['id'])
        analytics = parse_analytics(app['id'])

        apps_data.append({
            'app': app,
            'versions': versions,
            'localizations': localizations,
            'prices': prices,
            'analytics': analytics
        })

    print("\n" + "="*80, file=sys.stderr)
    print("✅ PARSING COMPLETE", file=sys.stderr)
    print("="*80, file=sys.stderr)
    print("\nOutputting formatted data for Claude analysis...\n", file=sys.stderr)
    print("="*80 + "\n", file=sys.stderr)

    # Output to stdout (for Claude to read)
    print(generate_portfolio_summary(apps_data))

    for app_data in apps_data:
        print(format_app_summary(
            app_data['app'],
            app_data['versions'],
            app_data['localizations'],
            app_data['prices'],
            app_data['analytics']
        ))

    # Add revenue projections summary
    print(generate_revenue_projections(apps_data))

    print("\n" + "="*80)
    print("END OF DATA")
    print("="*80)

    print(f"\n✓ Data output complete", file=sys.stderr)
    print(f"✓ Ready for Claude analysis\n", file=sys.stderr)

if __name__ == "__main__":
    main()
