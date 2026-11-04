#!/usr/bin/env python3
"""Builds Menzen's app catalog: which App Store apps are games, music or video
apps, and the link to each one's App Store icon (its default icon, never an
alternate), published on the catalog branch for the tweak to read as
games.json, audio.json and video.json, so each only changes with its own apps.

    charts   adds the apps on the App Store's top charts and refreshes every app
             already in the catalog, so icon links follow icon changes
    request  adds the one app an issue asks for
    reply    words the issue comment for a request's result
    merge    applies what charts or request staged onto a catalog checkout

charts and request only stage changes, so merge can be retried on a fresh
checkout when another run pushed first. Standard library only; everything
comes from Apple, never from the issue beyond an app id.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CATALOG_VERSION = 1
# One file per kind; an entry's kind is the file it's in.
CATALOG_FILES = {"game": "games.json", "audio": "audio.json", "video": "video.json"}

GAME_GENRES = {6014} | set(range(7001, 7020))
AUDIO_GENRES = {6011}  # Music
VIDEO_GENRES = {6016, 6008}  # Entertainment, Photo & Video
# Games' subgenres each have their own charts, so they're listed one by one.
CHART_GENRES = sorted(GAME_GENRES | AUDIO_GENRES | VIDEO_GENRES)
CHARTS = ["topfreeapplications", "topgrossingapplications", "toppaidapplications"]
DEFAULT_COUNTRIES = ["us", "gb", "ca", "au", "de", "fr", "jp", "kr", "br", "mx", "in"]
# Apps Menzen supports that the charts miss, by App Store id: where they're
# looked up and their kind. Apple's own apps come with iOS and never chart, and
# podcast apps are listed under News (Apple Podcasts under Entertainment).
SUPPORTED_APPS = {
	"1108187390": ("us", "audio"),  # Apple Music
	"1174078549": ("us", "video"),  # Apple TV
	"525463029": ("us", "audio"),  # Apple Podcasts
	"1080840241": ("us", "audio"),  # Castro
	"888422857": ("us", "audio"),  # Overcast
	"414834813": ("us", "audio"),  # Pocket Casts
}

# Apple asks for about 20 lookups a minute, and the chart feeds throttle too.
LOOKUP_DELAY = 3.2
CHART_DELAY = 1.0
LOOKUP_BATCH = 100

BUNDLE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)+$")
APP_STORE_LINK = re.compile(r"https?://(?:apps|itunes)\.apple\.com/(?:([a-z]{2})/)?(?:app/)?(?:[^/\s]+/)?id(\d{5,12})", re.I)
ARTWORK_SIZE = re.compile(r"/\d+x\d+bb\.(?:jpg|png|webp)$")
# The tweak only accepts icon links on Apple's artwork servers.
ICON_HOST = re.compile(r"^https://is\d+-ssl\.mzstatic\.com/image/thumb/")
USER_AGENT = "MenzenCatalog/1 (+https://github.com/waruhachi/Menzen)"

_last_lookup = 0.0


def log(message):
	print(message, file=sys.stderr, flush=True)


def fetch(url, attempts=4, method="GET"):
	"""The body of url, retrying throttling and server errors; None for 404."""
	for attempt in range(attempts):
		request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT}, method=method)
		try:
			with urllib.request.urlopen(request, timeout=30) as response:
				return response.read()
		except urllib.error.HTTPError as error:
			if error.code == 404:
				return None
			if error.code not in (403, 429) and error.code < 500:
				raise
			wait = 30 * (attempt + 1)
		except (urllib.error.URLError, TimeoutError):
			wait = 5 * (attempt + 1)
		if attempt + 1 < attempts:
			log(f"  retrying in {wait}s: {url}")
			time.sleep(wait)
	raise RuntimeError(f"gave up on {url}")


def fetch_json(url):
	body = fetch(url)
	return json.loads(body) if body else None


def lookup(country, **query):
	"""App records from Apple's lookup API, spaced out to stay under its limit."""
	global _last_lookup
	wait = _last_lookup + LOOKUP_DELAY - time.monotonic()
	if wait > 0:
		time.sleep(wait)
	_last_lookup = time.monotonic()
	query.update(country=country, entity="software")
	data = fetch_json("https://itunes.apple.com/lookup?" + urllib.parse.urlencode(query)) or {}
	return [r for r in data.get("results", []) if r.get("kind") == "software" and r.get("bundleId")]


def kind_of(record):
	"""game, audio or video: its kind in SUPPORTED_APPS, else by the app's
	primary category, else None. Other categories don't count: Discord lists
	Games as one, and isn't a game."""
	supported = SUPPORTED_APPS.get(str(record.get("trackId")))
	if supported:
		return supported[1]
	primary = int(record.get("primaryGenreId") or 0)
	if primary in GAME_GENRES:
		return "game"
	if primary in AUDIO_GENRES:
		return "audio"
	if primary in VIDEO_GENRES:
		return "video"
	return None


def icon_url(record):
	"""The 512 px JPEG of the app's default icon, the size Discord wants."""
	artwork = record.get("artworkUrl512") or record.get("artworkUrl100") or ""
	if not ICON_HOST.match(artwork) or not ARTWORK_SIZE.search(artwork):
		return None
	return ARTWORK_SIZE.sub("/512x512bb.jpg", artwork)


