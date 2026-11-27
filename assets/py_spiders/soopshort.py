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


FEEDS = [
    ("sexydance", "性感舞蹈", "섹시댄스"),
    ("bikini", "比基尼", "비키니"),
]
FEED_KW = {tid: kw for tid, _name, kw in FEEDS}

_TAG_MAIN = re.compile(r"^(?:섹시댄스|섹시여캠|섹시남캠|비키니|란제리)$")
_TAG_CAM = re.compile(r"^(?:여캠|남캠|신입여캠|신입남캠)$")
_TAG_SEXY = re.compile(r"^섹시$")
_TAG_DANCE = re.compile(r"^댄스$")


class Spider(BaseSpider):
    def getName(self):
        return "SOOP短视频"

    def getDependence(self):
        return []

    def init(self, extend=""):
        self._ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        self._home = "https://vod.sooplive.co.kr/"
        self._search_api = "https://sch.sooplive.co.kr/api.php"
        self._view_api = "https://api.m.sooplive.co.kr/station/video/a/view"

    def destroy(self):
        pass

    def _fetch(self, url, data=None, referer=None, retries=3, timeout=30):
        last = None
        for attempt in range(retries):
            try:
                headers = {"User-Agent": self._ua, "Accept": "*/*", "Connection": "close"}
                if referer:
                    headers["Referer"] = referer
                body = None
                if data is not None:
                    body = urllib.parse.urlencode(data).encode("utf-8")
                    headers["Content-Type"] = "application/x-www-form-urlencoded"
                req = urllib.request.Request(url, data=body, headers=headers)
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    return r.read().decode("utf-8", "replace")
            except Exception as e:
                last = e
                time.sleep(1 << attempt)
        raise last

    def _search(self, keyword, page, hash_mode):
        params = {
            "l": "DF", "m": "vodSearch", "w": "webk", "isMobile": "0",
            "szType": "json", "c": "UTF-8", "v": "5.0", "tab": "vod",
            "isHashSearch": "1" if hash_mode else "0",
            "szKeyword": keyword, "szFileType": "CATCH", "szTerm": "1year",
            "nPageNo": str(page), "nListCnt": "30",
            "location": "total_search", "szOrder": "view_cnt",
        }
        raw = self._fetch(self._search_api + "?" + urllib.parse.urlencode(params), referer=self._home)
        data = json.loads(raw)
        if int(data.get("RESULT") or 0) != 1 or not isinstance(data.get("DATA"), list):
            raise Exception("search api returned invalid data")
        return data

    def _in_scope(self, row):
        if row.get("file_type") != "CATCH" or str(row.get("vod_category")) != "00130000":
            return False
        tags = [str(t).strip() for t in (row.get("hash_tags") or []) if isinstance(t, str)]
        if any(_TAG_MAIN.match(t) for t in tags):
            return True
        return (any(_TAG_CAM.match(t) for t in tags)
                and any(_TAG_SEXY.match(t) for t in tags)
                and any(_TAG_DANCE.match(t) for t in tags))

    def _is_free(self, row):
        try:
            grade = int(row.get("grade") or 0)
        except Exception:
            grade = 0
        if grade >= 19:
            return False
        if row.get("ppv") or row.get("ppv_yn") == "Y":
            return False
        try:
            if int(row.get("fan_flag") or 0) > 0 or int(row.get("subs_flag") or 0) > 0:
                return False
        except Exception:
            pass
        auth = row.get("auth")
        if auth and auth != "OPEN_ALL":
            return False
        return True

    def _cover(self, row):
        url = ""
        if row.get("v_thumb"):
            url = str(row["v_thumb"])
        elif row.get("use_vertical_thumbnail") and row.get("vertical_thumbnail_path"):
            url = str(row["vertical_thumbnail_path"])
        elif row.get("thumbnail_path"):
            url = str(row["thumbnail_path"])
        elif row.get("thumbnail"):
            url = str(row["thumbnail"])
        if url.startswith("http://"):
            url = "https://" + url[len("http://"):]
        return url

    def _duration_text(self, row):
        ms = row.get("total_file_duration") or row.get("vod_duration")
        try:
            ms = int(ms)
        except Exception:
            ms = 0
        if ms > 0:
            sec = ms // 1000
            return "%d:%02d" % (sec // 60, sec % 60)
        d = str(row.get("duration") or "").strip()
        return d

    def _card(self, row):
        if not self._in_scope(row) or not self._is_free(row):
            return None
        tid = str(row.get("title_no") or "")
        title = str(row.get("title") or "").strip()
        if not re.fullmatch(r"[1-9]\d{0,11}", tid) or not title:
            return None
        return {
            "vod_id": tid,
            "vod_name": title,
            "vod_pic": self._cover(row),
            "vod_remarks": self._duration_text(row),
        }

    def _list_result(self, data, pg):
        items = []
        for row in data.get("DATA") or []:
            card = self._card(row)
            if card:
                items.append(card)
        has_more = bool(data.get("HAS_MORE_LIST"))
        pagecount = pg + 1 if has_more else pg
        return {"list": items, "page": pg, "pagecount": pagecount, "limit": 30, "total": 999999}

    def homeContent(self, filter=False):
        cats = [{"type_id": tid, "type_name": name} for tid, name, _kw in FEEDS]
        result = {"class": cats, "filters": {}}
        try:
            result["list"] = self.homeVideoContent().get("list") or []
        except Exception:
            result["list"] = []
        return result

    def homeVideoContent(self):
        data = self._search(FEED_KW[FEEDS[0][0]], 1, True)
        return self._list_result(data, 1)

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if extend is None:
            extend = {}
        pg = int(pg or 1)
        kw = FEED_KW.get(str(tid or ""))
        if not kw:
            raise Exception("unknown category: " + str(tid))
        data = self._search(kw, pg, True)
        return self._list_result(data, pg)

    def _view(self, tid):
        raw = self._fetch(self._view_api, data={"nTitleNo": tid, "nApiLevel": "10"},
                          referer=self._home + "player/" + tid)
        resp = json.loads(raw)
        data = resp.get("data")
        if int(resp.get("result") or 0) != 1 or not isinstance(data, dict):
            raise Exception("detail api returned invalid data")
        code = data.get("code")
        if code is not None:
            try:
                code = int(code)
            except Exception:
                code = 0
            if code == -6221:
                raise Exception("video not found")
            if code < 0:
                raise Exception("video unavailable (code %d)" % code)
        if str(data.get("title_no")) != tid:
            raise Exception("video not found")
        if data.get("adult_status") == "notLogin" or data.get("sub_upload_type") or data.get("is_paid") or data.get("is_ppv"):
            raise Exception("video requires login or payment on the original site")
        if data.get("flag") != "SUCCEED" or int(data.get("is_public") or 0) != 1:
            raise Exception("video is not public")
        return data

    def _files(self, data):
        files = data.get("files")
        if not isinstance(files, list) or not files:
            raise Exception("video has no files")
        parts = []
        for f in files:
            if not isinstance(f, dict) or f.get("hide") != "N":
                raise Exception("video file is hidden")
            key = str(f.get("file_info_key") or "")
            if not key:
                idx = f.get("idx")
                if isinstance(idx, int) and idx > 0:
                    key = str(idx)
            try:
                order = int(f.get("file_order") or 0)
            except Exception:
                order = 0
            if not re.fullmatch(r"[A-Za-z0-9_\-]{1,128}", key) or order < 1:
                raise Exception("video file data invalid")
            parts.append((order, key, f))
        parts.sort(key=lambda x: x[0])
        return parts

    def detailContent(self, ids):
        if isinstance(ids, (list, tuple)):
            tid = str(ids[0]) if ids else ""
        else:
            tid = str(ids)
        if not re.fullmatch(r"[1-9]\d{0,11}", tid):
            raise Exception("bad video id")
        data = self._view(tid)
        parts = self._files(data)
        cover = str(data.get("thumb") or "")
        if cover.startswith("http://"):
            cover = "https://" + cover[len("http://"):]
        tags = [str(t).strip() for t in (data.get("hash_tags") or []) if isinstance(t, str) and str(t).strip()]
        eps = []
        for order, key, _f in parts:
            eps.append("第%d段$%s|%s" % (order, tid, key))
        vod = {
            "vod_id": tid,
            "vod_name": str(data.get("title") or ""),
            "vod_pic": cover,
            "vod_actor": str(data.get("writer_nick") or ""),
            "vod_tag": ",".join(tags),
            "vod_remarks": self._duration_text(data),
            "vod_play_from": "SOOP",
            "vod_play_url": "#".join(eps),
        }
        return {"list": [vod]}

    def searchContent(self, key, quick=False, pg="1"):
        pg = int(pg or 1)
        kw = str(key or "").strip()
        if not kw:
            return {"list": [], "page": pg, "pagecount": pg, "limit": 30, "total": 0}
        data = self._search(kw, pg, True)
        result = self._list_result(data, pg)
        if not result["list"]:
            data = self._search(kw, pg, False)
            result = self._list_result(data, pg)
        return result

    def playerContent(self, flag, id, vipFlags=None):
        m = re.fullmatch(r"([1-9]\d{0,11})\|([A-Za-z0-9_\-]{1,128})", str(id or ""))
        if not m:
            raise Exception("bad episode id")
        tid, key = m.group(1), m.group(2)
        data = self._view(tid)
        parts = self._files(data)
        chosen = None
        for _order, k, f in parts:
            if k == key:
                chosen = f
                break
        if chosen is None:
            raise Exception("episode not found")
        url = str(chosen.get("file") or "")
        u = urllib.parse.urlparse(url)
        if u.scheme != "https" or not u.hostname or not u.path.lower().endswith(".m3u8"):
            raise Exception("stream is not an https m3u8")
        return {"parse": 0, "url": url, "header": {"User-Agent": self._ua, "Referer": self._home + "player/" + tid}}

    def isVideoFormat(self, url):
        u = str(url or "").lower()
        return ".m3u8" in u or ".mp4" in u

    def manualVideoCheck(self):
        return False

    def localProxy(self, param=None):
        return None

    def action(self, action=None):
        return None
