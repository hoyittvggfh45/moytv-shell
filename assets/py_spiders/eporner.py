import http.cookiejar
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    from base.spider import BaseSpider
except Exception:
    try:
        from spider import BaseSpider
    except Exception:
        class BaseSpider:
            pass


CATS = [
    ("4k-porn", "4K Porn"), ("hd-1080p", "HD 1080p"), ("60fps", "60 FPS"),
    ("vr-porn", "VR Porn"), ("japanese", "Japanese"), ("anal", "Anal"),
    ("pov-porn", "POV"), ("indian", "Indian"), ("milf", "MILF"),
    ("hentai", "Hentai"), ("bbw", "BBW"), ("pinay", "Pinay"),
    ("amateur", "Amateur"), ("asian", "Asian"), ("asmr", "ASMR"),
    ("bdsm", "BDSM"), ("big-ass", "Big Ass"), ("big-dick", "Big Dick"),
    ("big-tits", "Big Tits"), ("cosplay", "Cosplay"), ("creampie", "Creampie"),
    ("cuckold", "Cuckold"), ("ebony", "Ebony"), ("footjob", "Footjob"),
    ("group-sex", "Group Sex"), ("hardcore", "Hardcore"), ("homemade", "Homemade"),
    ("indonesia", "Indonesia"), ("interracial", "Interracial"), ("latina", "Latina"),
    ("massage", "Massage"), ("mature", "Mature"), ("orgy", "Orgy"),
    ("redhead", "Redhead"), ("stepmom", "Stepmom"), ("stepsister", "Stepsister"),
    ("threesome", "Threesome"), ("vintage", "Vintage"), ("gay", "Gay"),
    ("lesbians", "Lesbian"), ("shemale", "Trans"), ("ai", "AI"),
    ("bisexual", "Bisexual"), ("blonde", "Blonde"), ("blowjob", "Blowjob"),
    ("bondage", "Bondage"), ("brunette", "Brunette"), ("bukkake", "Bukkake"),
    ("casting", "Casting"), ("compilation", "Compilation"), ("cumshot", "Cumshot"),
    ("double-penetration", "Double Penetration"), ("fat", "Fat"), ("fetish", "Fetish"),
    ("fisting", "Fisting"), ("for-women", "For Women"), ("gloryhole", "Gloryhole"),
    ("handjob", "Handjob"), ("hd-sex", "HD Sex"), ("hotel", "Hotel"),
    ("hotwife", "Hotwife"), ("housewives", "Housewives"), ("hq-porn", "HQ Porn"),
    ("lingerie", "Lingerie"), ("masturbation", "Masturbation"), ("nurse", "Nurses"),
    ("office", "Office"), ("old-man", "Older Men"), ("outdoor", "Outdoor"),
    ("pawg", "PAWG"), ("petite", "Petite"), ("pornstar", "Pornstar"),
    ("pregnant", "Pregnant"), ("public", "Public"), ("small-tits", "Small Tits"),
    ("squirt", "Squirt"), ("striptease", "Striptease"), ("swingers", "Swinger"),
    ("toys", "Toys"), ("uncategorized", "Uncategorized"), ("uniform", "Uniform"),
    ("webcam", "Webcam"), ("sleep", "Sleep"), ("doctor", "Doctor"),
]

CAT_NAME = dict(CATS)


def _b36(n):
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    if n == 0:
        return "0"
    out = ""
    while n:
        out = digits[n % 36] + out
        n //= 36
    return out


def _hash_token(hexhash):
    return "".join(_b36(int(hexhash[i:i + 8], 16)) for i in range(0, 32, 8))


