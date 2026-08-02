#!/usr/bin/env python3
"""
Fetch customer reviews for App Store apps via RSS feeds

Apple's App Store Connect API does not provide endpoints for customer reviews.
This script uses the public RSS feeds to fetch reviews programmatically.

Usage:
    cd /Users/oleksandr/Projects/rootyapps/tmp
    python3 ../marketing/logic/fetch_reviews.py <app_id> [country_code] [page]

Examples:
    # Fetch US reviews for Golden Ratio Calculator Lite (page 1)
    python3 ../marketing/logic/fetch_reviews.py 1570956847

    # Fetch UK reviews
    python3 ../marketing/logic/fetch_reviews.py 1570956847 gb

    # Fetch specific page
    python3 ../marketing/logic/fetch_reviews.py 1570956847 us 2

    # Fetch all apps reviews (from apps.json)
    python3 ../marketing/logic/fetch_reviews.py --all

Output:
    - reviews_<app_id>_<country>.json - All reviews with metadata
    - reviews_<app_id>_<country>_unanswered.json - Only unanswered reviews
"""

import sys
import json
import xml.etree.ElementTree as ET
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from pathlib import Path
from datetime import datetime
import time

def fetch_reviews_page(app_id, country='us', page=1, sort='mostrecent'):
    """
    Fetch a single page of reviews from App Store RSS feed

    Args:
        app_id: Apple App Store app ID
        country: 2-letter country code (us, gb, jp, etc.)
        page: Page number (1-10, Apple limits to 10 pages)
        sort: 'mostrecent' or 'mosthelpful'

    Returns:
        List of review dictionaries
    """
    url = f"https://itunes.apple.com/{country}/rss/customerreviews/page={page}/id={app_id}/sortby={sort}/xml"

    try:
        req = Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0')

        with urlopen(req, timeout=30) as response:
            xml_data = response.read()

        # Parse XML
        root = ET.fromstring(xml_data)

        # Extract namespace
        ns = {'atom': 'http://www.w3.org/2005/Atom',
              'im': 'http://itunes.apple.com/rss'}

        reviews = []

        # Skip first entry (it's app info, not a review)
        entries = root.findall('.//atom:entry', ns)[1:]

        for entry in entries:
            try:
                review = {
                    'id': entry.find('atom:id', ns).text if entry.find('atom:id', ns) is not None else None,
                    'title': entry.find('atom:title', ns).text if entry.find('atom:title', ns) is not None else None,
                    'content': entry.find('atom:content', ns).text if entry.find('atom:content', ns) is not None else None,
                    'rating': int(entry.find('im:rating', ns).text) if entry.find('im:rating', ns) is not None else None,
                    'author': entry.find('atom:author/atom:name', ns).text if entry.find('atom:author/atom:name', ns) is not None else None,
                    'version': entry.find('im:version', ns).text if entry.find('im:version', ns) is not None else None,
                    'updated': entry.find('atom:updated', ns).text if entry.find('atom:updated', ns) is not None else None,
                    'vote_sum': entry.find('im:voteSum', ns).text if entry.find('im:voteSum', ns) is not None else None,
                    'vote_count': entry.find('im:voteCount', ns).text if entry.find('im:voteCount', ns) is not None else None,
                }
                reviews.append(review)
            except Exception as e:
                print(f"Warning: Failed to parse review entry: {e}", file=sys.stderr)
                continue

        return reviews

    except HTTPError as e:
        if e.code == 404:
            print(f"No reviews found for app {app_id} in {country.upper()} (page {page})", file=sys.stderr)
            return []
        else:
            print(f"HTTP Error {e.code}: {e.reason}", file=sys.stderr)
            return []
    except URLError as e:
        print(f"URL Error: {e.reason}", file=sys.stderr)
        return []
    except ET.ParseError as e:
        print(f"XML Parse Error: {e}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        return []

def fetch_all_reviews(app_id, country='us', max_pages=10, sort='mostrecent'):
    """
    Fetch all available reviews for an app (up to max_pages)

    Args:
        app_id: Apple App Store app ID
        country: 2-letter country code
        max_pages: Maximum number of pages to fetch (Apple limits to 10)
        sort: 'mostrecent' or 'mosthelpful'

    Returns:
        List of all reviews
    """
    all_reviews = []

    print(f"Fetching reviews for app {app_id} in {country.upper()}...")

    for page in range(1, max_pages + 1):
        print(f"  Fetching page {page}...", end=' ')
        reviews = fetch_reviews_page(app_id, country, page, sort)

        if not reviews:
            print("No more reviews.")
            break

        print(f"Got {len(reviews)} reviews.")
        all_reviews.extend(reviews)

        # Rate limiting - be nice to Apple's servers
        if page < max_pages:
            time.sleep(1)

    print(f"Total reviews fetched: {len(all_reviews)}")
    return all_reviews

def filter_unanswered(reviews):
    """
    Filter reviews to find potentially unanswered ones.

    Note: RSS feeds don't show developer responses, so we can't definitively
    identify unanswered reviews. This returns all reviews for manual review.

    To check if reviews are answered, you need to:
    1. Check App Store Connect web interface
    2. Use App Store Connect mobile app

    Returns:
        List of all reviews (since we can't determine answered status via RSS)
    """
    # RSS feeds don't include developer responses, so we return all reviews
    # You'll need to manually check App Store Connect to see which are answered
    return reviews

def save_reviews(reviews, filename):
    """Save reviews to JSON file with metadata"""
    output = {
        'fetched_at': datetime.now().isoformat(),
        'total_reviews': len(reviews),
        'reviews': reviews,
        'note': 'RSS feeds do not include developer responses. Check App Store Connect to identify actually unanswered reviews.'
    }

    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"Saved {len(reviews)} reviews to {filename}")