def link_works(url):
	try:
		return fetch(url, attempts=2, method="HEAD") is not None
	except Exception:
		return False


# MARK: - Catalog files


def load_catalog(folder):
	"""Every app in a catalog checkout, each entry with its kind."""
	apps = {}
	for kind, name in CATALOG_FILES.items():
		try:
			with open(os.path.join(folder, name)) as file:
				entries = json.load(file).get("apps", {})
		except FileNotFoundError:
			continue
		for bundle_id, entry in entries.items():
			apps[bundle_id] = dict(entry, kind=kind)
	if not apps:
		# The single file the catalog started as, carried over once.
		try:
			with open(os.path.join(folder, "apps.json")) as file:
				apps = json.load(file).get("apps", {})
		except FileNotFoundError:
			pass
	return apps


def write_catalog(folder, apps):
	for kind, name in CATALOG_FILES.items():
		entries = {bundle_id: {k: v for k, v in entry.items() if k != "kind"} for bundle_id, entry in apps.items() if entry["kind"] == kind}
		# One app per line, sorted, so each commit's diff shows just what
		# changed. The tweak relies on it too: it reads only the lines of the
		# apps installed (Daemon/MZApps/MZAppCatalog.m).
		lines = [f"\t{json.dumps(bundle_id)}: {json.dumps(entries[bundle_id], sort_keys=True, ensure_ascii=False)}" for bundle_id in sorted(entries)]
		with open(os.path.join(folder, name), "w") as file:
			file.write('{\n"version": %d,\n"apps": {\n%s\n}\n}\n' % (CATALOG_VERSION, ",\n".join(lines)))
	legacy = os.path.join(folder, "apps.json")
	if os.path.exists(legacy):
		os.remove(legacy)


def entry_for(record, country):
	"""record's catalog entry, or None when it has no usable bundle id or icon."""
	bundle_id = record["bundleId"]
	kind = kind_of(record)
	url = icon_url(record)
	if not kind or not url or not BUNDLE_ID.match(bundle_id):
		return None
	return {
		"appStoreId": int(record["trackId"]),
		"country": country,
		"icon": url,
		"kind": kind,
		"name": record.get("trackName", "").strip(),
	}


def write_stage(out, apps, remove=()):
	"""Stages new or changed entries and the bundle ids to drop."""
	os.makedirs(out, exist_ok=True)
	with open(os.path.join(out, "stage.json"), "w") as file:
		json.dump({"apps": apps, "remove": sorted(remove)}, file, indent="\t", sort_keys=True, ensure_ascii=False)


# MARK: - charts


def chart_ids(country, chart, genre):
	data = fetch_json(f"https://itunes.apple.com/{country}/rss/{chart}/limit=100/genre={genre}/json")
	entries = ((data or {}).get("feed") or {}).get("entry") or []
	if isinstance(entries, dict):
		entries = [entries]
	return [e["id"]["attributes"]["im:id"] for e in entries if e.get("id", {}).get("attributes", {}).get("im:id", "").isdigit()]


def run_charts(args):
	existing = load_catalog(args.catalog)
	countries = args.countries or DEFAULT_COUNTRIES
	genres = args.genres or CHART_GENRES

	# Every app already in the catalog is looked up again, where it was found.
	wanted = {str(app["appStoreId"]): app.get("country", "us") for app in existing.values()}
	failed = 0
	for country in countries:
		for genre in genres:
			for chart in CHARTS:
				try:
					for app_id in chart_ids(country, chart, genre):
						wanted.setdefault(app_id, country)
				except Exception as error:
					# One throttled feed shouldn't cost the whole run.
					failed += 1
					log(f"  skipped {country} {chart} {genre}: {error}")
				time.sleep(CHART_DELAY)
		log(f"{country}: {len(wanted)} apps so far")
	for app_id, (country, _) in SUPPORTED_APPS.items():
		wanted.setdefault(app_id, country)
	log(f"{len(wanted)} apps to look up ({len(existing)} already in the catalog, {failed} feeds skipped)")

	by_country = {}
	for app_id, country in wanted.items():
		by_country.setdefault(country, []).append(app_id)
	staged, seen = {}, {}
	for country, ids in by_country.items():
		for start in range(0, len(ids), LOOKUP_BATCH):
			for record in lookup(country, id=",".join(ids[start : start + LOOKUP_BATCH])):
				seen[record["bundleId"]] = record
				entry = entry_for(record, country)
				if entry and existing.get(record["bundleId"]) != entry:
					staged[record["bundleId"]] = entry

	# No longer a game, music or video app.
	remove = [bundle_id for bundle_id in existing if bundle_id in seen and bundle_id not in staged and not kind_of(seen[bundle_id])]
	# Gone from the App Store (or its country): kept while its icon link works.
	remove += [bundle_id for bundle_id, app in existing.items() if bundle_id not in seen and not link_works(app["icon"])]
	write_stage(args.out, staged, remove)
	log(f"staged {len(staged)} new or changed apps, {len(remove)} to remove")


