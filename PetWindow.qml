import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Common
import "pet.js" as Pet
import "ai.js" as AI
import "balance.js" as Balance

// 整屏透明层：只有宠物身体（和打开时的菜单）接收鼠标，其余区域点击穿透。
// niri 不允许客户端自己摆窗口，所以宠物不移动窗口，而是在这个全屏层里移动。
PanelWindow {
    id: win

    property real petSize: 300          // 640x360 素材帧显示宽度（px）
    property bool roam: true            // 是否随机走动
    property bool overlayLayer: false   // true = 盖在全屏窗口上
    property real groundOffset: 0       // 地面离屏幕底边的距离（px），给 dock 留位置
    property string petName: "大肥鱼"

    // AI（OpenAI 兼容接口）
    property string aiBaseUrl: ""
    property string aiApiKey: ""        // 明文，或 env:变量名 / file:/路径
    property string aiModel: ""
    property string persona: ""
    property bool whisperEnabled: true
    property int whisperIntervalSec: 300
    property int chatMemoryRounds: 10
    property bool chatAnimationEnabled: true
    property bool sleepTalkEnabled: true
    property int sleepTalkSec: 90
    property bool todoNotify: true

    // 余额
    property string balanceProvider: "auto"   // auto / deepseek / openrouter / siliconflow / off
    property string balanceApiKey: ""         // 空 = 用 AI 的 key；同样支持 env: / file:
    property string balanceBaseUrl: ""        // 空 = 服务商默认地址
    property real balanceFull: 0              // 满额参考（元/美元），0 = 默认（DeepSeek ¥20/$5）
    property bool balanceAuto: true           // 定时报余额
    property int balanceIntervalSec: 1800

    // 多屏：宠物可以去的屏（single 模式 = 小组件显示的所有屏），isPrimary 的那只注册 IPC
    property var allowedScreens: []
    property bool isPrimary: true

    // 给外部（桌面小组件）读的状态
    readonly property bool sleeping: mode === "sleep"
    readonly property string currentAnim: sprite.current

    color: "transparent"
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    WlrLayershell.layer: overlayLayer ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // 聊天框打开时才要键盘；OnDemand = 点到输入框时由合成器给焦点
    WlrLayershell.keyboardFocus: (chat.visible || todoPanel.visible) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "dms:dux-pet"

    mask: menu.visible ? null : petRegion

    // 输入区域直接绑定坐标：Region.item 只跟踪那个 item 自身的几何变化，
    // 而 hitArea 是跟着父级 pet 移动的，绑 item 会让可点区域停在出生点。
    Region {
        id: petRegion
        x: Math.round(pet.x + win.hx0)
        y: Math.round(pet.y + win.hy0)
        width: Math.round(win.hx1 - win.hx0)
        height: Math.round(win.hy1 - win.hy0)

        Region {
            x: Math.round(chat.x)
            y: Math.round(chat.y)
            width: chat.visible ? Math.round(chat.width) : 0
            height: chat.visible ? Math.round(chat.height) : 0
        }
        Region {
            x: Math.round(todoPanel.x)
            y: Math.round(todoPanel.y)
            width: todoPanel.visible ? Math.round(todoPanel.width) : 0
            height: todoPanel.visible ? Math.round(todoPanel.height) : 0
        }
        Region {
            x: Math.round(todoChip.x)
            y: Math.round(todoChip.y)
            width: todoChip.visible ? Math.round(todoChip.width) : 0
            height: todoChip.visible ? Math.round(todoChip.height) : 0
        }
    }

    // ---------------------------------------------------------------- 几何

    readonly property real petW: petSize
    readonly property real petH: petSize * 9 / 16
    readonly property real hx0: Pet.HIT_BOX.x0 / 640 * petW
    readonly property real hx1: Pet.HIT_BOX.x1 / 640 * petW
    readonly property real hy0: Pet.HIT_BOX.y0 / 360 * petH
    readonly property real hy1: Pet.HIT_BOX.y1 / 360 * petH
    // 用屏幕尺寸而不是窗口尺寸：layer surface 刚映射时窗口宽高还不是最终值
    readonly property real sw: screen ? screen.width : width
    readonly property real sh: screen ? screen.height : height
    readonly property var bounds: ({
            left: -hx0,
            right: sw - hx1,
            top: -hy0,
            bottom: sh - hy1 - groundOffset
        })

    // ---------------------------------------------------------------- 多屏

    readonly property var screenRects: allowedScreens.map(s => ({
                x: s.x,
                y: s.y,
                width: s.width,
                height: s.height
            }))
    readonly property int screenIndex: allowedScreens.indexOf(screen)
    readonly property bool leftOpen: screenIndex >= 0 && Pet.neighbor(screenRects, screenRects[screenIndex], -1) !== null
    readonly property bool rightOpen: screenIndex >= 0 && Pet.neighbor(screenRects, screenRects[screenIndex], 1) !== null
    // 有相邻屏的那一侧不设墙，越过屏边时 checkHandoff 把宠物交给隔壁屏
    readonly property var softBounds: ({
            left: leftOpen ? -1e9 : bounds.left,
            right: rightOpen ? 1e9 : bounds.right,
            top: bounds.top,
            bottom: bounds.bottom
        })

    function clampX(x) {
        return Math.max(softBounds.left, Math.min(softBounds.right, x));
    }

    property bool handingOff: false

    function checkHandoff() {
        if (handingOff || mode === "drag" || !screen || screenIndex < 0)
            return;
        const cx = pet.x + (hx0 + hx1) / 2;
        if (cx >= 0 && cx < sw)
            return;
        const gx = screen.x + cx;
        const gy = screen.y + pet.y + hy1 - 1;
        const rects = screenRects;
        const target = Pet.screenAt(rects, gx, gy);
        const idx = target ? rects.indexOf(target) : -1;
        if (idx < 0 || idx === screenIndex) {
            pet.x = Math.max(bounds.left, Math.min(bounds.right, pet.x));
            return;
        }
        handingOff = true;
        const moving = moveAnim.running || moveCont.running;
        const remain = moving ? (moveCont.running ? moveCont.to : moveTravel.to) - pet.x : 0;
        const speed = moving ? Math.abs(moveTravel.to - moveTravel.from) / Math.max(1, moveTravel.duration) : 0;
        moveAnim.stop();
        moveCont.stop();
        const from = screen;
        const to = allowedScreens[idx];
        pet.x += from.x - to.x;
        pet.y += from.y - to.y;
        screen = to;
        if (pet.y > bounds.bottom)
            pet.y = bounds.bottom;
        handingOff = false;
        if (moving && Math.abs(remain) > 1 && speed > 0) {
            moveCont.from = pet.x;
            moveCont.to = pet.x + remain;
            moveCont.duration = Math.abs(remain) / speed;
            moveCont.start();
        }
        if (mode === "auto" && pet.y < bounds.bottom - 0.5)
            mode = "fly";
    }

    // 叫到某块屏（默认当前屏）：从右侧上方落下来
    function summon(target) {
        stopMotion();
        if (target && allowedScreens.indexOf(target) >= 0 && target !== screen)
            screen = target;
        pet.x = bounds.right - 40;
        vx = 0;
        vy = 0;
        if (mode === "sleep") {
            pet.y = bounds.bottom;      // 睡着/正在醒：直接放到地上
        } else {
            pet.y = bounds.top;
            mode = "fly";
        }
    }

    function home() {
        summon(screen);
    }

    onSwChanged: Qt.callLater(keepInside)
    onShChanged: Qt.callLater(keepInside)
    onPetSizeChanged: Qt.callLater(keepInside)
    onGroundOffsetChanged: Qt.callLater(keepInside)

    property bool placed: false

    function keepInside() {
        if (sw <= 0 || sh <= 0)
            return;
        if (!placed) {
            placed = true;
            pet.x = bounds.right - 40;
            pet.y = bounds.bottom;
            return;
        }
        pet.x = clampX(pet.x);
        if (mode === "drag")
            return;
        if (pet.y > bounds.bottom)
            pet.y = bounds.bottom;
        if (pet.y < bounds.bottom - 0.5 && mode !== "fly" && mode !== "sleep") {
            stopMotion();
            mode = "fly";
        }
    }

    // ---------------------------------------------------------------- 状态机
    // auto: 自主动作  drag: 被拖着  fly: 抛飞/下落  sleep: 睡觉（含入睡/醒来）
    property string mode: "auto"
    property string kind: "idle"       // 当前动画的含义：idle/turn/move/action/click/sleepStart/sleepLoop/sleepEnd
    property string facing: "left"     // 素材默认朝左
    property var pendingMove: null
    property real vx: 0
    property real vy: 0
    property bool started: false

    function playAnim(name, k, loop) {
        kind = k;
        sprite.play(name, loop);
    }

    function nextAuto() {
        if (mode !== "auto")
            return;
        if (pet.y < bounds.bottom - 0.5) {
            // 兜底：不管怎么悬空的，先掉下来
            vx = 0;
            vy = 0;
            mode = "fly";
            return;
        }
        const a = Pet.nextAction(roam && !chat.visible);
        if (a.kind === "move") {
            pendingMove = a.move;
            playAnim(a.name, "move", false);
        } else {
            pendingMove = null;
            playAnim(a.name, a.kind, false);
        }
    }

    function playCategory(catId) {
        if (mode === "sleep") {
            say(Pet.pick(Pet.SLEEP_REFUSE_TEXTS));
            return;
        }
        const cat = Pet.CATEGORIES.find(c => c.id === catId);
        if (!cat)
            return;
        stopMotion();
        mode = "auto";
        playAnim(Pet.pick(cat.actions), "action", false);
    }

    function stopMotion() {
        moveAnim.stop();
        moveCont.stop();
        pendingMove = null;
    }

    function goSleep() {
        if (mode === "sleep")
            return;
        stopMotion();
        if (pet.y < bounds.bottom - 0.5)
            pet.y = bounds.bottom;
        mode = "sleep";
        say(Pet.pick(Pet.SLEEP_START_TEXTS));
        playAnim(Pet.SLEEP.start, "sleepStart", false);
    }

    function wakeUp() {
        if (mode !== "sleep" || kind === "sleepEnd")
            return;
        say(Pet.pick(Pet.SLEEP_END_TEXTS));
        playAnim(Pet.SLEEP.end, "sleepEnd", false);
    }

    function onClicked() {
        if (mode === "sleep") {
            wakeUp();
            return;
        }
        stopMotion();
        mode = "auto";
        squash(0.75);
        playAnim(Pet.pick(Pet.CLICKS), "click", false);
    }

    function turnAround() {
        if (mode === "sleep")
            return;
        stopMotion();
        mode = "auto";
        playAnim(Pet.TURN, "turn", false);
    }

    function startMove(p) {
        const dur = sprite.durationSec;
        if (dur <= 0)
            return;
        let dir = facing === "right" ? 1 : -1;
        const room = d => d > 0 ? (rightOpen ? p.maxDist : bounds.right - p.margin - pet.x) : (leftOpen ? p.maxDist : pet.x - (bounds.left + p.margin));
        let avail = room(dir);
        if (avail < p.minDist) {
            // 前方没路就掉头走
            facing = facing === "right" ? "left" : "right";
            dir = -dir;
            avail = room(dir);
        }
        if (avail <= 0)
            return;
        const dist = Math.min(avail, Pet.rand(p.minDist, p.maxDist));
        moveLead.duration = p.leadSec * 1000;
        moveTravel.from = pet.x;
        moveTravel.to = pet.x + dir * dist;
        moveTravel.duration = Math.max(100, (dur - p.leadSec - p.tailSec) * 1000);
        moveAnim.restart();
    }

    Connections {
        target: sprite

        function onStarted(name) {
            if (win.kind === "move" && win.pendingMove) {
                win.startMove(win.pendingMove);
                win.pendingMove = null;
            }
        }

        function onFinished(name) {
            switch (win.kind) {
            case "turn":
                win.facing = win.facing === "right" ? "left" : "right";
                break;
            case "sleepStart":
                win.playAnim(Pet.SLEEP.loop, "sleepLoop", true);
                return;
            case "sleepEnd":
                win.mode = "auto";
                break;
            }
            if (win.mode === "auto")
                win.nextAuto();
        }
    }

    // 走到一半换屏后，剩下的路程用它接着走
    NumberAnimation {
        id: moveCont
        target: pet
        property: "x"
        easing.type: Easing.Linear
    }

    SequentialAnimation {
        id: moveAnim
        PauseAnimation {
            id: moveLead
        }
        NumberAnimation {
            id: moveTravel
            target: pet
            property: "x"
            easing.type: Easing.Linear
        }
    }

    // ---------------------------------------------------------------- 物理

    FrameAnimation {
        running: win.mode === "fly" && win.visible
        onTriggered: {
            const dt = Math.min(frameTime, Pet.PHYSICS.maxStepDt);
            const r = Pet.flightStep({
                x: pet.x,
                y: pet.y,
                vx: win.vx,
                vy: win.vy
            }, dt, win.softBounds, Pet.PHYSICS.gravity, Pet.PHYSICS.restitution, Pet.PHYSICS.groundFriction);
            pet.x = r.s.x;
            pet.y = r.s.y;
            win.vx = r.s.vx;
            win.vy = r.s.vy;
            if (Math.abs(win.vx) > 30)
                win.facing = win.vx > 0 ? "right" : "left";
            win.checkHandoff();
            if (r.impact > 300)
                win.squash(Pet.landingSquash(r.impact));
            if (r.atRest) {
                win.mode = "auto";
                win.playAnim(Pet.IDLE, "idle", false);
            }
        }
    }

    property real squashDepth: Pet.SQ_SQUASH
    property real squashU: 1

    function squash(depth) {
        squashDepth = depth;
        squashAnim.restart();
    }

    NumberAnimation {
        id: squashAnim
        target: win
        property: "squashU"
        from: 0
        to: 1
        duration: Pet.SQ_DURATION_MS
    }

    // ---------------------------------------------------------------- 画面

    Item {
        id: pet
        width: win.petW
        height: win.petH
        x: 0
        y: 0
        onXChanged: if (moveAnim.running || moveCont.running) win.checkHandoff()

        PetSprite {
            id: sprite
            anchors.fill: parent
            mirrored: win.facing === "right" && !Pet.noMirror(current)
            squashY: win.squashU >= 1 ? 1 : Pet.squashScale(win.squashU, win.squashDepth)
        }

        // 身体命中区：只有这一块吃鼠标
        MouseArea {
            id: hitArea
            x: win.hx0
            y: win.hy0
            width: win.hx1 - win.hx0
            height: win.hy1 - win.hy0
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

            property bool pressedLeft: false
            property bool dragging: false
            property point pressG
            property point grabOff
            property var trail: []

            function g(mouse) {
                return mapToItem(win.contentItem, mouse.x, mouse.y);
            }

            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) {
                    const p = g(mouse);
                    menu.openAt(p.x, p.y);
                    return;
                }
                menu.close();
                pressedLeft = true;
                dragging = false;
                pressG = g(mouse);
                grabOff = Qt.point(pressG.x - pet.x, pressG.y - pet.y);
                trail = [{
                        x: pressG.x,
                        y: pressG.y,
                        t: Date.now()
                    }];
            }

            onPositionChanged: mouse => {
                if (!pressedLeft)
                    return;
                const p = g(mouse);
                if (!dragging) {
                    if (Math.hypot(p.x - pressG.x, p.y - pressG.y) < Pet.PHYSICS.dragThreshold)
                        return;
                    if (win.mode === "sleep")
                        return;
                    dragging = true;
                    win.stopMotion();
                    win.mode = "drag";
                    win.playAnim(Pet.DRAG, "drag", true);
                }
                pet.x = win.clampX(p.x - grabOff.x);
                pet.y = Math.max(win.bounds.top, Math.min(win.bounds.bottom, p.y - grabOff.y));
                const now = Date.now();
                trail.push({
                    x: p.x,
                    y: p.y,
                    t: now
                });
                while (trail.length > 2 && now - trail[0].t > 200)
                    trail.shift();
            }

            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton || !pressedLeft)
                    return;
                pressedLeft = false;
                if (!dragging) {
                    win.onClicked();
                    return;
                }
                dragging = false;
                const v = Pet.releaseVelocity(trail, Date.now());
                win.vx = v.vx;
                win.vy = v.vy;
                win.mode = "fly";
            }

            onCanceled: {
                if (dragging) {
                    dragging = false;
                    win.vx = 0;
                    win.vy = 0;
                    win.mode = "fly";
                }
                pressedLeft = false;
            }
        }
    }

    // ---------------------------------------------------------------- 气泡

    function say(text) {
        bubbleText.text = text;
        bubble.opacity = 1;
        bubbleTimer.interval = Math.max(4000, Math.min(12000, 2500 + text.length * 180));
        bubbleTimer.restart();
    }

    // ---------------------------------------------------------------- AI：碎碎念 / 对话

    function keyFilePath(spec) {
        const k = (spec || "").trim();
        return k.startsWith("file:") ? k.slice(5).trim().replace(/^~(?=\/)/, Quickshell.env("HOME")) : "";
    }

    function resolveKey(spec, fileView) {
        const k = (spec || "").trim();
        if (k.startsWith("env:"))
            return (Quickshell.env(k.slice(4).trim()) || "").trim();
        if (k.startsWith("file:"))
            return fileView.loaded ? fileView.text().trim() : "";
        return k;
    }

    readonly property string resolvedKey: resolveKey(aiApiKey, keyFile)
    readonly property bool aiLocal: /^https?:\/\/(localhost|127\.|\[::1\])/.test(aiBaseUrl.trim())
    readonly property bool aiReady: aiBaseUrl.trim() !== "" && aiModel.trim() !== "" && (resolvedKey !== "" || aiLocal)
    readonly property var aiCfg: ({
            baseUrl: aiBaseUrl,
            apiKey: resolvedKey,
            model: aiModel
        })
    readonly property var actionNames: {
        let all = [];
        for (const c of Pet.CATEGORIES)
            all = all.concat(c.actions);
        return all;
    }

    FileView {
        id: keyFile
        path: win.keyFilePath(win.aiApiKey)
        blockLoading: true
        printErrors: false
    }

    property var pending: null       // 进行中的请求 { cancel() }
    property bool busy: pending !== null
    property string lastWhisper: ""
    property string lastError: ""

    function request(messages, cb) {
        if (pending)
            pending.cancel("被新的请求顶掉了");
        let handle = null;
        handle = AI.complete(aiCfg, messages, (err, text) => {
            if (pending === handle) {
                pending = null;
                aiTimeout.stop();
            }
            lastError = err || "";
            cb(err, text);
        });
        pending = handle;
        aiTimeout.restart();
    }

    Timer {
        id: aiTimeout
        interval: 30000
        onTriggered: if (win.pending) win.pending.cancel("请求超时（30 秒）")
    }

    function playWhisperAnim() {
        if (mode !== "auto" || kind === "move" || kind === "drag")
            return;
        stopMotion();
        playAnim(Pet.pick(Pet.WHISPER_ANIMS), "action", false);
    }

    function whisper() {
        if (mode === "sleep" || mode === "drag" || busy)
            return;
        if (!aiReady) {
            lastWhisper = Pet.pick(AI.OFFLINE_WHISPERS);
            say(lastWhisper);
            playWhisperAnim();
            return;
        }
        request(AI.whisperMessages(persona, petName), (err, text) => {
            if (err || !text || mode === "sleep")
                return;
            lastWhisper = text.split("\n")[0];
            say(lastWhisper);
            playWhisperAnim();
        });
    }

    Timer {
        interval: Math.max(30, win.whisperIntervalSec) * 1000
        repeat: true
        running: win.whisperEnabled && win.visible
        onTriggered: if (win.mode === "auto" && !chat.visible) win.whisper()
    }

    // [{role, content, t, action?}]
    property var history: []

    FileView {
        id: historyFile
        path: Quickshell.statePath("duxPet-chat.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const h = JSON.parse(text());
                if (Array.isArray(h))
                    win.history = h;
            } catch (e) {}
        }
    }

    function saveHistory() {
        historyFile.setText(JSON.stringify(history.slice(-200)));
    }

    function pushHistory(msg) {
        history = history.concat([msg]);
    }

    function sendChat(text) {
        text = (text || "").trim();
        if (!text || busy)
            return false;
        if (mode === "sleep") {
            say(Pet.pick(Pet.SLEEP_REFUSE_TEXTS));
            return false;
        }
        if (!aiReady) {
            pushHistory({ role: "note", content: "还没配置 AI 接口：插件设置里填 API 地址和模型。", t: Date.now() });
            return false;
        }
        const msgs = AI.chatMessages(persona, petName, history.filter(h => h.role !== "note"), chatMemoryRounds, text, chatAnimationEnabled ? actionNames : []);
        pushHistory({ role: "user", content: text, t: Date.now() });
        request(msgs, (err, reply) => {
            if (err) {
                pushHistory({ role: "note", content: "出错了：" + err, t: Date.now() });
                return;
            }
            const r = AI.parseAction(reply, chatAnimationEnabled ? actionNames : []);
            pushHistory({ role: "assistant", content: r.text, action: r.action, t: Date.now() });
            saveHistory();
            if (!chat.visible)
                say(r.text);
            if (r.action && mode === "auto") {
                stopMotion();
                playAnim(r.action, "action", false);
            }
        });
        return true;
    }

    function openChat() {
        if (mode === "sleep") {
            say(Pet.pick(Pet.SLEEP_REFUSE_TEXTS));
            return;
        }
        stopMotion();
        chat.visible = true;
        chatInput.forceActiveFocus();
    }

    function clearHistory() {
        history = [];
        saveHistory();
    }

    // ---------------------------------------------------------------- 余额

    FileView {
        id: balanceKeyFile
        path: win.keyFilePath(win.balanceApiKey)
        blockLoading: true
        printErrors: false
    }

    readonly property string balanceProviderId: balanceProvider === "auto" ? Balance.guessProvider(aiBaseUrl) : (balanceProvider === "off" ? "" : balanceProvider)
    readonly property string balanceKey: balanceApiKey.trim() !== "" ? resolveKey(balanceApiKey, balanceKeyFile) : resolvedKey
    readonly property bool balanceReady: balanceProviderId !== "" && !!Balance.PROVIDERS[balanceProviderId] && balanceKey !== ""
    property var lastBalance: null      // parse() 的结果 + { at }
    property var balancePending: null

    // announce: true = 弹气泡 + 播档位动画（睡着时不打扰）
    function checkBalance(announce) {
        if (!balanceReady) {
            if (announce)
                say(balanceProviderId === "" ? "不知道去哪查余额：插件设置里选一下服务商吧。" : "查余额需要 API Key，在插件设置里填一下吧。");
            return false;
        }
        if (balancePending)
            balancePending.cancel();
        const prov = Balance.PROVIDERS[balanceProviderId];
        const base = (balanceBaseUrl.trim() || prov.base).replace(/\/+$/, "");
        const id = balanceProviderId;
        let handle = null;
        handle = AI.getJson(base + prov.path, balanceKey, (err, body) => {
            if (balancePending === handle) {
                balancePending = null;
                balanceTimeout.stop();
            }
            const r = err ? { ok: false, error: err } : Balance.parse(id, body, balanceFull, new Date());
            r.at = Date.now();
            r.provider = id;
            lastBalance = r;
            if (!announce || mode === "sleep" || mode === "drag")
                return;
            say(Balance.bubbleText(r, petName));
            const anim = Balance.animFor(r);
            if (anim && mode === "auto" && kind !== "move" && !chat.visible && !todoPanel.visible) {
                stopMotion();
                playAnim(anim, "action", false);
            }
        });
        balancePending = handle;
        balanceTimeout.restart();
        return true;
    }

    Timer {
        id: balanceTimeout
        interval: 20000
        onTriggered: if (win.balancePending) win.balancePending.cancel("查询超时")
    }

    Timer {
        interval: Math.max(300, win.balanceIntervalSec) * 1000
        repeat: true
        running: win.balanceAuto && win.balanceReady
        onTriggered: win.checkBalance(win.mode === "auto")
    }

    // ---------------------------------------------------------------- 梦话

    function sleepTalk() {
        if (mode !== "sleep" || kind !== "sleepLoop" || busy)
            return;
        if (!aiReady) {
            say(Pet.pick(Pet.OFFLINE_SLEEP_TALKS));
            return;
        }
        request(AI.whisperMessages(persona, petName, Pet.SLEEP_TALK_INSTRUCTION), (err, text) => {
            if (!err && text && mode === "sleep")
                say(text.split("\n")[0]);
        });
    }

    Timer {
        interval: Math.max(20, win.sleepTalkSec) * 1000
        repeat: true
        running: win.sleepTalkEnabled && win.mode === "sleep"
        onTriggered: win.sleepTalk()
    }

    // ---------------------------------------------------------------- 待办

    // [{id, text, due(ms, 0=不限时), created, lastRemind, dueFired}]
    property var todos: []
    readonly property var sortedTodos: todos.slice().sort((a, b) => (a.due || 9e15) - (b.due || 9e15) || a.created - b.created)

    FileView {
        id: todoFile
        path: Quickshell.statePath("duxPet-todos.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const t = JSON.parse(text());
                if (Array.isArray(t))
                    win.todos = t;
            } catch (e) {}
        }
    }

    function saveTodos() {
        todoFile.setText(JSON.stringify(todos));
    }

    function addTodo(input) {
        const r = Pet.parseTodo(input, Date.now());
        if (!r.text)
            return false;
        const now = Date.now();
        todos = todos.concat([{
                id: now + "_" + Math.floor(Math.random() * 1e6),
                text: r.text,
                due: r.due,
                created: now,
                lastRemind: now,
                dueFired: false
            }]);
        saveTodos();
        if (mode !== "sleep") {
            say("记下啦：「" + r.text + "」" + (r.due ? " " + Pet.fmtDue(r.due, now) : ""));
            if (mode === "auto" && kind !== "move" && !chat.visible) {
                stopMotion();
                playAnim(Pet.TODO_ANIM, "action", false);
            }
        }
        return true;
    }

    function removeTodo(id) {
        todos = todos.filter(t => t.id !== id);
        saveTodos();
    }

    function completeTodo(id) {
        const t = todos.find(x => x.id === id);
        if (!t)
            return;
        removeTodo(id);
        if (mode !== "sleep") {
            say("「" + t.text + "」完成啦，主人真棒！");
            squash(0.8);
        }
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Dux Pet", "-i", "alarm-symbolic", title, body]);
    }

    // 每 30 秒看一眼；一次只提醒最急的那条
    function checkTodos() {
        const now = Date.now();
        let changed = false;
        let spoken = false;
        for (const t of sortedTodos) {
            const remind = Pet.shouldRemind(t, now);   // 要在置 dueFired 之前算：到点那次靠它
            if (t.due && now >= t.due && !t.dueFired) {
                t.dueFired = true;
                changed = true;
                if (todoNotify)
                    notify(petName + " 提醒你", t.text + "（" + Pet.fmtDue(t.due, now) + " 到期）");
            }
            if (spoken || mode === "sleep" || mode === "drag" || !remind)
                continue;
            t.lastRemind = now;
            changed = true;
            spoken = true;
            say(Pet.remindText(t, now));
            if (mode === "auto" && kind !== "move" && !chat.visible && !todoPanel.visible) {
                stopMotion();
                playAnim(Pet.TODO_ANIM, "action", false);
            }
        }
        if (changed) {
            todos = todos.slice();
            saveTodos();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: win.todos.length > 0
        onTriggered: win.checkTodos()
    }

    function openTodos() {
        stopMotion();
        todoPanel.open();
    }

    Rectangle {
        id: bubble
        opacity: 0
        visible: opacity > 0
        width: Math.min(260, bubbleText.implicitWidth + 24)
        height: bubbleText.implicitHeight + 14
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.color: Theme.outlineVariant
        border.width: 1
        x: Math.max(4, Math.min(win.sw - width - 4, pet.x + (win.hx0 + win.hx1) / 2 - width / 2))
        y: Math.max(4, pet.y + win.hy0 - height - 6)

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }

        Text {
            id: bubbleText
            anchors.centerIn: parent
            width: Math.min(236, implicitWidth)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
        }

        Timer {
            id: bubbleTimer
            interval: 4000
            onTriggered: bubble.opacity = 0
        }
    }

    // ---------------------------------------------------------------- 聊天框

    Rectangle {
        id: chat
        visible: false
        width: 340
        height: 320
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1
        // 跟着宠物，放在头顶，放不下就放旁边
        x: Math.max(8, Math.min(win.sw - width - 8, pet.x + (win.hx0 + win.hx1) / 2 - width / 2))
        y: {
            const above = pet.y + win.hy0 - height - 8;
            return above >= 8 ? above : Math.max(8, Math.min(win.sh - height - 8, pet.y + win.hy0));
        }

        function close() {
            visible = false;
        }

        // 吃掉面板内的点击，别穿到下面
        MouseArea {
            anchors.fill: parent
            onPressed: chatInput.forceActiveFocus()
        }

        Item {
            id: chatHeader
            x: 12
            y: 6
            width: parent.width - 24
            height: 30

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.petName + (win.busy ? "  正在输入…" : "")
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: [
                        { label: "清空", act: () => win.clearHistory() },
                        { label: "✕", act: () => chat.close() }
                    ]

                    Rectangle {
                        required property var modelData
                        width: hdrText.implicitWidth + 14
                        height: 24
                        radius: 12
                        color: hdrMouse.containsMouse ? Theme.primaryHover : "transparent"

                        Text {
                            id: hdrText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: hdrMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.act()
                        }
                    }
                }
            }
        }

        ListView {
            id: chatList
            x: 10
            y: chatHeader.y + chatHeader.height + 4
            width: parent.width - 20
            height: inputBox.y - y - 8
            clip: true
            spacing: 6
            model: win.history.slice(-40)
            onCountChanged: Qt.callLater(positionViewAtEnd)
            onVisibleChanged: if (visible) Qt.callLater(positionViewAtEnd)

            delegate: Item {
                required property var modelData
                readonly property bool mine: modelData.role === "user"
                readonly property bool note: modelData.role === "note"
                width: chatList.width
                height: msgBg.height

                Rectangle {
                    id: msgBg
                    anchors.right: mine ? parent.right : undefined
                    anchors.left: mine ? undefined : parent.left
                    anchors.horizontalCenter: note ? parent.horizontalCenter : undefined
                    width: Math.min(parent.width * 0.82, msgText.implicitWidth + 20)
                    height: msgText.implicitHeight + 12
                    radius: Theme.cornerRadius
                    color: note ? "transparent" : mine ? Theme.primary : Theme.surfaceContainerHigh

                    Text {
                        id: msgText
                        x: 10
                        y: 6
                        width: Math.min(chatList.width * 0.82 - 20, implicitWidth)
                        text: modelData.content + (modelData.action ? "  〔" + modelData.action + "〕" : "")
                        wrapMode: Text.Wrap
                        color: note ? Theme.surfaceVariantText : mine ? Theme.primaryText : Theme.surfaceText
                        font.pixelSize: note ? Theme.fontSizeSmall : Theme.fontSizeMedium
                    }
                }
            }
        }

        Rectangle {
            id: inputBox
            x: 10
            y: parent.height - height - 10
            width: parent.width - 20
            height: 38
            radius: height / 2
            color: Theme.surfaceContainerHigh
            border.color: chatInput.activeFocus ? Theme.primary : Theme.outlineVariant
            border.width: 1

            TextInput {
                id: chatInput
                x: 14
                width: parent.width - 28 - sendBtn.width
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                clip: true
                readOnly: win.busy
                selectByMouse: true

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chatInput.text === "" && !chatInput.inputMethodComposing
                    text: win.aiReady ? "和" + win.petName + "说点什么…（回车发送，Esc 关闭）" : "先在插件设置里配置 AI 接口"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Keys.onReturnPressed: send()
                Keys.onEnterPressed: send()
                Keys.onEscapePressed: chat.close()

                function send() {
                    if (win.sendChat(text))
                        text = "";
                }
            }

            Rectangle {
                id: sendBtn
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 15
                color: win.busy ? Theme.surfaceVariantText : Theme.primary

                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: Theme.primaryText
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chatInput.send()
                }
            }
        }
    }

    // 头顶的待办小牌：显示条数和最近一条，点它打开待办
    Rectangle {
        id: todoChip
        visible: win.todos.length > 0 && !todoPanel.visible && win.mode !== "drag"
        width: chipText.implicitWidth + 16
        height: 22
        radius: 11
        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
        border.color: Theme.outlineVariant
        border.width: 1
        x: Math.max(4, Math.min(win.sw - width - 4, pet.x + (win.hx0 + win.hx1) / 2 - width / 2))
        y: Math.max(4, pet.y + win.hy0 - height - 4 - (bubble.visible ? bubble.height + 4 : 0))

        Text {
            id: chipText
            anchors.centerIn: parent
            readonly property var first: win.sortedTodos[0]
            text: "待办 " + win.todos.length + (first ? " · " + (first.text.length > 8 ? first.text.slice(0, 8) + "…" : first.text) + (first.due ? " " + Pet.fmtDue(first.due) : "") : "")
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: win.openTodos()
        }
    }

    TodoPanel {
        id: todoPanel
        win: win
        x: Math.max(8, Math.min(win.sw - width - 8, pet.x + (win.hx0 + win.hx1) / 2 - width / 2))
        y: {
            const above = pet.y + win.hy0 - height - 8;
            return above >= 8 ? above : Math.max(8, Math.min(win.sh - height - 8, pet.y + win.hy0));
        }
    }

    // ---------------------------------------------------------------- 右键菜单

    // 菜单打开时整屏吃鼠标：点菜单外任意处关闭
    MouseArea {
        anchors.fill: parent
        visible: menu.visible
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
    }

    Rectangle {
        id: menu
        visible: false
        width: 180
        height: menuCol.implicitHeight + 12
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.color: Theme.outlineVariant
        border.width: 1

        function openAt(px, py) {
            x = Math.min(px, win.sw - width - 4);
            y = Math.min(py, win.sh - height - 4);
            visible = true;
        }

        function close() {
            visible = false;
        }

        readonly property var items: {
            const list = [
                {
                    label: "随便玩点什么",
                    act: () => {
                        if (win.mode === "sleep")
                            return win.say(Pet.pick(Pet.SLEEP_REFUSE_TEXTS));
                        win.stopMotion();
                        win.mode = "auto";
                        win.nextAuto();
                    }
                }
            ];
            for (const c of Pet.CATEGORIES)
                list.push({
                    label: "  " + c.id,
                    act: () => win.playCategory(c.id)
                });
            list.push({
                label: "聊聊天",
                act: () => win.openChat()
            });
            list.push({
                label: "说句话",
                act: () => win.whisper()
            });
            if (win.balanceProviderId !== "")
                list.push({
                    label: "查余额",
                    act: () => win.checkBalance(true)
                });
            list.push({
                label: "待办" + (win.todos.length ? "（" + win.todos.length + "）" : "…"),
                act: () => win.openTodos()
            });
            list.push({
                label: "转个身",
                act: () => win.turnAround()
            });
            list.push({
                label: win.sleeping ? "起来" : "睡觉",
                act: () => win.sleeping ? win.wakeUp() : win.goSleep()
            });
            list.push({
                label: win.roam ? "原地待着" : "自由走动",
                act: () => win.roam = !win.roam
            });
            list.push({
                label: "回到右下角",
                act: () => win.home()
            });
            if (win.allowedScreens.length > 1) {
                for (const sc of win.allowedScreens)
                    if (sc !== win.screen)
                        list.push({
                            label: "去 " + sc.name,
                            act: () => win.summon(sc)
                        });
            }
            return list;
        }

        Column {
            id: menuCol
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: menu.items

                Rectangle {
                    required property var modelData
                    width: menuCol.width
                    height: 32
                    radius: Theme.cornerRadius / 2
                    color: itemMouse.containsMouse ? Theme.primaryHover : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        text: modelData.label
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            menu.close();
                            modelData.act();
                        }
                    }
                }
            }
        }
    }

    // dms ipc call duxPet <fn> ...   （多屏时只有一个实例注册成功）
    IpcHandler {
        target: "duxPet"
        enabled: win.isPrimary

        function home(): string {
            win.home();
            return "ok";
        }
        function sleep(): string {
            win.goSleep();
            return "ok";
        }
        function wake(): string {
            win.wakeUp();
            return "ok";
        }
        function play(category: string): string {
            win.playCategory(category);
            return "ok";
        }
        function say(text: string): string {
            win.say(text);
            return "ok";
        }
        function toss(vx: real, vy: real): string {
            if (win.mode === "sleep")
                return "sleeping";
            win.stopMotion();
            win.vx = vx;
            win.vy = vy;
            win.mode = "fly";
            win.playAnim(Pet.DRAG, "drag", true);
            return "ok";
        }
        function whisper(): string {
            win.whisper();
            return win.aiReady ? "requested" : "offline: " + win.lastWhisper;
        }
        function chat(text: string): string {
            return win.sendChat(text) ? "sent" : "not sent";
        }
        function balance(): string {
            return win.checkBalance(true) ? "requested (" + win.balanceProviderId + ")" : "not ready";
        }
        function balanceState(): string {
            return JSON.stringify(win.lastBalance);
        }
        function todoAdd(text: string): string {
            if (!win.addTodo(text))
                return "empty";
            const t = win.todos[win.todos.length - 1];
            return t.text + (t.due ? " @ " + Pet.fmtDue(t.due) : " (不限时)");
        }
        function todoList(): string {
            return JSON.stringify(win.sortedTodos.map(t => ({
                id: t.id,
                text: t.text,
                due: t.due ? Pet.fmtDue(t.due) : "",
                lastRemind: t.lastRemind,
                dueFired: t.dueFired
            })));
        }
        function todoDone(id: string): string {
            win.completeTodo(id);
            return "ok";
        }
        function todoCheck(): string {
            win.checkTodos();
            return "ok";
        }
        function sleepTalk(): string {
            win.sleepTalk();
            return "ok";
        }
        function summon(name: string): string {
            const sc = win.allowedScreens.find(s => s.name === name);
            win.summon(sc || win.screen);
            return sc ? "ok" : "unknown screen, summoned here";
        }
        function openChat(): string {
            win.openChat();
            return "ok";
        }
        function state(): string {
            return JSON.stringify({
                name: win.petName,
                size: win.petSize,
                screen: win.screen ? win.screen.name : "",
                screens: win.allowedScreens.map(s => s.name),
                bubble: bubble.visible ? bubbleText.text : "",
                busy: win.busy,
                aiReady: win.aiReady,
                lastWhisper: win.lastWhisper,
                lastError: win.lastError,
                lastReply: (win.history.filter(h => h.role === "assistant").slice(-1)[0] || {}).content || "",
                lastAction: (win.history.filter(h => h.role === "assistant").slice(-1)[0] || {}).action || "",
                mode: win.mode,
                kind: win.kind,
                anim: sprite.current,
                facing: win.facing,
                x: Math.round(pet.x),
                y: Math.round(pet.y)
            });
        }
    }

    // ---------------------------------------------------------------- 启动

    Component.onDestruction: {
        if (Pet.registry.primary === win)
            Pet.registry.primary = null;
        Pet.registry.list = Pet.registry.list.filter(w => w !== win);
    }

    onIsPrimaryChanged: if (isPrimary) Pet.registry.primary = win

    Component.onCompleted: {
        Pet.registry.list = Pet.registry.list.concat([win]);
        if (isPrimary)
            Pet.registry.primary = win;
        Qt.callLater(keepInside);
        mode = "auto";
        playAnim(Pet.IDLE, "idle", false);
    }
}
