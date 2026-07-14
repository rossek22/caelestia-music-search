import "media"
import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    property var searchedTrack: null
    readonly property bool searchedTrackMatches: {
        const activeTitle = (Players.active?.trackTitle ?? "").trim().toLowerCase();
        const selectedTitle = (searchedTrack?.title ?? "").trim().toLowerCase();
        return activeTitle.length > 0 && activeTitle === selectedTitle;
    }

    implicitWidth: Tokens.sizes.dashboard.mediaTabWidth
    implicitHeight: Tokens.sizes.dashboard.mediaTabHeight

    BackgroundShapes {
        anchors.fill: parent
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraLarge

        Item {
            Layout.fillHeight: true
            implicitWidth: Tokens.sizes.dashboard.mediaSectionWidth

            CoverVisualiser {
                anchors.fill: parent
            }

            MaterialShape {
                id: searchedArtworkMask

                anchors.centerIn: parent
                implicitSize: Tokens.sizes.dashboard.mediaCoverArtSize
                shape: MaterialShape.Cookie9Sided
                color: Colours.palette.m3surfaceContainerHighest
                visible: root.searchedTrackMatches && (root.searchedTrack?.artwork ?? "") !== ""
                layer.enabled: true

                Anim on rotation {
                    running: true
                    paused: !Players.active?.isPlaying
                    from: 360
                    to: 0
                    duration: 23500
                    easing.type: Easing.Linear
                    loops: Animation.Infinite
                }
            }

            Image {
                anchors.fill: searchedArtworkMask
                source: root.searchedTrackMatches ? (root.searchedTrack?.artwork ?? "") : ""
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(width * 2, height * 2)
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: Mask { maskSource: searchedArtworkMask }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            state: Players.active ? "" : "noMedia"

            states: State {
                name: "noMedia"
                PropertyChanges { noMedia.opacity: 1; content.opacity: 0 }
            }

            transitions: [
                Transition {
                    from: ""
                    SequentialAnimation {
                        Anim { target: content; property: "opacity"; type: Anim.DefaultEffects }
                        Anim { target: noMedia; property: "opacity"; type: Anim.SlowEffects }
                    }
                },
                Transition {
                    to: ""
                    SequentialAnimation {
                        Anim { target: noMedia; property: "opacity"; type: Anim.DefaultEffects }
                        Anim { target: content; property: "opacity"; type: Anim.SlowEffects }
                    }
                }
            ]

            Loader {
                id: noMedia

                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -Tokens.padding.extraLarge * 2
                asynchronous: true
                active: opacity > 0
                opacity: 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.small

                    MaterialShape {
                        Layout.topMargin: (pathBounds().height - implicitSize) / 2
                        Layout.bottomMargin: (pathBounds().height - implicitSize) / 2 + Tokens.spacing.small
                        Layout.alignment: Qt.AlignHCenter
                        color: Colours.palette.m3primaryContainer
                        implicitSize: icon.implicitHeight + Tokens.padding.extraLarge * 2
                        shape: MaterialShape.ClamShell

                        MaterialIcon {
                            id: icon
                            anchors.centerIn: parent
                            text: "queue_music"
                            fontStyle: Tokens.font.icon.builders.large.scale(2).build()
                            color: Colours.palette.m3onPrimaryContainer
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Nothing playing")
                        font: Tokens.font.headline.medium
                    }

                    StyledText {
                        text: qsTr("Play something for it to show up here!")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }
            }

            Loader {
                id: content

                anchors.fill: parent
                asynchronous: true
                active: opacity > 0

                sourceComponent: RowLayout {
                    spacing: Tokens.spacing.extraLarge

                    Details {
                        Layout.fillWidth: true
                        fallbackTrack: root.searchedTrack
                        onSearchRequested: initialText => searchOverlay.open(initialText)
                    }

                    LyricsAndSelector {
                        Layout.fillHeight: true
                        implicitWidth: Tokens.sizes.dashboard.mediaSectionWidth
                    }
                }
            }
        }
    }

    SearchOverlay {
        id: searchOverlay
        anchors.fill: parent
        onTrackPlayed: track => root.searchedTrack = track
    }
}
