.pragma library

// 余额查询：各服务商的接口与解析，以及按「已用百分比」分档。
// 分档与 DeepSeek 满额参考值取自 dsh-pet（shared/balance/percent.ts、host/balance/deepseek-common.ts）。

// 已用百分比 0-20-40-60-80-100 → 6 档动画；p === 100 单独一档
var ANIMS = ["余额-钱袋满溢", "余额-金袋叮当", "余额-钱袋如常", "余额-数金皱眉", "余额-袋空如洗", "余额-分文不剩"];

var PROVIDERS = {
    deepseek: {
        label: "DeepSeek",
        base: "https://api.deepseek.com",
        path: "/user/balance"
    },
    openrouter: {
        label: "OpenRouter",
        base: "https://openrouter.ai/api/v1",
        path: "/credits"
    },
    siliconflow: {
        label: "硅基流动",
        base: "https://api.siliconflow.cn/v1",
        path: "/user/info"
    }
};

// 没填满额参考时用的默认值（DeepSeek 官方：¥20 / $5）
var DEFAULT_FULL = { CNY: 20, USD: 5 };

// aiBaseUrl 猜服务商（provider = "auto" 时）
function guessProvider(aiBaseUrl) {
    var u = (aiBaseUrl || "").toLowerCase();
    if (u.indexOf("deepseek") >= 0)
        return "deepseek";
    if (u.indexOf("openrouter") >= 0)
        return "openrouter";
    if (u.indexOf("siliconflow") >= 0)
        return "siliconflow";
    return "";
}

function eventIndex(p) {
    if (p >= 100)
        return 5;
    var i = Math.floor(p / 20);
    return i < 5 ? i : 4;
}

function sym(cur) {
    return cur === "USD" ? "$" : "¥";
}

function money(n) {
    return Number(n).toFixed(2);
}

// DeepSeek 峰谷时段（北京时间工作日 9-12、14-18 为峰）
function deepseekTier(now) {
    var utc = now.getTime() + now.getTimezoneOffset() * 60000;
    var bj = new Date(utc + 8 * 3600000);
    var d = bj.getDay(), h = bj.getHours();
    if (d === 0 || d === 6)
        return "谷";
    return (h >= 9 && h < 12) || (h >= 14 && h < 18) ? "峰" : "谷";
}

// 解析响应 → { ok, percent (0-100，可能为 undefined), text, low } 或 { ok:false, error }
// full：用户填的满额参考（数字，0 = 用默认）
function parse(provider, body, full, now) {
    try {
        if (provider === "deepseek") {
            var infos = body.balance_infos;
            if (!infos || !infos.length)
                return { ok: false, error: "响应里没有 balance_infos" };
            var remaining = 0, based = 0, parts = [];
            for (var i = 0; i < infos.length; i++) {
                var w = infos[i];
                var total = Number(w.total_balance);
                var ref = full > 0 ? full : DEFAULT_FULL[w.currency];
                if (isFinite(total) && ref > 0) {
                    remaining += total / ref;
                    based++;
                }
                if (total !== 0)
                    parts.push(sym(w.currency) + money(total));
            }
            var p = based ? clamp(100 - remaining * 100) : undefined;
            return {
                ok: true,
                percent: p,
                text: "余额（" + deepseekTier(now || new Date()) + "）" + (parts.length ? parts.join(" / ") : "¥0.00"),
                available: body.is_available !== false
            };
        }
        if (provider === "openrouter") {
            var d = body.data || {};
            var credits = Number(d.total_credits), usage = Number(d.total_usage);
            if (!isFinite(credits) || !isFinite(usage))
                return { ok: false, error: "响应里没有 total_credits" };
            var left = credits - usage;
            return {
                ok: true,
                percent: credits > 0 ? clamp(usage / credits * 100) : 100,
                text: "余额 $" + money(left) + " / $" + money(credits),
                available: left > 0
            };
        }
        if (provider === "siliconflow") {
            var u = body.data || {};
            var bal = Number(u.totalBalance !== undefined ? u.totalBalance : u.balance);
            if (!isFinite(bal))
                return { ok: false, error: "响应里没有 totalBalance" };
            var ref2 = full > 0 ? full : 20;
            return {
                ok: true,
                percent: clamp(100 - bal / ref2 * 100),
                text: "余额 ¥" + money(bal),
                available: bal > 0
            };
        }
    } catch (e) {
        return { ok: false, error: "返回格式看不懂" };
    }
    return { ok: false, error: "不认识的服务商 " + provider };
}

function clamp(p) {
    return Math.max(0, Math.min(100, p));
}

// 气泡文案：余额 + 一句按档位的话
function bubbleText(r, petName) {
    if (!r.ok)
        return "查不到余额：" + r.error;
    var p = r.percent;
    var say = "";
    if (p === undefined)
        say = "";
    else if (p >= 100 || r.available === false)
        say = "钱包空空……主人快充值吧 QAQ";
    else if (p >= 90)
        say = "快用完啦，记得充值！";
    else if (p >= 70)
        say = "有点紧巴巴的……";
    else if (p >= 40)
        say = "还够用～";
    else
        say = "钱包鼓鼓的！";
    return r.text + (say ? "\n" + say : "");
}

function animFor(r) {
    if (!r.ok || r.percent === undefined)
        return "";
    return ANIMS[eventIndex(r.percent)];
}