def fetch_app_info_from_api(app_id):
    """Get app name from local apps.json if available"""
    try:
        apps_file = Path('marketing/apps.json')
        if apps_file.exists():
            with open(apps_file, 'r') as f:
                data = json.load(f)
                for app in data.get('data', []):
                    if app.get('id') == str(app_id):
                        return app.get('attributes', {}).get('name', f'App_{app_id}')
    except Exception:
        pass
    return f'App_{app_id}'

def fetch_all_apps_reviews(country='us', max_pages=10):
    """Fetch reviews for all apps from apps.json"""
    apps_file = Path('marketing/apps.json')

    if not apps_file.exists():
        print("Error: marketing/apps.json not found. Run fetch_data.py first.", file=sys.stderr)
        return

    with open(apps_file, 'r') as f:
        data = json.load(f)

    apps = data.get('data', [])
    print(f"Found {len(apps)} apps to fetch reviews for\n")

    for i, app in enumerate(apps, 1):
        app_id = app['id']
        app_name = app.get('attributes', {}).get('name', 'Unknown')

        print(f"\n[{i}/{len(apps)}] {app_name} (ID: {app_id})")
        print("=" * 60)

        reviews = fetch_all_reviews(app_id, country, max_pages)

        if reviews:
            filename = f"reviews_{app_id}_{country}.json"
            save_reviews(reviews, filename)

            # Also save a note about unanswered reviews
            unanswered_file = f"reviews_{app_id}_{country}_unanswered.json"
            save_reviews(reviews, unanswered_file)

            # Summary statistics
            ratings = [r['rating'] for r in reviews if r.get('rating')]
            if ratings:
                avg_rating = sum(ratings) / len(ratings)
                print(f"  Average rating: {avg_rating:.2f} stars")
                print(f"  Rating distribution: 5★={ratings.count(5)}, 4★={ratings.count(4)}, 3★={ratings.count(3)}, 2★={ratings.count(2)}, 1★={ratings.count(1)}")
        else:
            print(f"  No reviews found for {app_name}")

        # Rate limiting between apps
        if i < len(apps):
            time.sleep(2)

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    # Check for --all flag
    if sys.argv[1] == '--all':
        country = sys.argv[2] if len(sys.argv) > 2 else 'us'
        max_pages = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        fetch_all_apps_reviews(country, max_pages)
        return

    # Single app mode
    app_id = sys.argv[1]
    country = sys.argv[2] if len(sys.argv) > 2 else 'us'
    page = int(sys.argv[3]) if len(sys.argv) > 3 else None

    if page:
        # Fetch single page
        reviews = fetch_reviews_page(app_id, country, page)
        filename = f"reviews_{app_id}_{country}_page{page}.json"
    else:
        # Fetch all pages
        reviews = fetch_all_reviews(app_id, country, max_pages=10)
        filename = f"reviews_{app_id}_{country}.json"

    if reviews:
        save_reviews(reviews, filename)

        # Summary statistics
        ratings = [r['rating'] for r in reviews if r.get('rating')]
        if ratings:
            avg_rating = sum(ratings) / len(ratings)
            print(f"\nSummary:")
            print(f"  Total reviews: {len(reviews)}")
            print(f"  Average rating: {avg_rating:.2f} stars")
            print(f"  Rating distribution: 5★={ratings.count(5)}, 4★={ratings.count(4)}, 3★={ratings.count(3)}, 2★={ratings.count(2)}, 1★={ratings.count(1)}")

        # Create unanswered reviews file (contains all reviews since we can't filter)
        unanswered_file = f"reviews_{app_id}_{country}_unanswered.json"
        unanswered = filter_unanswered(reviews)
        save_reviews(unanswered, unanswered_file)

        print(f"\nNote: RSS feeds don't show developer responses.")
        print(f"All reviews saved to both files. Check App Store Connect to identify unanswered ones.")
    else:
        print("No reviews found.")

if __name__ == '__main__':
    main()
