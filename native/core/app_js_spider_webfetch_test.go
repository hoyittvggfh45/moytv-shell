package core

import (
	"strings"
	"testing"
)

// webFetch 声明式两段：jsSpiderDispatch 收到 command=webFetchResult 时
// 把壳侧取回的 HTML 与 ctx 喂给脚本的 webFetchResult(html, ctx)。
func TestJsSpiderWebFetchResultDispatch(t *testing.T) {
	script := `
function webFetchResult(html, ctx) {
  return {list: [{vod_id: ctx.id, vod_name: html.indexOf("cf_clearance") >= 0 ? "passed" : "empty"}]};
}
`
	out, err := jsSpiderDispatch(nativeInput{
		Content:      script,
		Command:      "webFetchResult",
		WebFetchHTML: "<html><script>cf_clearance=1</script></html>",
		WebFetchCtx:  `{"id":"abc123"}`,
	})
	if err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	items, ok := out["list"].([]interface{})
	if !ok || len(items) != 1 {
		t.Fatalf("list = %v", out["list"])
	}
	first, _ := items[0].(map[string]interface{})
	if first["vod_id"] != "abc123" || first["vod_name"] != "passed" {
		t.Fatalf("item = %v", first)
	}
}

func TestJsSpiderWebFetchResultMissingFunction(t *testing.T) {
	_, err := jsSpiderDispatch(nativeInput{
		Content:      `function homeContent() { return {list: []}; }`,
		Command:      "webFetchResult",
		WebFetchHTML: "<html></html>",
		WebFetchCtx:  `{}`,
	})
	if err == nil || !strings.Contains(err.Error(), "webFetchResult") {
		t.Fatalf("err = %v", err)
	}
}