class Spider(BaseSpider):
    def getName(self):
        return "Eporner"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._base = "https://www.eporner.com"
        self._ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        self._jar = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self._jar))

    def destroy(self):
        pass

    def _get(self, url, referer=None, retries=3, timeout=30):
        last = None
        for attempt in range(retries):
            try:
                headers = {"User-Agent": self._ua, "Accept": "*/*", "Connection": "close"}
                if referer:
                    headers["Referer"] = referer
                req = urllib.request.Request(url, headers=headers, method="GET")
                with self._opener.open(req, timeout=timeout) as r:
                    return r.read().decode("utf-8", "replace")
            except Exception as e:
                last = e
                time.sleep(1 << attempt)
        raise last

    def _api(self, path):
        raw = self._get(self._base + path, referer=self._base + "/")
        return json.loads(raw)

    def _api_items(self, data):
        items = []
        for v in data.get("videos") or []:
            thumb = (v.get("default_thumb") or {}).get("src") or ""
            items.append({
                "vod_id": v.get("id") or "",
                "vod_name": v.get("title") or "",
                "vod_pic": thumb,
                "vod_remarks": v.get("length_min") or "",
            })
        return items

    def _api_search(self, query, pg, per_page=36):
        q = urllib.parse.urlencode({"query": query, "per_page": per_page, "page": pg, "thumbsize": "big", "format": "json"})
        return self._api("/api/v2/video/search/?" + q)

    def homeContent(self, filter=False):
        cats = [{"type_id": tid, "type_name": name} for tid, name in CATS]
        result = {"class": cats, "filters": {}}
        try:
            result["list"] = self.homeVideoContent().get("list") or []
        except Exception:
            result["list"] = []
        return result

    def homeVideoContent(self):
        data = self._api_search("", 1)
        return {"list": self._api_items(data)}

    def _parse_cards(self, html):
        items = []
        for block in re.split(r'<div class="mb ', html)[1:]:
            m = re.search(r'href="/video-([A-Za-z0-9]+)/[^"]*/"', block)
            if not m:
                continue
            t = re.search(r'class="mbtit"><a[^>]*>([^<]+)</a>', block)
            img = re.search(r'<img src="(https://[^"]+)"', block)
            dur = re.search(r'class="mbtim"[^>]*>([^<]+)<', block)
            items.append({
                "vod_id": m.group(1),
                "vod_name": (t.group(1).strip() if t else ""),
                "vod_pic": (img.group(1).replace("_240.jpg", "_360.jpg") if img else ""),
                "vod_remarks": (dur.group(1).strip() if dur else ""),
            })
        return items

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        pg = int(pg or 1)
        slug = str(tid or "")
        url = self._base + "/cat/" + slug + "/"
        if pg > 1:
            url += str(pg) + "/"
        items = []
        pagecount = pg
        try:
            html = ""
            for _ in range(3):
                html = self._get(url, referer=self._base + "/cats/")
                if "Age verification" not in html[:2000]:
                    break
                html = ""
            if html:
                items = self._parse_cards(html)
                nums = [int(n) for n in re.findall(r"href='/cat/" + re.escape(slug) + r"/(\d+)/'", html)]
                if nums:
                    pagecount = max(nums)
                elif items:
                    pagecount = pg + 1
        except Exception:
            items = []
        if not items:
            data = self._api_search(CAT_NAME.get(slug, slug), pg)
            items = self._api_items(data)
            try:
                pagecount = int(data.get("total_pages") or pg)
            except Exception:
                pagecount = pg
        return {"list": items, "page": pg, "pagecount": pagecount, "limit": 36, "total": 999999}

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            vid = str(ids[0]) if ids else ""
        else:
            vid = str(ids)
        data = self._api("/api/v2/video/id/?" + urllib.parse.urlencode({"id": vid, "thumbsize": "big", "format": "json"}))
        thumb = (data.get("default_thumb") or {}).get("src") or ""
        kw = data.get("keywords") or ""
        vod = {
            "vod_id": vid,
            "vod_name": data.get("title") or "",
            "vod_pic": thumb,
            "vod_remarks": data.get("length_min") or "",
            "vod_content": kw,
            "vod_tag": kw,
            "vod_play_from": "Eporner",
            "vod_play_url": "正片$" + vid,
        }
        return {"list": [vod]}

    def searchContent(self, key, quick=False, pg="1"):
        pg = int(pg or 1)
        data = self._api_search(str(key or ""), pg)
        items = self._api_items(data)
        try:
            pagecount = int(data.get("total_pages") or pg)
        except Exception:
            pagecount = pg
        return {"list": items, "page": pg, "pagecount": pagecount, "limit": 36, "total": 999999}

    def playerContent(self, flag, id, vipFlags=None):
        vid = str(id or "")
        data = self._api("/api/v2/video/id/?" + urllib.parse.urlencode({"id": vid, "format": "json"}))
        page_url = data.get("url") or (self._base + "/video-" + vid + "/")
        m = None
        for _ in range(3):
            html = self._get(page_url, referer=self._base + "/")
            m = re.search(r"EP\.video\.player\.hash = '([0-9a-f]{32})'", html)
            if m:
                break
        if not m:
            raise Exception("player hash not found")
        token = _hash_token(m.group(1))
        q = urllib.parse.urlencode({
            "hash": token, "domain": "www.eporner.com", "embed": 0,
            "playerWidth": 1280, "playerHeight": 720, "pixelRatio": 1,
            "supportedFormats": "hls,mp4,dash", "_": int(time.time() * 1000),
        })
        raw = self._get(self._base + "/xhr/video/" + vid + "?" + q, referer=page_url)
        info = json.loads(raw)
        if not info.get("available"):
            raise Exception("video not available: " + str(info.get("message") or info.get("code")))
        sources = info.get("sources") or {}
        url = ""
        hls = (sources.get("hls") or {}).get("auto") or {}
        if hls.get("src"):
            url = hls["src"]
        else:
            mp4 = sources.get("mp4") or {}
            best = None
            for label, s in mp4.items():
                if not isinstance(s, dict) or not s.get("src"):
                    continue
                if s.get("default"):
                    best = s["src"]
                    break
                num = re.search(r"(\d+)p", label)
                rank = int(num.group(1)) if num else 0
                if best is None or rank > best[0]:
                    best = (rank, s["src"])
            if isinstance(best, tuple):
                url = best[1]
            elif best:
                url = best
        if not url:
            raise Exception("no playable source")
        return {"parse": 0, "url": url, "header": {"User-Agent": self._ua, "Referer": self._base + "/"}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".m3u8" in u or ".mp4" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
