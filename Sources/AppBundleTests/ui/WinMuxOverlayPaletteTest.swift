@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

final class WinMuxOverlayPaletteTest: XCTestCase {
    func testProjectFrameBackgroundUsesSelectedProjectColor() {
        for preset in workspaceSidebarProjectColorPresets {
            let family = workspaceCanvasProjectThemeFamily(
                activeProjectId: "client",
                projectColors: ["client": preset.hex]
            )
            for theme in [AppearanceTheme.light, .dark] {
                let palette = WinMuxOverlayPalette(theme: theme, projectThemeFamily: family)
                assertSameColor(
                    NSColor(workspaceCanvasBackground(for: palette)),
                    GeistColorSystem.color(family!, .color1, theme: theme)
                )
            }
        }
    }

    func testPaletteCanBeBuiltFromSwiftUIColorScheme() {
        XCTAssertEqual(WinMuxOverlayPalette(colorScheme: .light).theme, .light)
        XCTAssertEqual(WinMuxOverlayPalette(colorScheme: .dark).theme, .dark)
    }

    func testBackgroundRolesMatchGeistExactly() {
        let expectations: [(AppearanceTheme, GeistBackgroundRole, CGFloat)] = [
            (.light, .primary, 1.00),
            (.light, .secondary, 0.98),
            (.dark, .primary, 0.04),
            (.dark, .secondary, 0.00),
        ]

        for (theme, role, white) in expectations {
            assertGray(GeistColorSystem.background(role, theme: theme), white)
        }
    }

    func testNamedTokenLayerExposesAppearanceSpecificValues() {
        assertGray(GeistColorTokens.background1Light.nsColor, 1.00)
        assertGray(GeistColorTokens.background2Dark.nsColor, 0.00)
        assertGray(GeistColorTokens.gray100Light.nsColor, 0.95)
        assertGray(GeistColorTokens.gray1000Dark.nsColor, 0.93)

        for family in WorkspaceSidebarProjectThemeFamily.allCases {
            for theme in [AppearanceTheme.light, .dark] {
                for step in GeistColorStep.allCases {
                    assertSameColor(
                        GeistColorSystem.color(family, step, theme: theme),
                        GeistColorTokens.color(family, step, theme: theme).nsColor
                    )
                }
            }
        }
    }

    func testEveryFamilyAndAppearanceResolvesAllSemanticRolesToExactSteps() {
        for family in WorkspaceSidebarProjectThemeFamily.allCases {
            for theme in [AppearanceTheme.light, .dark] {
                let palette = WinMuxOverlayPalette(theme: theme, projectThemeFamily: family)

                for state in GeistComponentState.allCases {
                    let expectedComponentBackground = state == .normal
                        ? GeistColorSystem.background(.primary, theme: theme)
                        : GeistColorSystem.color(family, state.step, theme: theme)
                    assertSameColor(
                        palette.componentBackgroundNSColor(state),
                        expectedComponentBackground
                    )
                }
                for state in GeistBorderState.allCases {
                    assertSameColor(
                        palette.geistBorderNSColor(state),
                        GeistColorSystem.color(family, state.step, theme: theme)
                    )
                }
                for state in GeistHighContrastState.allCases {
                    assertSameColor(
                        palette.highContrastBackgroundNSColor(state),
                        GeistColorSystem.color(family, state.step, theme: theme)
                    )
                }
                for role in GeistContentRole.allCases {
                    assertSameColor(
                        palette.contentNSColor(role),
                        GeistColorSystem.color(family, role.step, theme: theme)
                    )
                }
                for step in GeistColorStep.allCases {
                    XCTAssertEqual(
                        palette.colorNSColor(family, step).alphaComponent,
                        1,
                        accuracy: 0.001,
                        "\(family.rawValue) \(theme) \(step)"
                    )
                }
            }
        }
    }

    func testGrayFamilyUsesOpaqueSolidGrayInsteadOfGrayAlpha() {
        let expected: [AppearanceTheme: [CGFloat]] = [
            .light: [0.95, 0.92, 0.90, 0.92, 0.79, 0.66, 0.56, 0.49, 0.30, 0.09],
            .dark: [0.10, 0.12, 0.16, 0.18, 0.27, 0.53, 0.56, 0.49, 0.63, 0.93],
        ]

        for theme in [AppearanceTheme.light, .dark] {
            for (step, white) in zip(GeistColorStep.allCases, expected[theme].orDie()) {
                assertGray(GeistColorSystem.color(.gray, step, theme: theme), white)
            }
        }
    }