# MARK: - request


def requested_app(body):
	"""(country, App Store id) or (None, bundle id) from an issue body."""
	link = APP_STORE_LINK.search(body)
	if link:
		return (link.group(1) or "").lower() or None, link.group(2)
	# An issue form puts each answer under its "### Label" heading.
	for line in body.splitlines():
		value = line.strip().strip("`").strip()
		if value and not value.startswith("#") and BUNDLE_ID.match(value):
			return None, value
	return None, None


def run_request(args):
	body = os.environ.get(args.body_env, "")
	country, app = requested_app(body)
	result = {"status": "invalid", "bundleId": None}

	if app:
		countries = ([country] if country else []) + [c for c in DEFAULT_COUNTRIES if c != country]
		key = "id" if app.isdigit() else "bundleId"
		record = None
		for candidate in countries:
			records = lookup(candidate, **{key: app})
			if records:
				record = records[0]
				break
		if not record:
			result["status"] = "not-found"
		else:
			result["bundleId"] = record["bundleId"]
			result["name"] = record.get("trackName", "").strip()
			result["link"] = record.get("trackViewUrl", "").split("?")[0]
			kind = kind_of(record)
			existing = load_catalog(args.catalog)
			if not kind:
				result["status"] = "unsupported"
				result["genre"] = record.get("primaryGenreName", "")
			elif record["bundleId"] in existing:
				result["status"] = "exists"
			else:
				entry = entry_for(record, candidate)
				if entry:
					write_stage(args.out, {record["bundleId"]: entry})
					result.update(status="added", kind=kind)
				else:
					result["status"] = "no-icon"

	with open(args.result, "w") as file:
		json.dump(result, file)
	log(f"request: {result['status']} {result.get('bundleId') or ''}")


def run_reply(args):
	"""The comment for a request's result, and how to close the issue."""
	with open(args.result) as file:
		result = json.load(file)
	name = result.get("name") or result.get("bundleId")
	app = f"[{name}]({result['link']})" if result.get("link") else f"**{name}**"
	kinds = {"game": "game", "audio": "music app", "video": "video app"}
	replies = {
		"added": (f"Added {app} as a {kinds.get(result.get('kind'), 'app')}. Menzen picks it up the next time it refreshes its app list.", "completed"),
		"exists": (f"{app} is already in Menzen's app list.", "completed"),
		"unsupported": (f"{app} is listed under {result.get('genre') or 'a category'} on the App Store. Menzen's list only takes games, music apps and video apps.", "not planned"),
		"not-found": ("I couldn't find that app on the App Store. Paste its App Store link (Share → Copy Link on its App Store page) or its bundle ID, then reopen this issue.", "not planned"),
		"no-icon": (f"I found {app} but couldn't get its icon from the App Store. A maintainer will take a look.", None),
		"invalid": ("I couldn't find an App Store link or bundle ID in this issue. Edit it to add one, then reopen it.", "not planned"),
	}
	message, reason = replies[result["status"]]
	with open(args.comment, "w") as file:
		file.write(message + "\n")
	print(reason or "")


# MARK: - merge


def run_merge(args):
	with open(os.path.join(args.stage, "stage.json")) as file:
		staged = json.load(file)
	apps = load_catalog(args.catalog)
	for bundle_id, entry in staged["apps"].items():
		if BUNDLE_ID.match(bundle_id) and ICON_HOST.match(entry.get("icon", "")):
			apps[bundle_id] = entry
	for bundle_id in staged["remove"]:
		apps.pop(bundle_id, None)
	write_catalog(args.catalog, apps)
	log(f"merged {len(staged['apps'])} changes and {len(staged['remove'])} removals, {len(apps)} in the catalog")


def main():
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	commands = parser.add_subparsers(dest="command", required=True)

	charts = commands.add_parser("charts")
	charts.add_argument("--catalog", required=True, help="folder with the current catalog files")
	charts.add_argument("--out", required=True, help="staging folder")
	charts.add_argument("--countries", type=lambda s: [c for c in re.split(r"[\s,]+", s.lower()) if re.fullmatch(r"[a-z]{2}", c)], default=None)
	charts.add_argument("--genres", type=lambda s: [int(g) for g in re.split(r"[\s,]+", s) if g.isdigit()], default=None)
	charts.set_defaults(run=run_charts)

	request = commands.add_parser("request")
	request.add_argument("--catalog", required=True, help="folder with the current catalog files")
	request.add_argument("--out", required=True)
	request.add_argument("--body-env", required=True, help="environment variable holding the issue body")
	request.add_argument("--result", required=True)
	request.set_defaults(run=run_request)

	reply = commands.add_parser("reply")
	reply.add_argument("--result", required=True)
	reply.add_argument("--comment", required=True)
	reply.set_defaults(run=run_reply)

	merge = commands.add_parser("merge")
	merge.add_argument("--stage", required=True)
	merge.add_argument("--catalog", required=True, help="catalog branch checkout")
	merge.set_defaults(run=run_merge)

	args = parser.parse_args()
	args.run(args)


if __name__ == "__main__":
	main()
