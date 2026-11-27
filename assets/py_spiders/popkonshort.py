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


PAGE_SIZE = 20


class Spider(BaseSpider):
    def getName(self):
        return "PopkonTV短视频"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        self._base = "https://www.popkontv.com"
        self._api = "https://www.popkontv.com/api/proxy/vod/v1"
        self._scan_cache = {}

    def destroy(self):
        pass

    def _api_call(self, path, body, retries=3, timeout=30):
        payload = dict(body)
        payload["partnerCode"] = "P-00001"
        payload["signId"] = ""
        raw = json.dumps(payload).encode("utf-8")
        last = None
        for attempt in range(retries):
            try:
                headers = {
                    "User-Agent": self._ua,
                    "Accept": "*/*",
                    "Content-Type": "application/json",
                    "Origin": self._base,
                    "Referer": self._base + "/",
                    "Connection": "close",
                }
                req = urllib.request.Request(self._api + path, data=raw, headers=headers)
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    data = json.loads(r.read().decode("utf-8", "replace"))
                if data.get("statusCd") != "S2000":
                    raise Exception("api status: " + str(data.get("statusCd")))
                return data.get("data")
            except Exception as e:
                last = e
                time.sleep(1 << attempt)
        raise last

    def _quote(self, url):
        return urllib.parse.quote(str(url or ""), safe=":/?&=+%")

    def _card(self, v):
        idx = str(v.get("idx") or "")
        title = str(v.get("vodTitle") or "").strip()
        if not re.fullmatch(r"[1-9]\d{0,8}", idx) or not title:
            return None
        return {
            "vod_id": idx,
            "vod_name": title,
            "vod_pic": self._quote(v.get("thumbnailUrl") or ""),
            "vod_remarks": str(v.get("ago") or ""),
        }

    def _list_page(self, pg):
        data = self._api_call("/list", {
            "category": 1, "groupCode": 20,
            "pageNum": pg, "pageSize": PAGE_SIZE, "sortType": 2,
        })
        if not isinstance(data, dict) or not isinstance(data.get("vodList"), list):
            raise Exception("list api returned invalid data")
        try:
            total = int(data.get("totalCnt") or 0)
        except Exception:
            total = 0
        items = []
        for v in data["vodList"]:
            card = self._card(v)
            if card:
                items.append(card)
        pagecount = (total + PAGE_SIZE - 1) // PAGE_SIZE if total > 0 else pg
        return items, pagecount, total

    def homeContent(self, filter=False):
        result = {"class": [{"type_id": "recommend", "type_name": "推荐"}], "filters": {}}
        try:
            result["list"] = self.homeVideoContent().get("list") or []
        except Exception:
            result["list"] = []
        return result

    def homeVideoContent(self):
        items, _pc, _total = self._list_page(1)
        return {"list": items}

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        pg = int(pg or 1)
        if str(tid or "") != "recommend":
            raise Exception("unknown category: " + str(tid))
        items, pagecount, total = self._list_page(pg)
        return {"list": items, "page": pg, "pagecount": pagecount, "limit": PAGE_SIZE, "total": total}

    def _detail(self, idx):
        data = self._api_call("/detail", {"idx": int(idx)})
        if not isinstance(data, dict) or str(data.get("pk_code")) != str(idx) or not data.get("vodTitle"):
            raise Exception("video not found")
        return data

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            idx = str(ids[0]) if ids else ""
        else:
            idx = str(ids)
        if not re.fullmatch(r"[1-9]\d{0,8}", idx):
            raise Exception("bad video id")
        data = self._detail(idx)
        tags = [str(t).strip() for t in (data.get("hashTags") or []) if isinstance(t, str) and str(t).strip()]
        vod = {
            "vod_id": idx,
            "vod_name": str(data.get("vodTitle") or ""),
            "vod_pic": self._quote(data.get("vodPoster") or ""),
            "vod_actor": str(data.get("nickName") or ""),
            "vod_content": str(data.get("contentTxt") or ""),
            "vod_tag": ",".join(tags),
            "vod_play_from": "Popkon",
            "vod_play_url": "正片$" + idx,
        }
        return {"list": [vod]}

    def _scan_matches(self, kw):
        if kw in self._scan_cache:
            return self._scan_cache[kw]
        matches = []
        seen = set()
        pg = 1
        while True:
            items, pagecount, _total = self._list_page(pg)
            for it in items:
                if kw.lower() in it["vod_name"].lower() and it["vod_id"] not in seen:
                    seen.add(it["vod_id"])
                    matches.append(it)
            if pg >= pagecount or not items:
                break
            pg += 1
        self._scan_cache[kw] = matches
        return matches

    def searchContent(self, key, quick=False, pg="1"):
        pg = int(pg or 1)
        kw = str(key or "").strip()
        if not kw:
            return {"list": [], "page": pg, "pagecount": pg, "limit": PAGE_SIZE, "total": 0}
        matches = self._scan_matches(kw)
        start = (pg - 1) * PAGE_SIZE
        page_items = matches[start:start + PAGE_SIZE]
        pagecount = (len(matches) + PAGE_SIZE - 1) // PAGE_SIZE if matches else pg
        return {"list": page_items, "page": pg, "pagecount": pagecount, "limit": PAGE_SIZE, "total": len(matches)}

    def playerContent(self, flag, id, vipFlags=None):
        idx = str(id or "")
        if not re.fullmatch(r"[1-9]\d{0,8}", idx):
            raise Exception("bad video id")
        data = self._detail(idx)
        url = str(data.get("vodAddress") or "")
        u = urllib.parse.urlparse(url)
        if u.scheme != "https" or not u.hostname or not u.path.lower().endswith(".mp4"):
            raise Exception("stream is not an https mp4")
        return {"parse": 0, "url": self._quote(url), "header": {"User-Agent": self._ua, "Referer": self._base + "/"}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".m3u8" in u or ".mp4" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