    func testTabRowBorderStatePriorityMatchesGeistSemantics() {
        XCTAssertNil(workspaceSidebarTabRowBorderRole(
            isSelected: false,
            isHovered: false,
            isActiveInteraction: false
        ))
        XCTAssertEqual(workspaceSidebarTabRowBorderRole(
            isSelected: true,
            isHovered: false,
            isActiveInteraction: false
        ), .color4)
        XCTAssertEqual(workspaceSidebarTabRowBorderRole(
            isSelected: true,
            isHovered: true,
            isActiveInteraction: false
        ), .color5)
        XCTAssertEqual(workspaceSidebarTabRowBorderRole(
            isSelected: true,
            isHovered: true,
            isActiveInteraction: true
        ), .color6)
    }

    func testRootSurfaceAlwaysUsesActiveThemeColorOne() {
        for theme in [AppearanceTheme.light, .dark] {
            let defaultGray = WinMuxOverlayPalette(theme: theme)
            assertSameColor(
                defaultGray.rootSurfaceNSColor,
                GeistColorSystem.color(.gray, .color1, theme: theme)
            )

            for family in WorkspaceSidebarProjectThemeFamily.allCases {
                let themed = WinMuxOverlayPalette(theme: theme, projectThemeFamily: family)
                assertSameColor(
                    themed.rootSurfaceNSColor,
                    GeistColorSystem.color(family, .color1, theme: theme)
                )
            }
        }
    }

    func testUnsetOrAchromaticProjectColorResolvesToGray() {
        XCTAssertEqual(WorkspaceSidebarProjectThemeFamily.resolve(configuredHex: nil), .gray)
        XCTAssertEqual(WorkspaceSidebarProjectThemeFamily.resolve(configuredHex: "#777777"), .gray)
    }

    func testAllEightProjectPresetsResolveToTheirNamedGeistFamily() {
        XCTAssertEqual(workspaceSidebarProjectColorPresets.count, 8)
        XCTAssertEqual(
            Set(workspaceSidebarProjectColorPresets.compactMap {
                WorkspaceSidebarProjectThemeFamily.resolve(configuredHex: $0.hex)
            }),
            Set(WorkspaceSidebarProjectThemeFamily.allCases)
        )
    }

    func testResizePreviewUsesDocumentedGeistRoles() {
        assertSameColor(ResizePreviewPalette.shadeFillNSColor, .clear)
        assertSameColor(ResizePreviewPalette.shadeStrokeNSColor, .white)
        for (appearance, theme) in [(NSAppearance.Name.aqua, AppearanceTheme.light), (.darkAqua, .dark)] {
            assertSameColor(
                resolvedColor(ResizePreviewPalette.fillNSColor, appearance: appearance),
                GeistColorSystem.color(.gray, .color7, theme: theme)
            )
            assertSameColor(
                resolvedColor(ResizePreviewPalette.strokeNSColor, appearance: appearance),
                GeistColorSystem.color(.gray, .color6, theme: theme)
            )
            assertSameColor(
                resolvedColor(ResizePreviewPalette.sourceFrameFillNSColor, appearance: appearance),
                GeistColorSystem.color(.gray, .color2, theme: theme)
            )
        }
    }

    func testUISourcesDoNotBypassGeistTokens() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = ["ui", "mouse", "sidebar_widgets"].map {
            repositoryRoot.appending(path: "Sources/AppBundle/\($0)")
        }
        let excludedFiles = Set([
            "GeistColorSystem.swift",
            "GeistColorTokens.swift",
            "WorkspaceSidebarColor.swift",
        ])
        let forbiddenFragments = [
            "winMuxOverlayForeground",
            "winMuxOverlayMutedForeground",
            "winMuxOverlayBackground",
            "winMuxOverlayCard",
            "winMuxOverlayContrastingFill",
            "winMuxOverlayShadow",
            "winMuxOverlayAttention",
            "winMuxOverlayDestructive",
            "winMuxOverlayAccent",
            "winMuxOverlayOnAccent",
            "withAlphaComponent(",
            "srgbRed:",
            "displayP3Red:",
            "Color.black",
            "Color.white",
            "Color.gray",
            "NSColor.black",
            "NSColor.white",
            ".shadow(",
        ]

