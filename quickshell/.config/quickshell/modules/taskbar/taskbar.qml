import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQml

Instantiator {
    
    model: Quickshell.screens

    delegate: PanelWindow {
        id: root

        screen: modelData

        property color colBg: '#510c114a'
        property color colCyan: "#0db9d7"
        property color colBlue: "#7aa2f7"
        property color colPill: "#e0af68"
        property color colText: "#a9b1d6"
        property color colInactive: "#444b6a"
        property color colWhite: "#ffffff"
        property string fontFamily: "JetBrainsMono Nerd Font"
        property string iconFontFamily: "Font Awesome 7 Free"

        property string volumeVal: "0%"

        property double volFloat: 0.0 
        property bool showVolBar: false 
        property bool isMuted: false

        // Filtered list of actual application windows (not background processes)
        property var filteredApps: []
        property var lastFocusedIndex: ({})
        property var focusedApp: null
        property string nowPlayingTitle: ""
        property string nowPlayingArtist: ""
        property string nowPlayingStatus: ""

        function updateFilteredApps() {
            var apps = []
            var seenClasses = {}
            
            // Access toplevels
            var toplevels = Hyprland.toplevels.values || Hyprland.toplevels || []
            
            for (var i = 0; i < toplevels.length; i++) {
                var toplevel = toplevels[i]
                
                // Get app class from wayland object or extract from title
                var appClass = ""
                var waylandAppId = ""
                if (toplevel.wayland) {
                    var wayland = toplevel.wayland
                    waylandAppId = wayland.appId || wayland.class || ""
                }
                
                var title = toplevel.title || ""
                
                // Skip if no title (likely background process)
                if (!title || title === "") continue
                
                // Try to extract app name from title first (more reliable)
                if (title.includes("—")) {
                    var parts = title.split("—")
                    if (parts.length > 1) {
                        appClass = parts[parts.length - 1].trim().toLowerCase()
                        // Clean up common suffixes
                        appClass = appClass.replace(/\s+(browser|launcher|app)$/i, "")
                    }
                }
                
                // If no class from title, try wayland appId (but only if it's not a background process)
                if (!appClass || appClass === "") {
                    if (waylandAppId && waylandAppId !== "") {
                        var waylandLower = waylandAppId.toLowerCase()
                        // Only use wayland appId if it's not a known background process
                        if (waylandLower !== "electron" && 
                            !waylandLower.includes("ime") &&
                            !waylandLower.includes("input")) {
                            appClass = waylandLower
                        }
                    }
                }
                
                // If still no class, skip this window
                if (!appClass || appClass === "") continue
                
                // Filter out system processes and background services
                var skipClasses = [
                    "default ime", "ime", "input", "agent",
                    "electron", "waybar", "quickshell",
                    "fcitx", "ibus", "xwayland", "xwayland",
                    "desktop", "background"
                ]
                var shouldSkip = false
                var appClassLower = appClass.toLowerCase()
                for (var j = 0; j < skipClasses.length; j++) {
                    // Check if appClass contains or equals the skip pattern
                    if (appClassLower === skipClasses[j] || 
                        appClassLower.includes(skipClasses[j])) {
                        shouldSkip = true
                        break
                    }
                }
                if (shouldSkip) continue
                
                // Also skip if appClass is too short or looks like a system process
                if (appClass.length < 2) continue
                
                // Only add unique app classes (one entry per app type)
                // Store all instances for this app class so we can cycle through them
                if (!seenClasses[appClass]) {
                    seenClasses[appClass] = {
                        instances: [],
                        waylandAppId: waylandAppId  // Store wayland appId for icon lookup
                    }
                }
                seenClasses[appClass].instances.push(toplevel)
            }
            
            // Convert to array format with all instances per app
            var result = []
            for (var appClass in seenClasses) {
                var appData = seenClasses[appClass]
                result.push({
                    class: appClass,
                    instances: appData.instances,
                    waylandAppId: appData.waylandAppId
                })
            }
            
            filteredApps = result
        }
        
        function getIconSource(waylandAppId, appClass) {
            var lowerAppId = waylandAppId ? waylandAppId.toLowerCase() : ""
            var lowerClass = appClass ? appClass.toLowerCase() : ""
            if (lowerAppId.indexOf("cursor") !== -1 || lowerClass.indexOf("cursor") !== -1) {
                var cursorIcon = Quickshell.iconPath("co.anysphere.cursor")
                if (cursorIcon && cursorIcon !== "") {
                    return cursorIcon
                }
            }
            var keys = []
            if (waylandAppId && waylandAppId !== "") {
                keys.push(waylandAppId)
            }
            if (appClass && appClass !== "" && appClass !== waylandAppId) {
                keys.push(appClass)
            }
            for (var i = 0; i < keys.length; i++) {
                var iconPath = Quickshell.iconPath(keys[i])
                if (iconPath && iconPath !== "") {
                    return iconPath
                }
            }
            return ""
        }

        function getFocusedApp() {
            var toplevels = Hyprland.toplevels.values || Hyprland.toplevels || []
            for (var i = 0; i < toplevels.length; i++) {
                var t = toplevels[i]
                if (!t.activated)
                    continue
                var waylandAppId = ""
                var appClass = ""
                if (t.wayland) {
                    var w = t.wayland
                    waylandAppId = w.appId || w.class || ""
                    appClass = w.class || waylandAppId
                }
                var title = t.title || ""
                return {
                    title: title,
                    waylandAppId: waylandAppId,
                    appClass: appClass,
                    address: t.address,
                    workspace: t.workspace
                }
            }
            return null
        }

        Component.onCompleted: {
            updateFilteredApps()
            focusedApp = getFocusedApp()
        }
        
        // Update when toplevels change - try different approaches
        Connections {
            target: Hyprland
            function onToplevelsChanged() {
                root.updateFilteredApps()
                root.focusedApp = root.getFocusedApp()
            }
        }

        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 35
        color: colBg

        Timer {
            id: volHideTimer
            interval: 1000
            onTriggered: root.showVolBar = false
        }

        Timer {
            interval: 100
            running: true
            repeat: true
            onTriggered: volumeProc.running = true
        }

        Timer {
            interval: 500
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                root.updateFilteredApps()
                root.focusedApp = root.getFocusedApp()
            }
        }

        Process {
            id: volumeProc
            
            command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
            
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    
                    root.isMuted = data.includes("MUTED")
                    var match = data.match(/Volume:\s+([\d\.]+)/)
                    if (match) {
                        var val = parseFloat(match[1])
                        
                        if (Math.abs(val - root.volFloat) > 0.01 || root.isMuted !== (data.includes("MUTED"))) {
                            root.showVolBar = true
                            volHideTimer.restart()
                        }

                        root.volFloat = val
                    }
                }
            }
        }

        Process {
            id: nowPlayingProc
            command: ["playerctl", "metadata", "--format", "{{status}}|{{title}}|{{artist}}"]
            stdout: SplitParser {
                onRead: data => {
                    if (!data)
                        return
                    var parts = data.split("|")
                    root.nowPlayingStatus = parts.length > 0 ? parts[0] : ""
                    root.nowPlayingTitle = parts.length > 1 ? parts[1] : ""
                    root.nowPlayingArtist = parts.length > 2 ? parts[2] : ""
                }
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: nowPlayingProc.running = true
        }

        // appsContainer removed for now; apps will be surfaced via center pill and future control center

        Rectangle {
            id: workspaceContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 4
            width: workspaceRow.implicitWidth + 20
            height: 25
            radius: 15
            color: colPill
            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
            RowLayout {
                id: workspaceRow
                anchors.centerIn: parent
                Repeater {
                    model: 8
                    Rectangle {
                        id: workspaceBar
                        property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                        property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
                        implicitWidth: isActive? 30 : 15
                        implicitHeight: 15
                        radius: 10
                        opacity: isActive ? 1 : 0.2
                        Layout.leftMargin: 1
                        Layout.rightMargin: 1
                        color: colWhite
                        z: isActive ? 100 : 0
                        Text {
                            anchors.centerIn: parent
                            text: index + 1
                            color: colBg
                            font.family: fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }
                        Behavior on implicitWidth { 
                            NumberAnimation { 
                                duration: 200
                                easing.type: Easing.OutQuad 
                            } 
                        }
                        Behavior on color { 
                            ColorAnimation { duration: 200 } 
                        }
                        MouseArea { 
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch("workspace " + (index + 1))
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: centerAppContainer
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            height: 20
            radius: 0
            color: "transparent"
            visible: root.focusedApp !== null
            width: centerRow.implicitWidth + 20
            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
            RowLayout {
                id: centerRow
                anchors.centerIn: parent
                spacing: 6
                Image {
                    id: centerIcon
                    width: 11
                    height: 11
                    Layout.preferredWidth: 25
                    Layout.preferredHeight: 25
                    sourceSize.width: 25
                    sourceSize.height: 25
                    visible: source !== ""
                    source: root.focusedApp ? root.getIconSource(root.focusedApp.waylandAppId, root.focusedApp.appClass) : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Text {
                    text: root.focusedApp ? root.focusedApp.title : ""
                    color: colWhite
                    font.family: fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var app = root.focusedApp
                    if (!app)
                        return
                    if (app.address) {
                        Hyprland.dispatch("focuswindow address:" + app.address)
                    }
                    if (app.workspace) {
                        app.workspace.activate()
                    }
                }
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
            }
        }

        Rectangle {
            id: rightContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 4

            width: rightRowLayout.implicitWidth + 20
            height: 25

            color: "transparent"

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            RowLayout {
                id: rightRowLayout
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    id: nowPlayingContainer
                    height: 25
                    radius: 15
                    color: colPill
                    visible: root.nowPlayingStatus === "Playing" && root.nowPlayingTitle !== ""
                    property bool hovered: false
                    implicitWidth: hovered ? Math.min(220, nowPlayingRow.implicitWidth + 20) : 40
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    clip: true
                    Behavior on implicitWidth {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }
                    RowLayout {
                        id: nowPlayingRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "󰎈"
                            color: colWhite
                            font.family: fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            visible: nowPlayingContainer.hovered
                            text: root.nowPlayingTitle
                            color: colWhite
                            font.family: fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: nowPlayingContainer.hovered = true
                        onExited: nowPlayingContainer.hovered = false
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Rectangle {
                    id: clockContainer
                    width: clockRow.implicitWidth + 20
                    height: 25
                    radius: 15

                    color: colPill

                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }


                    RowLayout {
                        id: clockRow
                        anchors.centerIn: parent

                        SystemClock {
                            id: clock
                            precision: SystemClock.Seconds
                        }

                        Text {
                            text: Qt.formatDateTime(clock.date, "ddd d MMM hh:mm:ss")
                            color: colWhite
                            font { pixelSize: 14; bold: true; family: fontFamily; }
                        }
                    }
                }

                Rectangle {
                    id: volPill

                    implicitWidth: root.showVolBar ? 150 : 40
                    height: 25
                    radius: 15
                    
                    color: colPill
                    clip: true

                    Behavior on implicitWidth { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack } 
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: root.isMuted ? "" : (root.volFloat > 0.5 ? "" : (root.volFloat > 0 ? "" : ""))
                            color: colWhite
                            
                            font.family: fontFamily
                            font.pixelSize: 14
                        }

                        Rectangle {
                            id: barTrack
                            width: 100
                            height: 8
                            radius: 15
                            color: "#44000000"
                            
                            visible: root.showVolBar || volPill.implicitWidth > 40
                            opacity: root.showVolBar ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                
                                color: root.isMuted ? "#ff5555" : colWhite
                                
                                width: parent.width * root.volFloat
                                Behavior on width { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                    }
                }

                Rectangle {
                    id: connectionContainer
                    anchors.margins: 4
                    width: connectionIcon.implicitWidth + 20
                    height: 25
                    radius: 15

                    color: colPill

                    Text {
                        id: connectionIcon
                        anchors.centerIn: parent
                        text: ""
                        color: colWhite
                        font { pixelSize: 14; bold: true; family: fontFamily; }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // onClicked: Connection.toggle() // TODO: Add connection menu
                        cursorShape: Qt.PointingHandCursor

                        hoverEnabled: true
                    }
                }

                // Right Power
                Rectangle {
                    id: powerContainer
                    anchors.margins: 4
                    width: powerIcon.implicitWidth + 20
                    height: 25
                    radius: 15

                    color: colPill

                    Text {
                        id: powerIcon
                        anchors.centerIn: parent
                        text: ""
                        color: colWhite
                        font { pixelSize: 14; bold: true; family: fontFamily; }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // onClicked: Power.shutdown() TODO: Add power menu
                        cursorShape: Qt.PointingHandCursor

                        hoverEnabled: true
                    }
                }
            }
        }

        // now playing popup overlay removed; handled inline in nowPlayingContainer
    }
}
