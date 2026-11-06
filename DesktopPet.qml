import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "pet.js" as Pet

// 可选的桌面小窝：宠物本身由 PetDaemon 养，这里只是个遥控器。
// 左键把宠物叫到这块屏，中键睡觉/起来。不想要就别添加这个桌面小组件（或在设置里关掉「显示桌面小窝」）。
DesktopPluginComponent {
    id: root

    property var screen: null

    minWidth: 48
    minHeight: 48
    property real defaultWidth: 150
    property real defaultHeight: 56

    readonly property bool showHouse: (root.pluginData?.showHouse ?? true) !== false

    // 隐藏小窝时让这块区域点击穿透（Dux shell 读实例配置里的 clickThrough）
    function syncClickThrough() {
        if (!root.instanceId)
            return;
        const want = !root.showHouse;
        if ((root.instanceData?.config?.clickThrough ?? false) !== want)
            root.setData("clickThrough", want);
    }
    onShowHouseChanged: Qt.callLater(syncClickThrough)
    onInstanceIdChanged: Qt.callLater(syncClickThrough)
    Component.onCompleted: Qt.callLater(syncClickThrough)

    // 每块屏各一只时找本屏那只，否则找唯一的那只
    function currentPet() {
        const own = Pet.registry.list.find(w => w.screen === root.screen && w.allowedScreens.length === 1);
        return own || Pet.registry.primary;
    }

    property bool petSleeping: false
    property bool petAlive: false
    Timer {
        interval: 1000
        repeat: true
        running: root.showHouse
        triggeredOnStart: true
        onTriggered: {
            const p = root.currentPet();
            root.petAlive = !!p;
            root.petSleeping = !!(p && p.sleeping);
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.showHouse
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainer, 0.75)
        border.color: Theme.outlineVariant
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.petSleeping ? "bedtime" : "pets"
                size: Math.min(root.height * 0.5, 24)
                color: root.petAlive ? Theme.primary : Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.width > 90
                text: !root.petAlive ? "宠物没在跑" : root.petSleeping ? "睡觉中" : "叫回来"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                const p = root.currentPet();
                if (!p)
                    return;
                if (mouse.button === Qt.MiddleButton)
                    p.sleeping ? p.wakeUp() : p.goSleep();
                else
                    p.summon(root.screen);
            }
        }
    }
}