        let manager = FileManager.default
        for root in sourceRoots {
            let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil).orDie()
            for case let file as URL in enumerator {
                guard file.pathExtension == "swift", !excludedFiles.contains(file.lastPathComponent) else { continue }
                let source = try String(contentsOf: file, encoding: .utf8)
                for fragment in forbiddenFragments {
                    XCTAssertFalse(source.contains(fragment), "\(file.path) bypasses Geist tokens with \(fragment)")
                }
            }
        }
    }

    func testSidebarPanelFrameUsesVisibleFrameAndExtraReserve() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 914)

        let frame = workspaceSidebarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: 480,
            extraTopReserveHeight: 0,
        )

        XCTAssertEqual(frame, NSRect(x: 0, y: 40, width: 480, height: 914))
    }

    func testSidebarPanelFrameCanSpanVisibleFrameForCanvasHost() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 914)

        let frame = workspaceSidebarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: visibleFrame.width,
            extraTopReserveHeight: 0,
        )

        XCTAssertEqual(frame, NSRect(x: 0, y: 40, width: 1512, height: 914))
    }

    func testBarSurfaceUsesMonochromeFillAndStroke() {
        for theme in [AppearanceTheme.light, .dark] {
            let palette = WinMuxOverlayPalette(theme: theme, projectThemeFamily: .blue)

            assertSameColor(
                NSColor(winMuxBarSurfaceFill(palette)),
                theme == .dark ? .black : .white
            )
            assertSameColor(
                NSColor(winMuxBarSurfaceStroke(palette)),
                theme == .dark ? .black : .white
            )
        }
    }

    func testGlassBarsUseExpandedDimensions() {
        XCTAssertEqual(WinMuxBarStyle.projectTabsBarContentHeight, 48)
        XCTAssertEqual(WinMuxBarStyle.projectBarHeight, 60)
        XCTAssertEqual(WinMuxBarStyle.workspaceTabContentHeight, 32)
        XCTAssertEqual(WinMuxBarStyle.workspaceBarHeight, 34)
        XCTAssertEqual(WinMuxBarStyle.dividerOpacity, 0.15)
        XCTAssertGreaterThan(menuBarWidgetFontSize, NSFont.menuBarFont(ofSize: 0).pointSize)
        XCTAssertEqual(WinMuxBarStyle.workspaceSelectedSegmentOpacity, 0.70)
        XCTAssertEqual(WinMuxBarStyle.windowSelectedSegmentOpacity, 0.80)
        XCTAssertEqual(WinMuxBarStyle.windowTabHoveredSegmentOpacity, 0.50)
        XCTAssertEqual(WinMuxBarStyle.windowTabDividerOpacity, 0.40)
        XCTAssertEqual(WinMuxBarStyle.windowBarStrokeOpacity, 0.45)
        XCTAssertEqual(WinMuxBarStyle.windowBarBackdropSaturation, 0)
        XCTAssertEqual(WinMuxGlassStyle.clear.recipe.blurOpacity, 1)
        XCTAssertEqual(WinMuxGlassStyle.clear.recipe.whiteTintOpacity, 0.20)
        XCTAssertEqual(WinMuxBarStyle.workspaceBarStrokeOpacity, 1)
        assertSameColor(NSColor(WinMuxBarStyle.workspaceBarStrokeColor), .white)
        XCTAssertEqual(WinMuxGlassStyle.workspaceBar.surfaceOpacity, 0.50)
        XCTAssertEqual(WinMuxGlassStyle.windowBar.surfaceOpacity, 1)
        XCTAssertEqual(WinMuxBarStyle.workspaceTabUnfocusedTextOpacity, 0.50)
        XCTAssertEqual(WinMuxBarStyle.windowTabUnfocusedTextOpacity, 0.50)
        XCTAssertEqual(WinMuxGlassStyle.workspaceBar.recipe.blurOpacity, 1)
        XCTAssertEqual(WinMuxGlassStyle.workspaceBar.recipe.whiteTintOpacity, 0.60)
        XCTAssertEqual(WinMuxGlassStyle.workspaceBar.recipe.shadowOpacity, 0.12)
        XCTAssertEqual(WinMuxGlassStyle.workspaceBar.recipe.shadowRadius, WinMuxSpacing.regular)
        XCTAssertEqual(WinMuxGlassStyle.workspaceBar.recipe.shadowY, WinMuxSpacing.hairline)
        XCTAssertEqual(WinMuxBarStyle.workspaceBarShadowOutset, WinMuxSpacing.section)
        XCTAssertEqual(WinMuxGlassStyle.windowBar.recipe.blurOpacity, 0.25)
        XCTAssertEqual(WinMuxGlassStyle.windowBar.recipe.whiteTintOpacity, 0.25)
        XCTAssertEqual(WinMuxGlassStyle.regular.recipe.blurOpacity, 1)
        XCTAssertEqual(WinMuxGlassStyle.regular.recipe.whiteTintOpacity, 0.28)
        XCTAssertGreaterThan(workspaceSidebarWorkspaceActivityRevealDuration, 1)
    }

    func testMenuBarUsesCurrentAppearanceWithoutReversingTheme() {
        XCTAssertEqual(
            menuBarStatusWidgetPalette(colorScheme: .light, projectThemeFamily: .blue).theme,
            .light
        )
        XCTAssertEqual(
            menuBarStatusWidgetPalette(colorScheme: .dark, projectThemeFamily: .blue).theme,
            .dark
        )
    }

    func testSidebarSideAreaVisualFrameIsInsetWithinHostFrame() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard
        let hostFrame = NSRect(x: 0, y: 40, width: 490, height: 914)

        let visualFrame = metrics.visualSidebarFrame(in: hostFrame, visibleWidth: 240)

        XCTAssertEqual(visualFrame, NSRect(x: 8, y: 48, width: 240, height: 898))
    }

    func testSidebarSideAreaBackgroundFrameUsesCurrentVisibleWidthWhenFolded() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard
        let hostFrame = NSRect(x: 0, y: 40, width: 510, height: 914)

        let backgroundFrame = metrics.sideAreaBackgroundFrame(
            in: hostFrame,
            visibleWidth: 44,
            expandedWidth: 250
        )

        XCTAssertEqual(backgroundFrame, NSRect(x: 0, y: 40, width: 60, height: 914))
    }

    func testSidebarSideAreaBackgroundFrameFillsExpandedSideArea() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard
        let hostFrame = NSRect(x: 0, y: 40, width: 510, height: 914)

        let backgroundFrame = metrics.sideAreaBackgroundFrame(
            in: hostFrame,
            visibleWidth: 250,
            expandedWidth: 250
        )

        XCTAssertEqual(backgroundFrame, NSRect(x: 0, y: 40, width: 266, height: 914))
    }

    func testSidebarSideAreaEdgeTriggerStaysFlushToHostEdge() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard
        let hostFrame = NSRect(x: -1440, y: 145, width: 490, height: 875)

        let triggerFrame = metrics.edgeTriggerFrame(in: hostFrame)

        XCTAssertEqual(triggerFrame, NSRect(x: -1440, y: 145, width: 4, height: 875))
    }

    func testSidebarSideAreaReservationUsesExpandedWidthAndWindowGap() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard

        XCTAssertEqual(metrics.sideAreaReservation(expandedWidth: 240), 256)
    }

    func testWindowCanvasLeftInsetUsesStandardGapWhenFolded() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard

        XCTAssertEqual(metrics.windowCanvasLeftInset(visibleWidth: 44), 60)
    }

    func testWindowCanvasLeftInsetUsesStandardGapWhenExpanded() {
        let metrics = WorkspaceSidebarSideAreaMetrics.standard

        XCTAssertEqual(metrics.windowCanvasLeftInset(visibleWidth: 250), 266)
    }

    func testSidebarProtectedFrameRequiresSynchronousRepairWhenActualWindowOverlapsSidebar() {
        let target = Rect(topLeftX: 270, topLeftY: 10, width: 1240, height: 900)
        let overlapping = Rect(topLeftX: 250, topLeftY: 10, width: 1260, height: 900)

        XCTAssertTrue(shouldSynchronouslyApplySidebarProtectedFrame(
            sidebarInset: 250,
            actualRect: overlapping,
            targetRect: target
        ))
    }

    func testSidebarProtectedFrameDoesNotRewriteMatchingActualWindow() {
        let target = Rect(topLeftX: 270, topLeftY: 10, width: 1240, height: 900)

        XCTAssertFalse(shouldSynchronouslyApplySidebarProtectedFrame(
            sidebarInset: 250,
            actualRect: target,
            targetRect: target
        ))
    }

    func testSidebarProtectedFrameIsInactiveWithoutSidebarReservation() {
        let target = Rect(topLeftX: 10, topLeftY: 10, width: 1490, height: 900)

        XCTAssertFalse(shouldSynchronouslyApplySidebarProtectedFrame(
            sidebarInset: 0,
            actualRect: nil,
            targetRect: target
        ))
    }

    func testSidebarPanelFrameDoesNotDoubleCountMenuBarReserveAlreadyInVisibleFrame() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 914)

        let frame = workspaceSidebarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: 480,
            extraTopReserveHeight: 28,
        )

        XCTAssertEqual(frame, NSRect(x: 0, y: 40, width: 480, height: 914))
    }

    func testSidebarPanelFrameAppliesReserveBeyondVisibleFrameTopInset() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 914)

        let frame = workspaceSidebarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: 480,
            extraTopReserveHeight: 56,
        )

        XCTAssertEqual(frame, NSRect(x: 0, y: 40, width: 480, height: 886))
    }

    func testSidebarPanelFrameKeepsSecondaryMonitorCoordinates() {
        let screenFrame = NSRect(x: -1440, y: 120, width: 1440, height: 900)
        let visibleFrame = NSRect(x: -1432, y: 145, width: 1432, height: 875)

        let frame = workspaceSidebarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: 480,
            extraTopReserveHeight: 0,
        )

        XCTAssertEqual(frame, NSRect(x: -1432, y: 145, width: 480, height: 875))
    }

    func testSidebarPanelFrameClampsToAtLeastOnePointTall() {
        let screenFrame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let visibleFrame = NSRect(x: 0, y: 20, width: 100, height: 40)

        let frame = workspaceSidebarPanelFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            width: 400,
            extraTopReserveHeight: 1000,
        )

        XCTAssertEqual(frame.width, 100)
        XCTAssertEqual(frame.height, 1)
    }
}

