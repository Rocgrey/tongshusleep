import XCTest
import SwiftUI
@testable import sleeptongshu

final class TemperaturePresentationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private func sample(_ day: Int, value: Double, device: String = "test-a", hour: Int = 12) -> WearableVital {
        WearableVital(device: device, deviceLabel: "测试设备", date: date(day, hour: hour), kind: .temperature, value: value, origin: "测试")
    }
    func testOneDeviceOnlyMissingDaysAndDuplicatesDoNotChangeTheMean() throws {
        let first = sample(1, value: 36)
        let input = [sample(3, value: 37), first, first, sample(2, value: 40, device: "test-b"), sample(3, value: 35, hour: 10)]
        let summary = TemperatureSummary(input, device: "test-a", now: date(4), calendar: calendar)
        XCTAssertEqual(summary.samples.count, 3)
        XCTAssertEqual(summary.days.count, 2)
        XCTAssertEqual(try XCTUnwrap(summary.mean), 36, accuracy: 0.0001)
        XCTAssertEqual(summary.days.last?.minimum, 35)
        XCTAssertEqual(summary.days.last?.maximum, 37)
        XCTAssertFalse(summary.days.contains { calendar.component(.day, from: $0.date) == 2 })
        XCTAssertTrue(TemperatureSummary(input, device: "absent", now: date(4), calendar: calendar).samples.isEmpty)
    }
    func testInvalidFutureAndOutOfRangeValuesStayOutAndNoRecordDoesNotBecomeZero() {
        var heart = sample(2, value: 65); heart.kind = .heart
        let input = [sample(1, value: .nan), sample(1, value: 0), sample(1, value: .infinity), sample(1, value: 46), sample(5, value: 36), sample(2, value: 36.4), heart]
        let summary = TemperatureSummary(input, now: date(4), calendar: calendar)
        XCTAssertEqual(summary.samples.count, 1)
        XCTAssertEqual(summary.mean, 36.4)
        XCTAssertEqual(summary.latest?.device, "test-a")
        XCTAssertLessThan(summary.domain.lowerBound, 36.4)
        XCTAssertGreaterThan(summary.domain.upperBound, 36.4)
        let empty = TemperatureSummary([], now: date(4), calendar: calendar)
        XCTAssertNil(empty.mean); XCTAssertNil(empty.latest); XCTAssertTrue(empty.days.isEmpty)
    }
    func testCalendarDaysSurviveDaylightSavingAndMidnight() {
        let summary = TemperatureSummary([sample(1, value: 36), sample(2, value: 36.4)], dayCount: 7, now: date(4), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: summary.range.lowerBound), 29)
        XCTAssertEqual(calendar.component(.month, from: summary.range.lowerBound), 10)
        XCTAssertEqual(calendar.dateComponents([.day], from: summary.range.lowerBound, to: summary.range.upperBound).day, 7)
        XCTAssertEqual(summary.range.upperBound.timeIntervalSince(summary.range.lowerBound), 7 * 86400 + 3600)
        XCTAssertEqual(summary.days.count, 2)
    }
    func testSemanticTextAndControlContrastInAllAppearanceChoices() {
        for mode in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: mode)
            let surfaces = [SleepPalette.background, SleepPalette.surface]
            for surface in surfaces {
                for foreground in [SleepPalette.ink, SleepPalette.muted, SleepPalette.rose] {
                    XCTAssertGreaterThanOrEqual(contrast(foreground, surface, traits), 4.5)
                }
                XCTAssertGreaterThanOrEqual(contrast(SleepPalette.controlLine, surface, traits), 3)
            }
            for appearance in AppAppearance.allCases {
                XCTAssertGreaterThanOrEqual(contrast(SleepPalette.onAccent, Color(uiColor: appearance.readableAccent), traits), 4.5)
            }
            for color in GroveColor.allCases {
                XCTAssertGreaterThanOrEqual(contrast(SleepPalette.onAccent, color.tint, traits), 4.5)
            }
        }
    }
    private func contrast(_ first: Color, _ second: Color, _ traits: UITraitCollection) -> Double {
        func luminance(_ color: Color) -> Double {
            let color = UIColor(color).resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let values = [r, g, b].map { component -> Double in
                let v = Double(component)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
