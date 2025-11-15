# Marketing Logic Scripts

This directory contains scripts and tools for managing App Store Connect data for marketing purposes.

## Requirements

All scripts require:
- Python 3.x
- PyJWT library
- cryptography library

## Setup

```bash
# Create virtual environment (recommended)
cd tmp  # or your working directory
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install PyJWT cryptography
```

## API Credentials

All scripts use credentials stored in `/Users/oleksandr/Projects/rootyapps/keys/`:
- Key ID: 55B6L3J65N
- Issuer ID: 057ddafb-cb0e-4410-9e0a-00e24f6e1688
- P8 Key: AuthKey_55B6L3J65N.p8.txt

JWT tokens generated are valid for 20 minutes.

---

## Scripts

### 1. fetch_all_apps.py

**Purpose**: Fetches all apps from App Store Connect API

**Usage**:
```bash
cd tmp  # or wherever you want to save output files
source venv/bin/activate
python3 ../marketing/logic/fetch_all_apps.py
```

**Output Files**:
- `all_apps_full.json` - Complete API response with all app details
- `all_apps_list.txt` - Simple pipe-delimited list: Name|ID|BundleID|SKU

**When to use**:
- Getting overview of all your apps
- Extracting app IDs for other scripts
- Checking app metadata and SKUs
- Portfolio analysis

---

### 2. fetch_analytics_reports.py

**Purpose**: Fetches analytics reports (sales, downloads, engagement data) for a specific app

**Usage**:
```bash
cd tmp
source venv/bin/activate

# Fetch analytics report requests for an app
python3 ../marketing/logic/fetch_analytics_reports.py <app_id>

# Fetch specific report request's available reports
python3 ../marketing/logic/fetch_analytics_reports.py <app_id> <report_request_id>
```

**Examples**:
```bash
# Get analytics for Golden Ratio Calculator Lite
python3 ../marketing/logic/fetch_analytics_reports.py 1570956847

# Get specific report request
python3 ../marketing/logic/fetch_analytics_reports.py 1570956847 4c57f118-3daf-4aba-927f-38f9656e5593
```

**Output Files**:
- `analytics_requests_<app_id>.json` - All analytics report requests
- `analytics_reports_<request_id>.json` - Available reports for a request

**Reports Available**:
- **COMMERCE**: Downloads, purchases, pre-orders
- **APP_USAGE**: Sessions, installations, deletions
- **APP_STORE_ENGAGEMENT**: Discovery, impressions, conversion
- **PERFORMANCE**: Install performance, networking
- **FRAMEWORK_USAGE**: Various framework usage metrics

**When to use**:
- Analyzing sales trends
- Understanding user behavior
- ASO performance analysis
- Download/revenue tracking
- Before/after comparison of marketing changes

**Note**: Analytics reports may need to be created first via App Store Connect UI or MCP tool `create_analytics_report_request`.

---

### 3. fetch_app_versions.py

**Purpose**: Fetches all app store versions (iOS, macOS, etc.) for a specific app

**Usage**:
```bash
cd tmp
source venv/bin/activate
python3 ../marketing/logic/fetch_app_versions.py <app_id>
```

**Example**:
```bash
# Get versions for Golden Ratio Tech Calculator
python3 ../marketing/logic/fetch_app_versions.py 1570841203
```

**Output Files**:
- `app_versions_<app_id>.json` - All versions with platform, state, release type

**Information Retrieved**:
- Version string (e.g., "1.0", "1.1")
- Platform (IOS, MAC_OS, TV_OS, VISION_OS)
- State (READY_FOR_SALE, PREPARE_FOR_SUBMISSION, IN_REVIEW, etc.)
- Release type (MANUAL, AFTER_APPROVAL, SCHEDULED)
- Version ID (needed for fetching localizations)

**When to use**:
- Checking version status across platforms
- Finding version IDs for localization fetching
- Audit of all published versions
- Understanding version history

---

### 4. fetch_app_localizations.py

**Purpose**: Fetches app store metadata (description, keywords, screenshots metadata) for specific version

**Usage**:
```bash
cd tmp
source venv/bin/activate

# Fetch localizations for latest version
python3 ../marketing/logic/fetch_app_localizations.py <app_id>

# Fetch localizations for specific version
python3 ../marketing/logic/fetch_app_localizations.py <app_id> <version_id>
```

**Examples**:
```bash
# Get latest localizations for Golden Ratio Tech Calculator
python3 ../marketing/logic/fetch_app_localizations.py 1570841203

# Get specific version localizations
python3 ../marketing/logic/fetch_app_localizations.py 1570841203 ef816b99-f4cc-49bc-a654-3ba745383a46
```

