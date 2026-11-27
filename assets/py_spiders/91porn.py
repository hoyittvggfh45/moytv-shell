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
    ("top", "Top This Month"), ("ori", "91 Original"), ("hot", "Hot"),
    ("long", "10+ Mins"), ("longer", "20+ Mins"), ("tf", "Top Favorites"),
    ("rf", "Featured"), ("hd", "HD"), ("top_last", "Top Last Month"),
    ("md", "Most Discussed"), ("mf", "Most Favorited"),
]

CAT_SET = dict(CATS)


def _strip_tags(s):
    s = re.sub(r"<[^>]+>", " ", s or "")
    s = s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&quot;", '"')
    s = s.replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"\s+", " ", s).strip()


class Spider(BaseSpider):
    def getName(self):
        return "91Porn"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._base = "https://91porn.com"
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

    def _parse_cards(self, html):
        items = []
        seen = set()
        for m in re.finditer(r'<a href="[^"]*view_video\.php\?viewkey=([a-zA-Z0-9]{5,64})[^"]*"[^>]*>(.*?)</a>', html, re.S):
            vk = m.group(1)
            block = m.group(2)
            if vk in seen:
                continue
            img = re.search(r'<img[^>]+src="(https://[^"]+)"', block)
            cover = img.group(1) if img else ""
            pv = re.search(r'playvthumb_(\d+)', block)
            cv = re.search(r'/thumb/(\d+)\.', cover)
            if pv and cv and pv.group(1) != cv.group(1):
                continue
            t = re.search(r"<bdi>([^<]+)</bdi>", block)
            if not t:
                t = re.search(r'class="video-title[^"]*"[^>]*>([^<]+)', block)
            if not t and img:
                t = re.search(r'(?:title|alt)="([^"]+)"', img.group(0))
            dur = re.search(r'class="duration"[^>]*>([^<]+)<', block)
            seen.add(vk)
            items.append({
                "vod_id": vk,
                "vod_name": _strip_tags(t.group(1)) if t else "",
                "vod_pic": cover,
                "vod_remarks": (dur.group(1).strip() if dur else ""),
            })
        return items

    def _list_url(self, tid, pg):
        if tid == "top_last":
            q = {"category": "top", "m": "-1", "viewtype": "basic", "page": pg}
        else:
            q = {"category": tid, "viewtype": "basic", "page": pg}
        return self._base + "/v.php?" + urllib.parse.urlencode(q)

    def _page_result(self, html, pg):
        items = self._parse_cards(html)
        if not items:
            raise Exception("no video cards parsed")
        total = re.search(r"Videos\s+[\d\s\-]+of\s+([\d,]+)", html)
        if total:
            n = int(total.group(1).replace(",", ""))
            pagecount = (n + 23) // 24
        elif len(items) >= 24:
            pagecount = pg + 1
        else:
            pagecount = pg
        return {"list": items, "page": pg, "pagecount": pagecount, "limit": 24, "total": 999999}

    def homeContent(self, filter=False):
        cats = [{"type_id": tid, "type_name": name} for tid, name in CATS]
        result = {"class": cats, "filters": {}}
        result["list"] = self.homeVideoContent().get("list") or []
        return result

    def homeVideoContent(self):
        html = self._get(self._list_url("rf", 1), referer=self._base + "/")
        return {"list": self._parse_cards(html)}

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        pg = int(pg or 1)
        tid = str(tid or "rf")
        if tid not in CAT_SET:
            raise Exception("unknown category: " + tid)
        html = self._get(self._list_url(tid, pg), referer=self._base + "/")
        return self._page_result(html, pg)

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            vid = str(ids[0]) if ids else ""
        else:
            vid = str(ids)
        if not re.fullmatch(r"[a-zA-Z0-9]{5,64}", vid):
            raise Exception("bad video id")
        url = self._base + "/view_video.php?viewkey=" + vid
        html = self._get(url, referer=self._base + "/")
        vod = self._parse_detail(html, vid)
        return {"list": [vod]}

    def _parse_detail(self, html, vid):
        title = ""
        zone = re.search(r'id="videodetails".*?<h4[^>]*>(.*?)</h4>', html, re.S)
        if zone:
            title = _strip_tags(zone.group(1))
        if not title:
            t = re.search(r"<title>([^<]+)</title>", html)
            title = _strip_tags(t.group(1)) if t else ""
        poster = re.search(r'<video[^>]*poster="([^"]+)"', html)
        cover = poster.group(1) if poster else ""
        if not cover:
            dec = self._decode_player(html)
            if dec:
                pm = re.search(r"poster=['\"]([^'\"]+)['\"]", dec)
                if pm:
                    cover = pm.group(1)
        desc = ""
        for pat in (r'id="v_desc"[^>]*>(.*?)</div>', r'id="v_desc"[^>]*>(.*?)</p>',
                    r'class="video-description"[^>]*>(.*?)</div>'):
            dm = re.search(pat, html, re.S)
            if dm:
                desc = _strip_tags(dm.group(1))
                break
        rt = re.search(r"Runtime:\s*<span[^>]*>([^<]+)</span>", html)
        tags = []
        for tm in re.finditer(r'search_result\.php\?[^"]*search_id=([^"&]+)', html):
            w = urllib.parse.unquote(tm.group(1)).strip()
            if w and w not in tags:
                tags.append(w)
        return {
            "vod_id": vid,
            "vod_name": title,
            "vod_pic": cover,
            "vod_remarks": (rt.group(1).strip() if rt else ""),
            "vod_content": desc,
            "vod_tag": ",".join(tags),
            "vod_play_from": "91Porn",
            "vod_play_url": "正片$" + vid,
        }

    def searchContent(self, key, quick=False, pg="1"):
        pg = int(pg or 1)
        q = urllib.parse.urlencode({
            "viewtype": "basic", "page": pg,
            "search_type": "search_videos", "search_id": str(key or ""),
        })
        html = self._get(self._base + "/search_result.php?" + q, referer=self._base + "/")
        return self._page_result(html, pg)

    def _decode_player(self, html):
        m = re.search(r"strencode2\(\s*[\"']((?:%[0-9a-fA-F]{2})+)[\"']\s*\)", html)
        if not m:
            m = re.search(r"strencode\(\s*[\"']((?:%[0-9a-fA-F]{2})+)[\"']\s*\)", html)
        if not m:
            return ""
        return urllib.parse.unquote(m.group(1))

    def _extract_stream(self, html):
        dec = self._decode_player(html)
        for text in (dec, html):
            if not text:
                continue
            m = re.search(r"<source[^>]+src=['\"](https://[^'\"]+\.mp4[^'\"]*)['\"]", text)
            if m:
                return m.group(1)
            m = re.search(r"<source[^>]+src=['\"](https://[^'\"]+\.m3u8[^'\"]*)['\"]", text)
            if m:
                return m.group(1)
        return ""

    def _check_stream_url(self, url):
        p = urllib.parse.urlparse(url)
        if p.scheme != "https" or not p.hostname:
            raise Exception("stream url not https")
        if p.username or p.password:
            raise Exception("stream url has userinfo")
        if p.port not in (None, 443):
            raise Exception("stream url has non-standard port")
        if re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", p.hostname) or ":" in p.hostname:
            raise Exception("stream host is an IP literal")
        return url

    def playerContent(self, flag, id, vipFlags=None):
        vid = str(id or "")
        if not re.fullmatch(r"[a-zA-Z0-9]{5,64}", vid):
            raise Exception("bad video id")
        page_url = self._base + "/view_video.php?viewkey=" + vid
        html = self._get(page_url, referer=self._base + "/")
        if "Guests can watch" in html or "logged-in members only" in html:
            raise Exception("guest playback blocked by site: new videos need a member login, videos older than 3 days are free")
        url = self._extract_stream(html)
        if not url:
            raise Exception("no playable source found on detail page")
        url = self._check_stream_url(url)
        return {"parse": 0, "url": url, "header": {"User-Agent": self._ua, "Referer": page_url}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".m3u8" in u or ".mp4" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
