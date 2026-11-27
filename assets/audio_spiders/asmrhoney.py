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
    ("audio", "音频"),
    ("asmr", "ASMR视频"),
    ("sensual-asmr", "Sensual ASMR"),
    ("ear-licking-asmr", "Ear Licking ASMR"),
    ("adult-asmr", "Adult ASMR"),
    ("creators", "创作者"),
]


def _clean(text):
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = text.replace("&amp;", "&").replace("&#39;", "'").replace("&quot;", '"').replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"\s+", " ", text).strip()


def _iso_dur(iso):
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", str(iso or ""))
    if not m:
        return ""
    h, mi, s = (int(x) if x else 0 for x in m.groups())
    if h:
        return "%d:%02d:%02d" % (h, mi, s)
    return "%d:%02d" % (mi, s)


class Spider(BaseSpider):
    def getName(self):
        return "ASMRHoney"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._base = "https://asmrhoney.com"
        self._ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        self._cache = {}

    def destroy(self):
        pass

    def _get(self, url, retries=3, timeout=40):
        if url in self._cache:
            return self._cache[url]
        last = None
        for attempt in range(retries):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": self._ua, "Accept": "*/*", "Connection": "close"}, method="GET")
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    text = r.read().decode("utf-8", "replace")
                self._cache[url] = text
                return text
            except Exception as e:
                last = e
                time.sleep(1 << attempt)
        raise last

    def _cards(self, html):
        items = []
        seen = set()
        for m in re.finditer(r'<a[^>]+href="(/(?:audio/album|clip)/[^"/]+/)"[^>]*>(.*?)</a>', html, re.S):
            path, block = m.group(1), m.group(2)
            slug = path.rstrip("/").rsplit("/", 1)[-1]
            kind = "album" if path.startswith("/audio/album/") else "clip"
            key = kind + ":" + slug
            if key in seen:
                continue
            seen.add(key)
            title_m = re.search(r"<h3[^>]*>(.*?)</h3>", block, re.S)
            title = _clean(title_m.group(1)) if title_m else slug
            pic = ""
            for img in re.findall(r'<img[^>]+src="([^"]+)"', block):
                if "creator-avatars" in img or "creator-covers" in img:
                    continue
                pic = img
                break
            if not pic:
                if kind == "album":
                    pic = "https://cdn.asmrhoney.com/audio-albums/" + slug + "/cover.jpg"
                else:
                    pic = "https://cdn.asmrhoney.com/clips/" + slug + "/cover.jpg"
            creator = ""
            cm = re.search(r'class="creator-name"[^>]*>([^<]+)<', block)
            if cm:
                creator = _clean(cm.group(1))
            else:
                pm = re.search(r"<p>([^<]+)</p>", block)
                if pm:
                    creator = _clean(pm.group(1))
            remarks = creator
            dm = re.search(r"(\d+\s*轨|tracks?)", block)
            items.append({
                "vod_id": key,
                "vod_name": title,
                "vod_pic": pic,
                "vod_remarks": remarks,
            })
        return items

    def _section_items(self, tid):
        html = self._get(self._base + "/" + tid + "/")
        return self._cards(html)

    def homeContent(self, filter=False):
        cats = [{"type_id": tid, "type_name": name} for tid, name in CATS]
        result = {"class": cats, "filters": {}}
        try:
            result["list"] = self.homeVideoContent().get("list") or []
        except Exception:
            result["list"] = []
        return result

    def homeVideoContent(self):
        try:
            return {"list": self._section_items("asmr")[:24]}
        except Exception:
            return {"list": []}

    def _creator_items(self):
        html = self._get(self._base + "/creators/")
        items = []
        seen = set()
        for m in re.finditer(r'<a[^>]+href="/creator/([^"/]+)/[^"]*"[^>]*>(.*?)</a>', html, re.S):
            slug, block = m.group(1), m.group(2)
            if slug in seen:
                continue
            seen.add(slug)
            nm = re.search(r"<h[23][^>]*>(.*?)</h[23]>", block, re.S)
            name = _clean(nm.group(1)) if nm else slug
            pic = ""
            for img in re.findall(r'<img[^>]+src="([^"]+)"', block):
                pic = img
                break
            items.append({
                "vod_id": "creator:" + slug,
                "vod_name": name,
                "vod_pic": pic,
                "vod_remarks": "",
                "vod_tag": "folder",
            })
        return items

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        tid = str(tid or "")
        if tid.startswith("creator:"):
            slug = tid[len("creator:"):]
            html = self._get(self._base + "/creator/" + slug + "/")
            items = self._cards(html)
            return {"list": items, "page": 1, "pagecount": 1, "limit": len(items) or 1, "total": len(items)}
        if tid == "creators":
            items = self._creator_items()
            return {"list": items, "page": 1, "pagecount": 1, "limit": len(items) or 1, "total": len(items)}
        items = self._section_items(tid)
        return {"list": items, "page": 1, "pagecount": 1, "limit": len(items) or 1, "total": len(items)}

    def _ld_json(self, html):
        out = []
        for m in re.finditer(r'<script type="application/ld\+json">(.*?)</script>', html, re.S):
            try:
                out.append(json.loads(m.group(1)))
            except Exception:
                pass
        return out

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            vid = str(ids[0]) if ids else ""
        else:
            vid = str(ids)
        kind, _, slug = vid.partition(":")
        if kind == "album":
            url = self._base + "/audio/album/" + slug + "/"
            html = self._get(url)
            title, pic, desc, tracks = slug, "", "", []
            for doc in self._ld_json(html):
                if doc.get("@type") == "CollectionPage":
                    title = doc.get("name") or title
                    pic = doc.get("image") or ""
                    desc = doc.get("description") or ""
                    main = doc.get("mainEntity") or {}
                    for el in main.get("itemListElement") or []:
                        item = el.get("item") or {}
                        nm = (item.get("name") or "").replace("#", "_").replace("$", "_")
                        cu = item.get("contentUrl") or ""
                        if cu:
                            tracks.append("%s$%s" % (nm, cu))
            if not tracks:
                for cu in sorted(set(re.findall(r'https://cdn\.asmrhoney\.com/audio/[^"]+\.mp3', html))):
                    nm = cu.rsplit("/", 2)[-2]
                    tracks.append("%s$%s" % (nm, cu))
            vod = {
                "vod_id": vid,
                "vod_name": _clean(title),
                "vod_pic": pic or ("https://cdn.asmrhoney.com/audio-albums/" + slug + "/cover.jpg"),
                "vod_remarks": "%d轨" % len(tracks) if tracks else "",
                "vod_content": _clean(desc),
                "vod_play_from": "ASMRHoney",
                "vod_play_url": "#".join(tracks),
            }
            return {"list": [vod]}
        url = self._base + "/clip/" + slug + "/"
        html = self._get(url)
        title, pic, play = slug, "", ""
        for doc in self._ld_json(html):
            if doc.get("@type") == "VideoObject":
                title = doc.get("name") or title
                play = doc.get("contentUrl") or ""
                pic = doc.get("thumbnailUrl") or doc.get("image") or ""
        if not play:
            mp4s = [u for u in sorted(set(re.findall(r'https://cdn\.asmrhoney\.com/clips/[^"]+\.mp4', html))) if "480p" not in u]
            play = mp4s[0] if mp4s else ""
        vod = {
            "vod_id": vid,
            "vod_name": _clean(title),
            "vod_pic": pic or ("https://cdn.asmrhoney.com/clips/" + slug + "/cover.jpg"),
            "vod_remarks": "",
            "vod_content": "",
            "vod_play_from": "ASMRHoney",
            "vod_play_url": "正片$" + play if play else "",
        }
        return {"list": [vod]}

    def searchContent(self, key, quick=False, pg="1"):
        kw = str(key or "").strip().lower()
        items = []
        if kw:
            for tid in ("audio", "asmr"):
                try:
                    for it in self._section_items(tid):
                        hay = (it.get("vod_name") or "") + " " + (it.get("vod_remarks") or "") + " " + it.get("vod_id", "")
                        if kw in hay.lower():
                            items.append(it)
                except Exception:
                    pass
        return {"list": items, "page": 1, "pagecount": 1, "limit": len(items) or 1, "total": len(items)}

    def playerContent(self, flag, id, vipFlags=None):
        url = str(id or "")
        return {"parse": 0, "url": url, "header": {"User-Agent": self._ua, "Referer": self._base + "/"}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".mp4" in u or ".m3u8" in u or ".mp3" in u or ".m4a" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