**Output Files**:
- `localizations_<app_id>_<version_id>.json` - Full localization data

**Information Retrieved**:
- Description (with character count)
- Keywords
- Marketing URL
- Support URL
- Promotional text
- What's New text
- Locale (en-US, ja, es, etc.)

**When to use**:
- ASO analysis (checking current keywords/description)
- Auditing multiple language versions
- Extracting text for rewriting
- Comparing descriptions across apps
- Before updating metadata

---

### 5. fetch_data.py (Comprehensive Fetcher) ⭐

**Purpose**: One-stop script to fetch ALL data for ALL apps automatically

**Usage**:
```bash
cd tmp
source venv/bin/activate
python3 ../marketing/logic/fetch_data.py
```

**What it does**:
1. Clears `tmp/marketing/` directory
2. Fetches all apps from App Store Connect
3. For each app, fetches:
   - App info
   - All versions
   - Localizations (latest version)
   - Analytics requests and reports
4. Saves everything to organized JSON files

**Output Files** (in `tmp/marketing/`):
- `apps.json` - All apps list
- `app_info_<app_id>.json` - Detailed app info
- `versions_<app_id>.json` - All versions
- `localizations_<app_id>_<version_id>.json` - Metadata & keywords
- `analytics_<app_id>.json` - Analytics requests
- `analytics_reports_<app_id>_<request_id>.json` - Available reports

**When to use**:
- Starting fresh analysis of entire portfolio
- Regular data snapshots (weekly/monthly)
- Before major ASO changes (backup)
- Comparing data over time

**Advantages**:
- Fully automated - no need to run individual scripts
- Consistent data structure
- Handles all apps in one run
- Built-in rate limiting to avoid API throttling

---

### 6. parse_data.py (Data Formatter) ⭐

**Purpose**: Parse fetched JSON data and output formatted analysis context for Claude

**Usage**:
```bash
cd tmp
source venv/bin/activate
python3 ../marketing/logic/parse_data.py
```

**What it does**:
1. Reads all JSON files from `tmp/marketing/`
2. Extracts key information (descriptions, keywords, versions, analytics)
3. Formats data in human-readable format
4. Outputs to stdout for Claude analysis
5. Shows portfolio-wide summary with issues

**Output includes**:
- Portfolio summary (total apps, platforms, states)
- Potential issues (short descriptions, missing keywords, no analytics)
- Per-app details:
  - Basic info (ID, bundle ID, SKU)
  - Versions (platform, state, release type)
  - Localizations (description length, keywords, URLs)
  - Analytics status

**When to use**:
- After running `fetch_data.py`
- Preparing data for Claude analysis
- Quick portfolio health check
- Identifying apps with ASO issues

**Advantages**:
- Filters huge JSON files to relevant data only
- Consistent formatting for AI analysis
- No MD files - direct output for context
- Identifies issues automatically

---

### 7. fetch_reviews.py (Customer Reviews via RSS) ⭐

**Purpose**: Fetch customer reviews from App Store using public RSS feeds

**Important**: Apple's App Store Connect API does NOT provide customer review endpoints. This script uses RSS feeds as the only programmatic way to access reviews.

**Usage**:
```bash
cd tmp
source venv/bin/activate

# Fetch all reviews for a specific app (US store)
python3 ../marketing/logic/fetch_reviews.py <app_id>

# Fetch reviews from specific country
python3 ../marketing/logic/fetch_reviews.py <app_id> <country_code>

# Fetch all apps' reviews
python3 ../marketing/logic/fetch_reviews.py --all [country_code]
```

**Examples**:
```bash
# Fetch US reviews for Golden Ratio Calculator Lite
python3 ../marketing/logic/fetch_reviews.py 1570956847

# Fetch UK reviews
python3 ../marketing/logic/fetch_reviews.py 1570956847 gb

# Fetch reviews for all apps from marketing/apps.json
python3 ../marketing/logic/fetch_reviews.py --all us
```

