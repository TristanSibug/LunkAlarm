import SwiftUI
import UIKit

// UIDatePicker owns the continuous time wheels, including noon/midnight rollover.
// Its native time layout has no headings and uses unpadded hours in 12-hour mode.
struct NativeTimePicker: UIViewRepresentable {
    @Binding var hour: Int
    @Binding var minute: Int
    let use24Hour: Bool
    let isLight: Bool

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.accessibilityIdentifier = "alarmTimePicker"
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }
    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        let locale = Locale(identifier: use24Hour ? "en_GB" : "en_US")
        if picker.locale != locale { picker.locale = locale }
        picker.overrideUserInterfaceStyle = isLight ? .light : .dark
        let selected = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
        if selected.hour != hour || selected.minute != minute {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: picker.date)
            parts.hour = hour; parts.minute = minute; parts.second = 0
            if let date = Calendar.current.date(from: parts) { picker.setDate(date, animated: false) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: NativeTimePicker
        init(_ parent: NativeTimePicker) { self.parent = parent }
        @objc func changed(_ picker: UIDatePicker) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
            let selected = parts.hour ?? 0
            let resolved = AlarmTimeWheel.resolvedHour(previous: parent.hour, selected: selected, use24Hour: parent.use24Hour)
            if resolved != selected {
                var corrected = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: picker.date)
                corrected.hour = resolved
                if let date = Calendar.current.date(from: corrected) { picker.setDate(date, animated: false) }
            }
            parent.hour = resolved
            parent.minute = parts.minute ?? 0
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
