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


FEEDS = [("trending", "Trending"), ("latest", "Latest")]
BLOCKED_NICHE = re.compile(r"teen|school|loli|shota|underage|jailbait", re.I)
PER_PAGE = 40


class Spider(BaseSpider):
    def getName(self):
        return "RedGifs"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._api = "https://api.redgifs.com"
        self._ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        self._jar = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self._jar))
        self._token = ""
        self._niches = None

    def destroy(self):
        pass

    def _raw_get(self, url, token=None, retries=3, timeout=30):
        last = None
        for attempt in range(retries):
            try:
                headers = {"User-Agent": self._ua, "Accept": "application/json", "Connection": "close"}
                if token:
                    headers["Authorization"] = "Bearer " + token
                req = urllib.request.Request(url, headers=headers, method="GET")
                with self._opener.open(req, timeout=timeout) as r:
                    return r.status, r.read().decode("utf-8", "replace")
            except urllib.error.HTTPError as e:
                try:
                    return e.code, e.read().decode("utf-8", "replace")
                except Exception:
                    return e.code, ""
            except Exception as e:
                last = e
                time.sleep(1 << attempt)
        raise last

    def _fetch_token(self):
        st, body = self._raw_get(self._api + "/v2/auth/temporary")
        if st != 200:
            raise Exception("token request failed: HTTP " + str(st))
        self._token = json.loads(body).get("token") or ""
        if not self._token:
            raise Exception("token missing in response")
        return self._token

    def _api_get(self, path):
        if not self._token:
            self._fetch_token()
        st, body = self._raw_get(self._api + path, token=self._token)
        if st == 401:
            self._fetch_token()
            st, body = self._raw_get(self._api + path, token=self._token)
        if st != 200:
            raise Exception("api HTTP " + str(st) + " @ " + path + " " + body[:120])
        return json.loads(body)

    def _load_niches(self):
        if self._niches is not None:
            return self._niches
        out = []
        page = 1
        pages = 1
        while page <= pages:
            data = self._api_get("/v2/niches?page=" + str(page) + "&count=100")
            pages = int(data.get("pages") or 1)
            for n in data.get("niches") or []:
                nid = n.get("id") or ""
                name = n.get("name") or ""
                if not nid or not name:
                    continue
                if BLOCKED_NICHE.search(nid) or BLOCKED_NICHE.search(name):
                    continue
                out.append(("niche:" + nid, name))
            page += 1
        self._niches = out
        return out

    def _fmt_dur(self, sec):
        try:
            s = int(float(sec))
        except Exception:
            return ""
        return str(s // 60) + ":" + str(s % 60).zfill(2)

    def _item(self, g):
        urls = g.get("urls") or {}
        tags = g.get("tags") or []
        name = (g.get("description") or "").strip()
        if not name and tags:
            name = ", ".join(tags[:3])
        if not name:
            name = (g.get("userName") or "") + " " + (g.get("id") or "")
        return {
            "vod_id": g.get("id") or "",
            "vod_name": name.strip(),
            "vod_pic": urls.get("poster") or urls.get("thumbnail") or "",
            "vod_remarks": self._fmt_dur(g.get("duration")),
        }

    def _list_result(self, data, pg):
        items = [self._item(g) for g in data.get("gifs") or [] if g.get("id")]
        pages = int(data.get("pages") or pg)
        return {"list": items, "page": pg, "pagecount": pages, "limit": PER_PAGE, "total": int(data.get("total") or 999999)}

    def homeContent(self, filter=False):
        cats = [{"type_id": tid, "type_name": name} for tid, name in FEEDS]
        try:
            cats += [{"type_id": tid, "type_name": name} for tid, name in self._load_niches()]
        except Exception:
            pass
        result = {"class": cats, "filters": {}}
        try:
            result["list"] = self.homeVideoContent().get("list") or []
        except Exception:
            result["list"] = []
        return result

    def homeVideoContent(self):
        data = self._api_get("/v2/gifs/search?search_text=&order=trending&page=1&count=" + str(PER_PAGE))
        return {"list": [self._item(g) for g in data.get("gifs") or [] if g.get("id")]}

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        pg = int(pg or 1)
        tid = str(tid or "")
        if tid in ("trending", "latest"):
            q = urllib.parse.urlencode({"search_text": "", "order": tid, "page": pg, "count": PER_PAGE})
            data = self._api_get("/v2/gifs/search?" + q)
            return self._list_result(data, pg)
        if tid.startswith("niche:"):
            slug = tid[len("niche:"):]
            if not re.fullmatch(r"[a-z0-9\-]+", slug):
                raise Exception("bad niche id")
            q = urllib.parse.urlencode({"sort": "trending", "page": pg, "count": PER_PAGE})
            data = self._api_get("/v2/niches/" + slug + "/gifs?" + q)
            return self._list_result(data, pg)
        raise Exception("unknown category: " + tid)

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            vid = str(ids[0]) if ids else ""
        else:
            vid = str(ids)
        if not re.fullmatch(r"[a-z0-9]+", vid):
            raise Exception("bad video id")
        data = self._api_get("/v2/gifs/" + vid)
        g = data.get("gif") or {}
        if not g:
            raise Exception("gif not found")
        item = self._item(g)
        tags = g.get("tags") or []
        vod = {
            "vod_id": vid,
            "vod_name": item["vod_name"],
            "vod_pic": item["vod_pic"],
            "vod_remarks": item["vod_remarks"],
            "vod_actor": g.get("userName") or "",
            "vod_content": (g.get("description") or "").strip(),
            "vod_tag": ",".join(tags),
            "vod_play_from": "RedGifs",
            "vod_play_url": "正片$" + vid,
        }
        return {"list": [vod]}

    def searchContent(self, key, quick=False, pg="1"):
        pg = int(pg or 1)
        q = urllib.parse.urlencode({"search_text": "", "tags": str(key or ""), "order": "trending", "page": pg, "count": PER_PAGE})
        data = self._api_get("/v2/gifs/search?" + q)
        return self._list_result(data, pg)

    def playerContent(self, flag, id, vipFlags=None):
        vid = str(id or "")
        if not re.fullmatch(r"[a-z0-9]+", vid):
            raise Exception("bad video id")
        data = self._api_get("/v2/gifs/" + vid)
        g = data.get("gif") or {}
        urls = g.get("urls") or {}
        url = urls.get("hd") or urls.get("sd") or ""
        if not url.startswith("https://"):
            raise Exception("no playable source")
        return {"parse": 0, "url": url, "header": {"User-Agent": self._ua, "Referer": "https://www.redgifs.com/"}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".m3u8" in u or ".mp4" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
