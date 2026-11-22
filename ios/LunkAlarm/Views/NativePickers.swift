import SwiftUI
import UIKit

// UIDatePicker owns the continuous time wheels, including noon/midnight rollover.
// Its native time layout has no headings and uses unpadded hours in 12-hour mode.
struct NativeTimePicker: UIViewRepresentable {
    @Binding var settings: AlarmSettings
    let isLight: Bool

    // The alarm stores a wall-clock time. A fixed calendar prevents a DST
    // transition day from normalizing a valid hour or minute in the editor.
    private static let wheelCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static func wheelDate(hour: Int, minute: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(hour * 3_600 + minute * 60))
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.calendar = Self.wheelCalendar
        picker.timeZone = Self.wheelCalendar.timeZone
        picker.accessibilityIdentifier = "alarmTimePicker"
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }
    func updateUIView(_ picker: UIDatePicker, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let locale = Locale(identifier: settings.use24Hour ? "en_GB" : "en_US")
        if picker.locale != locale {
            picker.locale = locale
            coordinator.displayedSelection = nil
        }
        let style: UIUserInterfaceStyle = isLight ? .light : .dark
        if picker.overrideUserInterfaceStyle != style { picker.overrideUserInterfaceStyle = style }

        // Only push external changes, such as opening a saved alarm. The
        // native wheel can be between rows when SwiftUI refreshes the view.
        let selection = DateComponents(hour: settings.hour, minute: settings.minute)
        guard coordinator.displayedSelection != selection else { return }
        coordinator.displayedSelection = selection
        picker.setDate(Self.wheelDate(hour: settings.hour, minute: settings.minute), animated: false)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeTimePicker
        var displayedSelection: DateComponents?
        init(_ parent: NativeTimePicker) { self.parent = parent }
        @objc func changed(_ picker: UIDatePicker) {
            let parts = NativeTimePicker.wheelCalendar.dateComponents([.hour, .minute], from: picker.date)
            guard let selectedHour = parts.hour, let minute = parts.minute else { return }
            var settings = parent.settings
            let hour = minute == settings.minute
                ? AlarmTimeWheel.resolvedHour(previous: settings.hour, selected: selectedHour, use24Hour: settings.use24Hour)
                : selectedHour
            displayedSelection = DateComponents(hour: hour, minute: minute)
            if hour != selectedHour {
                picker.setDate(NativeTimePicker.wheelDate(hour: hour, minute: minute), animated: false)
            }
            guard settings.hour != hour || settings.minute != minute else { return }
            settings.hour = hour
            settings.minute = minute
            parent.settings = settings
        }
    }
}

// Recenter after every selection. A small repeated window keeps both the
// paired wheels and their VoiceOver/accessibility snapshots responsive.
struct LoopingNumberPicker: UIViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String
    let identifier: String
    let color: UIColor
    private var size: Int { range.count }
    private var middle: Int { size * 10 }
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.accessibilityIdentifier = identifier
        picker.accessibilityLabel = label
        picker.selectRow(middle + value - range.lowerBound, inComponent: 0, animated: false)
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.color != color {
            context.coordinator.color = color
            picker.reloadAllComponents()
        }
        if picker.selectedRow(inComponent: 0) % size + range.lowerBound != value {
            picker.selectRow(middle + value - range.lowerBound, inComponent: 0, animated: false)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 140, height: proposal.height ?? 112)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: LoopingNumberPicker
        var color: UIColor
        init(_ parent: LoopingNumberPicker) { self.parent = parent; color = parent.color }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { parent.size * 21 }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 40 }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { String(row % parent.size + parent.range.lowerBound) }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = String(row % parent.size + parent.range.lowerBound)
            label.accessibilityLabel = label.text
            label.textAlignment = .center
            label.textColor = color
            label.font = .systemFont(ofSize: 28, weight: .light)
            label.isAccessibilityElement = false
            return label
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.value = row % parent.size + parent.range.lowerBound
            // Identical rows surround the new position, so recentering is invisible
            // and neither direction can run into an end after repeated use.
            pickerView.selectRow(parent.middle + row % parent.size, inComponent: 0, animated: false)
        }
    }
}