**Output Files**:
- `reviews_<app_id>_<country>.json` - All reviews with metadata
- `reviews_<app_id>_<country>_unanswered.json` - Same as above (RSS can't filter)

**Information Retrieved**:
- Review ID
- Title and content (text)
- Star rating (1-5)
- Author name
- App version reviewed
- Date/time posted
- Vote count (helpful votes)

**Country Codes** (common):
- `us` - United States
- `gb` - United Kingdom
- `ca` - Canada
- `au` - Australia
- `jp` - Japan
- `de` - Germany
- `fr` - France
- `es` - Spain
- `it` - Italy

**When to use**:
- Monitoring customer feedback
- Identifying common issues/complaints
- ASO research (what users say)
- Competitor analysis (if you know their app IDs)
- Response prioritization (check recent reviews)

**Limitations**:
- ⚠️ **RSS feeds do NOT show developer responses** - You cannot determine which reviews are actually answered via RSS
- Limited to 10 pages (~500 reviews max per fetch)
- Only public reviews (not filtered/hidden ones)
- Sorted by most recent or most helpful only
- No official API for responding (must use App Store Connect web/app)

**How to identify unanswered reviews**:
1. Use this script to fetch all reviews
2. Manually check App Store Connect web interface or mobile app
3. Cross-reference review IDs/content to see which lack responses

**Advantages**:
- Only programmatic way to access customer reviews
- No API credentials needed (public RSS)
- Works for any app (including competitors)
- Fast and reliable
- Get rating distribution and sentiment

---

## Common Workflows

### 🚀 Quick Start: Complete Portfolio Analysis

**Use the new comprehensive scripts:**

```bash
cd tmp
source venv/bin/activate

# Step 1: Fetch all data (metadata, versions, localizations, analytics)
python3 ../marketing/logic/fetch_data.py

# Step 2: Fetch all reviews for all apps
python3 ../marketing/logic/fetch_reviews.py --all us

# Step 3: Parse and analyze
python3 ../marketing/logic/parse_data.py > portfolio_analysis.txt

# Step 4: Review output or provide to Claude for analysis
```

This replaces the manual multi-script workflow and gives you a complete data snapshot in ~3-5 minutes.

---

## Common Workflows (Legacy/Individual Scripts)

### ASO Analysis Workflow

1. **Get all apps**:
   ```bash
   python3 ../marketing/logic/fetch_all_apps.py
   ```

2. **Pick app ID from output, fetch versions**:
   ```bash
   python3 ../marketing/logic/fetch_app_versions.py 1570956847
   ```

3. **Fetch current metadata**:
   ```bash
   python3 ../marketing/logic/fetch_app_localizations.py 1570956847
   ```

4. **Analyze analytics**:
   ```bash
   python3 ../marketing/logic/fetch_analytics_reports.py 1570956847
   ```

5. **Review all JSON files for insights**

### Multi-App Portfolio Analysis

```bash
cd tmp
source venv/bin/activate

# Fetch all apps
python3 ../marketing/logic/fetch_all_apps.py

# Extract app IDs from all_apps_list.txt
# For each app, run:
for app_id in 1570956847 1570841203 1631148042; do
    echo "Analyzing app $app_id..."
    python3 ../marketing/logic/fetch_app_localizations.py $app_id
    python3 ../marketing/logic/fetch_analytics_reports.py $app_id
done
```

### Before Updating App Metadata

```bash
# 1. Backup current metadata
python3 ../marketing/logic/fetch_app_localizations.py <app_id>

# 2. Review output JSON file
cat localizations_*.json | jq '.data[0].attributes'

# 3. Make changes via App Store Connect or MCP tools

# 4. Verify changes
python3 ../marketing/logic/fetch_app_localizations.py <app_id>
```

---

## Troubleshooting

### Authentication Errors
- Verify P8 file path is correct
- Check Key ID and Issuer ID match your App Store Connect API key
- Ensure API key has necessary permissions in App Store Connect

### No Data Returned
- Check app ID is correct (get from `fetch_all_apps.py`)
- For analytics: Reports may need to be created first
- For versions: App may not have any published versions yet

### JSON Parsing Errors
- API might be down or rate-limited
- Token might have expired (re-run script)
- Check internet connection

---

## Output Files Location

All scripts save output files to the current working directory (typically `tmp/`).

**Keep these files for**:
- Historical records of metadata
- Before/after comparisons
- Input for analysis tools
- Backup before making changes

**Files are NOT deleted automatically** - you can reuse them across sessions.

---

## Next Steps

After gathering data with these scripts:
1. Review JSON files for insights
2. Use data for ASO analysis reports
3. Compare competitors using similar tools
4. Make informed decisions about metadata updates
5. Track changes over time by running scripts periodically

---

## Related Documentation

- Main analysis: `../golden_ratio_lite_analysis.md`
- Tech app analysis: `../golden_ratio_tech_analysis.md`
- Strategic positioning: `../golden_ratio_apps_strategy.md`
- App list: `../all_apps.md`
