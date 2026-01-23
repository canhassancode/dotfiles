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

        property string cpuVal: "0%"
        property string memVal: "0%"
        property string gpuVal: "0°C"
        property string tempVal: "0°C"
        property string volumeVal: "0%"

        property double volFloat: 0.0 
        property bool showVolBar: false 
        property bool isMuted: false

        property var lastTotal: 0
        property var lastIdle: 0

        // Filtered list of actual application windows (not background processes)
        property var filteredApps: []
        
        // Track last focused instance index per app (for cycling)
        property var lastFocusedIndex: ({})

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
        
        // Simple function to get icon - just use wayland appId directly
        function getIconSource(waylandAppId, appClass) {
            var lowerClass = appClass ? appClass.toLowerCase() : ""
            
            // Special case only for cursor
            if (lowerClass === "cursor") {
                var cursorIcon = Quickshell.iconPath("co.anysphere.cursor")
                if (cursorIcon && cursorIcon !== "") {
                    return cursorIcon
                }
            }
            
            // Use wayland appId if available (most reliable)
            if (waylandAppId && waylandAppId !== "") {
                var iconPath = Quickshell.iconPath(waylandAppId)
                if (iconPath && iconPath !== "") {
                    return iconPath
                }
            }
            
            // Try app class name
            if (appClass && appClass !== "") {
                var classIcon = Quickshell.iconPath(appClass)
                if (classIcon && classIcon !== "") {
                    return classIcon
                }
            }
            
            // Return empty to trigger fallback text (first letter)
            return ""
        }

        Component.onCompleted: updateFilteredApps()
        
        // Update when toplevels change - try different approaches
        Connections {
            target: Hyprland
            function onToplevelsChanged() { root.updateFilteredApps() }
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
            interval: 2000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                cpuProc.running = true
                memProc.running = true
                tempProc.running = true
                gpuProc.running = true
                root.updateFilteredApps()
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
            id: cpuProc
            command: ["sh", "-c", "head -1 /proc/stat"]
            
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    let lines = data.split("\n")
                    if (lines.length < 1) return
                    
                    var parts = lines[0].split(/\s+/)
                    var idle = parseInt(parts[4])
                    var total = 0
                    for (var i = 1; i < parts.length; i++) {
                        var val = parseInt(parts[i])
                        if (!isNaN(val)) total += val
                    }
                    
                    var diffIdle = idle - root.lastIdle
                    var diffTotal = total - root.lastTotal
                    var usage = (diffTotal > 0) ? (100 * (diffTotal - diffIdle) / diffTotal).toFixed(0) : "0"
                    
                    root.cpuVal = usage + "%"
                    root.lastIdle = idle
                    root.lastTotal = total
                }
            }

            Component.onCompleted: running = true
        }

        Process {
            id: memProc
            command: ["sh", "-c", "free | grep Mem"]
            
            stdout: SplitParser {
                onRead: data => {
                    if (!data ) return
                    let parts = data.trim().split(/\s+/)
                    let total = parseInt(parts[1])
                    let used = parseInt(parts[2])
                    
                    if (total > 0) {
                        root.memVal = Math.round(100 * used / total) + "%"
                    } 
                }
            }

            Component.onCompleted: running = true
        }

        Process {
            id: tempProc
            command: ["sh", "-c", "sensors k10temp-pci-00c3 | grep Tctl"]
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    var match = data.match(/\+(\d+\.\d+)/)
                    if (match) {
                        root.tempVal = Math.round(parseFloat(match[1])) + "°C"
                    }
                }
            }

            Component.onCompleted: running = true
        }

        Process {
            id: gpuProc
            command: ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader"]
            stdout: SplitParser {
                onRead: data => {
                    if (!data) return
                    if (data.trim() !== "") {
                        root.gpuVal = data.trim() + "°C"
                    }
                }
            }

            Component.onCompleted: running = true
        }

        Rectangle {
            id: leftContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 4
            
            width: statsRow.implicitWidth + 20 
            height: 25
            radius: 15
            color: colPill
            clip: true 

            Behavior on width { NumberAnimation { duration: 200 } }

            RowLayout {
                id: statsRow
                anchors.centerIn: parent
                spacing: 12

                RowLayout {
                    spacing: 4
                    Text { text: ""; color: colWhite; font.family: fontFamily }
                    Text { text: "CPU: " + root.cpuVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
                RowLayout {
                    spacing: 4
                    Text { text: ""; color: colWhite; font.family: fontFamily }
                    Text { text: "RAM: " + root.memVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
                RowLayout {
                    spacing: 4
                    Text { text: "󰢮"; color: colWhite; font.family: fontFamily }
                    Text { text: "GPU: " + root.gpuVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
                RowLayout {
                    spacing: 4
                    Text { text: ""; color: colWhite; font.family: fontFamily }
                    Text { text: "Temp: " + root.tempVal; color: colWhite; font.family: fontFamily; font.bold: true }
                }
            }
        }

        Rectangle {
            id: appsContainer
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: leftContainer.right
            anchors.leftMargin: 8
            anchors.margins: 4
            
            width: appsRow.implicitWidth + 20
            height: 25
            radius: 15
            color: colPill
            clip: true

            Behavior on width { NumberAnimation { duration: 200 } }

            RowLayout {
                id: appsRow
                anchors.centerIn: parent
                spacing: 8

                Repeater {
                    id: appsRepeater
                    model: root.filteredApps

                    Rectangle {
                        id: appPill
                        height: 20
                        width: 20
                        radius: 10
                        color: "transparent"

                        property var appData: modelData
                        property int instanceCount: appData ? appData.instances.length : 0
                        property string iconSource: appData ? root.getIconSource(appData.waylandAppId, appData.class) : ""

                        Image {
                            id: appIcon
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: appPill.iconSource
                            fillMode: Image.PreserveAspectFit
                            opacity: 1.0  // Full opacity for icon
                            smooth: true
                            antialiasing: true
                            asynchronous: false  // Load synchronously to catch errors faster
                            
                            // Fallback to text if icon not found or broken
                            onStatusChanged: {
                                if (status === Image.Error || status === Image.Null) {
                                    fallbackText.visible = true
                                    appIcon.visible = false
                                } else if (status === Image.Ready) {
                                    fallbackText.visible = false
                                    appIcon.visible = true
                                } else if (status === Image.Loading) {
                                    fallbackText.visible = false
                                    appIcon.visible = true
                                }
                            }
                        }
                        
                        // Fallback text if icon not available
                        Text {
                            id: fallbackText
                            anchors.centerIn: parent
                            visible: !appIcon.visible || appIcon.status === Image.Error
                            text: {
                                if (!appData) return "?"
                                var displayName = appData.class || "?"
                                // Show first letter if single instance, or count if multiple
                                if (instanceCount > 1) {
                                    return instanceCount.toString()
                                }
                                return displayName.charAt(0).toUpperCase()
                            }
                            color: colWhite
                            font.family: fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }
                        
                        // Badge for multiple instances
                        Rectangle {
                            visible: instanceCount > 1
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: -2
                            width: 8
                            height: 8
                            radius: 4
                            color: colPill
                            border.width: 1
                            border.color: colWhite
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!appData || !appData.instances || appData.instances.length === 0) return
                                
                                var appClass = appData.class
                                var instances = appData.instances
                                
                                // Get the last focused index for this app
                                var currentIndex = root.lastFocusedIndex[appClass]
                                
                                if (currentIndex === undefined) {
                                    // First click: find the currently active instance, or use first one
                                    currentIndex = 0
                                    for (var i = 0; i < instances.length; i++) {
                                        if (instances[i].activated) {
                                            currentIndex = i
                                            break
                                        }
                                    }
                                } else {
                                    // Subsequent clicks: cycle to the next instance
                                    currentIndex = (currentIndex + 1) % instances.length
                                }
                                
                                // Update the last focused index
                                root.lastFocusedIndex[appClass] = currentIndex
                                
                                // Get the instance to focus
                                var instance = instances[currentIndex]
                                
                                // Focus the window and switch to its workspace
                                if (instance.address) {
                                    Hyprland.dispatch("focuswindow address:" + instance.address)
                                }
                                if (instance.workspace) {
                                    instance.workspace.activate()
                                }
                            }
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: workspaceContainer
            anchors.centerIn: parent
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
    }
}
