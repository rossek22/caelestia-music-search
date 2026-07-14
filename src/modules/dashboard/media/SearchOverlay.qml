pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

Item {
    id: root

    signal trackPlayed(var track)

    property bool opened
    property bool loading
    property var results: []
    property SearchProvider provider: providers[0]

    readonly property list<SearchProvider> providers: [
        SearchProvider { text: "Spotify"; icon: "music_note"; key: "spotify" },
        SearchProvider { text: "YouTube Music"; icon: "smart_display"; key: "youtube" },
        SearchProvider { text: "Deezer"; icon: "headphones"; key: "deezer" }
    ]

    function open(initialText: string): void {
        query.text = initialText;
        results = [];
        opened = true;
        setKeyboardFocus(true);
        Qt.callLater(() => {
            query.forceActiveFocus();
            query.selectAll();
            if (query.text.trim().length >= 2)
                searchDelay.restart();
        });
    }

    function close(): void {
        searchProcess.running = false;
        searchDelay.stop();
        opened = false;
        loading = false;
        results = [];
        setKeyboardFocus(false);
    }

    function setKeyboardFocus(active: bool): void {
        const window = QsWindow.window;
        if (window)
            window.dashboardSearchActive = active; // qmllint disable missing-property
    }

    function runSearch(): void {
        const text = query.text.trim();
        if (text.length < 2) {
            results = [];
            loading = false;
            return;
        }
        searchProcess.running = false;
        searchProcess.command = ["python3", `${Quickshell.shellDir}/scripts/music_search.py`, "search", text, provider.key];
        loading = true;
        searchProcess.running = true;
    }

    function play(track): void {
        trackPlayed(track);
        const trackProvider = track.provider ?? provider.key;
        playProcess.command = [
            "python3", `${Quickshell.shellDir}/scripts/music_search.py`, "play",
            trackProvider, track.url, track.artist, track.title
        ];
        playProcess.running = true;
        close();
    }

    function prefetchResults(): void {
        if (results.length === 0)
            return;
        prefetchProcess.running = false;
        prefetchProcess.command = [
            "python3", `${Quickshell.shellDir}/scripts/music_search.py`, "prefetch",
            provider.key, JSON.stringify(results)
        ];
        prefetchProcess.running = true;
    }

    anchors.fill: parent
    visible: opacity > 0
    enabled: opened
    opacity: opened ? 1 : 0
    z: 100

    Component.onDestruction: setKeyboardFocus(false)

    Behavior on opacity {
        Anim { type: Anim.FastEffects }
    }

    StyledRect {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.42)

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    StyledRect {
        id: dialog

        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.opened ? 0 : Tokens.spacing.large
        implicitWidth: Math.max(1, root.width - Tokens.padding.extraLarge * 2)
        implicitHeight: Math.max(1, root.height - Tokens.padding.extraLarge * 2)
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        scale: root.opened ? 1 : 0.92

        Behavior on scale {
            Anim { type: Anim.Emphasized }
        }

        Behavior on anchors.verticalCenterOffset {
            Anim { type: Anim.Emphasized }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: event => event.accepted = true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHighest

                    MaterialIcon {
                        id: searchIcon

                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.verticalCenter: parent.verticalCenter
                        // Keep the glyph static. Stopping a rotating font glyph between
                        // frames left it rasterised at a random angle on some GPUs.
                        text: "search"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledTextField {
                        id: query

                        anchors.left: searchIcon.right
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Tokens.spacing.small
                        anchors.rightMargin: Tokens.padding.medium
                        placeholderText: qsTr("Track, artist or album")
                        font: Tokens.font.title.medium
                        verticalAlignment: TextInput.AlignVCenter

                        onTextEdited: {
                            root.results = [];
                            searchDelay.restart();
                        }
                        onAccepted: {
                            if (root.results.length > 0)
                                root.play(root.results[0]);
                            else
                                root.runSearch();
                        }

                        Keys.onEscapePressed: root.close()
                        Keys.onDownPressed: resultsList.forceActiveFocus()
                    }
                }

                SplitButton {
                    type: SplitButton.Tonal
                    active: root.provider
                    menuItems: root.providers
                    minLeftWidth: Math.min(120, root.width * 0.14)
                    horizontalPadding: Tokens.padding.small
                    verticalPadding: Tokens.padding.small
                    menu.onItemSelected: item => {
                        root.provider = item as SearchProvider;
                        root.results = [];
                        searchDelay.stop();
                        root.runSearch();
                    }
                }

                IconButton {
                    type: IconButton.Tonal
                    icon: "close"
                    isRound: true
                    onClicked: root.close()
                }
            }

            ListView {
                id: resultsList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Tokens.spacing.extraSmall
                model: root.results
                currentIndex: 0

                Keys.onEscapePressed: root.close()
                Keys.onReturnPressed: if (currentItem)
                    root.play(root.results[currentIndex])
                Keys.onEnterPressed: if (currentItem)
                    root.play(root.results[currentIndex])

                delegate: StyledRect {
                    id: resultItem

                    required property int index
                    required property var modelData

                    width: ListView.view.width
                    implicitHeight: 58
                    radius: Tokens.rounding.large
                    color: ListView.isCurrentItem ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainer

                    StateLayer {
                        radius: resultItem.radius
                        color: resultItem.ListView.isCurrentItem ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        onClicked: root.play(resultItem.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.extraSmall
                        spacing: Tokens.spacing.medium

                        Item {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48

                            StyledRect {
                                id: artworkMask
                                anchors.fill: parent
                                radius: Tokens.rounding.medium
                                color: Colours.palette.m3surfaceContainerHighest
                                layer.enabled: true
                            }

                            Image {
                                anchors.fill: parent
                                source: resultItem.modelData.artwork
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                layer.enabled: true
                                layer.effect: Mask { maskSource: artworkMask }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: resultItem.modelData.title
                                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `${resultItem.modelData.artist} · ${resultItem.modelData.album}`
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }
                        }

                        MaterialIcon {
                            text: "play_arrow"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.medium
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !root.loading && root.results.length === 0
                    text: query.text.trim().length < 2 ? qsTr("Type at least two characters") : qsTr("No tracks found")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.large
                }
            }
        }
    }

    Timer {
        id: searchDelay
        interval: 350
        onTriggered: root.runSearch()
    }

    Process {
        id: searchProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.query === query.text.trim() && data.provider === root.provider.key) {
                        root.loading = false;
                        root.results = data.results ?? [];
                    }
                } catch (error) {
                    root.loading = false;
                    root.results = [];
                }
            }
        }

        stderr: StdioCollector {}
    }

    Process {
        id: playProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    Process {
        id: prefetchProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    component SearchProvider: MenuItem {
        required property string key
        activeIcon: icon
    }
}
