import html as htmlmod
import http.cookiejar
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
    ("tiktok-nudes", "Nudes"), ("tiktok-porn", "TikTok"), ("tiktok-boobs", "Boobs"),
    ("instagram-porn", "Instagram"), ("tiktok-sex", "Sex"), ("nsfw-tiktok", "NSFW"),
    ("tiktok-xxx", "XXX"), ("tiktok-ass", "Ass"), ("tiktok-pussy", "Pussy"),
    ("tiktok-live", "Live"), ("sexy-tiktok", "Sexy"), ("tiktok-thots", "Thots"),
]

CAT_SET = dict(CATS)


class Spider(BaseSpider):
    def getName(self):
        return "Fyptt"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._base = "https://fyptt.to"
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

    def _clean(self, s):
        s = re.sub(r"<[^>]+>", " ", s or "")
        s = htmlmod.unescape(s)
        return re.sub(r"\s+", " ", s).strip()

    def _parse_cards(self, page):
        items = []
        seen = set()
        for block in re.split(r'class="[^"]*fl-post-grid-post', page)[1:]:
            m = re.search(r'href="(https://fyptt\.to/(\d+)/([^"/]+)/)"', block)
            if not m:
                continue
            vid = m.group(2) + "/" + m.group(3)
            if vid in seen:
                continue
            seen.add(vid)
            img = re.search(r'<img[^>]+src="(https://[^"]+\.webp)"', block)
            t = re.search(r'class="fl-post-grid-title"[^>]*>\s*<a[^>]*>([\s\S]*?)</a>', block)
            if not t:
                t = re.search(r'<img[^>]+title="([^"]+)"', block)
            items.append({
                "vod_id": vid,
                "vod_name": self._clean(t.group(1)) if t else "",
                "vod_pic": img.group(1) if img else "",
                "vod_remarks": "",
            })
        return items

    def _page_result(self, page, pg):
        items = self._parse_cards(page)
        has_next = ("/page/" + str(pg + 1) + "/") in page or ("/page/" + str(pg + 1) + "?") in page
        pagecount = pg + 1 if has_next else pg
        return {"list": items, "page": pg, "pagecount": pagecount, "limit": 24, "total": 999999}

    def homeContent(self, filter=False):
        cats = [{"type_id": tid, "type_name": name} for tid, name in CATS]
        result = {"class": cats, "filters": {}}
        try:
            result["list"] = self.homeVideoContent().get("list") or []
        except Exception:
            result["list"] = []
        return result

    def homeVideoContent(self):
        page = self._get(self._base + "/", referer=self._base + "/")
        return {"list": self._parse_cards(page)}

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        pg = int(pg or 1)
        slug = str(tid or "")
        if slug not in CAT_SET:
            raise Exception("unknown category: " + slug)
        url = self._base + "/" + slug + "/"
        if pg > 1:
            url += "page/" + str(pg) + "/"
        page = self._get(url, referer=self._base + "/")
        return self._page_result(page, pg)

    def _post_url(self, vid):
        vid = str(vid or "").strip("/")
        if not re.fullmatch(r"\d+/[a-z0-9\-]+", vid):
            raise Exception("bad video id")
        return self._base + "/" + vid + "/"

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            vid = str(ids[0]) if ids else ""
        else:
            vid = str(ids)
        url = self._post_url(vid)
        page = self._get(url, referer=self._base + "/")
        t = re.search(r"<h1[^>]*>([\s\S]*?)</h1>", page)
        title = self._clean(t.group(1)) if t else ""
        if not title:
            raise Exception("detail title missing")
        cover = ""
        m = re.search(r'property="og:image" content="([^"]+)"', page)
        if m:
            cover = m.group(1)
        desc = ""
        m = re.search(r'name="description" content="([^"]*)"', page)
        if m:
            desc = htmlmod.unescape(m.group(1)).strip()
        tags = []
        for tm in re.finditer(r'href="https://fyptt\.to/tag/([^"/]+)/"', page):
            w = urllib.parse.unquote(tm.group(1)).replace("-", " ")
            if w and w not in tags:
                tags.append(w)
        vod = {
            "vod_id": vid,
            "vod_name": title,
            "vod_pic": cover,
            "vod_content": desc,
            "vod_tag": ",".join(tags),
            "vod_play_from": "Fyptt",
            "vod_play_url": "正片$" + vid,
        }
        return {"list": [vod]}

    def searchContent(self, key, quick=False, pg="1"):
        pg = int(pg or 1)
        q = urllib.parse.quote_plus(str(key or ""))
        if pg > 1:
            url = self._base + "/page/" + str(pg) + "/?s=" + q
        else:
            url = self._base + "/?s=" + q
        page = self._get(url, referer=self._base + "/")
        return self._page_result(page, pg)

    def playerContent(self, flag, id, vipFlags=None):
        url = self._post_url(id)
        page = self._get(url, referer=self._base + "/")
        m = re.search(r'<iframe[^>]+src="([^"]*fypttstr\.php\?[^"]+)"', page)
        if not m:
            raise Exception("player iframe not found")
        frame_url = htmlmod.unescape(m.group(1))
        frame = self._get(frame_url, referer=url)
        m = re.search(r'<source[^>]+src="([^"]+)"', frame)
        if not m:
            raise Exception("stream source not found")
        stream = htmlmod.unescape(m.group(1))
        if not stream.startswith("https://"):
            raise Exception("stream url not https")
        return {"parse": 0, "url": stream, "header": {"User-Agent": self._ua, "Referer": url}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".m3u8" in u or ".mp4" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