private func relativeLuminance(_ color: NSColor) -> CGFloat {
    let rgb = color.usingColorSpace(.sRGB).orDie()
    return (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
}

private func rgbComponents(_ color: NSColor) -> [CGFloat] {
    let rgb = color.usingColorSpace(.sRGB).orDie()
    return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
}

private func resolvedColor(_ color: NSColor, appearance: NSAppearance.Name) -> NSColor {
    let appearance = NSAppearance(named: appearance).orDie()
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.sRGB)
    }
    return resolved.orDie()
}

private func assertGray(_ color: NSColor, _ expectedWhite: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    let rgb = color.usingColorSpace(.sRGB).orDie()
    XCTAssertEqual(rgb.redComponent, expectedWhite, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(rgb.greenComponent, expectedWhite, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(rgb.blueComponent, expectedWhite, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(rgb.alphaComponent, 1, accuracy: 0.001, file: file, line: line)
}

private func assertHex(_ color: NSColor, _ expectedRGB: UInt32, file: StaticString = #filePath, line: UInt = #line) {
    assertRGB(
        color,
        red: CGFloat((expectedRGB >> 16) & 0xFF) / 255,
        green: CGFloat((expectedRGB >> 8) & 0xFF) / 255,
        blue: CGFloat(expectedRGB & 0xFF) / 255,
        file: file,
        line: line
    )
}

private func assertSameColor(
    _ actual: NSColor,
    _ expected: NSColor,
    message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actualComponents = rgbComponents(actual)
    let expectedComponents = rgbComponents(expected)
    for (actualComponent, expectedComponent) in zip(actualComponents, expectedComponents) {
        XCTAssertEqual(
            actualComponent,
            expectedComponent,
            accuracy: 0.0001,
            message,
            file: file,
            line: line
        )
    }
}

private func assertRGB(
    _ color: NSColor,
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let rgb = color.usingColorSpace(.sRGB).orDie()
    XCTAssertEqual(rgb.redComponent, red, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(rgb.greenComponent, green, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(rgb.blueComponent, blue, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(rgb.alphaComponent, 1, accuracy: 0.001, file: file, line: line)
}
