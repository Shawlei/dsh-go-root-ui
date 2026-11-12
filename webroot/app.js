/* dsh-go Root UI · 前端逻辑
 * 两条通道：
 *   1) 管理器原生 —— KernelSU/SukiSU 注入的 ksu 对象（回调式 ksu.exec）
 *   2) HTTP —— 守护在 127.0.0.1:7000，token 认证
 */
(function () {
  "use strict";

  var BRIDGE_NAMES = ["ksu", "$ksu", "kernelsu", "$kernelsu", "ksuAPI"];
  var MODDIR = "/data/adb/modules/dshgo_rootui";
  var state = { bridge: null, bridgeName: "", token: "", api: "", seq: 0 };

  var $ = function (id) { return document.getElementById(id); };
  var onLoopback = location.hostname === "127.0.0.1" || location.hostname === "localhost";

  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  function show(t) { $("out").textContent = t === "" ? "(无输出)" : String(t); }
  function strip(t) {
    return String(t || "").replace(/^WARNING: linker:.*\n/gm, "").replace(/\s+$/, "");
  }
  function setMode(text, tone) {
    var b = $("mode");
    b.textContent = text;
    b.className = "badge" + (tone ? " " + tone : "");
  }
  function errText(e) { return e && e.message ? e.message : String(e); }

  /* ---------- 通道探测 ---------- */
  function findBridge() {
    for (var i = 0; i < BRIDGE_NAMES.length; i++) {
      var o = window[BRIDGE_NAMES[i]];
      if (o && typeof o.exec === "function") {
        state.bridge = o; state.bridgeName = BRIDGE_NAMES[i];
        return true;
      }
    }
    return false;
  }

  /* 兼容 4 参回调 / 3 参回调 / 返回 Promise 或对象 */
  function bridgeExec(cmd) {
    return new Promise(function (resolve, reject) {
      var done = false, timer = null;
      function ok(a, b) {
        if (done) return;
        done = true; if (timer) clearTimeout(timer);
        if (a && typeof a === "object") resolve({ stdout: a.stdout || "", stderr: a.stderr || "" });
        else resolve({ stdout: a == null ? "" : String(a), stderr: b == null ? "" : String(b) });
      }
      function bad(e) {
        if (done) return;
        done = true; if (timer) clearTimeout(timer);
        reject(e instanceof Error ? e : new Error(String(e)));
      }
      var cb = "_cb" + Date.now() + "_" + (state.seq++);
      window[cb] = ok;
      window[cb + "_error"] = bad;
      var ret;
      try { ret = state.bridge.exec(cmd, "{}", cb, cb + "_error"); }
      catch (e1) {
        try { ret = state.bridge.exec(cmd, "{}", cb); }
        catch (e2) { bad(e2); return; }
      }
      if (ret && typeof ret.then === "function") {
        ret.then(function (v) { ok(v && v.stdout, v && v.stderr); }, bad); return;
      }
      if (ret && (ret.stdout !== undefined || ret.errno !== undefined)) {
        ok(ret.stdout, ret.stderr); return;
      }
      timer = setTimeout(function () {
        bad(new Error("桥没有回调（调用形状不匹配）"));
      }, 2500);
    });
  }

  function httpExec(cmd) {
    return fetch(state.api + "/api/exec?token=" + encodeURIComponent(state.token), {
      method: "POST", body: cmd
    }).then(function (r) {
      if (r.status === 401) throw new Error("token 不对");
      return r.text();
    });
  }

  function exec(cmd) {
    if (state.bridge) {
      return bridgeExec(cmd).then(function (r) {
        return r.stdout + (r.stderr ? "\n" + r.stderr : "");
      });
    }
    return httpExec(cmd);
  }

  /* ---------- 动作 ---------- */
  function run() {
    var cmd = $("cmd").value;
    $("run").disabled = true;
    show("执行中…");
    exec(cmd).then(function (t) {
      show(strip(t));
      remember(cmd);
    }).catch(function (e) {
      show("执行失败：" + errText(e));
    }).then(function () {
      $("run").disabled = false;
    });
  }

  function remember(cmd) {
    var h = [];
    try { h = JSON.parse(lsGet("dshgo_hist") || "[]"); } catch (e) { h = []; }
    h = h.filter(function (x) { return x !== cmd; });
    h.unshift(cmd);
    lsSet("dshgo_hist", JSON.stringify(h.slice(0, 20)));
  }

  function status() {
    exec("id -u; getprop ro.product.model; getprop ro.build.version.release; " +
         "cat /proc/self/attr/current 2>/dev/null; " +
         "ls " + MODDIR + "/webroot/index.html >/dev/null 2>&1 && echo mod=ok; " +
         "ls /usr/local/bin/r >/dev/null 2>&1 && echo cli=yes")
      .then(function (txt) {
        var L = strip(txt).split("\n");
        var uid = (L[0] || "").trim();
        $("s-uid").innerHTML = uid === "0"
          ? '<span class="ok">0 · root</span>'
          : '<span class="bad">' + (uid || "?") + "</span>";
        $("s-dev").textContent = (L[1] || "—") + " · Android " + (L[2] || "—");
        $("s-ctx").textContent = L[3] || "—";
        $("s-cli").innerHTML = txt.indexOf("cli=yes") >= 0
          ? '<span class="ok">已安装 r / rfix</span>'
          : '<span class="bad">未安装</span>';
        setMode(state.bridge ? "原生 " + state.bridgeName : "HTTP 7000");
      })
      .catch(function (e) {
        $("s-uid").innerHTML = '<span class="bad">通道未通</span>';
        show("通道未通：" + errText(e) +
          "\n\n诊断：bridge=" + (state.bridge ? state.bridgeName : "未找到") +
          "  origin=" + location.href);
      });
  }

  function api(path, body) {
    if (state.bridge) return exec(body || null);
    return fetch(state.api + path + "?token=" + encodeURIComponent(state.token), {
      method: "POST", body: body || ""
    }).then(function (r) {
      if (r.status === 401) throw new Error("token 不对");
      return r.text();
    });
  }

  function act(kind) {
    var btn = $(kind);
    if (btn) btn.disabled = true;
    show("执行中…");

    var p;
    if (kind === "install") p = exec("sh " + MODDIR + "/bin/install-client.sh");
    if (kind === "log")     p = exec("tail -n 80 /data/adb/dshgo_rootui/daemon.log 2>/dev/null");
    if (kind === "rotate")  p = exec("sh " + MODDIR + "/bin/rotate.sh");

    (p || Promise.reject(new Error("未知动作")))
      .then(function (t) {
        t = strip(t);
        if (kind === "rotate") {
          var lines = t.split("\n");
          var tok = (lines[0] || "").replace("新 token: ", "").trim();
          if (/^[0-9a-f]{16,}$/.test(tok)) {
            state.token = tok;
            lsSet("dshgo_tok", tok);
            $("tok").value = tok;
          }
          show(t + "\n\n容器里的 r 已同步更新。");
        } else {
          show(t);
        }
        if (kind !== "log") status();
      })
      .catch(function (e) { show("失败：" + errText(e)); })
      .then(function () { if (btn) btn.disabled = false; });
  }

  /* ---------- 启动 ---------- */
  function boot() {
    if ($("s-uid").textContent !== "—" && state.bridge) return;

    state.token = lsGet("dshgo_tok") || (window.DSHGO && window.DSHGO.token) || "";
    $("tok").value = state.token;

    if (findBridge()) {
      setMode("原生 " + state.bridgeName);
      $("tokbox").classList.add("hide");
      status();
      return;
    }

    if (!onLoopback) {
      // 管理器可能是 file:// 打开且没注入桥：跳到守护自己的页面（token 现场注入）
      setMode("连接守护…", "warn");
      fetch("http://127.0.0.1:7000/api/ping", { cache: "no-store" })
        .then(function (r) {
          if (!r.ok) throw new Error("ping " + r.status);
          $("out").innerHTML =
            '<a href="http://127.0.0.1:7000/">打开控制台</a>\n（守护已就绪，正在跳转…）';
          setTimeout(function () { location.replace("http://127.0.0.1:7000/"); }, 250);
        })
        .catch(function () {
          setMode("守护未启动", "bad");
          show("通道未通：管理器没有暴露原生桥，本机 7000 端口也没开。\n\n" +
            "① 重启一次手机（service.sh 会拉起守护），再打开本页；\n" +
            "② 或在 Termux 里执行：\n" +
            '   su -c "nohup /system/bin/sh ' + MODDIR + '/bin/rootd.sh >/dev/null 2>&1 &"\n' +
            "③ 也可以直接在浏览器打开 http://127.0.0.1:7000/");
        });
      return;
    }

    setMode("HTTP 7000");
    $("tokbox").classList.remove("hide");
    if (!state.token) show("需要 token：/data/adb/dshgo_rootui/token");
    else status();
  }

  var CMDS = ["id", "ls /data/adb/modules", "getprop ro.product.model",
              "dumpsys battery | head -6", "ls /data/adb/dshgo_rootui"];
  CMDS.forEach(function (c) {
    var b = document.createElement("span");
    b.className = "chip";
    b.textContent = c;
    b.onclick = function () { $("cmd").value = c; run(); };
    $("chips").appendChild(b);
  });

  $("run").onclick = run;
  $("install").onclick = function () { act("install"); };
  $("log").onclick = function () { act("log"); };
  $("rotate").onclick = function () { act("rotate"); };
  $("copy").onclick = function () {
    var t = $("out").textContent;
    if (navigator.clipboard) navigator.clipboard.writeText(t).then(function () {
      if (window.ksu && window.ksu.toast) window.ksu.toast("已复制");
    });
  };
  $("cmd").addEventListener("keydown", function (e) {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); run(); }
    if (e.key === "ArrowUp" && $("cmd").value.indexOf("\n") < 0) {
      var h = [];
      try { h = JSON.parse(lsGet("dshgo_hist") || "[]"); } catch (e2) { h = []; }
      if (h.length) { e.preventDefault(); $("cmd").value = h[0]; }
    }
  });
  $("tok").addEventListener("change", function () {
    state.token = this.value.trim();
    lsSet("dshgo_tok", state.token);
    status();
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { setTimeout(boot, 60); });
  } else {
    setTimeout(boot, 60);
  }
  window.addEventListener("load", function () {
    setTimeout(function () { if (!state.bridge && findBridge()) boot(); }, 300);
  });
})();
